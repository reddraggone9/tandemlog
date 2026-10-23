// Benchmark JSON records intentionally use stdout.
// ignore_for_file: avoid_print
import 'dart:async';

import 'synthetic_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/application/checklist_completion_command.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/platform/foreground_importer.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/unified_manifest.dart' show bytesDigest;
import 'package:tandemlog/text/native_text_engine.dart';

const benchmarkWarmups = 2, benchmarkSamples = 5;
int sampleStart = 0, sampleEnd = benchmarkWarmups + benchmarkSamples;

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

String logicalFood(FoodStore food) =>
    jsonEncode(food.state.containers.map((c) => c.toJson()).toList());

class Audit {
  Audit(this.config, this.family);
  final Map<String, dynamic> config;
  final String family;
  late Directory root, shared;
  late String writer, user;
  late NativeTextEngine engine;
  late LocalProfileDatabase profile;
  late UnifiedHistory history;
  late TaskStore tasks;
  late FoodStore food;
  late LocalSettings settings;
  final original = <String, List<int>>{};
  bool opened = false;
  String? profileOverride;
  Map<String, dynamic> row(String id) =>
      tasks.currentTextRow(id) ??
      (throw StateError('Missing expected task/item'));
  Future<void> initialize() async {
    final output = Directory(config['runRoot'] as String);
    require(
      output.path == output.absolute.path,
      'Absolute disposable output required',
    );
    root = Directory('${output.path}/$family');
    require(!await root.exists(), 'Refuse existing family');
    await root.create(recursive: true);
    shared = await Directory('${root.path}/workspace').create();
    writer = config['fixtureWriter'] as String;
    final source = Directory(config['sealedWorkspacePath'] as String);
    final expected = Map<String, dynamic>.from(config['sealedFiles'] as Map);
    final entries = await source.list(followLinks: false).toList();
    require(
      entries.length == expected.length,
      'Closed source inventory differs',
    );
    for (final entry in entries) {
      require(entry is File, 'Only regular canonical files allowed');
      final file = entry as File;
      final name = file.uri.pathSegments.last;
      require(expected.containsKey(name), 'Unexpected source file');
      require(
        await file.length() < 256 * 1024 * 1024,
        'Bounded canonical file',
      );
      final bytes = await file.readAsBytes();
      require(
        bytesDigest(bytes) == expected[name],
        'Source canonical hash differs',
      );
      original[name] = bytes;
      await File('${shared.path}/$name').writeAsBytes(bytes, flush: true);
    }
    engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    await open(fresh: true, report: family == 'startup');
    user = tasks.rows.firstWhere((r) => r['kind'] == 'user')['id'] as String;
    settings.user = user;
    await settings.save();
  }

  Future<void> open({
    required bool fresh,
    bool report = false,
    int sampleIndex = -1,
  }) async {
    final watch = Stopwatch()..start();
    profile = await LocalProfileDatabase.open(
      profileOverride ?? '${root.path}/profile',
    );
    if (fresh) {
      profile.transaction(
        () => profile.database.execute(
          'INSERT INTO protected_settings VALUES (1,?,?)',
          [
            writer,
            utf8.encode(
              jsonEncode({
                'writer': writer,
                'folder': shared.path,
                'user': null,
                'appearance': 'system',
                'lastSection': 'tasks',
              }),
            ),
          ],
        ),
      );
    }
    final profileUs = watch.elapsedMicroseconds;
    history = await UnifiedHistory.open(
      LocalLogFolder(shared.path),
      profile: profile,
      writer: writer,
      textEngine: engine,
      now: () => DateTime.utc(2026, 10, 22),
    );
    final historyUs = watch.elapsedMicroseconds - profileUs;
    tasks = await TaskStore.openUnified(history);
    final taskUs = watch.elapsedMicroseconds - profileUs - historyUs;
    food = await FoodStore.openUnified(history);
    final foodUs = watch.elapsedMicroseconds - profileUs - historyUs - taskUs;
    settings = LocalSettings(profile.root, profileDatabase: profile);
    await settings.load();
    opened = true;
    if (report) {
      print(
        jsonEncode({
          'index': sampleIndex,
          'warmup': sampleIndex < benchmarkWarmups,
          'measurement': 'broad-startup',
          'family': family,
          'freshProfile': fresh,
          'profileUs': profileUs,
          'historyUs': historyUs,
          'taskAttachUs': taskUs,
          'foodAttachUs': foodUs,
          'totalUs': watch.elapsedMicroseconds,
          'proofUs': history.warmTaskCacheProofMicroseconds,
          'cacheRestoreUs': history.warmTaskCacheRestoreMicroseconds,
          'warmProjectionReuses': tasks.warmProjectionReuses,
          'physicalRecords': history.snapshot.records.length,
          'taskRows': tasks.rows.length,
          'foodContainers': food.state.containers.length,
          'scope': 'standalone AOT storage/application; no UI',
        }),
      );
    }
  }

  Future<T> measure<T>(
    String action,
    int rep,
    Future<T> Function() body, {
    int? expectedDelta,
    bool readOnly = false,
  }) async {
    if (family == 'food-historical') action = 'historical.$action';
    require(
      !history.hasPending && !history.snapshot.pendingEffects,
      'Clean admission required',
    );
    final seq = history.physicalSequence,
        reads = history.readFiles,
        validations = history.semanticValidationRuns;
    final watch = Stopwatch()..start();
    final value = await body();
    final us = watch.elapsedMicroseconds;
    final delta = history.physicalSequence - seq;
    require(
      !history.hasPending && !history.snapshot.pendingEffects,
      'Acknowledgement must clear pending intent',
    );
    if (readOnly) require(delta == 0, 'Read-only operation appended');
    if (expectedDelta != null) {
      require(delta == expectedDelta, 'Unexpected physical action count');
    }
    print(
      jsonEncode({
        'index': rep,
        'warmup': rep < benchmarkWarmups,
        'measurement': 'broad-action',
        'family': family,
        'action': action,
        'rep': rep,
        'microseconds': us,
        'ownPhysicalDelta': delta,
        'readFilesDelta': history.readFiles - reads,
        'semanticValidationsDelta':
            history.semanticValidationRuns - validations,
        'taskRows': tasks.rows.length,
        'foodContainers': food.state.containers.length,
        'scope': 'standalone AOT storage/application; no UI',
      }),
    );
    return value;
  }

