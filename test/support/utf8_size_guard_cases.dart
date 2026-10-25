import 'dart:io';

import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/unified_record.dart';

const _space = '11111111-1111-4111-8111-111111111111';
const _epoch = '33333333-3333-4333-8333-333333333333';
const _writer = '22222222-2222-4222-8222-222222222222';
const _container = '44444444-4444-4444-8444-444444444444';

String _person() => File(
  'test/fixtures/current-operation-v1/persons.operations',
).readAsLinesSync().first;

FoodRecord _food({String name = 'Café € 🙂', String space = _space}) =>
    FoodRecord(
      space: space,
      writer: _writer,
      sequence: 1,
      clock: EventClock(BigInt.one),
      previousHash: eventGenesisHash(_space, _writer),
      operation: FoodOperation(
        id: '$_writer:1',
        order: 1,
        action: FoodAction.add,
        targets: [_container],
        details: FoodDetails(name: name),
        createdAt: '2026-10-10T00:00:00Z',
      ),
    );

UnifiedRecord namedAction() {
  final head = unifiedGenesis(_space, _epoch, _writer);
  return UnifiedRecord(
    space: _space,
    epoch: _epoch,
    writer: _writer,
    sequence: 1,
    clock: EventClock(BigInt.one),
    previousHash: head,
    observed: {_writer: UnifiedFrontier(0, head)},
    effect: UnifiedEffect.named('Café € 🙂'),
  );
}

Map<String, Object?> _outcome(Object? Function() work) {
  try {
    work();
    return {'result': 'accepted'};
  } on FormatFailure catch (error) {
    return {'type': 'FormatFailure', 'message': error.message};
  } on FormatException catch (error) {
    return {'type': 'FormatException', 'message': error.message};
  }
}

/// Snapshot against unmodified e23 before integrating any new guard.
Map<String, Object?> utf8CallerOutcomes() {
  final surrogate = String.fromCharCode(0xd800);
  final malformedPerson = _person().replaceFirst('Example', surrogate);
  return {
    'current.asciiOversize': _outcome(
      () => CurrentOperation.decode(' ' * (1024 * 1024 + 1), module: 'tasks'),
    ),
    'current.multibyteOversize': _outcome(
      () => CurrentOperation.decode(
        '€' * (1024 * 1024 ~/ 3 + 1),
        module: 'tasks',
      ),
    ),
    'current.invalidScalar': _outcome(
      () => CurrentOperation.decode(malformedPerson, module: 'tasks'),
    ),
    'current.formatBeforeHash': _outcome(
      () => CurrentOperation.decode('{}', module: 'tasks'),
    ),
    'event.asciiOversize': _outcome(
      () => LogEvent.decode(' ' * (1024 * 1024 + 1)),
    ),
    'event.multibyteOversize': _outcome(
      () => LogEvent.decode('€' * (1024 * 1024 ~/ 3 + 1)),
    ),
    'event.invalidScalar': _outcome(() => LogEvent.decode(malformedPerson)),
    'event.formatBeforeHash': _outcome(() => LogEvent.decode('{}')),
    'food.invalidScalar': _outcome(() => _food(name: surrogate)),
    'food.identityBeforeScalar': _outcome(
      () => _food(name: surrogate, space: 'not-an-id'),
    ),
    'food.textBeforeHash': _outcome(() => _food(name: '€' * 501)),
    'action.asciiOversize': _outcome(
      () => UnifiedRecord.decode(' ' * (maximumUnifiedRecordBytes + 1)),
    ),
    'action.multibyteOversize': _outcome(
      () => UnifiedRecord.decode('€' * (maximumUnifiedRecordBytes ~/ 3 + 1)),
    ),
    'action.formatBeforeHash': _outcome(() => UnifiedRecord.decode('{}')),
    'action.invalidScalar': _outcome(
      () => UnifiedRecord.decode(
        namedAction().encode().replaceFirst('Café', surrogate),
      ),
    ),
  };
}

Map<String, Object?> utf8FrozenRecordValues() => {
  'constructedFood': _food().encode(),
  'constructedAction': namedAction().encode(),
  'persons': [
    for (final raw in File(
      'test/fixtures/current-operation-v1/persons.operations',
    ).readAsLinesSync())
      LogEvent.decode(raw).encode(),
  ],
  'food': [
    for (final raw in File(
      'test/fixtures/current-operation-v1/food.operations',
    ).readAsLinesSync())
      FoodRecord.decode(raw).encode(),
  ],
};
