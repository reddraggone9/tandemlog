import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_admission.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000010';
const a = '00000000-0000-4000-8000-000000000002';
const b = '00000000-0000-4000-8000-000000000003';
const c = '00000000-0000-4000-8000-000000000004';
const d = '00000000-0000-4000-8000-000000000005';

FoodRecord record(
  int seq,
  FoodAction action,
  List<String> targets, {
  FoodDetails? details,
  Contents? contents,
  List<String> fields = const [],
  List<String> deletes = const [],
  List<String> edits = const [],
  int? retracts,
  int? time,
  Map<String, String>? births,
}) => FoodRecord(
  unified: true,
  space: space,
  writer: writer,
  sequence: seq,
  clock: EventClock(BigInt.from(time ?? seq)),
  previousHash: 'a' * 64,
  createdWith: action == FoodAction.add
      ? {}
      : births ?? {for (final target in targets) target: '$writer:1'},
  operation: FoodOperation(
    id: '$writer:$seq',
    order: time ?? seq,
    action: action,
    targets: targets,
    details: details,
    contents: contents,
    fields: fields,
    createdAt: action == FoodAction.add ? '2026-10-22T00:00:00Z' : null,
    observedDeletes: deletes,
    observedEdits: edits,
    retracts: retracts == null ? null : '$writer:$retracts',
  ),
);

List<Map<String, dynamic>> state(FoodAdmission value) =>
    value.state.containers.map((c) => c.toJson()).toList();

