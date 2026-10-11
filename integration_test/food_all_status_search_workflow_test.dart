import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_all_status_search_workflow_test.dart'
    show verifyFoodAllStatusSearch;
import 'food_preview_workflow_test.dart' as pixels;
import 'food_production_workflow_test.dart' show registerFoodProductionTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodAllStatusSearchTests();
  registerFoodProductionTests();
}

void registerFoodAllStatusSearchTests() {
  testWidgets(
    'native all-status Food search pins Deleted and moves restored/removed rows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recording = Platform.environment['FOOD_PREVIEW_RECORD'] == '1';
      for (final brightness
          in recording ? [Brightness.dark] : Brightness.values) {
        for (final sample
            in recording ? [(900.0, 1.0)] : [(900.0, 1.0), (320.0, 2.0)]) {
          tester.view.physicalSize = Size(sample.$1, recording ? 850 : 1000);
          await verifyFoodAllStatusSearch(
            tester,
            brightness: brightness,
            textScale: sample.$2,
            input: (finder) => pixels.tap(tester, finder),
            capture: (name) async {
              if (recording && name == 'mixed-active') {
                await pixels.startRecording(tester);
              }
              await pixels.capture(
                tester,
                'food-search-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
              );
            },
          );
        }
      }
    },
  );
}