  Future<void> assertOriginals() async {
    for (final entry in original.entries) {
      final file = File('${shared.path}/${entry.key}');
      require(await file.exists(), 'Original canonical missing');
      final bytes = await file.readAsBytes();
      if (entry.key == unifiedLogName(writer)) {
        require(bytes.length >= entry.value.length, 'Own prefix truncated');
        require(
          bytesDigest(bytes.sublist(0, entry.value.length)) ==
              bytesDigest(entry.value),
          'Own original prefix changed',
        );
      } else {
        require(
          bytesDigest(bytes) == bytesDigest(entry.value),
          'Nonowner original bytes changed',
        );
      }
    }
  }

  Future<Map<String, String>> inventory() async => {
    for (final f
        in await shared.list().where((e) => e is File).cast<File>().toList())
      f.uri.pathSegments.last: bytesDigest(await f.readAsBytes()),
  };
  Future<void> closeHandles() async {
    if (!opened) return;
    await food.close();
    await tasks.close();
    await history.close();
    await profile.close();
    opened = false;
  }

  Future<void> replayCheck() async {
    await assertOriginals();
    final beforeTasks = jsonEncode(tasks.rows),
        beforeFood = logicalFood(food),
        before = await inventory();
    await closeHandles();
    await open(fresh: false);
    require(jsonEncode(tasks.rows) == beforeTasks, 'Reopen Task state differs');
    require(logicalFood(food) == beforeFood, 'Reopen Food state differs');
    require(
      jsonEncode(await inventory()) == jsonEncode(before),
      'Read-only reopen changed canonical inventory',
    );
    await assertOriginals();
  }

  Future<void> dispose() async {
    await closeHandles();
    engine.dispose();
  }

  Future<List<String>> syntheticTasks(int count) async {
    final values = {
      for (var i = 0; i < count; i++)
        const Uuid().v4(): 'Benchmark synthetic $family $i',
    };
    final result = await tasks.createTasks(values, user);
    require(
      result.succeeded && result.committedIds.length == count,
      'Task fixture capture failed',
    );
    return values.keys.toList();
  }

  Future<void> undo(
    OperationReceipt receipt,
    String action,
    int rep, {
    int count = 1,
  }) async {
    final result = await measure(
      action,
      rep,
      () => tasks.undoOperations([receipt.id]),
      expectedDelta: count,
    );
    require(
      result.error == null && result.remaining.isEmpty,
      'Task Undo did not acknowledge all actions',
    );
  }
}

Future<void> scenario(
  Map<String, dynamic> config,
  String family,
  Future<void> Function(Audit) body,
) async {
  final a = Audit(config, family);
  try {
    await a.initialize();
    await body(a);
    await a.replayCheck();
    print(
      jsonEncode({
        'measurement': 'broad-family-pass',
        'family': family,
        'stateAndReplayAndOriginalPrefixesAccepted': true,
      }),
    );
  } finally {
    await a.dispose();
  }
}

Future<void> textRound(
  Audit a,
  String id,
  String prefix,
  int rep, {
  bool notes = false,
  bool both = false,
  String? expectedProtectedOrder,
}) async {
  final before = Map<String, dynamic>.from(a.row(id));
  TaskTextCapture? capture;
  TaskTextSession? session;
  await a.measure<void>('$prefix.editorOpen', rep, () async {
    capture = await a.tasks.captureTaskText(id);
    session = TaskTextSession(
      capture!,
      registerDraftActor: (f, allocation, actor) =>
          a.tasks.registerTextDraftActor(capture!, f, allocation, actor),
    );
  }, readOnly: true);
  try {
    if (!notes || both) {
      session!.replace('title', 'Benchmark synthetic title $rep');
    }
    if (notes || both) {
      session!.replace('description', 'Benchmark synthetic Notes $rep');
    }
    final desiredTags = List<String>.from(before['tags'] as List? ?? []),
        refs = Map<String, String>.from(before['tagRefs'] as Map? ?? {});
    final snapshot = a.tasks.taskSnapshot;
    final saved = await a.measure(
      '$prefix.save',
      rep,
      () => TextSaveCommand(a.tasks, session!).save(
        fields: {},
        tags: desiredTags,
        observedTagRefs: refs,
        expectedSnapshot: snapshot,
      ),
      expectedDelta: 1,
    );
    require(
      saved.receipt != null && saved.status != TextSaveStatus.unchanged,
      'Native Save has no receipt',
    );
    if (!notes || both) {
      require(
        a.row(id)['title'] == 'Benchmark synthetic title $rep',
        'Saved title differs',
      );
    }
    if (notes || both) {
      require(
        a.row(id)['description'] == 'Benchmark synthetic Notes $rep',
        'Saved Notes differ',
      );
    }
    await a.undo(saved.receipt!, '$prefix.undo', rep);
    final expected = Map<String, dynamic>.from(before);
    if (expectedProtectedOrder != null) {
      expected['order'] = expectedProtectedOrder;
      require(
        a.row(id)['order'] == expectedProtectedOrder,
        'Independent activity must protect exact original successor seed stamp',
      );
    }
    require(
      sameData(a.row(id), expected),
      'Native Undo did not restore exact current row and contracted seed order',
    );
  } finally {
    session?.cancel();
    if (capture != null) a.tasks.releaseTextCapture(capture!);
  }
}

Future<void> explicitTaskText(Audit a) async {
  final id = (await a.syntheticTasks(1)).single;
  require(
    a.history.snapshot.tasks.any(
      (e) => e.entity == id && e.type == 'task.createdWithText',
    ),
    'Explicit editor target must have its own canonical native birth',
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await textRound(a, id, 'explicitTask.title', rep);
    await textRound(a, id, 'explicitTask.notes', rep, notes: true);
    await textRound(a, id, 'explicitTask.titleAndNotes', rep, both: true);
    await editorCancelRound(a, id, 'explicitTask.editorOpenCancel', rep);
  }
}