void main() {
  test(
    'ready point confirmation preserves reference hashes and pending fallback',
    () {
      const old = '00000000-0000-4000-8000-000000000011';
      final imported = FoodRecord(
        unified: true,
        space: space,
        writer: old,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: 'a' * 64,
        retainedReferenceHash: 'b' * 64,
        operation: FoodOperation(
          id: '$old:1',
          order: 1,
          action: FoodAction.add,
          targets: [a],
          details: const FoodDetails(name: 'Imported'),
          createdAt: '2026-10-22T00:00:00Z',
        ),
      );
      final owners = {old: writer};
      final admitted = admitFoodRecords([imported], legacyOwners: owners);
      expect(imported.hash, isNot(imported.integrityHash));
      expect(
        admitted.confirmsReadyRecord(FoodRecord.decode(imported.encode())),
        isTrue,
      );
      final wrongHash = FoodRecord(
        unified: true,
        space: space,
        writer: old,
        sequence: 1,
        clock: imported.clock,
        previousHash: imported.previousHash,
        operation: imported.operation,
      );
      expect(wrongHash.hash, imported.integrityHash);
      expect(admitted.confirmsReadyRecord(wrongHash), isFalse);
      expect(
        admitted.confirmsReadyRecord(record(8, FoodAction.remove, [a])),
        isFalse,
      );
      expect(admitted.hasReadyRetraction(imported.id), isFalse);
      final undo = FoodRecord(
        unified: true,
        space: space,
        writer: writer,
        sequence: 2,
        clock: EventClock(BigInt.from(3)),
        previousHash: 'a' * 64,
        createdWith: {a: imported.id},
        operation: FoodOperation(
          id: '$writer:2',
          order: 3,
          action: FoodAction.undo,
          targets: [a],
          retracts: imported.id,
          undoOwner: writer,
        ),
      );
      final next = appendReadyFoodRecords(admitted, [
        undo,
      ], legacyOwners: owners)!;
      expect(next.hasReadyRetraction(imported.id), isTrue);
      expect(next.confirmsReadyRecord(undo), isTrue);
      expect(admitted.hasReadyRetraction(imported.id), isFalse);
      expect(
        state(next),
        state(admitFoodRecords([imported, undo], legacyOwners: owners)),
      );

      final seed = record(1, FoodAction.add, [
        a,
      ], details: const FoodDetails(name: 'Seed'));
      final missingUndo = record(3, FoodAction.undo, [a], retracts: 2);
      final pending = admitFoodRecords([seed, missingUndo]);
      expect(pending.readyIds, {seed.id});
      expect(pending.confirmsReadyRecord(seed), isNull);
      expect(pending.confirmsReadyRecord(missingUndo), isNull);
      expect(pending.hasReadyRetraction('$writer:2'), isNull);
      final removal = record(2, FoodAction.remove, [a]);
      final complete = admitFoodRecords([seed, removal, missingUndo]);
      expect(complete.hasReadyRetraction(removal.id), isTrue);
      expect(complete.confirmsReadyRecord(missingUndo), isTrue);
      expect(complete.confirmsReadyRecord(seed), isTrue);
    },
  );

  test(
    'legacy owner Undo preserves full bulk target proof and rejects remapping or Undo of Undo',
    () {
      const old = '00000000-0000-4000-8000-000000000011';
      const other = '00000000-0000-4000-8000-000000000012';
      final seed = FoodRecord(
        unified: true,
        space: space,
        writer: old,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: 'a' * 64,
        operation: FoodOperation(
          id: '$old:1',
          order: 1,
          action: FoodAction.add,
          targets: [a, b],
          details: const FoodDetails(name: 'Imported'),
          createdAt: '2026-10-22T00:00:00Z',
        ),
      );
      final undo = FoodRecord(
        unified: true,
        space: space,
        writer: writer,
        sequence: 2,
        clock: EventClock(BigInt.from(3)),
        previousHash: 'a' * 64,
        createdWith: {a: '$old:1', b: '$old:1'},
        operation: FoodOperation(
          id: '$writer:2',
          order: 3,
          action: FoodAction.undo,
          targets: [a, b],
          retracts: '$old:1',
          undoOwner: writer,
        ),
      );
      final owners = {old: writer};
      final base = admitFoodRecords([seed], legacyOwners: owners);
      final next = appendReadyFoodRecords(base, [undo], legacyOwners: owners);
      expect(next, isNotNull);
      expect(
        state(next!),
        state(admitFoodRecords([seed, undo], legacyOwners: owners)),
      );
      expect(next.state.containers, isEmpty);
      expect(next.births.keys.toSet(), {a, b});
      final wrong = {old: other};
      expect(
        () => appendReadyFoodRecords(
          admitFoodRecords([seed], legacyOwners: wrong),
          [undo],
          legacyOwners: wrong,
        ),
        throwsFormatException,
      );
      final undoAgain = FoodRecord(
        unified: true,
        space: space,
        writer: writer,
        sequence: 3,
        clock: EventClock(BigInt.from(4)),
        previousHash: 'a' * 64,
        createdWith: {a: '$old:1', b: '$old:1'},
        operation: FoodOperation(
          id: '$writer:3',
          order: 4,
          action: FoodAction.undo,
          targets: [a, b],
          retracts: '$writer:2',
        ),
      );
      expect(
        () => appendReadyFoodRecords(next, [undoAgain], legacyOwners: owners),
        throwsFormatException,
      );
    },
  );

  test(
    'asymmetric bulk references reject; old-clock fast fallback retains full noncausal rejection',
    () {
      final seed = record(1, FoodAction.add, [
        a,
        b,
      ], details: const FoodDetails(name: 'Beans'));
      final removed = record(2, FoodAction.remove, [a]);
      final base = admitFoodRecords([seed, removed]);
      final asymmetric = record(
        3,
        FoodAction.restore,
        [a, b],
        deletes: ['$writer:2'],
      );
      expect(
        () => appendReadyFoodRecords(base, [asymmetric]),
        throwsFormatException,
      );
      expect(
        () => admitFoodRecords([seed, removed, asymmetric]),
        throwsFormatException,
      );
      final later = record(4, FoodAction.remove, [a]);
      final noncausal = record(
        5,
        FoodAction.restore,
        [a],
        time: 3,
        deletes: ['$writer:4'],
      );
      final advanced = admitFoodRecords([seed, later]);
      expect(appendReadyFoodRecords(advanced, [noncausal]), isNull);
      expect(
        () => admitFoodRecords([seed, later, noncausal]),
        throwsFormatException,
      );
    },
  );

  test(
    'incremental admission is bound to original ownership mapping and limits',
    () {
      final seed = record(1, FoodAction.add, [
        a,
        b,
      ], details: const FoodDetails(name: 'Beans'));
      final next = record(2, FoodAction.remove, [a]);
      final base = admitFoodRecords(
        [seed],
        maximumContainers: 2,
        legacyOwners: {writer: writer},
      );
      expect(
        appendReadyFoodRecords(base, [next], maximumContainers: 2),
        isNull,
      );
      expect(
        appendReadyFoodRecords(base, [next], legacyOwners: {writer: writer}),
        isNull,
      );
      final actual = appendReadyFoodRecords(
        base,
        [next],
        maximumContainers: 2,
        legacyOwners: {writer: writer},
      );
      expect(actual, isNotNull);
      expect(
        state(actual!),
        state(
          admitFoodRecords(
            [seed, next],
            maximumContainers: 2,
            legacyOwners: {writer: writer},
          ),
        ),
      );
    },
  );

  test(
    'incremental full-target bulk actions, selective Undo and hidden births equal every full replay',
    () {
      final history = [
        record(1, FoodAction.add, [
          a,
          b,
        ], details: const FoodDetails(name: 'Beans')),
        record(2, FoodAction.add, [
          c,
        ], details: const FoodDetails(name: 'Unchanged')),
        record(
          3,
          FoodAction.edit,
          [a, b],
          details: const FoodDetails(name: 'Beans', brand: 'New'),
          fields: ['brand'],
        ),
        record(4, FoodAction.remove, [a, b]),
        record(5, FoodAction.restore, [a, b], deletes: ['$writer:4']),
        record(6, FoodAction.undo, [a, b], retracts: 5),
        record(7, FoodAction.undo, [a, b], retracts: 4),
        record(8, FoodAction.edit, [
          a,
          b,
        ], contents: const Contents.fraction(1, 2)),
        record(
          9,
          FoodAction.edit,
          [a],
          contents: const Contents.fraction(1, 4),
          edits: ['$writer:8'],
        ),
        record(10, FoodAction.undo, [a], retracts: 9),
        record(11, FoodAction.undo, [a, b], retracts: 1),
        record(12, FoodAction.undo, [a, b], retracts: 3),
        record(13, FoodAction.add, [
          d,
        ], details: const FoodDetails(name: 'Hidden')),
        record(
          14,
          FoodAction.undo,
          [d],
          retracts: 13,
          births: {d: '$writer:13'},
        ),
        record(
          15,
          FoodAction.edit,
          [d],
          details: const FoodDetails(name: 'Protected'),
          fields: ['name'],
          births: {d: '$writer:13'},
        ),
      ];
      var admission = admitFoodRecords(history.take(2).toList());
      final untouched = admission.state.containers.singleWhere(
        (x) => x.id == c,
      );
      for (var i = 2; i < history.length; i++) {
        final before = state(admission);
        final next = appendReadyFoodRecords(admission, [history[i]]);
        expect(next, isNotNull, reason: 'prefix $i');
        final full = admitFoodRecords(history.take(i + 1).toList());
        expect(state(next!), state(full), reason: 'prefix $i');
        expect(next.readyIds, full.readyIds);
        expect(next.births.keys.toSet(), full.births.keys.toSet());
        expect(state(admission), before, reason: 'immutable accepted base');
        expect(
          identical(
            next.state.containers.singleWhere((x) => x.id == c),
            untouched,
          ),
          isTrue,
        );
        admission = next;
      }
    },
  );

  test(
    'pending bases and missing new dependencies fall back; invalid references still fail',
    () {
      final seed = record(1, FoodAction.add, [
        a,
        b,
      ], details: const FoodDetails(name: 'Beans'));
      final missing = record(
        3,
        FoodAction.restore,
        [a],
        deletes: ['$writer:2'],
      );
      final ready = admitFoodRecords([seed]);
      expect(appendReadyFoodRecords(ready, [missing]), isNull);
      final pending = admitFoodRecords([seed, missing]);
      expect(
        appendReadyFoodRecords(pending, [
          record(4, FoodAction.remove, [a]),
        ]),
        isNull,
      );
      final edited = record(2, FoodAction.edit, [
        a,
      ], contents: const Contents.fraction(1, 2));
      final base = admitFoodRecords([seed, edited]);
      expect(
        () => appendReadyFoodRecords(base, [
          record(
            3,
            FoodAction.edit,
            [b],
            contents: const Contents.fraction(1, 4),
            edits: ['$writer:2'],
          ),
        ]),
        throwsFormatException,
      );
      expect(
        () => appendReadyFoodRecords(base, [
          record(3, FoodAction.undo, [a, b], retracts: 2),
        ]),
        throwsFormatException,
      );
      expect(
        () => appendReadyFoodRecords(base, [
          record(3, FoodAction.add, [
            a,
          ], details: const FoodDetails(name: 'Duplicate')),
        ]),
        throwsFormatException,
      );
      expect(
        () => appendReadyFoodRecords(base, [edited]),
        throwsFormatException,
      );
      expect(state(base), state(admitFoodRecords([seed, edited])));
    },
  );
}
