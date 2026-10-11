import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';

const _writer = '00000000-0000-4000-8000-000000000010';
String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

FoodOperation _add(
  int n, {
  String? expiry,
  String retention = '',
  bool? estimated,
}) => FoodOperation(
  id: '$_writer:$n',
  order: n,
  action: FoodAction.add,
  targets: [_id(n)],
  details: FoodDetails(
    name: 'Shared food $n',
    expiry: expiry,
    retention: retention,
    estimated: estimated,
  ),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-10T00:00:00Z',
);

List<FoodOperation> _history() => [
  _add(1),
  _add(2, expiry: '2026-10-20', estimated: false),
  _add(3, retention: 'Keep', estimated: true),
  _add(4, expiry: '2026-10-14', retention: 'Gift', estimated: false),
  _add(5, expiry: '2026-10-12', estimated: true),
  _add(6),
  _add(7, expiry: '2026-10-20'),
  _add(8, retention: 'Keep'),
  _add(9, expiry: '2026-10-14', retention: 'Gift'),
  for (var n = 6; n <= 9; n++)
    FoodOperation(
      id: '$_writer:${n + 4}',
      order: n + 4,
      action: FoodAction.remove,
      targets: [_id(n)],
    ),
];

List<String> _ids(List<FoodGroup> groups) => [
  for (final group in groups)
    for (final container in group.containers) container.id,
];

void main() {
  test(
    'Stock partitions exclude retained and deleted food without losing active IDs',
    () {
      final state = projectFood(_history());
      final inbox = _ids(state.view(FoodView.inbox));
      final dated = _ids(state.view(FoodView.inventory));
      final retained = _ids(state.view(FoodView.retained));
      final stock = [...inbox, ...dated];
      expect(inbox, [_id(1)]);
      expect(dated, [_id(5), _id(2)]);
      expect(retained.toSet(), {_id(3), _id(4)});
      expect(stock.toSet().intersection(retained.toSet()), isEmpty);
      expect({...stock, ...retained}, state.active.map((e) => e.id).toSet());
      expect(stock.length + retained.length, state.active.length);
      expect(_ids(state.view(FoodView.deleted)).toSet(), {
        _id(6),
        _id(7),
        _id(8),
        _id(9),
      });
      final undatedRetained = state.active.singleWhere((e) => e.id == _id(3));
      expect(undatedRetained.details.expiry, isNull);
      expect(undatedRetained.details.retention, 'Keep');
      expect(undatedRetained.details.estimated, isTrue);
    },
  );

  test(
    'searched views return each active match once and bypass retention filters',
    () {
      final state = projectFood(_history());
      for (final view in [
        FoodView.inventory,
        FoodView.inbox,
        FoodView.retained,
      ]) {
        final matches = _ids(
          state.view(view, search: 'shared food', reasons: {'Gift'}),
        );
        expect(matches.toSet(), state.active.map((e) => e.id).toSet());
        expect(matches.length, state.active.length);
        expect(matches, [_id(5), _id(4), _id(2), _id(1), _id(3)]);
      }
      expect(_ids(state.view(FoodView.retained, reasons: {'Gift'})), [_id(4)]);
      final deletedMatches = _ids(
        state.view(FoodView.deleted, search: 'shared food'),
      );
      expect(deletedMatches.toSet(), state.deleted.map((e) => e.id).toSet());
      expect(deletedMatches.length, state.deleted.length);
      expect(
        deletedMatches.toSet().intersection(
          state.active.map((e) => e.id).toSet(),
        ),
        isEmpty,
      );
      expect(state.view(FoodView.deleted, search: 'missing'), isEmpty);
    },
  );

  test('whitespace search keeps ordinary dated and undated partitions', () {
    final state = projectFood(_history());
    expect(_ids(state.view(FoodView.inbox, search: '  \t ')), [_id(1)]);
    expect(_ids(state.view(FoodView.inventory, search: '  \t ')), [
      _id(5),
      _id(2),
    ]);
    expect(
      _ids(state.view(FoodView.retained, search: '  \t ', reasons: {'Gift'})),
      [_id(4)],
    );
  });

  test(
    'date and retention edits reclassify without changing identity or hidden facts',
    () {
      final original = _history();
      final before = original.map((e) => e.toJson()).toList();
      final state = projectFood([
        ...original,
        FoodOperation(
          id: '$_writer:14',
          order: 14,
          action: FoodAction.edit,
          targets: [_id(1)],
          details: const FoodDetails(
            name: 'Shared food 1',
            expiry: '2026-10-10',
          ),
          fields: const ['expiry'],
        ),
        FoodOperation(
          id: '$_writer:15',
          order: 15,
          action: FoodAction.edit,
          targets: [_id(3)],
          details: const FoodDetails(name: 'Shared food 3'),
          fields: const ['retention'],
        ),
      ]);
      expect(_ids(state.view(FoodView.inbox)), [_id(3)]);
      expect(_ids(state.view(FoodView.inventory)), [_id(1), _id(5), _id(2)]);
      expect(_ids(state.view(FoodView.retained)), [_id(4)]);
      expect(
        state.containers.map((e) => e.id),
        projectFood(original).containers.map((e) => e.id),
      );
      expect(
        state.containers.map((e) => e.contents.toJson()),
        projectFood(original).containers.map((e) => e.contents.toJson()),
      );
      expect(
        state.containers.map((e) => e.details.estimated),
        projectFood(original).containers.map((e) => e.details.estimated),
      );
      expect(original.map((e) => e.toJson()).toList(), before);
    },
  );
}
