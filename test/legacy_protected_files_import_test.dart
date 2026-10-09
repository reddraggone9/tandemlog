import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/legacy_protected_files_import.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/profile_lock.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';
import 'package:tandemlog/storage/writer_guard.dart';

import 'profile_safety_store_test.dart'
    show space, writer, otherSpace, intentBytes;

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  final cacheKey = 'c' * 64;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-legacy-import-');
    await File('${root.path}/settings.json').writeAsString(
      jsonEncode({
        'folder': '/synthetic/workspace',
        'user': writer,
        'appearance': 'dark',
        'writer': writer,
      }),
    );
    await File('${root.path}/writer-migration.json').writeAsString('{"v":1}');
    final cache = await Directory(
      '${root.path}/spaces/$cacheKey/text-intents',
    ).create(recursive: true);
    await File('${cache.path}/$writer-1.json').writeAsBytes(intentBytes());
    await FileWriterGuard(root.path).prepare(
      space,
      writer,
      0,
      eventGenesisHash(space, writer),
      [
        PreparedWriterRecord(
          1,
          LogEvent.decode(utf8.decode(intentBytes())).hash!,
        ),
      ],
    );
    profile = await LocalProfileDatabase.open(root.path);
  });
  tearDown(() async {
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'imports exact identity, reservations and pending bytes; deletes nothing',
    () async {
      await File('${root.path}/unrelated.txt').writeAsString('leave');
      await File(
        '${root.path}/spaces/$cacheKey/cache.sqlite',
      ).writeAsString('not read by this slice');
      final result = await LegacyProtectedFilesImport(profile).run();
      expect(result.importedFiles, 4);
      expect(result.unmigratedCaches, ['spaces/$cacheKey/cache.sqlite']);
      expect(
        profile.database
            .select('SELECT writer FROM protected_settings')
            .single['writer'],
        writer,
      );
      expect(
        (await SqliteWriterGuard(
          profile,
        ).load(space, writer))!.pending.single.sequence,
        1,
      );
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
      expect(File('${root.path}/settings.json').existsSync(), isTrue);
      expect(
        File(
          '${root.path}/spaces/$cacheKey/text-intents/$writer-1.json',
        ).existsSync(),
        isTrue,
      );
      expect(await File('${root.path}/unrelated.txt').readAsString(), 'leave');
      await profile.close();
      profile = await LocalProfileDatabase.open(root.path);
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
    },
  );

  test(
    'import interruption before commit rolls back every protected file',
    () async {
      await expectLater(
        LegacyProtectedFilesImport(profile).run(
          beforeCommit: () {
            throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      for (final table in [
        'protected_settings',
        'protected_writer_guards',
        'protected_text_intents',
        'migration_file_imports',
      ]) {
        expect(profile.database.select('SELECT * FROM $table'), isEmpty);
      }
      await LegacyProtectedFilesImport(profile).run();
      expect(
        ProfileTextIntents(profile).pending(space, writer).single,
        intentBytes(),
      );
    },
  );

  test('repeat import preserves subsequent acknowledged guard state', () async {
    await LegacyProtectedFilesImport(profile).run();
    final event = LogEvent.decode(utf8.decode(intentBytes()));
    await SqliteWriterGuard(profile).acknowledge(space, writer, 1, event.hash!);
    final repeat = await LegacyProtectedFilesImport(profile).run();
    expect(repeat.importedFiles, 0);
    expect((await SqliteWriterGuard(profile).load(space, writer))!.sequence, 1);
  });

  test(
    'changed legacy authority after import is retained and rejected',
    () async {
      await LegacyProtectedFilesImport(profile).run();
      await File(
        '${root.path}/settings.json',
      ).writeAsString(jsonEncode({'writer': otherSpace}));
      await expectLater(
        LegacyProtectedFilesImport(profile).run(),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(
        profile.database
            .select('SELECT writer FROM protected_settings')
            .single['writer'],
        writer,
      );
      expect(
        await File('${root.path}/settings.json').readAsString(),
        jsonEncode({'writer': otherSpace}),
      );
    },
  );

  test('legacy profile lease prevents concurrent migration', () async {
    final legacy = await ProfileLock.acquire(root.path);
    try {
      await expectLater(
        LegacyProtectedFilesImport(profile).run(),
        throwsA(isA<ProfileInUse>()),
      );
      expect(
        profile.database.select('SELECT * FROM protected_settings'),
        isEmpty,
      );
    } finally {
      await legacy.close();
    }
  });

  test('guard conflicts fail without overwriting either authority', () async {
    await SqliteWriterGuard(profile).prepare(
      space,
      writer,
      0,
      eventGenesisHash(space, writer),
      [PreparedWriterRecord(1, 'b' * 64)],
    );
    await expectLater(
      LegacyProtectedFilesImport(profile).run(),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    expect(
      profile.database.select('SELECT * FROM protected_settings'),
      isEmpty,
    );
    expect(
      (await SqliteWriterGuard(
        profile,
      ).load(space, writer))!.pending.single.hash,
      'b' * 64,
    );
  });

  for (final repeated in [false, true]) {
    test(
      'bad indexed intent binding cannot verify ${repeated ? 'repeat' : 'first'} import',
      () async {
        if (repeated) {
          await LegacyProtectedFilesImport(profile).run();
        } else {
          ProfileTextIntents(profile).stage(space, writer, intentBytes());
        }
        profile.database.execute('UPDATE protected_text_intents SET entity=?', [
          otherSpace,
        ]);
        await expectLater(
          LegacyProtectedFilesImport(profile).run(),
          throwsA(isA<FormatFailure>()),
        );
        expect(File('${root.path}/settings.json').existsSync(), isTrue);
      },
    );
  }

  for (final corruptHash in [false, true]) {
    test(
      'repeat import rejects ${corruptHash ? 'changed' : 'lost'} previously imported reservations',
      () async {
        await LegacyProtectedFilesImport(profile).run();
        final old = File('${root.path}/writer-guards/$space.$writer.json');
        final data =
            jsonDecode(await old.readAsString()) as Map<String, dynamic>;
        if (corruptHash) {
          (data['pending'] as List).single['hash'] = 'b' * 64;
        } else {
          data['pending'] = [];
        }
        profile.database.execute('UPDATE protected_writer_guards SET raw=?', [
          utf8.encode(jsonEncode(data)),
        ]);
        await expectLater(
          LegacyProtectedFilesImport(profile).run(),
          throwsA(isA<LocalDatabaseFailure>()),
        );
        expect((await old.readAsString()), contains('pending'));
      },
    );
  }

  test('missing previously imported guard source is rejected', () async {
    await LegacyProtectedFilesImport(profile).run();
    await File('${root.path}/writer-guards/$space.$writer.json').delete();
    await expectLater(
      LegacyProtectedFilesImport(profile).run(),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    expect(
      (await SqliteWriterGuard(
        profile,
      ).load(space, writer))!.pending.single.sequence,
      1,
    );
  });

  test(
    'settings index must agree with preserved raw installation UUID',
    () async {
      await LegacyProtectedFilesImport(profile).run();
      profile.database.execute('UPDATE protected_settings SET writer=?', [
        otherSpace,
      ]);
      await expectLater(
        LegacyProtectedFilesImport(profile).run(),
        throwsA(isA<LocalDatabaseFailure>()),
      );
    },
  );

  test('source replacement after commit cannot mark import verified', () async {
    await expectLater(
      LegacyProtectedFilesImport(profile).run(
        beforeCommit: () {
          File(
            '${root.path}/writer-migration.json',
          ).writeAsStringSync('{"v":2}');
        },
      ),
      throwsA(isA<LocalDatabaseFailure>()),
    );
    expect(
      profile.database
          .select(
            "SELECT value FROM profile_metadata WHERE key='migration.protected-files'",
          )
          .single['value'],
      'pending-verification',
    );
    expect(File('${root.path}/settings.json').existsSync(), isTrue);
  });

  if (!Platform.isWindows) {
    test(
      'recognized symlink source is rejected without following it',
      () async {
        final settings = File('${root.path}/settings.json');
        await settings.rename('${root.path}/other.json');
        await Link(settings.path).create('${root.path}/other.json');
        await expectLater(
          LegacyProtectedFilesImport(profile).run(),
          throwsA(isA<LocalDatabaseFailure>()),
        );
        expect(
          profile.database.select('SELECT * FROM protected_settings'),
          isEmpty,
        );
      },
    );
  }
}
