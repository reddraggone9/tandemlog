import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import '../tool/food_preview.dart';
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
  }

  testWidgets('native Food keyboard Space selects one group (dark)', (
    tester,
  ) async {
    await open(tester);
    await pixels.capture(tester, 'food-keyboard-warmup-not-evidence');
    final row = find
        .ancestor(of: find.text('Peas'), matching: find.byType(InkWell))
        .first;
    Focus.of(
      tester.element(
        find.descendant(of: row, matching: find.byType(Semantics)).first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'food-keyboard-dark-900-row-focused');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'food-keyboard-dark-900-after-space');
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native Food row Actions menu offers Select (dark)', (
    tester,
  ) async {
    await open(tester);
    await pixels.tap(tester, find.byTooltip('Actions for Peas'));
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'food-keyboard-dark-900-actions-menu');
    expect(find.text('Select'), findsOneWidget);
    await pixels.tap(tester, find.text('Select'));
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'food-keyboard-dark-900-menu-selected');
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(FoodInventoryPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
