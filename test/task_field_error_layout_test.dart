import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  for (final scale in [1.0, 2.0]) {
    testWidgets('Task time explanation wraps completely in420pane at${scale}x', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Roboto',
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(420, 1000),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: TaskEditor(
                panel: true,
                task: {
                  'id': 'synthetic',
                  'kind': 'task',
                  'title': 'Synthetic task',
                  'description': '',
                  'tags': <String>[],
                  'tagRefs': <String, String>{},
                  'schedule': {
                    'startDate': '2026-10-01',
                    'dueDate': '2026-10-20',
                  },
                },
                onClose: () {},
                save: (_, _, _) async {
                  saves++;
                },
              ),
            ),
          ),
        ),
      );
      final time = find.byKey(const ValueKey('startTime'));
      await tester.ensureVisible(time);
      await tester.enterText(time, '-1');
      tester
          .widget<TextField>(find.byKey(const ValueKey('dueDate')))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      final explanation = find.text('Start time must be HH:mm.');
      await tester.ensureVisible(explanation);
      await tester.pumpAndSettle();
      expect(explanation, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: explanation, matching: find.byType(RichText)),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason:
            'Native narrow Time error must include the required HH:mm format.',
      );
      expect(find.text('Review errors'), findsOneWidget);
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(tester.widget<TextField>(time).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
