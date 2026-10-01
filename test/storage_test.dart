import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late LocalLogFolder aFolder, bFolder;
  TaskStore? a, b;
  late DateTime testNow;
  Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
    for (final f in await from.list()) {
      await File('${from.location}/${f.name}').copy('${to.location}/${f.name}');
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-test');
    await Directory('${root.path}/a').create();
    await Directory('${root.path}/b').create();
    aFolder = LocalLogFolder('${root.path}/a');
    bFolder = LocalLogFolder('${root.path}/b');
    testNow = DateTime.now().toUtc();
    a = await TaskStore.open(
      aFolder,
      '${root.path}/private-a',
      now: () => testNow,
    );
    await copy(aFolder, bFolder);
    b = await TaskStore.open(
      bFolder,
      '${root.path}/private-b',
      now: () => testNow,
    );
  });
  tearDown(() async {
    await a?.close();
    await b?.close();
    await root.delete(recursive: true);
  });
  Future<String> task() async {
    final id = const Uuid().v4();
    final user = const Uuid().v4();
    await a!.command(user, 'user.created', {'name': 'Lee'});
    await a!.command(id, 'task.created', {
      'title': 'Groceries',
      'description': '',
      'assignee': user,
    });
    return id;
  }

  Map<String, dynamic> state(TaskStore store, String id) =>
      store.rows.firstWhere((r) => r['id'] == id);

  test(
    'local task deletion targeting user rejects before canonical append',
    () async {
      final id = await task();
      final user = state(a!, id)['assignee'] as String;
      final before = await aFolder.read('${a!.writer}.jsonl');
      final snapshot = a!.taskSnapshot;
      await expectLater(
        a!.deleteTask(user, expectedTaskSnapshot: snapshot),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), before);
      expect(a!.taskSnapshot, snapshot);
      expect(state(a!, user)['kind'], 'user');
    },
  );

  test(
    'delayed remote user creation resolves pending task deletion as transactional error',
    () async {
      final remote = const Uuid().v4(), user = const Uuid().v4();
      final deletion = LogEvent(
        a!.space,
        remote,
        1,
        testClock(1, 0),
        user,
        'task.deleted',
        {},
      );
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${deletion.encode()}\n')),
      );
      await a!.refresh();
      expect(a!.hasEntity(user), isFalse);
      expect(
        a!.db.select('SELECT id FROM events WHERE id=?', [deletion.id]).length,
        1,
      );
      final checkpoint = Map<String, Object?>.from(
        a!.db.select('SELECT * FROM streams WHERE name=?', [
          '$remote.jsonl',
        ]).single,
      );
      final creation = LogEvent(
        a!.space,
        remote,
        2,
        testClock(2, 0),
        user,
        'user.created',
        {'name': 'Delayed user'},
      );
      await aFolder.append(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${creation.encode()}\n')),
      );
      final canonical = await aFolder.read('$remote.jsonl');
      await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
      expect(a!.hasEntity(user), isFalse);
      expect(
        a!.db.select('SELECT id FROM events WHERE id=?', [creation.id]),
        isEmpty,
      );
      expect(
        a!.db.select('SELECT * FROM streams WHERE name=?', [
          '$remote.jsonl',
        ]).single,
        checkpoint,
      );
      expect(await aFolder.read('$remote.jsonl'), canonical);
      await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
    },
  );

  for (final operation in ['edit', 'delete', 'move']) {
    test(
      'bulk $operation reconciles durable append after refresh failure before retry',
      () async {
        final first = await task();
        final second = const Uuid().v4(), anchor = const Uuid().v4();
        for (final id in [second, anchor]) {
          await a!.command(id, 'task.created', {
            'title': id,
            'description': '',
            'assignee': state(a!, first)['assignee'],
          });
        }
        await a!.close();
        a = null;
        final transport = _FailRefreshAfterAppendFolder(aFolder);
        a = await TaskStore.open(transport, '${root.path}/private-a');
        Future<BulkTaskResult> run(List<String> ids) {
          final snapshot = a!.taskSnapshot;
          return switch (operation) {
            'edit' => a!.bulkEdit(
              ids,
              BulkTaskEdit(addTags: ['bulk']),
              expectedTaskSnapshot: snapshot,
            ),
            'delete' => a!.deleteTasks(ids, expectedTaskSnapshot: snapshot),
            _ => a!.moveBlockBefore(
              ids,
              null,
              expectedTaskSnapshot: snapshot,
              canCommit: () => true,
            ),
          };
        }

        final count =
            a!.db.select('SELECT COUNT(*) AS n FROM events').single['n'] as int;
        transport.failNext = true;
        final partial = await run([first, second]);
        expect(partial.error, isA<StateError>());
        expect(partial.committedIds, isEmpty);
        expect(partial.remainingIds, [first, second]);
        // Append succeeded but the disposable cache did not acknowledge it.
        expect(
          a!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          count,
        );
        await a!.refresh();
        expect(
          a!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          count + 1,
        );
        final appended = LogEvent.decode(
          a!.db
                  .select('SELECT raw FROM events ORDER BY seq DESC LIMIT 1')
                  .single['raw']
              as String,
        );
        expect(appended.entity, first);
        // Reconcile the uncertain first task from canonical history before retry.
        final retryIds = partial.remainingIds
            .where((id) => id != appended.entity)
            .toList();
        final retry = await run(retryIds);
        expect(retry.succeeded, isTrue);
        expect(
          a!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          count + 2,
        );
        if (operation == 'edit') {
          for (final id in [first, second]) {
            expect(state(a!, id)['tags'], ['bulk']);
            expect((state(a!, id)['tagRefs'] as Map).length, 1);
          }
          final repeat = await run([first, second]);
          expect(repeat.succeeded, isTrue);
          expect(
            a!.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
            count + 2,
          );
        } else if (operation == 'delete') {
          expect(
            a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']),
            [anchor],
          );
          await expectLater(
            a!.command(first, 'task.edited', {'title': 'Revive'}),
            throwsA(isA<FormatFailure>()),
          );
        } else {
          expect(
            a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']),
            [anchor, first, second],
          );
          expect(
            a!.db
                .select(
                  "SELECT COUNT(*) AS n FROM events WHERE json_extract(raw,'\$.type')='task.moved'",
                )
                .single['n'],
            2,
          );
        }
        final finalSnapshot = a!.taskSnapshot;
        await a!.close();
        a = await TaskStore.open(aFolder, '${root.path}/private-a');
        expect(a!.taskSnapshot, finalSnapshot);
      },
    );
  }

  test(
    'bulk patch preserves mixed fields and observed tags; invalid patch writes nothing',
    () async {
      final first = await task();
      final second = const Uuid().v4();
      await a!.command(second, 'task.created', {
        'title': 'Second',
        'description': 'Keep',
        'assignee': state(a!, first)['assignee'],
        'schedule': {'dueDate': '2026-10-10', 'dueMinDays': 5},
        'tags': ['keep', 'remove'],
      });
      await a!.command(first, 'task.edited', {
        'schedule': {'dueDate': '2026-10-05', 'dueMinDays': 1},
      });
      final snapshot = a!.taskSnapshot;
      await expectLater(
        a!.bulkEdit(
          [first, second],
          BulkTaskEdit(schedulePatch: {'dueMaxDays': 2}),
          expectedTaskSnapshot: snapshot,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(a!.taskSnapshot, snapshot);
      final result = await a!.bulkEdit(
        [first, second],
        BulkTaskEdit(
          schedulePatch: {'dueMaxDays': 8},
          addTags: ['new'],
          removeTags: ['remove'],
        ),
        expectedTaskSnapshot: snapshot,
      );
      expect(result.succeeded, isTrue);
      expect((state(a!, first)['schedule'] as Map)['dueDate'], '2026-10-05');
      expect((state(a!, second)['schedule'] as Map)['dueDate'], '2026-10-10');
      expect((state(a!, second)['schedule'] as Map)['dueMinDays'], 5);
      expect(state(a!, second)['description'], 'Keep');
      expect(state(a!, second)['tags'], ['keep', 'new']);
    },
  );

  test(
    'bulk guard reports partial progress and retry; block uses global order',
    () async {
      final first = await task();
      final ids = [first];
      for (var i = 0; i < 3; i++) {
        final id = const Uuid().v4();
        ids.add(id);
        await a!.command(id, 'task.created', {
          'title': '$i',
          'description': '',
          'assignee': state(a!, first)['assignee'],
        });
      }
      var checks = 0;
      final partial = await a!.bulkEdit(
        ids,
        BulkTaskEdit(addTags: ['bulk']),
        expectedTaskSnapshot: a!.taskSnapshot,
        canCommit: () => ++checks <= 2,
      );
      expect(partial.committedIds, [first]);
      expect(partial.remainingIds, ids.sublist(1));
      expect(partial.error, isA<StaleTaskSnapshot>());
      final retry = await a!.bulkEdit(
        partial.remainingIds,
        BulkTaskEdit(addTags: ['bulk']),
        expectedTaskSnapshot: a!.taskSnapshot,
      );
      expect(retry.succeeded, isTrue);
      final moved = await a!.moveBlockBefore(
        [ids[2], first],
        null,
        expectedTaskSnapshot: a!.taskSnapshot,
        canCommit: () => true,
      );
      expect(moved.succeeded, isTrue);
      expect(a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        ids[1],
        ids[3],
        first,
        ids[2],
      ]);
    },
  );

  test(
    'offline edits and completions cannot resurrect deletion; successor survives restart',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every day'},
      });
      await a!.complete(id, completionDay: DateTime.utc(2026, 10, 1));
      final successor = const Uuid().v5(id, 'successor');
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.deleteTask(id, expectedTaskSnapshot: a!.taskSnapshot);
      await b!.command(id, 'task.edited', {'title': 'Remote later'});
      await b!.complete(id, completionDay: DateTime.utc(2026, 10, 2));
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows.any((r) => r['id'] == id), isFalse);
      expect(a!.hasEntity(id), isTrue);
      expect(state(a!, successor)['title'], state(b!, successor)['title']);
      await expectLater(
        a!.command(id, 'task.edited', {'title': 'Resurrect'}),
        throwsA(isA<FormatFailure>()),
      );
      final before = a!.taskSnapshot;
      await a!.close();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.taskSnapshot, before);
      expect(a!.rows.any((r) => r['id'] == successor), isTrue);
    },
  );

  test(
    'stale bulk and invalid selections fail before any durable command',
    () async {
      final id = await task();
      final old = a!.taskSnapshot;
      await a!.command(id, 'task.edited', {'description': 'changed'});
      await expectLater(
        a!.deleteTasks([id], expectedTaskSnapshot: old),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      final snapshot = a!.taskSnapshot;
      await expectLater(
        a!.deleteTasks([id, const Uuid().v4()], expectedTaskSnapshot: snapshot),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a!.moveBlockBefore(
          [id],
          id,
          expectedTaskSnapshot: snapshot,
          canCommit: () => true,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(a!.taskSnapshot, snapshot);
    },
  );

  test(
    'guarded move rejects changes arriving inside its refresh without append',
    () async {
      final id = await task();
      final second = const Uuid().v4();
      await a!.command(second, 'task.created', {
        'title': 'Second task',
        'description': '',
        'assignee': state(a!, id)['assignee'],
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.close();
      a = null;
      final transport = _OnNextListFolder(aFolder);
      a = await TaskStore.open(
        transport,
        '${root.path}/private-a',
        now: () => testNow,
      );
      for (final change in <Future<void> Function()>[
        () async {
          await b!.command(id, 'task.edited', {
            'schedule': {'startDate': '2026-10-01', 'dueDate': '2026-10-02'},
          });
        },
        () async {
          await b!.moveBefore(id, null);
        },
        () async {
          await b!.complete(id, completionDay: DateTime.utc(2026, 10, 2));
        },
      ]) {
        final snapshot = a!.taskSnapshot;
        final before = await aFolder.read('${a!.writer}.jsonl');
        await change();
        transport.beforeNextList = () async {
          await File(
            '${bFolder.location}/${b!.writer}.jsonl',
          ).copy('${aFolder.location}/${b!.writer}.jsonl');
        };
        await expectLater(
          a!.moveBefore(second, id, expectedTaskSnapshot: snapshot),
          throwsA(isA<StaleTaskSnapshot>()),
        );
        expect(await aFolder.read('${a!.writer}.jsonl'), before);
        expect(a!.taskSnapshot, isNot(snapshot));
      }
      final timeSnapshot = a!.taskSnapshot;
      final timeBytes = await aFolder.read('${a!.writer}.jsonl');
      var stillEligible = true;
      transport.beforeNextList = () async {
        stillEligible = false;
      };
      await expectLater(
        a!.moveBefore(
          id,
          second,
          expectedTaskSnapshot: timeSnapshot,
          canCommit: () => stillEligible,
        ),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      expect(
        a!.taskSnapshot,
        timeSnapshot,
        reason: 'Only caller-owned time/view conditions changed.',
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), timeBytes);
      final snapshot = a!.taskSnapshot;
      await b!.command(const Uuid().v4(), 'user.created', {
        'name': 'Another user',
      });
      transport.beforeNextList = () async {
        await File(
          '${bFolder.location}/${b!.writer}.jsonl',
        ).copy('${aFolder.location}/${b!.writer}.jsonl');
      };
      await a!.moveBefore(id, second, expectedTaskSnapshot: snapshot);
      expect(
        a!.rows.where((row) => row['kind'] == 'task').map((row) => row['id']),
        [id, second],
      );
    },
  );

  test(
    'typed due bounds are atomic across offline edits and rebuild',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'dueMinDays': 1, 'dueMaxDays': 3},
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-02', 'dueMinDays': 4, 'dueMaxDays': 8},
      });
      testNow = testNow.add(const Duration(milliseconds: 1));
      await b!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-03', 'dueMinDays': 2, 'dueMaxDays': 2},
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      expect(state(a!, id)['schedule'], containsPair('dueMinDays', 2));
      expect(state(a!, id)['schedule'], containsPair('dueMaxDays', 2));
      expect(state(a!, id)['schedule'], containsPair('dueDate', '2026-10-03'));
      final before = await aFolder.read('${a!.writer}.jsonl');
      for (final bounds in [
        {'dueMinDays': 3, 'dueMaxDays': 2},
        {'dueMinDays': '2'},
        {'dueMaxDays': 2.5},
        {'dueMaxDays': 9223372036854775807},
      ]) {
        await expectLater(
          a!.command(id, 'task.edited', {'schedule': bounds}),
          throwsA(isA<FormatFailure>()),
        );
      }
      for (final tag in [
        'due-min-2-days',
        '#due-max-1-day',
        'start-time-0930',
      ]) {
        await expectLater(
          a!.command(id, 'task.tagsChanged', {
            'add': [tag],
            'remove': <String>[],
          }),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(await aFolder.read('${a!.writer}.jsonl'), before);
      await a!.command(id, 'task.tagsChanged', {
        'add': ['Due-min-2-days', 'ordinary'],
        'remove': <String>[],
      });
      final expected = a!.rows;
      await a!.close();
      a = null;
      await File('${root.path}/private-a/cache.sqlite').delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
    },
  );

  test(
    'failed obsolete-cache replay preserves identity and prior stream guards on retry',
    () async {
      final id = await task();
      final expected = a!.rows;
      final writer = a!.writer;
      final original = await aFolder.read('$writer.jsonl');
      final manifest = await aFolder.read('tandemlog-space.json');
      a!.db.execute('PRAGMA user_version=6');
      await a!.close();
      a = null;
      final foreign = const Uuid().v4();
      final unknown = LogEvent(
        jsonDecode(utf8.decode(manifest))['id'],
        foreign,
        1,
        testClock(1, 0),
        const Uuid().v4(),
        'future.event',
        {},
      );
      final file = File('${aFolder.location}/$foreign.jsonl');
      await file.writeAsString('${unknown.encode()}\n');
      final unknownBytes = await file.readAsBytes();
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(isA<FormatFailure>()),
      );
      expect(await file.readAsBytes(), unknownBytes);
      expect(await aFolder.read('$writer.jsonl'), original);
      await File(
        '${aFolder.location}/tandemlog-space.json',
      ).writeAsString(jsonEncode({'v': 2, 'id': const Uuid().v4()}));
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.message,
            'identity',
            contains('identity changed'),
          ),
        ),
      );
      await File(
        '${aFolder.location}/tandemlog-space.json',
      ).writeAsBytes(manifest);
      await File('${aFolder.location}/$writer.jsonl').delete();
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.message,
            'missing',
            contains('Previously imported log'),
          ),
        ),
      );
      await File('${aFolder.location}/$writer.jsonl').writeAsBytes(original);
      // The test explicitly removes only its unsupported, never-ingested stream.
      await file.delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.writer, writer);
      expect(a!.rows, expected);
      expect(state(a!, id)['title'], 'Groceries');
      expect(await aFolder.read('$writer.jsonl'), original);
      expect(
        await Directory('${root.path}/private-a')
            .list()
            .where((file) => file.uri.pathSegments.last.startsWith('cache-v6-'))
            .length,
        1,
      );
    },
  );

  test(
    'future caches and v1 canonical protocol are retained and not auto-converted',
    () async {
      await task();
      a!.db.execute('PRAGMA user_version=99');
      await a!.close();
      a = null;
      final cache = File('${root.path}/private-a/cache.sqlite');
      final before = await cache.readAsBytes();
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.message,
            'future',
            contains('newer app'),
          ),
        ),
      );
      expect(await cache.readAsBytes(), before);
      final oldManifest =
          jsonDecode(utf8.decode(await aFolder.read('tandemlog-space.json')))
              as Map;
      oldManifest['v'] = 1;
      await File(
        '${aFolder.location}/tandemlog-space.json',
      ).writeAsString(jsonEncode(oldManifest));
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/fresh-cache'),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.message,
            'protocol',
            contains('older prerelease format (v1)'),
          ),
        ),
      );
    },
  );

  test(
    'known obsolete cache rebuilds canonical state and retains backup',
    () async {
      final id = await task();
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      a!.db.execute('PRAGMA user_version=4');
      a!.db.execute('UPDATE views SET raw=? WHERE id=?', [
        jsonEncode({'id': id, 'kind': 'future-kind', 'futureField': []}),
        id,
      ]);
      await a!.close();
      a = null;
      final writerBefore = await File(
        '${root.path}/private-a/writer-id',
      ).readAsString();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['kind'], 'task');
      expect(state(a!, id)['title'], 'Groceries');
      expect(a!.readFiles, 1);
      expect(
        await File('${root.path}/private-a/writer-id').readAsString(),
        writerBefore,
      );
      final backups = await Directory('${root.path}/private-a')
          .list()
          .where((file) => file.uri.pathSegments.last.startsWith('cache-v4-'))
          .toList();
      expect(backups, hasLength(1));
      expect(await (backups.single as File).length(), greaterThan(0));
      a!.db.execute('ATTACH DATABASE ? AS retained', [backups.single.path]);
      expect(
        a!.db.select('SELECT raw FROM retained.views WHERE id=?', [
          id,
        ]).single['raw'],
        contains('future-kind'),
      );
      a!.db.execute('DETACH DATABASE retained');

      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.readFiles, 0);
      expect(
        await aFolder.read(
          '${jsonDecode(utf8.decode(bytes).split('\n').first)['writer']}.jsonl',
        ),
        bytes,
      );
      final old =
          jsonDecode(utf8.decode(bytes).split('\n').first)
              as Map<String, dynamic>;
      old['type'] = 'future.event';
      old['data'] = {'futureField': []};
      await File(
        '${aFolder.location}/${old['writer']}.jsonl',
      ).writeAsString('${jsonEncode(old)}\n');
      final rejectedBytes = await aFolder.read('${old['writer']}.jsonl');
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/fresh-cache'),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${old['writer']}.jsonl'), rejectedBytes);
    },
  );

  test(
    'reopen targets observed completions, is idempotent and survives restart',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.command(id, 'task.completed', {});
      await b!.command(id, 'task.completed', {});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      final observed = a!.activeCompletionIds(id);
      expect(observed, hasLength(2));
      await a!.reopen(id, observed);
      expect(state(a!, id)['completed'], isFalse);
      final bytes = await File(
        '${aFolder.location}/${a!.writer}.jsonl',
      ).readAsString();
      await a!.reopen(id, observed);
      expect(
        await File('${aFolder.location}/${a!.writer}.jsonl').readAsString(),
        bytes,
      );
      // A completion unseen by this reopen survives synchronization.
      await b!.command(id, 'task.completed', {});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      expect(state(a!, id)['completed'], isTrue);
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id), state(b!, id));
      await a!.reopen(id, a!.activeCompletionIds(id));
      await a!.close();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], isFalse);
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id), state(b!, id));
    },
  );

  test('reopen refresh does not expand the observed target set', () async {
    final id = await task();
    await copy(aFolder, bFolder);
    await b!.refresh();
    await a!.command(id, 'task.completed', {});
    final observed = a!.activeCompletionIds(id);
    final unseen = await b!.command(id, 'task.completed', {});
    await File(
      '${bFolder.location}/${b!.writer}.jsonl',
    ).copy('${aFolder.location}/${b!.writer}.jsonl');
    await a!.reopen(id, observed);
    expect(a!.activeCompletionIds(id), [unseen.id]);
    expect(state(a!, id)['completed'], isTrue);
  });

  test('partial reopen retries without duplicating a committed undo', () async {
    final id = await task();
    await a!.command(id, 'task.completed', {});
    await a!.command(id, 'task.completed', {});
    final observed = a!.activeCompletionIds(id);
    await a!.close();
    final failing = _FailAfterAppendFolder(aFolder);
    a = await TaskStore.open(failing, '${root.path}/private-a');
    failing.failNext = true;
    await expectLater(a!.reopen(id, observed), throwsStateError);
    await a!.reopen(id, observed);
    expect(state(a!, id)['completed'], isFalse);
    final events = a!.db
        .select('SELECT raw FROM events')
        .map((r) => LogEvent.decode(r['raw'] as String));
    expect(
      events.where((e) => e.type == 'task.completionUndone'),
      hasLength(2),
    );
  });

  test(
    'restart retains state and unchanged files avoid parsing/replay',
    () async {
      final id = await task();
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'Groceries');
      expect(a!.readFiles, 0);
    },
  );
  test(
    'cache deletion rebuilds exact projection and writer stays stable',
    () async {
      final id = await task();
      final expected = a!.rows;
      final writer = a!.writer;
      await a!.close();
      a = null;
      await File('${root.path}/private-a/cache.sqlite').delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
      expect(a!.writer, writer);
      await a!.command(id, 'task.edited', {'title': 'Updated'});
      expect(state(a!, id)['title'], 'Updated');
    },
  );
  test(
    'offline independent fields, duplicate transport and atomic replacement converge',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.command(id, 'task.edited', {'title': 'Buy oats'});
      await b!.command(id, 'task.edited', {'description': 'Large bag'});
      // Exchange only each owning writer's stream; emulate rename replacement.
      final temp = File('${aFolder.location}/incoming.tmp');
      await File('${bFolder.location}/${b!.writer}.jsonl').copy(temp.path);
      await temp.rename('${aFolder.location}/${b!.writer}.jsonl');
      await File(
        '${aFolder.location}/${a!.writer}.jsonl',
      ).copy('${bFolder.location}/${a!.writer}.jsonl');
      await a!.refresh();
      await b!.refresh();
      await a!.refresh();
      expect(a!.rows, b!.rows);
      expect(state(a!, id)['title'], 'Buy oats');
      expect(state(a!, id)['description'], 'Large bag');
    },
  );
  test(
    'concurrent completion survives targeted undo from another user',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final completion = await a!.command(id, 'task.completed', {});
      await b!.command(id, 'task.completed', {});
      await a!.command(id, 'task.completionUndone', {
        'completion': completion.id,
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      expect(state(a!, id)['completed'], true);
    },
  );
  test(
    'unknown version blocks import without checkpoint advancement',
    () async {
      await task();
      final remote = const Uuid().v4();
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('{"v":99}\n')),
      );
      final before = a!.rows;
      await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
      expect(a!.rows, before);
      expect(
        a!.db.select('SELECT * FROM streams WHERE name=?', ['$remote.jsonl']),
        isEmpty,
      );
    },
  );
  test('malformed complete records are preserved and block writes', () async {
    final id = await task();
    final remote = const Uuid().v4();
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('not-json\n')),
    );
    await expectLater(
      a!.command(id, 'task.completed', {}),
      throwsA(isA<FormatFailure>()),
    );
    expect(utf8.decode(await aFolder.read('$remote.jsonl')), 'not-json\n');
  });
  test('incomplete remote tail is retried after completion', () async {
    final remote = const Uuid().v4();
    final id = const Uuid().v4();
    final raw = LogEvent(
      a!.space,
      remote,
      1,
      testClock(1, 0),
      id,
      'user.created',
      {'name': 'Lee'},
    ).encode();
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode(raw.substring(0, 20))),
    );
    await a!.refresh();
    expect(a!.rows, isEmpty);
    await aFolder.append(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('${raw.substring(20)}\n')),
    );
    await a!.refresh();
    expect(state(a!, id)['name'], 'Lee');
  });
  test('changed same-length committed prefix fails closed', () async {
    await task();
    final f = File('${aFolder.location}/${a!.writer}.jsonl');
    await f.writeAsString(
      (await f.readAsString()).replaceFirst('Groceries', 'Xroceries'),
      flush: true,
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test('missing previously seen stream blocks writes', () async {
    await task();
    await File('${aFolder.location}/${a!.writer}.jsonl').delete();
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test('owned incomplete tail is not silently truncated', () async {
    await task();
    await aFolder.append(
      '${a!.writer}.jsonl',
      Uint8List.fromList(utf8.encode('{')),
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
    expect(
      utf8.decode(await aFolder.read('${a!.writer}.jsonl')).endsWith('{'),
      true,
    );
  });
  test(
    'durable append before cache failure recovers once after restart',
    () async {
      final id = await task();
      final seq = 3;
      final e = LogEvent(
        a!.space,
        a!.writer,
        seq,
        EventClock.next(
          BigInt.from(testNow.microsecondsSinceEpoch) * BigInt.from(1000),
          LogEvent.decode(
            a!.db
                    .select(
                      'SELECT raw FROM events ORDER BY clock DESC LIMIT 1',
                    )
                    .first['raw']
                as String,
          ).clock,
        ),
        id,
        'task.completed',
        {},
      );
      await aFolder.append(
        '${a!.writer}.jsonl',
        Uint8List.fromList(utf8.encode('${e.encode()}\n')),
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], true);
      expect(a!.db.select('SELECT * FROM events').length, 3);
    },
  );
  test(
    'out-of-order entity dependency is retained and projected later',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      await b!.command(id, 'task.edited', {'title': 'Changed elsewhere'});
      final third = LocalLogFolder('${root.path}/third');
      await Directory(third.location).create();
      await File(
        '${aFolder.location}/tandemlog-space.json',
      ).copy('${third.location}/tandemlog-space.json');
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${third.location}/${b!.writer}.jsonl');
      final c = await TaskStore.open(third, '${root.path}/private-c');
      try {
        expect(c.rows, isEmpty);
        await File(
          '${aFolder.location}/${a!.writer}.jsonl',
        ).copy('${third.location}/${a!.writer}.jsonl');
        await c.refresh();
        expect(state(c, id)['title'], 'Changed elsewhere');
      } finally {
        await c.close();
      }
    },
  );
  test(
    'concurrent commands and refreshes serialize without duplicate sequence',
    () async {
      final id = await task();
      await Future.wait([
        a!.command(id, 'task.edited', {'title': 'First'}),
        a!.command(id, 'task.edited', {'description': 'Second'}),
        a!.refresh(),
        a!.command(id, 'task.completed', {}),
      ]);
      expect(
        a!.db
            .select('SELECT seq FROM events WHERE writer=? ORDER BY seq', [
              a!.writer,
            ])
            .map((r) => r['seq'])
            .toList(),
        [1, 2, 3, 4, 5],
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'First');
      expect(state(a!, id)['completed'], true);
    },
  );
  test('invalid local commands leave canonical bytes unchanged', () async {
    final id = await task();
    final before = await aFolder.read('${a!.writer}.jsonl');
    final user = a!.rows.firstWhere((r) => r['kind'] == 'user')['id'] as String;
    await expectLater(
      a!.command(id, 'task.created', {
        'title': 'Duplicate',
        'description': '',
        'assignee': user,
      }),
      throwsA(isA<FormatFailure>()),
    );
    await expectLater(
      a!.command(user, 'task.edited', {'title': 'Invalid'}),
      throwsA(isA<FormatFailure>()),
    );
    await expectLater(
      a!.command(const Uuid().v4(), 'task.completed', {}),
      throwsA(isA<FormatFailure>()),
    );
    for (final invalid in [
      '------------------------------------',
      '11111111-1111-1111-1111-111111111111',
    ]) {
      await expectLater(
        a!.command(invalid, 'task.created', {
          'title': 'Rejected recurring task',
          'description': '',
          'assignee': user,
          'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every month'},
        }),
        throwsA(isA<FormatFailure>()),
      );
    }
    expect(await aFolder.read('${a!.writer}.jsonl'), before);
    await a!.command(id, 'task.edited', {'title': 'Still works'});
  });
  test(
    'manifest deletion, replacement and future format block commands',
    () async {
      final id = await task();
      final manifest = await aFolder.read('tandemlog-space.json');
      final before = await aFolder.read('${a!.writer}.jsonl');
      final file = File('${aFolder.location}/tandemlog-space.json');
      for (final replacement in [
        null,
        jsonEncode({'v': 1, 'id': const Uuid().v4()}),
        jsonEncode({'v': 99, 'id': a!.space}),
      ]) {
        if (replacement == null) {
          await file.delete();
        } else {
          await file.writeAsString(replacement);
        }
        await expectLater(
          a!.command(id, 'task.completed', {}),
          throwsA(anything),
        );
        expect(await aFolder.read('${a!.writer}.jsonl'), before);
        await file.writeAsBytes(manifest);
      }
      await a!.command(id, 'task.completed', {});
    },
  );
  test(
    'local undo requires an earlier completion of the same entity',
    () async {
      final id = await task();
      final before = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.completionUndone', {
          'completion': '${a!.writer}:99',
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a!.command(id, 'task.completionUndone', {
          'completion': '${a!.writer}:1',
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), before);
    },
  );
  test(
    'remote undo arriving before completion is revalidated when target arrives',
    () async {
      final id = await task();
      final remote = const Uuid().v4(), other = const Uuid().v4();
      final undo = LogEvent(
        a!.space,
        remote,
        1,
        testClock(10, 0),
        id,
        'task.completionUndone',
        {'completion': '$other:1'},
      );
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
      );
      await a!.refresh();
      final completed = LogEvent(
        a!.space,
        other,
        1,
        testClock(9, 0),
        id,
        'task.completed',
        {},
      );
      await aFolder.create(
        '$other.jsonl',
        Uint8List.fromList(utf8.encode('${completed.encode()}\n')),
      );
      await a!.refresh();
      expect(state(a!, id)['completed'], false);
    },
  );
  test('remote undo cannot suppress a future-clock completion', () async {
    final id = await task();
    final remote = const Uuid().v4(), other = const Uuid().v4();
    final undo = LogEvent(
      a!.space,
      remote,
      1,
      testClock(10, 0),
      id,
      'task.completionUndone',
      {'completion': '$other:1'},
    );
    await aFolder.create(
      '$remote.jsonl',
      Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
    );
    await a!.refresh();
    final completed = LogEvent(
      a!.space,
      other,
      1,
      testClock(11, 0),
      id,
      'task.completed',
      {},
    );
    await aFolder.create(
      '$other.jsonl',
      Uint8List.fromList(utf8.encode('${completed.encode()}\n')),
    );
    await expectLater(a!.refresh(), throwsA(isA<FormatFailure>()));
  });
  test(
    'close drains accepted work, rejects new work and is idempotent',
    () async {
      final id = await task();
      await a!.close();
      final gated = _GatedAppendFolder(aFolder);
      a = await TaskStore.open(gated, '${root.path}/private-a');
      final active = a!.command(id, 'task.edited', {
        'title': 'Saved before close',
      });
      await gated.entered.future;
      final queued = a!.refresh();
      final closing = a!.close();
      final repeatedClose = a!.close();
      final afterCloseRejected = expectLater(a!.refresh(), throwsStateError);
      var closed = false;
      closing.then((_) => closed = true);
      try {
        expect(identical(closing, repeatedClose), true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, false);
        // The database must remain available to the active command until drain.
        expect(state(a!, id)['title'], 'Groceries');
      } finally {
        gated.release.complete();
      }
      await active;
      expect(await queued, false);
      await afterCloseRejected;
      await closing;
      expect(closed, true);
      await a!.close();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['title'], 'Saved before close');
      expect(a!.db.select('SELECT * FROM events').length, 3);
    },
  );
  test(
    'pending undo is validated before its local target is appended',
    () async {
      final id = await task();
      final otherTask = await task();
      final nextSeq =
          (a!.db.select('SELECT MAX(seq) AS n FROM events WHERE writer=?', [
                a!.writer,
              ]).first['n']
              as int) +
          1;
      final remote = const Uuid().v4();
      final undo = LogEvent(
        a!.space,
        remote,
        1,
        testClock(20, 0),
        id,
        'task.completionUndone',
        {'completion': '${a!.writer}:$nextSeq'},
      );
      await aFolder.create(
        '$remote.jsonl',
        Uint8List.fromList(utf8.encode('${undo.encode()}\n')),
      );
      await a!.refresh();
      final before = await aFolder.read('${a!.writer}.jsonl');
      final eventCount = a!.db.select('SELECT * FROM events').length;
      for (final candidate in [
        (
          entity: id,
          type: 'task.edited',
          data: <String, dynamic>{'title': 'Wrong type'},
        ),
        (entity: otherTask, type: 'task.completed', data: <String, dynamic>{}),
        (entity: id, type: 'task.completed', data: <String, dynamic>{}),
      ]) {
        await expectLater(
          a!.command(candidate.entity, candidate.type, candidate.data),
          throwsA(isA<FormatFailure>()),
        );
        expect(await aFolder.read('${a!.writer}.jsonl'), before);
        expect(a!.db.select('SELECT * FROM events').length, eventCount);
      }
      // A rejected local target must not leave a poisoned canonical record.
      await a!.refresh();
      expect(state(a!, id)['completed'], false);
    },
  );
  test(
    'missing canonical folder contents do not initialize a new manifest',
    () async {
      final id = await task();
      final expected = a!.rows;
      final originalSpace = a!.space;
      final savedFiles = <String, Uint8List>{};
      for (final file in await aFolder.list()) {
        savedFiles[file.name] = await aFolder.read(file.name);
      }
      await a!.close();
      a = null;
      for (final name in savedFiles.keys) {
        await File('${aFolder.location}/$name').delete();
      }
      await expectLater(
        TaskStore.open(aFolder, '${root.path}/private-a'),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        await aFolder.list(),
        isEmpty,
        reason: 'Opening a known space must not create a replacement manifest.',
      );
      // Restoring canonical files recovers the same identity and cached state.
      for (final entry in savedFiles.entries) {
        await aFolder.create(entry.key, entry.value);
      }
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.space, originalSpace);
      expect(a!.rows, expected);
      expect(state(a!, id)['title'], 'Groceries');
    },
  );
  test(
    'offline tag removal preserves unseen same-name additions and atomic edits',
    () async {
      final id = await task();
      await a!.setTags(id, ['home']);
      await copy(aFolder, bFolder);
      await b!.refresh();
      final observed = Map<String, String>.from(
        state(a!, id)['tagRefs'] as Map,
      );
      await b!.command(id, 'task.tagsChanged', {
        'add': ['home', 'other'],
        'remove': <String>[],
      });
      await a!.edit(
        id,
        {'title': 'Revised'},
        tags: [],
        observedTagRefs: observed,
      );
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id)['title'], 'Revised');
      expect(state(a!, id)['tags'], ['home', 'other']);
      expect(a!.rows, b!.rows);
    },
  );
  test(
    'concurrent relative moves converge and survive cache rebuild',
    () async {
      final first = await task();
      final user = state(a!, first)['assignee'];
      final second = const Uuid().v4(), third = const Uuid().v4();
      for (final id in [second, third]) {
        await a!.command(id, 'task.created', {
          'title': id,
          'description': '',
          'assignee': user,
        });
      }
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.moveBefore(third, first);
      await b!.moveBefore(second, first);
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      final expected = a!.rows;
      await a!.close();
      a = null;
      await File('${root.path}/private-a/cache.sqlite').delete();
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
    },
  );
  test(
    'concurrent recurrence completion has one durable successor and history reopen retains edits',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {
          'startDate': '2026-10-01',
          'scheduledDate': '2026-10-02',
          'dueDate': '2026-10-03',
          'startTime': '09:30',
          'timeZone': 'America/Chicago',
          'recurrence': 'every week when done',
        },
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      final one = await a!.complete(
        id,
        completionDay: DateTime.utc(2026, 10, 20),
      );
      await b!.complete(id, completionDay: DateTime.utc(2026, 10, 21));
      final next = const Uuid().v5(id, 'successor');
      await a!.command(next, 'task.edited', {'description': 'Successor work'});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(a!.rows.where((r) => r['kind'] == 'task').length, 2);
      expect(state(a!, next)['description'], 'Successor work');
      expect((state(a!, next)['schedule'] as Map)['scheduledDate'], null);
      expect(
        a!.rows.indexWhere((r) => r['id'] == next),
        lessThan(a!.rows.indexWhere((r) => r['id'] == id)),
      );
      await a!.reopen(id, a!.activeCompletionIds(id));
      expect(state(a!, id)['completed'], false);
      expect(state(a!, next)['description'], 'Successor work');
      await a!.complete(id, completionDay: DateTime.utc(2026, 10, 22));
      expect(a!.rows.where((r) => r['kind'] == 'task').length, 2);
      expect(one.data['successor'], isNotNull);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
    },
  );
  test('protocol v1 remains untouched and explicitly rejected', () async {
    await a!.close();
    a = null;
    final old = jsonEncode({'v': 1, 'id': const Uuid().v4()});
    await File('${aFolder.location}/tandemlog-space.json').writeAsString(old);
    await expectLater(
      TaskStore.open(aFolder, '${root.path}/fresh-private'),
      throwsA(
        isA<FormatFailure>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('older prerelease'),
            contains('Preserve this folder'),
            contains('new data folder'),
          ),
        ),
      ),
    );
    expect(
      await File('${aFolder.location}/tandemlog-space.json').readAsString(),
      old,
    );
  });
  test(
    'late winning recurrence seed cannot resurrect removed successor tags',
    () async {
      final id = await task();
      await a!.setTags(id, ['seed']);
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-03', 'recurrence': 'every week'},
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      final early = a!.writer.compareTo(b!.writer) < 0 ? a! : b!;
      final late = identical(early, a) ? b! : a!;
      await early.complete(id, completionDay: DateTime.utc(2026, 10, 20));
      await late.complete(id, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(id, 'successor');
      await late.setTags(next, []);
      expect(state(late, next)['tags'], isEmpty);
      await File(
        '${early.folder.location}/${early.writer}.jsonl',
      ).copy('${late.folder.location}/${early.writer}.jsonl');
      await late.refresh();
      expect(state(late, next)['tags'], isEmpty);
      await copy(late.folder as LocalLogFolder, early.folder as LocalLogFolder);
      await early.refresh();
      expect(early.rows, late.rows);
    },
  );
  test(
    'successor collision and invalid tag/move references fail before append',
    () async {
      final id = await task();
      await a!.setTags(id, ['tag']);
      final user = state(a!, id)['assignee'] as String;
      final next = const Uuid().v5(id, 'successor');
      await a!.command(next, 'task.created', {
        'title': 'Existing',
        'description': '',
        'assignee': user,
      });
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-03', 'recurrence': 'every week'},
      });
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.complete(id, completionDay: DateTime.utc(2026, 10, 20)),
        throwsA(isA<FormatFailure>()),
      );
      final ref = (state(a!, id)['tagRefs'] as Map).keys.single as String;
      await expectLater(
        a!.command(next, 'task.tagsChanged', {
          'add': [],
          'remove': [ref],
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(a!.moveBefore(id, user), throwsA(isA<FormatFailure>()));
      await expectLater(
        a!.moveBefore(id, const Uuid().v4()),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
      await a!.refresh();
    },
  );
  test(
    'offline schedule edits converge atomically without mixing precise date-times',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final left = {
        'startDate': '2026-10-01',
        'scheduledDate': '2026-10-01',
        'dueDate': '2026-10-01',
        'startTime': '09:00',
        'scheduledTime': '09:30',
        'dueTime': '10:00',
        'timeZone': 'UTC',
      };
      final right = {
        'startDate': '2026-10-01',
        'scheduledDate': '2026-10-01',
        'dueDate': '2026-10-01',
        'startTime': '11:00',
        'scheduledTime': '11:30',
        'dueTime': '12:00',
        'timeZone': 'UTC',
      };
      await a!.command(id, 'task.edited', {'schedule': left});
      await b!.command(id, 'task.edited', {'schedule': right});
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(
        state(a!, id)['schedule'],
        a!.writer.compareTo(b!.writer) > 0 ? left : right,
      );
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.edited', {
          'schedule': {'startDate': '2026-12-01', 'dueDate': '2026-11-01'},
        }),
        throwsA(isA<FormatFailure>()),
      );
      await expectLater(
        a!.command(id, 'task.completed', {
          'successor': {
            'id': const Uuid().v5(id, 'successor'),
            'title': 'Invalid interval',
            'description': '',
            'assignee': state(a!, id)['assignee'],
            'tags': [],
            'schedule': {
              'startDate': '2026-10-01',
              'dueDate': '2026-10-01',
              'startTime': '11:00',
              'dueTime': '10:00',
            },
          },
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    },
  );
  test(
    'completion reconciles changed timezone before selecting civil day',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {
          'dueDate': '2026-10-01',
          'timeZone': 'UTC',
          'recurrence': 'every day when done',
        },
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await b!.command(id, 'task.edited', {
        'schedule': {
          'dueDate': '2026-10-01',
          'timeZone': 'America/Chicago',
          'recurrence': 'every day when done',
        },
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      final completion = await a!.complete(
        id,
        completionInstant: DateTime.utc(2026, 10, 20, 2),
      );
      expect(completion.data['completedAt'], '2026-10-19');
      expect(
        ((completion.data['successor'] as Map)['schedule'] as Map)['dueDate'],
        '2026-10-20',
      );
    },
  );
  test(
    'completion durable append failure recovers parent and sole successor together',
    () async {
      final id = await task();
      await a!.command(id, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every day'},
      });
      await a!.close();
      a = null;
      final failing = _FailAfterAppendFolder(aFolder);
      a = await TaskStore.open(failing, '${root.path}/private-a');
      failing.failNext = true;
      await expectLater(
        a!.complete(id, completionDay: DateTime.utc(2026, 10, 20)),
        throwsStateError,
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(aFolder, '${root.path}/private-a');
      expect(state(a!, id)['completed'], true);
      expect(a!.rows.where((r) => r['kind'] == 'task'), hasLength(2));
      expect(state(a!, const Uuid().v5(id, 'successor'))['completed'], false);
      expect(a!.activeCompletionIds(id), hasLength(1));
    },
  );
  test('pending future tag removal cannot poison next local append', () async {
    final id = await task();
    final seq =
        (a!.db.select('SELECT MAX(seq) AS n FROM events WHERE writer=?', [
              a!.writer,
            ]).first['n']
            as int) +
        1;
    final remote = LogEvent(
      a!.space,
      b!.writer,
      1,
      testClock(100, 0),
      id,
      'task.tagsChanged',
      {
        'add': [],
        'remove': ['${a!.writer}:$seq:0'],
      },
    );
    await aFolder.append(
      '${b!.writer}.jsonl',
      Uint8List.fromList(utf8.encode('${remote.encode()}\n')),
    );
    await a!.refresh();
    final bytes = await aFolder.read('${a!.writer}.jsonl');
    await expectLater(a!.setTags(id, ['later']), throwsA(isA<FormatFailure>()));
    expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    await a!.refresh();
  });
  test(
    'offline older high sequence loses to a later wall-clock edit',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      LogEvent? old;
      for (var i = 0; i < 30; i++) {
        old = await a!.command(id, 'task.edited', {'title': 'Older $i'});
      }
      testNow = testNow.add(const Duration(hours: 1));
      final recent = await b!.command(id, 'task.edited', {'title': 'Newer'});
      expect(old!.sequence, greaterThan(recent.sequence));
      expect(recent.clock, greaterThan(old.clock));
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(state(a!, id)['title'], 'Newer');
      expect(a!.rows, b!.rows);
    },
  );
  test(
    'observed clocks precede local writes across rollback and restart',
    () async {
      final id = await task();
      await copy(aFolder, bFolder);
      await b!.refresh();
      final remote = await b!.command(id, 'task.edited', {
        'description': 'Remote',
      });
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      testNow = testNow.subtract(const Duration(minutes: 1));
      final local = await a!.command(id, 'task.edited', {
        'title': 'Causal later',
      });
      expect(local.clock > remote.clock, isTrue);
      expect(local.clock.value, remote.clock.value + BigInt.one);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.readFiles, 0);
      expect(a!.rows, expected);
      final afterRestart = await a!.command(id, 'task.edited', {
        'description': 'After restart',
      });
      expect(afterRestart.clock > local.clock, isTrue);
    },
  );

  test(
    'future records remain immutable and readable while warning permits writes',
    () async {
      final id = await task();
      final future = LogEvent(
        a!.space,
        b!.writer,
        1,
        testClock(testNow.millisecondsSinceEpoch + 3600000, 123),
        id,
        'task.edited',
        {'title': 'Future record'},
      );
      final bytes = Uint8List.fromList(utf8.encode('${future.encode()}\n'));
      await aFolder.append('${b!.writer}.jsonl', bytes);
      await a!.refresh();
      expect(state(a!, id)['title'], 'Future record');
      expect(a!.clockWarning, isNotNull);
      final later = await a!.command(id, 'task.edited', {
        'title': 'Continued edit',
      });
      expect(later.clock.value, future.clock.value + BigInt.one);
      expect(state(a!, id)['title'], 'Continued edit');
      expect(await aFolder.read('${b!.writer}.jsonl'), bytes);
      final expected = a!.rows;
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.clockWarning, isNotNull);
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
      final restarted = await a!.command(id, 'task.edited', {
        'description': 'Still writable',
      });
      expect(restarted.clock.value, later.clock.value + BigInt.one);
      testNow = testNow.add(const Duration(hours: 2));
      await a!.refresh();
      expect(a!.clockWarning, isNull);
      expect(await aFolder.read('${b!.writer}.jsonl'), bytes);
      expect(
        a!.db.select('SELECT * FROM events WHERE writer=?', [b!.writer]),
        hasLength(1),
      );
    },
  );
  test(
    'large clock rollback warns without blocking and warning clears when caught up',
    () async {
      final id = await task();
      final previous = LogEvent.decode(
        a!.db
                .select('SELECT raw FROM events ORDER BY clock DESC LIMIT 1')
                .first['raw']
            as String,
      );
      testNow = testNow.subtract(const Duration(minutes: 6));
      final changed = await a!.command(id, 'task.edited', {
        'title': 'Continued despite rollback',
      });
      expect(a!.clockWarning, isNotNull);
      expect(changed.clock.value, previous.clock.value + BigInt.one);
      expect(state(a!, id)['title'], 'Continued despite rollback');
      testNow = testNow.add(const Duration(minutes: 6));
      await a!.refresh();
      expect(a!.clockWarning, isNull);
    },
  );
  test(
    'SQLite and canonical clock retain exact signed-64-bit nanoseconds',
    () async {
      final id = await task();
      final exact = EventClock(EventClock.maximum - BigInt.from(2));
      final remote = LogEvent(
        a!.space,
        b!.writer,
        1,
        exact,
        id,
        'task.edited',
        {'title': 'Exact large timestamp'},
      );
      await aFolder.append(
        '${b!.writer}.jsonl',
        Uint8List.fromList(utf8.encode('${remote.encode()}\n')),
      );
      await a!.refresh();
      expect(
        BigInt.from(
          a!.db.select('SELECT clock FROM events WHERE writer=?', [
                b!.writer,
              ]).single['clock']
              as int,
        ),
        exact.value,
      );
      expect(a!.clockWarning, isNotNull);
      final changed = await a!.command(id, 'task.edited', {
        'description': 'Continued',
      });
      expect(changed.clock.value, exact.value + BigInt.one);
      expect(
        jsonDecode(changed.encode())['clock'],
        (exact.value + BigInt.one).toString(),
      );
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(state(a!, id)['description'], 'Continued');
      final finalInRange = await a!.command(id, 'task.edited', {
        'description': 'Last representable clock',
      });
      expect(finalInRange.clock.value, EventClock.maximum);
      final bytes = await aFolder.read('${a!.writer}.jsonl');
      await expectLater(
        a!.command(id, 'task.edited', {'description': 'Overflow'}),
        throwsFormatException,
      );
      expect(await aFolder.read('${a!.writer}.jsonl'), bytes);
    },
  );
  test(
    'recurrence inserts at current parent position and later moves stay independent',
    () async {
      final monthly = await task();
      await a!.command(monthly, 'task.edited', {
        'title': 'Monthly review',
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every month'},
      });
      final read = const Uuid().v4();
      await a!.command(read, 'task.created', {
        'title': 'Read project notes',
        'description': '',
        'assignee': state(a!, monthly)['assignee'],
      });
      List<String> order() => a!.rows
          .where((r) => r['kind'] == 'task')
          .map((r) => r['id'] as String)
          .toList();
      await a!.moveBefore(monthly, null);
      expect(order(), [read, monthly]);
      await a!.complete(monthly, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(monthly, 'successor');
      expect(order(), [read, next, monthly]);
      await a!.moveBefore(monthly, read);
      expect(order(), [
        monthly,
        read,
        next,
      ], reason: 'Moving completed history does not drag its successor.');
      await a!.moveBefore(next, monthly);
      expect(order(), [next, monthly, read]);
      await a!.moveBefore(monthly, null);
      expect(order(), [next, read, monthly]);
      await a!.reopen(monthly, a!.activeCompletionIds(monthly));
      await a!.complete(monthly, completionDay: DateTime.utc(2026, 10, 21));
      expect(order(), [
        next,
        read,
        monthly,
      ], reason: 'Recompletion must not reposition the existing occurrence.');
      expect(state(a!, monthly)['completedAt'], '2026-10-21');
      await a!.reopen(monthly, a!.activeCompletionIds(monthly));
      expect(state(a!, monthly)['completedAt'], isNull);
    },
  );
  test('later creation stays after an earlier move to end', () async {
    final first = await task();
    final user = state(a!, first)['assignee'];
    final second = const Uuid().v4(), third = const Uuid().v4();
    await a!.command(second, 'task.created', {
      'title': 'Second',
      'description': '',
      'assignee': user,
    });
    await a!.moveBefore(first, null);
    await a!.command(third, 'task.created', {
      'title': 'Third',
      'description': '',
      'assignee': user,
    });
    expect(a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
      second,
      first,
      third,
    ]);
  });
  test(
    'late pre-completion move converges and old order cache rebuilds without log writes',
    () async {
      final monthly = await task();
      await a!.command(monthly, 'task.edited', {
        'schedule': {'dueDate': '2026-10-01', 'recurrence': 'every month'},
      });
      final read = const Uuid().v4();
      await a!.command(read, 'task.created', {
        'title': 'Read project notes',
        'description': '',
        'assignee': state(a!, monthly)['assignee'],
      });
      await copy(aFolder, bFolder);
      await b!.refresh();
      await a!.moveBefore(monthly, null);
      testNow = testNow.add(const Duration(milliseconds: 1));
      await b!.complete(monthly, completionDay: DateTime.utc(2026, 10, 20));
      final next = const Uuid().v5(monthly, 'successor');
      expect(b!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        next,
        monthly,
        read,
      ]);
      await File(
        '${bFolder.location}/${b!.writer}.jsonl',
      ).copy('${aFolder.location}/${b!.writer}.jsonl');
      await a!.refresh();
      await copy(aFolder, bFolder);
      await b!.refresh();
      expect(a!.rows, b!.rows);
      expect(a!.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        read,
        next,
        monthly,
      ]);
      final expected = a!.rows;
      final raw = await aFolder.read('${a!.writer}.jsonl');
      a!.db.execute('UPDATE positions SET rank=-rank');
      a!.db.execute("DELETE FROM metadata WHERE key='order_projection'");
      await a!.close();
      a = null;
      a = await TaskStore.open(
        aFolder,
        '${root.path}/private-a',
        now: () => testNow,
      );
      expect(a!.rows, expected);
      expect(a!.readFiles, 0);
      expect(await aFolder.read('${a!.writer}.jsonl'), raw);
      expect(
        a!.db
            .select("SELECT value FROM metadata WHERE key='order_projection'")
            .single['value'],
        '2',
      );
    },
  );
}

