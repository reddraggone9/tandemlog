import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_group_action_geometry_test.dart'
    show verifyFoodGroupActionGeometry;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodGroupActionGeometryTests();
}

void registerFoodGroupActionGeometryTests() {
  testWidgets('native Food group controls keep header anchors and date width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final brightness in Brightness.values) {
      for (final sample in [(1200.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(sample.$1, 1200);
        await verifyFoodGroupActionGeometry(
          tester,
          brightness: brightness,
          textScale: sample.$2,
          input: (target) => pixels.tap(tester, target),
          capture: (name) => pixels.capture(
            tester,
            'group-actions-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
          ),
        );
      }
    }
  });
}
