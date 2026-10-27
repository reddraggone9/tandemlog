import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';

FoodContainer _item(int n, FoodDetails details, {bool deleted = false}) =>
    FoodContainer(
      id: '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
      details: details,
      contents: n.isEven
          ? const Contents.fraction(1, 1)
          : const Contents.fraction(1, 3),
      createdAt: '2026-10-23T00:00:00Z',
      deletions: deleted ? {'00000000-0000-4000-8000-000000000999:$n'} : {},
      deletedOrder: deleted ? n : 0,
      lastDeletionId: deleted
          ? '00000000-0000-4000-8000-000000000999:$n'
          : null,
      contentsEdits: {},
    );

// The pre-optimization algorithm is the differential oracle: expiry first,
// canonical descriptive key second, and physical container ID inside a group.
List<FoodGroup> _previousGroups(Iterable<FoodContainer> values) {
  final grouped = <String, List<FoodContainer>>{};
  for (final item in values) {
    grouped.putIfAbsent(item.details.displayGroupKey, () => []).add(item);
  }
  final result = grouped.values
      .map((items) => FoodGroup(items..sort((a, b) => a.id.compareTo(b.id))))
      .toList();
  result.sort((a, b) {
    final date = (a.details.expiry ?? '9999-99-99').compareTo(
      b.details.expiry ?? '9999-99-99',
    );
    return date != 0
        ? date
        : a.details.displayGroupKey.compareTo(b.details.displayGroupKey);
  });
  return result;
}

List<Object> _description(List<FoodGroup> groups) => [
  for (final group in groups)
    [
      group.details.toJson(),
      group.containers.map((item) => item.toJson()).toList(),
      group.summary,
      group.quickRemoveTarget,
    ],
];

class _CountingDetails extends FoodDetails {
  _CountingDetails(String name) : super(name: name, expiry: '2026-10-23');
  int reads = 0;
  @override
  String get displayGroupKey {
    reads++;
    return super.displayGroupKey;
  }
}

void main() {
  test('retained grouping keys preserve expiry ties and physical grouping', () {
    final items = List.generate(96, (i) {
      final cohort = i % 24;
      return _item(
        96 - i,
        FoodDetails(
          name: ['A', 'Z', 'a', 'é', 'Tea "quoted"', 'Tea\\'][cohort % 6],
          brand: cohort % 2 == 0 ? 'One' : 'Two',
          expiry: [null, '2026-10-01', '2026-10-23', '2027-01-01'][cohort ~/ 6],
          estimated: [false, true, null][i ~/ 32],
          size: '1 lb',
        ),
      );
    });
    final expected = _description(_previousGroups(items));
    for (var shift = 0; shift < 8; shift++) {
      final input = [
        ...items.skip(shift),
        ...items.take(shift),
      ].reversed.toList();
      final actual = FoodState(input).groups;
      expect(_description(actual), expected);
      expect(actual.length, 24, reason: 'Estimated certainty is excluded.');
      expect(actual.first.details.expiry, '2026-10-01');
      expect(actual.last.details.expiry, isNull);
      for (final group in actual) {
        expect(group.containers.length, 4);
        for (final item in group.containers) {
          expect(input.any((original) => identical(original, item)), isTrue);
        }
      }
      expect(
        input,
        [...items.skip(shift), ...items.take(shift)].reversed,
        reason: 'Grouping must not reorder its caller-owned list.',
      );
    }
  });

  test('views preserve status separation filters and deleted recency', () {
    const stock = FoodDetails(name: 'Same', expiry: '2026-10-23', brand: 'A');
    final items = [
      _item(6, stock, deleted: true),
      _item(2, stock),
      _item(
        1,
        const FoodDetails(
          name: 'Same',
          expiry: '2026-10-23',
          brand: 'A',
          estimated: true,
        ),
      ),
      _item(3, const FoodDetails(name: 'Same', brand: 'B')),
      _item(
        4,
        const FoodDetails(
          name: 'Same',
          expiry: '2026-10-01',
          retention: 'Keep',
          brand: 'A',
        ),
      ),
      _item(
        5,
        const FoodDetails(name: 'Same', expiry: '2026-10-01', brand: 'B'),
        deleted: true,
      ),
    ];
    final state = FoodState(items);
    List<List<String>> ids(List<FoodGroup> groups) => [
      for (final group in groups)
        group.containers.map((item) => item.id).toList(),
    ];
    List<String> expected(List<int> numbers) => [
      for (final n in numbers)
        items
            .singleWhere(
              (item) => item.id.endsWith(n.toString().padLeft(12, '0')),
            )
            .id,
    ];
    expect(ids(state.view(FoodView.inventory)), [
      expected([1, 2]),
    ]);
    expect(ids(state.view(FoodView.inbox)), [
      expected([3]),
    ]);
    expect(ids(state.view(FoodView.retained, reasons: {'Keep'})), [
      expected([4]),
    ]);
    expect(ids(state.view(FoodView.retained, reasons: {'Other'})), isEmpty);
    expect(ids(state.view(FoodView.deleted)), [
      expected([6]),
      expected([5]),
    ]);
    expect(state.view(FoodView.inventory, brands: {'B'}), isEmpty);
    for (final view in FoodView.values) {
      final result = state.view(view, search: 'same', brands: {'No match'});
      expect(ids(result), [
        expected([4]),
        expected([1, 2]),
        expected([3]),
        expected([6]),
        expected([5]),
      ]);
      expect(
        result.every(
          (group) =>
              group.containers.map((item) => item.deleted).toSet().length == 1,
        ),
        isTrue,
      );
    }
    expect(state.view(FoodView.inventory, search: 'absent'), isEmpty);
  });

  test('sorting reuses the key already computed for each container', () {
    final details = List.generate(
      64,
      (i) => _CountingDetails('Food ${63 - i}'),
    );
    final state = FoodState([
      for (var i = 0; i < details.length; i++) _item(i + 1, details[i]),
    ]);
    final groups = state.groups;
    expect(groups.length, 64);
    expect(details.map((item) => item.reads), everyElement(1));
    expect(
      groups.map((group) => group.details.name).toList(),
      details.map((item) => item.name).toList()..sort(),
    );
  });
}
