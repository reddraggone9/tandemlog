import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Future<FoodInventoryPageState> _pump(
  WidgetTester tester, {
  bool wide = false,
  Map<String, String> names = const {},
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
                name: names[entry.$2.$1] ?? entry.$2.$1,
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
  // Narrow selection hides search; exercise the mounted callback separately.
  // The layout parity tests use pointer/keyboard input in the visible wide field.
  final field = tester.widget<TextField>(
    find.byKey(const ValueKey('food-search')),
  );
  field.controller!.text = value;
  field.onChanged!(value);
  await tester.pumpAndSettle();
}

Future<void> _clearSearch(WidgetTester tester) async {
  final button = tester.widget<IconButton>(
    find.byWidgetPredicate(
      (w) => w is IconButton && w.tooltip == 'Clear food search',
    ),
  );
  button.onPressed!();
  await tester.pumpAndSettle();
}

/// Shared with the native Linux workflow: filtering a wide editor must not
/// silently change the captured targets behind its count or draft.
Future<void> verifyFoodWideSelectionRetention(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  final page = await _pump(tester, wide: true);
  await _toggle(tester, 'Beans');
  await _toggle(tester, 'Rice');
  expect(find.text('Edit 2 containers'), findsOneWidget);
  await capture?.call('wide-selection-before-filter');
  await chooseFoodView(tester, 'Retained');
  expect(find.text('Rice'), findsNothing);
  expect(page.bulkSelected, {_id(1), _id(2)});
  expect(find.text('Edit 2 containers'), findsOneWidget);
  await capture?.call('wide-selection-after-filter-editor-captured');
  // Closing the pane clears selection, as Tasks does; no hidden stale targets remain.
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  expect(page.bulkSelected, isEmpty);
  expect(page.selecting, isFalse);
  expect(find.text('0 selected'), findsNothing);
  expect(find.text('Edit 2 containers'), findsNothing);
  await capture?.call('wide-selection-after-editor-close-pruned');
  expect(tester.takeException(), isNull);
}

Future<void> verifyFoodSearchFocusRetention(
  WidgetTester tester, {
  Future<void> Function(String)? typeText,
  Future<void> Function(String)? capture,
}) async {
  Future<void> typeQuery(String query) async {
    if (typeText != null) {
      await typeText(query);
    } else {
      tester.testTextInput.enterText(query);
    }
  }

  final page = await _pump(
    tester,
    wide: true,
    names: {'Beans': 'RC117 Receipt birth', 'Rice': 'RC117 Labeled undated'},
  );
  await _toggle(tester, 'RC117 Receipt birth');
  await _toggle(tester, 'RC117 Labeled undated');
  final search = find.byKey(const ValueKey('food-search'));
  await tester.tap(search);
  await typeQuery('e');
  await tester.pumpAndSettle();
  expect(page.bulkSelected, {_id(1), _id(2)});
  await typeQuery('Rece');
  await tester.pumpAndSettle();
  final input = find.descendant(
    of: search,
    matching: find.byType(EditableText),
  );
  expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
  // Continue through the active IME connection, without refocusing Search.
  for (final query in ['Recei', 'Receip', 'Receipt']) {
    await typeQuery(query);
    await tester.pumpAndSettle();
  }
  expect(tester.widget<TextField>(search).controller!.text, 'Receipt');
  expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
  final name = find.widgetWithText(TextField, 'Food name');
  expect(
    tester.widget<TextField>(name).controller!.text,
    'RC117 Receipt birth',
  );
  expect(find.byType(FoodEditor), findsOneWidget);
  expect(page.bulkSelected, isEmpty); // The survivor is now plain-edited.
  expect(
    tester
        .widget<FoodEditor>(find.byType(FoodEditor))
        .group!
        .containers
        .map((c) => c.id),
    [_id(1)],
  );
  await capture?.call('search-receipt-typing-survivor');
  await typeQuery('');
  await tester.pumpAndSettle();
  expect(
    tester.widget<TextField>(name).controller!.text,
    'RC117 Receipt birth',
  );
  expect(find.text('Edit 2 containers'), findsNothing);
  expect(find.byType(FoodEditor), findsOneWidget);
  await capture?.call('search-typing-survivor');
}

Future<void> verifyFoodHiddenSearchAnchor(
  WidgetTester tester, {
  Future<void> Function(String)? capture,
}) async {
  final page = await _pump(tester, wide: true);
  await tester.tap(find.text('Rice').first);
  await tester.pumpAndSettle();
  await _toggle(tester, 'Beans');
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'Rice');
  await tester.pumpAndSettle();
  await _clearSearch(tester);
  await capture?.call('hidden-anchor-before-shift');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(find.text('Milk').first);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
  await capture?.call('hidden-anchor-after-shift');
  expect(page.bulkSelected, {_id(3)});
  expect(find.text('Edit 2 containers'), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'wide Search forgets hidden anchor after returning to single editing',
    verifyFoodHiddenSearchAnchor,
  );

  testWidgets('wide Search keeps a surviving range anchor', (tester) async {
    final page = await _pump(tester, wide: true);
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Rice');
    await _search(tester, 'Rice');
    await _clearSearch(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Milk').first);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(1), _id(2), _id(3)});
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search keeps selected rows that remain visible', (tester) async {
    // Lee 2026-11-12: Tasks and Food keep selected rows that remain visible
    // when Search changes.
    final page = await _pump(tester);
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Rice');
    await _search(tester, 'e'); // Beans and Rice both still match.
    expect(page.bulkSelected, {_id(1), _id(2)});
    expect(page.selecting, isTrue);
    await _search(tester, 'Beans');
    expect(page.bulkSelected, {_id(1)});
    expect(page.selecting, isTrue);
    expect(find.text('1 selected'), findsOneWidget);
    await _clearSearch(tester);
    // Hidden rows are dropped, not resurrected when the search widens.
    expect(page.bulkSelected, {_id(1)});
    expect(page.selecting, isTrue);
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(1), _id(2)});
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
  });

  testWidgets('Search that hides every selected row ends selection', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Rice');
    await _search(tester, 'Milk');
    expect(page.bulkSelected, isEmpty);
    expect(page.selecting, isFalse);
    await _clearSearch(tester);
    expect(page.bulkSelected, isEmpty);
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Food name'), findsOneWidget);
  });

  testWidgets('a search-hidden anchor cannot extend a later range', (
    tester,
  ) async {
    final page = await _pump(tester);
    await _toggle(tester, 'Rice');
    await _toggle(tester, 'Beans'); // Anchor Beans will become hidden.
    await _search(tester, 'Rice');
    expect(page.bulkSelected, {_id(2)});
    await _clearSearch(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Milk'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_id(3)});
  });

  testWidgets('clearing a search keeps the rows its view still shows', (
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
    expect(page.selecting, isTrue);
    await chooseFoodView(tester, 'Stock');
    expect(page.bulkSelected, isEmpty);
    expect(page.selecting, isTrue);
  });

  testWidgets(
    'wide Search narrowing to one keeps typing in Search',
    verifyFoodSearchFocusRetention,
  );

  testWidgets('wide Search keeps the pane and guards a hidden target', (
    tester,
  ) async {
    final page = await _pump(tester, wide: true);
    await _search(tester, 'e');
    await _toggle(tester, 'Beans');
    await _toggle(tester, 'Reserve');
    expect(find.text('Edit 2 containers'), findsOneWidget);
    final brand = find.widgetWithText(TextField, 'Brand');
    await tester.enterText(brand, 'Wide search draft');
    await tester.pumpAndSettle();
    final pane = tester.element(find.byType(FoodEditor));
    final field = find.byKey(const ValueKey('food-search'));
    // Both selected rows still match: no prompt, same pane and draft.
    await tester.enterText(field, 's');
    await tester.pumpAndSettle();
    expect(find.text('Discard food changes?'), findsNothing);
    expect(tester.element(find.byType(FoodEditor)), same(pane));
    expect(
      tester.widget<TextField>(brand).controller!.text,
      'Wide search draft',
    );
    expect(page.bulkSelected, {_id(1), _id(4)});
    // Clearing hides retained Reserve from Stock, so the draft is resolved.
    await tester.tap(find.byTooltip('Clear food search'));
    await tester.pumpAndSettle();
    expect(find.text('Discard food changes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Keep editing').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 's');
    expect(
      tester.widget<TextField>(brand).controller!.text,
      'Wide search draft',
    );
    expect(page.bulkSelected, {_id(1), _id(4)});
    await tester.tap(find.byTooltip('Clear food search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    // Beans stays shown, so the pane returns to its single editor.
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('Edit 2 containers'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Food name'))
          .controller!
          .text,
      'Beans',
    );
    expect(find.text('Reserve'), findsNothing);
    // A plain-edited row that Search hides closes its clean editor.
    await tester.enterText(field, 'Milk');
    await tester.pumpAndSettle();
    expect(find.byType(FoodEditor), findsNothing);
    expect(page.bulkSelected, isEmpty);
    expect(page.selecting, isFalse);
    expect(tester.takeException(), isNull);
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
