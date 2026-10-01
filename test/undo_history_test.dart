import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/undo_history.dart';
import 'package:tandemlog/domain/undo.dart';

void main() {
  test(
    'failed receipt ID reuse confirms only exact successful retry bytes',
    () {
      final history = SessionUndoHistory(), group = Object();
      history.record('editing', [
        const OperationReceipt('w:1', 'failed', 'a'),
      ], group: group);
      history.record('editing', [
        const OperationReceipt('w:1', 'saved', 'a'),
      ], group: group);
      expect(history.latest, isNull);
      history.reconcile(
        (rs) => {
          for (final r in rs)
            if (r.raw == 'saved') r.id,
        },
      );
      expect(history.latest!.operations, {'w:1'});
      expect(history.latest!.pending, isEmpty);
      expect(history.latest!.label, 'editing 1 task');
    },
  );
  test(
    'grouped partial retry and independent actions step through bounded history',
    () {
      final history = SessionUndoHistory(), group = Object();
      history.record('editing', [
        const OperationReceipt('w:1', 'one', 'a'),
        const OperationReceipt('w:2', 'two', 'b'),
      ], group: group);
      history.reconcile(
        (rs) => {
          for (final r in rs)
            if (r.raw == 'one') r.id,
        },
      );
      final entry = history.latest!;
      history.record('editing', [
        const OperationReceipt('w:2', 'two', 'b'),
      ], group: group);
      history.reconcile((rs) => {for (final r in rs) r.id});
      expect(identical(entry, history.latest), isTrue);
      expect(entry.label, 'editing 2 tasks');
      history.record('deleting', [const OperationReceipt('w:3', 'three', 'c')]);
      history.reconcile((rs) => {for (final r in rs) r.id});
      history.acknowledge(history.latest!, ['w:3']);
      expect(history.latest, entry);
      history.acknowledge(entry, ['w:1']);
      expect(entry.label, 'editing 1 task');
      history.acknowledge(entry, ['w:2']);
      expect(history.latest, isNull);
      for (var i = 0; i < 55; i++) {
        history.record('editing', [OperationReceipt('w:$i', '$i', 'a')]);
        history.reconcile((rs) => {for (final r in rs) r.id});
      }
      var retained = 0;
      while (history.latest != null) {
        final e = history.latest!;
        history.acknowledge(e, e.operations.toList());
        retained++;
      }
      expect(retained, SessionUndoHistory.capacity);
      history.record('editing', [const OperationReceipt('w:60', 'sixty', 'a')]);
      history.clear();
      history.reconcile((rs) => {for (final r in rs) r.id});
      expect(history.latest, isNull);
    },
  );
}