Future<void> editorCancelRound(
  Audit a,
  String id,
  String action,
  int rep,
) async {
  final seq = a.history.physicalSequence;
  await a.measure(action, rep, () async {
    final capture = await a.tasks.captureTaskText(id);
    final session = TaskTextSession(capture);
    try {
      session.cancel();
    } finally {
      a.tasks.releaseTextCapture(capture);
    }
  }, readOnly: true);
  require(a.history.physicalSequence == seq, 'Cancel wrote canonical bytes');
}

Future<void> taskText(Audit a) async {
  final id =
      a.tasks.rows.firstWhere(
            (r) =>
                r['kind'] == 'task' &&
                r['completed'] != true &&
                r['description'] is String,
          )['id']
          as String;
  require(
    a.history.snapshot.tasks.any(
          (e) => (e.data['successor'] as Map?)?['id'] == id,
        ) &&
        !a.history.snapshot.tasks.any(
          (e) => e.entity == id && e.type == 'task.createdWithText',
        ),
    'Existing task.title metrics must retain their inherited fixture target',
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await textRound(a, id, 'task.title', rep);
    await textRound(a, id, 'task.notes', rep, notes: true);
    await textRound(a, id, 'task.titleAndNotes', rep, both: true);
  }
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await editorCancelRound(a, id, 'task.editorOpenCancel', rep);
  }
}

Future<void> taskCommands(Audit a) async {
  final ids = await a.syntheticTasks(4), id = ids.first;
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final kind in ['schedule', 'tags', 'assignee']) {
      final before = Map<String, dynamic>.from(a.row(id));
      final tags = List<String>.from(before['tags'] as List? ?? []);
      final fields = <String, dynamic>{};
      if (kind == 'schedule') {
        fields['schedule'] = {
          ...Map<String, dynamic>.from(before['schedule'] as Map),
          'dueDate': '2026-11-01',
        };
      }
      if (kind == 'assignee') {
        final users = a.tasks.rows.where((r) => r['kind'] == 'user').toList();
        require(
          users.length > 1,
          'Assignee audit requires two real admitted users',
        );
        fields['assignee'] = users.firstWhere(
          (r) => r['id'] != before['assignee'],
        )['id'];
      }
      if (kind == 'tags') tags.add('synthetic-audit');
      OperationReceipt? receipt;
      final snapshot = a.tasks.taskSnapshot;
      await a.measure(
        'task.metadata.$kind',
        rep,
        () => a.tasks.edit(
          id,
          fields,
          tags: tags,
          observedTagRefs: Map<String, String>.from(
            before['tagRefs'] as Map? ?? {},
          ),
          expectedTaskSnapshot: snapshot,
          onPrepared: (r) => receipt = r,
        ),
        expectedDelta: 1,
      );
      require(receipt != null, 'Metadata missing receipt');
      await a.undo(receipt!, 'task.metadata.$kind.undo', rep);
      require(
        jsonEncode(a.row(id)) == jsonEncode(before),
        'Metadata Undo differs',
      );
    }
    final before = jsonEncode(a.tasks.rows);
    OperationReceipt? deleted;
    await a.measure(
      'task.delete',
      rep,
      () => a.tasks.deleteTask(
        id,
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        onPrepared: (r) => deleted = r,
      ),
      expectedDelta: 1,
    );
    require(
      !a.tasks.rows.any((r) => r['id'] == id),
      'Deleted task still visible',
    );
    await a.undo(deleted!, 'task.restoreViaUndo', rep);
    require(jsonEncode(a.tasks.rows) == before, 'Delete Undo differs');
    OperationReceipt? moved;
    await a.measure(
      'task.reorder',
      rep,
      () => a.tasks.moveBefore(
        ids[3],
        ids[1],
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        canCommit: () => true,
        onPrepared: (r) => moved = r,
      ),
      expectedDelta: 1,
    );
    final order = a.tasks.rows.map((r) => r['id']).toList();
    require(
      order.indexOf(ids[3]) < order.indexOf(ids[1]),
      'Move order differs',
    );
    await a.undo(moved!, 'task.reorder.undo', rep);
    require(jsonEncode(a.tasks.rows) == before, 'Move Undo differs');
    OperationReceipt? completed;
    await a.measure(
      'task.complete.application',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        id,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
        onPrepared: (r) => completed = r,
      ),
      expectedDelta: 1,
    );
    require(completed != null, 'Completion receipt missing');
    require(a.row(id)['completed'] == true, 'Completion not visible');
    await a.measure(
      'task.reopen',
      rep,
      () => a.tasks.reopen(id, a.tasks.activeCompletionIds(id)),
      expectedDelta: 1,
    );
    require(a.row(id)['completed'] == false, 'Reopen not visible');
  }
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final selected = ids.take(3).toList(), before = jsonEncode(a.tasks.rows);
    final receipts = <OperationReceipt>[];
    final result = await a.measure(
      'task.bulkEdit.three',
      rep,
      () => a.tasks.bulkEdit(
        selected,
        BulkTaskEdit(addTags: ['synthetic-bulk']),
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        onPrepared: receipts.add,
      ),
      expectedDelta: 1,
    );
    require(
      result.succeeded &&
          result.committedIds.length == 3 &&
          receipts.length == 3 &&
          a.tasks.confirmedOperations(receipts).length == 3,
      'Bulk edit incomplete',
    );
    require(
      selected.every(
        (id) => (a.row(id)['tags'] as List).contains('synthetic-bulk'),
      ),
      'Bulk tag missing',
    );
    final undone = await a.measure(
      'task.bulkEdit.undo',
      rep,
      () => a.tasks.undoOperations(receipts.map((r) => r.id).toList()),
      expectedDelta: 1,
    );
    require(
      undone.error == null && undone.remaining.isEmpty,
      'Bulk Undo incomplete',
    );
    require(jsonEncode(a.tasks.rows) == before, 'Bulk Undo differs');
    receipts.clear();
    final removed = await a.measure(
      'task.bulkDelete.three',
      rep,
      () => a.tasks.deleteTasks(
        selected,
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        onPrepared: receipts.add,
      ),
      expectedDelta: 1,
    );
    require(
      removed.succeeded &&
          removed.committedIds.length == 3 &&
          receipts.length == 3 &&
          a.tasks.confirmedOperations(receipts).length == 3 &&
          !a.tasks.rows.any((r) => selected.contains(r['id'])),
      'Bulk delete incomplete',
    );
    await a.measure(
      'task.bulkDelete.undo',
      rep,
      () => a.tasks.undoOperations(receipts.map((r) => r.id).toList()),
      expectedDelta: 1,
    );
    require(jsonEncode(a.tasks.rows) == before, 'Bulk delete Undo differs');
    receipts.clear();
    final moved = await a.measure(
      'task.bulkReorder.three',
      rep,
      () => a.tasks.moveBlockBefore(
        selected,
        null,
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        canCommit: () => true,
        onPrepared: receipts.add,
      ),
      expectedDelta: 1,
    );
    require(
      moved.succeeded &&
          moved.committedIds.length == 3 &&
          receipts.length == 3 &&
          a.tasks.confirmedOperations(receipts).length == 3,
      'Bulk move incomplete',
    );
    await a.measure(
      'task.bulkReorder.undo',
      rep,
      () => a.tasks.undoOperations(receipts.map((r) => r.id).toList()),
      expectedDelta: 1,
    );
    require(jsonEncode(a.tasks.rows) == before, 'Bulk move Undo differs');
  }
}

