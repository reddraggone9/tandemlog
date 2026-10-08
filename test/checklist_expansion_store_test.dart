import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/checklist_expansion_store.dart';

void main() {
  const first = '11111111-1111-4111-8111-111111111111';
  const second = '22222222-2222-4222-8222-222222222222';
  late Database db;
  late ChecklistExpansionStore state;
  setUp(() {
    db = sqlite3.openInMemory();
    db.execute(
      'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      "INSERT INTO metadata VALUES ('space','synthetic-space'),('order_projection','3'),('replay_pending','1')",
    );
    state = ChecklistExpansionStore(db);
  });
  tearDown(() => db.close());
  test('sparse local expansion preserves other metadata and normal reopen', () {
    expect(state.load(), isEmpty);
    state.setExpanded([first, second, first], true);
    expect(ChecklistExpansionStore(db).load(), {first, second});
    state.setExpanded([first], false);
    expect(state.load(), {second});
    expect(
      db.select('SELECT key FROM metadata WHERE key=?', [
        '${ChecklistExpansionStore.prefix}$first',
      ]),
      isEmpty,
    );
    expect(
      db.select('SELECT value FROM metadata WHERE key=?', [
        'space',
      ]).single['value'],
      'synthetic-space',
    );
    expect(
      db.select('SELECT value FROM metadata WHERE key=?', [
        'order_projection',
      ]).single['value'],
      '3',
    );
    expect(
      db.select('SELECT value FROM metadata WHERE key=?', [
        'replay_pending',
      ]).single['value'],
      '1',
    );
  });
  test(
    'cache reset defaults collapsed and invalid local values are ignored',
    () {
      db.execute('INSERT INTO metadata VALUES (?,?), (?,?), (?,?)', [
        '${ChecklistExpansionStore.prefix}$first',
        '0',
        '${ChecklistExpansionStore.prefix}invalid',
        '1',
        '${ChecklistExpansionStore.prefix}$second',
        'unknown',
      ]);
      expect(state.load(), isEmpty);
      state.setExpanded([first], true);
      db.execute('DELETE FROM metadata WHERE key LIKE ?', [
        '${ChecklistExpansionStore.prefix}%',
      ]);
      expect(ChecklistExpansionStore(db).load(), isEmpty);
    },
  );
  test(
    'bad IDs and an active canonical transaction cannot cause partial UI writes',
    () {
      expect(
        () => state.setExpanded([first, 'invalid'], true),
        throwsArgumentError,
      );
      expect(state.load(), isEmpty);
      db.execute('BEGIN IMMEDIATE');
      expect(() => state.setExpanded([first], true), throwsStateError);
      db.execute('ROLLBACK');
      expect(state.load(), isEmpty);
    },
  );
}
