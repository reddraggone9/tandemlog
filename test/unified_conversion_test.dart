import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';

const space = '11111111-1111-4111-8111-111111111111';
const owner = '22222222-2222-4222-8222-222222222222';
const peer = '33333333-3333-4333-8333-333333333333';
const container = '44444444-4444-4444-8444-444444444444';

List<FoodRecord> foodHistory() {
  final writer = foodWriter(owner);
  final add = FoodRecord(
    space: space,
    writer: writer,
    sequence: 1,
    clock: EventClock(BigInt.one),
    previousHash: eventGenesisHash(space, writer),
    operation: FoodOperation(
      id: '$writer:1',
      order: 1,
      action: FoodAction.add,
      targets: [container],
      details: const FoodDetails(name: 'Rice'),
      createdAt: '2026-10-17T00:00:00Z',
    ),
  );
  final edit = FoodRecord(
    space: space,
    writer: writer,
    sequence: 2,
    clock: EventClock(BigInt.from(10)),
    previousHash: add.hash,
    createdWith: {container: add.id},
    operation: FoodOperation(
      id: '$writer:2',
      order: 10,
      action: FoodAction.edit,
      targets: [container],
      details: const FoodDetails(name: 'Brown rice'),
      fields: ['name'],
    ),
  );
  final undo = FoodRecord(
    space: space,
    writer: writer,
    sequence: 3,
    clock: EventClock(BigInt.from(11)),
    previousHash: edit.hash,
    createdWith: {container: add.id},
    operation: FoodOperation(
      id: '$writer:3',
      order: 11,
      action: FoodAction.undo,
      targets: [container],
      retracts: edit.id,
    ),
  );
  return [add, edit, undo];
}

Map<String, List<int>> sources() => {
  '$owner.jsonl': File('test/fixtures/event_chain_v3.jsonl').readAsBytesSync(),
  foodLogName(foodWriter(owner)): utf8.encode(
    '${foodHistory().map((r) => r.encode()).join('\n')}\n',
  ),
};
UnifiedCutoverPlan plan({
  Map<String, List<int>>? input,
  bool pending = false,
}) => UnifiedCutoverPlan.inspect(
  space: space,
  owners: {owner, peer},
  participants: {owner, peer},
  sources: input ?? sources(),
  hasUnresolvedPreparedWrites: pending,
);
List<CutoverAcknowledgement> ack(UnifiedCutoverPlan p) => [owner, peer]
    .map(
      (o) => CutoverAcknowledgement(
        o,
        p.sourceDigest,
        quiesced: true,
        pendingResolved: true,
      ),
    )
    .toList();
List<UnifiedRecord> records(UnifiedConversion c) => c.files.values
    .expand(
      (bytes) => utf8
          .decode(bytes)
          .split('\n')
          .where((s) => s.isNotEmpty)
          .map(UnifiedRecord.decode),
    )
    .toList();
List<String> foodState(Iterable<FoodOperation> ops) => projectFood(
  ops,
).containers.map((c) => canonicalDataJson(c.toJson())).toList();

