import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_rows.dart';
import 'package:tandemlog/food/inventory.dart';

FoodContainer _item(
  int n,
  String name, {
  String? expiry,
  String retention = '',
  bool deleted = false,
}) => FoodContainer(
  id: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  details: FoodDetails(name: name, expiry: expiry, retention: retention),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-11-14T00:00:00Z',
  deletions: deleted ? {'00000000-0000-4000-8000-000000000999:$n'} : {},
  deletedOrder: deleted ? n : 0,
  lastDeletionId: deleted ? '00000000-0000-4000-8000-000000000999:$n' : null,
  contentsEdits: {},
);

List<String> _names(List<FoodGroup> groups) => [
  for (final group in groups) group.details.name,
];

void main() {
  final state = FoodState([
    _item(1, 'Food Z inbox'),
    _item(2, 'Food A later', expiry: '2026-12-01'),
    _item(3, 'Food B earlier', expiry: '2026-11-01'),
    _item(4, 'Food A inbox'),
    _item(5, 'Food Z retained', retention: 'Keep'),
    _item(6, 'Food A retained', expiry: '2026-10-01', retention: 'Keep'),
    _item(7, 'Food deleted undated', deleted: true),
    _item(8, 'Food deleted dated', expiry: '2026-09-01', deleted: true),
  ]);

  test('search puts undated active rows first, with Deleted still last', () {
    for (final view in FoodView.values) {
      final rows = FoodRows(state: state, view: view, query: 'food');
      expect(rows.inbox, isEmpty);
      expect(_names(rows.groups), [
        'Food A inbox',
        'Food Z inbox',
        'Food Z retained',
        'Food A retained',
        'Food B earlier',
        'Food A later',
      ]);
      expect(_names(rows.deletedGroups), [
        'Food deleted dated',
        'Food deleted undated',
      ]);
      expect(rows.rows, [...rows.groups, ...rows.deletedGroups]);
    }
  });

  test('normal Stock keeps separate Inbox above dated Stock', () {
    for (final view in [FoodView.inventory, FoodView.inbox]) {
      for (final query in ['', ' \t ']) {
        final rows = FoodRows(state: state, view: view, query: query);
        expect(_names(rows.inbox), ['Food A inbox', 'Food Z inbox']);
        expect(_names(rows.groups), ['Food B earlier', 'Food A later']);
        expect(rows.deletedGroups, isEmpty);
        expect(rows.rows, [...rows.inbox, ...rows.groups]);
      }
    }
  });

  test('normal Retained is undated first; Deleted keeps deletion recency', () {
    final retained = FoodRows(state: state, view: FoodView.retained, query: '');
    expect(retained.inbox, isEmpty);
    expect(_names(retained.rows), ['Food Z retained', 'Food A retained']);
    final deleted = FoodRows(state: state, view: FoodView.deleted, query: '');
    expect(_names(deleted.rows), [
      'Food deleted dated',
      'Food deleted undated',
    ]);
  });
}
