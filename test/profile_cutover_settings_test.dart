import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/profile_lock.dart';

const writer = '22222222-2222-4222-8222-222222222222';
const user = '33333333-3333-4333-8333-333333333333';
const settingsSql =
    'CREATE TABLE protected_settings (singleton INTEGER PRIMARY KEY CHECK(singleton=1), writer TEXT NOT NULL, raw BLOB NOT NULL)';
void main() {
  late Directory root;
  LocalProfileDatabase? profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('synthetic-profile-reset-');
  });
  tearDown(() async {
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });
  void oldProfile({
    Map<String, dynamic>? values,
    int version = 5,
    bool missing = false,
  }) {
    final db = sqlite3.open('${root.path}/local.sqlite');
    try {
      db.execute(settingsSql);
      db.execute('CREATE TABLE old_cache (raw BLOB)');
      db.execute('CREATE TABLE protected_app_outbox (raw BLOB)');
      db.execute('INSERT INTO old_cache VALUES (?)', [
        utf8.encode('disposable cached view'),
      ]);
      db.execute('INSERT INTO protected_app_outbox VALUES (?)', [
        utf8.encode('abandoned pending save'),
      ]);
      if (!missing) {
        db.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
          writer,
          utf8.encode(
            jsonEncode(
              values ??
                  {
                    'writer': writer,
                    'folder': 'content://synthetic/tree/household',
                    'user': user,
                    'appearance': 'dark',
                    'lastSection': 'food',
                    'obsolete': 'discard',
                  },
            ),
          ),
        ]);
      }
      db.execute('PRAGMA application_id=1414284354');
      db.execute('PRAGMA user_version=$version');
    } finally {
      db.close();
    }
  }

  for (final version in [1, 2, 3, 4, 5]) {
    test(
      'old profile$version retains only preferences and resets disposable state',
      () async {
        oldProfile(version: version);
        final canonical = File('${root.path}/unrelated-canonical-log');
        await canonical.writeAsString('untouched real-copy sentinel');
        profile = await LocalProfileDatabase.open(root.path);
        final settings = LocalSettings(root.path, profileDatabase: profile);
        await settings.load();
        expect(settings.writer, writer);
        expect(settings.folder, 'content://synthetic/tree/household');
        expect(settings.user, user);
        expect(settings.appearance, Appearance.dark);
        expect(settings.lastSection, AppSection.food);
        expect(
          LocalSettings.protectedValues(profile!).containsKey('obsolete'),
          isFalse,
        );
        final tables = profile!.database
            .select(
              "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((r) => r['name'])
            .toSet();
        expect(tables, {
          'protected_settings',
          'profile_metadata',
          'protected_app_workspaces',
          'protected_app_heads',
        });
        expect(
          profile!.database.select('PRAGMA user_version').single.values.single,
          6,
        );
        expect(await canonical.readAsString(), 'untouched real-copy sentinel');
        await profile!.close();
        profile = await LocalProfileDatabase.open(root.path);
        expect(LocalSettings.protectedValues(profile!)['writer'], writer);
      },
    );
  }
  test(
    'invalid or missing old identity refuses without dropping source tables',
    () async {
      oldProfile(values: {'writer': user, 'folder': 'kept'});
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      final db = sqlite3.open('${root.path}/local.sqlite');
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 5);
        expect(db.select('SELECT * FROM old_cache'), hasLength(1));
        expect(db.select('SELECT * FROM protected_app_outbox'), hasLength(1));
      } finally {
        db.close();
      }
    },
  );
  test('missing old settings refuses without inventing a new writer', () async {
    oldProfile(missing: true);
    await expectLater(
      LocalProfileDatabase.open(root.path),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    final db = sqlite3.open('${root.path}/local.sqlite');
    try {
      expect(db.select('SELECT * FROM protected_settings'), isEmpty);
      expect(db.select('SELECT * FROM old_cache'), hasLength(1));
    } finally {
      db.close();
    }
  });
  test(
    'future profile is preserved and current damaged authority is never rebuilt',
    () async {
      oldProfile(version: 99);
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      final db = sqlite3.open('${root.path}/local.sqlite');
      db.execute('PRAGMA user_version=5');
      db.close();
      profile = await LocalProfileDatabase.open(root.path);
      profile!.database.execute('DROP TABLE protected_app_heads');
      await profile!.close();
      profile = null;
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<LocalDatabaseFailure>()),
      );
    },
  );
  test(
    'fresh initialization is idempotent and a second owner cannot reset settings',
    () async {
      profile = await LocalProfileDatabase.open(root.path);
      await LocalSettings.initialize(profile!);
      final first = LocalSettings.protectedValues(profile!);
      await LocalSettings.initialize(profile!);
      expect(LocalSettings.protectedValues(profile!), first);
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<ProfileInUse>()),
      );
      expect(LocalSettings.protectedValues(profile!), first);
    },
  );
}
