import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

void main() {
  for (final action in ['Cancel', 'Apply']) {
    testWidgets('repeated Food filter $action owns only its modal', (
      tester,
    ) async {
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: SizedBox(
                      width: 700,
                      height: 500,
                      child: FoodInventoryPage(
                        state: FoodState([]),
                        onAdd: (_, _) => writes++,
                        onRemove: (_) => writes++,
                        onRestore: (_) => writes++,
                        onDetails: (_, _, _, _) => writes++,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open inventory'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open inventory'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More filters…'));
      await tester.pumpAndSettle();
      final button = action == 'Apply'
          ? tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, action))
                .onPressed!
          : tester
                .widget<TextButton>(find.widgetWithText(TextButton, action))
                .onPressed!;
      button();
      button();
      await tester.pumpAndSettle();
      expect(
        find.byType(FoodInventoryPage),
        findsOneWidget,
        reason: 'The containing route must survive repeated activation',
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('Food filter queries dispose when the app unmounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onDetails: (_, _, _, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More filters…'));
    await tester.pumpAndSettle();
    final controllers = [
      for (final field in ['brand', 'location'])
        tester
            .widget<TextField>(find.byKey(ValueKey('food-$field-filter-query')))
            .controller!,
    ];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final controller in controllers) {
      expect(() => controller.text = 'after disposal', throwsFlutterError);
    }
    expect(tester.takeException(), isNull);
  });
}