Future<void> checklist(Audit a) async {
  final parent = (await a.syntheticTasks(1)).single;
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final id = const Uuid().v4();
    await a.measure(
      'checklist.add',
      rep,
      () => a.tasks.addChecklistItem(
        parent,
        'Benchmark item $rep',
        notes: 'Benchmark Notes',
        id: id,
      ),
      expectedDelta: 1,
    );
    require(
      a.tasks.checklistItems(parent).any((r) => r['id'] == id),
      'Checklist add missing',
    );
    await textRound(a, id, 'checklist.titleAndNotes', rep, both: true);
    final before = jsonEncode(a.tasks.checklistItems(parent));
    OperationReceipt? checked;
    await a.measure(
      'checklist.complete',
      rep,
      () => a.tasks.setChecklistCompleted(
        id,
        true,
        onPrepared: (r) => checked = r,
      ),
      expectedDelta: 1,
    );
    require(a.row(id)['completed'] == true, 'Checklist completion missing');
    OperationReceipt? unchecked;
    await a.measure(
      'checklist.uncomplete',
      rep,
      () => a.tasks.setChecklistCompleted(
        id,
        false,
        onPrepared: (r) => unchecked = r,
      ),
      expectedDelta: 1,
    );
    require(a.row(id)['completed'] == false, 'Direct uncheck missing');
    await a.undo(unchecked!, 'checklist.recompleteViaUndo', rep);
    require(
      a.row(id)['completed'] == true,
      'Uncheck Undo did not restore completion',
    );
    await a.undo(checked!, 'checklist.uncompleteViaUndo', rep);
    require(
      jsonEncode(a.tasks.checklistItems(parent)) == before,
      'Checklist completion Undo differs',
    );
    final anchor = const Uuid().v4();
    await a.tasks.addChecklistItem(parent, 'Benchmark anchor', id: anchor);
    OperationReceipt? moved;
    final orderBefore = jsonEncode(a.tasks.checklistItems(parent));
    await a.measure(
      'checklist.reorder',
      rep,
      () => a.tasks.moveChecklistItem(anchor, id, onPrepared: (r) => moved = r),
      expectedDelta: 1,
    );
    require(
      a.tasks.checklistItems(parent).indexWhere((r) => r['id'] == anchor) <
          a.tasks.checklistItems(parent).indexWhere((r) => r['id'] == id),
      'Checklist order differs',
    );
    await a.undo(moved!, 'checklist.reorder.undo', rep);
    require(
      jsonEncode(a.tasks.checklistItems(parent)) == orderBefore,
      'Checklist order Undo differs',
    );
    OperationReceipt? removed;
    await a.measure(
      'checklist.delete',
      rep,
      () => a.tasks.deleteChecklistItem(id, onPrepared: (r) => removed = r),
      expectedDelta: 1,
    );
    require(
      !a.tasks.checklistItems(parent).any((r) => r['id'] == id),
      'Deleted item still visible',
    );
    await a.undo(removed!, 'checklist.restoreViaUndo', rep);
    require(
      jsonEncode(a.tasks.checklistItems(parent)) == orderBefore,
      'Checklist delete Undo differs',
    );
    final seq = a.history.physicalSequence;
    final declined = await a.measure(
      'task.complete.checklistDecline',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        parent,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => false,
      ),
      readOnly: true,
    );
    require(
      declined == null && a.history.physicalSequence == seq,
      'Declined completion wrote',
    );
    await a.measure(
      'task.complete.checklistConfirm',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        parent,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
      ),
      expectedDelta: 1,
    );
    require(a.row(parent)['completed'] == true, 'Confirmed completion missing');
    await a.measure(
      'task.reopen.withChecklist',
      rep,
      () => a.tasks.reopen(parent, a.tasks.activeCompletionIds(parent)),
      expectedDelta: 1,
    );
  }
}

