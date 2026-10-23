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

void main() {
  for (final damage in [
    'none',
    'typed',
    'raw',
    'generation',
    'binding',
    'missing',
    'malformed',
  ]) {
    test('clean action decode cache $damage retains canonical authority', () async {
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
        final files = {
          for (final entry in await folder.list())
            entry.name: base64Encode(await folder.read(entry.name)),
        };
        await store.close();
        store = null;
        if (damage != 'none') {
          final profile = await LocalProfileDatabase.open(profilePath);
          try {
            profile.transaction(() {
              final payload = profile.database
                  .select(
                    "SELECT key,value FROM profile_metadata WHERE key LIKE 'app5.decoded.payload.%'",
                  )
                  .single;
              final proof = profile.database
                  .select(
                    "SELECT key,value FROM profile_metadata WHERE key LIKE 'app5.decoded.proof.%'",
                  )
                  .single;
              if (damage == 'missing') {
                profile.database.execute(
                  'DELETE FROM profile_metadata WHERE key=?',
                  [proof['key']],
                );
                return;
              }
              final value = jsonDecode(payload['value'] as String) as Map;
              switch (damage) {
                case 'typed':
                  final rows = value['records'] as List;
                  final pair = rows
                      .expand((row) => (row as List)[1] as List)
                      .whereType<List>()
                      .last;
                  final typed = pair[1] as List;
                  (typed[6] as Map)['title'] = 'Forged cached title';
                case 'raw':
                  (value['records'] as List).last[0] = '{}';
                case 'generation':
                  value['generation'] = 999;
                case 'binding':
                  value['binding'] = 'another profile';
              }
              final changed = damage == 'malformed' ? '{' : jsonEncode(value);
              profile.database.execute(
                'UPDATE profile_metadata SET value=? WHERE key=?',
                [changed, payload['key']],
              );
              if (damage == 'generation' || damage == 'binding') {
                // Even a coherent checksum cannot bypass reader/scope binding.
                profile.database.execute(
                  'UPDATE profile_metadata SET value=? WHERE key=?',
                  [
                    sha256.convert(utf8.encode(changed)).toString(),
                    proof['key'],
                  ],
                );
              }
            });
          } finally {
            await profile.close();
          }
        }
        store = await TaskStore.open(folder, profilePath);
        expect(jsonEncode(store.rows), expected);
        expect(
          store.unified!.decodedCacheReuses,
          damage == 'none' ? greaterThan(0) : 0,
        );
        expect(
          store.unified!.decodedRecords,
          damage == 'none' ? 0 : greaterThan(0),
        );
        expect(
          store.db.select(
            "SELECT key FROM profile_metadata WHERE key LIKE 'app5.decoded.proof.%'",
          ),
          isEmpty,
          reason: 'A consumed proof cannot survive an unclean process stop.',
        );
        final beforeAudit = store.unified!.decodedRecords;
        await store.verifyHistory();
        expect(store.unified!.decodedRecords, greaterThan(beforeAudit));
        expect(jsonEncode(store.rows), expected);
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
        final payload = UnifiedDecodedCache.encode(
          records,
          'Synthetic binding',
        );
        final batch = ValidatedActionCache.verify(
          payload,
          sha256.convert(utf8.encode(payload)).toString(),
          'Synthetic binding',
        );
        final receipts = batch.records
            .expand((record) => record.effects)
            .toList();
        final saved = receipts
            .where((effect) => effect.kind.endsWith('food'))
            .toList();
        expect(saved, isNotEmpty);
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
        }
        expect(
          () => FoodRecord.fromDecodedCache(
            receipts.firstWhere((effect) => effect.kind.endsWith('task')),
          ),
          throwsFormatException,
        );
        final swapped = jsonDecode(payload) as Map;
        final row =
            (swapped['records'] as List).firstWhere(
                  (row) => ((row as List)[1] as List).any(
                    (effect) =>
                        effect is List &&
                        (effect[0] as String).endsWith('food'),
                  ),
                )
                as List;
        final effect =
            (row[1] as List).firstWhere(
                  (effect) =>
                      effect is List && (effect[0] as String).endsWith('food'),
                )
                as List;
        effect[0] = 'task';
        final changed = jsonEncode(swapped);
        expect(
          () => ValidatedActionCache.verify(
            changed,
            sha256.convert(utf8.encode(changed)).toString(),
            'Synthetic binding',
          ),
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
      final payload = UnifiedDecodedCache.encode([
        record,
      ], 'Historical binding');
      final restored = UnifiedDecodedCache.restore(
        payload,
        sha256.convert(utf8.encode(payload)).toString(),
        'Historical binding',
      ).single;
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
}
