import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/storage/legacy_cache_import.dart';
import 'package:tandemlog/storage/legacy_protected_files_import.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_text_intents.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

const writer = '00000000-0000-4000-8000-000000000001';
const user = '00000000-0000-4000-8000-000000000002';
const task = '00000000-0000-4000-8000-000000000003';

void main() {
  late Directory root, shared;
  late String key, cache;
  LocalProfileDatabase? profile;
  TaskStore? opened;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy-cache-import-');
    shared = await Directory('${root.path}/canonical').create();
    key = sha256.convert(utf8.encode(shared.path)).toString();
    cache = '${root.path}/profile/spaces/$key';
    await Directory('${root.path}/profile').create();
    await File('${root.path}/profile/settings.json').writeAsString(
      jsonEncode({
        'writer': writer,
        'folder': shared.path,
        'appearance': 'dark',
      }),
    );
  });
  tearDown(() async {
    await opened?.close();
    opened = null;
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });
  Future<void> seed() async {
    final store = await TaskStore.open(
      LocalLogFolder(shared.path),
      cache,
      writerIdentity: writer,
      writerGuard: FileWriterGuard('${root.path}/profile'),
    );
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(task, 'task.created', {
      'title': 'Preserved',
      'description': '',
      'assignee': user,
    });
    await store.close();
  }

  Future<void> importFiles() async {
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    await LegacyProtectedFilesImport(profile!).run();
  }

  test(
    'captures primary and historical observations, keeps originals and replays unchanged logs',
    () async {
      await seed();
      await File(
        '$cache/cache.sqlite',
      ).copy('$cache/cache-v13-00000000-0000-4000-8000-000000000004.sqlite');
      await importFiles();
      expect(await LegacyCacheImport(profile!).run(), 2);
      expect(
        profile!.database.select('SELECT * FROM protected_cache_imports'),
        hasLength(2),
      );
      expect(File('$cache/cache.sqlite').existsSync(), isTrue);
      expect(await LegacyCacheImport(profile!).run(), 0);
      final before = await File('${shared.path}/$writer.jsonl').readAsBytes();
      opened = await TaskStore.open(
        LocalLogFolder(shared.path),
        profile!.root,
        profileDatabase: profile,
        writerIdentity: writer,
      );
      expect(
        opened!.rows.firstWhere((r) => r['id'] == task)['title'],
        'Preserved',
      );
      expect(await File('${shared.path}/$writer.jsonl').readAsBytes(), before);
    },
  );
  test(
    'cache import transaction interruption leaves no partial observations',
    () async {
      await seed();
      await importFiles();
      await expectLater(
        LegacyCacheImport(
          profile!,
        ).run(beforeCommit: () => throw StateError('cut')),
        throwsStateError,
      );
      expect(
        profile!.database.select('SELECT * FROM protected_cache_imports'),
        isEmpty,
      );
      expect(await LegacyCacheImport(profile!).run(), 1);
    },
  );

  test('warm namespace still validates protected snapshot bytes', () async {
    await seed();
    await importFiles();
    await LegacyCacheImport(profile!).run();
    opened = await TaskStore.open(
      LocalLogFolder(shared.path),
      profile!.root,
      profileDatabase: profile,
      writerIdentity: writer,
    );
    await opened!.close();
    opened = null;
    profile!.database.execute(
      "UPDATE protected_cache_imports SET raw=CAST('{}' AS BLOB)",
    );
    await expectLater(
      TaskStore.open(
        LocalLogFolder(shared.path),
        profile!.root,
        profileDatabase: profile,
        writerIdentity: writer,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'interrupted legacy replay retains independent heads/ranges and backup',
    () async {
      await seed();
      await File(
        '$cache/cache.sqlite',
      ).copy('$cache/cache-v13-00000000-0000-4000-8000-000000000004.sqlite');
      final db = sqlite3.open('$cache/cache.sqlite');
      db.execute('DROP TABLE events');
      db.execute('DROP TABLE views');
      db.execute('DROP TABLE positions');
      db.execute(
        "INSERT OR REPLACE INTO metadata VALUES ('replay_pending','1')",
      );
      db.execute('PRAGMA user_version=10');
      db.close();
      await importFiles();
      expect(await LegacyCacheImport(profile!).run(), 2);
      opened = await TaskStore.open(
        LocalLogFolder(shared.path),
        profile!.root,
        profileDatabase: profile,
        writerIdentity: writer,
      );
      expect(
        opened!.rows.firstWhere((r) => r['id'] == task)['title'],
        'Preserved',
      );
    },
  );
  test(
    'changed source or conflicting location binding rejects without replacement',
    () async {
      await seed();
      await importFiles();
      await LegacyCacheImport(profile!).run();
      final db = sqlite3.open('$cache/cache.sqlite');
      db.execute(
        "UPDATE metadata SET value='00000000-0000-4000-8000-000000000099' WHERE key='space'",
      );
      db.close();
      await expectLater(
        LegacyCacheImport(profile!).run(),
        throwsA(isA<Exception>()),
      );
      expect(File('$cache/cache.sqlite').existsSync(), isTrue);
      expect(
        profile!.database.select('SELECT * FROM protected_cache_imports'),
        hasLength(1),
      );
    },
  );
  test(
    'cache-only exact native receipt imports and retries without private file',
    () async {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      try {
        final folder = _FailFolder(LocalLogFolder(shared.path));
        var store = await TaskStore.open(
          folder,
          cache,
          writerIdentity: writer,
          writerGuard: FileWriterGuard('${root.path}/profile'),
          textEngine: engine,
        );
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        OperationReceipt? receipt;
        folder.fail = true;
        await expectLater(
          store.command(task, 'task.createdWithText', {
            'title': 'Outbox only',
            'description': '',
            'assignee': user,
            'text': {
              'codec': 'yrs-v1',
              'adapter': 1,
              'seeds': {
                'title': sha256
                    .convert(engine.seedText('Outbox only').bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('').bytes)
                    .toString(),
              },
            },
          }, onPrepared: (r) => receipt = r),
          throwsA(isA<FolderAccessFailure>()),
        );
        await store.close();
        await File('$cache/text-intents/$writer-2.json').delete();
        await importFiles();
        await LegacyCacheImport(profile!).run();
        expect(
          utf8.decode(
            ProfileTextIntents(profile!).pending(store.space, writer).single,
          ),
          receipt!.raw,
        );
        store = await TaskStore.open(
          folder,
          profile!.root,
          profileDatabase: profile,
          writerIdentity: writer,
          textEngine: engine,
        );
        opened = store;
        expect(store.pendingTextOperations.single.raw, receipt!.raw);
        expect(
          (await store.retryTextOperation(receipt!)).canonicalRaw,
          receipt!.raw,
        );
        expect(store.pendingTextOperations, isEmpty);
        await store.close();
        expect(await LegacyCacheImport(profile!).run(), 0);
      } finally {
        engine.dispose();
      }
    },
  );
}

class _FailFolder implements LogFolder, RangeLogFolder {
  _FailFolder(this.inner);
  final LocalLogFolder inner;
  bool fail = false;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      inner.readFrom(name, offset);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (fail) {
      fail = false;
      throw FolderAccessFailure('Synthetic unknown append');
    }
    await inner.append(name, bytes);
  }
}
