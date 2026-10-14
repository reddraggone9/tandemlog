import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import '../tool/food_preview.dart';
import 'food_density_workflow_test.dart' show densityFixture;
import 'food_preview_workflow_test.dart' as pixels;

Future<void> activateWithKeyboard(
  WidgetTester tester,
  Finder control, {
  bool backwards = false,
}) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  final icons = find.descendant(of: control, matching: find.byType(Icon));
  final focus = Focus.of(
    tester.element(icons.evaluate().isEmpty ? control : icons.first),
  );
  final label = control.toString();
  for (var step = 0; step < 60 && !focus.hasPrimaryFocus; step++) {
    if (backwards) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (backwards) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pumpAndSettle();
    if (control.evaluate().isEmpty) {
      debugPrint(
        'FOOD_INSPECT_FOCUS target=$label step=$step '
        'primary=${FocusManager.instance.primaryFocus?.debugLabel} '
        'originalPrimary=${focus.hasPrimaryFocus} '
        'visibleTooltips=${find.byType(Tooltip).evaluate().map((e) => (e.widget as Tooltip).message).toList()}',
      );
      await pixels.capture(tester, 'inspect-traversal-diagnostic');
      break;
    }
  }
  expect(
    focus.hasPrimaryFocus,
    isTrue,
    reason: 'Control reachable through Tab',
  );
  expect(control, findsOneWidget, reason: 'Focused target remains mounted');
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Flat rows expose metadata, keyboard editing and independent menus with Back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        FoodPreviewApp(initialOperations: densityFixture()),
      );
      await tester.pumpAndSettle();
      await pixels.capture(tester, 'inspect-warmup-not-evidence');
      for (final width in [390.0, 1200.0]) {
        for (final scale in [1.0, 2.0]) {
          final name = 'inspect-dark-${scale.toInt()}x-${width.toInt()}';
          tester.view.physicalSize = Size(width, 850);
          await tester.pumpWidget(
            FoodPreviewApp(
              key: ValueKey(name),
              initialOperations: densityFixture(),
              textScale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final before = tester
              .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
              .state
              .containers
              .map((e) => e.toJson())
              .toList();
          final row = find.text('Oat milk');
          final card = find.ancestor(of: row, matching: find.byType(Card));
          final metadata = find.descendant(
            of: card,
            matching: find.text('500 g · Freezer'),
          );
          expect(metadata.hitTestable(), findsOneWidget);
          expect(find.text('Remaining contents'), findsNothing);
          final actions = find.byTooltip('Actions for Oat milk');
          await activateWithKeyboard(tester, actions);
          expect(find.text('Add another…').hitTestable(), findsOneWidget);
          expect(find.text('Remove 1 container').hitTestable(), findsOneWidget);
          expect(find.text('Edit group details'), findsNothing);
          await pixels.capture(tester, '$name-actions');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(metadata.hitTestable(), findsOneWidget);
          await activateWithKeyboard(tester, row, backwards: true);
          expect(find.text('Edit 1 container'), findsOneWidget);
          final size = find.widgetWithText(TextField, 'Container size');
          final location = find.widgetWithText(TextField, 'Location');
          expect(tester.widget<TextField>(size).controller!.text, '500 g');
          expect(
            tester.widget<TextField>(location).controller!.text,
            'Freezer',
          );
          await tester.ensureVisible(location);
          await tester.pumpAndSettle();
          expect(location.hitTestable(), findsOneWidget);
          await pixels.capture(tester, '$name-editor');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(metadata.hitTestable(), findsOneWidget);
          expect(actions, findsOneWidget);
          final state = tester
              .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
              .state;
          expect(state.containers.map((e) => e.toJson()).toList(), before);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
