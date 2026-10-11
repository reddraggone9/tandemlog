import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/food_undo_history.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';

const _space = '00000000-0000-4000-8000-000000000001';
const _writer = '00000000-0000-4000-8000-000000000010';
FoodRecord _receipt(int n) => FoodRecord(
  space: _space,
  writer: _writer,
  sequence: n,
  clock: EventClock(BigInt.from(n)),
  previousHash: n == 1 ? eventGenesisHash(_space, _writer) : '0' * 64,
  operation: FoodOperation(
    id: '$_writer:$n',
    order: n,
    action: FoodAction.add,
    targets: ['00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}'],
    details: const FoodDetails(name: 'Synthetic food'),
    createdAt: '2026-10-11T00:00:00Z',
  ),
);

void main() {
  test('inverse receipts cannot create a new action or Redo entry', () {
    final history = FoodUndoHistory()..setWorkspace('first');
    final original = _receipt(1);
    final inverse = FoodRecord(
      space: _space,
      writer: _writer,
      sequence: 2,
      clock: EventClock(BigInt.from(2)),
      previousHash: original.hash,
      operation: FoodOperation(
        id: '$_writer:2',
        order: 2,
        action: FoodAction.undo,
        targets: original.operation.targets,
        retracts: original.id,
      ),
      createdWith: {original.operation.targets.single: original.id},
    );
    history.record('adding', [original], confirmed: (_) => true);
    final entry = history.latest;
    expect(
      () => history.record('undoing', [inverse], confirmed: (_) => true),
      throwsStateError,
    );
    expect(history.latest, same(entry));
    expect(history.length, 1);
  });

  test(
    'Food bulk receipts form one immutable action and successive Undo uses the stack',
    () {
      final history = FoodUndoHistory()..setWorkspace('first');
      final first = _receipt(1), second = _receipt(2), third = _receipt(3);
      history.record('adding', [first, second], confirmed: (_) => true);
      final bulk = history.latest!;
      expect(bulk.records.map((r) => r.id), [first.id, second.id]);
      expect(bulk.label, 'adding 2 containers');
      expect(() => bulk.records.clear(), throwsUnsupportedError);
      history.record('editing', [third], confirmed: (_) => true);
      final edit = history.latest!;
      expect(edit.label, 'editing 1 container');
      history.complete(edit);
      expect(history.latest, same(bulk));
      history.complete(bulk);
      expect(history.latest, isNull);
    },
  );

  test(
    'unconfirmed saves and failed Undo leave prior history intact; acknowledgment is idempotent',
    () {
      final history = FoodUndoHistory()..setWorkspace('first');
      final first = _receipt(1), second = _receipt(2);
      history.record('adding', [first], confirmed: (_) => true);
      final entry = history.latest;
      expect(
        () => history.record('editing', [second], confirmed: (_) => false),
        throwsStateError,
      );
      expect(history.latest, same(entry));
      history.record('adding', [first], confirmed: (_) => true);
      history.record('editing', const [], confirmed: (_) => true);
      expect(history.length, 1);
      // Transport failure does not call complete; the exact original receipts
      // remain available for retry rather than a snapshot or replacement action.
      expect(history.latest!.records.single.encode(), first.encode());
    },
  );

  test(
    'same workspace preserves history; another workspace and explicit close clear it',
    () {
      final history = FoodUndoHistory()..setWorkspace('first');
      history.record('adding', [_receipt(1)], confirmed: (_) => true);
      final entry = history.latest;
      history.setWorkspace('first');
      expect(history.latest, same(entry));
      history.setWorkspace('second');
      expect(history.latest, isNull);
      expect(() => history.complete(entry!), throwsStateError);
      history.record('adding', [_receipt(2)], confirmed: (_) => true);
      history.clear();
      expect(history.latest, isNull);
      expect(
        () => history.record('adding', [_receipt(3)], confirmed: (_) => true),
        throwsStateError,
      );
    },
  );

  test('Food session retention matches the 50-action Tasks bound', () {
    final history = FoodUndoHistory()..setWorkspace('first');
    for (var i = 1; i <= 51; i++) {
      history.record('adding', [_receipt(i)], confirmed: (_) => true);
    }
    expect(history.length, FoodUndoHistory.capacity);
    for (var i = 51; i >= 2; i--) {
      expect(history.latest!.records.single.id, '$_writer:$i');
      history.complete(history.latest!);
    }
    expect(history.latest, isNull);
  });
}
