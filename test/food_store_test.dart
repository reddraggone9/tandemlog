import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/task_store.dart';

const installation = '00000000-0000-4000-8000-000000000001';

class FaultFolder
    implements LogFolder, BoundedLogFolder, TailTruncateLogFolder {
  FaultFolder(this.inner);
  final LogFolder inner;
  int? prefix;
  bool throwAfter = false;
  int listCalls = 0;
  String? readFailure;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() {
    listCalls++;
    return inner.list();
  }

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
  Future<void> truncateOwnedTail(
    String name,
    Uint8List expected,
    int keepBytes,
  ) => (inner as TailTruncateLogFolder).truncateOwnedTail(
    name,
    expected,
    keepBytes,
  );
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
    // Empty declared bootstrap owners may have no file until their first save.
    // These provider-fault tests explicitly supply the equivalent empty file.
    await folder.create('$installation.applog', Uint8List(0));
  });
  tearDown(() async {
    await food?.close();
    food = null;
    await tasks.close();
    await profile.close();
    await root.delete(recursive: true);
  });
  Future<void> open() async {
    await tasks.refresh();
    food = await FoodStore.openUnified(tasks.unified!);
  }

  test(
    'Food prepares from one fresh observation and retains confirmation',
    () async {
      await open();
      final before = folder.listCalls;
      await food!.add(const FoodDetails(name: 'Single preparation'), 1);
      // One prepare, one final concurrent-write check, one own-append confirmation.
      expect(folder.listCalls - before, 3);
      expect(food!.state.containers.single.details.name, 'Single preparation');
      expect(tasks.unified!.pendingRecords, isEmpty);
    },
  );

  List<Map<String, Object?>> receipts() => [
    for (final r in tasks.unified!.pendingRecords)
      {'raw': utf8.encode('${r.encode()}\n')},
  ];
  test(
    'malformed common Food history blocks both modules without changing the view',
    () async {
      await open();
      final file = File('${folder.location}/$installation.applog');
      final original = await file.readAsBytes();
      await file.writeAsBytes([...original, ...utf8.encode('not-json\n')]);
      await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
      await expectLater(
        tasks.command('00000000-0000-4000-8000-000000000002', 'user.created', {
          'name': 'Must not append',
        }),
        throwsA(isA<FormatFailure>()),
      );
      expect(tasks.rows, isEmpty);
      expect(food!.state.active, isEmpty);
      expect(receipts(), isEmpty);
      expect(await file.readAsBytes(), [
        ...original,
        ...utf8.encode('not-json\n'),
      ]);
    },
  );
  test(
    'common provider failure blocks both modules and recovers after access returns',
    () async {
      await open();
      folder.readFailure = '$installation.applog';
      await expectLater(food!.refresh(), throwsA(isA<FolderAccessFailure>()));
      await expectLater(tasks.refresh(), throwsA(isA<FolderAccessFailure>()));
      folder.readFailure = null;
      await food!.refresh();
      expect(food!.state.active, isEmpty);
    },
  );
  test('moved manifest stays a shared fatal fault', () async {
    await File(
      '${folder.location}/tandemlog-space.json',
    ).writeAsString('{"v":3,"id":"00000000-0000-4000-8000-000000000003"}');
    await expectLater(open(), throwsA(isA<FormatFailure>()));
    await expectLater(tasks.refresh(), throwsA(isA<FormatFailure>()));
  });
  test('malformed protected common head is shared integrity', () async {
    await open();
    profile.database.execute('UPDATE protected_app_heads SET sequence=-1');
    await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
    await expectLater(tasks.refresh(), throwsA(isA<FormatFailure>()));
  });
  for (final name in [
    '$installation.sync-conflict-synthetic.applog',
    '$installation.applog.sync-conflict-synthetic',
    'unclassified.sync-conflict-synthetic',
  ]) {
    test(
      'sync conflict blocks both modules and preserves its bytes: $name',
      () async {
        await open();
        final conflict = File('${folder.location}/$name');
        await conflict.writeAsString('preserve me');
        await expectLater(tasks.refresh(), throwsA(isA<FormatFailure>()));
        await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
        expect(await conflict.readAsString(), 'preserve me');
      },
    );
  }
  test(
    'corrupt owned append retains its exact receipt without guessing repair',
    () async {
      await open();
      final file = File('${folder.location}/$installation.applog');
      final original = await file.readAsBytes();
      folder.prefix = 71;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 1),
        throwsStateError,
      );
      final pending = receipts();
      expect(pending, hasLength(1));
      await file.writeAsBytes([...original, ...utf8.encode('not-json\n')]);
      await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
      expect(receipts(), pending);
      expect(food!.state.active, isEmpty);
      // Restore the exact failed synthetic prefix, then use normal exact recovery.
      await file.writeAsBytes([
        ...original,
        ...(pending.single['raw'] as List<int>).take(71),
      ]);
      await food!.recoverPrepared();
      expect(food!.state.active, hasLength(1));
      expect(receipts(), isEmpty);
    },
  );

  test(
    'physical count and durable Deleted survive restart with the task prefix unchanged',
    () async {
      final before = await folder.read('tandemlog-space.json');
      await tasks.command(
        '00000000-0000-4000-8000-000000000002',
        'user.created',
        {'name': 'Synthetic'},
      );
      final taskBytes = await folder.read('$installation.applog');
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
      expect(
        (await folder.read(
          '$installation.applog',
        )).take(taskBytes.length).toList(),
        taskBytes,
      );
      expect(await folder.read('tandemlog-space.json'), before);
      expect(
        (await folder.list()).where((e) => e.name.endsWith('.applog')),
        hasLength(1),
      );
    },
  );
  test(
    'partial first action is reconciled from memory in the same running profile',
    () async {
      await open();
      folder.prefix = 71;
      await expectLater(
        food!.add(const FoodDetails(name: 'Rice'), 1),
        throwsStateError,
      );
      final base = tasks.unified!.snapshot.physical[installation]!;
      final saved = receipts();
      expect(saved, hasLength(1));
      expect(food!.state.active, isEmpty);
      await food!.close();
      await open();
      expect(food!.hasPreparedAppend, isTrue);
      await food!.recoverPrepared();
      expect(food!.state.active, hasLength(1));
      expect(await folder.read(unifiedLogName(installation)), [
        ...base,
        ...(saved.single['raw'] as List<int>),
      ]);
      expect(receipts(), isEmpty);
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
        '${folder.location}/${unifiedLogName(installation)}',
      ).rename('${root.path}/preserved.foodlog');
      await expectLater(food!.refresh(), throwsA(isA<FormatFailure>()));
      expect(food!.state.active, hasLength(1));
      await expectLater(
        food!.remove([food!.state.active.single.id]),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test('food refresh SQL fault preserves state and receipts together', () async {
    await open();
    profile.database.execute(
      "CREATE TRIGGER reject_food_head BEFORE INSERT ON protected_app_heads WHEN NEW.sequence>0 BEGIN SELECT RAISE(ABORT,'synthetic admission failure'); END",
    );
    profile.database.execute(
      "CREATE TRIGGER reject_food_head_update BEFORE UPDATE ON protected_app_heads WHEN NEW.sequence>0 BEGIN SELECT RAISE(ABORT,'synthetic admission failure'); END",
    );
    await expectLater(
      food!.add(const FoodDetails(name: 'Rice'), 1),
      throwsA(isA<Exception>()),
    );
    expect(food!.state.active, isEmpty);
    expect(receipts(), hasLength(1));
    profile.database.execute('DROP TRIGGER reject_food_head');
    profile.database.execute('DROP TRIGGER reject_food_head_update');
    await food!.refresh();
    expect(food!.state.active, hasLength(1));
    expect(food!.hasPreparedAppend, isFalse);
  });
  test(
    'restart forgets the unfinished Food save and truncates only its tail on explicit Save',
    () async {
      await open();
      final file = File('${folder.location}/$installation.applog');
      final before = await file.readAsBytes();
      folder.prefix = 71;
      await expectLater(
        food!.add(const FoodDetails(name: 'Abandoned'), 1),
        throwsStateError,
      );
      final abandoned =
          food!.lastPreparedRecords.single.operation.targets.single;
      final partial = await file.readAsBytes();
      await food!.close();
      food = null;
      await tasks.close();
      await profile.close();
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: installation,
      );
      await open();
      expect(food!.hasPreparedAppend, isFalse);
      expect(await file.readAsBytes(), partial);
      await food!.add(const FoodDetails(name: 'Replacement'), 1);
      expect(food!.state.active.single.details.name, 'Replacement');
      expect(food!.state.active.single.id, isNot(abandoned));
      expect((await file.readAsBytes()).take(before.length).toList(), before);
    },
  );

  test(
    'food handle releases its lease when the profile owner is poisoned',
    () async {
      final settingsRaw = utf8.encode(
        jsonEncode({'writer': installation, 'appearance': 'dark'}),
      );
      profile.transaction(
        () => profile.database.execute(
          'INSERT OR REPLACE INTO protected_settings VALUES (1,?,?)',
          [installation, settingsRaw],
        ),
      );
      await tasks.command(
        '00000000-0000-4000-8000-000000000002',
        'user.created',
        {'name': 'Preserved after poison'},
      );
      final taskBytes = await folder.read('$installation.applog');
      await open();
      await food!.add(const FoodDetails(name: 'Rice'), 1);
      final id = food!.state.active.single.id;
      final space = tasks.space;
      final writer = food!.writer;
      final before = await folder.read(unifiedLogName(writer));
      final heads = profile.database
          .select('SELECT * FROM protected_app_heads')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      final guards = profile.database
          .select(
            'SELECT * FROM protected_app_heads ORDER BY space,epoch,writer',
          )
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      expect(
        () => profile.transaction(() => profile.database.close()),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(() => profile.database, throwsStateError);
      var admitted = false;
      await expectLater(
        profile.serialize(() async => admitted = true),
        throwsStateError,
      );
      expect(admitted, isFalse);
      await expectLater(food!.refresh(), throwsStateError);
      await food!.close();
      await tasks.close();
      await profile.close();
      await food!.close();
      await tasks.close();
      await profile.close();

      // Successful reopening proves both module leases and the owner's lease
      // were released, while the committed identity/history survive poison.
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      final settings = LocalSettings(profile.root, profileDatabase: profile);
      await settings.load();
      expect(settings.writer, installation);
      expect(settings.appearance, Appearance.dark);
      expect(
        profile.database
            .select('SELECT raw FROM protected_settings')
            .single['raw'],
        settingsRaw,
      );
      expect(
        profile.database.select('SELECT * FROM protected_app_heads'),
        heads,
      );
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: settings.writer,
      );
      food = null;
      await open();
      expect(tasks.space, space);
      expect(food!.writer, writer);
      expect(food!.state.active.single.id, id);
      expect(await folder.read(unifiedLogName(writer)), before);
      expect(
        (await folder.read(
          '$installation.applog',
        )).take(taskBytes.length).toList(),
        taskBytes,
      );
      expect(tasks.rows.single['name'], 'Preserved after poison');
      expect(
        profile.database.select(
          'SELECT * FROM protected_app_heads ORDER BY space,epoch,writer',
        ),
        guards,
      );
    },
  );
}
