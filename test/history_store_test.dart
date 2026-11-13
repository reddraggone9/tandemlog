import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;
import 'package:tandemlog/storage/history_store.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

/// Lee 11-05 (design/history-store.md): the profile database holds the whole
/// decoded history; a warm start checks each writer's seal (size and the
/// exact last record) and reads only what follows it.
void main() {
  late Directory root;
  late LocalLogFolder folder;
  final person = const Uuid().v4();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('history-store-');
    addTearDown(() => root.delete(recursive: true));
    folder = LocalLogFolder(
      (await Directory('${root.path}/data').create()).path,
    );
  });

  NativeTextEngine engine() {
    final e = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    addTearDown(e.dispose);
    return e;
  }

  Future<TaskStore> open(String profile, {bool defer = false}) =>
      TaskStore.open(
        folder,
        profile,
        textEngine: engine(),
        deferPeerCatchUp: defer,
      );

  /// The profile as a stopped process leaves it: copied while still open.
  var copies = 0;
  Future<String> killedCopy(String profile) async {
    final target = await Directory('${root.path}/copy${copies++}').create();
    await for (final entry in Directory(profile).list()) {
      if (entry is File) {
        await entry.copy('${target.path}/${entry.uri.pathSegments.last}');
      }
    }
    return target.path;
  }

  Future<TaskStore> seeded(String profile, int tasks) async {
    final store = await openNativeFixtureStore(
      folder,
      profile,
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
    return store;
  }

  Future<void> addTask(TaskStore store, String title) =>
      store.createNativeFixtureTask(const Uuid().v4(), {
        'title': title,
        'description': '',
        'assignee': person,
      });

  String storeKey() => sha256.convert(utf8.encode(folder.location)).toString();

  /// Edits a stopped profile's database directly.
  void tamper(String profile, void Function(Database db) edit) {
    final db = sqlite3.open('$profile/local.sqlite');
    try {
      edit(db);
    } finally {
      db.close();
    }
  }

  /// A strict open of the same history on a fresh profile is the oracle.
  Future<String> strictRows(String name) async {
    final oracle = await open('${root.path}/oracle-$name');
    final rows = jsonEncode(oracle.rows);
    expect(oracle.unified!.decodedCacheReuses, 0);
    await oracle.close(sealCache: false);
    return rows;
  }

  test(
    'paged store read preserves seal checks across page boundaries',
    () async {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute(
        'CREATE TABLE profile_metadata (key TEXT PRIMARY KEY, value TEXT)',
      );
      final key = 'a' * 64;
      final history = HistoryStore(db, key)..reset('test');
      final table = 'history_${key}_records';
      for (var n = 1; n <= 256; n++) {
        db.execute('INSERT INTO $table VALUES (?,?,?,?,?,?,?)', [
          'writer',
          n,
          n * 10,
          9,
          'hash$n',
          'raw$n',
          'typed$n',
        ]);
      }
      final seal = HistorySeal(256, 2570, 'hash256', 2560);
      var pauses = 0;
      Future<void> pause() async {
        pauses++;
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        await history.readWriterBetweenFrames('writer', seal, pause),
        history.readWriter('writer', seal),
      );
      expect(pauses, 2);
      db.execute('INSERT INTO $table VALUES (?,?,?,?,?,?,?)', [
        'writer',
        257,
        2570,
        9,
        'extra',
        'raw',
        'typed',
      ]);
      expect(
        await history.readWriterBetweenFrames('writer', seal, pause),
        isNull,
      );
      db.execute('DELETE FROM $table WHERE seq=257');
      db.execute("UPDATE $table SET hash='changed' WHERE seq=256");
      expect(
        await history.readWriterBetweenFrames('writer', seal, pause),
        isNull,
      );
      db.execute("UPDATE $table SET hash='hash256' WHERE seq=256");
      db.execute('DELETE FROM $table WHERE seq=128');
      expect(
        await history.readWriterBetweenFrames('writer', seal, pause),
        isNull,
      );
    },
  );

  test('first open with no store loads strictly and writes the store', () async {
    final writer = await seeded('${root.path}/a', 3);
    final existing = writer.unified!.snapshot.records.length;
    await writer.close();
    // A new installation: strict decode of everything, then its own header.
    final first = await open('${root.path}/fresh');
    expect(first.unified!.decodedCacheReuses, 0);
    expect(first.unified!.decodedRecords, existing);
    final records = first.unified!.snapshot.records.length;
    expect(records, existing + 1);
    final copy = await killedCopy('${root.path}/fresh');
    await first.close(sealCache: false);
    tamper(copy, (db) {
      final key = storeKey();
      final seals = db.select(
        'SELECT writer,sequence,end_offset,hash FROM history_${key}_seals ORDER BY writer',
      );
      final heads = db.select(
        'SELECT writer,sequence,bytes,hash FROM protected_app_heads ORDER BY writer',
      );
      expect(seals.length, heads.length);
      for (var i = 0; i < seals.length; i++) {
        expect(seals[i]['writer'], heads[i]['writer']);
        expect(seals[i]['sequence'], heads[i]['sequence']);
        expect(seals[i]['end_offset'], heads[i]['bytes']);
        expect(seals[i]['hash'], heads[i]['hash']);
      }
      expect(
        db
            .select('SELECT COUNT(*) AS n FROM history_${key}_records')
            .single['n'],
        records,
      );
    });
  });

  test(
    'a killed process reopens on the fast path with identical lists',
    () async {
      final store = await seeded('${root.path}/a', 5);
      final records = store.unified!.snapshot.records.length;
      final rows = jsonEncode(store.rows);
      // No seal, no close: the store is current after every commit.
      final warm = await open(await killedCopy('${root.path}/a'));
      expect(jsonEncode(warm.rows), rows);
      expect(warm.unified!.decodedCacheReuses, records);
      expect(warm.unified!.decodedRecords, 0);
      expect(jsonEncode(warm.rows), await strictRows('kill'));
      await warm.close(sealCache: false);
      await store.close();
    },
  );

  test(
    'a write after the seal is appended after the own sealed head',
    () async {
      final store = await seeded('${root.path}/a', 2);
      await store.sealWarmCaches();
      await addTask(store, 'Synthetic after the seal');
      final records = store.unified!.snapshot.records.length;
      final warm = await open(await killedCopy('${root.path}/a'));
      expect(jsonEncode(warm.rows), jsonEncode(store.rows));
      expect(warm.unified!.decodedCacheReuses, records);
      expect(warm.unified!.decodedRecords, 0);
      // The Task projection witness was invalidated by the write.
      expect(warm.warmProjectionReuses, 0);
      // And writes keep appending after this reopen.
      await addTask(warm, 'Synthetic after the reopen');
      final again = await open(await killedCopy(warm.unified!.profile.root));
      expect(again.unified!.decodedRecords, 0);
      expect(again.unified!.decodedCacheReuses, records + 1);
      expect(jsonEncode(again.rows), jsonEncode(warm.rows));
      await again.close(sealCache: false);
      await warm.close(sealCache: false);
      await store.close();
    },
  );

  test(
    'a damaged store fails the fast check, opens strictly and is rebuilt',
    () async {
      final store = await seeded('${root.path}/a', 3);
      final records = store.unified!.snapshot.records.length;
      final copy = await killedCopy('${root.path}/a');
      await store.close();
      tamper(copy, (db) {
        // The stored last record no longer equals the bytes at its offset.
        db.execute(
          "UPDATE history_${storeKey()}_records SET raw = raw || ' ' WHERE seq = (SELECT MAX(seq) FROM history_${storeKey()}_records)",
        );
      });
      final strict = await open(copy);
      expect(strict.unified!.decodedCacheReuses, 0);
      expect(strict.unified!.decodedRecords, records);
      final rebuilt = await killedCopy(copy);
      await strict.close(sealCache: false);
      final warm = await open(rebuilt);
      expect(warm.unified!.decodedCacheReuses, records);
      expect(warm.unified!.decodedRecords, 0);
      await warm.close(sealCache: false);
    },
  );

  test('a store generation change rebuilds the store from the logs', () async {
    final store = await seeded('${root.path}/a', 3);
    final records = store.unified!.snapshot.records.length;
    final copy = await killedCopy('${root.path}/a');
    await store.close();
    tamper(copy, (db) {
      final key = 'app5.store.${storeKey()}';
      final binding =
          jsonDecode(
                db.select('SELECT value FROM profile_metadata WHERE key=?', [
                      key,
                    ]).single['value']
                    as String,
              )
              as List;
      expect(binding.first, HistoryStore.generation);
      binding[0] = HistoryStore.generation - 1;
      db.execute('UPDATE profile_metadata SET value=? WHERE key=?', [
        jsonEncode(binding),
        key,
      ]);
    });
    final strict = await open(copy);
    expect(strict.unified!.decodedRecords, records);
    expect(strict.unified!.decodedCacheReuses, 0);
    final rebuilt = await killedCopy(copy);
    await strict.close(sealCache: false);
    tamper(rebuilt, (db) {
      final binding =
          jsonDecode(
                db.select('SELECT value FROM profile_metadata WHERE key=?', [
                      'app5.store.${storeKey()}',
                    ]).single['value']
                    as String,
              )
              as List;
      expect(binding.first, HistoryStore.generation);
    });
    final warm = await open(rebuilt);
    expect(warm.unified!.decodedRecords, 0);
    expect(warm.unified!.decodedCacheReuses, records);
    await warm.close(sealCache: false);
  });

  test(
    'a replaced file whose last sealed record differs opens strictly',
    () async {
      final store = await seeded('${root.path}/a', 2);
      final writer = store.unified!.writer;
      final copy = await killedCopy('${root.path}/a');
      await store.close();
      final file = File('${folder.location}/$writer.applog');
      final bytes = await file.readAsBytes();
      // Same length, different last record: a replaced history.
      final last = bytes.lastIndexOf(10, bytes.length - 2) + 1;
      final replaced = List<int>.of(bytes);
      final i = replaced.indexWhere((b) => b >= 0x61 && b <= 0x66, last + 40);
      replaced[i] = replaced[i] == 0x61 ? 0x62 : 0x61;
      await file.writeAsBytes(replaced, flush: true);
      // The strict path runs and refuses the changed history.
      await expectLater(open(copy), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'a same-length change inside the sealed prefix is not re-read; Verify Logs finds it',
    () async {
      final store = await seeded('${root.path}/a', 3);
      final writer = store.unified!.writer;
      final copy = await killedCopy('${root.path}/a');
      await store.close();
      final file = File('${folder.location}/$writer.applog');
      final bytes = await file.readAsBytes();
      final firstLine = bytes.indexOf(10);
      final damaged = List<int>.of(bytes);
      final i = damaged.indexWhere((b) => b >= 0x61 && b <= 0x66, 20);
      expect(i, lessThan(firstLine));
      damaged[i] = damaged[i] == 0x61 ? 0x62 : 0x61;
      await file.writeAsBytes(damaged, flush: true);
      // Lee's accepted blind spot: the warm start trusts the sealed prefix.
      final warm = await open(copy);
      expect(warm.unified!.decodedRecords, 0);
      // An explicit full audit reads every byte and refuses it.
      await expectLater(
        warm.unified!.profile.serialize(
          () => warm.unified!.refreshInProfileQueue(forceFullAudit: true),
        ),
        throwsA(isA<FormatFailure>()),
      );
      await warm.close(sealCache: false);
    },
  );

  test(
    'peer records arrive during catch-up; local edits append after the own head',
    () async {
      final a = await seeded('${root.path}/a', 2);
      final b = await open('${root.path}/b');
      await addTask(b, 'Synthetic from B before');
      await a.refresh();
      final aCopy = await killedCopy('${root.path}/a');
      await a.close();
      // B writes while A is stopped.
      await addTask(b, 'Synthetic from B while A is stopped');
      await addTask(b, 'Synthetic from B, again');
      final bRows = jsonEncode(b.rows);

      final reopened = await open(aCopy, defer: true);
      final history = reopened.unified!;
      expect(history.decodedRecords, 0);
      expect(history.catchUpPending, isTrue);
      // Lists are the stored state: B's two new tasks are not there yet.
      final stored = reopened.rows.length;
      expect(stored, b.rows.length - 2);

      // A local edit before catch-up has run: it waits for catch-up on the
      // profile queue and lands after A's own sealed head.
      final ownBefore = history.snapshot.recordsByWriter[history.writer]!.last;
      await addTask(reopened, 'Synthetic from A during catch-up');
      expect(history.catchUpPending, isFalse);
      final own = history.snapshot.recordsByWriter[history.writer]!;
      expect(own[own.length - 2].hash, ownBefore.hash);
      expect(reopened.rows.length, b.rows.length + 1);
      await b.refresh();
      expect(jsonEncode(b.rows), jsonEncode(reopened.rows));
      expect(bRows, isNot(jsonEncode(b.rows)));

      // Everything, including the caught-up peer records, is in the store.
      final records = history.snapshot.records.length;
      final again = await open(await killedCopy(history.profile.root));
      expect(again.unified!.decodedRecords, 0);
      expect(again.unified!.decodedCacheReuses, records);
      expect(jsonEncode(again.rows), jsonEncode(reopened.rows));
      await again.close(sealCache: false);
      await reopened.close();
      await b.close();
    },
  );

  test(
    'catch-up without edits applies peer records on the next refresh',
    () async {
      final a = await seeded('${root.path}/a', 1);
      final b = await open('${root.path}/b');
      await a.refresh();
      final aCopy = await killedCopy('${root.path}/a');
      await a.close();
      await addTask(b, 'Synthetic from B while A is stopped');
      final reopened = await open(aCopy, defer: true);
      expect(reopened.unified!.catchUpPending, isTrue);
      expect(reopened.rows.length, b.rows.length - 1);
      await reopened.refresh();
      expect(reopened.unified!.catchUpPending, isFalse);
      expect(jsonEncode(reopened.rows), jsonEncode(b.rows));
      // Without deferral the open itself applies them.
      final direct = await open(await killedCopy(aCopy));
      expect(direct.unified!.catchUpPending, isFalse);
      expect(jsonEncode(direct.rows), jsonEncode(b.rows));
      await direct.close(sealCache: false);
      await reopened.close();
      await b.close();
    },
  );
}
