import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000010';
const container = '00000000-0000-4000-8000-000000000002';
FoodOperation seed() => FoodOperation(
  id: '$writer:1',
  order: 1,
  action: FoodAction.add,
  targets: [container],
  details: const FoodDetails(name: 'Rice', expiry: '2026-10-15'),
  createdAt: '2026-10-10T00:00:00Z',
  contents: const Contents.fraction(1, 1),
);
void main() {
  // Frozen independently with Python json/SHA256/UUID-v5, not the Dart codec.
  test('literal canonical food wire/hash and module writer fixture', () {
    const raw =
        r'{"clock":"1","createdWith":{},"hash":"6648ddb329d58e21703e9670df883866fae0865f2dfca6ffb07604d97cf97901","module":"food","operation":{"action":"add","contents":{"denominator":1,"numerator":1,"unit":null},"createdAt":"2026-10-10T00:00:00Z","details":{"brand":"","estimated":false,"expiry":"2026-10-15","location":"","name":"Rice","retention":"","size":""},"fields":[],"observedDeletes":[],"observedEdits":[],"targets":["00000000-0000-4000-8000-000000000002"]},"previousHash":"7be6c79ffd50fb16f6d6c38680415eafdd4c6633c0e86dbb79b4117018e713ca","seq":1,"space":"00000000-0000-4000-8000-000000000001","v":1,"writer":"00000000-0000-4000-8000-000000000010"}';
    final record = FoodRecord.decode(raw);
    expect(
      record.hash,
      '6648ddb329d58e21703e9670df883866fae0865f2dfca6ffb07604d97cf97901',
    );
    expect(record.operation.toJson(), seed().toJson());
    expect(record.encode(), raw);
    expect(foodWriter(writer), 'ef7de7ae-f895-59f0-9090-8480d065bcd4');
  });

  test('separate food hash domain and immutable envelope bindings', () {
    final record = FoodRecord(
      space: space,
      writer: writer,
      sequence: 1,
      clock: EventClock(BigInt.one),
      operation: seed(),
      previousHash: eventGenesisHash(space, writer),
    );
    final raw = record.encode();
    expect(FoodRecord.decode(raw).operation.toJson(), seed().toJson());
    expect(FoodRecord.decode(raw).hash, record.hash);
    expect(() => LogEvent.decode(raw), throwsA(isA<FormatFailure>()));
    final changed = jsonDecode(raw) as Map<String, dynamic>;
    changed['space'] = container;
    expect(() => FoodRecord.decode(jsonEncode(changed)), throwsFormatException);
    changed['space'] = space;
    changed['module'] = 'tasks';
    expect(() => FoodRecord.decode(jsonEncode(changed)), throwsFormatException);
  });
  test(
    'food DTO identity and order cannot disagree with verified envelope',
    () {
      final mismatch = FoodOperation(
        id: '$writer:2',
        order: 1,
        action: FoodAction.add,
        targets: [container],
        details: const FoodDetails(name: 'Rice'),
        createdAt: '2026-10-10T00:00:00Z',
      );
      expect(
        () => FoodRecord(
          space: space,
          writer: writer,
          sequence: 1,
          clock: EventClock(BigInt.one),
          operation: mismatch,
          previousHash: eventGenesisHash(space, writer),
        ),
        throwsFormatException,
      );
    },
  );
  test('noncreation records carry observed per-container creation basis', () {
    final op = FoodOperation(
      id: '$writer:2',
      order: 2,
      action: FoodAction.remove,
      targets: [container],
    );
    expect(
      () => FoodRecord(
        space: space,
        writer: writer,
        sequence: 2,
        clock: EventClock(BigInt.two),
        operation: op,
        previousHash: 'a' * 64,
      ),
      throwsFormatException,
    );
    final record = FoodRecord(
      space: space,
      writer: writer,
      sequence: 2,
      clock: EventClock(BigInt.two),
      operation: op,
      createdWith: {container: '$writer:1'},
      previousHash: 'a' * 64,
    );
    expect(FoodRecord.decode(record.encode()).createdWith, {
      container: '$writer:1',
    });
  });
  test('unknown/noncanonical/oversized records are rejected', () {
    final record = FoodRecord(
      space: space,
      writer: writer,
      sequence: 1,
      clock: EventClock(BigInt.one),
      operation: seed(),
      previousHash: eventGenesisHash(space, writer),
    );
    expect(
      () => FoodRecord.decode(' ${record.encode()}'),
      throwsFormatException,
    );
    final raw = jsonDecode(record.encode()) as Map<String, dynamic>;
    raw['quantity'] = 1;
    expect(() => FoodRecord.decode(jsonEncode(raw)), throwsFormatException);
    expect(
      () => FoodRecord.decode(' ' * (256 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('exact signed64 clock roundtrip and bounds', () {
    final clock = EventClock(EventClock.maximum);
    final op = FoodOperation(
      id: '$writer:1',
      order: clock.value.toInt(),
      action: FoodAction.add,
      targets: [container],
      details: const FoodDetails(name: 'Rice'),
      createdAt: '2026-10-10T00:00:00Z',
    );
    final record = FoodRecord(
      space: space,
      writer: writer,
      sequence: 1,
      clock: clock,
      operation: op,
      previousHash: eventGenesisHash(space, writer),
    );
    expect(FoodRecord.decode(record.encode()).clock, clock);
    expect(
      () => FoodRecord(
        space: space,
        writer: writer,
        sequence: 1,
        clock: EventClock(EventClock.maximum + BigInt.one),
        operation: op,
        previousHash: eventGenesisHash(space, writer),
      ),
      throwsFormatException,
    );
  });
}
