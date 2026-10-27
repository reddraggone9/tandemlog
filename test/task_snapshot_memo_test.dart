import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  late TaskStore store;
  late String user, first, second;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('task-snapshot-memo-');
    final folder = await Directory('${root.path}/shared').create();
    store = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/profile',
    );
    user = const Uuid().v4();
    first = const Uuid().v4();
    second = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic user'});
    for (final id in [first, second]) {
      await store.command(id, 'task.created', {
        'title': 'Unicode café / "quoted"\n$id',
        'description': 'Synthetic Notes',
        'assignee': user,
      });
    }
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  String oracle() =>
      jsonEncode(store.rows.where((row) => row['kind'] == 'task').toList());
  String raw(String id) =>
      store.db.select('SELECT raw FROM ${store.tables.views} WHERE id=?', [
            id,
          ]).single['raw']
          as String;
  void setRaw(String id, String value) => store.db.execute(
    'UPDATE ${store.tables.views} SET raw=? WHERE id=?',
    [value, id],
  );

  test(
    'unchanged SQL rows reuse exact serialization, not freshness authority',
    () async {
      final expected = oracle();
      expect(store.taskSnapshot, expected);
      final decoded = store.taskSnapshotRowsDecoded;
      for (var i = 0; i < 5; i++) {
        expect(store.taskSnapshot, expected);
      }
      expect(store.taskSnapshotRowsDecoded, decoded);
      final old = raw(first);
      // Even semantically equal but differently encoded cache bytes must be read.
      setRaw(first, ' $old ');
      expect(store.taskSnapshot, expected);
      expect(store.taskSnapshotRowsDecoded, greaterThan(decoded));
      setRaw(first, old);
      await store.command(first, 'task.edited', {
        'description': 'Changed Notes',
      });
      expect(store.taskSnapshot, oracle());
      expect(store.taskSnapshot, isNot(expected));
      await expectLater(
        store.deleteTasks([first], expectedTaskSnapshot: expected),
        throwsA(isA<StaleTaskSnapshot>()),
      );
    },
  );

  test('staged edits and rollback both use the live SQL value', () {
    final original = store.taskSnapshot;
    final old = raw(first);
    final failure = StateError('projection rollback');
    expect(
      () => store.profileDatabase!.transaction<Never>(() {
        setRaw(
          first,
          jsonEncode({
            ...jsonDecode(old) as Map<String, dynamic>,
            'title': 'Staged',
          }),
        );
        expect(store.taskSnapshot, oracle());
        expect(store.taskSnapshot, isNot(original));
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(store.taskSnapshot, original);
    expect(store.taskSnapshot, oracle());
  });

  test(
    'visibility, order, user-only rows and malformed SQL remain observable',
    () {
      final original = store.taskSnapshot;
      final saved = raw(first);
      for (final field in ['deleted', 'successorSuppressed']) {
        setRaw(
          first,
          jsonEncode({
            ...jsonDecode(saved) as Map<String, dynamic>,
            field: true,
          }),
        );
        expect(store.taskSnapshot, oracle());
        expect(store.taskSnapshot, isNot(original));
        setRaw(first, saved);
      }
      final userRaw = raw(user);
      setRaw(
        user,
        jsonEncode({
          ...jsonDecode(userRaw) as Map<String, dynamic>,
          'title': 'Renamed user',
        }),
      );
      expect(store.taskSnapshot, original);
      setRaw(user, userRaw);
      final rank = store.db.select(
        'SELECT rank FROM ${store.tables.positions} WHERE id=?',
        [second],
      ).single['rank'];
      store.db.execute(
        'UPDATE ${store.tables.positions} SET rank=-1 WHERE id=?',
        [second],
      );
      expect(store.taskSnapshot, oracle());
      expect(store.taskSnapshot, isNot(original));
      store.db.execute(
        'UPDATE ${store.tables.positions} SET rank=? WHERE id=?',
        [rank, second],
      );
      expect(
        () => setRaw(first, 'invalid JSON'),
        throwsA(isA<SqliteException>()),
      );
      setRaw(first, saved);
      expect(store.taskSnapshot, original);
    },
  );

  test(
    'oversized representations are not retained; close releases the memo',
    () async {
      final original = raw(first);
      setRaw(
        first,
        jsonEncode({
          ...jsonDecode(original) as Map<String, dynamic>,
          'description': List.filled(1100000, 'x').join(),
        }),
      );
      final expected = oracle();
      expect(store.taskSnapshot, expected);
      expect(store.cachedTaskSnapshotBytes, 0);
      final decoded = store.taskSnapshotRowsDecoded;
      expect(store.taskSnapshot, expected);
      expect(store.taskSnapshotRowsDecoded, greaterThan(decoded));
      setRaw(first, original);
      expect(store.taskSnapshot, oracle());
      expect(store.cachedTaskSnapshotBytes, greaterThan(0));
      await store.close();
      expect(store.cachedTaskSnapshotBytes, 0);
      expect(() => store.taskSnapshot, throwsStateError);
    },
  );
}