Future<void> foodCommands(Audit a, {bool historical = false}) async {
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final count in [1, 3]) {
      final before = logicalFood(a.food),
          oldIds = a.food.state.containers.map((c) => c.id).toSet();
      await a.measure(
        'food.add.$count',
        rep,
        () => a.food.add(
          FoodDetails(
            name: 'Benchmark audit food $rep/$count',
            expiry: '2026-11-10',
            brand: 'Benchmark brand',
            location: 'Benchmark location',
          ),
          count,
        ),
        expectedDelta: 1,
      );
      final adds = List<FoodRecord>.from(a.food.lastPreparedRecords),
          newIds = a.food.state.containers
              .where((c) => !oldIds.contains(c.id))
              .map((c) => c.id)
              .toList();
      require(newIds.length == count, 'Food add count differs');
      require(adds.every(a.food.isAdmitted), 'Food add unacknowledged');
      await a.measure(
        'food.add.$count.undo',
        rep,
        () => a.food.undoOperations(adds),
        expectedDelta: 1,
      );
      require(logicalFood(a.food) == before, 'Food add Undo differs');
    }
  }
  late List<String> synthetic;
  if (historical) {
    synthetic = a.food.state.active.take(3).map((c) => c.id).toList();
  } else {
    await a.food.add(
      const FoodDetails(
        name: 'Benchmark persistent audit food',
        expiry: '2026-11-10',
        brand: 'Benchmark brand',
        location: 'Benchmark location',
      ),
      3,
    );
    synthetic = a.food.lastPreparedRecords
        .expand((r) => r.operation.targets)
        .toList();
  }
  require(synthetic.length == 3, 'Food fixture missing');
  FoodContainer item() =>
      a.food.state.containers.singleWhere((c) => c.id == synthetic.first);
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final count in [1, 3]) {
      final before = logicalFood(a.food);
      await a.measure(
        'food.details.$count',
        rep,
        () => a.food.changeDetails(
          synthetic.take(count).toList(),
          FoodDetails(
            name: 'Benchmark renamed food $rep',
            brand: 'Benchmark new brand',
            location: 'Benchmark new location',
          ),
          ['name', 'brand', 'location'],
        ),
        expectedDelta: 1,
      );
      final edits = List<FoodRecord>.from(a.food.lastPreparedRecords);
      require(
        synthetic
            .take(count)
            .every(
              (id) =>
                  a.food.state.containers
                      .singleWhere((c) => c.id == id)
                      .details
                      .name ==
                  'Benchmark renamed food $rep',
            ),
        'Food details differ',
      );
      await a.measure(
        'food.details.$count.undo',
        rep,
        () => a.food.undoOperations(edits),
        expectedDelta: 1,
      );
      require(logicalFood(a.food) == before, 'Food details Undo differs');
    }
    final before = logicalFood(a.food);
    await a.measure(
      'food.contents.APIonly',
      rep,
      () => a.food.changeContents(item(), const Contents.fraction(1, 2)),
      expectedDelta: 1,
    );
    final edits = List<FoodRecord>.from(a.food.lastPreparedRecords);
    require(
      item().contents.toJson()['numerator'] == 1 &&
          item().contents.toJson()['denominator'] == 2,
      'Contents differs',
    );
    await a.measure(
      'food.contents.APIonly.undo',
      rep,
      () => a.food.undoOperations(edits),
      expectedDelta: 1,
    );
    require(logicalFood(a.food) == before, 'Contents Undo differs');
    for (final count in [1, 3]) {
      final ids = synthetic.take(count).toList();
      final removed = await a.measure(
        'food.delete.$count',
        rep,
        () => a.food.remove(ids),
        expectedDelta: 1,
      );
      require(
        ids.every((id) => a.food.state.deleted.any((c) => c.id == id)),
        'Food deletion missing',
      );
      await a.measure(
        'food.delete.$count.undo',
        rep,
        () => a.food.undoOperations(removed),
        expectedDelta: 1,
      );
      require(logicalFood(a.food) == before, 'Food remove Undo differs');
      final second = await a.food.remove(ids);
      final observed = a.food.state.deleted
          .where((c) => ids.contains(c.id))
          .toList();
      await a.measure(
        'food.restore.$count',
        rep,
        () => a.food.restore(observed),
        expectedDelta: 1,
      );
      final restored = List<FoodRecord>.from(a.food.lastPreparedRecords);
      require(
        ids.every((id) => a.food.state.active.any((c) => c.id == id)),
        'Food restore missing',
      );
      await a.measure(
        'food.restore.$count.undo',
        rep,
        () => a.food.undoOperations(restored),
        expectedDelta: 1,
      );
      require(
        ids.every((id) => a.food.state.deleted.any((c) => c.id == id)),
        'Restore Undo missing',
      );
      await a.food.undoOperations(second);
      require(logicalFood(a.food) == before, 'Restore sequence differs');
    }
  }
}

Future<void> readModels(Audit a) async {
  final viewTime = ViewTime(
    instant: DateTime.utc(2026, 10, 22, 12),
    localZoneId: 'UTC',
    localOffset: Duration.zero,
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final rows = await a.measure(
      'task.rows.queryDecode',
      rep,
      () async => a.tasks.rows,
      readOnly: true,
    );
    require(rows.isNotEmpty, 'Rows missing');
    final snapshots = await a.measure(
      'task.snapshot.serializeAll',
      rep,
      () async => a.tasks.taskSnapshot,
      readOnly: true,
    );
    require((jsonDecode(snapshots) as List).isNotEmpty, 'Task snapshot empty');
    for (final mode in [
      'openCompleted',
      'upcoming',
      'assignee',
      'tags',
      'search',
    ]) {
      final result = await a.measure(
        'task.view.$mode',
        rep,
        () async => projectTaskView(
          rows,
          viewTime,
          includeUpcoming: mode == 'upcoming',
          assignee: mode == 'assignee' ? a.user : null,
          tags: mode == 'tags' ? {'synthetic-unmatched-tag'} : null,
          searchQuery: mode == 'search' ? 'synthetic-unmatched-query' : null,
        ),
        readOnly: true,
      );
      if (mode == 'search') {
        require(result.value.searchActive, 'Search state missing');
      }
      if (mode == 'tags') {
        require(
          result.value.open.isEmpty && result.value.completed.isEmpty,
          'Tag filter differs',
        );
      }
    }
    for (final mode in FoodView.values) {
      final groups = await a.measure(
        'food.view.${mode.name}',
        rep,
        () async => a.food.state.view(mode),
        readOnly: true,
      );
      require(groups.every((g) => g.containers.isNotEmpty), 'Empty Food group');
    }
    for (final filter in ['search', 'brand', 'location', 'retention']) {
      final groups = await a.measure(
        'food.filter.$filter',
        rep,
        () async => a.food.state.view(
          filter == 'retention' ? FoodView.retained : FoodView.inventory,
          search: filter == 'search' ? 'synthetic-unmatched-query' : '',
          brands: filter == 'brand' ? {'synthetic-unmatched-brand'} : {},
          locations: filter == 'location'
              ? {'synthetic-unmatched-location'}
              : {},
          reasons: filter == 'retention' ? {'synthetic-unmatched-reason'} : {},
        ),
        readOnly: true,
      );
      require(groups.isEmpty, 'Expected unmatched Food filter');
    }
    await a.measure(
      'refresh.tasks.unchanged',
      rep,
      () => a.tasks.refresh(),
      readOnly: true,
    );
    await a.measure(
      'refresh.food.unchanged',
      rep,
      () => a.food.refresh(),
      readOnly: true,
    );
  }
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await a.measure(
      'section.preference.food',
      rep,
      () => a.settings.saveSection(AppSection.food),
      readOnly: true,
    );
    require(
      a.settings.lastSection == AppSection.food,
      'Section preference missing',
    );
    await a.measure(
      'section.preference.tasks',
      rep,
      () => a.settings.saveSection(AppSection.tasks),
      readOnly: true,
    );
    require(
      a.settings.lastSection == AppSection.tasks,
      'Section preference missing',
    );
  }
  Completer<void>? done = Completer<void>();
  final importer = ForegroundImporter(
    reconcile: () async {
      await a.tasks.refresh();
      done?.complete();
    },
    fallback: const Duration(days: 1),
  );
  try {
    importer.start();
    await done.future;
    for (var rep = sampleStart; rep < sampleEnd; rep++) {
      done = Completer<void>();
      await a.measure('foreground.request.reconcileImmediate', rep, () async {
        importer.request();
        await done!.future;
      }, readOnly: true);
    }
  } finally {
    importer.dispose();
  }
}

