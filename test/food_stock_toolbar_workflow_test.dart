import 'package:tandemlog/presentation/list_row_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/section_menu.dart';

const _writer = '00000000-0000-4000-8000-000000000090';

List<FoodOperation> stockToolbarFoods() => [
  for (final entry in <(String, String?, String)>[
    ('Food undated', null, ''),
    ('Food early', '2026-10-12', ''),
    ('Food late', '2026-10-20', ''),
    ('Food retained undated', null, 'Emergency'),
    ('Food retained dated', '2026-10-11', 'Emergency'),
    ('Food deleted', '2026-10-10', ''),
  ].indexed)
    FoodOperation(
      id: '$_writer:${entry.$1 + 1}',
      order: entry.$1 + 1,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(entry.$1 + 90).toString().padLeft(12, '0')}',
      ],
      details: FoodDetails(
        name: entry.$2.$1,
        expiry: entry.$2.$2,
        retention: entry.$2.$3,
      ),
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-11T00:00:00Z',
    ),
  FoodOperation(
    id: '$_writer:7',
    order: 7,
    action: FoodAction.remove,
    targets: ['00000000-0000-4000-8000-000000000095'],
  ),
];

Future<void> chooseFoodView(
  WidgetTester tester,
  String label, {
  Future<void> Function(Finder)? input,
}) async {
  Future<void> tap(Finder target) async {
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
  }

  await tap(find.byKey(const ValueKey('food-filter')));
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(PopupMenuItem<FoodView>, label));
  await tester.pumpAndSettle();
}

Future<void> verifyFoodStockToolbarWorkflow(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  var writes = 0;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('stock-toolbar-${brightness.name}-$textScale'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: projectFood(stockToolbarFoods()),
        now: () => DateTime(2026, 10, 11),
        userName: 'Synthetic household',
        identityMenu: (child) => PopupMenuButton<String>(
          tooltip: 'Active user: Synthetic household',
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings', child: Text('Settings')),
          ],
          child: child,
        ),
        sectionMenu: (compact) =>
            SectionMenu(food: true, compact: compact, onSelected: (_) {}),
        onAdd: (_, _) => writes++,
        onRemove: (_) => writes++,
        onRestore: (_) => writes++,
        onDetails: (_, _, _, _) => writes++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('food-filter')), findsOneWidget);
  expect(find.byType(ChoiceChip), findsNothing);
  expect(find.text('Inbox'), findsOneWidget);
  expect(find.text('Food undated'), findsOneWidget);
  expect(find.text('Food retained undated'), findsNothing);
  expect(find.text('Food deleted'), findsNothing);
  expect(
    tester.getTopLeft(find.text('Food undated')).dy,
    lessThan(tester.getTopLeft(find.text('Food early')).dy),
  );
  expect(
    tester.getTopLeft(find.text('Food early')).dy,
    lessThan(tester.getTopLeft(find.text('Food late')).dy),
  );
  expect(
    tester.getSize(find.byKey(const ValueKey('food-filter'))).height,
    greaterThanOrEqualTo(48),
  );
  await capture?.call('stock-inbox');

  await chooseFoodView(tester, 'Retained', input: input);
  expect(find.text('Food undated'), findsNothing);
  expect(find.text('Inbox'), findsNothing);
  expect(find.byType(ExpansionTile), findsNothing);
  await tester.ensureVisible(find.text('Food retained undated'));
  expect(
    find.descendant(
      of: find.widgetWithText(ListRowSurface, 'Food retained undated'),
      matching: find.text('Emergency'),
    ),
    findsOneWidget,
  );
  expect(find.text('Food retained undated'), findsOneWidget);
  expect(find.text('Needs expiration'), findsOneWidget);
  await capture?.call('retained-undated');

  await input?.call(find.byKey(const ValueKey('food-search')));
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'Food');
  await tester.pumpAndSettle();
  for (final name in [
    'Food undated',
    'Food early',
    'Food late',
    'Food retained undated',
    'Food retained dated',
    'Food deleted',
  ]) {
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(name),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
  }
  expect(find.byTooltip('Restore one Food deleted container'), findsOneWidget);
  expect(find.text('Inbox'), findsNothing);
  await capture?.call('all-food-search');

  // Search pauses every saved view, including Deleted, until it is cleared.
  await chooseFoodView(tester, 'Deleted', input: input);
  tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  expect(find.text('Search food'), findsOneWidget);
  await capture?.call('all-food-search-saved-deleted');
  await chooseFoodView(tester, 'Stock', input: input);
  tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  expect(find.text('Search food'), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text('Food undated'),
    250,
    scrollable: find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Food undated'), findsOneWidget);

  tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  final searchField = find.byKey(const ValueKey('food-search'));
  // Reconnect the native editor after the Filter popup changed focus.
  if (input == null) {
    await tester.tap(searchField);
  } else {
    await input(searchField);
  }
  await tester.pumpAndSettle();
  await tester.enterText(searchField, '   ');
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(searchField).controller!.text, '   ');
  tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      )
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  // Reach the restored lazy Inbox explicitly, as with the other native rows.
  await tester.scrollUntilVisible(
    find.text('Inbox'),
    250,
    scrollable: find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Inbox'), findsOneWidget);
  expect(find.text('Food retained dated'), findsNothing);
  expect(writes, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets('combined Food Stock and Filter ${sample.$1} '
          '${sample.$2}x ${brightness.name}', (tester) async {
        tester.view.physicalSize = Size(sample.$1, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await verifyFoodStockToolbarWorkflow(
          tester,
          brightness: brightness,
          textScale: sample.$2,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
