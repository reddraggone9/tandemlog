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

const releasedFoodSchema3 = [
  'CREATE TABLE protected_food_intents (space TEXT NOT NULL, writer TEXT NOT NULL, sequence INTEGER NOT NULL, id TEXT NOT NULL, raw BLOB NOT NULL, PRIMARY KEY(space,writer,sequence), UNIQUE(space,id))',
  'CREATE TABLE protected_food_heads (space TEXT NOT NULL, writer TEXT NOT NULL, sequence INTEGER NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(space,writer))',
  'CREATE TABLE protected_food_locations (location TEXT PRIMARY KEY, space TEXT NOT NULL)',
  'CREATE TABLE protected_food_import_witnesses (space TEXT PRIMARY KEY NOT NULL, version INTEGER NOT NULL CHECK(version=1))',
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

  for (final version in [2, 3]) {
    test(
      'released schema$version keeps valid settings and intentionally resets old Food/private state',
      () async {
        writeReleasedProfile();
        final old = sqlite3.open('${root.path}/local.sqlite');
        final settings = utf8.encode(
          jsonEncode({
            'writer': '22222222-2222-4222-8222-222222222222',
            'folder': 'synthetic://workspace',
            'appearance': 'dark',
            'lastSection': 'food',
          }),
        );
        old.execute('UPDATE protected_settings SET writer=?,raw=?', [
          '22222222-2222-4222-8222-222222222222',
          settings,
        ]);
        if (version == 3) {
          for (final sql in releasedFoodSchema3) {
            old.execute(sql);
          }
          old.execute('INSERT INTO protected_food_intents VALUES(?,?,?,?,?)', [
            'old-space',
            'old-writer',
            17,
            'old-writer:17',
            utf8.encode('abandoned Food intent'),
          ]);
          old.execute('PRAGMA user_version=3');
        }
        old.close();
        profile = await LocalProfileDatabase.open(root.path);
        expect(
          profile!.database.select('PRAGMA user_version').single.values.single,
          6,
        );
        expect(
          profile!.database
              .select('SELECT raw FROM protected_settings')
              .single['raw'],
          settings,
        );
        expect(
          profile!.database.select(
            "SELECT name FROM sqlite_schema WHERE name LIKE 'protected_food_%'",
          ),
          isEmpty,
        );
        expect(
          profile!.database.select(
            "SELECT name FROM sqlite_schema WHERE name LIKE 'migration_%'",
          ),
          isEmpty,
        );
        expect(
          profile!.database.select('SELECT * FROM protected_app_heads'),
          isEmpty,
        );
        expect(
          profile!.database.select('SELECT * FROM protected_app_workspaces'),
          isEmpty,
        );
      },
    );
  }
  test(
    'opaque or invalid old settings refuse without discarding old private evidence',
    () async {
      writeReleasedProfile();
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      final old = sqlite3.open('${root.path}/local.sqlite');
      try {
        expect(old.select('PRAGMA user_version').single.values.single, 2);
        expect(
          old.select('SELECT raw FROM protected_text_intents').single['raw'],
          utf8.encode('exact pending text'),
        );
        expect(
          old.select('SELECT raw FROM protected_settings').single['raw'],
          utf8.encode('exact settings bytes'),
        );
      } finally {
        old.close();
      }
    },
  );
  test(
    'weakened old settings authority refuses before resetting any table',
    () async {
      writeReleasedProfile();
      final old = sqlite3.open('${root.path}/local.sqlite');
      old.execute('DROP TABLE protected_settings');
      old.execute(
        'CREATE TABLE protected_settings(singleton INTEGER,writer TEXT,raw BLOB)',
      );
      old.close();
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      final retained = sqlite3.open('${root.path}/local.sqlite');
      try {
        expect(retained.select('PRAGMA user_version').single.values.single, 2);
        expect(
          retained
              .select('SELECT raw FROM protected_text_intents')
              .single['raw'],
          utf8.encode('exact pending text'),
        );
      } finally {
        retained.close();
      }
    },
  );
}