Future<void> startup(Audit a) async {
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final before = await a.inventory();
    await a.closeHandles();
    await a.open(fresh: false, report: true, sampleIndex: rep);
    require(a.tasks.warmProjectionReuses == 1, 'Expected clean-cache reuse');
    require(
      jsonEncode(await a.inventory()) == jsonEncode(before),
      'Startup wrote canonical bytes',
    );
  }
}

Future<void> coldStartup(Audit a) async {
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final before = await a.inventory();
    await a.closeHandles();
    a.profileOverride = '${a.root.path}/cold-$rep';
    await a.open(fresh: true, report: true, sampleIndex: rep);
    require(
      a.tasks.warmProjectionReuses == 0,
      'Cold profile reused existing cache',
    );
    require(
      sameData(await a.inventory(), before),
      'Cold startup changed canonical fixture',
    );
  }
}

Future<void> main(List<String> args) async {
  require(
    args.length == 4,
    'Usage: benchmark generate OUTPUT_ROOT NATIVE_LIBRARY BASE_RECORDS | benchmark run OUTPUT_ROOT NATIVE_LIBRARY FIXTURE_MANIFEST',
  );
  final root = Directory(args[1]);
  require(
    root.absolute.path == root.path && !await root.exists(),
    'Refuse nonabsolute/existing benchmark output',
  );
  require(
    Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == args[2],
    'Native library binding differs',
  );
  if (args[0] == 'generate') {
    final spec = parseSyntheticFixtureSpec(args[3]);
    final count = spec.baseRecords;
    final fixture = await buildSyntheticFixture(
      root,
      count,
      nativeLibrary: args[2],
      growthKind: spec.growthKind,
    );
    print(
      jsonEncode({
        'measurement': 'fixture-generated',
        'fixtureManifest': '${root.path}/fixture.json',
        'baseHistoricalRecords': count,
        'actualPhysicalRecords': fixture['actualPhysicalRecords'],
      }),
    );
    return;
  }
  require(args[0] == 'run', 'Unknown benchmark mode');
  final fixture = Map<String, dynamic>.from(
    jsonDecode(await File(args[3]).readAsString()) as Map,
  );
  require(
    fixture['schemaVersion'] == fixtureSchemaVersion &&
        fixture['syntheticOnly'] == true,
    'Unknown/non-synthetic fixture contract',
  );
  final count = fixture['baseHistoricalRecords'];
  require([60, 1320, 2640].contains(count), 'Unknown versioned history size');
  await root.create(recursive: true);
  final config = <String, dynamic>{
    'authorizedRuntimeReady': true,
    'runRoot': '${root.path}/workloads',
    'sealedWorkspacePath': fixture['workspace'],
    'sealedFiles': fixture['files'],
    'fixtureWriter': fixture['writer'],
  };
  final all = <String, Future<void> Function(Audit)>{
    'task-text': taskText,
    'explicit-task-text': explicitTaskText,
    'task-commands': taskCommands,
    'checklist': checklist,
    'food': foodCommands,
    'food-historical': (a) => foodCommands(a, historical: true),
    'read-models': readModels,
    'startup': startup,
    'cold-startup': coldStartup,
    'capture': taskCapture,
    'matched-readmodels': matchedReadModels,
    'peer': changedPeer,
    'derived-recurring': derivedRecurring,
  };
  for (final entry in all.entries) {
    if (entry.key == 'derived-recurring') {
      for (var rep = 0; rep < benchmarkWarmups + benchmarkSamples; rep++) {
        sampleStart = rep;
        sampleEnd = rep + 1;
        await scenario(
          {...config, 'runRoot': '${root.path}/equivalent-recurring-$rep'},
          entry.key,
          entry.value,
        );
      }
      sampleStart = 0;
      sampleEnd = benchmarkWarmups + benchmarkSamples;
    } else {
      await scenario(config, entry.key, entry.value);
    }
  }
  print(
    jsonEncode({
      'measurement': 'broad-all-pass',
      'families': all.length,
      'fixtureSchemaVersion': fixtureSchemaVersion,
      'baseHistoricalRecords': count,
      'actualPhysicalRecords': fixture['actualPhysicalRecords'],
      'warmups': benchmarkWarmups,
      'samples': benchmarkSamples,
      'scope':
          'AOT storage/application/readmodel; actual UI input/paint measured separately',
    }),
  );
}

bool sameData(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameData(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => sameData(a[i], b[i])).every((v) => v);
  }
  return a == b;
}

