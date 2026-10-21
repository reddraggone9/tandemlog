import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late LocalLogFolder folder, remoteFolder;
  late TaskStore a, b;
  late String user, other;
  var closedA = false, closedB = false;
  Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
    for (final f in await from.list()) {
      await File('${from.location}/${f.name}').copy('${to.location}/${f.name}');
    }
  }

  Map<String, dynamic> row(TaskStore s, String id) =>
      s.rows.firstWhere((r) => r['id'] == id);
  Future<String> create({
    String title = 'Original',
    List<String> tags = const [],
    Map<String, dynamic> schedule = const {},
  }) async {
    final id = const Uuid().v4();
    await a.command(id, 'task.created', {
      'title': title,
      'description': 'Notes $title',
      'assignee': user,
      'tags': tags,
      'schedule': schedule,
    });
    return id;
  }

  Future<void> converge() async {
    await File(
      '${remoteFolder.location}/${b.writer}.applog',
    ).copy('${folder.location}/${b.writer}.applog');
    await a.refresh();
    await copy(folder, remoteFolder);
    await b.refresh();
    expect(a.rows, b.rows);
  }

  setUp(() async {
    closedA = closedB = false;
    root = await Directory.systemTemp.createTemp('undo-storage-');
    folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    remoteFolder = LocalLogFolder(
      (await Directory('${root.path}/remote').create()).path,
    );
    a = await TaskStore.open(folder, '${root.path}/a');
    user = const Uuid().v4();
    other = const Uuid().v4();
    await a.command(user, 'user.created', {'name': 'Alex'});
    await a.command(other, 'user.created', {'name': 'Blair'});
    await copy(folder, remoteFolder);
    b = await TaskStore.open(remoteFolder, '${root.path}/b');
  });
  tearDown(() async {
    if (!closedA) await a.close();
    if (!closedB) await b.close();
    await root.delete(recursive: true);
  });
  test(
    'bulk Undo restores mixed schedules/assignees/tags and retains newer synced registers',
    () async {
      final first = await create(
        tags: ['home'],
        schedule: {'dueDate': '2030-05-01'},
      );
      final second = await create(
        title: 'Second',
        tags: ['work'],
        schedule: {'dueDate': '2030-05-02'},
      );
      await copy(folder, remoteFolder);
      await b.refresh();
      final receipts = <OperationReceipt>[];
      final result = await a.bulkEdit(
        [first, second],
        BulkTaskEdit(
          assignee: other,
          schedulePatch: {'dueTime': '12:00'},
          addTags: ['bulk'],
          removeTags: ['home'],
        ),
        expectedTaskSnapshot: a.taskSnapshot,
        onPrepared: receipts.add,
      );
      expect(result.succeeded, true);
      expect(a.confirmedOperations(receipts).length, 2);
      await copy(folder, remoteFolder);
      await b.refresh();
      await b.command(first, 'task.edited', {
        'title': 'New remote title',
        'schedule': {'dueDate': '2030-06-01', 'dueTime': '15:00'},
      });
      // Re-add the same label independently: Undo must not erase unseen work.
      await b.command(first, 'task.edited', {
        'tagChanges': {
          'add': ['bulk'],
          'remove': <String>[],
        },
      });
      await converge();
      final originalRaw = receipts.map((r) => r.raw).toList();
      final undo = await a.undoOperations(receipts.map((r) => r.id).toList());
      expect(undo.error, isNull);
      expect(undo.keptNewerChanges, true);
      expect(row(a, first)['title'], 'New remote title');
      expect((row(a, first)['schedule'] as Map)['dueDate'], '2030-06-01');
      expect(row(a, first)['assignee'], user);
      expect(row(a, first)['tags'], ['bulk', 'home']);
      expect(row(a, second)['assignee'], user);
      expect(row(a, second)['tags'], ['work']);
      expect((row(a, second)['schedule'] as Map)['dueDate'], '2030-05-02');
      expect((row(a, second)['schedule'] as Map)['dueTime'], isNull);
      for (var i = 0; i < receipts.length; i++) {
        expect(
          a.db.select("SELECT raw FROM ${a.tables.events} WHERE id=?", [
            receipts[i].id,
          ]).single['raw'],
          originalRaw[i],
        );
      }
      final n = a.db
          .select("SELECT COUNT(*) n FROM ${a.tables.events}")
          .single['n'];
      await a.undoOperations(receipts.map((r) => r.id).toList());
      expect(
        a.db.select("SELECT COUNT(*) n FROM ${a.tables.events}").single['n'],
        n,
      );
      await converge();
    },
  );
  test(
    'completion and reopening Undo preserve successor work and independent completion/deletion',
    () async {
      final id = await create(
        schedule: {'dueDate': '2030-05-01', 'recurrence': 'every day'},
      );
      final complete = await a.complete(
        id,
        completionDay: DateTime.utc(2030, 5, 1),
      );
      final successor = const Uuid().v5(id, 'successor');
      await a.command(successor, 'task.edited', {'title': 'Worked successor'});
      await a.undoOperations([complete.id]);
      expect(row(a, id)['completed'], false);
      expect(row(a, successor)['title'], 'Worked successor');
      await a.complete(id, completionDay: DateTime.utc(2030, 5, 2));
      final reopened = <OperationReceipt>[];
      await a.reopen(id, a.activeCompletionIds(id), onPrepared: reopened.add);
      expect(row(a, id)['completed'], false);
      await a.undoOperations(reopened.map((r) => r.id).toList());
      expect(row(a, id)['completed'], true);
      expect(a.rows.where((r) => r['id'] == successor).length, 1);
      final plain = await create();
      await copy(folder, remoteFolder);
      await b.refresh();
      final localComplete = await a.complete(
        plain,
        completionDay: DateTime.utc(2030, 5, 1),
      );
      await b.complete(plain, completionDay: DateTime.utc(2030, 5, 2));
      await converge();
      await a.undoOperations([localComplete.id]);
      expect(row(a, plain)['completed'], true);
      final localDelete = await a.deleteTask(
        plain,
        expectedTaskSnapshot: a.taskSnapshot,
      );
      await b.deleteTask(plain, expectedTaskSnapshot: b.taskSnapshot);
      await converge();
      await a.undoOperations([localDelete.id]);
      expect(a.rows.where((r) => r['id'] == plain), isEmpty);
      await converge();
    },
  );
  test(
    'move Undo retains later relative move and replays after projection rebuild and reopen',
    () async {
      final first = await create(),
          second = await create(),
          third = await create();
      final moved = await a.moveBefore(third, first);
      await copy(folder, remoteFolder);
      await b.refresh();
      await b.moveBefore(second, first);
      await converge();
      await a.undoOperations([moved.id]);
      final tasks = a.rows
          .where((r) => r['kind'] == 'task')
          .map((r) => r['id'])
          .toList();
      expect(tasks, [second, first, third]);
      await converge();
      final expected = a.rows, writer = a.writer;
      final canonical = {
        for (final f in await folder.list())
          f.name: base64Encode(await folder.read(f.name)),
      };
      await a.rebuildCache();
      await a.close();
      closedA = true;
      a = await TaskStore.open(folder, '${root.path}/a');
      closedA = false;
      expect(a.writer, writer);
      expect(a.rows, expected);
      expect({
        for (final f in await folder.list())
          f.name: base64Encode(await folder.read(f.name)),
      }, canonical);
      await a.close();
      closedA = true;
      a = await TaskStore.open(folder, '${root.path}/a');
      closedA = false;
      expect(
        a.readFiles,
        greaterThan(0),
        reason: 'Current admission revalidates canonical bytes',
      );
      expect(a.rows, expected);
    },
  );
  for (final failAfter in [false, true]) {
    test(
      'Undo failure ${failAfter ? 'after' : 'before'} append confirms only durable prefix and retry is idempotent',
      () async {
        final one = await create(), two = await create();
        final edits = <OperationReceipt>[];
        await a.bulkEdit(
          [one, two],
          BulkTaskEdit(addTags: ['bulk']),
          expectedTaskSnapshot: a.taskSnapshot,
          onPrepared: edits.add,
        );
        await a.close();
        closedA = true;
        final faulty = _FailFolder(folder, failAfter);
        a = await TaskStore.open(faulty, '${root.path}/a');
        closedA = false;
        faulty.countdown = 1;
        final partial = await a.undoOperations(edits.map((r) => r.id).toList());
        expect(partial.error, isA<StateError>());
        expect(partial.undone.length, failAfter ? 2 : 0);
        expect(partial.remaining.length, failAfter ? 0 : 2);
        if (partial.remaining.isNotEmpty) {
          final blocked = await a.undoOperations(partial.remaining);
          expect(
            blocked.error,
            anyOf(isA<WriterGuardFailure>(), isA<FormatFailure>()),
          );
          await faulty.revealPending();
          await a.refresh();
          final retry = await a.undoOperations(partial.remaining);
          expect(retry.error, isNull);
        }
        expect(row(a, one)['tags'], isEmpty);
        expect(row(a, two)['tags'], isEmpty);
        expect(
          a.db
              .select(
                "SELECT * FROM ${a.tables.events} WHERE json_extract(semantic,'\$.type')='task.operationUndone'",
              )
              .length,
          2,
        );
      },
    );
  }
  test(
    'unresolved write blocks new payload until exact delayed record appears',
    () async {
      final id = await create();
      await a.close();
      closedA = true;
      final faulty = _FailFolder(folder, false);
      a = await TaskStore.open(faulty, '${root.path}/a');
      closedA = false;
      faulty.countdown = 1;
      final failed = <OperationReceipt>[];
      await expectLater(
        a.command(id, 'task.edited', {
          'title': 'Failed',
        }, onPrepared: failed.add),
        throwsStateError,
      );
      await expectLater(
        a.command(id, 'task.edited', {'title': 'Different'}),
        throwsA(anyOf(isA<WriterGuardFailure>(), isA<FormatFailure>())),
      );
      await faulty.revealPending();
      await a.refresh();
      expect(a.confirmedOperations(failed), {failed.single.id});
      final saved = <OperationReceipt>[];
      await a.command(id, 'task.edited', {
        'title': 'Saved',
      }, onPrepared: saved.add);
      expect(failed.single.id, isNot(saved.single.id));
      expect(a.confirmedOperations(failed), {failed.single.id});
      expect(a.confirmedOperations(saved), {saved.single.id});
    },
  );
  test(
    'delayed cross-entity Undo target fails transactionally with canonical bytes preserved',
    () async {
      final id = await create(), otherTask = await create();
      final remote = const Uuid().v4(), targetWriter = const Uuid().v4();
      final base = a.unified!.maximumClock!.value + BigInt.from(100);
      List<UnifiedRecord> chain(
        String writer,
        BigInt clock,
        String entity,
        String type,
        Map<String, dynamic> data,
      ) {
        final genesis = unifiedGenesis(
          a.space,
          a.unified!.manifest.epoch,
          writer,
        );
        final header = UnifiedRecord(
          space: a.space,
          epoch: a.unified!.manifest.epoch,
          writer: writer,
          sequence: 1,
          clock: EventClock(clock),
          previousHash: genesis,
          effect: UnifiedEffect.joined(),
          observed: {writer: UnifiedFrontier(0, genesis)},
        );
        final event = LogEvent(
          a.space,
          writer,
          2,
          EventClock(clock + BigInt.one),
          entity,
          type,
          data,
        ).encode(previousHash: header.hash);
        final record = UnifiedRecord(
          space: a.space,
          epoch: a.unified!.manifest.epoch,
          writer: writer,
          sequence: 2,
          clock: EventClock(clock + BigInt.one),
          previousHash: header.hash,
          effect: UnifiedEffect('task', event),
          observed: {writer: UnifiedFrontier(1, header.hash)},
        );
        return [header, record];
      }

      final undo = chain(
        remote,
        base + BigInt.from(2),
        id,
        'task.operationUndone',
        {'operation': '$targetWriter:2'},
      );
      await folder.create(
        unifiedLogName(remote),
        Uint8List.fromList(
          utf8.encode(undo.map((r) => '${r.encode()}\n').join()),
        ),
      );
      await a.refresh();
      final before = a.rows;
      expect(a.unified!.snapshot.pendingEffects, isTrue);
      final target = chain(targetWriter, base, otherTask, 'task.edited', {
        'title': 'Wrong entity',
      });
      final bytes = utf8.encode(target.map((r) => '${r.encode()}\n').join());
      await folder.create(
        unifiedLogName(targetWriter),
        Uint8List.fromList(bytes),
      );
      await expectLater(a.refresh(), throwsA(isA<FormatFailure>()));
      expect(a.rows, before);
      expect(await folder.read(unifiedLogName(targetWriter)), bytes);
      expect(
        a.db.select('SELECT * FROM ${a.tables.events} WHERE id=?', [
          target.last.effect.task!.id,
        ]),
        isEmpty,
      );
    },
  );
}

class _FailFolder implements LogFolder, BoundedLogFolder {
  final LogFolder delegate;
  final bool after;
  int countdown = 0;
  String? delayedName;
  Uint8List? delayedSuffix;
  Future<void> revealPending() async {
    await delegate.append(delayedName!, delayedSuffix!);
    delayedName = null;
    delayedSuffix = null;
  }

  _FailFolder(this.delegate, this.after);
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String n) => delegate.read(n);
  @override
  Future<Uint8List> readBounded(String n, int limit) =>
      (delegate as BoundedLogFolder).readBounded(n, limit);
  @override
  Future<void> create(String n, Uint8List b) => delegate.create(n, b);
  @override
  Future<void> append(String n, Uint8List b) async {
    final fail = countdown > 0 && --countdown == 0;
    if (fail && !after) {
      delayedName = n;
      delayedSuffix = b;
      throw StateError('Injected append failure');
    }
    await delegate.append(n, b);
    if (fail) throw StateError('Injected acknowledgement failure');
  }
}
