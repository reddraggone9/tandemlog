import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root, shared;
  late TaskStore store;
  late String user;
  late List<String> ids;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bulk-selection-projection-');
    shared = await Directory('${root.path}/shared').create();
    store = await TaskStore.open(
      LocalLogFolder(shared.path),
      '${root.path}/profile',
    );
    user = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    final titles = {
      for (var i = 0; i < 50; i++) const Uuid().v4(): 'Café ☕ $i',
    };
    await store.createTasks(titles, user);
    ids = store.rows
        .where((r) => r['kind'] == 'task')
        .map((r) => r['id'] as String)
        .toList();
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  Future<Map<String, List<int>>> bytes() async => {
    for (final file in shared.listSync().cast<File>())
      file.uri.pathSegments.last: await file.readAsBytes(),
  };
  for (final action in ['delete', 'edit', 'move']) {
    test(
      'bulk $action uses global selection order and exact Undo with unrelated rows',
      () async {
        final selected = [ids[1], ids[23], ids[40]];
        final before = jsonEncode(store.rows);
        final original = await bytes();
        final sequence = store.unified!.physicalSequence;
        final receipts = <OperationReceipt>[];
        final input = selected.reversed.toList();
        final snapshot = store.taskSnapshot;
        final result = switch (action) {
          'delete' => await store.deleteTasks(
            input,
            expectedTaskSnapshot: snapshot,
            onPrepared: receipts.add,
          ),
          'edit' => await store.bulkEdit(
            input,
            BulkTaskEdit(addTags: ['selected']),
            expectedTaskSnapshot: snapshot,
            onPrepared: receipts.add,
          ),
          _ => await store.moveBlockBefore(
            input,
            null,
            expectedTaskSnapshot: snapshot,
            canCommit: () => true,
            onPrepared: receipts.add,
          ),
        };
        expect(result.succeeded, isTrue);
        expect(result.committedIds, selected);
        expect(receipts.map((r) => r.entity), selected);
        expect(
          store.confirmedOperations(receipts),
          receipts.map((r) => r.id).toSet(),
        );
        expect(store.unified!.physicalSequence - sequence, 1);
        if (action == 'move') {
          expect(
            store.rows.where((r) => r['kind'] == 'task').map((r) => r['id']),
            [...ids.where((id) => !selected.contains(id)), ...selected],
          );
        }
        if (action == 'edit') {
          expect(
            store.rows
                .where((r) => selected.contains(r['id']))
                .every((r) => (r['tags'] as List).contains('selected')),
            isTrue,
          );
        }
        final undone = await store.undoOperations(
          receipts.map((r) => r.id).toList(),
        );
        expect(undone.error, isNull);
        expect(undone.remaining, isEmpty);
        expect(store.unified!.physicalSequence - sequence, 2);
        expect(jsonEncode(store.rows), before);
        final after = await bytes();
        for (final entry in original.entries) {
          expect(after[entry.key]!.take(entry.value.length), entry.value);
          if (entry.key != '${store.writer}.applog') {
            expect(after[entry.key], entry.value);
          }
        }
      },
    );
  }

  test(
    'stale snapshot wins before invalid selection; fresh invalid selections never append',
    () async {
      final old = store.taskSnapshot;
      await store.command(ids.last, 'task.edited', {'description': 'Changed'});
      final before = await bytes();
      await expectLater(
        store.deleteTasks([ids.first, ids.first], expectedTaskSnapshot: old),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      final fresh = store.taskSnapshot;
      for (final input in <List<String>>[
        [],
        [ids.first, ids.first],
        [user],
        [ids.first, const Uuid().v4()],
      ]) {
        await expectLater(
          store.deleteTasks(input, expectedTaskSnapshot: fresh),
          throwsA(isA<FormatFailure>()),
        );
        expect(await bytes(), before);
      }
    },
  );

  for (final condition in [
    'deleted',
    'successorSuppressed',
    'user',
    'checklistItem',
    'unpositioned',
    'duplicateLogicalId',
  ]) {
    test(
      'selection reads live $condition SQL after the caller guard without memo authority',
      () async {
        final selected = [ids[1], ids[23], ids[40]];
        final snapshot = store.taskSnapshot;
        final before = await bytes();
        var called = false;
        await expectLater(
          store.deleteTasks(
            selected,
            expectedTaskSnapshot: snapshot,
            canCommit: () {
              if (called) return true;
              called = true;
              // Stage a private projection change in the same queue turn, after the
              // comparison token check. Selection must still read these SQL values.
              if (condition == 'unpositioned') {
                store.db.execute(
                  'DELETE FROM ${store.tables.positions} WHERE id=?',
                  [selected.first],
                );
              } else {
                final target = condition == 'duplicateLogicalId'
                    ? ids.last
                    : selected.first;
                final raw =
                    store.db.select(
                          'SELECT raw FROM ${store.tables.views} WHERE id=?',
                          [target],
                        ).single['raw']
                        as String;
                final row = jsonDecode(raw) as Map<String, dynamic>;
                if (condition == 'deleted' ||
                    condition == 'successorSuppressed') {
                  row[condition] = true;
                } else if (condition == 'duplicateLogicalId') {
                  row['id'] = selected.first;
                } else {
                  row['kind'] = condition;
                }
                store.db.execute(
                  'UPDATE ${store.tables.views} SET raw=? WHERE id=?',
                  [jsonEncode(row), target],
                );
              }
              return true;
            },
          ),
          throwsA(
            isA<FormatFailure>().having(
              (e) => e.message,
              'message',
              'Selection contains a missing or deleted task.',
            ),
          ),
        );
        expect(called, isTrue);
        expect(await bytes(), before);
      },
    );
  }

  void replaceRaw(String id, String Function(String) update) {
    final raw =
        store.db.select('SELECT raw FROM ${store.tables.views} WHERE id=?', [
              id,
            ]).single['raw']
            as String;
    store.db.execute('UPDATE ${store.tables.views} SET raw=? WHERE id=?', [
      update(raw),
      id,
    ]);
  }

  for (final selected in [false, true]) {
    for (final afterGuard in [false, true]) {
      test(
        'strict Dart JSON refusal selected=$selected afterGuard=$afterGuard',
        () async {
          final snapshot = store.taskSnapshot;
          final before = await bytes();
          void inject() => replaceRaw(
            selected ? ids.first : ids.last,
            (raw) => '$raw /* synthetic JSON5 accepted by SQLite, not Dart */',
          );
          if (!afterGuard) inject();
          var called = false;
          await expectLater(
            store.deleteTasks(
              [ids.first],
              expectedTaskSnapshot: snapshot,
              canCommit: () {
                if (!called && afterGuard) inject();
                called = true;
                return true;
              },
            ),
            throwsA(isA<FormatException>()),
          );
          expect(called, afterGuard);
          expect(await bytes(), before);
        },
      );
    }
  }

  for (final afterGuard in [false, true]) {
    test(
      'duplicate selected ID labels retain Dart last-label semantics afterGuard=$afterGuard',
      () async {
        final snapshot = store.taskSnapshot;
        final sequence = store.unified!.physicalSequence;
        void inject() => replaceRaw(
          ids.first,
          (raw) => '{"id":"unselected-first-label",${raw.substring(1)}',
        );
        if (!afterGuard) inject();
        final expected = afterGuard ? snapshot : store.taskSnapshot;
        var called = false;
        final receipts = <OperationReceipt>[];
        final result = await store.deleteTasks(
          [ids.first],
          expectedTaskSnapshot: expected,
          canCommit: () {
            if (!called && afterGuard) inject();
            called = true;
            return true;
          },
          onPrepared: receipts.add,
        );
        expect(result.succeeded, isTrue);
        expect(receipts.single.entity, ids.first);
        expect(store.unified!.physicalSequence - sequence, 1);
        final undone = await store.undoOperations([receipts.single.id]);
        expect(undone.error, isNull);
        expect(undone.remaining, isEmpty);
        expect(
          store.rows.where((r) => r['id'] == ids.first).single['deleted'],
          isNot(true),
        );
      },
    );

    test(
      'duplicate unselected ID labels cannot evade cardinality refusal afterGuard=$afterGuard',
      () async {
        final snapshot = store.taskSnapshot;
        final before = await bytes();
        // First label remains the physical/logical unrelated ID; Dart's last
        // label makes this a second match. A SQL-only filter would miss it.
        void inject() => replaceRaw(
          ids.last,
          (raw) =>
              '${raw.substring(0, raw.length - 1)},"id":${jsonEncode(ids.first)}}',
        );
        if (!afterGuard) inject();
        final expected = afterGuard ? snapshot : store.taskSnapshot;
        var called = false;
        await expectLater(
          store.deleteTasks(
            [ids.first],
            expectedTaskSnapshot: expected,
            canCommit: () {
              if (!called && afterGuard) inject();
              called = true;
              return true;
            },
          ),
          throwsA(
            isA<FormatFailure>().having(
              (e) => e.message,
              'message',
              'Selection contains a missing or deleted task.',
            ),
          ),
        );
        expect(await bytes(), before);
      },
    );
  }

  test(
    'false guard still wins before decoding its staged malformed row',
    () async {
      final snapshot = store.taskSnapshot;
      final before = await bytes();
      await expectLater(
        store.deleteTasks(
          [ids.first],
          expectedTaskSnapshot: snapshot,
          canCommit: () {
            replaceRaw(ids.last, (raw) => '$raw /* synthetic JSON5 */');
            return false;
          },
        ),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      expect(await bytes(), before);
    },
  );

  test(
    'large missing selection retains validation without a SQL parameter per ID',
    () async {
      final before = await bytes();
      await expectLater(
        store.deleteTasks([
          ids.first,
          for (var i = 0; i < 33000; i++) 'missing-$i',
        ], expectedTaskSnapshot: store.taskSnapshot),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.message,
            'message',
            'Selection contains a missing or deleted task.',
          ),
        ),
      );
      expect(await bytes(), before);
    },
  );
}