Future<void> taskCapture(Audit a) async {
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final count in [1, 3]) {
      final values = {
        for (var i = 0; i < count; i++)
          const Uuid().v4(): 'Benchmark capture audit $rep $i',
      };
      final seq = a.history.physicalSequence;
      final result = await a.measure(
        'task.capture.$count',
        rep,
        () => a.tasks.createTasks(values, a.user),
        expectedDelta: 1,
      );
      require(
        result.succeeded &&
            result.createdIds.length == count &&
            result.committedIds.length == count,
        'Capture acknowledgement differs',
      );
      require(
        values.entries.every((e) => a.row(e.key)['title'] == e.value),
        'Capture title/identity differs',
      );
      final record = a.history.snapshot.records.singleWhere(
        (r) => r.writer == a.writer && r.sequence == seq + 1,
      );
      require(
        record.effects.length == 2 * count,
        'Capture must retain creation and placement effects',
      );
    }
  }
}

Future<void> matchedReadModels(Audit a) async {
  final id = (await a.syntheticTasks(1)).single;
  await a.tasks.edit(
    id,
    {},
    tags: ['synthetic-matched-tag'],
    observedTagRefs: {},
  );
  await a.food.add(
    const FoodDetails(
      name: 'Benchmark matched stock',
      brand: 'Benchmark matched brand',
      location: 'Benchmark matched location',
      expiry: '2026-11-10',
    ),
    3,
  );
  await a.food.add(
    const FoodDetails(
      name: 'Benchmark matched retained',
      retention: 'Benchmark matched reason',
    ),
    2,
  );
  final time = ViewTime(
    instant: DateTime.utc(2026, 10, 22, 12),
    localZoneId: 'UTC',
    localOffset: Duration.zero,
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final kind in ['search', 'tags', 'assignee']) {
      final result = await a.measure(
        'task.matched.$kind',
        rep,
        () async => projectTaskView(
          a.tasks.rows,
          time,
          includeUpcoming: true,
          searchQuery: kind == 'search' ? 'Benchmark synthetic' : null,
          tags: kind == 'tags' ? {'synthetic-matched-tag'} : null,
          assignee: kind == 'assignee' ? a.user : null,
        ),
        readOnly: true,
      );
      require(
        [
          ...result.value.open,
          ...result.value.completed,
        ].any((e) => e.task['id'] == id),
        'Matched Task missing',
      );
    }
    for (final kind in ['search', 'brand', 'location', 'retention']) {
      final result = await a.measure(
        'food.matched.$kind',
        rep,
        () async => a.food.state.view(
          kind == 'retention' ? FoodView.retained : FoodView.inventory,
          search: kind == 'search' ? 'Benchmark matched' : '',
          brands: kind == 'brand' ? {'Benchmark matched brand'} : {},
          locations: kind == 'location' ? {'Benchmark matched location'} : {},
          reasons: kind == 'retention' ? {'Benchmark matched reason'} : {},
        ),
        readOnly: true,
      );
      require(result.isNotEmpty, 'Matched Food group missing');
    }
  }
}

Future<void> changedPeer(Audit a) async {
  final remote = await Directory('${a.root.path}/peer-workspace').create();
  for (final f
      in await a.shared.list().where((e) => e is File).cast<File>().toList()) {
    await File(
      '${remote.path}/${f.uri.pathSegments.last}',
    ).writeAsBytes(await f.readAsBytes(), flush: true);
  }
  TaskStore? peer;
  FoodStore? peerFood;
  try {
    peer = await TaskStore.open(
      LocalLogFolder(remote.path),
      '${a.root.path}/peer-profile',
      textEngine: a.engine,
    );
    peerFood = await FoodStore.openUnified(peer.unified!);
    final name = unifiedLogName(peer.writer);
    require(!a.original.containsKey(name), 'Peer writer must be fresh');
    Future<void> deliver() async {
      final bytes = await File('${remote.path}/$name').readAsBytes();
      final target = File('${a.shared.path}/$name');
      if (await target.exists()) {
        final old = await target.readAsBytes();
        require(
          bytes.length >= old.length &&
              bytesDigest(bytes.sublist(0, old.length)) == bytesDigest(old),
          'App-produced peer prefix differs',
        );
        final out = await target.open(mode: FileMode.append);
        try {
          await out.writeFrom(bytes, old.length);
          await out.flush();
        } finally {
          await out.close();
        }
      } else {
        await target.create(exclusive: true);
        await target.writeAsBytes(bytes, flush: true);
      }
    }

    for (var rep = sampleStart; rep < sampleEnd; rep++) {
      final id = const Uuid().v4();
      final capture = await peer.createTasks({
        id: 'Benchmark peer incoming $rep',
      }, a.user);
      require(capture.succeeded, 'Peer capture failed');
      await a.settings.saveSection(AppSection.food);
      final beforeFood = logicalFood(a.food);
      await deliver();
      await a.measure(
        'sync.peerTask.whileFood.storageAdmission',
        rep,
        () => a.food.refresh(),
        readOnly: true,
      );
      require(
        a.row(id)['title'] == 'Benchmark peer incoming $rep',
        'Incoming peer Task missing',
      );
      require(logicalFood(a.food) == beforeFood, 'Task-only peer changed Food');
      final beforeIds = a.food.state.containers.map((c) => c.id).toSet();
      await peerFood.add(FoodDetails(name: 'Benchmark peer food $rep'), 1);
      await a.settings.saveSection(AppSection.tasks);
      await deliver();
      await a.measure(
        'sync.peerFood.whileTasks.storageAdmission',
        rep,
        () => a.tasks.refresh(),
        readOnly: true,
      );
      require(
        a.food.state.containers
                .where((c) => !beforeIds.contains(c.id))
                .length ==
            1,
        'Incoming peer Food missing',
      );
      final head = a.profile.database.select(
        'SELECT sequence FROM protected_app_heads WHERE space=? AND writer=?',
        [a.history.manifest.space, peer.writer],
      );
      require(
        head.length == 1 &&
            head.single['sequence'] == peer.unified!.physicalSequence,
        'Protected peer head differs',
      );
    }
  } finally {
    await peerFood?.close();
    await peer?.close();
  }
}

