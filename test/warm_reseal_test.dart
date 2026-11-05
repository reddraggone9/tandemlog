import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

/// Android stops backgrounded apps without a clean close. The history store
/// is current after every commit; the Task projection witness is sealed when
/// the app is backgrounded. A write after that seal invalidates only the
/// witness: the history still reopens from the store, the Task rows strictly.
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

    // Without a seal, a stopped process rebuilds the Task rows strictly but
    // still reads its history from the store.
    final unsealed = await reopen(
      folder,
      await killedCopy('${root.path}/profile', 'unsealed'),
    );
    expect(jsonEncode(unsealed.rows), rows);
    expect(unsealed.warmProjectionReuses, 0);
    expect(unsealed.unified!.decodedCacheReuses, greaterThan(0));
    expect(unsealed.unified!.decodedRecords, 0);
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

    // A write after the seal makes the Task witness stale: correct rows,
    // strict Task rebuild, history still from the store.
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
    expect(stale.unified!.decodedRecords, 0);
    await stale.close(sealCache: false);
    await store.close();
  });

  // Lee's history passed 4 MB in November 2026, and the old decoded-history
  // blob's size estimate then skipped it silently. The store has no cap
  // beyond the log limits: twice the phone's history still reopens warm.
  test('a history twice the phone copy still reopens warm', () async {
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
    for (var i = 0; bytes <= 2 * 4300 * 1024; i++) {
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
    expect(stale.unified!.decodedCacheReuses, records + 1);
    expect(stale.unified!.decodedRecords, 0);
    await stale.close(sealCache: false);
    await store.close();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
