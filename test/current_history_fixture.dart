import 'dart:convert';
import 'dart:typed_data';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/food/food_record.dart';

Uint8List peerBytesFor(TaskStore owner, LogEvent event) {
  final epoch = owner.unified!.manifest.epoch;
  final genesis = unifiedGenesis(event.space, epoch, event.writer);
  final header = UnifiedRecord(
    space: event.space,
    epoch: epoch,
    writer: event.writer,
    sequence: 1,
    clock: EventClock(BigInt.zero),
    previousHash: genesis,
    effect: UnifiedEffect.joined(),
    observed: {event.writer: UnifiedFrontier(0, genesis)},
  );
  final record = UnifiedRecord(
    space: event.space,
    epoch: epoch,
    writer: event.writer,
    sequence: 2,
    clock: event.clock,
    previousHash: header.hash,
    effect: UnifiedEffect('task', event.encode(previousHash: header.hash)),
    observed: {event.writer: UnifiedFrontier(1, header.hash)},
  );
  return Uint8List.fromList(
    utf8.encode('${header.encode()}\n${record.encode()}\n'),
  );
}

// A peer publishes complete current actions. Typed logical IDs stay stable while
// each physical action includes its own canonical predecessor and installation header.
Uint8List peerFoodBytesFor(TaskStore owner, List<FoodRecord> records) {
  final writer = records.first.writer,
      space = owner.space,
      epoch = owner.unified!.manifest.epoch;
  final genesis = unifiedGenesis(space, epoch, writer);
  final header = UnifiedRecord(
    space: space,
    epoch: epoch,
    writer: writer,
    sequence: 1,
    clock: EventClock(BigInt.zero),
    previousHash: genesis,
    effect: UnifiedEffect.joined(),
    observed: {writer: UnifiedFrontier(0, genesis)},
  );
  final actions = <UnifiedRecord>[header];
  for (final original in records) {
    final previous = actions.last;
    final food = FoodRecord(
      unified: true,
      space: space,
      writer: writer,
      sequence: original.sequence,
      clock: original.clock,
      previousHash: previous.hash,
      createdWith: original.createdWith,
      operation: original.operation,
    );
    actions.add(
      UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: writer,
        sequence: previous.sequence + 1,
        clock: food.clock,
        previousHash: previous.hash,
        effect: UnifiedEffect('food', food.encode()),
        observed: {writer: UnifiedFrontier(previous.sequence, previous.hash)},
      ),
    );
  }
  return Uint8List.fromList(
    utf8.encode(actions.map((r) => '${r.encode()}\n').join()),
  );
}
