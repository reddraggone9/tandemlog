import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final keyboardArrivesAfterReview in [false, true]) {
      testWidgets(
        'checklist review reveals whole title and explanation above keyboard at320dp200percent transition=$keyboardArrivesAfterReview $brightness',
        (tester) async {
          // Native IME includes the navigation-bar region: 960 - 538 = 422px.
          const keyboard = 422 / 1.5;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          tester.view.viewInsets = FakeViewPadding(
            bottom: keyboardArrivesAfterReview ? 0 : keyboard,
          );
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
          tester.view.padding = const FakeViewPadding(top: 24);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(() {
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
            tester.view.resetViewInsets();
            tester.view.resetViewPadding();
            tester.view.resetPadding();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
          });
          final saved = <(String, String)>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                platform: TargetPlatform.android,
                brightness: brightness,
                fontFamily: 'Roboto',
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => ChecklistItemEditor(
                        save: (title, notes) async {
                          saved.add((title, notes));
                        },
                        onClose: () => Navigator.pop(dialogContext),
                      ),
                    ),
                    child: const Text('Open checklist'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open checklist'));
          await tester.pumpAndSettle();
          final title = find.byKey(const Key('checklist-item-title'));
          final action = find.byKey(const Key('checklist-item-save'));
          final beforeReview = tester.getRect(action);
          expect(tester.widget<TextField>(title).decoration!.errorText, isNull);
          await tester.tap(action);
          await tester.pumpAndSettle();
          if (keyboardArrivesAfterReview) {
            await tester.pump(const Duration(milliseconds: 150));
            tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
            await tester.pumpAndSettle();
          }
          final before = tester.getRect(action);
          if (!keyboardArrivesAfterReview) {
            expect(before, beforeReview);
          }
          final error = find.text('Enter a checklist item title.');
          expect(error, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: error, matching: find.byType(RichText)),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          final clip = RenderAbstractViewport.of(paragraph) as RenderBox;
          Rect globalRect(RenderBox box) => MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
          final clipRect = globalRect(clip);
          final errorRect = globalRect(paragraph);
          final decorator = tester.renderObject<RenderBox>(
            find.descendant(of: title, matching: find.byType(InputDecorator)),
          );
          final inputRect = globalRect(decorator);
          expect(errorRect.top, greaterThanOrEqualTo(clipRect.top));
          expect(
            errorRect.bottom,
            lessThanOrEqualTo(clipRect.bottom),
            reason:
                'Every line of the local explanation must clear the fixed actions',
          );
          expect(
            inputRect.top,
            greaterThanOrEqualTo(clipRect.top),
            reason:
                'Review must show the whole input as well as its explanation',
          );
          expect(inputRect.bottom, lessThanOrEqualTo(clipRect.bottom));
          final editable = tester.widget<EditableText>(
            find.descendant(of: title, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(tester.view.viewInsets.bottom, keyboard);
          expect(tester.getRect(action), before);
          expect(action.hitTestable(), findsOneWidget);
          expect(
            find.byKey(const Key('checklist-item-cancel')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(640 - keyboard),
          );
          expect(saved, isEmpty);
          await tester.enterText(title, 'Synthetic item');
          await tester.pumpAndSettle();
          expect(tester.getRect(action), before);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(saved, isEmpty, reason: 'Corrected Review cannot become Save');
          expect(
            find.descendant(of: action, matching: find.text('Save item')),
            findsOneWidget,
          );
          expect(tester.getRect(action), before);
          expect(tester.view.viewInsets.bottom, keyboard);
          expect(
            tester.widget<TextField>(title).controller!.text,
            'Synthetic item',
          );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(saved, [('Synthetic item', '')]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
