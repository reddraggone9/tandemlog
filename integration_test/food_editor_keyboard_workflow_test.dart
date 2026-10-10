import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/food_editor_keyboard_layout_test.dart'
    show verifyFoodEditorKeyboardLayout;
import '../tool/food_preview.dart';
import 'food_preview_workflow_test.dart' as pixels;

void registerFoodEditorKeyboardTests() {
  testWidgets('native Food editor title/form/IME/error layout matrix', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'keyboard-warmup-not-evidence');
    await pixels.startRecording(tester);
    tester.view.physicalSize = const Size(320, 640);
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        for (final count in [0, 1, 100]) {
          await verifyFoodEditorKeyboardLayout(
            tester,
            brightness: brightness,
            textScale: scale,
            editingCount: count,
            capture: (name) => pixels.capture(tester, 'keyboard-$name'),
            input: (target) => pixels.tap(tester, target),
          );
        }
      }
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodEditorKeyboardTests();
}
