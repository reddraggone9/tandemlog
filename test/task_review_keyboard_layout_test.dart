import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/editor_surface.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final retainInputFocus in [false, true]) {
    for (final kind
        in retainInputFocus
            ? [PointerDeviceKind.touch]
            : [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets(
        'first Task review retains target and reveals whole invalid time with Android keyboard for $kind retained=$retainInputFocus',
        (tester) async {
          const keyboard = 422 / 1.5;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
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
          var saves = 0, deletes = 0, closes = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                platform: TargetPlatform.android,
                fontFamily: 'Roboto',
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              home: Scaffold(
                resizeToAvoidBottomInset: true,
                body: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(
                        height: 66,
                        child: Center(child: Text('Synthetic Tasks')),
                      ),
                      Expanded(
                        child: EditorSurface(
                          list: const SizedBox(),
                          panel: false,
                          editor: TaskEditor(
                            task: {
                              'kind': 'task',
                              'id': 'synthetic-review',
                              'title': 'Synthetic recurring task',
                              'description': '',
                              'assignee': 'a',
                              'tags': <String>[],
                              'tagRefs': <String, String>{},
                              'schedule': <String, dynamic>{
                                'startDate': '2026-10-01',
                                'dueDate': '2026-10-20',
                                'dueTime': '12:30',
                                'scheduledDate': '2026-10-21',
                                'scheduledTime': '09:30',
                                'recurrence': 'every week',
                                'dueMinDays': 0,
                              },
                            },
                            users: const [
                              {'id': 'a', 'name': 'Synthetic user'},
                            ],
                            onClose: () {
                              closes++;
                            },
                            onDelete: () async {
                              deletes++;
                            },
                            save: (_, _, _) async {
                              saves++;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final dueTime = find.byKey(const ValueKey('dueTime'));
          await tester.ensureVisible(dueTime);
          await tester.enterText(dueTime, '-1');
          await tester.pumpAndSettle();
          final editable = tester.widget<EditableText>(
            find.descendant(of: dueTime, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          expect(
            tester.widget<TextField>(dueTime).decoration!.errorText,
            isNull,
          );
          final action = find.descendant(
            of: find.byType(ValidationActionButton),
            matching: find.byType(FilledButton),
          );
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(action);
          final actionElement = tester.element(action);
          expect(
            editable.focusNode.hasFocus,
            isTrue,
            reason: 'Scrolling the form must retain the existing input focus',
          );
          final gesture = await tester.startGesture(bounds.center, kind: kind);
          if (!retainInputFocus) editable.focusNode.unfocus();
          await tester.pump(const Duration(milliseconds: 200));
          if (retainInputFocus) {
            expect(
              editable.focusNode.hasFocus,
              isTrue,
              reason:
                  'Scrolling to actions keeps the actual Due time focus; Review must scroll upward without a focus transition.',
            );
          }
          expect(
            tester.getRect(action),
            bounds,
            reason: 'A held first gesture must keep its entire painted target',
          );
          expect(tester.element(action), same(actionElement));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(saves, 0);
          expect(deletes, 0);
          expect(closes, 0);
          expect(
            editable.focusNode.hasFocus,
            isTrue,
            reason: 'The first gesture must focus the actual invalid Due time',
          );
          expect(tester.view.viewInsets.bottom, keyboard);
          expect(tester.widget<TextField>(dueTime).controller!.text, '-1');
          final errorText = tester
              .widget<TextField>(dueTime)
              .decoration!
              .errorText;
          expect(errorText, isNotEmpty);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(errorText!),
              matching: find.byType(RichText),
            ),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          final clip = RenderAbstractViewport.of(paragraph) as RenderBox;
          Rect globalRect(RenderBox box) => MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
          final clipRect = globalRect(clip);
          final errorRect = globalRect(paragraph);
          final inputRect = globalRect(
            tester.renderObject<RenderBox>(
              find.descendant(
                of: dueTime,
                matching: find.byType(InputDecorator),
              ),
            ),
          );
          expect(errorRect.top, greaterThanOrEqualTo(clipRect.top));
          expect(errorRect.bottom, lessThanOrEqualTo(clipRect.bottom));
          expect(inputRect.top, greaterThanOrEqualTo(clipRect.top));
          expect(inputRect.bottom, lessThanOrEqualTo(clipRect.bottom));
          // The floating label paints above the field's layout box. Checking
          // only the InputDecorator misses a clipped first line at scroll top.
          final timeLabel = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.descendant(of: dueTime, matching: find.text('Time')),
              matching: find.byType(RichText),
            ),
          );
          final labelRect = globalRect(timeLabel);
          expect(timeLabel.didExceedMaxLines, isFalse);
          expect(
            labelRect.top,
            greaterThanOrEqualTo(clipRect.top),
            reason:
                'The actual painted floating Time label must clear the scroll clip',
          );
          expect(labelRect.bottom, lessThanOrEqualTo(clipRect.bottom));
          expect(labelRect.left, greaterThanOrEqualTo(clipRect.left));
          expect(labelRect.right, lessThanOrEqualTo(clipRect.right));
          expect(clipRect.bottom, lessThanOrEqualTo(640 - keyboard));
          expect(find.text('Review errors'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
