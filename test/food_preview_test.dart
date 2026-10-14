import 'support/toolbar_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';
import '../tool/food_preview.dart';
import 'food_expiry_guidance_test.dart' show selectFoodView;

void main() {
  final summaries = <String, (List<Contents>, String?)>{
    'single known full': ([const Contents.fraction(1, 1)], null),
    'single partial': ([const Contents.fraction(1, 3)], null),
    'multiple full': (
      [const Contents.fraction(1, 1), const Contents.fraction(1, 1)],
      '2 full',
    ),
    'mixed full and partial': (
      [const Contents.fraction(1, 1), const Contents.fraction(1, 3)],
      '1 full + 1 container ⅓ full',
    ),
  };
  for (final entry in summaries.entries) {
    testWidgets('physical count preserves legacy ${entry.key}', (tester) async {
      final contents = entry.value.$1;
      final operations = List.generate(
        contents.length,
        (i) => FoodOperation(
          id: '00000000-0000-4000-8000-000000000010:${i + 1}',
          order: i + 1,
          action: FoodAction.add,
          targets: [
            '00000000-0000-4000-8000-${(i + 1).toRadixString(16).padLeft(12, '0')}',
          ],
          details: const FoodDetails(
            name: 'Rice',
            brand: 'Sample Foods',
            expiry: '2026-10-15',
            size: '1 lb',
            location: 'Freezer',
          ),
          contents: contents[i],
          createdAt: '2026-10-10T00:00:00Z',
        ),
      );
      await tester.pumpWidget(FoodPreviewApp(initialOperations: operations));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Sample Foods'), findsOneWidget);
      if (contents.length == 1) {
        expect(find.text('1 container'), findsNothing);
      } else {
        expect(find.text('${contents.length} containers'), findsOneWidget);
      }
      expect(find.text('1 lb · Freezer'), findsOneWidget);
      expect(find.text('Full'), findsNothing);
      expect(find.text('Remaining contents'), findsNothing);
      expect(find.byTooltip('Remove one Rice container'), findsOneWidget);
      expect(operations.map((op) => op.contents).toList(), contents);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'retained food is directly visible; active search bypasses filters',
    (tester) async {
      await tester.pumpWidget(const FoodPreviewApp());
      await tester.pumpAndSettle();
      await selectFoodView(tester, FoodView.retained);
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.widgetWithText(Card, 'Birthday baking'), findsOneWidget);
      expect(find.text('Chocolate').hitTestable(), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'birthday',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('Chocolate').hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'narrow and wide inventory render partial stock without overflow',
    (tester) async {
      for (final width in [390.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(FoodPreviewApp(key: ValueKey(width)));
        await tester.pumpAndSettle();
        expect(find.text('8 containers'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Rice'),
              matching: find.byType(Card),
            ),
            matching: find.text('1 lb'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
  testWidgets('quick remove, Deleted and Undo preserve physical identity', (
    tester,
  ) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove one Oat milk container'));
    await tester.pumpAndSettle();
    await selectFoodView(tester, FoodView.deleted);
    await tester.pumpAndSettle();
    expect(find.text('Oat milk'), findsOneWidget);
    final undo = find.byKey(const ValueKey('undo-food-action'));
    expect(toolbarButton(tester, undo).onPressed, isNotNull);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.text('Oat milk'), findsNothing);
    await selectFoodView(tester, FoodView.inventory);
    await tester.pumpAndSettle();
    expect(find.text('2 containers'), findsOneWidget);
  });
  testWidgets(
    'legacy partial containers support quick removal; search includes retained stock',
    (tester) async {
      await tester.pumpWidget(const FoodPreviewApp());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove one Rice container'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'birthday',
      );
      await tester.pumpAndSettle();
      expect(find.text('Chocolate'), findsOneWidget);
      expect(find.text('Rice'), findsNothing);
    },
  );
}
