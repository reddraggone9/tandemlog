import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

// Owner jobs: top-level so they can run on the profile's background owner.
void _create(Database db, List<Database> _, void _) =>
    db.execute('CREATE TABLE IF NOT EXISTS probe (n INTEGER PRIMARY KEY)');

int _insertThenSleep(Database db, List<Database> _, (int, int) a) {
  final insert = db.prepare('INSERT INTO probe VALUES (?)');
  try {
    for (var n = 0; n < a.$1; n++) {
      insert.execute([n]);
    }
  } finally {
    insert.close();
  }
  sleep(Duration(milliseconds: a.$2));
  return a.$1;
}

void _insertRange(Database db, List<Database> _, (int, int) range) {
  for (var n = range.$1; n < range.$2; n++) {
    db.execute('INSERT INTO probe VALUES (?)', [n]);
  }
}

void _insertThenFail(Database db, List<Database> _, int rows) {
  _insertThenSleep(db, const [], (rows, 0));
  throw StateError('job failed after writing');
}

int _count(Database db, List<Database> _, void _) =>
    db.select('SELECT COUNT(*) AS n FROM probe').single['n'] as int;

int _readLent(Database db, List<Database> lent, void _) =>
    lent.single.select('SELECT COUNT(*) AS n FROM scratch').single['n'] as int;

