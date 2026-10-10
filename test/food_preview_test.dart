import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';
import '../tool/food_preview.dart';

void main() {
  final summaries = <String, (List<Contents>, String?)>{
    'single known full': ([const Contents.fraction(1, 1)], null),
    'single unknown': ([const Contents.unknown()], '× 1'),
    'single partial': ([const Contents.fraction(1, 3)], '1 container ⅓ full'),
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
    testWidgets('collapsed summary preserves ${entry.key}', (tester) async {
      final (contents, expected) = entry.value;
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
      if (expected == null) {
        expect(find.text('1 full'), findsNothing);
        await tester.tap(find.byTooltip('Inspect Rice containers'));
        await tester.pumpAndSettle();
        expect(find.text('1 container · 1 lb · Freezer'), findsOneWidget);
        expect(find.textContaining(' · Full'), findsOneWidget);
      } else {
        expect(find.text(expected), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('retained reasons start collapsed; active search bypasses them', (
    tester,
  ) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retained'));
    await tester.pumpAndSettle();
    expect(find.text('Chocolate').hitTestable(), findsNothing);
    await tester.tap(find.widgetWithText(ExpansionTile, 'Birthday baking'));
    await tester.pumpAndSettle();
    expect(find.text('Chocolate').hitTestable(), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('food-search')),
      'birthday',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Chocolate').hitTestable(), findsOneWidget);
  });
  testWidgets(
    'narrow and wide inventory render partial stock without overflow',
    (tester) async {
      for (final width in [390.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(FoodPreviewApp(key: ValueKey(width)));
        await tester.pumpAndSettle();
        expect(find.text('7 full + 1 container ⅓ full'), findsOneWidget);
        await tester.tap(find.byTooltip('Inspect Rice containers'));
        await tester.pumpAndSettle();
        expect(find.text('8 containers · 1 lb'), findsOneWidget);
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
    await tester.tap(find.text('Deleted'));
    await tester.pumpAndSettle();
    expect(find.text('Oat milk'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo removal'));
    await tester.pumpAndSettle();
    expect(find.text('Oat milk'), findsNothing);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('2 full'), findsOneWidget);
  });
  testWidgets(
    'partial containers require inspection; search includes retained stock',
    (tester) async {
      await tester.pumpWidget(const FoodPreviewApp());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove one Rice container'), findsNothing);
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
