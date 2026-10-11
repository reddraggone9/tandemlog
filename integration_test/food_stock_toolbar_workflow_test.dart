import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_stock_toolbar_workflow_test.dart'
    show verifyFoodStockToolbarWorkflow;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodStockToolbarTests();
}

void registerFoodStockToolbarTests() {
  testWidgets('native combined Food Stock and scoped toolbar Filter', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recording = Platform.environment['FOOD_PREVIEW_RECORD'] == '1';
    for (final brightness
        in recording ? [Brightness.dark] : Brightness.values) {
      for (final sample
          in recording ? [(1200.0, 1.0)] : [(1200.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(sample.$1, recording ? 850 : 1200);
        await verifyFoodStockToolbarWorkflow(
          tester,
          brightness: brightness,
          textScale: sample.$2,
          input: (target) => pixels.tap(tester, target),
          capture: (name) async {
            await pixels.capture(
              tester,
              'stock-toolbar-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
            );
            if (recording && name == 'stock-inbox') {
              await pixels.startRecording(tester);
            }
          },
        );
      }
    }
  });
}
