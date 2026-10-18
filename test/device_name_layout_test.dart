import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/device_name_dialog.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final dark in [false, true]) {
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