/// Lee 11-13 (60 fps): long shared-profile commits run their SQL on a
/// background isolate. These pin the safety contract: one transaction,
/// all-or-nothing, nothing touches the connection while it is lent, and
/// memory publishes only after COMMIT.
void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-owner-');
    addTearDown(() => root.delete(recursive: true));
  });

  Future<LocalProfileDatabase> openProfile(String name) async {
    final profile = await LocalProfileDatabase.open('${root.path}/$name');
    addTearDown(profile.close);
    await profile.serialize(
      () => profile.transactionAsync(
        (tx) => tx.run(_create, null, offload: false),
      ),
    );
    return profile;
  }

  int count(LocalProfileDatabase profile) =>
      profile.database.select('SELECT COUNT(*) AS n FROM probe').single['n']
          as int;

  test('the bundled SQLite can lend a connection to another isolate', () {
    expect(sqlite3.usedCompileOption('THREADSAFE=0'), isFalse);
    expect(LocalProfileDatabase.offloadAvailable, isTrue);
  });

  test('a lent connection is fenced until its job ends', () async {
    final profile = await openProfile('fence');
    late Future<int> written;
    final checked = Completer<void>();
    final done = profile.serialize(
      () => profile.transactionAsync((tx) async {
        written = tx.run(_insertThenSleep, (100, 300));
        // The job now owns the handle; every UI-isolate route is refused.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(profile.isLent, isTrue);
        expect(
          () => profile.database,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              LocalProfileDatabase.lentMessage,
            ),
          ),
        );
        expect(() => profile.transaction(() => 0), throwsStateError);
        expect(
          () => profile.transactionAsync((_) async => 0),
          throwsStateError,
        );
        // A second job cannot borrow the handle concurrently.
        await expectLater(tx.run(_count, null), throwsStateError);
        checked.complete();
        return written;
      }),
    );
    expect(await done, 100);
    await checked.future;
    expect(profile.isLent, isFalse);
    expect(count(profile), 100);
  });

  test('a failing job rolls back everything it and the UI wrote', () async {
    final profile = await openProfile('fail');
    await expectLater(
      profile.serialize(
        () => profile.transactionAsync((tx) async {
          profile.database.execute('INSERT INTO probe VALUES (-1)');
          await tx.run(_insertThenFail, 50);
        }),
      ),
      throwsA(isA<StateError>()),
    );
    expect(count(profile), 0);
    expect(profile.database.autocommit, isTrue);
    // Not poisoned: the next transaction commits normally.
    await profile.serialize(
      () => profile.transactionAsync((tx) => tx.run(_insertThenSleep, (3, 0))),
    );
    expect(count(profile), 3);
  });

  test('a body failing before its job ends rolls back after the job', () async {
    final profile = await openProfile('unawaited');
    await expectLater(
      profile.serialize(
        () => profile.transactionAsync((tx) async {
          // Started, never awaited: the rollback must wait for the owner,
          // or the job's remaining inserts would run outside a transaction.
          tx.run(_insertThenSleep, (3000, 200)).ignore();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw const FormatException('body failed early');
        }),
      ),
      throwsFormatException,
    );
    expect(profile.isLent, isFalse);
    expect(count(profile), 0);
    expect(profile.database.autocommit, isTrue);
  });

  test('a UI failure after an offloaded job rolls the job back too', () async {
    final profile = await openProfile('ui-fail');
    await expectLater(
      profile.serialize(
        () => profile.transactionAsync((tx) async {
          await tx.run(_insertThenSleep, (500, 0));
          // The job's rows are visible inside the transaction...
          expect(count(profile), 500);
          throw const FormatException('stage failed');
        }),
      ),
      throwsFormatException,
    );
    // ...and gone with it.
    expect(count(profile), 0);
  });

  test(
    'a COMMIT failing on the owner rolls back and keeps the profile',
    () async {
      final profile = await openProfile('commit-fail');
      profile.database.execute('PRAGMA foreign_keys=ON');
      profile.transaction(() {
        profile.database.execute(
          'CREATE TABLE parent (id INTEGER PRIMARY KEY)',
        );
        profile.database.execute(
          'CREATE TABLE child (p INTEGER REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED)',
        );
      });
      await expectLater(
        profile.serialize(
          () => profile.transactionAsync((tx) async {
            await tx.run(_insertThenSleep, (10, 0));
            // Checked only at COMMIT, which runs on the background owner.
            profile.database.execute('INSERT INTO child VALUES (7)');
          }),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(count(profile), 0);
      expect(
        profile.database.select('SELECT COUNT(*) AS n FROM child').single['n'],
        0,
      );
      expect(profile.database.autocommit, isTrue);
    },
  );

  test('a process stopped mid-transaction leaves no partial rows', () async {
    final profile = await openProfile('crash');
    final copy = await Directory('${root.path}/copy').create();
    await profile.serialize(
      () => profile.transactionAsync((tx) async {
        final job = tx.run(_insertThenSleep, (2000, 400));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        // The rows are written (some pages may already be in the WAL) but
        // not committed: a copy now is what a killed process leaves.
        for (final entry in Directory(profile.root).listSync()) {
          if (entry is File) {
            entry.copySync('${copy.path}/${entry.uri.pathSegments.last}');
          }
        }
        await job;
      }),
    );
    expect(count(profile), 2000);
    final reopened = sqlite3.open('${copy.path}/local.sqlite');
    addTearDown(reopened.close);
    expect(reopened.select('SELECT COUNT(*) AS n FROM probe').single['n'], 0);
  });

  test('a lent scratch database is readable by the job only', () async {
    final profile = await openProfile('lend');
    final scratch = sqlite3.openInMemory();
    addTearDown(scratch.close);
    scratch.execute('CREATE TABLE scratch (n INTEGER)');
    scratch.execute('INSERT INTO scratch VALUES (1),(2),(3)');
    final read = await profile.serialize(
      () => profile.transactionAsync((tx) async {
        final job = tx.run(_readLent, null, lend: [scratch]);
        expect(LocalProfileDatabase.isLentDatabase(scratch), isTrue);
        return job;
      }),
    );
    expect(read, 3);
    expect(LocalProfileDatabase.isLentDatabase(scratch), isFalse);
  });

  group('workspace open', () {
    late LocalLogFolder folder;
    final person = const Uuid().v4();
    setUp(() async {
      folder = LocalLogFolder(
        (await Directory('${root.path}/data').create()).path,
      );
    });
    tearDown(() {
      LocalProfileDatabase.offloadAvailable = true;
      TaskStore.prestageAttach = true;
    });

    NativeTextEngine engine() {
      final e = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      addTearDown(e.dispose);
      return e;
    }

    Future<void> seed(int tasks) async {
      final store = await openNativeFixtureStore(
        folder,
        '${root.path}/seed',
        nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      await store.command(person, 'user.created', {'name': 'Synthetic Lee'});
      for (var i = 0; i < tasks; i++) {
        await store.createNativeFixtureTask(const Uuid().v4(), {
          'title': 'Synthetic chore $i',
          'description': '',
          'assignee': person,
        });
      }
      await store.close();
    }

    /// Every table except the profile's own lease row, in a fixed order.
    String dump(String profile) {
      final db = sqlite3.open('$profile/local.sqlite');
      try {
        final out = <String, Object?>{};
        final tables = db
            .select(
              "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name",
            )
            .map((r) => r['name'] as String);
        for (final table in tables) {
          out[table] = db
              .select('SELECT * FROM "$table" ORDER BY 1,2')
              .map(
                (r) => r.values
                    .map((v) => v is List<int> ? base64.encode(v) : v)
                    .toList(),
              )
              .toList();
        }
        // The installation's writer differs per profile; so do its own
        // header row and settings. Compare everything that is shared.
        out.remove('protected_settings');
        return jsonEncode(out);
      } finally {
        db.close();
      }
    }

    /// Both profiles see the same folder bytes: restore the seeded folder.
    Future<void> restoreFolder(String from) async {
      final data = Directory(folder.location);
      for (final entry in data.listSync()) {
        entry.deleteSync();
      }
      for (final entry in Directory(from).listSync()) {
        (entry as File).copySync('${data.path}/${entry.uri.pathSegments.last}');
      }
    }

    Future<(String rows, int reuses, int prestaged)> openAndClose(
      String name,
    ) async {
      final store = await TaskStore.open(
        folder,
        '${root.path}/$name',
        textEngine: engine(),
        writerIdentity: '00000000-0000-4000-8000-000000000001',
        now: () => DateTime.utc(2026, 11, 13, 12),
      );
      final rows = jsonEncode(store.rows);
      // The view the stage published equals a fresh read of the same rows.
      expect(jsonEncode(store.currentView.rows), rows);
      final reuses =
          store.semanticProjectionReuses + store.warmProjectionReuses;
      final prestaged = store.prestagedProjectionUses;
      await store.close();
      return (rows, reuses, prestaged);
    }

    test('an attached projection publishes only after its COMMIT', () async {
      await seed(3);
      final store = await TaskStore.open(
        folder,
        '${root.path}/attach',
        textEngine: engine(),
      );
      addTearDown(store.close);
      final history = store.unified!, profile = history.profile;
      profile.database.execute('CREATE TABLE probe (n INTEGER PRIMARY KEY)');
      final events = <String>[];
      final before = history.snapshot;
      void Function() stage(UnifiedSnapshot snapshot) {
        events.add('stage');
        expect(identical(snapshot, before), isTrue);
        expect(profile.database.autocommit, isFalse); // Still inside.
        expect(count(profile), 400); // Sees the owner's uncommitted rows.
        return () {
          events.add('publish');
          expect(profile.database.autocommit, isTrue); // Committed.
          expect(count(profile), 400);
        };
      }

      Future<void> prestage(
        UnifiedSnapshot snapshot,
        ProfileTransaction tx,
      ) async {
        final job = tx.run(_insertThenSleep, (400, 100));
        events.add('prestage');
        expect(identical(history.snapshot, before), isTrue);
        expect(() => profile.database, throwsStateError);
        await job;
      }

      final owner = Object();
      await profile.serialize(
        () =>
            history.attachProjectionInProfileQueueAsync(owner, stage, prestage),
      );
      expect(events, ['prestage', 'stage', 'publish']);
      history.detachProjectionInProfileQueue(owner);

      // A failing stage: nothing published, nothing attached, rows gone.
      events.clear();
      final failing = Object();
      await expectLater(
        profile.serialize(
          () => history.attachProjectionInProfileQueueAsync(
            failing,
            (_) => throw const FormatException('stage failed'),
            (_, tx) async {
              await tx.run(_insertRange, (1000, 2000));
              events.add('prestage');
            },
          ),
        ),
        throwsFormatException,
      );
      expect(events, ['prestage']);
      expect(count(profile), 400);
      // Not attached: attaching the same owner again is allowed.
      await profile.serialize(
        () => history.attachProjectionInProfileQueueAsync(
          failing,
          (_) => () {},
          (_, _) async {},
        ),
      );
      history.detachProjectionInProfileQueue(failing);
    });

    test(
      'strict and warm opens write identical SQL whether offloaded or inline',
      () async {
        await seed(90); // Over the store's offload threshold.
        final seeded = await Directory('${root.path}/seeded').create();
        for (final entry in Directory(folder.location).listSync()) {
          (entry as File).copySync(
            '${seeded.path}/${entry.uri.pathSegments.last}',
          );
        }
        // The oracle: the synchronous path, the stage doing all the work.
        LocalProfileDatabase.offloadAvailable = false;
        TaskStore.prestageAttach = false;
        final inlineStrict = await openAndClose('inline');
        final inlineWarm = await openAndClose('inline');
        LocalProfileDatabase.offloadAvailable = true;
        TaskStore.prestageAttach = true;
        final inlineFolder = jsonEncode([
          for (final f in Directory(
            folder.location,
          ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
            base64.encode((f as File).readAsBytesSync()),
        ]);
        await restoreFolder(seeded.path);
        final offStrict = await openAndClose('offload');
        final offWarm = await openAndClose('offload');
        // Same header bytes, so the two profiles are directly comparable.
        expect(
          jsonEncode([
            for (final f in Directory(
              folder.location,
            ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
              base64.encode((f as File).readAsBytesSync()),
          ]),
          inlineFolder,
        );
        expect(offStrict.$1, inlineStrict.$1);
        expect(offWarm.$1, inlineWarm.$1);
        expect(offStrict.$2, inlineStrict.$2);
        expect(offWarm.$2, inlineWarm.$2);
        expect(offStrict.$2, greaterThan(0)); // The copy branch ran.
        expect(offWarm.$2, greaterThan(0)); // The warm branch ran.
        expect(inlineStrict.$3 + inlineWarm.$3, 0);
        expect(offStrict.$3, 2); // Copy and view came from the owner.
        expect(offWarm.$3, 1); // The view came from the owner.
        expect(dump('${root.path}/offload'), dump('${root.path}/inline'));
      },
    );
  });
}
