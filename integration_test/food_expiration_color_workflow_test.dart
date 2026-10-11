import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_expiration_color_workflow_test.dart'
    show verifyFoodExpirationColorWorkflow;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodExpirationColorTests();
}

void registerFoodExpirationColorTests() {
  testWidgets('native Food date colors in Stock and Retained, local-day resume', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(sample.$1, 1200);
        await verifyFoodExpirationColorWorkflow(
          tester,
          brightness: brightness,
          textScale: sample.$2,
          capture: (name) => pixels.capture(
            tester,
            'date-colors-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
          ),
        );
      }
    }
  });
}
