import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/writer_guard.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000010';
FoodRecord seed() => FoodRecord(
  space: space,
  writer: writer,
  sequence: 1,
  clock: EventClock(BigInt.one),
  previousHash: eventGenesisHash(space, writer),
  operation: FoodOperation(
    id: '$writer:1',
    order: 1,
    action: FoodAction.add,
    targets: ['00000000-0000-4000-8000-000000000002'],
    details: const FoodDetails(name: 'Rice'),
    createdAt: '2026-10-10T00:00:00Z',
  ),
);
void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('food-intents-');
    profile = await LocalProfileDatabase.open(root.path);
  });
  tearDown(() async {
    await profile.close();
    await root.delete(recursive: true);
  });
  test('reservation and exact bytes commit or roll back together', () async {
    final record = seed(),
        intents = ProfileFoodIntents(profile),
        guard = SqliteWriterGuard(profile);
    final bytes = Uint8List.fromList(utf8.encode(record.encode()));
    expect(
      () => profile.transaction(() {
        guard.prepareInTransaction(
          space,
          writer,
          0,
          eventGenesisHash(space, writer),
          [PreparedWriterRecord(1, record.hash)],
        );
        intents.stageInTransaction(record, bytes);
        throw StateError('fault before commit');
      }),
      throwsStateError,
    );
    expect(await guard.load(space, writer), isNull);
    expect(intents.pending(space, writer), isEmpty);
    profile.transaction(() {
      guard.prepareInTransaction(
        space,
        writer,
        0,
        eventGenesisHash(space, writer),
        [PreparedWriterRecord(1, record.hash)],
      );
      intents.stageInTransaction(record, bytes);
    });
    expect(intents.pending(space, writer).single, bytes);
    expect((await guard.load(space, writer))!.pending.single.hash, record.hash);
    await profile.close();
    profile = await LocalProfileDatabase.open(root.path);
    expect(ProfileFoodIntents(profile).pending(space, writer).single, bytes);
  });
  test(
    'receipt cannot be retired by different bytes or without transaction',
    () {
      final record = seed(),
          intents = ProfileFoodIntents(profile),
          bytes = Uint8List.fromList(utf8.encode(record.encode()));
      expect(() => intents.stageInTransaction(record, bytes), throwsStateError);
      profile.transaction(() => intents.stageInTransaction(record, bytes));
      expect(
        () => profile.transaction(
          () => intents.retireInTransaction(
            record,
            Uint8List.fromList(utf8.encode(' ${record.encode()}')),
          ),
        ),
        throwsFormatException,
      );
      expect(intents.pending(space, writer), hasLength(1));
      final other = FoodRecord(
        space: space,
        writer: writer,
        sequence: 1,
        clock: record.clock,
        previousHash: record.previousHash,
        operation: FoodOperation(
          id: record.id,
          order: 1,
          action: FoodAction.add,
          targets: record.operation.targets,
          details: const FoodDetails(name: 'Other'),
          createdAt: record.operation.createdAt,
        ),
      );
      expect(
        () => profile.transaction(
          () => intents.retireInTransaction(other, bytes),
        ),
        throwsFormatException,
      );
      expect(intents.pending(space, writer), hasLength(1));
      profile.transaction(() => intents.retireInTransaction(record, bytes));
      expect(intents.pending(space, writer), isEmpty);
    },
  );
}
