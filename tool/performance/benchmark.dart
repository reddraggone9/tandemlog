// Benchmark JSON records intentionally use stdout.
// ignore_for_file: avoid_print
import 'dart:async';

import 'synthetic_fixture.dart';
import 'operation_diagnostics.dart';
import 'cost_trace.dart';
import 'package:tandemlog/storage/local_durability.dart';

import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:tandemlog/agent/agent_workspace.dart' show agentTextEngine;
import 'package:tandemlog/agent/cli.dart' show runCli;
import 'package:tandemlog/application/food_undo_history.dart';
import 'package:tandemlog/application/workspace_session.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/application/checklist_completion_command.dart';
import 'package:tandemlog/domain/event.dart' show LogEvent;
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/event_chain.dart' show canonicalDataJson;
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_purchase_import.dart';
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

final durabilityDiagnostics = BenchmarkDurabilityDiagnostics(
  LocalDurability.shared,
);

const benchmarkWarmups = 2, benchmarkSamples = 5;
int sampleStart = 0, sampleEnd = benchmarkWarmups + benchmarkSamples;

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

String logicalFood(FoodStore food) =>
    jsonEncode(food.state.containers.map((c) => c.toJson()).toList());

// Include catalog-only changes and voided purchases, not just container rows.
// Container rows keep plain JSON: ordering keys such as deletedOrder may exceed
// the canonical encoder's exact-integer range.
String productFoodState(FoodStore food) {
  final catalog = food.state.catalog;
  final products = canonicalDataJson({
    'products': catalog.products,
    'aliases': catalog.aliases,
    'purchases': {
      for (final p in catalog.purchases.values)
        p.id: {...p.toJson(), 'voided': p.voided},
    },
  });
  return '${logicalFood(food)}\n$products';
}

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
  ProbeCostTrace? costTrace;
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
    if (config['diagnosticCosts'] == true) {
      final clock = Stopwatch()..start();
      costTrace = ProbeCostTrace(
        () => clock.elapsedMicroseconds,
        profileHookAttachment: 'after SQLite profile open, before history open',
      );
      await Directory('${root.path}/cost-traces').create();
    }
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
    if (costTrace case final trace?) {
      engine.diagnosticObserver = ProbeProfileDiagnostics(trace);
    }
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
    if (costTrace case final trace?) {
      profile.diagnosticObserver = ProbeProfileDiagnostics(trace);
    }
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
      costTrace == null
          ? LocalLogFolder(shared.path, durability: durabilityDiagnostics)
          : ProbeLocalLogFolder(
              shared.path,
              costTrace!,
              durability: durabilityDiagnostics,
            ),
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
    if (family.startsWith('converted-')) action = 'converted.$action';
    if (family == 'food-cardinality500') action = 'cardinality500.$action';
    require(
      !history.hasPending && !history.snapshot.pendingEffects,
      'Clean admission required',
    );
    final seq = history.physicalSequence,
        reads = history.readFiles,
        validations = history.semanticValidationRuns;
    final resourcesBefore = benchmarkResourceCounters();
    final appendCallsBefore = durabilityDiagnostics.appendCalls;
    final appendUsBefore = durabilityDiagnostics.appendMicroseconds;
    final snapshotDecodesBefore = tasks.taskSnapshotRowsDecoded;
    final semanticSortsBefore = history.semanticTaskSortRuns;
    final trace = costTrace;
    trace?.reset();
    final traceStart = trace?.now();
    final watch = Stopwatch()..start();
    final value = await body();
    final traceEnd = trace?.now();
    final us = trace == null
        ? watch.elapsedMicroseconds
        : traceEnd! - traceStart!;
    final resourcesAfter = benchmarkResourceCounters();
    Map<String, Object?>? costs;
    if (trace != null) {
      trace.action(action, traceStart!, traceEnd!);
      costs = trace.partition(traceStart, traceEnd);
      final filename =
          '${action.replaceAll(RegExp(r"[^a-zA-Z0-9_.-]"), "_")}-$rep.json';
      final file = File('${root.path}/cost-traces/$filename');
      await file.writeAsString(
        jsonEncode({
          'action': action,
          'family': family,
          'sample': rep,
          'profileDiagnosticCallbackFailures':
              profile.diagnosticCallbackFailures,
          'partition': costs,
          ...trace.report(),
        }),
      );
      costs['traceFile'] = file.path;
      require(
        profile.diagnosticCallbackFailures == 0 &&
            engine.diagnosticCallbackFailures == 0 &&
            trace.droppedSpans == 0,
        'Incomplete diagnostic attribution; results and trace retained',
      );
      require(
        costs['reconciled'] == true,
        'Diagnostic wall interval did not reconcile',
      );
    }
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
        'costs': ?costs,
        'diagnostics': {
          'semanticTaskSortsDelta':
              history.semanticTaskSortRuns - semanticSortsBefore,
          'taskSnapshotRowsDecodedDelta':
              tasks.taskSnapshotRowsDecoded - snapshotDecodesBefore,
          'taskSnapshotRetainedBytesAfter': tasks.cachedTaskSnapshotBytes,
          'appendCalls': durabilityDiagnostics.appendCalls - appendCallsBefore,
          'appendMicroseconds':
              durabilityDiagnostics.appendMicroseconds - appendUsBefore,
          'resourceInterval': 'bracketed; probe overhead outside action timer',
          'resourcesAvailable':
              resourcesBefore.isNotEmpty &&
              resourcesBefore.keys.every(resourcesAfter.containsKey),
          'resourceDeltas': {
            for (final entry in resourcesBefore.entries)
              if (resourcesAfter.containsKey(entry.key))
                entry.key: resourcesAfter[entry.key]! - entry.value,
          },
          'rssBytesAfter': ProcessInfo.currentRss,
        },
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
        beforeFood = productFoodState(food),
        before = await inventory();
    await closeHandles();
    await open(fresh: false);
    require(jsonEncode(tasks.rows) == beforeTasks, 'Reopen Task state differs');
    require(productFoodState(food) == beforeFood, 'Reopen Food state differs');
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
  String? replacementTitle,
  String? replacementNotes,
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
      session!.replace(
        'title',
        replacementTitle ?? 'Benchmark synthetic title $rep',
      );
    }
    if (notes || both) {
      session!.replace(
        'description',
        replacementNotes ?? 'Benchmark synthetic Notes $rep',
      );
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
        a.row(id)['title'] ==
            (replacementTitle ?? 'Benchmark synthetic title $rep'),
        'Saved title differs',
      );
    }
    if (notes || both) {
      require(
        a.row(id)['description'] ==
            (replacementNotes ?? 'Benchmark synthetic Notes $rep'),
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

Map<String, Object?> convertedBeforeState(Audit a, Object value) {
  final heads = <String, UnifiedRecord>{};
  for (final record in a.history.snapshot.records) {
    final old = heads[record.writer];
    if (old == null || old.sequence < record.sequence) {
      heads[record.writer] = record;
    }
  }
  return {
    'canonicalCurrentValueSHA256': bytesDigest(
      utf8.encode(canonicalDataJson(value)),
    ),
    'physicalHeads': {
      for (final entry in heads.entries)
        entry.key: {'sequence': entry.value.sequence, 'hash': entry.value.hash},
    },
    'cache':
        'fresh profile per family; native owner retained across repetitions',
    'sequence': 'two warmups then five measured samples; no timing retry',
  };
}

List<String> convertedTaskTargets(Audit a) {
  final base = a.config['fixtureBaseIdentity'] as int;
  final ids = [
    for (final i in [3, 6, 9, 18]) benchmarkId('task:$base:$i'),
  ];
  for (final id in ids) {
    final birth = a.history.snapshot.effects
        .where(
          (effect) =>
              effect.kind == 'history.task' &&
              effect.task?.entity == id &&
              effect.task?.type == 'task.created',
        )
        .toList();
    require(
      birth.length == 1,
      'Converted Task must retain its imported scalar birth',
    );
    require(
      !a.history.snapshot.tasks.any(
        (event) =>
            event.entity == id && event.type == 'task.createdWithText' ||
            (event.data['successor'] as Map?)?['id'] == id,
      ),
      'Converted Task must not be a newly created or derived native target',
    );
    final row = a.row(id);
    require(
      row['kind'] == 'task' &&
          row['completed'] != true &&
          row['assignee'] == a.user,
      'Converted Task target/cohort differs',
    );
  }
  print(
    jsonEncode({
      'measurement': 'converted-target-contract',
      'family': a.family,
      'module': 'tasks',
      'ids': ids,
      'birth': 'history.task/task.created',
      'pairedNativeTarget': ids.first,
      'before': convertedBeforeState(a, a.row(ids.first)),
      'pairedTitle': 'Benchmark paired title',
      'pairedNotes': 'Benchmark paired Notes',
    }),
  );
  return ids;
}

void requireImportedFoodTargets(Audit a, List<String> ids) {
  for (final id in ids) {
    final births = a.history.snapshot.effects
        .where(
          (effect) =>
              effect.kind == 'history.food' &&
              effect.food?.operation.action == FoodAction.add &&
              effect.food!.operation.targets.contains(id),
        )
        .toList();
    require(
      births.length == 1,
      'Food target must retain one imported creation',
    );
    require(
      a.history.manifest.referenceAuthors[births.single.food!.writer] ==
          births.single.food!.author,
      'Food imported ownership differs',
    );
    require(
      a.food.state.active.any((item) => item.id == id),
      'Imported Food target must start active',
    );
  }
}

Future<void> convertedTaskText(Audit a) async {
  final id = convertedTaskTargets(a).first;
  // Contiguous open/Save/Undo repetitions match the paired native input plan.
  // Existing inherited/native metric families retain their original ordering.
  for (final mode in ['title', 'notes', 'titleAndNotes']) {
    for (var rep = sampleStart; rep < sampleEnd; rep++) {
      await textRound(
        a,
        id,
        'task.$mode',
        rep,
        notes: mode == 'notes',
        both: mode == 'titleAndNotes',
        replacementTitle: 'Benchmark paired title',
        replacementNotes: 'Benchmark paired Notes',
      );
    }
  }
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await editorCancelRound(a, id, 'task.editorOpenCancel', rep);
  }
}

// Separate application confirmation boundary; existing backend-only metrics stay intact.
Future<void> convertedConfirmedFood(Audit a) async {
  final base = a.config['fixtureBaseIdentity'] as int;
  final ordinal = base == 60 ? 4 : 1000;
  final id = benchmarkId('food:$base:$ordinal');
  requireImportedFoodTargets(a, [id]);
  final birth = a.history.snapshot.effects
      .singleWhere(
        (effect) =>
            effect.kind == 'history.food' &&
            effect.food?.operation.action == FoodAction.add &&
            effect.food!.operation.targets.contains(id),
      )
      .food!;
  final undoHistory = FoodUndoHistory()
    ..setWorkspace(
      jsonEncode([
        a.history.folder.location,
        a.history.manifest.space,
        a.writer,
      ]),
    );
  print(
    jsonEncode({
      'measurement': 'confirmed-food-contract',
      'family': a.family,
      'target': id,
      'creationReference': birth.id,
      'before': convertedBeforeState(
        a,
        a.food.state.active.singleWhere((item) => item.id == id).toJson(),
      ),
      'boundary':
          'Backend plus main exact-receipt confirmation and real session Undo history; excludes widget/render',
    }),
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final before = logicalFood(a.food);
    final item = a.food.state.active.singleWhere((value) => value.id == id);
    final details = FoodDetails.fromJson({
      ...item.details.toJson(),
      'brand': 'Benchmark paired brand',
    });
    late List<FoodRecord> saved;
    await a.measure('food.paired.details.confirmedSave', rep, () async {
      await a.food.changeDetails([id], details, ['brand']);
      saved = a.food.lastPreparedRecords;
      require(
        saved.every(a.food.isAdmitted),
        'Food save needs exact confirmation',
      );
      undoHistory.record('Updated', saved, confirmed: a.food.isAdmitted);
    }, expectedDelta: 1);
    require(
      saved.length == 1 &&
          saved.single.createdWith[id] == birth.id &&
          a.food.state.active
                  .singleWhere((value) => value.id == id)
                  .details
                  .brand ==
              'Benchmark paired brand',
      'Confirmed imported Food edit/basis differs',
    );
    final entry =
        undoHistory.latest ??
        (throw StateError('Confirmed Food Undo entry missing'));
    require(
      undoHistory.length == 1 && identical(entry.records.single, saved.single),
      'Confirmed Food Undo entry differs',
    );
    await a.measure('food.paired.details.confirmedUndo', rep, () async {
      await a.food.undoOperations(entry.records);
      final inverse = a.food.lastPreparedRecords;
      require(
        inverse.every(a.food.isAdmitted),
        'Food Undo needs exact confirmation',
      );
      undoHistory.complete(entry);
    }, expectedDelta: 1);
    require(
      undoHistory.latest == null && undoHistory.length == 0,
      'Confirmed Food Undo entry retained',
    );
    require(logicalFood(a.food) == before, 'Confirmed Food Undo differs');
  }
}

Future<void> convertedPairedFood(Audit a) async {
  final base = a.config['fixtureBaseIdentity'] as int;
  final ordinal = base == 60 ? 4 : 1000;
  final id = benchmarkId('food:$base:$ordinal');
  requireImportedFoodTargets(a, [id]);
  final birth = a.history.snapshot.effects
      .singleWhere(
        (effect) =>
            effect.kind == 'history.food' &&
            effect.food?.operation.action == FoodAction.add &&
            effect.food!.operation.targets.contains(id),
      )
      .food!;
  print(
    jsonEncode({
      'measurement': 'converted-target-contract',
      'family': a.family,
      'module': 'food',
      'ids': [id],
      'creationReference': birth.id,
      'author': birth.author,
      'nativePairing': base == 60
          ? 'functional-only; Food1000 absent'
          : 'Food1000',
      'before': convertedBeforeState(
        a,
        a.food.state.active.singleWhere((value) => value.id == id).toJson(),
      ),
      'pairedBrand': 'Benchmark paired brand',
    }),
  );
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    final before = logicalFood(a.food);
    final item = a.food.state.active.singleWhere((value) => value.id == id);
    final details = FoodDetails.fromJson({
      ...item.details.toJson(),
      'brand': 'Benchmark paired brand',
    });
    await a.measure(
      'food.paired.details.save',
      rep,
      () => a.food.changeDetails([id], details, ['brand']),
      expectedDelta: 1,
    );
    final records = List<FoodRecord>.from(a.food.lastPreparedRecords);
    require(
      records.length == 1 &&
          records.single.createdWith[id] == birth.id &&
          a.food.state.active
                  .singleWhere((value) => value.id == id)
                  .details
                  .brand ==
              'Benchmark paired brand',
      'Paired imported Food edit/basis differs',
    );
    await a.measure(
      'food.paired.details.undo',
      rep,
      () => a.food.undoOperations(records),
      expectedDelta: 1,
    );
    require(logicalFood(a.food) == before, 'Paired Food Undo differs');
  }
}

