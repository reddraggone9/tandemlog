import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';

const rice = FoodDetails(name: 'Rice', expiry: '2026-10-15', size: '1 lb');
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const c = '00000000-0000-4000-8000-000000000003';
const writer = '00000000-0000-4000-8000-000000000010';
FoodOperation operation(
  int n,
  FoodAction action,
  List<String> targets, {
  FoodDetails? details,
  Contents? contents,
  List<String> observed = const [],
}) => FoodOperation(
  id: '$writer:$n',
  order: n,
  action: action,
  targets: targets,
  details: details,
  contents: contents,
  observedDeletes: observed,
  createdAt: action == FoodAction.add ? '2026-10-10T00:00:00Z' : null,
);

void main() {
  test('Deleted sorts tied writers and uses latest still-active deletion', () {
    const other = '00000000-0000-4000-8000-000000000020';
    final events = [
      operation(1, FoodAction.add, [a], details: rice),
      FoodOperation(
        id: '$other:1',
        order: 1,
        action: FoodAction.add,
        targets: [b],
        details: const FoodDetails(name: 'Soup', expiry: '2026-10-11'),
        createdAt: '2026-10-10T00:00:00Z',
      ),
      operation(2, FoodAction.remove, [b]),
      operation(3, FoodAction.remove, [a]),
      FoodOperation(
        id: '$other:2',
        order: 3,
        action: FoodAction.remove,
        targets: [b],
      ),
    ];
    List<String> deletedIds(Iterable<FoodOperation> input) => projectFood(
      input,
    ).view(FoodView.deleted).map((e) => e.containers.single.id).toList();
    expect(deletedIds(events.reversed), [b, a]);
    events.add(operation(4, FoodAction.restore, [b], observed: ['$other:2']));
    expect(deletedIds(events), [a, b]);
    expect(deletedIds(events.reversed), [a, b]);
    expect(
      projectFood(events).deleted.singleWhere((e) => e.id == b).deletions,
      {'$writer:2'},
    );
  });
  test('Deleted sequence tie uses numeric sequence rather than lexical ID', () {
    final events = [
      operation(1, FoodAction.add, [a], details: rice),
      FoodOperation(
        id: '$writer:3',
        order: 1,
        action: FoodAction.add,
        targets: [b],
        details: const FoodDetails(name: 'Soup'),
        createdAt: '2026-10-10T00:00:00Z',
      ),
      FoodOperation(
        id: '$writer:2',
        order: 2,
        action: FoodAction.remove,
        targets: [a],
      ),
      FoodOperation(
        id: '$writer:10',
        order: 2,
        action: FoodAction.remove,
        targets: [b],
      ),
    ];
    expect(
      projectFood(
        events.reversed,
      ).view(FoodView.deleted).map((e) => e.containers.single.id),
      [b, a],
    );
  });
  test(
    'equivalent fractions do not conflict; real alternatives require review',
    () {
      final events = [
        operation(1, FoodAction.add, [a], details: rice),
        operation(2, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(1, 2)),
        operation(3, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(2, 4)),
      ];
      expect(projectFood(events).active.single.contentsConflict, isFalse);
      expect(const Contents.fraction(2, 6).label, '⅓ remaining');
      events.add(
        operation(4, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(1, 1)),
      );
      expect(
        projectFood(events).groups.single.summary,
        '1 containers · contents need review',
      );
      expect(projectFood(events).groups.single.quickRemoveTarget, isNull);
    },
  );
  test(
    'multiwriter tied clocks and delayed Restore replay deterministically',
    () {
      const other = '00000000-0000-4000-8000-000000000020';
      final seed = operation(1, FoodAction.add, [a], details: rice);
      final remove = FoodOperation(
        id: '$other:1',
        order: 2,
        action: FoodAction.remove,
        targets: [a],
      );
      final restore = FoodOperation(
        id: '$writer:2',
        order: 3,
        action: FoodAction.restore,
        targets: [a],
        observedDeletes: ['$other:1'],
      );
      expect(projectFood([seed, restore]).active.single.id, a);
      expect(projectFood([restore, remove, seed]).active.single.id, a);
      final edit1 = FoodOperation(
        id: '$writer:3',
        order: 4,
        action: FoodAction.edit,
        targets: [a],
        contents: const Contents.fraction(1, 2),
      );
      final edit2 = FoodOperation(
        id: '$other:2',
        order: 4,
        action: FoodAction.edit,
        targets: [a],
        contents: const Contents.fraction(1, 3),
      );
      expect(
        projectFood([seed, edit1, edit2]).containers.single.toJson(),
        projectFood([edit2, seed, edit1]).containers.single.toJson(),
      );
    },
  );
  test('independent field edits merge without overwriting the other field', () {
    final state = projectFood([
      operation(1, FoodAction.add, [a], details: rice),
      FoodOperation(
        id: '$writer:2',
        order: 2,
        action: FoodAction.edit,
        targets: [a],
        details: const FoodDetails(name: 'Rice', brand: 'Example brand'),
        fields: ['brand'],
      ),
      FoodOperation(
        id: '$writer:3',
        order: 3,
        action: FoodAction.edit,
        targets: [a],
        details: const FoodDetails(name: 'Rice', expiry: '2026-11-01'),
        fields: ['expiry'],
      ),
    ]);
    expect(state.active.single.details.brand, 'Example brand');
    expect(state.active.single.details.expiry, '2026-11-01');
    expect(state.active.single.details.size, '1 lb');
  });
  test(
    'concurrent contents alternatives remain visible until observed resolution',
    () {
      final events = [
        operation(1, FoodAction.add, [a], details: rice),
        operation(2, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(1, 3)),
        operation(3, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(1, 2)),
      ];
      expect(projectFood(events).active.single.contentsConflict, isTrue);
      events.add(
        FoodOperation(
          id: '$writer:4',
          order: 4,
          action: FoodAction.edit,
          targets: [a],
          contents: const Contents.fraction(1, 3),
          observedEdits: ['$writer:2', '$writer:3'],
        ),
      );
      expect(
        projectFood(events.reversed).active.single.contentsConflict,
        isFalse,
      );
      expect(projectFood(events).active.single.contents.label, '⅓ remaining');
    },
  );
  test('Add N creates physical containers; count is derived', () {
    final state = projectFood([
      operation(
        1,
        FoodAction.add,
        [a, b],
        details: rice,
        contents: const Contents.fraction(1, 1),
      ),
    ]);
    expect(state.containers.length, 2);
    expect(state.groups.single.containers.map((e) => e.id), [a, b]);
    expect(state.groups.single.summary, '2 full');
  });
  test(
    'eight containers stay eight with seven full and one third remaining',
    () {
      final ids = List.generate(
        8,
        (i) => '00000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
      );
      final state = projectFood([
        operation(
          1,
          FoodAction.add,
          ids,
          details: rice,
          contents: const Contents.fraction(1, 1),
        ),
        operation(2, FoodAction.edit, [
          ids.last,
        ], contents: const Contents.fraction(1, 3)),
      ]);
      expect(state.groups.single.containers.length, 8);
      expect(state.groups.single.summary, '7 full + ⅓ remaining');
      expect(state.groups.single.quickRemoveTarget, isNull);
    },
  );
  test('identical full containers have a deterministic quick target', () {
    final state = projectFood([
      operation(
        1,
        FoodAction.add,
        [b, a],
        details: rice,
        contents: const Contents.fraction(1, 1),
      ),
    ]);
    expect(state.groups.single.quickRemoveTarget, a);
  });
  test('observed group deletion excludes concurrent new containers', () {
    final events = [
      operation(1, FoodAction.add, [a, b], details: rice),
      operation(2, FoodAction.remove, [a, b]),
      operation(3, FoodAction.add, [c], details: rice),
    ];
    expect(projectFood(events).active.map((e) => e.id), [c]);
    expect(projectFood(events.reversed).active.map((e) => e.id), [c]);
  });
  test(
    'concurrent same-target remove counts once; unseen delete survives Restore',
    () {
      final events = [
        operation(1, FoodAction.add, [a], details: rice),
        operation(2, FoodAction.remove, [a]),
        operation(3, FoodAction.remove, [a]),
        operation(4, FoodAction.restore, [a], observed: ['$writer:2']),
      ];
      expect(projectFood(events).active, isEmpty);
      expect(projectFood(events).deleted.single.deletions, {'$writer:3'});
      events.add(
        operation(5, FoodAction.restore, [a], observed: ['$writer:3']),
      );
      expect(projectFood(events).active.single.id, a);
    },
  );
  test('duplicate and arbitrarily reordered delivery replay identically', () {
    final events = [
      operation(1, FoodAction.add, [a, b], details: rice),
      operation(2, FoodAction.edit, [
        a,
      ], contents: const Contents.fraction(1, 3)),
      operation(3, FoodAction.remove, [b]),
      operation(4, FoodAction.restore, [b], observed: ['$writer:3']),
    ];
    final expected = projectFood(
      events,
    ).containers.map((e) => e.toJson()).toList();
    for (var shift = 0; shift < events.length; shift++) {
      final shuffled = [
        ...events.skip(shift),
        ...events.take(shift),
        ...events.reversed,
      ];
      expect(
        projectFood(shuffled).containers.map((e) => e.toJson()).toList(),
        expected,
      );
    }
  });
  test(
    'retention hides even preexpiry; undated stays Inbox; search ignores filters',
    () {
      final state = projectFood([
        operation(1, FoodAction.add, [a], details: rice),
        operation(
          2,
          FoodAction.add,
          [b],
          details: const FoodDetails(
            name: 'Soup',
            expiry: '2026-10-11',
            retention: 'Keep for trip',
          ),
        ),
        operation(3, FoodAction.add, [
          c,
        ], details: const FoodDetails(name: 'Frozen peas')),
      ]);
      expect(state.view(FoodView.inventory).single.containers.single.id, a);
      expect(state.view(FoodView.inbox).single.containers.single.id, c);
      expect(
        state
            .view(FoodView.inventory, search: 'soup', reasons: {'Other'})
            .single
            .containers
            .single
            .id,
        b,
      );
    },
  );
  test(
    'expiry order is global; different expiry or descriptive data stay separate',
    () {
      final state = projectFood([
        operation(1, FoodAction.add, [a], details: rice),
        operation(2, FoodAction.add, [
          b,
        ], details: const FoodDetails(name: 'Zucchini', expiry: '2026-10-11')),
        operation(
          3,
          FoodAction.add,
          [c],
          details: const FoodDetails(
            name: 'Rice',
            expiry: '2026-10-17',
            size: '1 lb',
          ),
        ),
      ]);
      expect(state.groups.map((e) => e.details.expiry), [
        '2026-10-11',
        '2026-10-15',
        '2026-10-17',
      ]);
    },
  );
  test('Deleted is explicit, searchable, and durable with no age cutoff', () {
    final events = [
      operation(1, FoodAction.add, [a], details: rice),
      operation(2, FoodAction.remove, [a]),
    ];
    expect(
      projectFood(events).view(FoodView.inventory, search: 'rice'),
      isEmpty,
    );
    expect(
      projectFood(events).view(FoodView.deleted, search: 'rice'),
      hasLength(1),
    );
    expect(
      projectFood(
        events.map((e) => FoodOperation.fromJson(e.toJson())),
      ).deleted.single.id,
      a,
    );
  });
  test(
    'invalid counts, fractions, dates, paths and unknown fields fail closed',
    () {
      expect(
        () => operation(1, FoodAction.add, [], details: rice).validate(),
        throwsFormatException,
      );
      expect(
        () => operation(1, FoodAction.add, [a, a], details: rice).validate(),
        throwsFormatException,
      );
      expect(
        () => operation(1, FoodAction.edit, [
          a,
        ], contents: const Contents.fraction(2, 1)).validate(),
        throwsFormatException,
      );
      expect(
        () => operation(1, FoodAction.add, [
          '../escape',
        ], details: rice).validate(),
        throwsFormatException,
      );
      expect(
        () => operation(
          1,
          FoodAction.add,
          [a],
          details: const FoodDetails(name: 'X', expiry: '2026-02-30'),
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => FoodOperation.fromJson({
          ...operation(1, FoodAction.remove, [a]).toJson(),
          'quantity': 99,
        }),
        throwsFormatException,
      );
    },
  );
}
