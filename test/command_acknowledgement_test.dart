import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

/// Append succeeds, then a transport replaces the stream before reconciliation.
/// The previously committed prefix is preserved byte-for-byte.
class _ReplacingFolder implements LogFolder {
  _ReplacingFolder(this.inner);
  final LocalLogFolder inner;
  int? keepNewRecords;
  bool replaceNewTitle = false;
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
    final keep = keepNewRecords;
    final replace = replaceNewTitle;
    keepNewRecords = null;
    replaceNewTitle = false;
    final previous = await inner.read(name);
    await inner.append(name, bytes);
    if (keep == null && !replace) return;
    final lines = utf8.decode(bytes).split('\n')..removeLast();
    String suffix;
    if (replace) {
      final event = jsonDecode(lines.single) as Map<String, dynamic>;
      (event['data'] as Map<String, dynamic>)['title'] =
          'Transport replacement';
      suffix = '${jsonEncode(event)}\n';
    } else {
      suffix = lines.take(keep!).map((line) => '$line\n').join();
    }
    final temporary = File('$location/replacement.tmp');
    await temporary.writeAsBytes([
      ...previous,
      ...utf8.encode(suffix),
    ], flush: true);
    await temporary.rename('$location/$name');
  }
}

void main() {
  late Directory root;
  late _ReplacingFolder folder;
  late TaskStore store;
  late String user;
  Future<String> task() async {
    final id = const Uuid().v4();
    await store.command(id, 'task.created', {
      'title': 'Original',
      'description': '',
      'assignee': user,
    });
    return id;
  }

  Map<String, dynamic> row(String id) =>
      store.rows.firstWhere((r) => r['id'] == id);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('command-ack-');
    folder = _ReplacingFolder(
      LocalLogFolder((await Directory('${root.path}/shared').create()).path),
    );
    store = await TaskStore.open(folder, '${root.path}/private');
    user = const Uuid().v4();
    // The hook reads an existing stream, so the initial user append is ordinary.
    await folder.create('${store.writer}.jsonl', Uint8List(0));
    await store.command(user, 'user.created', {'name': 'Example'});
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'single edit must fail when transport drops newly appended event',
    () async {
      final id = await task();
      final receipts = <OperationReceipt>[];
      folder.keepNewRecords = 0;
      await expectLater(
        store.edit(
          id,
          {'title': 'Draft'},
          tags: [],
          observedTagRefs: {},
          onPrepared: receipts.add,
        ),
        throwsA(anything),
      );
      expect(row(id)['title'], 'Original');
      expect(store.confirmedOperations(receipts), isEmpty);
      // A deliberate retry can reuse the sequence, but only its own raw receipt confirms.
      final retry = <OperationReceipt>[];
      await store.edit(
        id,
        {'title': 'Retry'},
        tags: [],
        observedTagRefs: {},
        onPrepared: retry.add,
      );
      expect(retry.single.id, receipts.single.id);
      expect(store.confirmedOperations(receipts), isEmpty);
      expect(store.confirmedOperations(retry), {retry.single.id});
    },
  );

  test(
    'single command must not acknowledge different bytes with the same event ID',
    () async {
      final id = await task();
      final receipts = <OperationReceipt>[];
      folder.replaceNewTitle = true;
      await expectLater(
        store.command(id, 'task.edited', {
          'title': 'Draft',
        }, onPrepared: receipts.add),
        throwsA(anything),
      );
      expect(row(id)['title'], 'Transport replacement');
      expect(store.confirmedOperations(receipts), isEmpty);
    },
  );

  for (final keep in [0, 1]) {
    for (final action in ['create', 'edit', 'delete']) {
      test(
        '$action batch reports $keep confirmed records after suffix replacement',
        () async {
          final ids = action == 'create'
              ? [const Uuid().v4(), const Uuid().v4()]
              : [await task(), await task()];
          folder.keepNewRecords = keep;
          final BulkTaskResult result;
          if (action == 'create') {
            result = await store.createTasks({
              for (final id in ids) id: 'Draft',
            }, user);
          } else if (action == 'edit') {
            result = await store.bulkEdit(
              ids,
              BulkTaskEdit(addTags: ['Draft']),
              expectedTaskSnapshot: store.taskSnapshot,
            );
          } else {
            result = await store.deleteTasks(
              ids,
              expectedTaskSnapshot: store.taskSnapshot,
            );
          }
          expect(result.succeeded, isFalse);
          expect(result.error, isNotNull);
          expect(result.committedIds, ids.take(keep));
          expect(result.remainingIds, ids.skip(keep));
          if (action == 'create') {
            expect(ids.where(store.hasEntity), ids.take(keep));
          } else if (action == 'edit') {
            expect(
              ids.where((id) => (row(id)['tags'] as List).contains('Draft')),
              ids.take(keep),
            );
          } else {
            expect(
              ids.where((id) => !store.rows.any((task) => task['id'] == id)),
              ids.take(keep),
            );
          }
          final BulkTaskResult retry;
          if (action == 'create') {
            retry = await store.createTasks({
              for (final id in ids) id: 'Draft',
            }, user);
          } else if (action == 'edit') {
            retry = await store.bulkEdit(
              result.remainingIds,
              BulkTaskEdit(addTags: ['Draft']),
              expectedTaskSnapshot: store.taskSnapshot,
            );
          } else {
            retry = await store.deleteTasks(
              result.remainingIds,
              expectedTaskSnapshot: store.taskSnapshot,
            );
          }
          expect(retry.succeeded, isTrue);
          expect(retry.remainingIds, isEmpty);
        },
      );
    }

    test(
      'reopen must fail and retain unconfirmed completion targets ($keep prefix)',
      () async {
        final id = await task();
        await store.command(id, 'task.completed', {});
        await store.command(id, 'task.completed', {});
        final targets = store.activeCompletionIds(id);
        folder.keepNewRecords = keep;
        await expectLater(store.reopen(id, targets), throwsA(anything));
        expect(store.activeCompletionIds(id), targets.skip(keep));
        await store.reopen(id, targets);
        expect(row(id)['completed'], isFalse);
      },
    );

    test(
      'Undo reports only confirmed retractions and preserves retry ($keep prefix)',
      () async {
        final ids = [await task(), await task()];
        final receipts = <OperationReceipt>[];
        await store.bulkEdit(
          ids,
          BulkTaskEdit(addTags: ['Draft']),
          expectedTaskSnapshot: store.taskSnapshot,
          onPrepared: receipts.add,
        );
        final operations = receipts.map((r) => r.id).toList();
        folder.keepNewRecords = keep;
        final result = await store.undoOperations(operations);
        expect(result.error, isNotNull);
        expect(result.undone, operations.take(keep));
        expect(result.remaining, operations.skip(keep));
        expect(
          ids.where((id) => (row(id)['tags'] as List).isEmpty),
          ids.take(keep),
        );
        final retry = await store.undoOperations(result.remaining);
        expect(retry.error, isNull);
        expect(retry.remaining, isEmpty);
        expect(ids.every((id) => (row(id)['tags'] as List).isEmpty), isTrue);
      },
    );
  }

  test('incomplete BulkTaskResult cannot report success without an error', () {
    expect(BulkTaskResult(['committed'], ['remaining']).succeeded, isFalse);
  });
}
