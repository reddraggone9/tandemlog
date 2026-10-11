import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'adaptive Undo ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 500);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var pressed = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: brightness,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(sample.$2)),
                child: child!,
              ),
              home: Scaffold(
                body: FoodInventoryToolbar(
                  userName: 'Synthetic household',
                  undoLabel: 'Undo editing 3 containers',
                  onUndo: () => pressed++,
                  onAdd: () {},
                  filter: (_) => const SizedBox(width: 48, height: 48),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final undo = find.byKey(const ValueKey('undo-food-action'));
          expect(
            find.descendant(of: undo, matching: find.text('Undo')),
            sample.$1 >= 600 ? findsOneWidget : findsNothing,
          );
          expect(find.byTooltip('Undo editing 3 containers'), findsOneWidget);
          expect(tester.getSize(undo).shortestSide, greaterThanOrEqualTo(48));
          await tester.tap(undo);
          await tester.pumpAndSettle();
          expect(pressed, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
