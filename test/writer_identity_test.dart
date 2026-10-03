import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

void main() {
  late Directory root;
  const first = '11111111-1111-4111-8111-111111111111';
  const selected = '22222222-2222-4222-8222-222222222222';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-writer-settings');
  });
  tearDown(() => root.delete(recursive: true));
  Future<File> legacy(String directory, String writer) async {
    await Directory('${root.path}/spaces/$directory').create(recursive: true);
    return File('${root.path}/spaces/$directory/writer-id')
      ..writeAsStringSync(writer, flush: true);
  }

  test(
    'migration prefers selected cache and preserves every legacy identity',
    () async {
      final other = await legacy('000', first);
      const folder = '/chosen/folder';
      final key = sha256.convert(utf8.encode(folder)).toString();
      final chosen = await legacy(key, selected);
      await File('${root.path}/settings.json').writeAsString(
        jsonEncode({'folder': folder, 'user': 'lee', 'appearance': 'dark'}),
      );
      final settings = LocalSettings(root.path);
      await settings.load();
      expect(settings.writer, selected);
      expect(settings.folder, folder);
      expect(settings.user, 'lee');
      expect(settings.appearance, Appearance.dark);
      expect(await other.readAsString(), first);
      expect(await chosen.readAsString(), selected);
      final saved = jsonDecode(
        await File('${root.path}/settings.json').readAsString(),
      );
      expect(saved['writer'], selected);
      expect(
        await File('${root.path}/writer-migration.json').readAsString(),
        '{"v":1}',
      );
      expect(await File('${root.path}/settings.json.tmp').exists(), isFalse);
    },
  );

  test(
    'no selected cache chooses lexical first independent of listing order',
    () async {
      await legacy('zzz', selected);
      await legacy('aaa', first);
      final settings = LocalSettings(root.path);
      await settings.load();
      expect(settings.writer, first);
    },
  );

  test(
    'settings reset creates fresh writer without resurrecting legacy',
    () async {
      await legacy('aaa', first);
      final settings = LocalSettings(root.path);
      await settings.load();
      expect(settings.writer, first);
      await File('${root.path}/settings.json').delete();
      await settings.load();
      expect(isCanonicalId(settings.writer), isTrue);
      expect(settings.writer, isNot(first));
      final replacement = settings.writer;
      final reloaded = LocalSettings(root.path);
      await reloaded.load();
      expect(reloaded.writer, replacement);
      expect(
        await File('${root.path}/spaces/aaa/writer-id').readAsString(),
        first,
      );
    },
  );

  test('saved migration identity finishes marker after interruption', () async {
    await legacy('aaa', first);
    await File(
      '${root.path}/settings.json',
    ).writeAsString(jsonEncode({'writer': selected}));
    final settings = LocalSettings(root.path);
    await settings.load();
    expect(settings.writer, selected);
    expect(await File('${root.path}/writer-migration.json').exists(), isTrue);
  });

  test(
    'marker write failure retains durable settings identity on retry',
    () async {
      await legacy('aaa', first);
      final obstruction = await Directory(
        '${root.path}/writer-migration.json.tmp',
      ).create();
      await expectLater(
        LocalSettings(root.path).load(),
        throwsA(isA<FileSystemException>()),
      );
      final saved = jsonDecode(
        await File('${root.path}/settings.json').readAsString(),
      );
      expect(saved['writer'], first);
      await obstruction.delete();
      final settings = LocalSettings(root.path);
      await settings.load();
      expect(settings.writer, first);
      expect(await File('${root.path}/writer-migration.json').exists(), isTrue);
    },
  );

  test(
    'store startup failures release the defensive workspace lease',
    () async {
      final folder = LocalLogFolder('${root.path}/space');
      await Directory(folder.location).create();
      final cache = '${root.path}/cache';
      await expectLater(
        TaskStore.open(folder, cache, writerIdentity: 'invalid'),
        throwsA(isA<FormatFailure>()),
      );
      final store = await TaskStore.open(folder, cache, writerIdentity: first);
      await store.close();
    },
  );

  test(
    'cache 9 replays Inbox classification without changing canonical bytes',
    () async {
      final folder = LocalLogFolder('${root.path}/space');
      await Directory(folder.location).create();
      final cache = '${root.path}/cache';
      final store = await TaskStore.open(folder, cache, writerIdentity: first);
      final user = const Uuid().v4(), task = const Uuid().v4();
      await store.command(user, 'user.created', {'name': 'Lee'});
      await store.command(task, 'task.created', {
        'title': 'Prepared',
        'description': 'Imported detail',
        'assignee': user,
      });
      final bytes = await folder.read('$first.jsonl');
      final stale = Map<String, dynamic>.from(
        store.rows.firstWhere((row) => row['id'] == task),
      )..['inbox'] = true;
      store.db.execute('UPDATE views SET raw=? WHERE id=?', [
        jsonEncode(stale),
        task,
      ]);
      store.db.execute('PRAGMA user_version=9');
      await store.close();
      final replayed = await TaskStore.open(
        folder,
        cache,
        writerIdentity: first,
      );
      try {
        expect(
          replayed.db.select('PRAGMA user_version').single['user_version'],
          11,
        );
        expect(
          replayed.rows.firstWhere((row) => row['id'] == task)['inbox'],
          isFalse,
        );
        expect(await folder.read('$first.jsonl'), bytes);
        expect(
          await Directory(
            cache,
          ).list().where((entry) => entry.path.contains('cache-v9-')).length,
          1,
        );
      } finally {
        await replayed.close();
      }
    },
  );

  test(
    'invalid legacy identity fails without overwriting settings or identity',
    () async {
      final identity = await legacy('aaa', 'invalid');
      final file = File('${root.path}/settings.json');
      const original = '{"folder":"chosen"}';
      await file.writeAsString(original);
      await expectLater(
        LocalSettings(root.path).load(),
        throwsA(isA<FormatFailure>()),
      );
      expect(await file.readAsString(), original);
      expect(await identity.readAsString(), 'invalid');
      expect(
        await File('${root.path}/writer-migration.json').exists(),
        isFalse,
      );
    },
  );

  test(
    'invalid settings writer and migration marker fail explicitly',
    () async {
      final file = File('${root.path}/settings.json');
      await file.writeAsString('{"writer":"invalid"}');
      await expectLater(
        LocalSettings(root.path).load(),
        throwsA(isA<FormatFailure>()),
      );
      expect(await file.readAsString(), '{"writer":"invalid"}');
      await file.writeAsString(jsonEncode({'writer': selected}));
      await File('${root.path}/writer-migration.json').writeAsString('invalid');
      await expectLater(
        LocalSettings(root.path).load(),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'failed atomic settings replacement does not finalize migration',
    () async {
      await legacy('aaa', first);
      final obstruction = await Directory(
        '${root.path}/settings.json.tmp',
      ).create();
      final settings = LocalSettings(root.path);
      await expectLater(settings.load(), throwsA(isA<FileSystemException>()));
      expect(await File('${root.path}/settings.json').exists(), isFalse);
      expect(
        await File('${root.path}/writer-migration.json').exists(),
        isFalse,
      );
      await obstruction.delete();
      await settings.load();
      expect(settings.writer, first);
    },
  );

  test(
    'two spaces share installation writer and resume each stream safely',
    () async {
      final settings = LocalSettings(root.path);
      await settings.load();
      final writer = settings.writer;
      final folderA = LocalLogFolder('${root.path}/a');
      final folderB = LocalLogFolder('${root.path}/b');
      await Directory(folderA.location).create();
      await Directory(folderB.location).create();
      for (final entry in [
        (folderA, 'a', 1),
        (folderB, 'b', 1),
        (folderA, 'a', 2),
      ]) {
        final store = await TaskStore.open(
          entry.$1,
          '${root.path}/cache-${entry.$2}',
          writerIdentity: writer,
        );
        try {
          final event = await store.command(const Uuid().v4(), 'user.created', {
            'name': entry.$2,
          });
          expect(event.writer, writer);
          expect(event.sequence, entry.$3);
          expect(
            await File('${root.path}/cache-${entry.$2}/writer-id').exists(),
            isFalse,
          );
        } finally {
          await store.close();
        }
      }
      expect((await folderA.read('$writer.jsonl')).isNotEmpty, isTrue);
      expect((await folderB.read('$writer.jsonl')).isNotEmpty, isTrue);
    },
  );

  test(
    'explicit identity preserves old stream and uses a fresh stream',
    () async {
      final folder = LocalLogFolder('${root.path}/space');
      await Directory(folder.location).create();
      final cache = '${root.path}/cache';
      final old = await TaskStore.open(folder, cache, writerIdentity: first);
      await old.command(const Uuid().v4(), 'user.created', {'name': 'Old'});
      final bytes = await folder.read('$first.jsonl');
      await old.close();
      final fresh = await TaskStore.open(
        folder,
        cache,
        writerIdentity: selected,
      );
      try {
        expect(fresh.rows, hasLength(1));
        final event = await fresh.command(const Uuid().v4(), 'user.created', {
          'name': 'New',
        });
        expect(event.sequence, 1);
        expect(await folder.read('$first.jsonl'), bytes);
        expect(fresh.rows, hasLength(2));
      } finally {
        await fresh.close();
      }
    },
  );
}
