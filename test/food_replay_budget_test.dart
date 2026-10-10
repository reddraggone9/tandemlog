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
import 'package:tandemlog/storage/task_store.dart';

void main() {
  test(
    'wide-target thousand-reference history has a bounded replay budget',
    () async {
      const writer = '00000000-0000-4000-8000-000000000001';
      final root = await Directory.systemTemp.createTemp('food-replay-budget-');
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      final data = await Directory('${root.path}/data').create();
      final folder = LocalLogFolder(data.path);
      final tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: writer,
      );
      FoodStore? food;
      try {
        final targets = List.generate(
          100,
          (i) =>
              '00000000-0000-4000-8001-${i.toRadixString(16).padLeft(12, '0')}',
        );
        final lines = <String>[];
        var hash = eventGenesisHash(tasks.space, writer);
        void append(FoodOperation operation, {bool creation = false}) {
          final record = FoodRecord(
            space: tasks.space,
            writer: writer,
            sequence: lines.length + 1,
            clock: EventClock(BigInt.from(lines.length + 1)),
            operation: operation,
            previousHash: hash,
            createdWith: creation
                ? {}
                : {for (final id in targets) id: '$writer:1'},
          );
          lines.add(record.encode());
          hash = record.hash;
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
        final bytes = utf8.encode('${lines.join('\n')}\n');
        await File('${data.path}/${foodLogName(writer)}').writeAsBytes(bytes);
        final timer = Stopwatch()..start();
        food = await FoodStore.open(
          folder,
          profile: profile,
          installationWriter: writer,
          space: tasks.space,
        );
        timer.stop();
        expect(food.state.active, hasLength(100));
        expect(food.state.deleted, isEmpty);
        expect(food.pendingReferences, 0);
        // Generous Linux regression ceiling, not a mobile responsiveness claim.
        expect(timer.elapsedMilliseconds, lessThan(12000));
        debugPrint(
          'FOOD_REPLAY_BUDGET bytes=${bytes.length} records=${lines.length} targets=100 refs=1000 elapsed_ms=${timer.elapsedMilliseconds}',
        );
      } finally {
        await food?.close();
        await tasks.close();
        await profile.close();
        await root.delete(recursive: true);
      }
    },
  );
}
