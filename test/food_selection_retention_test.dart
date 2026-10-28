import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Future<FoodInventoryPageState> _pump(
  WidgetTester tester, {
  bool wide = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(wide ? 1400 : 800, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: FoodInventoryPage(
        state: projectFood([
          for (final entry in [
            ('Beans', 'Pantry', ''),
            ('Rice', 'Pantry', ''),
            ('Milk', 'Dairy', ''),
            ('Reserve', 'Pantry', 'Emergency'),
          ].indexed)
            FoodOperation(
              id: '00000000-0000-4000-8000-000000000099:${entry.$1 + 1}',
              order: entry.$1 + 1,
              action: FoodAction.add,
              targets: [_id(entry.$1 + 1)],
              details: FoodDetails(
                name: entry.$2.$1,
                brand: entry.$2.$2,
                retention: entry.$2.$3,
                expiry: '2026-11-01',
              ),
              contents: const Contents.fraction(1, 1),
              createdAt: '2026-10-28T00:00:00Z',
            ),
        ]),
        onAdd: (_, _) {},
        onRemove: (_) {},
        onRestore: (_) {},
        onDetails: (_, _, _, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<FoodInventoryPageState>(find.byType(FoodInventoryPage));
}

Future<void> _toggle(WidgetTester tester, String name) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tap(find.text(name).first);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String value) async {
  // The existing compact selection actions cover the mounted search field.
  // Exercise its real change callback without changing that presentation policy.
  final field = tester.widget<TextField>(
    find.byKey(const ValueKey('food-search')),
  );
  field.controller!.text = value;
  field.onChanged!(value);
  await tester.pumpAndSettle();
}

Future<void> _clearSearch(WidgetTester tester) async {
  final button = tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.close).first,
  );
  button.onPressed!();
  await tester.pumpAndSettle();
}

/// Shared with the native Linux workflow: filtering a wide editor must not
/// silently change the captured targets behind its count or draft.
Future<void> verifyFoodWideSelectionRetention(WidgetTester tester) async {
  final page = await _pump(tester, wide: true);
  await _toggle(tester, 'Beans');
  await _toggle(tester, 'Rice');
  expect(find.text('Edit 2 containers'), findsOneWidget);
  await chooseFoodView(tester, 'Retained');
  expect(find.text('Rice'), findsNothing);
  expect(page.bulkSelected, {_id(1), _id(2)});
  expect(find.text('2 selected'), findsOneWidget);
  expect(find.text('Edit 2 containers'), findsOneWidget);
  // Closing the pane permits pruning; no hidden selection or stale pane remains.
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  expect(page.bulkSelected, isEmpty);
  expect(page.selecting, isTrue);
  expect(find.text('0 selected'), findsOneWidget);
  expect(find.text('Edit 2 containers'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('search prunes hidden IDs; clear does not resurrect them', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Rice');
    await _search(tester, 'Beans');
    expect(page.bulkSelected, {_id(1)});
    expect(find.text('1 selected'), findsOneWidget);
    await _clearSearch(tester);
    expect(page.bulkSelected, {_id(1)});
    await _search(tester, 'nothing matches');
    expect(page.bulkSelected, isEmpty);
    expect(
      page.selecting,
      isTrue,
    ); // Tasks preserves explicit selection intent.
    await _clearSearch(tester);
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(2)});
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
  });

  testWidgets('a hidden anchor cannot extend a later visible range', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _toggle(tester, 'Rice');
    await _toggle(tester, 'Beans'); // Anchor Beans will become hidden.
    await _search(tester, 'Rice');
    await _clearSearch(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Milk'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(3)});
  });

  testWidgets('view changes retain selection while search bypasses the view', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _search(tester, 'e');
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Reserve');
    await chooseFoodView(tester, 'Retained');
    expect(page.bulkSelected, {_id(1), _id(4)});
    await _clearSearch(tester);
    expect(page.bulkSelected, {_id(4)});
    await chooseFoodView(tester, 'Stock');
    expect(page.bulkSelected, isEmpty);
    expect(page.selecting, isTrue);
  });

  testWidgets('More filters keeps visible selected and drops hidden IDs', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Milk');
    await tester.tap(find.byKey(const ValueKey('food-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More filters…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-brand-filter-query')),
      'Pan',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-Pantry')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(1)});
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Milk'), findsNothing);
  });

  testWidgets(
    'wide bulk pane preserves captured selection while filtering',
    verifyFoodWideSelectionRetention,
  );
}
