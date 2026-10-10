import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_expiry_guidance_test.dart'
    show verifyExpiryGuidanceWorkflow;
import '../tool/food_preview.dart';
import 'food_preview_workflow_test.dart' as pixels;

void registerFoodExpiryGuidanceTests() {
  testWidgets('native 320dp expiry guidance at 100/200% in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'expiry-warmup-not-evidence');
    await pixels.startRecording(tester);
    tester.view.physicalSize = const Size(320, 640);
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        await verifyExpiryGuidanceWorkflow(
          tester,
          brightness: brightness,
          textScale: scale,
          capture: (name) => pixels.capture(tester, 'expiry-$name'),
          input: (target) => pixels.tap(tester, target),
        );
      }
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodExpiryGuidanceTests();
}