void main() {
  test('sealed conversion collections cannot be changed after inspection', () {
    final p = plan();
    expect(() => p.effects[owner]!.clear(), throwsUnsupportedError);
    expect(() => p.effects.clear(), throwsUnsupportedError);
  });

  test(
    'complete conversion is repeatable and preserves frozen semantic bytes',
    () {
      final p = plan(), a = p.convert(ack(p)), b = p.convert(ack(p));
      expect(a.manifest.encode(), b.manifest.encode());
      expect(a.files, b.files);
      final decoded = records(a);
      expect(decoded, hasLength(5));
      expect(decoded.map((r) => r.sequence), [1, 2, 3, 4, 5]);
      expect(decoded.map((r) => r.recordId).toSet(), hasLength(5));
      expect(decoded.map((r) => r.effect.key).toSet(), hasLength(5));
      expect(
        decoded.map((r) => r.effect.raw).toSet(),
        a.originalEffects.map((e) => e.raw).toSet(),
      );
      expect(a.files.keys.toSet(), {
        unifiedLogName(owner),
        unifiedLogName(peer),
      });
      expect(
        a.files.keys.any((n) => n.endsWith('.foodlog') || n.endsWith('.jsonl')),
        isFalse,
      );
      var head = unifiedGenesis(space, a.manifest.epoch, owner);
      for (final r in decoded) {
        expect(r.previousHash, head);
        head = r.hash;
        expect(r.effect.historical, isTrue);
      }
      expect(
        UnifiedManifest.decode(a.manifest.encode()).digest,
        a.manifest.digest,
      );
      final originalTasks = a.originalEffects
          .where((e) => e.task != null)
          .map((e) => e.raw)
          .toList();
      expect(
        originalTasks,
        File('test/fixtures/event_chain_v3.jsonl').readAsLinesSync(),
      );
    },
  );

  test(
    'unchanged peer conflict and Undo results survive interleave and duplicates',
    () {
      final p = plan(), c = p.convert(ack(p));
      final old = foodHistory().map((r) => r.operation).toList();
      final migrated = records(c)
          .where((r) => r.effect.food != null)
          .map((r) => r.effect.food!.operation)
          .toList();
      final writer = foodWriter(peer);
      for (final clock in [2, 10, 12]) {
        final other = FoodOperation(
          id: '$writer:1',
          order: clock,
          action: FoodAction.edit,
          targets: [container],
          details: const FoodDetails(name: 'Peer name'),
          fields: ['name'],
        );
        expect(foodState([...migrated, other]), foodState([...old, other]));
        expect(
          foodState([other, ...migrated.reversed, ...migrated]),
          foodState([...old, other]),
        );
      }
      expect(foodState(migrated), foodState(old));
    },
  );

  test(
    'missing, stale and non-quiescent participant reports block conversion',
    () {
      final p = plan();
      expect(() => p.convert(ack(p).take(1)), throwsA(isA<FormatFailure>()));
      expect(
        () => p.convert([
          ...ack(p).take(1),
          CutoverAcknowledgement(
            peer,
            '0' * 64,
            quiesced: true,
            pendingResolved: true,
          ),
        ]),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        () => p.convert([
          CutoverAcknowledgement(
            owner,
            p.sourceDigest,
            quiesced: false,
            pendingResolved: true,
          ),
          ack(p).last,
        ]),
        throwsA(isA<FormatFailure>()),
      );
      expect(() => plan(pending: true), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'late source changes require a new snapshot and fresh acknowledgements',
    () {
      final first = plan(), changed = sources();
      changed['$peer.jsonl'] = utf8.encode(
        '${LogEvent(space, peer, 1, EventClock(BigInt.from(20)), container, 'user.created', {'name': 'Peer'}).encode()}\n',
      );
      final newer = plan(input: changed);
      expect(newer.sourceDigest, isNot(first.sourceDigest));
      expect(() => newer.convert(ack(first)), throwsA(isA<FormatFailure>()));
      expect(
        newer.convert(ack(newer)).manifest.epoch,
        isNot(first.convert(ack(first)).manifest.epoch),
      );
    },
  );

  for (final mutation in ['partial', 'conflict', 'identity', 'hash']) {
    test('reject malformed or unowned source $mutation before conversion', () {
      final input = sources();
      if (mutation == 'partial') {
        input['$owner.jsonl'] = input['$owner.jsonl']!.sublist(0, 20);
      }
      if (mutation == 'conflict') {
        input['$owner.sync-conflict-x.jsonl'] = input['$owner.jsonl']!;
      }
      if (mutation == 'identity') {
        input['$peer.jsonl'] = input.remove('$owner.jsonl')!;
      }
      if (mutation == 'hash') {
        input['$owner.jsonl'] = utf8.encode(
          utf8.decode(input['$owner.jsonl']!).replaceFirst('Zoë', 'Zoe'),
        );
      }
      expect(() => plan(input: input), throwsA(isA<FormatFailure>()));
    });
  }

  test('unknown app kinds and unknown closed fields demand an update', () {
    final p = plan(), r = records(p.convert(ack(p))).first;
    final j = jsonDecode(r.encode()) as Map<String, dynamic>;
    (j['effect'] as Map)['kind'] = 'future.unknown';
    expect(
      () => UnifiedRecord.decode(canonicalDataJson(j)),
      throwsA(isA<FormatFailure>()),
    );
    j['extra'] = true;
    expect(
      () => UnifiedRecord.decode(canonicalDataJson(j)),
      throwsA(isA<FormatFailure>()),
    );
  });

  test(
    'outer record identity cannot substitute for original semantic identity',
    () {
      final p = plan(), all = records(p.convert(ack(p)));
      expect(all.any((r) => r.effect.sequence != r.sequence), isTrue);
      for (final r in all.where((r) => r.effect.food != null)) {
        expect(r.effect.writer, foodWriter(owner));
        expect(r.writer, owner);
        expect(r.effect.id, isNot(r.recordId));
      }
    },
  );
}
