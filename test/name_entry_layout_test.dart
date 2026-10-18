import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/name_entry_dialog.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final dark in [false, true]) {
    testWidgets(
      'Add user input survives phone keyboard arrival at320x568200percent, dark=$dark',
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
        String? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => result = await showDialog<String>(
                    context: context,
                    builder: (_) => const NameEntryDialog(
                      title: 'Who is using Tandemlog?',
                      label: 'Name',
                    ),
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
        final field = find.byType(TextField);
        final scroll = find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first;
        final viewport = tester.getRect(scroll), input = tester.getRect(field);
        expect(input.top, greaterThanOrEqualTo(viewport.top - .01));
        expect(input.bottom, lessThanOrEqualTo(viewport.bottom + .01));
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        final action = find.byType(FilledButton);
        final before = tester.getRect(action);
        expect(before.bottom, lessThanOrEqualTo(334));
        tester.widget<TextField>(field).controller!.text = 'x' * 101;
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('Review errors'), findsOneWidget);
        expect(tester.getRect(action), before);
        final error = find.text('Name must be 100 characters or fewer.');
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
        expect(find.text('Review errors'), findsNothing);
        expect(
          result,
          isNull,
          reason: 'Correction itself cannot create a user.',
        );
        expect(find.byType(NameEntryDialog), findsOneWidget);
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
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(NameEntryDialog), findsNothing);
        expect(result, 'Corrected label');
      },
    );
  }
}
