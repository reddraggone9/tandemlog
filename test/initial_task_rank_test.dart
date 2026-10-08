import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import 'batch_storage_test.dart' show CountingFolder;

List<String> taskIds(TaskStore store) => [
  for (final row in store.rows.where((row) => row['kind'] == 'task'))
    row['id'] as String,
];

void main() {
  for (final native in [false, true]) {
    test(
      '${native ? 'native' : 'scalar'} capture retains top rank after Inbox triage and replay',
      () async {
        final root = await Directory.systemTemp.createTemp('initial-rank-');
        final shared = await Directory('${root.path}/shared').create();
        final folder = CountingFolder(LocalLogFolder(shared.path));
        final engine = native
            ? NativeTextEngine(
                libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
              )
            : null;
        final store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4(),
            a = const Uuid().v4(),
            b = const Uuid().v4();
        final first = const Uuid().v4(), second = const Uuid().v4();
        try {
          await store.command(user, 'user.created', {'name': 'Synthetic'});
          for (final id in [a, b]) {
            await store.command(id, 'task.created', {
              'title': id == a ? 'Older A' : 'Older B',
              'description': 'Organized',
              'assignee': user,
            });
          }
          await store.moveBefore(b, a);
          expect(taskIds(store), [b, a]);
          final originalBytes = await folder.read('${store.writer}.jsonl');
          folder.reset();
          expect(
            (await store.createTasks({
              first: 'First new',
              second: 'Second new',
            }, user)).succeeded,
            isTrue,
          );
          expect(
            folder.appends,
            1,
            reason:
                'Capture and its explicit initial positions share one flush.',
          );
          expect(taskIds(store), [first, second, b, a]);
          final withCapture = await folder.read('${store.writer}.jsonl');
          expect(withCapture.take(originalBytes.length), originalBytes);
          for (final id in [first, second]) {
            await store.command(id, 'task.edited', {'description': 'Triaged'});
          }
          final view = projectTaskView(
            store.rows,
            ViewTime(
              instant: DateTime.utc(2026, 10, 8),
              localZoneId: 'UTC',
              localOffset: Duration.zero,
            ),
          ).value;
          expect(view.open.map((row) => row.task['id']), [first, second, b, a]);
          expect(view.open.every((row) => !row.inbox), isTrue);
          final beforeRetry = await folder.read('${store.writer}.jsonl');
          folder.reset();
          expect(
            (await store.createTasks({
              first: 'First new',
              second: 'Second new',
            }, user)).succeeded,
            isTrue,
          );
          expect(
            folder.appends,
            0,
            reason:
                'A repeated capture must not move independently reordered tasks.',
          );
          expect(await folder.read('${store.writer}.jsonl'), beforeRetry);
          final peer = await TaskStore.open(
            folder.delegate,
            '${root.path}/peer',
            textEngine: engine,
          );
          try {
            await peer.moveBefore(a, first);
            await store.refresh();
            expect(taskIds(store), [a, first, second, b]);
            await store.createTasks({
              first: 'First new',
              second: 'Second new',
            }, user);
            expect(taskIds(store), [a, first, second, b]);
            final cold = await TaskStore.open(
              folder.delegate,
              '${root.path}/fresh-cache',
              textEngine: engine,
            );
            try {
              expect(taskIds(cold), taskIds(store));
              expect(cold.rows, store.rows);
            } finally {
              await cold.close();
            }
          } finally {
            await peer.close();
          }
        } finally {
          await store.close();
        }
        // Retain this synthetic fixture and its canonical bytes as recovery evidence.
      },
      skip: native && Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
          ? 'Reviewed native library required.'
          : false,
    );
  }

  test(
    'legacy creations and retries retain their released append order',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'initial-rank-legacy-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      final user = const Uuid().v4(),
          a = const Uuid().v4(),
          b = const Uuid().v4();
      try {
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        for (final id in [a, b]) {
          await store.command(id, 'task.created', {
            'title': 'Historical',
            'description': '',
            'assignee': user,
          });
        }
        final bytes = await folder.read('${store.writer}.jsonl');
        await store.createTasks({a: 'Historical', b: 'Historical'}, user);
        expect(taskIds(store), [a, b]);
        expect(await folder.read('${store.writer}.jsonl'), bytes);
        final cold = await TaskStore.open(folder, '${root.path}/cold');
        try {
          expect(taskIds(cold), [a, b]);
        } finally {
          await cold.close();
        }
      } finally {
        await store.close();
      }
    },
  );

  test(
    'complete-prefix capture waits for initial position and retries exact suffix',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'initial-rank-prefix-',
      );
      final folder = CountingFolder(
        LocalLogFolder((await Directory('${root.path}/shared').create()).path),
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      final user = const Uuid().v4(),
          old = const Uuid().v4(),
          fresh = const Uuid().v4();
      try {
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(old, 'task.created', {
          'title': 'Old',
          'description': 'Organized',
          'assignee': user,
        });
        folder.fault = 'prefix';
        final partial = await store.createTasks({fresh: 'New'}, user);
        expect(partial.error, isNotNull);
        expect(
          partial.committedIds,
          isEmpty,
          reason:
              'Creation alone has not established the promised initial rank.',
        );
        expect(partial.remainingIds, [fresh]);
        expect(partial.createdIds, [fresh]);
        final blocked = await store.createTasks({fresh: 'New'}, user);
        expect(blocked.error, isA<WriterGuardFailure>());
        expect(blocked.committedIds, isEmpty);
        expect(blocked.createdIds, [fresh]);
        await folder.revealPending();
        await store.refresh();
        final restored = await folder.read('${store.writer}.jsonl');
        expect(
          (await store.createTasks({fresh: 'New'}, user)).succeeded,
          isTrue,
        );
        expect(await folder.read('${store.writer}.jsonl'), restored);
        expect(taskIds(store), [fresh, old]);
        final events = utf8
            .decode(restored)
            .trim()
            .split('\n')
            .map(LogEvent.decode)
            .toList();
        expect(
          events
              .where((e) => e.entity == fresh && e.type == 'task.created')
              .length,
          1,
        );
        expect(
          events
              .where((e) => e.entity == fresh && e.type == 'task.moved')
              .length,
          1,
        );
      } finally {
        await store.close();
      }
    },
  );

  test(
    'native capture never exposes creation intent before placement reservation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'initial-rank-prepare-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final guard = FailPrepareGuard(FileWriterGuard('${root.path}/profile'));
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final store = await TaskStore.open(
        folder,
        '${root.path}/profile',
        writerGuard: guard,
        textEngine: engine,
      );
      final user = const Uuid().v4(),
          old = const Uuid().v4(),
          fresh = const Uuid().v4();
      try {
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(old, 'task.created', {
          'title': 'Old',
          'description': 'Organized',
          'assignee': user,
        });
        final original = await folder.read('${store.writer}.jsonl');
        guard.failNext = true;
        final failed = await store.createTasks({fresh: 'New'}, user);
        expect(failed.error, isA<FileSystemException>());
        expect(failed.createdIds, isEmpty);
        expect(
          store.pendingTextOperations,
          isEmpty,
          reason:
              'An unreserved creation must not survive as an individually retryable native intent without its placement.',
        );
        expect(await folder.read('${store.writer}.jsonl'), original);
        expect(
          (await store.createTasks({fresh: 'New'}, user)).succeeded,
          isTrue,
        );
        expect(taskIds(store), [fresh, old]);
      } finally {
        await store.close();
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
        ? 'Reviewed native library required.'
        : false,
  );

  test(
    'global first rank covers completed and other-assignee hidden tasks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'initial-rank-hidden-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      final user = const Uuid().v4(), other = const Uuid().v4();
      final completed = const Uuid().v4(),
          hidden = const Uuid().v4(),
          visible = const Uuid().v4();
      final first = const Uuid().v4(), latest = const Uuid().v4();
      try {
        for (final id in [user, other]) {
          await store.command(id, 'user.created', {'name': 'Synthetic'});
        }
        for (final id in [completed, hidden, visible]) {
          await store.command(id, 'task.created', {
            'title': 'Existing',
            'description': 'Organized',
            'assignee': id == hidden ? other : user,
          });
        }
        await store.complete(completed, completionDay: DateTime(2026, 10, 8));
        await store.createTasks({first: 'New'}, user);
        expect(taskIds(store), [first, completed, hidden, visible]);
        await store.command(first, 'task.edited', {'description': 'Triaged'});
        await store.createTasks({latest: 'Latest'}, user);
        await store.command(latest, 'task.edited', {'description': 'Triaged'});
        expect(taskIds(store), [latest, first, completed, hidden, visible]);
        final view = projectTaskView(
          store.rows,
          ViewTime(
            instant: DateTime.utc(2026, 10, 8),
            localZoneId: 'UTC',
            localOffset: Duration.zero,
          ),
          assignee: user,
        ).value;
        expect(view.open.map((row) => row.task['id']), [
          latest,
          first,
          visible,
        ]);
        expect(view.completed.map((row) => row.task['id']), [completed]);
      } finally {
        await store.close();
      }
    },
  );

  for (final prefix in [1, 2, 3]) {
    test(
      'multiline $prefix-record prefix retains exact placements through peer arrival and retry',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'initial-rank-prefix-$prefix-',
        );
        final folder = PrefixFolder(
          LocalLogFolder(
            (await Directory('${root.path}/shared').create()).path,
          ),
        );
        final store = await TaskStore.open(folder, '${root.path}/profile');
        final user = const Uuid().v4(), old = const Uuid().v4();
        final first = const Uuid().v4(),
            second = const Uuid().v4(),
            incoming = const Uuid().v4();
        try {
          await store.command(user, 'user.created', {'name': 'Synthetic'});
          await store.command(old, 'task.created', {
            'title': 'Old',
            'description': 'Organized',
            'assignee': user,
          });
          folder.prefixRecords = prefix;
          final partial = await store.createTasks({
            first: 'First',
            second: 'Second',
          }, user);
          expect(partial.error, isNotNull);
          expect(partial.createdIds, prefix == 1 ? [first] : [first, second]);
          expect(partial.committedIds, prefix == 3 ? [first] : isEmpty);
          final peer = await TaskStore.open(
            folder.delegate,
            '${root.path}/peer',
          );
          try {
            await peer.createTasks({incoming: 'Incoming'}, user);
            await store.refresh();
            final blocked = await store.createTasks({
              first: 'First',
              second: 'Second',
            }, user);
            expect(blocked.error, isA<WriterGuardFailure>());
            await folder.revealPending();
            await store.refresh();
            final original = await folder.read('${store.writer}.jsonl');
            expect(
              (await store.createTasks({
                first: 'First',
                second: 'Second',
              }, user)).succeeded,
              isTrue,
            );
            expect(await folder.read('${store.writer}.jsonl'), original);
            final events = utf8
                .decode(original)
                .trim()
                .split('\n')
                .map(LogEvent.decode)
                .toList();
            for (final id in [first, second]) {
              expect(
                events
                    .where((e) => e.entity == id && e.type == 'task.created')
                    .length,
                1,
              );
              expect(
                events
                    .singleWhere(
                      (e) => e.entity == id && e.type == 'task.moved',
                    )
                    .data,
                {'before': old},
                reason:
                    'Incoming order does not regenerate the reserved anchor.',
              );
            }
            expect(
              taskIds(store).indexOf(first),
              lessThan(taskIds(store).indexOf(second)),
            );
            expect(
              taskIds(store).indexOf(second),
              lessThan(taskIds(store).indexOf(old)),
            );
            final cold = await TaskStore.open(
              ReverseListingFolder(folder.location),
              '${root.path}/cold',
            );
            try {
              expect(cold.rows, store.rows);
            } finally {
              await cold.close();
            }
          } finally {
            await peer.close();
          }
        } finally {
          await store.close();
        }
      },
    );
  }
}

