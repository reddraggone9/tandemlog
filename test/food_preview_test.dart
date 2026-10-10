import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/food_preview.dart';

void main() {
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
