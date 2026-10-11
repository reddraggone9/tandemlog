import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/task_store.dart';

const installation = '00000000-0000-4000-8000-000000000001';
const otherInstallation = '00000000-0000-4000-8000-000000000020';

class UndoFaultFolder implements LogFolder, BoundedLogFolder {
  UndoFaultFolder(this.inner);
  final LocalLogFolder inner;
  int? completePrefix;
  bool failAfterAll = false;
  int appendCalls = 0;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appendCalls++;
    final prefix = completePrefix;
    completePrefix = null;
    if (prefix != null) {
      var end = 0, lines = 0;
      while (end < bytes.length && lines < prefix) {
        if (bytes[end++] == 10) lines++;
      }
      if (end > 0) {
        await inner.append(name, Uint8List.sublistView(bytes, 0, end));
      }
      throw StateError('synthetic Undo prefix failure');
    }
    await inner.append(name, bytes);
    if (failAfterAll) {
      failAfterAll = false;
      throw StateError('synthetic acknowledgement failure');
    }
  }
}

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  late TaskStore tasks;
  late UndoFaultFolder folder;
  late FoodStore food;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('food-undo-store-');
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
  Future<List<FoodRecord>> inverse(List<FoodRecord> records) =>
      (food as dynamic).undoOperations(records) as Future<List<FoodRecord>>;
  Future<void> remote(
    FoodOperation operation, {
    Map<String, String>? basis,
  }) async {
    final record = FoodRecord(
      space: tasks.space,
      writer: foodWriter(otherInstallation),
      sequence: 1,
      clock: EventClock(BigInt.from(operation.order)),
      operation: operation,
      previousHash: eventGenesisHash(
        tasks.space,
        foodWriter(otherInstallation),
      ),
      createdWith: basis ?? {},
    );
    await File(
      '${folder.location}/${foodLogName(record.writer)}',
    ).writeAsString('${record.encode()}\n');
  }

  FoodOperation remoteEdit(String id, String birth, {bool remove = false}) =>
      FoodOperation(
        id: '${foodWriter(otherInstallation)}:1',
        order: (food.lastPreparedRecords.last.clock.value + BigInt.from(100))
            .toInt(),
        action: remove ? FoodAction.remove : FoodAction.edit,
        targets: [id],
        details: remove
            ? null
            : const FoodDetails(name: 'Peer title', brand: 'Peer'),
        fields: remove ? null : ['name', 'brand'],
      );

  test(
    'Undo each saved Food action preserves IDs and exact original log bytes',
    () async {
      await food.add(const FoodDetails(name: 'Rice', expiry: '2026-10-15'), 2);
      final add = food.lastPreparedRecords.toList();
      final ids = food.state.active.map((c) => c.id).toList();
      final originalBytes = await folder.read(foodLogName(food.writer));
      await food.changeDetails(
        ids,
        const FoodDetails(
          name: 'Changed',
          expiry: '2026-11-01',
          brand: 'Brand',
        ),
        ['name', 'brand', 'expiry'],
      );
      final edits = food.lastPreparedRecords.toList();
      await inverse(edits);
      expect(food.state.active.map((c) => c.details.name), ['Rice', 'Rice']);
      await food.changeContents(
        food.state.active.first,
        const Contents.fraction(1, 3),
      );
      final contents = food.lastPreparedRecords.toList();
      await inverse(contents);
      expect(food.state.active.every((c) => c.contents.full), isTrue);
      final removals = await food.remove(ids);
      await food.restore(food.state.deleted);
      final restores = food.lastPreparedRecords.toList();
      await inverse(restores);
      expect(food.state.deleted.map((c) => c.id).toSet(), ids.toSet());
      await inverse(removals);
      expect(food.state.active.map((c) => c.id).toSet(), ids.toSet());
      await inverse(add);
      expect(food.state.containers, isEmpty);
      final nowBytes = await folder.read(foodLogName(food.writer));
      expect(nowBytes.take(originalBytes.length).toList(), originalBytes);
      expect(
        ProfileFoodIntents(profile).pending(tasks.space, food.writer),
        isEmpty,
      );
      await food.close();
      food = await FoodStore.open(
        folder,
        profile: profile,
        installationWriter: installation,
        space: tasks.space,
      );
      expect(food.state.containers, isEmpty);
      expect(await folder.read(foodLogName(food.writer)), nowBytes);
    },
  );

  test(
    'Undo details and Add preserve later remote edits at the same physical ID',
    () async {
      await food.add(const FoodDetails(name: 'Rice', expiry: '2026-10-15'), 2);
      final add = food.lastPreparedRecords.toList();
      final ids = food.state.active.map((c) => c.id).toList();
      await food.changeDetails(
        ids,
        const FoodDetails(name: 'Local', brand: 'Local'),
        ['name', 'brand'],
      );
      final edits = food.lastPreparedRecords.toList();
      await remote(
        remoteEdit(ids.first, add.single.id),
        basis: {ids.first: add.single.id},
      );
      await inverse(edits);
      expect(
        food.state.active.firstWhere((c) => c.id == ids.first).details.name,
        'Peer title',
      );
      await inverse(add);
      expect(food.state.active.single.id, ids.first);
      expect(food.state.active.single.details.brand, 'Peer');
      expect(food.state.deleted, isEmpty);
    },
  );

  test(
    'late remote removal restores suppressed Add seed in Deleted, not Stock',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 1);
      final add = food.lastPreparedRecords.toList();
      final id = food.state.active.single.id;
      await inverse(add);
      expect(food.state.containers, isEmpty);
      await remote(
        remoteEdit(id, add.single.id, remove: true),
        basis: {id: add.single.id},
      );
      await food.refresh();
      expect(food.state.active, isEmpty);
      expect(food.state.deleted.single.id, id);
      expect(food.state.deleted.single.deletions, {
        '${foodWriter(otherInstallation)}:1',
      });
    },
  );

  test(
    'bulk Undo failure acknowledges only exact admitted prefix and retains full receipts',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 100);
      await food.add(const FoodDetails(name: 'Rice'), 1);
      final ids = food.state.active.map((c) => c.id).toList();
      final removals = await food.remove(ids);
      expect(removals, hasLength(2));
      folder.completePrefix = 1;
      await expectLater(inverse(removals), throwsStateError);
      final prepared = food.lastPreparedRecords.toList();
      expect(prepared, hasLength(2));
      await food.refresh();
      expect(prepared.map(food.isAdmitted), [true, false]);
      expect(food.state.active, hasLength(100));
      expect(food.state.deleted, hasLength(1));
      final before = await folder.read(foodLogName(food.writer));
      await food.recoverPrepared();
      expect(prepared.every(food.isAdmitted), isTrue);
      expect(food.state.active, hasLength(101));
      final after = await folder.read(foodLogName(food.writer));
      expect(after.take(before.length).toList(), before);
      final calls = folder.appendCalls;
      expect(await inverse(removals), isEmpty);
      expect(folder.appendCalls, calls);
      expect(await folder.read(foodLogName(food.writer)), after);
    },
  );

  test(
    'failed Undo before any bytes never claims admission and exact recovery survives restart',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 1);
      final remove = await food.remove([food.state.active.single.id]);
      folder.completePrefix = 0;
      await expectLater(inverse(remove), throwsStateError);
      final prepared = food.lastPreparedRecords.toList();
      await food.refresh();
      expect(prepared.any(food.isAdmitted), isFalse);
      expect(food.state.deleted, hasLength(1));
      final retained = ProfileFoodIntents(
        profile,
      ).pending(tasks.space, food.writer);
      expect(retained.single, utf8.encode(prepared.single.encode()));
      await food.close();
      food = await FoodStore.open(
        folder,
        profile: profile,
        installationWriter: installation,
        space: tasks.space,
      );
      expect(food.state.deleted, hasLength(1));
      await food.recoverPrepared();
      expect(food.isAdmitted(prepared.single), isTrue);
      expect(food.state.active, hasLength(1));
      expect(
        ProfileFoodIntents(profile).pending(tasks.space, food.writer),
        isEmpty,
      );
    },
  );

  test(
    'acknowledgement failure does not duplicate Undo after canonical confirmation',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 1);
      final add = food.lastPreparedRecords.toList();
      folder.failAfterAll = true;
      await expectLater(inverse(add), throwsStateError);
      final prepared = food.lastPreparedRecords.toList();
      await food.refresh();
      expect(prepared.every(food.isAdmitted), isTrue);
      final before = await folder.read(foodLogName(food.writer));
      expect(await inverse(add), isEmpty);
      expect(await folder.read(foodLogName(food.writer)), before);
    },
  );

  test(
    'foreign, different bytes, duplicate, and Undo receipts reject before append',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 1);
      final add = food.lastPreparedRecords.single;
      final id = food.state.active.single.id;
      final peerEdit = remoteEdit(id, add.id);
      await remote(peerEdit, basis: {id: add.id});
      await food.refresh();
      final peerRecord = FoodRecord.decode(
        (await File(
          '${folder.location}/${foodLogName(foodWriter(otherInstallation))}',
        ).readAsLines()).single,
      );
      final fake = FoodRecord(
        space: add.space,
        writer: add.writer,
        sequence: add.sequence,
        clock: add.clock,
        previousHash: add.previousHash,
        operation: FoodOperation(
          id: add.id,
          order: add.operation.order,
          action: FoodAction.add,
          targets: add.operation.targets,
          details: const FoodDetails(name: 'Different bytes'),
          createdAt: add.operation.createdAt,
        ),
      );
      final before = await folder.read(foodLogName(food.writer));
      for (final receipts in [
        [peerRecord],
        [fake],
        [add, add],
        <FoodRecord>[],
      ]) {
        await expectLater(inverse(receipts), throwsFormatException);
        expect(await folder.read(foodLogName(food.writer)), before);
      }
      final undone = await inverse([add]);
      await expectLater(inverse(undone), throwsFormatException);
    },
  );

  test(
    'invalid original creation reference is rejected even when Undo excludes edit',
    () async {
      await food.add(const FoodDetails(name: 'Rice'), 2);
      final id = food.state.active.first.id;
      final wrongBasis = (await food.remove([
        food.state.active.last.id,
      ])).single;
      final peerWriter = foodWriter(otherInstallation);
      final bad = FoodRecord(
        space: tasks.space,
        writer: peerWriter,
        sequence: 1,
        clock: EventClock(wrongBasis.clock.value + BigInt.one),
        previousHash: eventGenesisHash(tasks.space, peerWriter),
        operation: FoodOperation(
          id: '$peerWriter:1',
          order: (wrongBasis.clock.value + BigInt.one).toInt(),
          action: FoodAction.edit,
          targets: [id],
          details: const FoodDetails(name: 'Invalid basis'),
          fields: ['name'],
        ),
        createdWith: {id: wrongBasis.id},
      );
      final inverseRecord = FoodRecord.decode(
        jsonEncode(
          jsonDecode(
            File(
              'test/fixtures/food-undo/mixed-v1-v2.foodlog',
            ).readAsLinesSync().last,
          ),
        ),
      );
      // The frozen v2 fixture is exercised above; construct this site's own record
      // through the compact operation decoder without bypassing hash validation.
      final retraction = FoodRecord(
        space: tasks.space,
        writer: peerWriter,
        sequence: 2,
        clock: EventClock(bad.clock.value + BigInt.one),
        previousHash: bad.hash,
        createdWith: bad.createdWith,
        operation: FoodOperation.fromJson({
          'id': '$peerWriter:2',
          'order': '${bad.clock.value + BigInt.one}',
          'action': inverseRecord.operation.action.name,
          'targets': [id],
          'retracts': bad.id,
        }),
      );
      await File(
        '${folder.location}/${foodLogName(peerWriter)}',
      ).writeAsString('${bad.encode()}\n${retraction.encode()}\n');
      await expectLater(food.refresh(), throwsA(isA<FoodHistoryFailure>()));
      expect(food.state.active.single.id, id);
    },
  );

  for (final wrongTarget in [false, true]) {
    test(
      'Undo waits for original creation dependency; arriving ${wrongTarget ? 'invalid' : 'valid'} basis is checked',
      () async {
        const id = '00000000-0000-4000-8000-000000000031';
        const differentId = '00000000-0000-4000-8000-000000000032';
        const creatorInstallation = '00000000-0000-4000-8000-000000000030';
        final creator = foodWriter(creatorInstallation);
        final editor = foodWriter(otherInstallation);
        final basis = {id: '$creator:1'};
        final original = FoodRecord(
          space: tasks.space,
          writer: editor,
          sequence: 1,
          clock: EventClock(BigInt.two),
          previousHash: eventGenesisHash(tasks.space, editor),
          createdWith: basis,
          operation: FoodOperation(
            id: '$editor:1',
            order: 2,
            action: FoodAction.edit,
            targets: [id],
            details: const FoodDetails(name: 'Changed'),
            fields: ['name'],
          ),
        );
        final retraction = FoodRecord(
          space: tasks.space,
          writer: editor,
          sequence: 2,
          clock: EventClock(BigInt.from(3)),
          previousHash: original.hash,
          createdWith: basis,
          operation: FoodOperation.fromJson({
            'id': '$editor:2',
            'order': '3',
            'action': 'undo',
            'targets': [id],
            'retracts': original.id,
          }),
        );
        await File(
          '${folder.location}/${foodLogName(editor)}',
        ).writeAsString('${original.encode()}\n${retraction.encode()}\n');
        await food.refresh();
        expect(food.pendingOperationIds.toSet(), {original.id, retraction.id});
        expect(food.state.containers, isEmpty);
        await expectLater(
          food.add(const FoodDetails(name: 'Blocked while pending'), 1),
          throwsFormatException,
        );
        final creation = FoodRecord(
          space: tasks.space,
          writer: creator,
          sequence: 1,
          clock: EventClock(BigInt.one),
          previousHash: eventGenesisHash(tasks.space, creator),
          operation: FoodOperation(
            id: '$creator:1',
            order: 1,
            action: FoodAction.add,
            targets: [wrongTarget ? differentId : id],
            details: const FoodDetails(name: 'Original'),
            createdAt: '2026-10-10T00:00:00Z',
          ),
        );
        await File(
          '${folder.location}/${foodLogName(creator)}',
        ).writeAsString('${creation.encode()}\n');
        if (wrongTarget) {
          await expectLater(food.refresh(), throwsA(isA<FoodHistoryFailure>()));
          expect(food.state.containers, isEmpty);
          expect(food.pendingReferences, 2);
        } else {
          await food.refresh();
          expect(food.pendingReferences, 0);
          expect(food.state.active.single.id, id);
          expect(food.state.active.single.details.name, 'Original');
          await food.add(const FoodDetails(name: 'Writes resume'), 1);
          expect(food.state.active, hasLength(2));
        }
      },
    );
  }
}
