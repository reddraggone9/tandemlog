import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
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
      '${remote.location}/${b.writer}.jsonl',
    ).copy('${folder.location}/${b.writer}.jsonl');
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
        '${remote.location}/${b.writer}.jsonl',
      ).copy('${folder.location}/${b.writer}.jsonl');
      final before = await File(
        '${folder.location}/${a.writer}.jsonl',
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
        await File('${folder.location}/${a.writer}.jsonl').readAsBytes(),
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
          .select('SELECT COUNT(*) AS n FROM events')
          .single['n'];
      for (final invalidParent in [first, user]) {
        await expectLater(
          add('Nested', owner: invalidParent),
          throwsA(isA<FormatFailure>()),
        );
        expect(
          a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
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
      final count = a.db.select('SELECT COUNT(*) AS n FROM events').single['n'];
      await expectLater(
        a.command(first, 'checklist.itemMoved', {'before': foreign}),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
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
        a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
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
        completionDay: DateTime(2030, 5, 1),
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
        completionDay: DateTime(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      final childCommon = const Uuid().v5(child, 'checklist:$common');
      await saveText(a, childCommon, 'title', 'AXBY');
      await b.complete(parent, completionDay: DateTime(2030, 5, 1));
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
        completionDay: DateTime(2030, 5, 1),
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
        completionDay: DateTime(2030, 5, 1),
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
        completionDay: DateTime(2030, 5, 2),
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
        completionDay: DateTime(2030, 5, 1),
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
      await a.complete(parent, completionDay: DateTime(2030, 5, 1));
      final child = const Uuid().v5(parent, 'successor');
      final copiedFirst = const Uuid().v5(child, 'checklist:$first');
      final copiedSecond = const Uuid().v5(child, 'checklist:$second');
      await a.command(copiedFirst, 'checklist.itemMoved', {'before': null});
      await a.command(copiedSecond, 'checklist.itemEdited', {
        'completed': true,
      });
      await b.complete(parent, completionDay: DateTime(2030, 5, 1));
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
        completionDay: DateTime(2030, 5, 1),
      );
      final child = const Uuid().v5(scalar, 'successor');
      await a.initializeSharedText();
      final copied = const Uuid().v5(child, 'checklist:$originalItem');
      await saveText(a, copied, 'title', 'Independent child');
      await a.undoOperations([original.id]);
      await add('Later old item', owner: scalar);
      final before = jsonEncode(task(a, child));
      expect(
        (await a.complete(scalar, completionDay: DateTime(2030, 5, 2))).type,
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
          completionDay: DateTime(2030, 5, 1 + generation),
        );
        current = const Uuid().v5(current, 'successor');
        currentItem = const Uuid().v5(current, 'checklist:$currentItem');
        expect(items(a, current).single['title'], 'AB $generation');
        expect(items(a, current).single['completed'], isFalse);
      }
      final malformed =
          jsonDecode(jsonEncode(completion!.data)) as Map<String, dynamic>;
      (malformed['checklist'] as Map)['items'] = [];
      final count = a.db.select('SELECT COUNT(*) AS n FROM events').single['n'];
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
        a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
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
        completionDay: DateTime(2030, 5, 1),
      );
      final child = const Uuid().v5(parent, 'successor');
      expect(items(a, child), hasLength(1));
      expect(
        (await a.undoOperations([completion.id])).removedSuccessorCount,
        1,
      );
      expect(a.rows.any((row) => row['id'] == child), isFalse);
      await a.complete(parent, completionDay: DateTime(2030, 5, 2));
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
      expect(a.readFiles, 0);
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
