import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/workspace_state.dart';
import 'package:tandemlog/storage/workspace_view.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import 'unified_conversion_test.dart' as fixture;
import 'unified_history_test.dart' as builders;

class _Folder extends LocalLogFolder {
  _Folder(super.location);
  int lists = 0;
  bool failRead = false;
  bool failAppend = false;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (failAppend) {
      failAppend = false;
      await super.append(name, Uint8List(0));
      throw const FileSystemException("Synthetic no-byte append failure");
    }
    await super.append(name, bytes);
  }

  @override
  Future<List<LogFileInfo>> list() {
    lists++;
    return super.list();
  }

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (failRead) {
      failRead = false;
      throw const FileSystemException('Synthetic provider read failure');
    }
    return super.readBounded(name, maximumBytes);
  }
}

Future<void> _settings(LocalProfileDatabase profile) async {
  profile.transaction(
    () => profile.database.execute(
      'INSERT INTO protected_settings VALUES (1,?,?)',
      [
        fixture.owner,
        utf8.encode(
          jsonEncode({'writer': fixture.owner, 'appearance': 'system'}),
        ),
      ],
    ),
  );
}

void main() {
  final nativeLibrary = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (nativeLibrary == null || !File(nativeLibrary).existsSync()) {
    throw StateError(
      'workspace_state_test requires the reviewed TANDEMLOG_TEXT_LIBRARY',
    );
  }
  late Directory root;
  late _Folder folder;
  late LocalProfileDatabase profile;
  late UnifiedHistory history;
  late TaskStore tasks;
  late FoodStore food;
  late WorkspaceState state;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-workspace-view-');
    folder = _Folder((await Directory('${root.path}/shared').create()).path);
    final plan = fixture.plan();
    final converted = plan.convert(fixture.ack(plan));
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(utf8.encode(converted.manifest.encode())),
    );
    for (final entry in converted.files.entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    await _settings(profile);
    history = await UnifiedHistory.open(
      folder,
      profile: profile,
      writer: fixture.owner,
    );
    tasks = await TaskStore.openUnified(history);
    food = await FoodStore.openUnified(history);
    state = WorkspaceState(tasks: tasks, food: food);
  });
  tearDown(() async {
    state.close();
    await food.close();
    await tasks.close();
    await history.close();
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'direct shared frame publishes both slices before the first observer',
    () async {
      final before = state.current;
      final observed = <WorkspaceSnapshot>[];
      final remove = state.listen((snapshot) {
        if (snapshot.tasks.rows.any((row) => row['id'] == builders.newTask)) {
          expect(
            snapshot.food!.state.containers.any(
              (item) => item.id == builders.newFood,
            ),
            isTrue,
          );
          expect(snapshot.historyRevision, history.snapshot.revision);
          expect(snapshot.health.hasPendingSave, isFalse);
          observed.add(snapshot);
        }
      });
      await history.appendAtomic([
        builders.taskBuilder(builders.newTask),
        builders.foodBuilder(),
      ]);
      expect(observed, hasLength(1));
      expect(
        before.tasks.rows.any((row) => row['id'] == builders.newTask),
        isFalse,
      );
      expect(
        before.food!.state.containers.any(
          (item) => item.id == builders.newFood,
        ),
        isFalse,
      );
      expect(
        () => state.current.tasks.rows.first['name'] = 'mutation',
        throwsUnsupportedError,
      );
      remove();
    },
  );

  test(
    'settled metadata and plain completion Undo preserve global positions',
    () async {
      final initialOrder = tasks.currentView.rows
          .map((row) => row['id'])
          .toList();
      final rebuilds = tasks.globalOrderRebuilds;
      final edited = await tasks.command(fixture.container, 'task.edited', {
        'schedule': {'dueDate': '2026-10-25'},
      });
      expect((await tasks.undoOperations([edited.id])).error, isNull);
      final completed = await tasks.complete(
        fixture.container,
        completionDay: DateTime.utc(2026, 10, 25),
      );
      expect((await tasks.undoOperations([completed.id])).error, isNull);
      expect(tasks.globalOrderRebuilds, rebuilds);
      expect(tasks.currentView.rows.map((row) => row['id']), initialOrder);
      expect(tasks.currentView.rows, tasks.rows);
    },
  );

  test(
    'delete restoration and manual moves retain ordered full fallback',
    () async {
      await tasks.command(builders.newTask, 'task.created', {
        'title': 'Unrelated Task',
        'description': '',
        'assignee': fixture.peer,
      });
      final initial = tasks.currentView;
      final rebuilds = tasks.globalOrderRebuilds;
      final deleted = await tasks.command(
        fixture.container,
        'task.deleted',
        {},
      );
      expect(
        tasks.currentView.rows.any((row) => row['id'] == fixture.container),
        isFalse,
      );
      final decoded = tasks.displaySnapshotRowsDecoded;
      expect((await tasks.undoOperations([deleted.id])).error, isNull);
      expect(tasks.globalOrderRebuilds, rebuilds);
      expect(tasks.displaySnapshotRowsDecoded - decoded, greaterThan(1));
      expect(
        tasks.currentView.rows.map((row) => row['id']),
        initial.rows.map((row) => row['id']),
      );
      expect(tasks.currentView.rows, tasks.rows);
      final beforeMove = tasks.globalOrderRebuilds;
      final move = await tasks.command(builders.newTask, 'task.moved', {
        'before': fixture.container,
      });
      expect(tasks.globalOrderRebuilds, beforeMove + 1);
      expect(tasks.currentView.rows, tasks.rows);
      final ids = tasks.currentView.rows
          .where((row) => row['kind'] == 'task')
          .map((row) => row['id'])
          .toList();
      expect(
        ids.indexOf(builders.newTask),
        lessThan(ids.indexOf(fixture.container)),
      );
      expect((await tasks.undoOperations([move.id])).error, isNull);
      expect(tasks.globalOrderRebuilds, beforeMove + 2);
      expect(
        tasks.currentView.rows.map((row) => row['id']),
        initial.rows.map((row) => row['id']),
      );
      expect(tasks.currentView.rows, tasks.rows);
    },
  );

  test(
    'point Task edit reuses unrelated display rows and immutable users',
    () async {
      await tasks.command(builders.newTask, 'task.created', {
        'title': 'Unrelated Task',
        'description': '',
        'assignee': fixture.peer,
      });
      final before = state.current.tasks;
      final unchanged = before.rows.singleWhere(
        (row) => row['id'] == builders.newTask,
      );
      final decoded = tasks.displaySnapshotRowsDecoded;
      await tasks.command(fixture.container, 'task.edited', {
        'schedule': {'dueDate': '2026-10-25'},
      });
      final after = state.current.tasks;
      expect(tasks.displaySnapshotRowsDecoded - decoded, 1);
      expect(after.revision, before.revision + 1);
      expect(identical(after.users, before.users), isTrue);
      expect(
        identical(
          after.rows.singleWhere((row) => row['id'] == builders.newTask),
          unchanged,
        ),
        isTrue,
      );
      final changed = after.rows.singleWhere(
        (row) => row['id'] == fixture.container,
      );
      expect((changed['schedule'] as Map)['dueDate'], '2026-10-25');
      expect(
        (before.rows.singleWhere(
              (row) => row['id'] == fixture.container,
            )['schedule']
            as Map)['dueDate'],
        isNull,
      );
      expect(
        () => (changed['schedule'] as Map)['dueDate'] = '2026-10-26',
        throwsUnsupportedError,
      );
      final stable = tasks.displaySnapshotRowsDecoded;
      await state.refresh();
      await food.add(const FoodDetails(name: 'Unrelated delta'), 1);
      await history.renameDevice('Metadata only');
      expect(tasks.displaySnapshotRowsDecoded, stable);
      expect(identical(state.current.tasks, after), isTrue);
    },
  );

  test(
    'failed projection stage cannot publish or mutate a point delta',
    () async {
      final before = state.current.tasks;
      final owner = Object();
      final originalRecordCount = history.snapshot.records.length;
      var fail = false;
      await profile.serialize(() async {
        history.attachProjectionInProfileQueue(owner, (snapshot) {
          if (fail && snapshot.records.length > originalRecordCount) {
            throw StateError('Synthetic stage failure after Task projection');
          }
          return () {};
        });
      });
      fail = true;
      await expectLater(
        tasks.command(fixture.container, 'task.edited', {
          'schedule': {'dueDate': '2026-10-25'},
        }),
        throwsStateError,
      );
      expect(identical(state.current.tasks, before), isTrue);
      expect(identical(tasks.currentView, before), isTrue);
      expect(
        (before.rows.singleWhere(
              (row) => row['id'] == fixture.container,
            )['schedule']
            as Map)['dueDate'],
        isNull,
      );
      fail = false;
      await profile.serialize(
        () async => history.detachProjectionInProfileQueue(owner),
      );
      await history.recoverPrepared();
      expect(
        (state.current.tasks.rows.singleWhere(
              (row) => row['id'] == fixture.container,
            )['schedule']
            as Map)['dueDate'],
        '2026-10-25',
      );
      final accepted = state.current.tasks;
      await state.refresh();
      expect(identical(state.current.tasks, accepted), isTrue);
    },
  );

  test(
    'display replacements preserve nested values, order, and fallback boundary',
    () {
      final before = TaskViewSnapshot.next([
        {'id': 'u', 'kind': 'user', 'name': 'One'},
        {
          'id': 'a',
          'kind': 'task',
          'title': 'A',
          'schedule': {'dueDate': null},
        },
        {
          'id': 'b',
          'kind': 'task',
          'title': 'B',
          'checklist': [
            {'id': 'item', 'title': 'Old'},
          ],
        },
      ], TaskViewSnapshot.empty());
      final same = TaskViewSnapshot.replacing({
        'a': {
          'schedule': {'dueDate': null},
          'title': 'A',
          'kind': 'task',
          'id': 'a',
        },
        'hidden': null,
      }, before);
      expect(identical(same, before), isTrue);
      final mutable = {
        'id': 'b',
        'kind': 'task',
        'title': 'B',
        'checklist': [
          {'id': 'item', 'title': 'New'},
        ],
      };
      final after = TaskViewSnapshot.replacing({'b': mutable}, before)!;
      ((mutable['checklist'] as List).single as Map)['title'] = 'Outside alias';
      expect(
        ((after.rows.last['checklist'] as List).single as Map)['title'],
        'New',
      );
      expect(
        ((before.rows.last['checklist'] as List).single as Map)['title'],
        'Old',
      );
      expect(identical(after.rows[1], before.rows[1]), isTrue);
      expect(identical(after.users, before.users), isTrue);
      expect(
        () => ((after.rows.last['checklist'] as List).single as Map)['title'] =
            'Mutate',
        throwsUnsupportedError,
      );
      final removed = TaskViewSnapshot.replacing({'a': null}, after)!;
      expect(removed.rows.map((row) => row['id']), ['u', 'b']);
      expect(
        TaskViewSnapshot.replacing({'a': before.rows[1]}, removed),
        isNull,
      );
      expect(
        TaskViewSnapshot.replacing({
          'new': {'id': 'new', 'kind': 'task'},
        }, before),
        isNull,
      );
      expect(
        TaskViewSnapshot.replacing({
          'a': {'id': 'b', 'kind': 'task'},
        }, before),
        isNull,
      );
      expect(before.rows.map((row) => row['id']), ['u', 'a', 'b']);
    },
  );

  test(
    'device metadata preserves Tasks users and Food slice identities',
    () async {
      final before = state.current;
      await history.renameDevice('Synthetic kitchen');
      expect(state.current.historyRevision, isNot(before.historyRevision));
      expect(identical(state.current.tasks, before.tasks), isTrue);
      expect(identical(state.current.tasks.users, before.tasks.users), isTrue);
      expect(identical(state.current.food, before.food), isTrue);
      expect(identical(food.state, before.food!.state), isTrue);
    },
  );

  test(
    'durable reservation is visible before callback and exact recovery',
    () async {
      final before = state.current;
      var callback = false;
      final seenPending = <bool>[];
      state.listen(
        (snapshot) => seenPending.add(snapshot.health.hasPendingSave),
      );
      await expectLater(
        tasks.command(
          builders.newTask,
          'user.created',
          {'name': 'Callback user'},
          onPrepared: (_) {
            callback = true;
            expect(state.health.hasPendingTaskSave, isTrue);
            expect(identical(state.current.tasks, before.tasks), isTrue);
            throw StateError('Synthetic callback failure');
          },
        ),
        throwsStateError,
      );
      expect(callback, isTrue);
      expect(seenPending, contains(true));
      expect(state.health.hasPendingSave, isTrue);
      await history.recoverPrepared();
      expect(state.health.hasPendingSave, isFalse);
      expect(
        tasks.currentView.rows.any((row) => row['id'] == builders.newTask),
        isTrue,
      );
      final bytes = await folder.read(unifiedLogName(fixture.owner));
      await history.recoverPrepared();
      expect(await folder.read(unifiedLogName(fixture.owner)), bytes);
    },
  );

  test(
    'read failure and identical retry publish health without changing content',
    () async {
      final before = state.current;
      folder.failRead = true;
      await expectLater(state.refresh(), throwsA(isA<FileSystemException>()));
      expect(state.health.sharedFailure, isNotNull);
      expect(identical(state.current.tasks, before.tasks), isTrue);
      expect(identical(state.current.food, before.food), isTrue);
      await state.refresh();
      expect(state.health.sharedFailure, isNull);
      expect(identical(state.current.tasks, before.tasks), isTrue);
      expect(identical(state.current.food, before.food), isTrue);
    },
  );

  test('zero-candidate occurrence pass scans shared root once', () async {
    final before = folder.lists;
    final planned = tasks.occurrenceDuePlansEvaluated;
    final decoded = tasks.displaySnapshotRowsDecoded;
    final result = await state.refresh(
      migrateOccurrenceDates: true,
      canMigrate: () => true,
    );
    expect(folder.lists - before, 1);
    expect(result.migration!.migrated, 0);
    expect(result.migrationError, isNull);
    expect(tasks.occurrenceDuePlansEvaluated, planned);
    expect(tasks.displaySnapshotRowsDecoded, decoded);
    await food.add(const FoodDetails(name: 'Food-only refresh'), 1);
    await state.refresh(migrateOccurrenceDates: true, canMigrate: () => true);
    expect(tasks.occurrenceDuePlansEvaluated, planned);
    expect(tasks.displaySnapshotRowsDecoded, decoded);
  });

  test(
    'facade detach never closes handles and fresh cohort has a new generation',
    () async {
      final before = state.current;
      var notifications = 0;
      state.listen((_) => notifications++);
      state.close();
      await food.add(const FoodDetails(name: 'Direct Add'), 1);
      expect(notifications, 0);
      final replacement = WorkspaceState(tasks: tasks, food: food);
      expect(
        identical(replacement.current.generation, before.generation),
        isFalse,
      );
      expect(
        replacement.current.food!.state.containers.length,
        before.food!.state.containers.length + 1,
      );
      replacement.close();
      await expectLater(state.refresh(), throwsStateError);
    },
  );

  test('typed immutable views preserve int64 and unchanged user identity', () {
    final users = TaskViewSnapshot.next([
      {'id': 'user', 'kind': 'user', 'name': 'A'},
    ], TaskViewSnapshot.empty());
    final next = TaskViewSnapshot.next([
      ...users.rows,
      {
        'id': 'task',
        'kind': 'task',
        'schedule': {'dueDate': null},
        'checklist': [
          {'title': 'one'},
        ],
      },
    ], users);
    expect(identical(users.users, next.users), isTrue);
    expect(
      () => (next.rows.last['schedule'] as Map)['dueDate'] = '2026-10-20',
      throwsUnsupportedError,
    );
    expect(
      () => ((next.rows.last['checklist'] as List).first as Map)['title'] =
          'changed',
      throwsUnsupportedError,
    );
    expect(
      workspaceValuesEqual(1792372071648809000, 1792372071648809001),
      isFalse,
    );
    expect(workspaceValuesEqual(1, 1.0), isFalse);
  });

  test(
    'reservation SQL poisoning immediately publishes the original shared failure',
    () async {
      final before = state.current;
      Object? original;
      try {
        await profile.serialize(
          () => history.prepareInProfileQueue(
            [builders.taskBuilder(builders.newTask)],
            onReserved: (_) {
              profile.database.close();
              profile.rollbackAfterFailure(
                StateError('Synthetic reservation SQL loss'),
              );
            },
          ),
        );
      } catch (error) {
        original = error;
      }
      expect(original, isA<LocalDatabaseFailure>());
      expect(identical(state.health.sharedFailure, original), isTrue);
      expect(state.health.taskWriteReady, isFalse);
      expect(state.health.foodWriteReady, isFalse);
      expect(identical(state.current.tasks, before.tasks), isTrue);
      expect(identical(state.current.food, before.food), isTrue);
    },
  );

  test(
    'common native intent exposes pending before throwing callback and recovers once',
    () async {
      final engine = NativeTextEngine(libraryPath: nativeLibrary);
      final p = await LocalProfileDatabase.open('${root.path}/native-profile');
      await _settings(p);
      final shared = LocalLogFolder(
        (await Directory('${root.path}/native-shared').create()).path,
      );
      TaskStore? t;
      FoodStore? nativeFood;
      WorkspaceState? session;
      try {
        t = await TaskStore.open(
          shared,
          p.root,
          writerIdentity: fixture.owner,
          profileDatabase: p,
          textEngine: engine,
          initializeNewWorkspaceText: true,
        );
        await t.command(builders.newTask, 'user.created', {
          'name': 'Synthetic native user',
        });
        nativeFood = await FoodStore.openUnified(t.unified!);
        session = WorkspaceState(tasks: t, food: nativeFood);
        final before = session.current.tasks;
        OperationReceipt? receipt;
        const id = '77777777-7777-4777-8777-777777777777';
        await expectLater(
          t.command(
            id,
            'task.createdWithText',
            {
              'assignee': builders.newTask,
              'title': 'Pending native',
              'description': '',
              'text': {
                'adapter': 1,
                'codec': 'yrs-v1',
                'seeds': {
                  'title': sha256
                      .convert(engine.seedText('Pending native').bytes)
                      .toString(),
                  'description': sha256
                      .convert(engine.seedText('').bytes)
                      .toString(),
                },
              },
            },
            onPrepared: (prepared) {
              receipt = prepared;
              expect(session!.health.hasPendingTaskSave, isTrue);
              expect(identical(session.current.tasks, before), isTrue);
              throw StateError('Synthetic native callback failure');
            },
          ),
          throwsStateError,
        );
        expect(session.health.hasPendingTaskSave, isTrue);
        expect(t.pendingTextOperations.single.raw, receipt!.raw);
        expect(session.health.foodWriteReady, isFalse);
        await expectLater(
          nativeFood.add(const FoodDetails(name: "Blocked pending Food"), 1),
          throwsA(anyOf(isA<FormatFailure>(), isA<WriterGuardFailure>())),
        );

        expect(session.health.hasPendingTaskSave, isTrue);
        expect(session.current.food!.state.containers, isEmpty);
        await t.retryTextOperation(receipt!);
        expect(session.health.hasPendingTaskSave, isFalse);
        expect(
          session.current.tasks.rows.where((row) => row['id'] == id),
          hasLength(1),
        );
        final bytes = await shared.read('${fixture.owner}.applog');
        await t.retryTextOperation(receipt!);
        expect(await shared.read('${fixture.owner}.applog'), bytes);
      } finally {
        session?.close();
        await nativeFood?.close();
        await t?.close();
        await p.close();
        engine.dispose();
      }
    },
  );
}