/// Holds an append open so shutdown tests exercise real asynchronous overlap.
class _GatedAppendFolder implements LogFolder {
  final LogFolder delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  _GatedAppendFolder(this.delegate);
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    entered.complete();
    await release.future;
    await delegate.append(name, bytes);
  }
}

class _FailAfterAppendFolder implements LogFolder {
  _FailAfterAppendFolder(this.delegate);
  final LogFolder delegate;
  bool failNext = false;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    await delegate.append(name, bytes);
    if (failNext) {
      failNext = false;
      throw StateError('Injected failure after durable append');
    }
  }
}

EventClock testClock(int wallMs, int increment) => EventClock(
  BigInt.from(wallMs) * BigInt.from(1000000) + BigInt.from(increment),
);

class _OnNextListFolder implements LogFolder {
  _OnNextListFolder(this.delegate);
  final LogFolder delegate;
  Future<void> Function()? beforeNextList;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() async {
    final callback = beforeNextList;
    beforeNextList = null;
    if (callback != null) await callback();
    return delegate.list();
  }

  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      delegate.append(name, bytes);
}

/// Real append succeeds; the subsequent ingestion fails before its transaction.
class _FailRefreshAfterAppendFolder implements LogFolder {
  _FailRefreshAfterAppendFolder(this.delegate);
  final LogFolder delegate;
  bool failNext = false, failList = false;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() async {
    if (failList) {
      failList = false;
      throw StateError('Injected refresh failure after durable append');
    }
    return delegate.list();
  }

  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    await delegate.append(name, bytes);
    if (failNext) {
      failNext = false;
      failList = true;
    }
  }
}
