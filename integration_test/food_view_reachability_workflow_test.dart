import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/inventory.dart';

import '../test/food_view_reachability_test.dart'
    show verifyFoodViewReachability;
import '../tool/food_preview.dart';
import 'food_preview_workflow_test.dart' as pixels;

void registerFoodViewReachabilityTests() {
  testWidgets('native Food views remain reachable by swiping at large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await pixels.capture(tester, 'reachability-warmup-not-evidence');
    await pixels.startRecording(tester);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    // Exercise the exact rejected layout first so RED captures its pixels.
    await verifyFoodViewReachability(
      tester,
      brightness: Brightness.dark,
      textScale: 2,
      mode: FoodView.inbox,
      capture: (name) => pixels.capture(tester, 'reachability-$name'),
      input: (target) => pixels.tap(tester, target),
    );
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        for (final mode in FoodView.values) {
          for (final withError in [false, true]) {
            if (brightness == Brightness.dark &&
                scale == 2 &&
                mode == FoodView.inbox &&
                !withError) {
              continue;
            }
            await verifyFoodViewReachability(
              tester,
              brightness: brightness,
              textScale: scale,
              mode: mode,
              withError: withError,
              capture: (name) => pixels.capture(tester, 'reachability-$name'),
              input: (target) => pixels.tap(tester, target),
            );
          }
          if (scale == 2) {
            await verifyFoodViewReachability(
              tester,
              brightness: brightness,
              textScale: scale,
              mode: mode,
              empty: true,
              capture: (name) => pixels.capture(tester, 'reachability-$name'),
              input: (target) => pixels.tap(tester, target),
            );
          }
        }
      }
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodViewReachabilityTests();
}
