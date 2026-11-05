import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

/// Android stops backgrounded apps without a clean close. Sealing the warm
/// proofs when the app is backgrounded keeps the next cold start warm; a
/// write after the seal must still reopen correctly, strictly.
void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('warm-reseal-');
    addTearDown(() => root.delete(recursive: true));
  });

  /// The profile as a stopped process leaves it: copied while still open.
  Future<String> killedCopy(String profile, String name) async {
    final target = Directory('${root.path}/$name');
    await target.create();
    await for (final entry in Directory(profile).list()) {
      if (entry is File) {
        await entry.copy('${target.path}/${entry.uri.pathSegments.last}');
      }
    }
    return target.path;
  }

  Future<TaskStore> reopen(LocalLogFolder folder, String profile) =>
      TaskStore.open(
        folder,
        profile,
        textEngine: NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        ),
      );

  test('a sealed, then stopped, process reopens warm', () async {
    final data = await Directory('${root.path}/data').create();
    final folder = LocalLogFolder(data.path);
    final person = const Uuid().v4();
    final store = await openNativeFixtureStore(
      folder,
      '${root.path}/profile',
      nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    await store.command(person, 'user.created', {'name': 'Synthetic Lee'});
    for (var i = 0; i < 5; i++) {
      await store.createNativeFixtureTask(const Uuid().v4(), {
        'title': 'Synthetic chore $i',
        'description': '',
        'assignee': person,
      });
    }
    final rows = jsonEncode(store.rows);

    // Without a seal, a stopped process rebuilds everything strictly.
    final unsealed = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'unsealed'),
    );
    expect(unsealed.warmProjectionReuses, 0);
    expect(unsealed.unified!.decodedCacheReuses, 0);
    await unsealed.close(sealCache: false);

    await store.sealWarmCaches();
    final sealed = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'sealed'),
    );
    expect(jsonEncode(sealed.rows), rows);
    expect(sealed.warmProjectionReuses, 1);
    expect(sealed.unified!.decodedCacheReuses, greaterThan(0));
    await sealed.close(sealCache: false);

    // A write after the seal makes it stale: correct rows, strict rebuild.
    await store.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Synthetic after the seal',
      'description': '',
      'assignee': person,
    });
    final after = jsonEncode(store.rows);
    final stale = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'stale'),
    );
    expect(jsonEncode(stale.rows), after);
    expect(stale.warmProjectionReuses, 0);
    await stale.close(sealCache: false);
    await store.close();
  });

  // Lee's history passed 4 MB in November 2026; the decode cache's old
  // size estimate (4x the history against 16 MiB) then skipped it silently.
  test('a history over 4 MB still reopens warm after a seal', () async {
    final data = await Directory('${root.path}/data').create();
    final folder = LocalLogFolder(data.path);
    final person = const Uuid().v4();
    final store = await openNativeFixtureStore(
      folder,
      '${root.path}/profile',
      nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    await store.command(person, 'user.created', {'name': 'Synthetic Lee'});
    var bytes = 0;
    for (var i = 0; bytes <= 4300 * 1024; i++) {
      await store.createNativeFixtureTask(const Uuid().v4(), {
        'title': 'Synthetic chore $i',
        'description': List.generate(
          300,
          (j) => 'step ${i * 300 + j} of a checklist',
        ).join('\n'),
        'assignee': person,
      });
      if (i % 25 == 24) {
        bytes = 0;
        await for (final file in data.list()) {
          if (file is File) bytes += await file.length();
        }
      }
    }
    final records = store.unified!.snapshot.records.length;
    final rows = jsonEncode(store.rows);

    await store.sealWarmCaches();
    final sealed = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'sealed'),
    );
    expect(jsonEncode(sealed.rows), rows);
    expect(sealed.warmProjectionReuses, 1);
    expect(sealed.unified!.decodedCacheReuses, records);
    expect(sealed.unified!.decodedRecords, 0);
    await sealed.close(sealCache: false);

    await store.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Synthetic after the seal',
      'description': '',
      'assignee': person,
    });
    final after = jsonEncode(store.rows);
    final stale = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'stale'),
    );
    expect(jsonEncode(stale.rows), after);
    expect(stale.warmProjectionReuses, 0);
    expect(stale.unified!.decodedCacheReuses, 0);
    expect(stale.unified!.decodedRecords, greaterThan(records));
    await stale.close(sealCache: false);
    await store.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
