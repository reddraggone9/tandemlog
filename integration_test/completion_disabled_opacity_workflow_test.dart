import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';

import 'fixtures/task_completion_checkbox_before.dart' as before;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('disabled repeat uses uniform native opacity in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        for (final historical in [true, false]) {
          final boundary = GlobalKey();
          final name =
              'repeat-${brightness.name}-${scale.toInt()}x-${historical ? 'before' : 'after'}';
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(name),
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RepaintBoundary(
                        key: boundary,
                        child: historical
                            ? const before.TaskCompletionCheckbox(
                                value: false,
                                repeating: true,
                                onChanged: null,
                              )
                            : const TaskCompletionCheckbox(
                                value: false,
                                repeating: true,
                                onChanged: null,
                              ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(child: Text('Unavailable repeat')),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (brightness == Brightness.dark && scale == 1 && historical) {
            await pixels.capture(tester, 'repeat-warmup-not-evidence');
          }
          await pixels.capture(tester, name);
          final maximumAlpha = await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 4);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            image.dispose();
            var maximum = 0;
            final rgba = bytes!.buffer.asUint8List();
            for (var i = 3; i < rgba.length; i += 4) {
              if (rgba[i] > maximum) maximum = rgba[i];
            }
            return maximum;
          });
          expect(
            maximumAlpha,
            historical ? greaterThan(99) : inInclusiveRange(90, 99),
          );
          expect(tester.getSize(find.byType(Checkbox)), const Size(48, 48));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
