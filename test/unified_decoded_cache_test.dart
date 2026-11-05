import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/validated_action_cache.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'current_history_fixture.dart';

void main() {
  String storeKey(LogFolder folder) =>
      sha256.convert(utf8.encode(folder.location)).toString();

  // Lee 11-05 (design/history-store.md): the fast check catches a changed
  // binding/generation, a missing store, a changed last record and a seal
  // that differs from the protected head; each opens strictly and rebuilds.
  // Other stored row contents are trusted until Verify Logs rewrites them.
  for (final damage in [
    'none',
    'generation',
    'missing',
    'lastRaw',
    'seal',
    'typed',
  ]) {
    test('history store damage "$damage" keeps canonical authority', () async {
      final root = await Directory.systemTemp.createTemp('decoded-clean-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profilePath = '${root.path}/profile';
      TaskStore? store;
      try {
        store = await TaskStore.open(folder, profilePath);
        final user = const Uuid().v4(), task = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(task, 'task.created', {
          'title': 'Canonical title',
          'description': '',
          'assignee': user,
        });
        final expected = jsonEncode(store.rows);
        final records = store.unified!.snapshot.records.length;
        String titles(TaskStore s) => jsonEncode([
          for (final e in s.unified!.snapshot.tasks)
            if (e.data['title'] != null) e.data['title'],
        ]);
        final canonicalTitles = titles(store);
        final files = {
          for (final entry in await folder.list())
            entry.name: base64Encode(await folder.read(entry.name)),
        };
        await store.close();
        store = null;
        final key = storeKey(folder);
        final profile = await LocalProfileDatabase.open(profilePath);
        try {
          profile.transaction(() {
            final db = profile.database;
            switch (damage) {
              case 'generation':
                final row = db.select(
                  'SELECT value FROM profile_metadata WHERE key=?',
                  ['app5.store.$key'],
                ).single;
                final binding = jsonDecode(row['value'] as String) as List;
                binding[0] = 999;
                db.execute('UPDATE profile_metadata SET value=? WHERE key=?', [
                  jsonEncode(binding),
                  'app5.store.$key',
                ]);
              case 'missing':
                db.execute('DELETE FROM profile_metadata WHERE key=?', [
                  'app5.store.$key',
                ]);
              case 'lastRaw':
                db.execute(
                  "UPDATE history_${key}_records SET raw='{}' WHERE seq=(SELECT MAX(seq) FROM history_${key}_records)",
                );
              case 'seal':
                db.execute(
                  'UPDATE history_${key}_seals SET sequence=sequence+1',
                );
              case 'typed':
                final row = db
                    .select(
                      "SELECT writer,seq,typed FROM history_${key}_records WHERE typed LIKE '%Canonical title%'",
                    )
                    .single;
                db.execute(
                  'UPDATE history_${key}_records SET typed=? WHERE writer=? AND seq=?',
                  [
                    (row['typed'] as String).replaceAll(
                      'Canonical title',
                      'Forged stored title',
                    ),
                    row['writer'],
                    row['seq'],
                  ],
                );
            }
          });
        } finally {
          await profile.close();
        }
        store = await TaskStore.open(folder, profilePath);
        expect(jsonEncode(store.rows), expected);
        final fast = damage == 'none' || damage == 'typed';
        expect(store.unified!.decodedCacheReuses, fast ? records : 0);
        expect(store.unified!.decodedRecords, fast ? 0 : records);
        // The accepted blind spot: other stored rows are trusted as stored.
        expect(titles(store) == canonicalTitles, damage != 'typed');
        final beforeAudit = store.unified!.decodedRecords;
        await store.verifyHistory();
        expect(store.unified!.decodedRecords, greaterThan(beforeAudit));
        expect(jsonEncode(store.rows), expected);
        expect(titles(store), canonicalTitles);
        await store.close();
        // Verify Logs rewrote the rows it re-read; the next open is warm and
        // equals the strict decode again.
        store = await TaskStore.open(folder, profilePath);
        expect(store.unified!.decodedRecords, 0);
        expect(titles(store), canonicalTitles);
        for (final entry in files.entries) {
          expect(base64Encode(await folder.read(entry.key)), entry.value);
        }
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    });
  }

  test(
    'Food receipts preserve wire evidence, Undo and immutable batch positions',
    () async {
      final root = await Directory.systemTemp.createTemp('decoded-food-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profilePath = '${root.path}/profile';
      TaskStore? tasks;
      FoodStore? food;
      try {
        tasks = await TaskStore.open(folder, profilePath);
        await tasks.command(const Uuid().v4(), 'user.created', {
          'name': 'Synthetic',
        });
        food = await FoodStore.openUnified(tasks.unified!);
        await food.add(
          const FoodDetails(name: 'Synthetic food', brand: 'Test'),
          2,
        );
        final removed = await food.remove([food.state.containers.first.id]);
        await food.undoOperations(removed);
        final expected = jsonEncode(
          food.state.containers.map((v) => v.toJson()).toList(),
        );
        final records = tasks.unified!.snapshot.records;
        List<(String, String)> rowsOf(Iterable<UnifiedRecord> records) => [
          for (final r in records)
            (r.encode(), UnifiedDecodedCache.typedFields(r)),
        ];
        final batch = ValidatedActionCache.fromStoredRows(rowsOf(records));
        final receipts = batch.records
            .expand((record) => record.effects)
            .toList();
        final saved = receipts
            .where((effect) => effect.kind.endsWith('food'))
            .toList();
        expect(saved, isNotEmpty);
        expect(() => batch.records.clear(), throwsUnsupportedError);
        final outer = batch.records.first.value;
        expect(() => outer['clock'] = 'changed', throwsUnsupportedError);
        final wire = outer['effects'] as List;
        expect(() => wire.clear(), throwsUnsupportedError);
        expect(
          () => (wire.first as Map)['raw'] = 'changed',
          throwsUnsupportedError,
        );
        for (final receipt in saved) {
          final cached = FoodRecord.fromDecodedCache(receipt);
          final strict = FoodRecord.decode(receipt.raw);
          expect(cached.encode(), receipt.raw);
          expect(cached.toJson(), strict.toJson());
          expect(cached.operation.toJson(), strict.operation.toJson());
          expect(cached.hash, strict.hash);
          expect(cached.integrityHash, strict.integrityHash);
          expect(cached.author, strict.author);
          expect(cached.attributedWriter, strict.attributedWriter);
          expect(cached.retainedReferenceHash, strict.retainedReferenceHash);
          expect(cached.createdWith, strict.createdWith);
          expect(cached.unified, strict.unified);
          expect(
            () => receipt.fields![0] = 'another space',
            throwsUnsupportedError,
          );
          expect(
            () => (receipt.fields![4] as Map)['id'] = 'another id',
            throwsUnsupportedError,
          );
          expect(
            () => ((receipt.fields![4] as Map)['targets'] as List).clear(),
            throwsUnsupportedError,
          );
        }
        expect(
          () => FoodRecord.fromDecodedCache(
            receipts.firstWhere((effect) => effect.kind.endsWith('task')),
          ),
          throwsFormatException,
        );
        final swapped = rowsOf(records).map((row) {
          final typed = jsonDecode(row.$2) as List;
          final i = typed.indexWhere(
            (effect) =>
                effect is List && (effect[0] as String).endsWith('food'),
          );
          if (i < 0) return row;
          (typed[i] as List)[0] = 'task';
          return (row.$1, jsonEncode(typed));
        }).toList();
        expect(
          () => ValidatedActionCache.fromStoredRows(swapped),
          throwsFormatException,
        );
        final bytes = await folder.read('${tasks.writer}.applog');
        await food.close();
        food = null;
        await tasks.close();
        tasks = null;
        tasks = await TaskStore.open(folder, profilePath);
        food = await FoodStore.openUnified(tasks.unified!);
        expect(tasks.unified!.decodedCacheReuses, greaterThan(0));
        expect(tasks.unified!.decodedRecords, 0);
        expect(
          jsonEncode(food.state.containers.map((v) => v.toJson()).toList()),
          expected,
        );
        expect(await folder.read('${tasks.writer}.applog'), bytes);
        final beforeAudit = tasks.unified!.decodedRecords;
        await tasks.verifyHistory();
        expect(tasks.unified!.decodedRecords, greaterThan(beforeAudit));
        expect(
          jsonEncode(food.state.containers.map((v) => v.toJson()).toList()),
          expected,
        );
      } finally {
        await food?.close();
        await tasks?.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'historical Food receipts retain distinct author and reference anchors',
    () {
      final space = const Uuid().v4(), epoch = const Uuid().v4();
      final originalWriter = const Uuid().v4(),
          currentAuthor = const Uuid().v4();
      final historical = FoodRecord(
        space: space,
        writer: originalWriter,
        sequence: 1,
        clock: EventClock(BigInt.from(100)),
        previousHash: eventGenesisHash(space, originalWriter),
        attributedWriter: currentAuthor,
        retainedReferenceHash: 'f' * 64,
        operation: FoodOperation(
          id: '$originalWriter:1',
          order: 100,
          action: FoodAction.add,
          targets: [const Uuid().v4()],
          details: const FoodDetails(name: 'Synthetic imported food'),
          contents: const Contents.fraction(1, 1),
          createdAt: '2030-05-10',
        ),
      );
      final record = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: currentAuthor,
        sequence: 1,
        clock: EventClock(BigInt.from(100)),
        previousHash: unifiedGenesis(space, epoch, currentAuthor),
        effect: UnifiedEffect('history.food', historical.encode()),
      );
      final restored = UnifiedDecodedCache.restoreStored([
        (record.encode(), UnifiedDecodedCache.typedFields(record)),
      ]).single;
      final cached = restored.effect.food!,
          strict = FoodRecord.decode(restored.effect.raw);
      expect(cached.writer, originalWriter);
      expect(cached.author, currentAuthor);
      expect(cached.attributedWriter, currentAuthor);
      expect(cached.retainedReferenceHash, 'f' * 64);
      expect(cached.hash, isNot(cached.integrityHash));
      expect(cached.hash, strict.hash);
      expect(cached.integrityHash, strict.integrityHash);
      expect(cached.encode(), strict.encode());
      expect(cached.toJson(), strict.toJson());
      expect(cached.operation.toJson(), strict.operation.toJson());
      expect(restored.encode(), record.encode());
    },
  );

  test('clean cache cannot hide an unknown complete appended action', () async {
    final root = await Directory.systemTemp.createTemp('decoded-suffix-');
    final folder = LocalLogFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    final profilePath = '${root.path}/profile';
    TaskStore? store;
    try {
      store = await TaskStore.open(folder, profilePath);
      await store.command(const Uuid().v4(), 'user.created', {
        'name': 'Synthetic',
      });
      final name = '${store.writer}.applog';
      await store.close();
      store = null;
      await folder.append(name, utf8.encode('{"v":987}\n'));
      final preserved = await folder.read(name);
      await expectLater(
        TaskStore.open(folder, profilePath),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read(name), preserved);
    } finally {
      await store?.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'warm cached prefix admits a new complete peer suffix without reusing its root',
    () async {
      final root = await Directory.systemTemp.createTemp('decoded-prefix-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profilePath = '${root.path}/profile';
      TaskStore? store;
      try {
        store = await TaskStore.open(folder, profilePath);
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Original',
        });
        final prefixCount = store.unified!.snapshot.records.length;
        final peer = const Uuid().v4(), added = const Uuid().v4();
        final bytes = peerBytesFor(
          store,
          LogEvent(
            store.space,
            peer,
            1,
            EventClock(store.unified!.maximumClock!.value + BigInt.one),
            added,
            'user.created',
            {'name': 'Arrived after clean close'},
          ),
        );
        final ownerName = '${store.writer}.applog';
        final original = await folder.read(ownerName);
        await store.close();
        store = null;
        await folder.create('$peer.applog', bytes);
        store = await TaskStore.open(folder, profilePath);
        expect(store.unified!.decodedCacheReuses, prefixCount);
        expect(store.unified!.decodedRecords, 2);
        expect(
          store.unified!.warmTaskCacheProofMicroseconds,
          greaterThan(0),
          reason:
              'The original Task prefix proof must be checked and restored, not silently replaced by a full rebuild.',
        );
        expect(store.unified!.warmTaskCacheRestoreMicroseconds, greaterThan(0));

        expect(
          store.rows.singleWhere((r) => r['id'] == added)['name'],
          'Arrived after clean close',
        );
        final expected = jsonEncode(store.rows);
        await store.verifyHistory();
        expect(jsonEncode(store.rows), expected);
        expect(await folder.read(ownerName), original);
        expect(await folder.read('$peer.applog'), bytes);
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );
}
