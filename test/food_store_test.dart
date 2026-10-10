import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/task_store.dart';

const installation = '00000000-0000-4000-8000-000000000001';

class FaultFolder implements LogFolder, BoundedLogFolder {
  FaultFolder(this.inner);
  final LogFolder inner;
  int? prefix;
  bool throwAfter = false;
  String? readFailure;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (name == readFailure) {
      throw FolderAccessFailure('Synthetic Food-only read failure');
    }
    return (inner as BoundedLogFolder).readBounded(name, maximumBytes);
  }

  @override
  Future<Uint8List> read(String name) => inner.read(name);
  Future<void> write(String name, Uint8List bytes, bool create) async {
    final cut = prefix;
    prefix = null;
    final saved = cut == null
        ? bytes
        : Uint8List.sublistView(bytes, 0, cut.clamp(0, bytes.length));
    if (create) {
      await inner.create(name, saved);
    } else {
      await inner.append(name, saved);
    }
    if (cut != null || throwAfter) {
      throwAfter = false;
      throw StateError('synthetic append failure');
    }
  }

  @override
  Future<void> create(String n, Uint8List b) => write(n, b, true);
  @override
  Future<void> append(String n, Uint8List b) => write(n, b, false);
}

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  late TaskStore tasks;
  late FaultFolder folder;
  FoodStore? food;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('food-store-');
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    final data = await Directory('${root.path}/data').create();
    folder = FaultFolder(LocalLogFolder(data.path));
    tasks = await TaskStore.open(
      folder,
      profile.root,
      profileDatabase: profile,
      writerIdentity: installation,
    );
  });
  tearDown(() async {
    await food?.close();
    food = null;
    await tasks.close();
    await profile.close();
    await root.delete(recursive: true);
  });
  Future<void> open() async {
    food = await FoodStore.open(
      folder,
      profile: profile,
      installationWriter: installation,
      space: tasks.space,
    );
  }

  test(
    'malformed Food disables only Food and existing Tasks remain writable',
    () async {
      await File(
        '${folder.location}/food-$installation.foodlog',
      ).writeAsString('not-json\n');
      await expectLater(open(), throwsA(isA<FoodHistoryFailure>()));
      await tasks.refresh();
      await tasks.command(
        '00000000-0000-4000-8000-000000000002',
        'user.created',
        {'name': 'Still available'},
      );
      expect(tasks.rows.single['name'], 'Still available');
      expect(
        ProfileFoodIntents(
          profile,
        ).pending(tasks.space, foodWriter(installation)),
        isEmpty,
      );
    },
  );
  test(
    'Food-only provider failure preserves the typed module boundary',
    () async {
      final name = 'food-$installation.foodlog';
      await File('${folder.location}/$name').writeAsBytes([]);
      folder.readFailure = name;
      await expectLater(open(), throwsA(isA<FoodHistoryFailure>()));
      await tasks.refresh();
      folder.readFailure = null;
      await open();
      expect(food!.state.active, isEmpty);
    },
  );
  test('moved manifest stays a shared fatal fault', () async {
    await File(
      '${folder.location}/tandemlog-space.json',
    ).writeAsString('{"v":3,"id":"00000000-0000-4000-8000-000000000003"}');
    await expectLater(
      open(),
      throwsA(
        isA<FormatException>().having(
          (e) => e is FoodHistoryFailure,
          'module-only',
          false,
        ),
      ),
    );
    await expectLater(tasks.refresh(), throwsA(isA<FormatFailure>()));
    expect(
      profile.database.select('SELECT * FROM protected_food_heads'),
      isEmpty,
    );
  });
  test(
    'malformed protected Food head is shared integrity, not history',
    () async {
      await open();
      await food!.close();
      food = null;
      profile.database.execute('UPDATE protected_food_heads SET sequence=-1');
      await expectLater(
        open(),
        throwsA(
          isA<FormatException>().having(
            (e) => e is FoodHistoryFailure,
            'module-only',
            false,
          ),
        ),
      );
    },
  );
  for (final name in [
    'food-$installation.sync-conflict-synthetic.foodlog',
    'food-$installation.foodlog.sync-conflict-synthetic',
  ]) {
    test('recognized Food conflict stays module-scoped: $name', () async {
      await File('${folder.location}/$name').writeAsString('preserve me');
      await tasks.refresh();
      await expectLater(open(), throwsA(isA<FoodHistoryFailure>()));
      expect(
        await File('${folder.location}/$name').readAsString(),
        'preserve me',
      );
    });
  }
  test(
    'unclassified conflict preserves released Task fail-closed policy',
    () async {
      await File(
        '${folder.location}/unclassified.sync-conflict-synthetic',
      ).writeAsString('preserve me');
      await expectLater(tasks.refresh(), throwsA(isA<FormatFailure>()));
    },
  );
  test(
    'disabled Food retains exact prepared bytes for explicit recovery',
    () async {
      await open();
      folder.prefix = 71;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 1),
        throwsStateError,
      );
      final receipts = ProfileFoodIntents(
        profile,
      ).pending(tasks.space, foodWriter(installation));
      await food!.close();
      food = null;
      final remote = File('${folder.location}/food-$installation.foodlog');
      await remote.writeAsString('not-json\n');
      await expectLater(open(), throwsA(isA<FoodHistoryFailure>()));
      expect(
        ProfileFoodIntents(
          profile,
        ).pending(tasks.space, foodWriter(installation)).single,
        receipts.single,
      );
      await tasks.refresh();
      await remote.writeAsBytes([]);
      await open();
      await food!.recoverPrepared();
      expect(food!.state.active, hasLength(1));
      expect(
        ProfileFoodIntents(
          profile,
        ).pending(tasks.space, foodWriter(installation)),
        isEmpty,
      );
    },
  );

  test(
    'food physical count and durable Deleted survive restart without changing task v3 bytes',
    () async {
      final before = await folder.read('tandemlog-space.json');
      await tasks.command(
        '00000000-0000-4000-8000-000000000002',
        'user.created',
        {'name': 'Synthetic'},
      );
      final taskBytes = await folder.read('$installation.jsonl');
      await open();
      await food!.add(const FoodDetails(name: 'Rice', expiry: '2026-10-15'), 8);
      final id = food!.state.active.first.id;
      await food!.remove([id]);
      await food!.close();
      await open();
      expect(food!.state.active, hasLength(7));
      expect(food!.state.deleted.single.id, id);
      await food!.restore([food!.state.deleted.single]);
      expect(food!.state.active, hasLength(8));
      await tasks.refresh();
      expect(await folder.read('$installation.jsonl'), taskBytes);
      expect(await folder.read('tandemlog-space.json'), before);
      expect(
        (await folder.list()).where((e) => e.name.endsWith('.foodlog')),
        hasLength(1),
      );
    },
  );
  test(
    'partial first record is resumed exactly from protected bytes across restart',
    () async {
      await open();
      folder.prefix = 71;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 1),
        throwsStateError,
      );
      final saved = ProfileFoodIntents(
        profile,
      ).pending(tasks.space, foodWriter(installation));
      expect(saved, hasLength(1));
      expect(food!.state.active, isEmpty);
      await food!.close();
      await open();
      expect(food!.hasPreparedAppend, isTrue);
      await food!.recoverPrepared();
      expect(food!.state.active, hasLength(1));
      expect(
        await folder.read(foodLogName(foodWriter(installation))),
        utf8.encode('${utf8.decode(saved.single)}\n'),
      );
      expect(
        ProfileFoodIntents(
          profile,
        ).pending(tasks.space, foodWriter(installation)),
        isEmpty,
      );
    },
  );
  test(
    'uncertain successful append admits once and retires exact receipt',
    () async {
      await open();
      folder.throwAfter = true;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 2),
        throwsStateError,
      );
      await food!.refresh();
      expect(food!.state.active, hasLength(2));
      expect(food!.hasPreparedAppend, isFalse);
      await food!.refresh();
      expect(food!.state.active, hasLength(2));
    },
  );
  test(
    'acknowledged missing stream fails closed and retains last view',
    () async {
      await open();
      await food!.add(const FoodDetails(name: 'Rice'), 1);
      await File(
        '${folder.location}/${foodLogName(foodWriter(installation))}',
      ).rename('${root.path}/preserved.foodlog');
      await expectLater(food!.refresh(), throwsFormatException);
      expect(food!.state.active, hasLength(1));
      await expectLater(
        food!.remove([food!.state.active.single.id]),
        throwsFormatException,
      );
    },
  );
  test('food refresh SQL fault preserves state and receipts together', () async {
    await open();
    profile.database.execute(
      "CREATE TRIGGER reject_food_head BEFORE INSERT ON protected_food_heads WHEN NEW.sequence>0 BEGIN SELECT RAISE(ABORT,'synthetic admission failure'); END",
    );
    await expectLater(
      food!.add(const FoodDetails(name: 'Rice'), 1),
      throwsA(isA<Exception>()),
    );
    expect(food!.state.active, isEmpty);
    expect(
      ProfileFoodIntents(
        profile,
      ).pending(tasks.space, foodWriter(installation)),
      hasLength(1),
    );
    profile.database.execute('DROP TRIGGER reject_food_head');
    await food!.refresh();
    expect(food!.state.active, hasLength(1));
    expect(food!.hasPreparedAppend, isFalse);
  });
  test(
    'missing own reservation after initialization cannot reuse a sequence',
    () async {
      await open();
      folder.prefix = 0;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 1),
        throwsStateError,
      );
      await food!.close();
      food = null;
      profile.database.execute('DELETE FROM protected_food_intents');
      profile.database.execute(
        'DELETE FROM protected_writer_guards WHERE space=? AND writer=?',
        [tasks.space, foodWriter(installation)],
      );
      await expectLater(open(), throwsFormatException);
      expect(
        (await folder.read(foodLogName(foodWriter(installation)))).length,
        0,
      );
    },
  );

  test(
    'food handle releases its lease when the profile owner is poisoned',
    () async {
      await open();
      expect(
        () => profile.transaction(() => profile.database.close()),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      await food!.close();
      await tasks.close();
      await profile.close();
    },
  );
}
