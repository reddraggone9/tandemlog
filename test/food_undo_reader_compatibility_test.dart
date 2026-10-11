import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/task_store.dart';

import 'fixtures/food-undo/released-build60/food/food_record.dart'
    as old_record;
import 'fixtures/food-undo/released-build60/food/food_store.dart' as old_store;
import 'food_store_undo_test.dart' show UndoFaultFolder;

const installation = '00000000-0000-4000-8000-000000000001';
const oldInstallation = '00000000-0000-4000-8000-000000000020';

void main() {
  test(
    'released Food reader source is frozen against its exact provenance',
    () {
      const root = 'test/fixtures/food-undo/released-build60';
      final provenance =
          jsonDecode(File('$root/provenance.json').readAsStringSync()) as Map;
      expect(provenance['commit'], '3d671c20c6a1f6bdc2a2082f9a00e820c34b8050');
      for (final entry in provenance['frozenFiles'] as List) {
        final relative = (entry['source'] as String).substring(4);
        final bytes = File('$root/$relative').readAsBytesSync();
        expect(bytes.length, entry['bytes']);
        expect(sha256.convert(bytes).toString(), entry['sha256']);
      }
    },
  );

  test(
    'actual released codec still reads frozen v1 and explicitly rejects v2',
    () {
      final lines = File(
        'test/fixtures/food-undo/mixed-v1-v2.foodlog',
      ).readAsLinesSync();
      expect(old_record.FoodRecord.decode(lines.first).encode(), lines.first);
      expect(
        () => old_record.FoodRecord.decode(lines.last),
        throwsFormatException,
      );
      expect(FoodRecord.decode(lines.first).encode(), lines.first);
      expect(FoodRecord.decode(lines.last).encode(), lines.last);
    },
  );

  group('actual released reader admission', () {
    late Directory root;
    late LocalProfileDatabase profile;
    late TaskStore tasks;
    late UndoFaultFolder folder;
    late FoodStore food;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('food-old-reader-');
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      folder = UndoFaultFolder(
        LocalLogFolder((await Directory('${root.path}/data').create()).path),
      );
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: installation,
      );
      food = await FoodStore.open(
        folder,
        profile: profile,
        installationWriter: installation,
        space: tasks.space,
      );
    });
    tearDown(() async {
      await food.close();
      await tasks.close();
      await profile.close();
      await root.delete(recursive: true);
    });

    test(
      'older peer rejects canonical v2 as Food-only without advancing heads or touching Tasks',
      () async {
        await food.add(const FoodDetails(name: 'Rice'), 1);
        await food.undoOperations(food.lastPreparedRecords.toList());
        final history = await folder.read(foodLogName(food.writer));
        final peerProfile = await LocalProfileDatabase.open(
          '${root.path}/old-peer',
        );
        try {
          await expectLater(
            old_store.FoodStore.open(
              folder,
              profile: peerProfile,
              installationWriter: oldInstallation,
              space: tasks.space,
            ),
            throwsA(isA<old_store.FoodHistoryFailure>()),
          );
          expect(
            peerProfile.database.select('SELECT * FROM protected_food_heads'),
            isEmpty,
          );
          expect(
            peerProfile.database.select('SELECT * FROM protected_food_intents'),
            isEmpty,
          );
          expect(await folder.read(foodLogName(food.writer)), history);
          await tasks.command(
            '00000000-0000-4000-8000-000000000002',
            'user.created',
            {'name': 'Tasks usable'},
          );
          expect(tasks.rows.single['name'], 'Tasks usable');
        } finally {
          await peerProfile.close();
        }
      },
    );

    test(
      'downgrade with protected v2 bytes fails hard, preserves authority and recovers on current reader',
      () async {
        await food.add(const FoodDetails(name: 'Rice'), 1);
        final add = food.lastPreparedRecords.toList();
        folder.completePrefix = 0;
        await expectLater(food.undoOperations(add), throwsStateError);
        final receipts = ProfileFoodIntents(
          profile,
        ).pending(tasks.space, food.writer);
        final history = await folder.read(foodLogName(food.writer));
        await food.close();
        await expectLater(
          old_store.FoodStore.open(
            folder,
            profile: profile,
            installationWriter: installation,
            space: tasks.space,
          ),
          throwsA(
            predicate(
              (failure) =>
                  failure is FormatException &&
                  failure is! old_store.FoodHistoryFailure,
            ),
          ),
        );
        expect(
          ProfileFoodIntents(profile).pending(tasks.space, food.writer).single,
          receipts.single,
        );
        expect(await folder.read(foodLogName(food.writer)), history);
        food = await FoodStore.open(
          folder,
          profile: profile,
          installationWriter: installation,
          space: tasks.space,
        );
        await food.recoverPrepared();
        expect(food.state.containers, isEmpty);
        expect(
          ProfileFoodIntents(profile).pending(tasks.space, food.writer),
          isEmpty,
        );
        final recovered = await folder.read(foodLogName(food.writer));
        expect(recovered.take(history.length).toList(), history);
      },
    );
  });
}
