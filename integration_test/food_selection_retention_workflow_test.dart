import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/food_selection_retention_test.dart'
    show verifyFoodWideSelectionRetention, verifyFoodSearchFocusRetention;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native wide Food filter preserves captured selection until editor closes',
    (tester) => verifyFoodWideSelectionRetention(
      tester,
      capture: (name) => pixels.capture(tester, name),
    ),
  );
  testWidgets(
    'native Food Search keeps keyboard input after pruning to one',
    (tester) => verifyFoodSearchFocusRetention(
      tester,
      typeText: (query) async {
        await tester.runAsync(() async {
          expect(
            (await Process.run('xdotool', [
              'key',
              '--clearmodifiers',
              'ctrl+a',
            ])).exitCode,
            0,
          );
          if (query.isEmpty) {
            expect(
              (await Process.run('xdotool', ['key', 'BackSpace'])).exitCode,
              0,
            );
          } else {
            expect(
              (await Process.run('xdotool', [
                'type',
                '--clearmodifiers',
                '--',
                query,
              ])).exitCode,
              0,
            );
          }
        });
      },
      capture: (name) => pixels.capture(tester, name),
    ),
  );
}
