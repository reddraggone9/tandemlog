import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  for (final count in [1, 30, 100]) {
    test(
      '$count-task create/edit/tag/move/delete/Undo use one durable append/cache transaction',
      () async {
        final root = await Directory.systemTemp.createTemp('batch-counts-');
        final folder = CountingFolder(
          LocalLogFolder(
            (await Directory('${root.path}/shared').create()).path,
          ),
        );
        final store = await TaskStore.open(folder, '${root.path}/private');
        try {
          final user = const Uuid().v4();
          await store.command(user, 'user.created', {'name': 'Example'});
          final titles = {
            for (var i = 0; i < count; i++) const Uuid().v4(): 'Task $i',
          };
          Future<void> oneBatch(Future<void> Function() operation) async {
            folder.reset();
            final before = store.cacheTransactions;
            await operation();
            expect(folder.appends, 1);
            expect(folder.lists, 2);
            expect(folder.reads, 3);
            expect(store.cacheTransactions - before, 1);
          }

          await oneBatch(() async {
            final result = await store.createTasks(titles, user);
            expect(result.succeeded, isTrue);
            expect(result.committedIds, titles.keys);
          });
          final tasks = titles.keys.toList();
          final anchor = const Uuid().v4();
          await store.command(anchor, 'task.created', {
            'title': 'Anchor',
            'description': '',
            'assignee': user,
          });
          final moves = <OperationReceipt>[];
          await oneBatch(() async {
            final result = await store.moveBlockBefore(
              tasks,
              null,
              expectedTaskSnapshot: store.taskSnapshot,
              canCommit: () => true,
              onPrepared: moves.add,
            );
            expect(result.succeeded, isTrue);
          });
          for (final edit in [
            BulkTaskEdit(schedulePatch: {'dueDate': '2026-10-05'}),
            BulkTaskEdit(addTags: ['Reviewed']),
          ]) {
            final receipts = <OperationReceipt>[];
            await oneBatch(() async {
              final result = await store.bulkEdit(
                tasks,
                edit,
                expectedTaskSnapshot: store.taskSnapshot,
                onPrepared: receipts.add,
              );
              expect(result.succeeded, isTrue);
            });
            await oneBatch(() async {
              expect(
                (await store.undoOperations(
                  receipts.map((r) => r.id).toList(),
                )).error,
                isNull,
              );
            });
          }
          final deletions = <OperationReceipt>[];
          await oneBatch(() async {
            expect(
              (await store.deleteTasks(
                tasks,
                expectedTaskSnapshot: store.taskSnapshot,
                onPrepared: deletions.add,
              )).succeeded,
              isTrue,
            );
          });
          await oneBatch(() async {
            expect(
              (await store.undoOperations(
                deletions.map((r) => r.id).toList(),
              )).error,
              isNull,
            );
          });
          final before = await folder.delegate.read('${store.writer}.jsonl');
          folder.reset();
          final retry = await store.createTasks(titles, user);
          expect(retry.committedIds, tasks);
          expect(folder.appends, 0);
          expect(await folder.delegate.read('${store.writer}.jsonl'), before);
          final expected = store.rows;
          await store.close();
          final replay = await TaskStore.open(
            folder,
            '${root.path}/fresh-cache',
          );
          expect(replay.rows, expected);
          await replay.close();
        } finally {
          await store.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  for (final fault in ['before', 'prefix', 'tail', 'after', 'cache']) {
    test(
      'capture $fault write reconciles exact records and never discards incomplete tail',
      () async {
        final root = await Directory.systemTemp.createTemp('batch-failure-');
        final folder = CountingFolder(
          LocalLogFolder(
            (await Directory('${root.path}/shared').create()).path,
          ),
        );
        final store = await TaskStore.open(folder, '${root.path}/private');
        try {
          final user = const Uuid().v4();
          await store.command(user, 'user.created', {'name': 'Example'});
          final titles = {
            const Uuid().v4(): 'First',
            const Uuid().v4(): 'Second',
          };
          folder.fault = fault;
          final result = await store.createTasks(titles, user);
          expect(result.error, isNotNull);
          final raw = await folder.delegate.read('${store.writer}.jsonl');
          if (fault == 'tail') {
            expect(result.committedIds, isEmpty);
            expect(result.remainingIds, titles.keys);
            expect(raw.last, isNot(10));
            await expectLater(
              store.createTasks(titles, user),
              throwsA(isA<FormatFailure>()),
            );
            expect(await folder.delegate.read('${store.writer}.jsonl'), raw);
            // A peer can ingest the complete prefix while this owner fails closed.
            final peer = await TaskStore.open(
              folder.delegate,
              '${root.path}/peer',
            );
            expect(peer.rows.where((r) => r['kind'] == 'task').length, 1);
            await peer.close();
          } else {
            final acknowledged = fault == 'before'
                ? 0
                : fault == 'prefix'
                ? 1
                : 2;
            expect(result.committedIds.length, acknowledged);
            expect(result.remainingIds.length, 2 - acknowledged);
            if (fault == 'before' || fault == 'prefix') {
              final blocked = await store.createTasks(titles, user);
              expect(blocked.error, isA<WriterGuardFailure>());
              await folder.revealPending();
              await store.refresh();
            }
            final retry = await store.createTasks(titles, user);
            expect(retry.succeeded, isTrue);
            expect(store.rows.where((r) => r['kind'] == 'task').length, 2);
            final events = store.db.select(
              "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.created'",
            );
            expect(
              events.length,
              2,
              reason: 'Retry must not duplicate any durable creation.',
            );
          }
        } finally {
          await store.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
  test(
    'invalid deferred reference to second batch event rejects all before append',
    () async {
      final root = await Directory.systemTemp.createTemp('batch-reference-');
      final folder = CountingFolder(
        LocalLogFolder((await Directory('${root.path}/shared').create()).path),
      );
      final now = DateTime.utc(2026, 10, 1);
      final store = await TaskStore.open(
        folder,
        '${root.path}/private',
        now: () => now,
      );
      try {
        final user = const Uuid().v4(),
            first = const Uuid().v4(),
            second = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Example'});
        final remote = const Uuid().v4();
        final event = LogEvent(
          store.space,
          remote,
          1,
          EventClock(BigInt.one),
          second,
          'task.operationUndone',
          {'operation': '${store.writer}:3'},
        );
        await folder.create(
          '$remote.jsonl',
          Uint8List.fromList(utf8.encode('${event.encode()}\n')),
        );
        await store.refresh();
        final before = await folder.delegate.read('${store.writer}.jsonl');
        final result = await store.createTasks({
          first: 'First',
          second: 'Second',
        }, user);
        expect(result.error, isA<FormatFailure>());
        expect(result.committedIds, isEmpty);
        expect(await folder.delegate.read('${store.writer}.jsonl'), before);
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'deferred tag reference to second prepared event rejects the complete batch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'batch-tag-reference-',
      );
      final folder = CountingFolder(
        LocalLogFolder((await Directory('${root.path}/shared').create()).path),
      );
      final store = await TaskStore.open(folder, '${root.path}/private');
      try {
        final user = const Uuid().v4(),
            first = const Uuid().v4(),
            second = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Example'});
        await store.createTasks({first: 'First', second: 'Second'}, user);
        final next =
            (store.db.select(
                  'SELECT MAX(seq) AS n FROM events WHERE writer=?',
                  [store.writer],
                ).single['n']
                as int) +
            2;
        final remote = const Uuid().v4();
        final event = LogEvent(
          store.space,
          remote,
          1,
          EventClock(BigInt.one),
          second,
          'task.edited',
          {
            'tagChanges': {
              'add': [],
              'remove': ['${store.writer}:$next:0'],
            },
          },
        );
        await folder.create(
          '$remote.jsonl',
          Uint8List.fromList(utf8.encode('${event.encode()}\n')),
        );
        await store.refresh();
        final before = await folder.delegate.read('${store.writer}.jsonl');
        final result = await store.bulkEdit(
          [first, second],
          BulkTaskEdit(addTags: ['Reviewed']),
          expectedTaskSnapshot: store.taskSnapshot,
        );
        expect(result.error, isA<FormatFailure>());
        expect(result.committedIds, isEmpty);
        expect(await folder.delegate.read('${store.writer}.jsonl'), before);
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
}

class CountingFolder implements LogFolder, RangeLogFolder, BoundedLogFolder {
  CountingFolder(this.delegate);
  final LocalLogFolder delegate;
  int appends = 0, lists = 0, reads = 0;
  String? fault;
  bool failList = false;
  String? delayedName;
  Uint8List? delayedSuffix;
  Future<void> revealPending() async {
    await delegate.append(delayedName!, delayedSuffix!);
    delayedName = null;
    delayedSuffix = null;
  }

  void reset() {
    appends = lists = reads = 0;
  }

  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() async {
    lists++;
    if (failList) {
      failList = false;
      throw StateError('Injected cache refresh failure');
    }
    return delegate.list();
  }

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      delegate.readBounded(name, maximumBytes);
  @override
  Future<Uint8List> read(String name) {
    reads++;
    return delegate.read(name);
  }

  @override
  Future<Uint8List> readFrom(String name, int offset) {
    reads++;
    return delegate.readFrom(name, offset);
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    final current = fault;
    fault = null;
    if (current == 'before') {
      delayedName = name;
      delayedSuffix = bytes;
      throw StateError('Injected before write');
    }
    if (current == 'prefix' || current == 'tail') {
      final end = bytes.indexOf(10) + 1;
      if (current == 'prefix') {
        delayedName = name;
        delayedSuffix = Uint8List.sublistView(bytes, end);
      }
      await delegate.append(
        name,
        Uint8List.sublistView(
          bytes,
          0,
          current == 'prefix' ? end : end + (bytes.length - end) ~/ 2,
        ),
      );
      throw StateError('Injected interrupted append');
    }
    await delegate.append(name, bytes);
    if (current == 'after') {
      throw StateError('Injected acknowledgement failure');
    }
    if (current == 'cache') failList = true;
  }
}
