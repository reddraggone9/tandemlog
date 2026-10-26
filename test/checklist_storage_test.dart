import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/checklist_copy_index.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late LocalLogFolder folder, remote;
  late TaskStore a, b;
  late NativeTextEngine engine;
  late String user, parent;
  var closedA = false, closedB = false;
  Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
    for (final f in await from.list()) {
      await File('${from.location}/${f.name}').copy('${to.location}/${f.name}');
    }
  }

  Map<String, dynamic> task(TaskStore store, String id) =>
      store.rows.singleWhere((row) => row['id'] == id);
  List<Map<String, dynamic>> items(TaskStore store, String id) =>
      (task(store, id)['checklist'] as List? ?? [])
          .cast<Map<String, dynamic>>();
  Map<String, dynamic> seed(String title, String notes) => {
    'codec': 'yrs-v1',
    'adapter': 1,
    'seeds': {
      'title': sha256.convert(engine.seedText(title).bytes).toString(),
      'description': sha256.convert(engine.seedText(notes).bytes).toString(),
    },
  };
  Future<String> add(String title, {String notes = '', String? owner}) async {
    final id = const Uuid().v4();
    await a.command(id, 'checklist.itemCreated', {
      'parent': owner ?? parent,
      'title': title,
      'description': notes,
      'before': null,
      'text': seed(title, notes),
    });
    return id;
  }

  Future<TextSaveResult> saveText(
    TaskStore store,
    String id,
    String field,
    String value,
  ) async {
    final capture = await store.captureTaskText(id);
    final session = TaskTextSession(
      capture,
      registerDraftActor: (field, allocation, actor) =>
          store.registerTextDraftActor(capture, field, allocation, actor),
    );
    try {
      session.replace(field, value);
      return await TextSaveCommand(
        store,
        session,
      ).save(fields: {}, tags: [], observedTagRefs: {});
    } finally {
      session.cancel();
      store.releaseTextCapture(capture);
    }
  }

  Future<void> converge() async {
    await File(
      '${remote.location}/${b.writer}.applog',
    ).copy('${folder.location}/${b.writer}.applog');
    await a.refresh();
    await copy(folder, remote);
    await b.refresh();
    expect(a.rows, b.rows);
  }

  test(
    'stale inline reorder stops before receipt after peer refresh',
    () async {
      final first = await add('First');
      await add('Second');
      await copy(folder, remote);
      await b.refresh();
      final snapshot = a.checklistSnapshot(parent);
      await b.addChecklistItem(parent, 'Incoming third');
      await File(
        '${remote.location}/${b.writer}.applog',
      ).copy('${folder.location}/${b.writer}.applog');
      final before = await File(
        '${folder.location}/${a.writer}.applog',
      ).readAsBytes();
      var prepared = 0;
      await expectLater(
        a.moveChecklistItem(
          first,
          null,
          canCommit: () => a.checklistSnapshot(parent) == snapshot,
          onPrepared: (_) => prepared++,
        ),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      expect(prepared, 0);
      expect(
        await File('${folder.location}/${a.writer}.applog').readAsBytes(),
        before,
      );
      expect(items(a, parent).map((item) => item['title']), [
        'First',
        'Second',
        'Incoming third',
      ]);
    },
  );

  setUp(() async {
    closedA = closedB = false;
    root = await Directory.systemTemp.createTemp('checklist-native-');
    folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    remote = LocalLogFolder(
      (await Directory('${root.path}/remote').create()).path,
    );
    engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    a = await TaskStore.open(folder, '${root.path}/a', textEngine: engine);
    user = const Uuid().v4();
    parent = const Uuid().v4();
    await a.command(user, 'user.created', {'name': 'Synthetic'});
    await a.command(parent, 'task.createdWithText', {
      'title': 'Parent',
      'description': '',
      'assignee': user,
      'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
      'text': seed('Parent', ''),
    });
    await copy(folder, remote);
    b = await TaskStore.open(remote, '${root.path}/b', textEngine: engine);
  });
  tearDown(() async {
    if (!closedA) await a.close();
    if (!closedB) await b.close();
    engine.dispose();
    // Fresh synthetic fixtures only; no existing workspace is used.
    await root.delete(recursive: true);
  });

  test(
    'settled simple completion and both Undo forms match full replay beside copied checklists',
    () async {
      final originalItem = await add('Original checklist item');
      await add('Another original checklist item');
      await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final descriptors = a.unified!.snapshot.tasks
          .where((e) => e.type == 'task.completedWithChecklist')
          .toList();
      final index = ChecklistCopyIndex.build(descriptors.reversed)!;
      final claims =
          (descriptors.single.data['checklist'] as Map)['items'] as List;
      for (final item in claims) {
        final id = (item as Map)['id'] as String;
        final sql = a.db.select(
          "SELECT e.id,i.value FROM ${a.tables.events} e JOIN json_each(json_extract(e.semantic,'\$.data.checklist.items')) i WHERE json_extract(e.semantic,'\$.type')='task.completedWithChecklist' AND json_extract(i.value,'\$.id')=? ORDER BY e.clock,e.writer,e.seq",
          [id],
        );
        expect(index[id].map((v) => v.$1.id), sql.map((r) => r['id']));
        expect(
          index[id].map((v) => v.$2),
          sql.map((r) => jsonDecode(r['value'] as String)),
        );
        expect(() => index[id].clear(), throwsUnsupportedError);
        expect(() => index[id].first.$2['id'] = user, throwsUnsupportedError);
      }
      expect(index[user], isEmpty);
      expect(ChecklistCopyIndex.build(descriptors, maximumClaims: 1), isNull);
      expect(
        ChecklistCopyIndex.build(descriptors, maximumPayloadBytes: 1),
        isNull,
      );
      final plain = const Uuid().v4();
      await a.command(plain, 'task.createdWithText', {
        'title': 'Plain task',
        'description': '',
        'assignee': user,
        'schedule': <String, dynamic>{},
        'text': seed('Plain task', ''),
      });
      final history = a.unified!;
      void oracle() {
        final events = history.snapshot.tasks.toList();
        final revision = TaskStore.canonicalTaskRevision(events);
        expect(
          history.verifiesTaskRevision(history.snapshot, revision),
          isTrue,
        );
        expect(
          history.verifiesTaskRevision(b.unified!.snapshot, revision),
          isFalse,
        );
        expect(
          history.verifiesTaskRevision(history.snapshot, 'different'),
          isFalse,
        );
        expect(
          a.rows,
          TaskStore.validateSemanticHistory(
            events,
            space: a.space,
            writer: a.writer,
            textEngine: engine,
          ),
        );
        final validator = TaskSemanticValidator(
          space: a.space,
          writer: a.writer,
          textEngine: engine,
        );
        try {
          expect(history.snapshot.readyTaskIds, validator.validate(events));
        } finally {
          validator.close();
        }
      }

      oracle();
      final added = const Uuid().v4();
      // Exercise the settled capture path with an explicit ready anchor.
      // First activity against a derived anchor deliberately keeps full replay.
      final firstVisible =
          a.rows.firstWhere((r) => r['kind'] == 'task')['id'] as String;
      if (firstVisible != plain) {
        await a.command(plain, 'task.moved', {'before': firstVisible});
        oracle();
      }
      expect(a.rows.firstWhere((r) => r['kind'] == 'task')['id'], plain);
      final beforeCapture = history.fullTaskReadinessRuns;
      await a.createTasks({added: 'Additional native task'}, user);
      expect(history.fullTaskReadinessRuns, beforeCapture);
      oracle();
      final edited = await a.command(plain, 'task.edited', {
        'schedule': {'dueDate': '2030-05-04'},
      });
      oracle();
      expect((await a.undoOperations([edited.id])).remaining, isEmpty);
      oracle();
      final deleted = await a.command(plain, 'task.deleted', {});
      oracle();
      expect((await a.undoOperations([deleted.id])).remaining, isEmpty);
      oracle();
      final toggled = await a.command(originalItem, 'checklist.itemEdited', {
        'completed': true,
      });
      oracle();
      expect((await a.undoOperations([toggled.id])).remaining, isEmpty);
      oracle();
      final user2 = const Uuid().v4();
      await a.command(user2, 'user.created', {'name': 'Second synthetic user'});
      oracle();
      final assigned = await a.command(plain, 'task.edited', {
        'assignee': user2,
      });
      oracle();
      expect((await a.undoOperations([assigned.id])).remaining, isEmpty);
      oracle();
      final tagged = await a.command(plain, 'task.edited', {
        'tagChanges': {
          'add': ['Synthetic tag'],
          'remove': <String>[],
        },
      });
      oracle();
      final untagged = await a.command(plain, 'task.edited', {
        'tagChanges': {
          'add': <String>[],
          'remove': ['${tagged.id}:0'],
        },
      });
      oracle();
      expect((await a.undoOperations([untagged.id])).remaining, isEmpty);
      oracle();
      final moved = await a.command(plain, 'task.moved', {'before': added});
      oracle();
      expect((await a.undoOperations([moved.id])).remaining, isEmpty);
      oracle();
      final firstItem = await a.addChecklistItem(plain, 'First explicit item');
      oracle();
      final secondItem = await a.addChecklistItem(
        plain,
        'Second explicit item',
        before: firstItem.entity,
      );
      oracle();
      final itemMove = await a.moveChecklistItem(
        firstItem.entity,
        secondItem.entity,
      );
      oracle();
      expect((await a.undoOperations([itemMove.id])).remaining, isEmpty);
      oracle();
      final itemDelete = await a.deleteChecklistItem(firstItem.entity);
      oracle();
      expect((await a.undoOperations([itemDelete.id])).remaining, isEmpty);
      oracle();
      await copy(folder, remote);
      await b.refresh();
      final exactRevision = TaskStore.canonicalTaskRevision(
        history.snapshot.tasks,
      );
      expect(
        TaskStore.canonicalTaskRevision(b.unified!.snapshot.tasks),
        exactRevision,
      );
      expect(
        history.verifiesTaskRevision(b.unified!.snapshot, exactRevision),
        isFalse,
      );
      final beforeInvalid = await folder.read('${a.writer}.applog');
      final userBirth = history.snapshot.tasks.firstWhere(
        (e) => e.type == 'user.created',
      );
      await expectLater(
        a.command(plain, 'task.edited', {
          'tagChanges': {
            'add': <String>[],
            'remove': ['${userBirth.id}:0'],
          },
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a.command(plain, 'task.moved', {'before': user}),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a.moveChecklistItem(firstItem.entity, originalItem),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read('${a.writer}.applog'), beforeInvalid);
      oracle();
      final fullBefore = history.fullTaskReadinessRuns;
      final first = await a.complete(
        plain,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      expect(first.type, 'task.completed');
      oracle();
      expect((await a.undoOperations([first.id])).remaining, isEmpty);
      oracle();
      final second = await a.complete(
        plain,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 2),
      );
      await a.command(plain, 'task.completionUndone', {
        'completion': second.id,
      });
      oracle();
      expect(history.fullTaskReadinessRuns, fullBefore);
      final before = await folder.read('${a.writer}.applog');
      await expectLater(
        a.command(parent, 'task.completed', {
          'completedInstant': '2030-05-03T00:00:00.000000Z',
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read('${a.writer}.applog'), before);
    },
  );

  test(
    'copied-claim staging rollback preserves old state and exact recovery',
    () async {
      await add('Original source');
      final first = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      expect((await a.undoOperations([first.id])).remaining, isEmpty);
      await add('New source after earlier copy');
      final before = jsonEncode(a.rows), sequence = a.unified!.physicalSequence;
      final history = a.unified!,
          profile = a.profileDatabase!,
          attachment = Object();
      await profile.serialize(() async {
        history.attachProjectionInProfileQueue(attachment, (candidate) {
          if (candidate.records.any(
            (r) => r.writer == a.writer && r.sequence > sequence,
          )) {
            throw FormatFailure(
              'Synthetic later projection rejects copied rows',
            );
          }
          return () {};
        });
      });
      try {
        await expectLater(
          a.complete(
            parent,
            localZoneId: 'UTC',
            completionInstant: DateTime.utc(2030, 5, 2),
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(jsonEncode(a.rows), before);
        expect(history.hasPending, isTrue);
        final exact = history.pendingRecords.map((r) => r.encode()).toList();
        await profile.serialize(() async {
          history.detachProjectionInProfileQueue(attachment);
        });
        await history.recoverPrepared();
        expect(history.hasPending, isFalse);
        expect(
          history.snapshot.records
              .where((r) => r.writer == a.writer && r.sequence > sequence)
              .map((r) => r.encode())
              .toList(),
          exact,
        );
        expect(
          a.rows,
          TaskStore.validateSemanticHistory(
            history.snapshot.tasks,
            space: a.space,
            writer: a.writer,
            textEngine: engine,
          ),
        );
        final successor = const Uuid().v5(parent, 'successor');
        expect(a.checklistItems(successor).map((r) => r['title']), [
          'Original source',
          'New source after earlier copy',
        ]);
      } finally {
        await profile.serialize(() async {
          history.detachProjectionInProfileQueue(attachment);
        });
      }
    },
  );

  test(
    'settled checklist Save keeps parent eligibility and native Undo deletion exception',
    () async {
      final item = await add('Original item');
      final capture = await a.captureTaskText(item);
      final session = TaskTextSession(
        capture,
        registerDraftActor: (field, allocation, actor) =>
            a.registerTextDraftActor(capture, field, allocation, actor),
      );
      try {
        session.replace('title', 'Saved item');
        final prepared = session.prepare();
        final deletion = await a.command(parent, 'task.deleted', {});
        final before = await folder.read('${a.writer}.applog');
        var receipts = 0;
        await expectLater(
          a.editNativeTask(
            item,
            prepared.changes,
            onPrepared: (_) => receipts++,
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(receipts, 0);
        expect(await folder.read('${a.writer}.applog'), before);
        expect((await a.undoOperations([deletion.id])).remaining, isEmpty);
        final saved = await TextSaveCommand(
          a,
          session,
        ).save(fields: {}, tags: [], observedTagRefs: {});
        expect(saved.receipt, isNotNull);
        final removed = await a.command(item, 'checklist.itemDeleted', {});
        expect(items(a, parent), isEmpty);
        // Undo of committed text retains the existing policy even while hidden.
        expect(
          (await a.undoOperations([saved.receipt!.id])).remaining,
          isEmpty,
        );
        expect((await a.undoOperations([removed.id])).remaining, isEmpty);
        expect(items(a, parent).single['title'], 'Original item');
      } finally {
        session.cancel();
        a.releaseTextCapture(capture);
      }
    },
  );

  test(
    'unpublished copied-item draft cannot bypass a suppressed parent',
    () async {
      final original = await add('Original copied item');
      final completion = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      final copied = const Uuid().v5(child, 'checklist:$original');
      final capture = await a.captureTaskText(copied);
      final session = TaskTextSession(
        capture,
        registerDraftActor: (field, allocation, actor) =>
            a.registerTextDraftActor(capture, field, allocation, actor),
      );
      try {
        session.replace('title', 'Private copied draft');
        final prepared = session.prepare();
        expect((await a.undoOperations([completion.id])).remaining, isEmpty);
        expect(a.rows.where((r) => r['id'] == child), isEmpty);
        final before = await folder.read('${a.writer}.applog');
        var receipts = 0;
        await expectLater(
          a.editNativeTask(
            copied,
            prepared.changes,
            onPrepared: (_) => receipts++,
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(receipts, 0);
        expect(await folder.read('${a.writer}.applog'), before);
      } finally {
        session.cancel();
        a.releaseTextCapture(capture);
      }
    },
  );

  test(
    'one-level items have native title/notes, completion, order and targeted Undo',
    () async {
      final first = await add('Pack bag', notes: 'Passport\nCharger');
      final second = await add('Lock door');
      expect(a.rows.where((row) => row['kind'] == 'task'), hasLength(1));
      expect(a.rows.any((row) => row['id'] == first), isFalse);
      expect(items(a, parent).map((row) => row['id']), [first, second]);
      expect(items(a, parent).first['completed'], isFalse);
      final checked = await a.command(first, 'checklist.itemEdited', {
        'completed': true,
      });
      final moved = await a.command(second, 'checklist.itemMoved', {
        'before': first,
      });
      expect(items(a, parent).map((row) => row['id']), [second, first]);
      expect(items(a, parent).last['completed'], isTrue);
      final saved = await saveText(
        a,
        first,
        'description',
        'Passport\nTwo chargers',
      );
      expect(items(a, parent).last['description'], 'Passport\nTwo chargers');
      expect((await a.undoOperations([saved.receipt!.id])).remaining, isEmpty);
      expect(items(a, parent).last['description'], 'Passport\nCharger');
      expect(
        (await a.undoOperations([checked.id, moved.id])).remaining,
        isEmpty,
      );
      expect(items(a, parent).map((row) => row['id']), [first, second]);
      expect(items(a, parent).first['completed'], isFalse);
      await a.command(second, 'checklist.itemDeleted', {});
      expect(items(a, parent).map((row) => row['id']), [first]);
    },
  );

  test(
    'nested, non-task parents and cross-parent move anchors append nothing',
    () async {
      final first = await add('First');
      final before = a.db
          .select('SELECT COUNT(*) AS n FROM ${a.tables.events}')
          .single['n'];
      for (final invalidParent in [first, user]) {
        await expectLater(
          add('Nested', owner: invalidParent),
          throwsA(isA<FormatFailure>()),
        );
        expect(
          a.db
              .select('SELECT COUNT(*) AS n FROM ${a.tables.events}')
              .single['n'],
          before,
        );
      }
      await expectLater(
        a.command(parent, 'checklist.itemEdited', {'completed': true}),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a.command(first, 'task.edited', {'schedule': {}}),
        throwsA(isA<FormatFailure>()),
      );
      final other = const Uuid().v4();
      await a.command(other, 'task.created', {
        'title': 'Other',
        'description': '',
        'assignee': user,
      });
      final foreign = await add('Foreign', owner: other);
      final count = a.db
          .select('SELECT COUNT(*) AS n FROM ${a.tables.events}')
          .single['n'];
      await expectLater(
        a.command(first, 'checklist.itemMoved', {'before': foreign}),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        a.db.select('SELECT COUNT(*) AS n FROM ${a.tables.events}').single['n'],
        count,
      );
      await expectLater(
        a.command(first, 'task.textEdited', {
          'changes': <String, dynamic>{},
          'assignee': user,
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        a.db.select('SELECT COUNT(*) AS n FROM ${a.tables.events}').single['n'],
        count,
      );
    },
  );

  test(
    'recurrence copies fresh unchecked items preserving order and native field identities',
    () async {
      final first = await add('Pack', notes: 'Passport');
      final second = await add('Lock');
      await a.command(first, 'checklist.itemEdited', {'completed': true});
      await a.command(second, 'checklist.itemMoved', {'before': first});
      final completion = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      expect(completion.type, 'task.completedWithChecklist');
      final child = const Uuid().v5(parent, 'successor');
      final copiedFirst = const Uuid().v5(child, 'checklist:$first');
      final copiedSecond = const Uuid().v5(child, 'checklist:$second');
      expect(items(a, child).map((row) => row['id']), [
        copiedSecond,
        copiedFirst,
      ]);
      expect(items(a, child).every((row) => row['completed'] == false), isTrue);
      expect(items(a, child).last['description'], 'Passport');
      await saveText(a, copiedFirst, 'description', 'Passport\nTicket');
      await saveText(a, first, 'description', 'Later old occurrence');
      expect(items(a, child).last['description'], 'Passport\nTicket');
      final undone = await a.undoOperations([completion.id]);
      expect(undone.retainedSuccessorCount, 1);
      expect(items(a, child).last['description'], 'Passport\nTicket');
      expect(task(a, parent)['completed'], isFalse);
    },
  );

  test(
    'offline completions union item text and membership while preserving successor edits',
    () async {
      final common = await add('AB', notes: 'AB notes');
      await copy(folder, remote);
      await b.refresh();
      await saveText(a, common, 'title', 'AXB');
      final addedA = await add('Only A');
      final addedB = const Uuid().v4();
      await b.command(addedB, 'checklist.itemCreated', {
        'parent': parent,
        'title': 'Only B',
        'description': '',
        'before': null,
        'text': seed('Only B', ''),
      });
      await saveText(b, common, 'description', 'AYB notes');
      final doneA = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      final childCommon = const Uuid().v5(child, 'checklist:$common');
      await saveText(a, childCommon, 'title', 'AXBY');
      await b.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      await converge();
      final shared = items(
        a,
        child,
      ).singleWhere((row) => row['id'] == childCommon);
      expect(shared['title'], 'AXBY');
      expect(shared['description'], 'AYB notes');
      expect(items(a, child).map((row) => row['id']).toSet(), {
        childCommon,
        const Uuid().v5(child, 'checklist:$addedA'),
        const Uuid().v5(child, 'checklist:$addedB'),
      });
      await a.undoOperations([doneA.id]);
      await converge();
      expect(
        items(
          a,
          child,
        ).singleWhere((row) => row['id'] == childCommon)['description'],
        'AYB notes',
      );
      await saveText(b, common, 'description', 'Old edit after completion');
      await converge();
      expect(
        items(
          a,
          child,
        ).singleWhere((row) => row['id'] == childCommon)['description'],
        'AYB notes',
      );
    },
  );

  test(
    'scalar parent can recur with native checklist without a forced parent text baseline',
    () async {
      final scalar = const Uuid().v4();
      await a.command(scalar, 'task.created', {
        'title': 'Legacy parent',
        'description': 'Legacy notes',
        'assignee': user,
        'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
      });
      final item = await add('Native item', owner: scalar);
      expect(a.sharedTextInitialized, isFalse);
      final completion = await a.complete(
        scalar,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      expect(completion.type, 'task.completedWithChecklist');
      expect(completion.data.containsKey('inheritance'), isFalse);
      final child = const Uuid().v5(scalar, 'successor');
      expect(task(a, child)['title'], 'Legacy parent');
      expect(
        items(a, child).single['id'],
        const Uuid().v5(child, 'checklist:$item'),
      );
      expect(a.sharedTextInitialized, isFalse);
    },
  );

  test(
    'historical recompletion leaves the independently initialized child checklist untouched',
    () async {
      final scalar = const Uuid().v4();
      await a.command(scalar, 'task.created', {
        'title': 'Historical',
        'description': '',
        'assignee': user,
        'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
      });
      final original = await a.complete(
        scalar,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(scalar, 'successor');
      await a.initializeSharedText();
      final childItem = await add('Existing child work', owner: child);
      await a.command(childItem, 'checklist.itemEdited', {'completed': true});
      await a.undoOperations([original.id]);
      await add('Later parent checklist', owner: scalar);
      final before = jsonEncode(items(a, child));
      final again = await a.complete(
        scalar,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 2),
      );
      expect(again.type, 'task.completedKeepingSuccessor');
      expect(jsonEncode(items(a, child)), before);
    },
  );

  test(
    'saved item completion/move/delete protects successor from completion Undo',
    () async {
      final first = await add('One');
      final second = await add('Two');
      final completion = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      final childFirst = const Uuid().v5(child, 'checklist:$first');
      final childSecond = const Uuid().v5(child, 'checklist:$second');
      await a.command(childFirst, 'checklist.itemEdited', {'completed': true});
      await a.command(childSecond, 'checklist.itemMoved', {
        'before': childFirst,
      });
      await a.command(childFirst, 'checklist.itemDeleted', {});
      expect(
        (await a.undoOperations([completion.id])).retainedSuccessorCount,
        1,
      );
      expect(items(a, child).single['id'], childSecond);
    },
  );

  test(
    'late offline copy cannot overwrite a saved child order or checked state',
    () async {
      final first = await add('First');
      final second = await add('Second');
      await copy(folder, remote);
      await b.refresh();
      await b.command(second, 'checklist.itemMoved', {'before': first});
      await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      final copiedFirst = const Uuid().v5(child, 'checklist:$first');
      final copiedSecond = const Uuid().v5(child, 'checklist:$second');
      await a.command(copiedFirst, 'checklist.itemMoved', {'before': null});
      await a.command(copiedSecond, 'checklist.itemEdited', {
        'completed': true,
      });
      await b.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      await converge();
      expect(items(a, child).map((row) => row['id']), [
        copiedSecond,
        copiedFirst,
      ]);
      expect(items(a, child).first['completed'], isTrue);
      await b.command(first, 'checklist.itemDeleted', {});
      await converge();
      expect(items(a, child).map((row) => row['id']), [
        copiedSecond,
        copiedFirst,
      ]);
    },
  );

  test(
    'scalar-mode checklist history also preserves initialized child on historical recompletion',
    () async {
      final scalar = const Uuid().v4();
      await a.command(scalar, 'task.created', {
        'title': 'Legacy',
        'description': '',
        'assignee': user,
        'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
      });
      final originalItem = await add('Original checklist', owner: scalar);
      final original = await a.complete(
        scalar,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(scalar, 'successor');
      await a.initializeSharedText();
      final copied = const Uuid().v5(child, 'checklist:$originalItem');
      await saveText(a, copied, 'title', 'Independent child');
      await a.undoOperations([original.id]);
      await add('Later old item', owner: scalar);
      final before = jsonEncode(task(a, child));
      expect(
        (await a.complete(
          scalar,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 2),
        )).type,
        'task.completedKeepingSuccessor',
      );
      expect(jsonEncode(task(a, child)), before);
    },
  );

  test(
    'copied-item native proofs work through three generations and exact membership cannot be forged',
    () async {
      final original = await add('AB', notes: 'Notes');
      var current = parent, currentItem = original;
      LogEvent? completion;
      for (var generation = 0; generation < 3; generation++) {
        await saveText(a, currentItem, 'title', 'AB $generation');
        completion = await a.complete(
          current,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 1 + generation),
        );
        current = const Uuid().v5(current, 'successor');
        currentItem = const Uuid().v5(current, 'checklist:$currentItem');
        expect(items(a, current).single['title'], 'AB $generation');
        expect(items(a, current).single['completed'], isFalse);
      }
      final malformed =
          jsonDecode(jsonEncode(completion!.data)) as Map<String, dynamic>;
      (malformed['checklist'] as Map)['items'] = [];
      final count = a.db
          .select('SELECT COUNT(*) AS n FROM ${a.tables.events}')
          .single['n'];
      var prepared = false;
      await expectLater(
        a.command(
          completion.entity,
          'task.completedWithChecklist',
          malformed,
          onPrepared: (_) => prepared = true,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(prepared, isFalse);
      expect(
        a.db.select('SELECT COUNT(*) AS n FROM ${a.tables.events}').single['n'],
        count,
      );
      final sourceCapture = await a.captureTaskText(original);
      final copiedCapture = await a.captureTaskText(currentItem);
      expect(
        sourceCapture.fields['title']!.context,
        isNot(copiedCapture.fields['title']!.context),
      );
      a.releaseTextCapture(sourceCapture);
      a.releaseTextCapture(copiedCapture);
    },
  );

  test(
    'untouched copied items follow successor suppression and identical cold/warm cache replay',
    () async {
      await add('One', notes: 'Notes');
      final completion = await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      expect(items(a, child), hasLength(1));
      expect(
        (await a.undoOperations([completion.id])).removedSuccessorCount,
        1,
      );
      expect(a.rows.any((row) => row['id'] == child), isFalse);
      await a.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 2),
      );
      final before = a.rows;
      final bytes = <String, String>{};
      for (final file in await folder.list()) {
        bytes[file.name] = sha256
            .convert(
              await File('${folder.location}/${file.name}').readAsBytes(),
            )
            .toString();
      }
      await a.close();
      closedA = true;
      a = await TaskStore.open(folder, '${root.path}/a', textEngine: engine);
      closedA = false;
      expect(
        a.readFiles,
        greaterThan(0),
        reason: 'Current admission revalidates canonical bytes',
      );
      expect(a.rows, before);
      await a.close();
      closedA = true;
      a = await TaskStore.open(folder, '${root.path}/cold', textEngine: engine);
      closedA = false;
      expect(a.rows, before);
      for (final entry in bytes.entries) {
        expect(
          sha256
              .convert(
                await File('${folder.location}/${entry.key}').readAsBytes(),
              )
              .toString(),
          entry.value,
        );
      }
    },
  );
}
