import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/local_profile_database.dart';

// Frozen released schema2 definitions; never regenerate from the new schema.
const releasedSchema2 = [
  'CREATE TABLE profile_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE protected_writer_guards (space TEXT NOT NULL, writer TEXT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(space,writer))',
  'CREATE TABLE protected_text_intents (space TEXT NOT NULL, writer TEXT NOT NULL, sequence INTEGER NOT NULL, id TEXT NOT NULL, entity TEXT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(space,writer,sequence), UNIQUE(space,id))',
  'CREATE TABLE protected_settings (singleton INTEGER PRIMARY KEY CHECK(singleton=1), writer TEXT NOT NULL, raw BLOB NOT NULL)',
  'CREATE TABLE migration_file_imports (path TEXT PRIMARY KEY, kind TEXT NOT NULL, hash TEXT NOT NULL)',
  'CREATE TABLE protected_cache_imports (path TEXT PRIMARY KEY, location TEXT NOT NULL, space TEXT NOT NULL, raw BLOB NOT NULL, hash TEXT NOT NULL)',
  "CREATE TABLE migration_cleanup (path TEXT PRIMARY KEY, kind TEXT NOT NULL, hash TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('ready','deleting','deleted')))",
];

void main() {
  late Directory root;
  LocalProfileDatabase? profile;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('food-schema-'),
  );
  tearDown(() async {
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });
  void writeReleasedProfile() {
    final db = sqlite3.open('${root.path}/local.sqlite');
    for (final sql in releasedSchema2) {
      db.execute(sql);
    }
    db.execute("INSERT INTO profile_metadata VALUES ('schema','2')");
    db.execute(
      "INSERT INTO profile_metadata VALUES ('migration.active','keep')",
    );
    db.execute('INSERT INTO protected_writer_guards VALUES (?,?,?)', [
      'space',
      'writer',
      utf8.encode('synthetic guard bytes'),
    ]);
    db.execute('INSERT INTO protected_text_intents VALUES (?,?,?,?,?,?)', [
      'space',
      'writer',
      7,
      'receipt',
      'entity',
      utf8.encode('exact pending text'),
    ]);
    db.execute('INSERT INTO protected_settings VALUES (?,?,?)', [
      1,
      'writer',
      utf8.encode('exact settings bytes'),
    ]);
    db.execute('INSERT INTO migration_file_imports VALUES (?,?,?)', [
      'source',
      'settings',
      'digest',
    ]);
    db.execute('INSERT INTO protected_cache_imports VALUES (?,?,?,?,?)', [
      'cache',
      'location',
      'space',
      utf8.encode('exact imported cache'),
      'digest',
    ]);
    db.execute('INSERT INTO migration_cleanup VALUES (?,?,?,?)', [
      'source',
      'settings',
      'digest',
      'deleting',
    ]);
    db.execute('PRAGMA application_id=1414284354');
    db.execute('PRAGMA user_version=2');
    db.close();
  }

  test(
    'released schema2 upgrades additively and retains all protected bytes',
    () async {
      writeReleasedProfile();
      profile = await LocalProfileDatabase.open(root.path);
      final db = profile!.database;
      expect(db.select('PRAGMA user_version').single.values.single, 3);
      expect(
        db.select('SELECT raw FROM protected_writer_guards').single['raw'],
        utf8.encode('synthetic guard bytes'),
      );
      expect(
        db.select('SELECT raw FROM protected_text_intents').single['raw'],
        utf8.encode('exact pending text'),
      );
      expect(
        db.select('SELECT raw FROM protected_settings').single['raw'],
        utf8.encode('exact settings bytes'),
      );
      expect(
        db.select('SELECT raw FROM protected_cache_imports').single['raw'],
        utf8.encode('exact imported cache'),
      );
      expect(
        db.select('SELECT state FROM migration_cleanup').single['state'],
        'deleting',
      );
      expect(
        db
            .select(
              "SELECT value FROM profile_metadata WHERE key='migration.active'",
            )
            .single['value'],
        'keep',
      );
      for (final table in [
        'protected_food_intents',
        'protected_food_heads',
        'protected_food_locations',
      ]) {
        expect(db.select('SELECT * FROM $table'), isEmpty);
      }
    },
  );
  test('weakened released authority prevents any schema3 creation', () async {
    writeReleasedProfile();
    final damaged = sqlite3.open('${root.path}/local.sqlite');
    damaged.execute('DROP TABLE protected_writer_guards');
    damaged.execute(
      'CREATE TABLE protected_writer_guards (space TEXT, writer TEXT, raw BLOB)',
    );
    damaged.close();
    await expectLater(
      LocalProfileDatabase.open(root.path),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    final retained = sqlite3.open('${root.path}/local.sqlite');
    expect(retained.select('PRAGMA user_version').single.values.single, 2);
    expect(
      retained.select(
        "SELECT name FROM sqlite_schema WHERE name LIKE 'protected_food_%'",
      ),
      isEmpty,
    );
    retained.close();
  });
  test(
    'halfway additive upgrade failure rolls back all new authority',
    () async {
      writeReleasedProfile();
      final db = sqlite3.open('${root.path}/local.sqlite');
      db.execute('CREATE TABLE protected_food_heads (collision TEXT)');
      db.close();
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<Exception>()),
      );
      final retained = sqlite3.open('${root.path}/local.sqlite');
      expect(retained.select('PRAGMA user_version').single.values.single, 2);
      expect(
        retained.select(
          "SELECT name FROM sqlite_schema WHERE name='protected_food_intents'",
        ),
        isEmpty,
      );
      expect(
        retained
            .select("SELECT value FROM profile_metadata WHERE key='schema'")
            .single['value'],
        '2',
      );
      expect(
        retained.select('SELECT raw FROM protected_text_intents').single['raw'],
        utf8.encode('exact pending text'),
      );
      retained.close();
    },
  );
}
