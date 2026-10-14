import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

Future<void> verifyFoodFieldFilters(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  const writer = '00000000-0000-4000-8000-000000000050';
  var writes = 0;
  final events = <FoodOperation>[
    for (final entry in [
      const FoodDetails(
        name: 'Synthetic rice',
        expiry: '2026-10-15',
        brand: 'Acme',
        location: 'Pantry',
      ),
      const FoodDetails(
        name: 'Synthetic beans',
        expiry: '2026-10-16',
        brand: 'Other',
        location: 'Pantry',
      ),
      const FoodDetails(
        name: 'Synthetic deleted',
        expiry: '2026-10-10',
        brand: 'Historical',
        location: 'Old freezer',
      ),
      const FoodDetails(
        name: 'Synthetic undated',
        brand: 'Other',
        location: 'Freezer',
      ),
      const FoodDetails(
        name: 'Synthetic retained',
        retention: 'Emergency',
        brand: 'Acme',
        location: 'Freezer',
      ),
    ].indexed)
      FoodOperation(
        id: '$writer:${entry.$1 + 1}',
        order: entry.$1 + 1,
        action: FoodAction.add,
        targets: [
          '00000000-0000-4000-8000-${(800 + entry.$1).toString().padLeft(12, '0')}',
        ],
        details: entry.$2,
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    FoodOperation(
      id: '$writer:6',
      order: 6,
      action: FoodAction.remove,
      targets: ['00000000-0000-4000-8000-000000000802'],
    ),
  ];
  Future<void> tap(Finder target) async {
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
    await tester.pumpAndSettle();
  }

  Future<void> openFilters() async {
    await tap(find.byKey(const ValueKey('food-filter')));
    await tap(find.text('More filters…'));
  }

  Future<void> option(String field, String query, String label) async {
    final target = find.byKey(ValueKey('food-$field-filter-query'));
    await tester.ensureVisible(target);
    await tap(target);
    await tester.enterText(target, query);
    await tester.pumpAndSettle();
    await tap(find.byKey(ValueKey('tag-option-$label')));
  }

  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('filters-${brightness.name}-$textScale'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: projectFood(events),
        onAdd: (_, _) => writes++,
        onRemove: (_) => writes++,
        onRestore: (_) => writes++,
        onDetails: (_, _, _) => writes++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFilters();
  await option('brand', 'ac', 'Acme');
  await option('brand', 'his', 'Historical');
  await option('location', 'pan', 'Pantry');
  await capture?.call('multi-selection');
  await tap(find.widgetWithText(FilledButton, 'Apply'));
  expect(find.text('Synthetic rice'), findsOneWidget);
  expect(find.text('Synthetic beans'), findsNothing);
  expect(find.text('Synthetic undated'), findsNothing);
  expect(find.byTooltip('Filter food: Stock · active filters'), findsOneWidget);
  await capture?.call('filtered-stock');
  await chooseFoodView(tester, 'Deleted', input: input);
  expect(find.text('No deleted containers'), findsOneWidget);
  await openFilters();
  await option('location', 'old', 'Old freezer');
  await tap(find.widgetWithText(FilledButton, 'Apply'));
  expect(find.text('Synthetic deleted'), findsOneWidget);
  await capture?.call('filtered-deleted');
  final search = find.byKey(const ValueKey('food-search'));
  await tap(search);
  await tester.enterText(search, 'Synthetic');
  await tester.pumpAndSettle();
  expect(
    find.byTooltip('Filter food: all food; saved Deleted filters paused'),
    findsOneWidget,
  );
  expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  final page = tester.state<FoodInventoryPageState>(
    find.byType(FoodInventoryPage),
  );
  expect(page.brands, {'Acme', 'Historical'});
  expect(page.locations, {'Pantry', 'Old freezer'});
  await chooseFoodView(tester, 'Stock', input: input);
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  for (final name in [
    'Synthetic rice',
    'Synthetic beans',
    'Synthetic undated',
    'Synthetic retained',
    'Synthetic deleted',
  ]) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(name),
      180,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
  }
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tap(find.byTooltip('Clear food search'));
  expect(find.text('Synthetic rice'), findsOneWidget);
  expect(find.text('Synthetic beans'), findsNothing);
  await openFilters();
  await option('brand', 'oth', 'Other');
  await tap(find.widgetWithText(TextButton, 'Cancel'));
  expect(page.brands, {
    'Acme',
    'Historical',
  }, reason: 'Cancel preserves saved selections');
  await openFilters();
  await tap(find.byTooltip('Clear brand filters'));
  await tap(find.byTooltip('Clear location filters'));
  await tap(find.widgetWithText(FilledButton, 'Apply'));
  expect(find.text('Synthetic undated'), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text('Synthetic beans'),
    180,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
  expect(find.text('Synthetic beans'), findsOneWidget);
  expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  expect(writes, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Food field filters ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFoodFieldFilters(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
