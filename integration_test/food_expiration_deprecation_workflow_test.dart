import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_expiration_deprecation_test.dart'
    show verifyExpirationDeprecationWorkflow;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodExpirationDeprecationTests();
}

void registerFoodExpirationDeprecationTests() {
  testWidgets('native date-only Food editing preserves mixed legacy certainty', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(sample.$1, 850);
        await verifyExpirationDeprecationWorkflow(
          tester,
          brightness: brightness,
          textScale: sample.$2,
          capture: (name) => pixels.capture(
            tester,
            'date-only-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
          ),
          input: (target) => pixels.tap(tester, target),
        );
      }
    }
  });
}
