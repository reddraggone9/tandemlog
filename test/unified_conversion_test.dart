import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
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

Map<String, List<int>> sources() {
  final person = LogEvent.decode(
    LogEvent(
      space,
      owner,
      1,
      EventClock(BigInt.from(1000000000)),
      peer,
      'user.created',
      {'name': 'Synthetic'},
    ).encode(),
  );
  final task = LogEvent.decode(
    LogEvent(
      space,
      owner,
      2,
      EventClock(BigInt.from(2000000000)),
      container,
      'task.created',
      {
        'title': 'Synthetic task',
        'description': 'Preserved notes',
        'assignee': peer,
      },
    ).encode(previousHash: person.hash),
  );
  return {
    '$owner.applog': utf8.encode('${person.encode()}\n${task.encode()}\n'),
    foodLogName(foodWriter(owner)): utf8.encode(
      '${foodHistory().map((r) => r.encode()).join('\n')}\n',
    ),
  };
}

class FixtureConversion {
  FixtureConversion(this.manifest, this.files, this.originalEffects);
  final UnifiedManifest manifest;
  final Map<String, List<int>> files;
  final List<UnifiedEffect> originalEffects;
}

/// Test-only bootstrap data from CURRENT operations. It cannot decode old wire
/// envelopes. Actual historical normalization lives outside the repository.
class FixturePlan {
  FixturePlan._(this.space, this.owners, this.effects, this.sourceDigest);
  final String space, sourceDigest;
  final Set<String> owners;
  final Map<String, List<UnifiedEffect>> effects;
  factory FixturePlan.inspect({
    required String space,
    required Set<String> owners,
    Set<String> participants = const {},
    required Map<String, List<int>> sources,
    required bool hasUnresolvedPreparedWrites,
  }) {
    if (hasUnresolvedPreparedWrites) {
      throw FormatFailure('Resolve pending writes.');
    }
    final effects = {for (final o in owners) o: <UnifiedEffect>[]};
    for (final e in sources.entries) {
      final task = e.key.endsWith('.applog');
      final matches = owners
          .where(
            (o) => e.key == (task ? '$o.applog' : foodLogName(foodWriter(o))),
          )
          .toList();
      if (matches.length != 1 || e.value.isNotEmpty && e.value.last != 10) {
        throw FormatFailure('Invalid current fixture source.');
      }
      final author = matches.single;
      final lines = utf8.decode(e.value).split('\n');
      for (final raw in lines.take(lines.length - 1)) {
        if (task) {
          final event = LogEvent.decode(raw);
          effects[author]!.add(
            UnifiedEffect(
              'history.task',
              LogEvent.decode(
                LogEvent(
                  event.space,
                  event.writer,
                  event.sequence,
                  event.clock,
                  event.entity,
                  event.type,
                  event.data,
                  previousHash: event.previousHash,
                  hash: event.hash,
                  attributedWriter: author,
                ).encode(),
              ).encode(),
            ),
          );
        } else {
          final event = FoodRecord.decode(raw);
          effects[author]!.add(
            UnifiedEffect(
              'history.food',
              FoodRecord(
                space: event.space,
                writer: event.writer,
                sequence: event.sequence,
                clock: event.clock,
                operation: event.operation,
                previousHash: event.previousHash,
                createdWith: event.createdWith,
                attributedWriter: author,
                retainedReferenceHash: event.hash,
              ).encode(),
            ),
          );
        }
      }
    }
    final digest = bytesDigest(
      utf8.encode(
        canonicalDataJson({
          'space': space,
          'sources': {
            for (final e in sources.entries) e.key: bytesDigest(e.value),
          },
        }),
      ),
    );
    return FixturePlan._(
      space,
      Set.unmodifiable(owners),
      Map.unmodifiable(
        effects.map((k, v) => MapEntry(k, List<UnifiedEffect>.unmodifiable(v))),
      ),
      digest,
    );
  }
  FixtureConversion convert(Object? _) => prepareConversion();
  FixtureConversion prepareConversion() {
    final epoch = const Uuid().v5(
      space,
      'current-test-bootstrap:$sourceDigest',
    );
    final files = <String, List<int>>{},
        heads = <String, Map<String, dynamic>>{},
        authors = <String, String>{};
    final originals = <UnifiedEffect>[];
    for (final owner in owners.toList()..sort()) {
      final ordered = effects[owner]!.toList()
        ..sort((a, b) {
          final c = a.clock.compareTo(b.clock);
          if (c != 0) return c;
          final w = a.writer.compareTo(b.writer);
          return w != 0 ? w : a.sequence.compareTo(b.sequence);
        });
      var seq = 0, head = unifiedGenesis(space, epoch, owner);
      EventClock? clock;
      final out = StringBuffer();
      for (final effect in ordered) {
        authors[effect.writer] = owner;
        clock = EventClock.next(effect.clock.value, clock);
        final r = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: owner,
          sequence: ++seq,
          clock: clock,
          previousHash: head,
          effect: effect,
        );
        out.writeln(r.encode());
        head = r.hash;
        originals.add(effect);
      }
      final bytes = Uint8List.fromList(
        utf8.encode(out.toString()),
      ).asUnmodifiableView();
      files[unifiedLogName(owner)] = bytes;
      heads[owner] = {'count': seq, 'head': head, 'digest': bytesDigest(bytes)};
    }
    return FixtureConversion(
      UnifiedManifest(space, epoch, sourceDigest, heads, authors),
      Map.unmodifiable(files),
      List.unmodifiable(originals),
    );
  }
}

FixturePlan plan({Map<String, List<int>>? input, bool pending = false}) =>
    FixturePlan.inspect(
      space: space,
      owners: {owner, peer},
      sources: input ?? sources(),
      hasUnresolvedPreparedWrites: pending,
    );
List<Object> ack(FixturePlan _) => const [];
List<UnifiedRecord> records(FixtureConversion c) => c.files.values
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
  test(
    'current bootstrap is deterministic, sealed and contains only normalized operations',
    () {
      final p = plan(), a = p.prepareConversion(), b = p.prepareConversion();
      expect(a.manifest.encode(), b.manifest.encode());
      expect(a.files, b.files);
      expect(records(a), hasLength(5));
      expect(records(a).every((r) => r.effect.historical), isTrue);
      expect(() => p.effects[owner]!.clear(), throwsUnsupportedError);
      expect(() => a.files.clear(), throwsUnsupportedError);
      expect(
        UnifiedManifest.decode(a.manifest.encode()).digest,
        a.manifest.digest,
      );
    },
  );
  test(
    'retired envelope input is rejected by the current fixture reader too',
    () {
      expect(
        () => plan(
          input: {
            '$owner.applog': File(
              'test/fixtures/event_chain_v3.jsonl',
            ).readAsBytesSync(),
          },
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test('bootstrap cannot be created from unresolved prepared operations', () {
    expect(() => plan(pending: true), throwsA(isA<FormatFailure>()));
  });
}
