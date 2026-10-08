import 'dart:convert';
import 'dart:io';

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
            reason: 'A repeated capture must not move independently reordered tasks.',
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

  test('complete-prefix capture waits for initial position and retries exact suffix', () async {
    final root = await Directory.systemTemp.createTemp('initial-rank-prefix-');
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
        reason: 'Creation alone has not established the promised initial rank.',
      );
      expect(partial.remainingIds, [fresh]);
      await folder.revealPending();
      await store.refresh();
      final restored = await folder.read('${store.writer}.jsonl');
      expect((await store.createTasks({fresh: 'New'}, user)).succeeded, isTrue);
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
        events.where((e) => e.entity == fresh && e.type == 'task.moved').length,
        1,
      );
    } finally {
      await store.close();
    }
  });
}
