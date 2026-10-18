import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/device_name_dialog.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final dark in [false, true]) {
    testWidgets(
      'Device name input survives phone keyboard arrival at320x568200percent, dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<DeviceNameChange>(
                    context: context,
                    builder: (_) =>
                        const DeviceNameDialog(name: 'Kitchen tablet'),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        // Actual API30 phone: 320x568 app viewport after system bars. The IME
        // arrives after autofocus and takes 234 logical pixels.
        tester.view.viewInsets = const FakeViewPadding(bottom: 234);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('device-name-field'));
        final scroll = find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first;
        final viewport = tester.getRect(scroll), input = tester.getRect(field);
        expect(input.top, greaterThanOrEqualTo(viewport.top - .01));
        expect(input.bottom, lessThanOrEqualTo(viewport.bottom + .01));
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        final action = find.byKey(const ValueKey('device-name-save'));
        final before = tester.getRect(action);
        expect(before.bottom, lessThanOrEqualTo(334));
        await tester.enterText(field, 'x' * 81);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Review errors'), findsOneWidget);
        expect(tester.getRect(action), before);
        final error = find.text(
          'Use up to 80 characters without control characters.',
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: error, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final errorRect = tester.getRect(error),
            visible = tester.getRect(scroll);
        expect(errorRect.top, greaterThanOrEqualTo(visible.top - .01));
        expect(errorRect.bottom, lessThanOrEqualTo(visible.bottom + .01));
        final decorated = tester.getRect(field);
        expect(decorated.top, greaterThanOrEqualTo(visible.top - .01));
        expect(decorated.bottom, lessThanOrEqualTo(visible.bottom + .01));
        await tester.enterText(field, 'Corrected label');
        await tester.pumpAndSettle();
        expect(tester.getRect(action), before);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(DeviceNameDialog), findsOneWidget);
        expect(tester.getRect(action), before);
        final corrected = tester.getRect(field);
        final correctedViewport = tester.getRect(scroll);
        expect(
          corrected.top,
          greaterThanOrEqualTo(correctedViewport.top - .01),
        );
        expect(
          corrected.bottom,
          lessThanOrEqualTo(correctedViewport.bottom + .01),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Device name full error and stable action at390px200percent keyboard, dark=$dark',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 900);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<DeviceNameChange>(
                    context: context,
                    builder: (_) => const DeviceNameDialog(name: null),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('device-name-field'));
        final action = find.byKey(const ValueKey('device-name-save'));
        final before = tester.getRect(action), element = tester.element(action);
        await tester.enterText(field, 'x' * 81);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Review errors'), findsOneWidget);
        expect(tester.getRect(action), before);
        expect(identical(tester.element(action), element), isTrue);
        final message = find.text(
          'Use up to 80 characters without control characters.',
        );
        expect(message, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: message, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final error = tester.getRect(message);
        expect(error.top, greaterThanOrEqualTo(0));
        expect(error.bottom, lessThanOrEqualTo(before.top));
        expect(before.bottom, lessThanOrEqualTo(600));
        await tester.enterText(field, 'Corrected label');
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(DeviceNameDialog), findsOneWidget);
        expect(tester.getRect(action), before);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      },
    );
  }
}
