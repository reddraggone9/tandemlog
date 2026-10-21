import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';

void main() {
  test(
    'wide-target thousand-reference normalized history has a bounded replay budget',
    () async {
      const writer = '00000000-0000-4000-8000-000000000001',
          space = '00000000-0000-4000-8000-000000000002',
          epoch = '00000000-0000-4000-8000-000000000003';
      final root = await Directory.systemTemp.createTemp(
        'food-current-replay-budget-',
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/data').create()).path,
      );
      UnifiedHistory? history;
      FoodStore? food;
      try {
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              writer,
              utf8.encode(
                jsonEncode({'writer': writer, 'appearance': 'system'}),
              ),
            ],
          ),
        );
        final targets = List.generate(
          100,
          (i) =>
              '00000000-0000-4000-8001-${i.toRadixString(16).padLeft(12, '0')}',
        );
        final lines = <String>[];
        var anchor = eventGenesisHash(space, writer),
            head = unifiedGenesis(space, epoch, writer);
        void append(FoodOperation op, {bool creation = false}) {
          final seq = lines.length + 1,
              clock = EventClock(BigInt.from(lines.length + 1));
          final food = FoodRecord(
            space: space,
            writer: writer,
            sequence: seq,
            clock: clock,
            operation: op,
            previousHash: anchor,
            createdWith: creation
                ? {}
                : {for (final id in targets) id: '$writer:1'},
          );
          final r = UnifiedRecord(
            space: space,
            epoch: epoch,
            writer: writer,
            sequence: seq,
            clock: clock,
            previousHash: head,
            effect: UnifiedEffect('history.food', food.encode()),
          );
          anchor = food.hash;
          head = r.hash;
          lines.add(r.encode());
        }

        append(
          FoodOperation(
            id: '$writer:1',
            order: 1,
            action: FoodAction.add,
            targets: targets,
            details: const FoodDetails(name: 'Synthetic Rice'),
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-10T00:00:00Z',
          ),
          creation: true,
        );
        for (var i = 2; i <= 1001; i++) {
          append(
            FoodOperation(
              id: '$writer:$i',
              order: i,
              action: FoodAction.remove,
              targets: targets,
            ),
          );
        }
        append(
          FoodOperation(
            id: '$writer:1002',
            order: 1002,
            action: FoodAction.restore,
            targets: targets,
            observedDeletes: List.generate(1000, (i) => '$writer:${i + 2}'),
          ),
        );
        final bytes = Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));
        final manifest = UnifiedManifest(
          space,
          epoch,
          bytesDigest(utf8.encode('synthetic-current-food-budget-v1')),
          {
            writer: {
              'count': lines.length,
              'head': head,
              'digest': bytesDigest(bytes),
            },
          },
          {writer: writer},
        );
        await folder.create(unifiedLogName(writer), bytes);
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(utf8.encode(manifest.encode())),
        );
        final timer = Stopwatch()..start();
        history = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: writer,
        );
        food = await FoodStore.openUnified(history);
        timer.stop();
        expect(food.state.active, hasLength(100));
        expect(food.state.deleted, isEmpty);
        expect(food.pendingReferences, 0);
        expect(timer.elapsedMilliseconds, lessThan(12000));
        debugPrint(
          'FOOD_REPLAY_BUDGET bytes=${bytes.length} records=${lines.length} targets=100 refs=1000 elapsed_ms=${timer.elapsedMilliseconds}',
        );
      } finally {
        await food?.close();
        await history?.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
