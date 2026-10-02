import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

class _PrefixReplacement implements LogFolder {
  _PrefixReplacement(this.inner);
  final LocalLogFolder inner;
  int? keep;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final file in await inner.list()) LogFileInfo(file.name, ''),
  ];
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final count = keep;
    keep = null;
    if (count == null) return inner.append(name, bytes);
    final previous = await inner.read(name);
    await inner.append(name, bytes);
    final lines = utf8.decode(bytes).split('\n')..removeLast();
    final temporary = File('$location/replacement.tmp');
    await temporary.writeAsBytes([
      ...previous,
      ...utf8.encode(lines.take(count).map((line) => '$line\n').join()),
    ], flush: true);
    await temporary.rename('$location/$name');
  }
}

void main() {
  late Directory root;
  late LocalLogFolder folder, remote;
  late _PrefixReplacement transport;
  late TaskStore a, b;
  late String user;
  var closed = false;
  Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
    for (final file in await from.list()) {
      await File(
        '${from.location}/${file.name}',
      ).copy('${to.location}/${file.name}');
    }
  }

  Future<void> join() async {
    await copy(folder, remote);
    await b.refresh();
  }

  Future<void> converge() async {
    await File(
      '${remote.location}/${b.writer}.jsonl',
    ).copy('${folder.location}/${b.writer}.jsonl');
    await a.refresh();
    await join();
    expect(a.rows, b.rows);
  }

  Future<String> task({
    bool repeating = true,
    String title = 'Original',
  }) async {
    final id = const Uuid().v4();
    await a.command(id, 'task.created', {
      'title': title,
      'description': '',
      'assignee': user,
      'schedule': {
        'dueDate': '2030-05-01',
        if (repeating) 'recurrence': 'every day',
      },
    });
    return id;
  }

  Map<String, dynamic> row(TaskStore store, String id) =>
      store.rows.firstWhere((r) => r['id'] == id);
  bool visible(TaskStore store, String id) =>
      store.rows.any((r) => r['id'] == id);
  Future<LogEvent> complete(String id) =>
      a.complete(id, completionDay: DateTime.utc(2030, 5, 1));
  setUp(() async {
    closed = false;
    root = await Directory.systemTemp.createTemp('recurring-undo-');
    folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    remote = LocalLogFolder(
      (await Directory('${root.path}/remote').create()).path,
    );
    transport = _PrefixReplacement(folder);
    a = await TaskStore.open(transport, '${root.path}/a');
    user = const Uuid().v4();
    await a.command(user, 'user.created', {'name': 'Example'});
    await copy(folder, remote);
    b = await TaskStore.open(remote, '${root.path}/b');
  });
  tearDown(() async {
    if (!closed) await a.close();
    await b.close();
    await root.delete(recursive: true);
  });

  test(
    'true Undo suppresses untouched successor, preserves bytes, and survives rebuild',
    () async {
      final id = await task(), completion = await complete(id);
      final next = const Uuid().v5(id, 'successor');
      final before = await folder.read('${a.writer}.jsonl');
      expect(visible(a, next), isTrue);
      final result = await a.undoOperations([completion.id]);
      expect(result.error, isNull);
      expect(result.removedSuccessorCount, 1);
      expect(result.retainedSuccessorCount, 0);
      expect(row(a, id)['completed'], isFalse);
      expect(visible(a, next), isFalse);
      expect(
        a.hasEntity(next),
        isTrue,
        reason: 'Canonical dependency identity remains materialized.',
      );
      final after = await folder.read('${a.writer}.jsonl');
      expect(after.sublist(0, before.length), before);
      expect(
        LogEvent.decode(utf8.decode(after.sublist(before.length)).trim()).type,
        'task.recurringCompletionUndone',
      );
      await a.undoOperations([completion.id]);
      expect(await folder.read('${a.writer}.jsonl'), after);
      a.db.execute('PRAGMA user_version=8');
      await a.close();
      closed = true;
      a = await TaskStore.open(transport, '${root.path}/a');
      closed = false;
      expect(a.db.select('PRAGMA user_version').single['user_version'], 9);
      expect(visible(a, next), isFalse);
      expect(await folder.read('${a.writer}.jsonl'), after);
      expect(
        await Directory(
          '${root.path}/a',
        ).list().where((f) => f.path.contains('cache-v8-')).length,
        1,
      );
    },
  );

  test(
    'ordinary Reopen and historical operationUndone still retain untouched successor',
    () async {
      final reopened = await task();
      await complete(reopened);
      await a.reopen(reopened, a.activeCompletionIds(reopened));
      expect(visible(a, const Uuid().v5(reopened, 'successor')), isTrue);
      final historical = await task(), completion = await complete(historical);
      await a.command(historical, 'task.operationUndone', {
        'operation': completion.id,
      });
      expect(row(a, historical)['completed'], isFalse);
      expect(visible(a, const Uuid().v5(historical, 'successor')), isTrue);
    },
  );

  for (final activity in [
    'edit',
    'tags',
    'move',
    'complete',
    'delete',
    'anchor',
    'undoneEdit',
  ]) {
    test('$activity protects successor from cleanup', () async {
      final id = await task(), completion = await complete(id);
      final next = const Uuid().v5(id, 'successor');
      if (activity == 'edit' || activity == 'undoneEdit') {
        final edit = await a.command(next, 'task.edited', {
          'title': 'Independent work',
        });
        if (activity == 'undoneEdit') await a.undoOperations([edit.id]);
      } else if (activity == 'tags') {
        await a.setTags(next, ['Independent']);
      } else if (activity == 'move') {
        await a.moveBefore(next, null);
      } else if (activity == 'complete') {
        await a.complete(next, completionDay: DateTime.utc(2030, 5, 2));
      } else if (activity == 'delete') {
        await a.deleteTask(next, expectedTaskSnapshot: a.taskSnapshot);
      } else {
        final other = await task(repeating: false);
        await a.moveBefore(other, next);
      }
      final result = await a.undoOperations([completion.id]);
      expect(result.retainedSuccessorCount, 1);
      expect(result.removedSuccessorCount, 0);
      expect(row(a, id)['completed'], isFalse);
      if (activity == 'delete') {
        expect(
          visible(a, next),
          isFalse,
          reason: 'Independent deletion stays deleted.',
        );
      } else {
        expect(visible(a, next), isTrue);
      }
      if (activity == 'edit') expect(row(a, next)['title'], 'Independent work');
      if (activity == 'complete') {
        expect(row(a, next)['completed'], isTrue);
        expect(visible(a, const Uuid().v5(next, 'successor')), isTrue);
      }
    });
  }

  for (final late in ['edit', 'completion', 'anchor']) {
    test(
      'late remote $late restores protected successor and converges after rebuild',
      () async {
        final id = await task(), completion = await complete(id);
        final next = const Uuid().v5(id, 'successor');
        final anchorTask = await task(repeating: false);
        await join();
        if (late == 'edit') {
          await b.command(next, 'task.edited', {
            'title': 'Late independent work',
          });
        } else if (late == 'completion') {
          await b.complete(id, completionDay: DateTime.utc(2030, 5, 2));
        } else {
          await b.moveBefore(anchorTask, next);
        }
        await a.undoOperations([completion.id]);
        expect(visible(a, next), isFalse);
        await converge();
        expect(visible(a, next), isTrue);
        if (late == 'edit') {
          expect(row(a, next)['title'], 'Late independent work');
        }
        if (late == 'completion') expect(row(a, id)['completed'], isTrue);
        final expected = a.rows;
        a.db.execute('PRAGMA user_version=8');
        await a.close();
        closed = true;
        a = await TaskStore.open(transport, '${root.path}/a');
        closed = false;
        expect(a.rows, expected);
      },
    );
  }

  test(
    'untouched recompletion uses surviving snapshot and current parent position',
    () async {
      final first = await task(repeating: false),
          id = await task(),
          last = await task(repeating: false);
      final completion = await complete(id),
          next = const Uuid().v5(id, 'successor');
      await a.undoOperations([completion.id]);
      await a.moveBefore(id, first);
      await a.command(id, 'task.edited', {
        'title': 'New proposal',
        'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
      });
      await a.complete(id, completionDay: DateTime.utc(2030, 5, 10));
      expect(row(a, next)['title'], 'New proposal');
      expect((row(a, next)['schedule'] as Map)['dueDate'], '2030-05-11');
      expect(a.rows.where((r) => r['kind'] == 'task').map((r) => r['id']), [
        next,
        id,
        first,
        last,
      ]);
      await join();
      expect(a.rows, b.rows);
    },
  );

  for (final keep in [0, 1]) {
    test(
      'mixed Undo confirms only prefix and retries cleanup ($keep retained)',
      () async {
        final id = await task(),
            completion = await complete(id),
            plain = await task(repeating: false);
        final edit = await a.command(plain, 'task.edited', {'title': 'Edited'});
        transport.keep = keep;
        final result = await a.undoOperations([completion.id, edit.id]);
        expect(result.error, isNotNull);
        expect(result.undone, [completion.id, edit.id].take(keep));
        expect(result.remaining, [completion.id, edit.id].skip(keep));
        expect(result.removedSuccessorCount, keep);
        expect(visible(a, const Uuid().v5(id, 'successor')), keep == 0);
        final retry = await a.undoOperations(result.remaining);
        expect(retry.error, isNull);
        expect(visible(a, const Uuid().v5(id, 'successor')), isFalse);
        expect(row(a, plain)['title'], 'Original');
      },
    );
  }

  test(
    'new cleanup rejects nonrecurring and wrong-task targets before append',
    () async {
      final id = await task(repeating: false),
          completion = await complete(id),
          other = await task();
      final before = await folder.read('${a.writer}.jsonl');
      for (final entity in [id, other]) {
        await expectLater(
          a.command(entity, 'task.recurringCompletionUndone', {
            'completion': completion.id,
          }),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(await folder.read('${a.writer}.jsonl'), before);
    },
  );

  test(
    'historical v2 fixture retains old retraction meaning without rewriting',
    () async {
      final bytes = await File(
        'test/fixtures/recurring_operation_undone_v2.jsonl',
      ).readAsBytes();
      final records = (utf8.decode(bytes).trim().split('\n'))
          .map(LogEvent.decode)
          .toList();
      final fixtureFolder = LocalLogFolder(
        (await Directory('${root.path}/fixture').create()).path,
      );
      await fixtureFolder.create(
        'tandemlog-space.json',
        Uint8List.fromList(
          utf8.encode(jsonEncode({'v': 2, 'id': records.first.space})),
        ),
      );
      await fixtureFolder.create('${records.first.writer}.jsonl', bytes);
      final fixture = await TaskStore.open(
        fixtureFolder,
        '${root.path}/fixture-private',
      );
      try {
        final id = records[1].entity;
        expect(row(fixture, id)['completed'], isFalse);
        expect(visible(fixture, const Uuid().v5(id, 'successor')), isTrue);
        expect(
          await fixtureFolder.read('${records.first.writer}.jsonl'),
          bytes,
        );
      } finally {
        await fixture.close();
      }
    },
  );

  test(
    'delayed valid cleanup suppresses successor once its target arrives',
    () async {
      final id = await task();
      final writer = const Uuid().v4();
      final snapshot = {
        'id': const Uuid().v5(id, 'successor'),
        'title': 'Delayed seed',
        'description': '',
        'assignee': user,
        'schedule': {'dueDate': '2030-05-02', 'recurrence': 'every day'},
        'tags': <String>[],
      };
      final seed = LogEvent(
        a.space,
        writer,
        1,
        EventClock(BigInt.from(10)),
        id,
        'task.completed',
        {'successor': snapshot},
      );
      await expectLater(
        a.command(id, 'task.recurringCompletionUndone', {
          'completion': seed.id,
        }),
        throwsA(isA<FormatFailure>()),
      );
      final cleanupWriter = const Uuid().v4();
      final cleanup = LogEvent(
        a.space,
        cleanupWriter,
        1,
        EventClock(BigInt.from(20)),
        id,
        'task.recurringCompletionUndone',
        {'completion': seed.id},
      );
      await folder.create(
        '$cleanupWriter.jsonl',
        Uint8List.fromList(utf8.encode('${cleanup.encode()}\n')),
      );
      await a.refresh();
      await folder.create(
        '$writer.jsonl',
        Uint8List.fromList(utf8.encode('${seed.encode()}\n')),
      );
      await a.refresh();
      expect(row(a, id)['completed'], isFalse);
      expect(visible(a, const Uuid().v5(id, 'successor')), isFalse);
    },
  );

  test(
    'delayed nonrecurring and forward cleanup targets fail transactionally',
    () async {
      final id = await task();
      for (final forward in [false, true]) {
        final targetWriter = const Uuid().v4(),
            cleanupWriter = const Uuid().v4();
        final target = LogEvent(
          a.space,
          targetWriter,
          1,
          EventClock(BigInt.from(forward ? 30 : 10)),
          id,
          'task.completed',
          {
            if (forward)
              'successor': {
                'id': const Uuid().v5(id, 'successor'),
                'title': 'Seed',
                'description': '',
                'assignee': user,
                'tags': <String>[],
                'schedule': {
                  'dueDate': '2030-05-02',
                  'recurrence': 'every day',
                },
              },
          },
        );
        final cleanup = LogEvent(
          a.space,
          cleanupWriter,
          1,
          EventClock(BigInt.from(20)),
          id,
          'task.recurringCompletionUndone',
          {'completion': target.id},
        );
        await folder.create(
          '$cleanupWriter.jsonl',
          Uint8List.fromList(utf8.encode('${cleanup.encode()}\n')),
        );
        await a.refresh();
        final before = a.rows;
        await folder.create(
          '$targetWriter.jsonl',
          Uint8List.fromList(utf8.encode('${target.encode()}\n')),
        );
        await expectLater(a.refresh(), throwsA(isA<FormatFailure>()));
        expect(a.rows, before);
        expect(
          await folder.read('$targetWriter.jsonl'),
          utf8.encode('${target.encode()}\n'),
        );
        // Remove only this disposable uncommitted test stream for the next case.
        await File('${folder.location}/$targetWriter.jsonl').delete();
      }
    },
  );

  test(
    'new cleanup wire schema rejects extra fields and malformed references',
    () async {
      final id = await task(), completion = await complete(id);
      for (final data in [
        {'completion': completion.id, 'deleteSuccessor': true},
        {'completion': 'not-an-event-id'},
        {'operation': completion.id},
      ]) {
        final event = LogEvent(
          a.space,
          a.writer,
          100,
          completion.clock,
          id,
          'task.recurringCompletionUndone',
          data,
        );
        expect(
          () => LogEvent.decode(event.encode()),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );

  test(
    'pure seed selection is independent of arrival order and preserves historical Undo',
    () async {
      final id = await task(), first = await complete(id);
      final second = await a.complete(
        id,
        completionDay: DateTime.utc(2030, 5, 2),
      );
      final cleanup = LogEvent(
        a.space,
        a.writer,
        100,
        EventClock(first.clock.value + BigInt.from(100000000000)),
        id,
        'task.recurringCompletionUndone',
        {'completion': first.id},
      );
      for (final seeds in [
        [first, second],
        [second, first],
      ]) {
        final selection = selectSuccessor(seeds, [cleanup], protected: false);
        expect(selection.seed.id, second.id);
        expect(selection.suppressed, isFalse);
        expect(
          selectSuccessor(seeds, [cleanup], protected: true).seed.id,
          first.id,
        );
      }
      final historical = LogEvent(
        a.space,
        a.writer,
        101,
        cleanup.clock,
        id,
        'task.operationUndone',
        {'operation': first.id},
      );
      expect(
        selectSuccessor([first], [historical], protected: false).suppressed,
        isFalse,
      );
    },
  );
}
