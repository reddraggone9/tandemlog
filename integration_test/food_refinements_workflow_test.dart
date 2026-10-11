import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/food_value_autocomplete_workflow_test.dart'
    show verifyFoodValueAutocomplete;
import '../test/food_field_filter_workflow_test.dart'
    show verifyFoodFieldFilters;
import '../test/food_bulk_details_workflow_test.dart'
    show verifyFoodBulkDetails;
import '../test/date_input_alignment_workflow_test.dart'
    show verifyDateInputAlignment;
import 'food_preview_workflow_test.dart' as pixels;
import 'food_group_action_geometry_workflow_test.dart'
    show registerFoodGroupActionGeometryTests;
import 'food_undo_stack_workflow_test.dart'
    show registerFoodUndoStackWorkflowTests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodRefinementTests();
  registerFoodGroupActionGeometryTests();
  registerFoodUndoStackWorkflowTests();
}

void registerFoodRefinementTests() {
  testWidgets(
    'native Food autocomplete filters bulk fields and shared date inset',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final recording = Platform.environment['FOOD_PREVIEW_RECORD'] == '1';
      var captureWarmed = false;
      for (final brightness
          in recording ? [Brightness.dark] : Brightness.values) {
        for (final sample
            in recording ? [(900.0, 1.0)] : [(900.0, 1.0), (320.0, 2.0)]) {
          tester.view.physicalSize = Size(sample.$1, recording ? 850 : 1100);
          final prefix =
              'food-refinements-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x';
          Future<void> capture(String flow, String name) async {
            if (!captureWarmed) {
              await pixels.capture(
                tester,
                'food-refinements-warmup-not-evidence',
              );
              captureWarmed = true;
            }
            if (recording && flow == 'bulk' && name == 'mixed-untouched') {
              await pixels.startRecording(tester);
            }
            await pixels.capture(tester, '$prefix-$flow-$name');
          }

          await verifyFoodValueAutocomplete(
            tester,
            brightness: brightness,
            textScale: sample.$2,
            input: (target) => pixels.tap(tester, target),
            capture: (name) => capture('autocomplete', name),
          );
          await verifyFoodFieldFilters(
            tester,
            brightness: brightness,
            textScale: sample.$2,
            input: (target) => pixels.tap(tester, target),
            capture: (name) => capture('filters', name),
          );
          await verifyFoodBulkDetails(
            tester,
            brightness: brightness,
            textScale: sample.$2,
            input: (target) => pixels.tap(tester, target),
            capture: (name) => capture('bulk', name),
          );
          await verifyDateInputAlignment(
            tester,
            brightness: brightness,
            textScale: sample.$2,
            capture: (name) => capture('date', name),
          );
        }
      }
    },
  );
}