Future<void> derivedRecurring(Audit a) async {
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final parent = (await a.syntheticTasks(1)).single;
    await a.tasks.edit(
      parent,
      {
        'schedule': {'dueDate': '2026-10-22', 'recurrence': 'every day'},
      },
      tags: [],
      observedTagRefs: {},
    );
    final first = const Uuid().v4(), second = const Uuid().v4();
    await a.tasks.addChecklistItem(
      parent,
      'Benchmark recurring first',
      notes: 'Benchmark recurring Notes',
      id: first,
    );
    await a.tasks.addChecklistItem(
      parent,
      'Benchmark recurring second',
      id: second,
    );
    await a.tasks.setChecklistCompleted(first, true);
    await a.tasks.moveChecklistItem(second, first);
    OperationReceipt? original;
    final completion = await a.measure(
      'recurring.complete.nativeChecklist',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        parent,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
        onPrepared: (r) => original = r,
      ),
      expectedDelta: 1,
    );
    require(
      completion?.type == 'task.completedWithChecklist',
      'Wrong recurring completion descriptor',
    );
    final child = const Uuid().v5(parent, 'successor'),
        copied = const Uuid().v5(child, 'checklist:$first');
    final items = a.tasks.checklistItems(child);
    require(
      items.length == 2 && items.every((r) => r['completed'] == false),
      'Copied items not fresh unchecked',
    );
    require(
      items.last['id'] == copied &&
          items.last['description'] == 'Benchmark recurring Notes',
      'Copied order/Notes differ',
    );
    final undone = await a.measure(
      'recurring.complete.undoUntouched',
      rep,
      () => a.tasks.undoOperations([original!.id]),
      expectedDelta: 1,
    );
    require(
      undone.error == null &&
          undone.remaining.isEmpty &&
          a.row(parent)['completed'] == false,
      'Recurring Undo failed',
    );
    require(
      !a.tasks.rows.any((r) => r['id'] == child),
      'Untouched successor must be suppressed',
    );
    OperationReceipt? current;
    await a.measure(
      'recurring.recomplete.nativeChecklist',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        parent,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
        onPrepared: (r) => current = r,
      ),
      expectedDelta: 1,
    );
    require(
      a.tasks.checklistItems(child).length == 2,
      'Recompletion lost copied items',
    );
    // Canonical Save+Undo is independent activity: preserve earliest original seed, not later unprotected re-completion.
    final originalOrder =
        '${completion!.clock.toString().padLeft(19, '0')}:${completion.writer}';
    await textRound(
      a,
      child,
      'derivedSuccessor.titleAndNotes',
      rep,
      both: true,
      expectedProtectedOrder: originalOrder,
    );
    await textRound(
      a,
      copied,
      'copiedChecklist.titleAndNotes',
      rep,
      both: true,
    );
    final beforeChild = Map<String, dynamic>.from(a.row(child));
    OperationReceipt? metadata;
    await a.measure(
      'derivedSuccessor.metadata.tags',
      rep,
      () => a.tasks.edit(
        child,
        {},
        tags: [
          ...List<String>.from(beforeChild['tags'] as List? ?? []),
          'synthetic-derived-tag',
        ],
        observedTagRefs: Map<String, String>.from(
          beforeChild['tagRefs'] as Map? ?? {},
        ),
        expectedTaskSnapshot: a.tasks.taskSnapshot,
        onPrepared: (r) => metadata = r,
      ),
      expectedDelta: 1,
    );
    require(
      (a.row(child)['tags'] as List).contains('synthetic-derived-tag'),
      'Derived metadata missing',
    );
    await a.undo(metadata!, 'derivedSuccessor.metadata.undo', rep);
    require(
      sameData(a.row(child), beforeChild),
      'Derived metadata Undo differs',
    );
    final beforeCopied = Map<String, dynamic>.from(a.row(copied));
    OperationReceipt? checked;
    await a.measure(
      'copiedChecklist.metadata.complete',
      rep,
      () => a.tasks.setChecklistCompleted(
        copied,
        true,
        onPrepared: (r) => checked = r,
      ),
      expectedDelta: 1,
    );
    require(a.row(copied)['completed'] == true, 'Copied completion missing');
    await a.undo(checked!, 'copiedChecklist.metadata.undo', rep);
    require(
      sameData(a.row(copied), beforeCopied),
      'Copied metadata Undo differs',
    );
    OperationReceipt? childDone;
    await a.measure(
      'derivedSuccessor.complete.nativeChecklist',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        child,
        completionInstant: DateTime.utc(2026, 10, 23, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
        onPrepared: (r) => childDone = r,
      ),
      expectedDelta: 1,
    );
    require(a.row(child)['completed'] == true, 'Derived completion missing');
    final grandchild = const Uuid().v5(child, 'successor');
    require(
      a.tasks.checklistItems(grandchild).length == 2,
      'Second generation checklist missing',
    );
    await a.undo(childDone!, 'derivedSuccessor.complete.undo', rep);
    require(
      a.row(child)['completed'] == false,
      'Derived completion Undo failed',
    );
    await a.measure(
      'derivedSuccessor.recomplete.nativeChecklist',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        child,
        completionInstant: DateTime.utc(2026, 10, 23, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
      ),
      expectedDelta: 1,
    );
    final retainedChild = jsonEncode(a.row(child)),
        retainedItems = jsonEncode(a.tasks.checklistItems(child));
    final retained = await a.measure(
      'recurring.complete.undoProtectedSuccessor',
      rep,
      () => a.tasks.undoOperations([current!.id]),
      expectedDelta: 1,
    );
    require(
      retained.error == null &&
          retained.remaining.isEmpty &&
          retained.retainedSuccessorCount == 1,
      'Independent successor must be retained',
    );
    require(
      jsonEncode(a.row(child)) == retainedChild &&
          jsonEncode(a.tasks.checklistItems(child)) == retainedItems,
      'Protected child changed on parent Undo',
    );
    final again = await a.measure(
      'recurring.recomplete.keepProtectedSuccessor',
      rep,
      () => ChecklistCompletionCommand(a.tasks).complete(
        parent,
        completionInstant: DateTime.utc(2026, 10, 22, 12),
        localZoneId: 'UTC',
        confirmUnfinished: (_) async => true,
      ),
      expectedDelta: 1,
    );
    require(
      again?.type == 'task.completedKeepingSuccessor',
      'Recompletion should keep protected successor',
    );
    require(
      jsonEncode(a.row(child)) == retainedChild,
      'Protected successor overwritten by recompletion',
    );
  }
}
