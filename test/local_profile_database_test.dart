import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/profile_lock.dart';

void main() {
  late Directory root;
  LocalProfileDatabase? profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-db-proof-');
  });
  tearDown(() async {
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });

  test(
    'one DB after clean close, with exclusive durable WAL configured',
    () async {
      profile = await LocalProfileDatabase.open(root.path);
      final db = profile!.database;
      expect(
        db.select('PRAGMA locking_mode').single.values.single,
        'exclusive',
      );
      expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
      expect(db.select('PRAGMA synchronous').single.values.single, 2);
      expect(File('${root.path}/local.sqlite-shm').existsSync(), isFalse);
      await profile!.close();
      await profile!.close();
      expect(root.listSync().map((f) => f.uri.pathSegments.last).toList(), [
        'local.sqlite',
      ]);
    },
  );

  test(
    'same process and symlink aliases fail before opening another handle',
    () async {
      profile = await LocalProfileDatabase.open(root.path);
      await expectLater(
        LocalProfileDatabase.open(root.path),
        throwsA(isA<ProfileInUse>()),
      );
      if (!Platform.isWindows) {
        final alias = Link('${root.path}-alias');
        await alias.create(root.path);
        try {
          await expectLater(
            LocalProfileDatabase.open(alias.path),
            throwsA(isA<ProfileInUse>()),
          );
        } finally {
          await alias.delete();
        }
      }
      profile!.database.execute('CREATE TABLE evidence (value TEXT)');
      profile!.database.execute("INSERT INTO evidence VALUES ('first')");
      await profile!.close();
      profile = await LocalProfileDatabase.open(root.path);
      expect(
        profile!.database.select('SELECT value FROM evidence').single['value'],
        'first',
      );
    },
  );

  test(
    'failed open retains unsupported database and releases process guard',
    () async {
      final db = sqlite3.open('${root.path}/local.sqlite');
      db.execute('PRAGMA user_version=999');
      db.execute('CREATE TABLE evidence (value TEXT)');
      db.execute("INSERT INTO evidence VALUES ('keep')");
      db.close();
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          LocalProfileDatabase.open(root.path),
          throwsA(isA<LocalDatabaseFailure>()),
        );
      }
      final retained = sqlite3.open('${root.path}/local.sqlite');
      expect(retained.select('PRAGMA user_version').single.values.single, 999);
      expect(
        retained.select('SELECT value FROM evidence').single['value'],
        'keep',
      );
      retained.close();
    },
  );

  for (final mode in ['commit', 'rollback', 'uncommitted']) {
    test('OS exclusion survives $mode and process death', () async {
      final child = await _startChild(root.path, mode);
      final errors = child.stderr.transform(utf8.decoder).join();
      try {
        expect(
          await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 45)),
          'ready',
        );
        await expectLater(
          LocalProfileDatabase.open(
            root.path,
          ).timeout(const Duration(seconds: 3)),
          throwsA(isA<ProfileInUse>()),
        );
      } finally {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode.timeout(const Duration(seconds: 15));
      }
      expect(await errors, isEmpty);
      profile = await LocalProfileDatabase.open(root.path);
      final rows = profile!.database.select(
        'SELECT value FROM evidence ORDER BY rowid',
      );
      expect(
        rows.map((r) => r['value']).toList(),
        mode == 'commit' ? ['durable', 'committed'] : ['durable'],
      );
      expect(
        profile!.database.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      await profile!.close();
      expect(root.listSync().map((f) => f.uri.pathSegments.last).toList(), [
        'local.sqlite',
      ]);
    });
  }

  test(
    'independent profiles can own DBs concurrently; this is not a workspace lease',
    () async {
      profile = await LocalProfileDatabase.open('${root.path}/first');
      final second = await LocalProfileDatabase.open('${root.path}/second');
      await second.close();
    },
  );

  for (final table in ['protected_writer_guards', 'protected_text_intents']) {
    test(
      'missing $table fails closed instead of recreating safety authority',
      () async {
        profile = await LocalProfileDatabase.open(root.path);
        await profile!.close();
        final damaged = sqlite3.open('${root.path}/local.sqlite');
        damaged.execute('DROP TABLE $table');
        damaged.close();
        await expectLater(
          LocalProfileDatabase.open(root.path),
          throwsA(isA<LocalDatabaseFailure>()),
        );
        final retained = sqlite3.open('${root.path}/local.sqlite');
        expect(
          retained.select('SELECT name FROM sqlite_schema WHERE name=?', [
            table,
          ]),
          isEmpty,
        );
        retained.close();
      },
    );
  }
  test(
    'weakened protected schema fails closed despite matching columns',
    () async {
      profile = await LocalProfileDatabase.open(root.path);
      await profile!.close();
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
    },
  );
}

Future<Process> _startChild(String root, String mode) {
  final executable = Platform.resolvedExecutable;
  final cache = executable.indexOf(
    '${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}',
  );
  final dart = cache < 0
      ? executable
      : '${executable.substring(0, cache)}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  return Process.start(dart, [
    'run',
    '--verbosity=error',
    'test/support/local_profile_database_child.dart',
    root,
    mode,
  ]);
}