Future<void> taskCommands(Audit a, {bool converted = false}) async {
  final ids = converted ? convertedTaskTargets(a) : await a.syntheticTasks(4),
      id = ids.first;
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
    require(
      jsonEncode(a.tasks.rows) == before,
      'Task reopen changed the pre-completion workspace state',
    );
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

Future<void> checklist(Audit a, {bool converted = false}) async {
  final parent = converted
      ? convertedTaskTargets(a).first
      : (await a.syntheticTasks(1)).single;
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
    final completionBefore = jsonEncode(a.tasks.rows);
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
    require(
      jsonEncode(a.tasks.rows) == completionBefore,
      'Checklist parent reopen changed the pre-completion workspace state',
    );
  }
}

Future<void> foodCommands(
  Audit a, {
  bool historical = false,
  List<String>? historicalTargets,
}) async {
  require(
    historicalTargets == null || historical,
    'Historical target override',
  );
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
    synthetic =
        historicalTargets ??
        a.food.state.active.take(3).map((c) => c.id).toList();
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
  if (historical) requireImportedFoodTargets(a, synthetic);
  FoodContainer item() =>
      a.food.state.containers.singleWhere((c) => c.id == synthetic.first);
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    for (final count in [1, 3]) {
      final before = logicalFood(a.food);
      await a.measure(
        'food.details.$count',
        rep,
        // Every field the bulk Food editor can apply (all except expiration).
        () => a.food.changeDetails(
          synthetic.take(count).toList(),
          FoodDetails(
            name: 'Benchmark renamed food $rep',
            brand: 'Benchmark new brand',
            size: 'Benchmark new size',
            location: 'Benchmark new location',
            retention: 'Benchmark retention',
          ),
          ['name', 'brand', 'size', 'location', 'retention'],
        ),
        expectedDelta: 1,
      );
      final edits = List<FoodRecord>.from(a.food.lastPreparedRecords);
      require(
        synthetic.take(count).every((id) {
          final details = a.food.state.containers
              .singleWhere((c) => c.id == id)
              .details;
          return details.name == 'Benchmark renamed food $rep' &&
              details.brand == 'Benchmark new brand' &&
              details.size == 'Benchmark new size' &&
              details.location == 'Benchmark new location' &&
              details.retention == 'Benchmark retention';
        }),
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

// A separate current-state stress family; original sealed shapes and labels stay intact.
Future<void> foodCardinality500(Audit a) async {
  final originalTaskRows = jsonEncode(a.tasks.rows);
  final originalFoodCount = a.food.state.containers.length;
  final originalIDs = a.food.state.active.map((item) => item.id).toSet();
  // Preserve the original retained cohort; expected members come from the
  // captured input details rather than calling the view under measurement.
  final originalInventory = {
    for (final item in a.food.state.active)
      if (item.details.expiry != null && item.details.retention.isEmpty)
        item.id,
  };
  final originalRetained = {
    for (final item in a.food.state.active)
      if (item.details.retention.isNotEmpty) item.id,
  };
  final originalInbox = {
    for (final item in a.food.state.active)
      if (item.details.expiry == null && item.details.retention.isEmpty)
        item.id,
  };
  final targets = a.food.state.active.take(3).map((item) => item.id).toList();
  requireImportedFoodTargets(a, targets);
  require(
    originalFoodCount < 490 &&
        originalIDs.length == originalFoodCount &&
        originalInventory.length +
                originalRetained.length +
                originalInbox.length ==
            originalFoodCount &&
        {
          ...originalInventory,
          ...originalRetained,
          ...originalInbox,
        }.containsAll(originalIDs),
    'Expected original active Food fixture with classified exact members',
  );
  final stock = <String>{},
      retained = <String>{},
      inbox = <String>{},
      deleted = <String>{},
      otherInventory = <String>{};
  final sequenceBefore = a.history.physicalSequence;
  for (var i = originalFoodCount; i < 503; i++) {
    final offset = i - originalFoodCount;
    await a.food.add(
      offset < 3
          ? const FoodDetails(
              name: 'Benchmark matched stock',
              expiry: '2026-11-10',
              brand: 'Benchmark matched brand',
              location: 'Benchmark matched location',
            )
          : offset < 5
          ? const FoodDetails(
              name: 'Benchmark matched retained',
              retention: 'Benchmark matched reason',
            )
          : offset < 7
          ? const FoodDetails(name: 'Benchmark cardinality inbox')
          : FoodDetails(
              name: 'Benchmark cardinality food $i',
              expiry: '2026-11-10',
              brand: 'Benchmark cardinality brand',
              location: 'Benchmark cardinality shelf',
            ),
      1,
    );
    final records = a.food.lastPreparedRecords;
    require(
      records.length == 1 && records.every(a.food.isAdmitted),
      'Food setup admission',
    );
    final id = records.single.operation.targets.single;
    (offset < 3
            ? stock
            : offset < 5
            ? retained
            : offset < 7
            ? inbox
            : offset < 10
            ? deleted
            : otherInventory)
        .add(id);
  }
  final removals = await a.food.remove(deleted.toList());
  require(removals.every(a.food.isAdmitted), 'Deleted-cohort setup admission');
  require(
    a.food.state.containers.length == 503 &&
        a.food.state.active.length == 500 &&
        a.food.state.deleted.length == 3 &&
        a.history.physicalSequence - sequenceBefore == 504 - originalFoodCount,
    'Food cardinality setup differs',
  );
  require(
    jsonEncode(a.tasks.rows) == originalTaskRows,
    'Food setup changed Tasks',
  );
  requireImportedFoodTargets(a, targets);
  final expectedModes = {
    FoodView.inventory: {...originalInventory, ...stock, ...otherInventory},
    FoodView.inbox: {...originalInbox, ...inbox},
    FoodView.retained: {...originalRetained, ...retained},
    FoodView.deleted: deleted,
  };
  final expectedMatches = {
    'search': {...stock, ...retained},
    'brand': stock,
    'location': stock,
    'retention': retained,
  };
  require(
    expectedModes[FoodView.inventory]!.length +
                expectedModes[FoodView.inbox]!.length +
                expectedModes[FoodView.retained]!.length ==
            500 &&
        expectedModes.values.expand((ids) => ids).toSet().length == 503 &&
        stock.length == 3 &&
        retained.length == 2 &&
        inbox.length == 2 &&
        deleted.length == 3,
    'Food setup cohort cardinalities',
  );
  print(
    jsonEncode({
      'measurement': 'food-cardinality-setup',
      'family': a.family,
      'initialContainers': originalFoodCount,
      'originalModeCounts': {
        'inventory': originalInventory.length,
        'retained': originalRetained.length,
        'inbox': originalInbox.length,
      },
      'currentContainers': 503,
      'activeContainers': 500,
      'deletedContainers': 3,
      'addedContainers': 503 - originalFoodCount,
      'setupPhysicalDelta': a.history.physicalSequence - sequenceBefore,
      'expectedModeCounts': {
        for (final entry in expectedModes.entries)
          entry.key.name: entry.value.length,
      },
      'expectedMatchCounts': {
        for (final entry in expectedMatches.entries)
          entry.key: entry.value.length,
      },
      'currentFoodSHA256': bytesDigest(utf8.encode(logicalFood(a.food))),
      'taskRowsSHA256': bytesDigest(utf8.encode(originalTaskRows)),
      'physicalRecordsAfterSetup': a.history.snapshot.records.length,
      'scope':
          'production setup outside timers; 500active+3deleted; IDs vary; state-stress case with added history, not isolated cardinality causation',
    }),
  );
  await convertedPairedFood(a);
  await foodCommands(a, historical: true, historicalTargets: targets);
  for (var rep = sampleStart; rep < sampleEnd; rep++) {
    await foodReadModels(a, rep, expectedByView: expectedModes);
    await matchedFoodReadModels(a, rep, expectedIDs: expectedMatches);
    await a.measure(
      'refresh.food.unchanged',
      rep,
      () => a.food.refresh(),
      readOnly: true,
    );
  }
  require(
    a.food.state.containers.length == 503 &&
        a.food.state.active.length == 500 &&
        a.food.state.deleted.length == 3,
    'Food stress family did not restore cardinality',
  );
  require(
    jsonEncode(a.tasks.rows) == originalTaskRows,
    'Food stress family changed Tasks',
  );
}

void requireFoodGroupIDs(
  List<FoodGroup> groups,
  Set<String> expected,
  String label,
) {
  final actual = groups
      .expand((group) => group.containers)
      .map((item) => item.id)
      .toList();
  require(
    actual.length == expected.length &&
        actual.toSet().length == actual.length &&
        actual.toSet().containsAll(expected),
    'Food $label exact members differ',
  );
}

Future<void> foodReadModels(
  Audit a,
  int rep, {
  Map<FoodView, Set<String>>? expectedByView,
}) async {
  for (final mode in FoodView.containerViews) {
    final groups = await a.measure(
      'food.view.${mode.name}',
      rep,
      () async => a.food.state.view(mode),
      readOnly: true,
    );
    require(groups.every((g) => g.containers.isNotEmpty), 'Empty Food group');
    if (expectedByView != null) {
      requireFoodGroupIDs(groups, expectedByView[mode]!, mode.name);
    }
  }
  for (final filter in ['search', 'brand', 'location', 'retention']) {
    final groups = await a.measure(
      'food.filter.$filter',
      rep,
      () async => a.food.state.view(
        filter == 'retention' ? FoodView.retained : FoodView.inventory,
        search: filter == 'search' ? 'synthetic-unmatched-query' : '',
        brands: filter == 'brand' ? {'synthetic-unmatched-brand'} : {},
        locations: filter == 'location' ? {'synthetic-unmatched-location'} : {},
        reasons: filter == 'retention' ? {'synthetic-unmatched-reason'} : {},
      ),
      readOnly: true,
    );
    require(groups.isEmpty, 'Expected unmatched Food filter');
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
    await foodReadModels(a, rep);
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
  await sessionEquivalence(a);
}

/// The app and the agent CLI open through [WorkspaceSession]. The timed
/// startup labels keep their per-phase store calls (history, Task attach,
/// Food attach), which are the session's own calls in the same order; outside
/// the timers, the composed session must reach the same state without
/// writing. Its remaining steps (folder listing, open-time occurrence
/// migration) stay the documented startup gap.
Future<void> sessionEquivalence(Audit a) async {
  final tasks = jsonEncode(a.tasks.rows), food = productFoodState(a.food);
  final before = await a.inventory();
  await a.closeHandles();
  final profile = await LocalProfileDatabase.open(
    a.profileOverride ?? '${a.root.path}/profile',
  );
  WorkspaceSession? session;
  try {
    session = await WorkspaceSession.open(
      LocalLogFolder(a.shared.path, durability: durabilityDiagnostics),
      profile: profile,
      writer: a.writer,
      textEngine: a.engine,
    );
    require(
      session != null && session.occurrenceMigrationError == null,
      'WorkspaceSession open failed',
    );
    require(
      jsonEncode(session!.tasks.rows) == tasks &&
          productFoodState(session.food) == food,
      'WorkspaceSession state differs from the timed store sequence',
    );
    require(
      sameData(await a.inventory(), before),
      'WorkspaceSession open wrote canonical bytes',
    );
  } finally {
    await session?.close();
    await profile.close();
  }
  await a.open(fresh: false);
  print(
    jsonEncode({
      'measurement': 'workspace-session-equivalence',
      'family': a.family,
      'sameTasksFoodAndBytes': true,
    }),
  );
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
    args.length == 4 || (args.length == 5 && args[0] == 'resample'),
    'Usage: benchmark generate OUTPUT_ROOT NATIVE_LIBRARY BASE_RECORDS | benchmark run OUTPUT_ROOT NATIVE_LIBRARY FIXTURE_MANIFEST | benchmark resample OUTPUT_ROOT NATIVE_LIBRARY FIXTURE_MANIFEST FAMILY',
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
  require(
    {'run', 'diagnose', 'resample'}.contains(args[0]),
    'Unknown benchmark mode',
  );
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
    'fixtureBaseIdentity': count == 60 ? 60 : 1320,
    'diagnosticCosts': args[0] == 'diagnose',
  };
  final all = <String, Future<void> Function(Audit)>{
    'task-text': taskText,
    'explicit-task-text': explicitTaskText,
    'task-commands': taskCommands,
    'converted-task-text': convertedTaskText,
    'converted-task-commands': (a) => taskCommands(a, converted: true),
    'converted-checklist': (a) => checklist(a, converted: true),
    'converted-food-paired': convertedPairedFood,
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
    'food-cardinality500': foodCardinality500,
    'converted-food-confirmed': convertedConfirmedFood,
    'food-products': foodProducts,
    'food-move-some': foodMoveSome,
    'first-derived-tags': (a) =>
        firstDerivedPointAction(a, sampleStart, 'tags'),
    'first-copied-checkbox': (a) =>
        firstDerivedPointAction(a, sampleStart, 'copy'),
    'first-derived-mixed': (a) =>
        firstDerivedPointAction(a, sampleStart, 'mixed'),
    'agent-cli': agentCli,
  };
  // Disk-stall resample: one family, all warmups and samples, fresh process.
  final only = args[0] == 'resample' ? args[4] : null;
  require(only == null || all.containsKey(only), 'Unknown resample family');
  for (final entry in all.entries) {
    if (only != null && entry.key != only) continue;
    if (entry.key == 'food-products' ||
        entry.key == 'food-move-some' ||
        entry.key == 'agent-cli' ||
        entry.key == 'derived-recurring' ||
        entry.key.startsWith('first-derived-') ||
        entry.key == 'first-copied-checkbox') {
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
      'families': only == null ? all.length : 1,
      'resampleFamily': ?only,
      'fixtureSchemaVersion': fixtureSchemaVersion,
      'baseHistoricalRecords': count,
      'actualPhysicalRecords': fixture['actualPhysicalRecords'],
      'growthKind': fixture['growthKind'],
      'warmups': benchmarkWarmups,
      'samples': benchmarkSamples,
      'costDiagnosticsEnabled': args[0] == 'diagnose',
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

Future<void> matchedFoodReadModels(
  Audit a,
  int rep, {
  Map<String, Set<String>>? expectedIDs,
}) async {
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
    if (expectedIDs != null) {
      requireFoodGroupIDs(result, expectedIDs[kind]!, 'matched $kind');
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
    await matchedFoodReadModels(a, rep);
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
      LocalLogFolder(remote.path, durability: durabilityDiagnostics),
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

Future<void> firstDerivedPointAction(Audit a, int rep, String kind) async {
  final copied = kind == 'copy', mixed = kind == 'mixed';
  final parent = (await a.syntheticTasks(1)).single;
  await a.tasks.edit(
    parent,
    {
      'schedule': {'dueDate': '2026-10-22', 'recurrence': 'every day'},
    },
    tags: [],
    observedTagRefs: {},
  );
  final item = await a.tasks.addChecklistItem(
    parent,
    'Baseline copied item',
    notes: 'Synthetic Notes',
  );
  final completion = await a.tasks.complete(
    parent,
    localZoneId: 'UTC',
    completionInstant: DateTime.utc(2026, 10, 22),
  );
  final child = const Uuid().v5(parent, 'successor');
  final sourceItem = item.entity;
  final copy = const Uuid().v5(child, 'checklist:$sourceItem');
  final target = copied ? copy : child;
  final old = a.history.snapshot;
  require(old.allVisibleTasksReady, 'Prior graph must be fully ready');
  require(
    !old.tasks.any((event) => event.entity == child || event.entity == copy),
    'No prior child/item canonical activity',
  );
  final expectedOrder =
      '${completion.clock.toString().padLeft(19, '0')}:${completion.writer}';
  final orderBefore = a.row(child)['order'];
  require(
    orderBefore == expectedOrder,
    'Actual selected pre-seed must be completion',
  );
  Map<String, dynamic> contexts() => {
    for (final row in a.tasks.db.select(
      'SELECT field,context FROM ${a.tasks.tables.textFields} WHERE entity=? ORDER BY field',
      [target],
    ))
      row['field'] as String: row['context'],
  };
  final priorContexts = contexts();
  require(priorContexts.length == 2, 'Actual native field contexts required');
  final before = jsonEncode(a.tasks.rows);
  final row = a.row(target);
  final snapshot = a.tasks.taskSnapshot;
  TaskTextCapture? capture;
  TaskTextSession? session;
  try {
    if (mixed) {
      final activeCapture = await a.tasks.captureTaskText(target);
      capture = activeCapture;
      session = TaskTextSession(
        activeCapture,
        registerDraftActor: (field, allocation, actor) => a.tasks
            .registerTextDraftActor(activeCapture, field, allocation, actor),
      );
      session.replace('title', 'First mixed title');
    }
    final full = a.history.fullTaskReadinessRuns;
    OperationReceipt? receipt;
    final label = copied
        ? 'firstCopied.metadata.complete'
        : mixed
        ? 'firstDerived.mixed.save'
        : 'firstDerived.metadata.tags';
    if (copied) {
      await a.measure(
        label,
        rep,
        () => a.tasks.setChecklistCompleted(
          copy,
          true,
          onPrepared: (r) => receipt = r,
        ),
        expectedDelta: 1,
      );
      require(
        a.row(copy)['completed'] == true,
        'First checkbox must be visible',
      );
    } else if (mixed) {
      final saved = await a.measure(
        label,
        rep,
        () => TextSaveCommand(a.tasks, session!).save(
          fields: {
            'schedule': {
              ...Map<String, dynamic>.from(row['schedule'] as Map),
              'dueDate': '2026-10-24',
            },
          },
          tags: [
            ...List<String>.from(row['tags'] as List? ?? []),
            'first-mixed-tag',
          ],
          observedTagRefs: Map<String, String>.from(
            row['tagRefs'] as Map? ?? {},
          ),
          expectedSnapshot: snapshot,
        ),
        expectedDelta: 1,
      );
      receipt = saved.receipt;
      require(
        saved.status != TextSaveStatus.unchanged &&
            a.row(target)['title'] == 'First mixed title',
        'Actual mixed native Save required',
      );
      require(
        (a.row(target)['schedule'] as Map)['dueDate'] == '2026-10-24' &&
            (a.row(target)['tags'] as List).contains('first-mixed-tag'),
        'Mixed metadata missing',
      );
    } else {
      await a.measure(
        label,
        rep,
        () => a.tasks.edit(
          child,
          {},
          tags: [
            ...List<String>.from(row['tags'] as List? ?? []),
            'first-metadata',
          ],
          observedTagRefs: Map<String, String>.from(
            row['tagRefs'] as Map? ?? {},
          ),
          expectedTaskSnapshot: snapshot,
          onPrepared: (r) => receipt = r,
        ),
        expectedDelta: 1,
      );
      require(
        (a.row(child)['tags'] as List).contains('first-metadata'),
        'First tags must be visible',
      );
    }
    require(
      receipt != null && a.history.snapshot.allVisibleTasksReady,
      'Actual new operation must be ready',
    );
    require(
      a.history.fullTaskReadinessRuns == full,
      'Proven first point action must avoid full readiness',
    );
    require(
      a.row(child)['order'] == orderBefore,
      'Actual selected post-seed/order must remain exact',
    );
    require(
      jsonEncode(contexts()) == jsonEncode(priorContexts),
      'Actual native context unexpectedly changed',
    );
    // Keep full replay away from the timed pair's live engine caches.
    final savedSnapshot = a.history.snapshot;
    final savedRows = jsonEncode(a.tasks.rows);
    final savedReady = Set<String>.unmodifiable(savedSnapshot.readyTaskIds);
    void oracle(
      UnifiedSnapshot current,
      String expectedRows,
      Set<String> expectedReady,
    ) {
      require(
        expectedRows ==
            jsonEncode(
              TaskStore.validateSemanticHistory(
                current.tasks,
                space: a.tasks.space,
                writer: a.tasks.writer,
                textEngine: a.engine,
              ),
            ),
        'Fresh full rows oracle differs',
      );
      final validator = TaskSemanticValidator(
        space: a.tasks.space,
        writer: a.tasks.writer,
        textEngine: a.engine,
      );
      try {
        final ready = validator.validate(
          List<LogEvent>.unmodifiable(current.tasks),
        );
        require(
          ready.length == expectedReady.length &&
              ready.every(expectedReady.contains),
          'Fresh ready oracle differs',
        );
      } finally {
        validator.close();
      }
    }

    final afterFull = a.history.fullTaskReadinessRuns;
    final undoLabel = mixed ? 'firstDerived.mixed.undo' : '$label.undo';
    await a.undo(receipt!, undoLabel, rep);
    require(
      a.history.fullTaskReadinessRuns == afterFull,
      'Established point Undo must avoid full readiness',
    );
    final undoSnapshot = a.history.snapshot;
    final undoRows = jsonEncode(a.tasks.rows);
    final undoReady = Set<String>.unmodifiable(undoSnapshot.readyTaskIds);
    require(undoRows == before, 'First metadata Undo must restore exact rows');
    // Both original full oracles remain, using their own immutable state.
    oracle(savedSnapshot, savedRows, savedReady);
    oracle(undoSnapshot, undoRows, undoReady);
    print(
      jsonEncode({
        'measurement': 'first-metadata-proof',
        'case': label,
        'index': rep,
        'noPriorOwnActivity': true,
        'allOldAndNewReady': true,
        'actualPreAndPostSeedOrderExact': true,
        'actualNativeContextsExact': true,
        'fullReadinessDelta': afterFull - full,
        'undoFullReadinessDelta': a.history.fullTaskReadinessRuns - afterFull,
        'freshFullOracleAccepted': true,
        'scope': 'standalone first-point action, no UI or release acceptance',
      }),
    );
  } finally {
    session?.cancel();
    if (capture != null) a.tasks.releaseTextCapture(capture);
  }
}

/// Production editor/store paths, with actual session confirmation and Undo.
/// Each repetition has a fresh sealed workspace: implicit first edit, bulk
/// product edit, rename/merge, explicit-link Add and reviewed receipt import.
Future<void> foodProducts(Audit a) async {
  final rep = sampleStart;
  final tasksBefore = jsonEncode(a.tasks.rows);
  final base = a.config['fixtureBaseIdentity'] as int;
  final imported = benchmarkId('food:$base:${base == 60 ? 4 : 1000}');
  requireImportedFoodTargets(a, [imported]);
  final source = a.food.state.containers.singleWhere((c) => c.id == imported);
  final sourceRoot = source.product;
  final undo = FoodUndoHistory()..setWorkspace(a.shared.path);

  Future<void> confirmed(Future<void> Function() command) async {
    await command();
    final records = List<FoodRecord>.of(a.food.lastPreparedRecords);
    require(
      records.isNotEmpty && records.every(a.food.isAdmitted),
      'Product action not exactly confirmed',
    );
    undo.record('Updated', records, confirmed: a.food.isAdmitted);
  }

  Future<void> inverse(String label, String before) async {
    // Reopen while the operation is still active, not only after its inverse.
    await a.replayCheck();
    final entry = undo.latest!;
    await a.measure('food.product.$label.undo', rep, () async {
      await a.food.undoOperations(entry.records);
      require(
        a.food.lastPreparedRecords.every(a.food.isAdmitted),
        'Product inverse not exactly confirmed',
      );
      undo.complete(entry);
    }, expectedDelta: 1);
    require(
      undo.length == 0 && productFoodState(a.food) == before,
      'Full product/catalog/container Undo differs: $label',
    );
    require(
      jsonEncode(a.tasks.rows) == tasksBefore,
      'Product action changed Tasks',
    );
  }

  var before = productFoodState(a.food);
  await a.measure(
    'food.product.edit',
    rep,
    () => confirmed(
      () => a.food.changeDetails(
        [source.id],
        source.details,
        [],
        products: FoodProductChange(
          roots: [sourceRoot],
          changes: {
            'name': 'Benchmark renamed product',
            'brand': 'Benchmark SKU brand',
            'size': '500 g',
            'links': ['https://example.com/benchmark-product'],
            'minimum': 100,
          },
        ),
      ),
    ),
    expectedDelta: 1,
  );
  final edited = a.food.state.products[sourceRoot]!;
  require(
    edited.name == 'Benchmark renamed product' &&
        edited.brand == 'Benchmark SKU brand' &&
        edited.size == '500 g' &&
        edited.links.single == 'https://example.com/benchmark-product' &&
        edited.minimum == 100 &&
        edited.runningLow,
    'Product editor fields/running-low differ',
  );
  await inverse('edit', before);

  // Seed a second product, then persistently rename it: Add by its new
  // description must use the production revision-2 product-link path.
  await a.food.add(const FoodDetails(name: 'Benchmark other SKU'), 2);
  final other = a.food.state.containers.firstWhere(
    (c) => c.details.name == 'Benchmark other SKU',
  );
  final targetRoot = other.product;
  const target = FoodDetails(
    name: 'Benchmark explicit target',
    brand: 'Target',
  );
  await a.food.changeDetails(
    [other.id],
    target,
    [],
    products: FoodProductChange(
      roots: [targetRoot],
      changes: {'name': target.name, 'brand': target.brand},
    ),
  );

  before = productFoodState(a.food);
  await a.measure(
    'food.product.bulkEdit',
    rep,
    () => confirmed(
      () => a.food.changeDetails(
        [source.id, other.id],
        const FoodDetails(name: 'unused', location: 'Benchmark shelf'),
        ['location'],
        products: FoodProductChange(
          roots: [sourceRoot, targetRoot],
          changes: {'size': '750 g'},
        ),
      ),
    ),
    expectedDelta: 1,
  );
  require(
    [
          sourceRoot,
          targetRoot,
        ].every((id) => a.food.state.products[id]!.size == '750 g') &&
        a.food.state.containers
            .where((c) => c.id == source.id || c.id == other.id)
            .every((c) => c.details.location == 'Benchmark shelf'),
    'Bulk product/container mixed Save differs',
  );
  await inverse('bulkEdit', before);

  before = productFoodState(a.food);
  await a.measure(
    'food.product.merge',
    rep,
    () => confirmed(
      () => a.food.changeDetails(
        [source.id],
        target,
        [],
        products: FoodProductChange(
          roots: [sourceRoot],
          changes: {
            'name': target.name,
            'brand': target.brand,
            'size': target.size,
          },
        ),
      ),
    ),
    expectedDelta: 1,
  );
  require(
    a.food.state.catalog.resolve(sourceRoot) == targetRoot &&
        a.food.state.containers.singleWhere((c) => c.id == source.id).product ==
            targetRoot,
    'Rename did not merge whole product',
  );
  await inverse('merge', before);

  before = productFoodState(a.food);
  final oldIDs = a.food.state.containers.map((c) => c.id).toSet();
  await a.measure(
    'food.product.addWithProduct',
    rep,
    () => confirmed(() => a.food.add(target, 3)),
    expectedDelta: 1,
  );
  final added = a.food.state.containers
      .where((c) => !oldIDs.contains(c.id))
      .toList();
  require(
    added.length == 3 &&
        added.every(
          (c) => c.product == targetRoot && c.productLink == targetRoot,
        ),
    'Add did not link three containers to renamed product',
  );
  await inverse('addWithProduct', before);

  // One existing-product line matches a historical hand entry; one new SKU
  // creates three Inbox containers. Stable public receipt keys, no private data.
  final plan = FoodPurchaseImportPlan(
    space: a.food.space,
    importId: benchmarkId('product-benchmark-import:$rep'),
    sourceSha256: bytesDigest(utf8.encode('synthetic product receipt $rep')),
    lines: [
      FoodPurchaseLine(
        sourceKind: 'benchmark',
        sourceKey: 'existing-$rep',
        date: source.createdAt.substring(0, 10),
        store: 'Synthetic store',
        amount: 250,
        quantity: 1,
        product: sourceRoot,
      ),
      FoodPurchaseLine(
        sourceKind: 'benchmark',
        sourceKey: 'new-$rep',
        date: '2026-10-28',
        store: 'Synthetic store',
        amount: 900,
        quantity: 3,
        name: 'Benchmark receipt SKU',
        brand: 'Receipt',
        link: 'https://example.com/receipt-sku',
      ),
    ],
  );
  before = productFoodState(a.food);
  final dry = await a.measure(
    'food.product.import.dryRun',
    rep,
    () => a.food.dryRunPurchaseImport(plan),
    readOnly: true,
  );
  require(
    dry.status == FoodPurchaseImportStatus.ready &&
        dry.lines.first.matched.length == 1 &&
        dry.lines.last.created.length == 3 &&
        productFoodState(a.food) == before,
    'Receipt dry run differs',
  );
  await a.measure(
    'food.product.import.commit',
    rep,
    () => confirmed(() async {
      await a.food.commitPurchaseImport(plan);
    }),
    expectedDelta: 1,
  );
  for (final line in plan.lines) {
    final purchase = a.food.state.catalog.purchases[line.purchaseId]!;
    require(
      purchase.amount == line.amount &&
          purchase.quantity == line.quantity &&
          purchase.store == line.store &&
          purchase.date == line.date &&
          purchase.currency == line.currency &&
          !purchase.voided &&
          canonicalDataJson(purchase.source) == canonicalDataJson(line.source),
      'Imported purchase values differ',
    );
    require(
      a.food.state.containers.where((c) => c.purchase == purchase.id).length ==
          line.quantity,
      'Imported purchase container links/count differ',
    );
  }
  final committed = productFoodState(a.food);
  final retry = await a.measure(
    'food.product.import.retry',
    rep,
    () => a.food.commitPurchaseImport(plan),
    readOnly: true,
  );
  require(
    retry.status == FoodPurchaseImportStatus.committed &&
        productFoodState(a.food) == committed,
    'Receipt retry duplicated or changed state',
  );
  await inverse('import', before);

  // Force a new profile to replay the still-active explicit product seed.
  await a.closeHandles();
  a.profileOverride = '${a.root.path}/product-fresh-replay';
  await a.open(fresh: true);
  require(
    productFoodState(a.food) == before &&
        jsonEncode(a.tasks.rows) == tasksBefore,
    'Fresh canonical product/catalog replay differs',
  );
}

/// Headless agent CLI tool calls (design/agent-interface.md section 8). Each
/// repetition copies the sealed fixture, joins it with a fresh agent profile
/// through `init`, then times whole in-process [runCli] calls: argument
/// parsing, profile lock/read copy, [WorkspaceSession] open, the command,
/// close and JSON rendering. Process start, AOT/VM boot, native library
/// loading and stdout are outside this boundary.
Future<void> agentCli(Audit a) async {
  final rep = sampleStart;
  agentTextEngine = () => NativeTextEngine(
    libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
  );
  final targets = convertedTaskTargets(a);
  final base = a.config['fixtureBaseIdentity'] as int;
  final imported = benchmarkId('food:$base:${base == 60 ? 4 : 1000}');
  requireImportedFoodTargets(a, [imported]);
  final source = a.food.state.containers.singleWhere((c) => c.id == imported);
  final taskIDs = {
    for (final r in a.tasks.rows)
      if (r['kind'] == 'task') r['id'] as String,
  };
  final containerIDs = {for (final c in a.food.state.containers) c.id};
  final tasksBefore = jsonEncode(a.tasks.rows);
  // The agent is a separate installation; the audit writer stays closed so
  // only agent calls touch the folder until the family's replay check.
  await a.closeHandles();
  final profile = '${a.root.path}/agent-profile';
  final env = {'HOME': a.root.path};

  Future<Map<String, dynamic>> cli(List<String> argv) async {
    final (code, out) = await runCli([
      ...argv,
      '--profile',
      profile,
      '--tz',
      'America/Chicago',
      '--format',
      'json',
    ], environment: env);
    final value = jsonDecode(out) as Map<String, dynamic>;
    require(code == 0, 'Agent CLI ${argv.take(2).join(' ')} failed: $out');
    return value;
  }

  Future<String> bytes({bool canonicalOnly = false}) async {
    final files = <File>[
      for (final dir in [a.shared, if (!canonicalOnly) Directory(profile)])
        ...await dir
            .list(recursive: true)
            .where((f) => f is File && !f.path.endsWith('/agent.lock'))
            .cast<File>()
            .toList(),
    ]..sort((x, y) => x.path.compareTo(y.path));
    return [
      for (final f in files) '${f.path} ${bytesDigest(await f.readAsBytes())}',
    ].join('\n');
  }

  Future<T> measure<T>(String action, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    final value = await body();
    final us = watch.elapsedMicroseconds;
    print(
      jsonEncode({
        'index': rep,
        'warmup': rep < benchmarkWarmups,
        'measurement': 'broad-action',
        'family': a.family,
        'action': action,
        'rep': rep,
        'microseconds': us,
        'diagnostics': {
          'agentProfileBytes': await Directory(profile)
              .list()
              .where((f) => f is File)
              .cast<File>()
              .fold<int>(0, (n, f) => n + f.lengthSync()),
          'rssBytesAfter': ProcessInfo.currentRss,
        },
        'scope':
            'in-process agent CLI call (parse, lock/copy, open, command, close, render); no process start or packaged binary',
      }),
    );
    return value;
  }

  Map<String, dynamic> shown(Map<String, dynamic> task) =>
      Map.of(task)..remove('rev');

  // Setup outside timers: join the copied fixture as a new agent writer.
  final joined = await cli([
    'init',
    '--workspace',
    a.shared.path,
    '--name',
    'Benchmark agent',
  ]);
  require(joined['writer'] != a.writer, 'Agent must be its own installation');

  var before = await bytes();
  final listed = await measure(
    'agent.read.coldOpenTasksList',
    () => cli(['tasks', 'list']),
  );
  final listedTasks = (listed['tasks'] as List).cast<Map>();
  require(
    listedTasks.isNotEmpty &&
        (listed['total'] as int) >= listedTasks.length &&
        listedTasks.every((t) => taskIDs.contains(t['id'])),
    'Agent tasks list differs from the fixture',
  );
  require(await bytes() == before, 'Agent read changed workspace or profile');

  final food = await measure(
    'agent.read.foodList',
    () => cli(['food', 'list']),
  );
  final rows = (food['rows'] as List).cast<Map>();
  require(
    rows.isNotEmpty && (food['total'] as int) >= rows.length,
    'Agent food list is empty',
  );
  require(await bytes() == before, 'Agent read changed workspace or profile');

  // Complete an imported scalar Task with its rev; whole-action Undo restores.
  final completeID = targets[0];
  final open = await cli(['tasks', 'show', completeID]);
  require(open['completed'] == false, 'Complete target already completed');
  final completed = await measure(
    'agent.write.taskComplete',
    () => cli([
      'tasks',
      'complete',
      completeID,
      '--if-rev',
      open['rev'] as String,
    ]),
  );
  final completeAction = (completed['actions'] as List).single as String;
  final afterComplete = await cli(['tasks', 'show', completeID]);
  require(
    afterComplete['rev'] != open['rev'] &&
        ((completed['affected'] as List).single as Map)['rev'] ==
            afterComplete['rev'],
    'Agent complete result differs',
  );
  await cli([
    'undo',
    completeAction,
    '--rev',
    '$completeID=${afterComplete['rev']}',
  ]);
  require(
    sameData(shown(await cli(['tasks', 'show', completeID])), shown(open)),
    'Agent complete Undo did not restore the task',
  );

  // Text edit, then whole-action Undo in its own (fresh-open) call.
  final textID = targets[1];
  final unedited = await cli(['tasks', 'show', textID]);
  final title = 'Benchmark agent title $rep';
  final edited = await measure(
    'agent.write.textEdit',
    () => cli([
      'tasks',
      'edit',
      textID,
      '--if-rev',
      unedited['rev'] as String,
      '--title',
      title,
    ]),
  );
  final editAction = (edited['actions'] as List).single as String;
  final afterEdit = await cli(['tasks', 'show', textID]);
  require(afterEdit['title'] == title, 'Agent text edit not applied');
  final undone = await measure(
    'agent.write.textEditUndo',
    () => cli(['undo', editAction, '--rev', '$textID=${afterEdit['rev']}']),
  );
  require(
    undone['alreadyUndone'] != true && (undone['actions'] as List).length == 1,
    'Agent text Undo appended no inverse',
  );
  require(
    sameData(shown(await cli(['tasks', 'show', textID])), shown(unedited)),
    'Agent text Undo did not restore the task',
  );

  // Two-task bulk edit dry run on the copy-on-write overlay.
  final bulk = [
    for (final id in targets.sublist(2)) await cli(['tasks', 'show', id]),
  ];
  before = await bytes();
  final plan = await measure(
    'agent.dryRun.bulkEdit2',
    () => cli([
      'tasks',
      'bulk-edit',
      for (final t in bulk) t['id'] as String,
      for (final t in bulk) ...['--rev', '${t['id']}=${t['rev']}'],
      '--due',
      '2026-11-05',
      '--dry-run',
    ]),
  );
  final effects = (plan['effects'] as List).cast<Map>();
  require(
    plan['dryRun'] == true &&
        (plan['planHash'] as String).isNotEmpty &&
        effects.length == 2 &&
        effects.every(
          (e) =>
              e['change'] == 'changed' &&
              targets.sublist(2).contains(e['id']) &&
              (e['fields'] as Map).containsKey('schedule'),
        ),
    'Agent bulk dry-run plan differs',
  );
  require(
    await bytes() == before,
    'Agent dry run changed workspace or profile',
  );

  // Two-line receipt: one existing product matching the imported hand entry,
  // one new SKU creating three Inbox containers (as food.product.import).
  final lines = File('${a.root.path}/agent-receipt-$rep.json');
  await lines.writeAsString(
    jsonEncode([
      {
        'source': {'kind': 'benchmark', 'key': 'existing-$rep'},
        'date': source.createdAt.substring(0, 10),
        'store': 'Synthetic store',
        'amount': 250,
        'quantity': 1,
        'product': source.product,
      },
      {
        'source': {'kind': 'benchmark', 'key': 'new-$rep'},
        'date': '2026-10-28',
        'store': 'Synthetic store',
        'amount': 900,
        'quantity': 3,
        'name': 'Benchmark receipt SKU',
        'brand': 'Receipt',
        'link': 'https://example.com/receipt-sku',
      },
    ]),
  );
  final planned = await cli(['purchases', 'plan', lines.path]);
  final planFile = planned['plan'] as String;
  require(planned['lines'] == 2, 'Agent purchase plan line count differs');
  before = await bytes(canonicalOnly: true);
  final dry = await measure(
    'agent.dryRun.purchaseImport2',
    () => cli(['purchases', 'import', planFile, '--dry-run']),
  );
  void requireLines(Map<String, dynamic> report) {
    final out = (report['lines'] as List).cast<Map>();
    require(
      out.length == 2 &&
          (out.first['matched'] as List).length == 1 &&
          (out.first['created'] as List).isEmpty &&
          (out.last['created'] as List).length == 3 &&
          out.last['newProduct'] == true,
      'Agent purchase import lines differ',
    );
  }

  require(
    dry['dryRun'] == true &&
        dry['status'] == 'ready' &&
        dry['importPlanHash'] == planned['planHash'],
    'Agent purchase dry run differs',
  );
  requireLines(dry);
  // The import's own dry run opens the agent profile for writing, so only
  // the canonical workspace must stay byte-identical.
  require(
    await bytes(canonicalOnly: true) == before,
    'Agent dry run changed canonical bytes',
  );
  final committed = await measure(
    'agent.write.purchaseImport2',
    () => cli([
      'purchases',
      'import',
      planFile,
      '--expect-plan',
      dry['planHash'] as String,
    ]),
  );
  require(
    committed['dryRun'] != true &&
        committed['importPlanHash'] == planned['planHash'] &&
        committed['status'] == 'ready' &&
        (committed['lines'] as List).every((l) => l['status'] == 'recorded') &&
        (committed['actions'] as List).length == 1,
    'Agent purchase import did not record one action',
  );
  requireLines(committed);

  // Back on the audit installation: the agent's actions replay; the Tasks
  // it changed and restored are unchanged, and Food gained exactly the
  // receipt's three Inbox containers.
  await a.open(fresh: false);
  require(
    jsonEncode(a.tasks.rows) == tasksBefore,
    'Agent Undo left Task drift',
  );
  final added = a.food.state.containers
      .where((c) => !containerIDs.contains(c.id))
      .toList();
  require(
    added.length == 3 && added.every((c) => c.purchase != null),
    'Agent import containers differ on the audit installation',
  );
}

/// Food row ⋮ Move some…: the page's onDetails path moves the first two
/// current containers of a three-container row (the imported container plus
/// two Add another containers) to a new Location as one changeDetails action,
/// with exact confirmation and session Undo. Fresh sealed workspace per
/// repetition, as in food-products.
Future<void> foodMoveSome(Audit a) async {
  final rep = sampleStart;
  final tasksBefore = jsonEncode(a.tasks.rows);
  final base = a.config['fixtureBaseIdentity'] as int;
  final imported = benchmarkId('food:$base:${base == 60 ? 4 : 1000}');
  requireImportedFoodTargets(a, [imported]);
  final source = a.food.state.containers.singleWhere((c) => c.id == imported);
  require(!source.deleted, 'Move some needs an active imported container');
  // Untimed setup: two more containers join the imported container's row.
  await a.food.add(source.details, 2);
  String rowKey() {
    final item = a.food.state.containers.singleWhere((c) => c.id == imported);
    return foodRowKey(item, a.food.state.usesProducts ? item.product : '');
  }

  final key = rowKey();
  final members = a.food.state.rows[key]!;
  require(
    members.length == 3 && members.any((c) => c.id == imported),
    'Move some row setup differs',
  );
  final moving = members.take(2).map((c) => c.id).toList();
  final details = members.first.details;
  final before = productFoodState(a.food);
  final undo = FoodUndoHistory()..setWorkspace(a.shared.path);
  await a.measure('food.moveSome', rep, () async {
    await a.food.changeDetails(
      moving,
      FoodDetails(
        name: details.name,
        brand: details.brand,
        expiry: details.expiry,
        estimated: details.estimated,
        retention: details.retention,
        location: 'Benchmark moved shelf',
        size: details.size,
      ),
      const ['location'],
    );
    final records = List<FoodRecord>.of(a.food.lastPreparedRecords);
    require(
      records.isNotEmpty && records.every(a.food.isAdmitted),
      'Move some not exactly confirmed',
    );
    undo.record('editing', records, confirmed: a.food.isAdmitted);
  }, expectedDelta: 1);
  final moved = a.food.state.containers
      .where((c) => moving.contains(c.id))
      .toList();
  require(
    undo.length == 1 &&
        moved.length == 2 &&
        moved.every((c) => c.details.location == 'Benchmark moved shelf') &&
        (a.food.state.rows[key]?.length ?? 0) == 1 &&
        a
                .food
                .state
                .rows[foodRowKey(
                  moved.first,
                  a.food.state.usesProducts ? moved.first.product : '',
                )]!
                .length ==
            2,
    'Move some did not split exactly two containers into their own row',
  );
  // Reopen while the move is still active, as food-products does.
  await a.replayCheck();
  final entry = undo.latest!;
  await a.measure('food.moveSome.undo', rep, () async {
    await a.food.undoOperations(entry.records);
    require(
      a.food.lastPreparedRecords.every(a.food.isAdmitted),
      'Move some inverse not exactly confirmed',
    );
    undo.complete(entry);
  }, expectedDelta: 1);
  require(
    undo.length == 0 &&
        productFoodState(a.food) == before &&
        a.food.state.rows[rowKey()]!.length == 3,
    'Move some Undo differs from the prior row',
  );
  require(jsonEncode(a.tasks.rows) == tasksBefore, 'Move some changed Tasks');
}
