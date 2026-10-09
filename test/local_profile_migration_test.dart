import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';
import 'package:tandemlog/domain/event.dart';
import 'profile_safety_store_test.dart' as safety;

const writer = '00000000-0000-4000-8000-000000000001';
const user = '00000000-0000-4000-8000-000000000002';
const task = '00000000-0000-4000-8000-000000000003';

void main() {
  late Directory root;
  LocalProfileDatabase? profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('full-profile-migration-');
  });
  tearDown(() async {
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });
  Future<String> legacy() async {
    final shared = await Directory('${root.path}/canonical').create();
    final private = await Directory('${root.path}/profile').create();
    await File('${private.path}/settings.json').writeAsString(
      jsonEncode({
        'writer': writer,
        'folder': shared.path,
        'user': user,
        'appearance': 'dark',
      }),
    );
    await File(
      '${private.path}/writer-migration.json',
    ).writeAsString('{"v":1}');
    final key = sha256.convert(utf8.encode(shared.path)).toString();
    final store = await TaskStore.open(
      LocalLogFolder(shared.path),
      '${private.path}/spaces/$key',
      writerIdentity: writer,
      writerGuard: FileWriterGuard(private.path),
    );
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(task, 'task.created', {
      'title': 'Retained',
      'description': '',
      'assignee': user,
    });
    await store.close();
    await File('${private.path}/unknown.txt').writeAsString('keep');
    await File('${private.path}/spaces/$key/unknown.bin').writeAsString('keep');
    profile = await LocalProfileDatabase.open(private.path);
    return shared.path;
  }

  test(
    'fresh profile creates one DB and stable settings identity without lock files',
    () async {
      profile = await LocalProfileDatabase.open('${root.path}/fresh');
      await LocalProfileMigration(profile!).run();
      final settings = LocalSettings(profile!.root, profileDatabase: profile);
      await settings.load();
      final id = settings.writer;
      await profile!.close();
      profile = await LocalProfileDatabase.open('${root.path}/fresh');
      await LocalProfileMigration(profile!).run();
      final reopened = LocalSettings(profile!.root, profileDatabase: profile);
      await reopened.load();
      expect(reopened.writer, id);
      await profile!.close();
      expect(
        await Directory(
          '${root.path}/fresh',
        ).list().map((f) => f.uri.pathSegments.last).toList(),
        ['local.sqlite'],
      );
    },
  );
  test(
    'verified full import cleans known originals, preserves unknown/canonical data and identity',
    () async {
      final shared = await legacy();
      final before = await File('$shared/$writer.jsonl').readAsBytes();
      await LocalProfileMigration(profile!).run();
      expect(File('${profile!.root}/settings.json').existsSync(), isFalse);
      expect(File('${profile!.root}/profile.lock').existsSync(), isFalse);
      expect(await File('${profile!.root}/unknown.txt').readAsString(), 'keep');
      expect(await File('$shared/$writer.jsonl').readAsBytes(), before);
      final settings = LocalSettings(profile!.root, profileDatabase: profile);
      await settings.load();
      expect(settings.writer, writer);
      expect(settings.folder, shared);
      expect(settings.appearance, Appearance.dark);
      final store = await TaskStore.open(
        LocalLogFolder(shared),
        profile!.root,
        profileDatabase: profile,
        writerIdentity: writer,
      );
      expect(
        store.rows.firstWhere((r) => r['id'] == task)['title'],
        'Retained',
      );
      await store.close();
      expect(
        profile!.database.select(
          "SELECT state FROM migration_cleanup WHERE state!='deleted'",
        ),
        isEmpty,
      );
    },
  );
  for (final cut in [
    'import.started',
    'files.imported',
    'caches.imported',
    'cleanup.planned',
    'sources.verified',
    'activation.before',
    'activation.committed',
    'cleanup.marked',
    'cleanup.deleted',
    'cleanup.committed',
    'cleanup.finished',
  ]) {
    test('restart resumes without identity change at $cut', () async {
      final shared = await legacy();
      final before = await File('$shared/$writer.jsonl').readAsBytes();
      var hit = false;
      await expectLater(
        LocalProfileMigration(profile!).run(
          checkpoint: (boundary, path) {
            if (boundary == cut && !hit) {
              hit = true;
              throw StateError('cut $cut');
            }
          },
        ),
        throwsStateError,
      );
      expect(hit, isTrue);
      await profile!.close();
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      await LocalProfileMigration(profile!).run();
      final settings = LocalSettings(profile!.root, profileDatabase: profile);
      await settings.load();
      expect(settings.writer, writer);
      expect(await File('$shared/$writer.jsonl').readAsBytes(), before);
      expect(await File('${profile!.root}/unknown.txt').readAsString(), 'keep');
      expect(
        profile!.database.select(
          "SELECT state FROM migration_cleanup WHERE state!='deleted'",
        ),
        isEmpty,
      );
    });
  }
  test(
    'activated private intent cannot disappear without atomic retirement proof',
    () async {
      final private = await Directory('${root.path}/proof-profile').create();
      await File(
        '${private.path}/settings.json',
      ).writeAsString(jsonEncode({'writer': safety.writer}));
      final directory = await Directory(
        '${private.path}/spaces/${'e' * 64}/text-intents',
      ).create(recursive: true);
      final bytes = safety.intentBytes(),
          event = LogEvent.decode(utf8.decode(bytes));
      await File(
        '${directory.path}/${safety.writer}-1.json',
      ).writeAsBytes(bytes);
      profile = await LocalProfileDatabase.open(private.path);
      await LocalProfileMigration(profile!).run();
      expect(directory.listSync(), isEmpty);
      profile!.database.execute(
        "CREATE TRIGGER reject_proof BEFORE INSERT ON profile_metadata WHEN NEW.key LIKE 'migration.retired.%' BEGIN SELECT RAISE(ABORT,'synthetic proof failure'); END",
      );
      expect(
        () => profile!.transaction(
          () => ProfileTextIntents(
            profile!,
          ).retireInTransaction(event.space, event.writer, bytes),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        ProfileTextIntents(profile!).pending(event.space, event.writer).single,
        bytes,
      );
      profile!.database.execute('DROP TRIGGER reject_proof');
      profile!.database.execute('DELETE FROM protected_text_intents');
      await expectLater(
        LocalProfileMigration(profile!).run(),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      // Restore only exact synthetic pending bytes. Successful retirement proof
      // uses the adapter transaction path; canonical admission itself is covered
      // by the native cache-only receipt/retry test.
      ProfileTextIntents(profile!).stage(event.space, event.writer, bytes);
      profile!.transaction(
        () => ProfileTextIntents(
          profile!,
        ).retireInTransaction(event.space, event.writer, bytes),
      );
      await LocalProfileMigration(profile!).run();
    },
  );
  test('actual crash-retained legacy WAL and SHM import and cleanup', () async {
    final shared = await Directory('${root.path}/canonical').create(),
        private = await Directory('${root.path}/profile').create();
    await File('${private.path}/settings.json').writeAsString(
      jsonEncode({'writer': writer, 'folder': shared.path, 'user': user}),
    );
    final executable = Platform.resolvedExecutable,
        index = Platform.resolvedExecutable.indexOf(
          '${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}',
        );
    final dart = index < 0
        ? executable
        : '${executable.substring(0, index)}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
    final child = await Process.start(dart, [
      'run',
      '--verbosity=error',
      'test/support/local_profile_migration_child.dart',
      root.path,
      'legacy-wal',
    ]);
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
    } finally {
      expect(child.kill(ProcessSignal.sigkill), isTrue);
      expect(await child.exitCode, isNot(0));
    }
    expect(await errors, isEmpty);
    final key = sha256.convert(utf8.encode(shared.path)).toString(),
        cache = '${private.path}/spaces/$key/cache.sqlite';
    for (final suffix in ['-wal', '-shm']) {
      expect(await File('$cache$suffix').length(), greaterThan(0));
    }
    final before = await File('${shared.path}/$writer.jsonl').readAsBytes();
    profile = await LocalProfileDatabase.open(private.path);
    await LocalProfileMigration(profile!).run();
    final store = await TaskStore.open(
      LocalLogFolder(shared.path),
      private.path,
      profileDatabase: profile,
      writerIdentity: writer,
    );
    expect(
      store.rows.firstWhere((row) => row['id'] == task)['title'],
      'Committed hot WAL',
    );
    await store.close();
    expect(await File('${shared.path}/$writer.jsonl').readAsBytes(), before);
    expect(Directory('${private.path}/spaces/$key').listSync(), isEmpty);
  });
  test('cleanup boundary rechecks target before deleting the source', () async {
    await legacy();
    await expectLater(
      LocalProfileMigration(profile!).run(
        checkpoint: (boundary, path) {
          if (boundary == 'cleanup.marked') {
            profile!.database.execute('DELETE FROM protected_settings');
          }
        },
      ),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    expect(File('${profile!.root}/settings.json').existsSync(), isTrue);
    expect(
      profile!.database
          .select(
            "SELECT value FROM profile_metadata WHERE key='migration.profile'",
          )
          .single['value'],
      'active',
    );
  });
  test(
    'valid guard regression after activation retains original authority',
    () async {
      await legacy();
      await expectLater(
        LocalProfileMigration(profile!).run(
          checkpoint: (boundary, path) {
            if (boundary == 'activation.committed') {
              final row = profile!.database
                  .select('SELECT space,writer FROM protected_writer_guards')
                  .first;
              profile!.database.execute(
                'UPDATE protected_writer_guards SET raw=? WHERE space=? AND writer=?',
                [
                  utf8.encode(
                    jsonEncode({
                      'v': 1,
                      'space': row['space'],
                      'writer': row['writer'],
                      'sequence': 0,
                      'hash': eventGenesisHash(
                        row['space'] as String,
                        row['writer'] as String,
                      ),
                      'pending': [],
                    }),
                  ),
                  row['space'],
                  row['writer'],
                ],
              );
            }
          },
        ),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(
        Directory('${profile!.root}/writer-guards').listSync(),
        isNotEmpty,
      );
    },
  );
  test(
    'changed cleanup source fails closed and resumes only after exact restoration',
    () async {
      await legacy();
      final original = await File(
        '${profile!.root}/settings.json',
      ).readAsBytes();
      await expectLater(
        LocalProfileMigration(profile!).run(
          checkpoint: (boundary, path) async {
            if (boundary == 'activation.committed') {
              await File(
                '${profile!.root}/settings.json',
              ).writeAsString('changed');
            }
          },
        ),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(
        await File('${profile!.root}/settings.json').readAsString(),
        'changed',
      );
      await File('${profile!.root}/settings.json').writeAsBytes(original);
      await LocalProfileMigration(profile!).run();
      expect(File('${profile!.root}/settings.json').existsSync(), isFalse);
    },
  );
  for (final table in [
    'protected_settings',
    'protected_writer_guards',
    'protected_cache_imports',
  ]) {
    test('missing $table at final activation gate retains originals', () async {
      await legacy();
      await expectLater(
        LocalProfileMigration(profile!).run(
          checkpoint: (boundary, path) {
            if (boundary == 'activation.before') {
              profile!.database.execute('DELETE FROM $table');
            }
          },
        ),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(File('${profile!.root}/settings.json').existsSync(), isTrue);
      expect(
        profile!.database
            .select(
              "SELECT value FROM profile_metadata WHERE key='migration.profile'",
            )
            .single['value'],
        'importing',
      );
    });
  }
  test(
    'sole exact private intent lost at final activation gate retains its file',
    () async {
      final private = await Directory('${root.path}/intent-profile').create();
      await File(
        '${private.path}/settings.json',
      ).writeAsString(jsonEncode({'writer': safety.writer}));
      final intent = await Directory(
        '${private.path}/spaces/${'f' * 64}/text-intents',
      ).create(recursive: true);
      final original = File('${intent.path}/${safety.writer}-1.json');
      await original.writeAsBytes(safety.intentBytes());
      profile = await LocalProfileDatabase.open(private.path);
      await expectLater(
        LocalProfileMigration(profile!).run(
          checkpoint: (boundary, path) {
            if (boundary == 'activation.before') {
              profile!.database.execute('DELETE FROM protected_text_intents');
            }
          },
        ),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(await original.readAsBytes(), safety.intentBytes());
    },
  );
  test(
    'orphan temporary authority and linked cleanup sources remain untouched',
    () async {
      await legacy();
      final temp = File('${profile!.root}/writer-migration.json.tmp');
      await temp.writeAsString('unconfirmed');
      await expectLater(
        LocalProfileMigration(profile!).run(),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(await temp.readAsString(), 'unconfirmed');
      await temp.delete();
      if (!Platform.isWindows) {
        final settings = File('${profile!.root}/settings.json');
        final saved = await settings.readAsBytes();
        await settings.delete();
        await Link(settings.path).create('${root.path}/outside');
        await expectLater(
          LocalProfileMigration(profile!).run(),
          throwsA(isA<LocalDatabaseFailure>()),
        );
        expect(
          await FileSystemEntity.type(settings.path, followLinks: false),
          FileSystemEntityType.link,
        );
        await Link(settings.path).delete();
        await settings.writeAsBytes(saved);
      }
      await LocalProfileMigration(profile!).run();
    },
  );
  for (final cut in [
    'files.imported',
    'cleanup.planned',
    'activation.committed',
    'cleanup.marked',
    'cleanup.deleted',
    'cleanup.committed',
  ]) {
    test('SIGKILL recovery retains identity and canonical bytes at $cut', () async {
      final shared = await legacy(), private = profile!.root;
      final canonical = await File('$shared/$writer.jsonl').readAsBytes();
      await profile!.close();
      profile = null;
      final executable = Platform.resolvedExecutable;
      final cache = executable.indexOf(
        '${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}',
      );
      final dart = cache < 0
          ? executable
          : '${executable.substring(0, cache)}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      final child = await Process.start(dart, [
        'run',
        '--verbosity=error',
        'test/support/local_profile_migration_child.dart',
        private,
        cut,
      ]);
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
      } finally {
        expect(child.kill(ProcessSignal.sigkill), isTrue);
        expect(
          await child.exitCode.timeout(const Duration(seconds: 15)),
          isNot(0),
        );
      }
      expect(await errors, isEmpty);
      profile = await LocalProfileDatabase.open(private);
      await LocalProfileMigration(profile!).run();
      final settings = LocalSettings(private, profileDatabase: profile);
      await settings.load();
      expect(settings.writer, writer);
      expect(await File('$shared/$writer.jsonl').readAsBytes(), canonical);
      expect(
        profile!.database.select(
          "SELECT state FROM migration_cleanup WHERE state!='deleted'",
        ),
        isEmpty,
      );
      await profile!.close();
      expect(
        Directory(private)
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toSet(),
        {'local.sqlite', 'unknown.txt'},
      );
    });
  }
}