class PrefixFolder extends CountingFolder {
  PrefixFolder(super.delegate);
  int? prefixRecords;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final prefix = prefixRecords;
    if (prefix == null) return super.append(name, bytes);
    prefixRecords = null;
    var boundary = -1;
    for (var i = 0; i < prefix; i++) {
      boundary = bytes.indexOf(10, boundary + 1);
    }
    if (boundary < 0) throw StateError('Fixture requires the reserved prefix.');
    delayedName = name;
    delayedSuffix = Uint8List.sublistView(bytes, boundary + 1);
    await delegate.append(name, Uint8List.sublistView(bytes, 0, boundary + 1));
    throw StateError('Synthetic complete prefix interruption');
  }
}

class ReverseListingFolder extends LocalLogFolder {
  ReverseListingFolder(super.location);
  @override
  Future<List<LogFileInfo>> list() async =>
      (await super.list()).reversed.toList();
}

class FailPrepareGuard implements WriterGuard {
  FailPrepareGuard(this.delegate);
  final WriterGuard delegate;
  bool failNext = false;
  @override
  Future<WriterGuardState?> load(String space, String writer) =>
      delegate.load(space, writer);
  @override
  Future<void> acknowledge(
    String space,
    String writer,
    int sequence,
    String hash,
  ) => delegate.acknowledge(space, writer, sequence, hash);
  @override
  Future<void> prepare(
    String space,
    String writer,
    int sequence,
    String hash,
    List<PreparedWriterRecord> records,
  ) {
    if (failNext) {
      failNext = false;
      throw const FileSystemException('Synthetic reservation failure');
    }
    return delegate.prepare(space, writer, sequence, hash, records);
  }
}
