import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

Map<String, dynamic> task(String id) => {
  'id': id,
  'title': 'Original $id',
  'description': '',
  'assignee': 'user',
  'tags': <String>[],
  'tagRefs': <String, String>{},
  'schedule': <String, dynamic>{},
};

Future<void> mountHeader(
  WidgetTester tester,
  Widget editor, {
  double width = 420,
  double scale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: editor),
    ),
  );
  await tester.pumpAndSettle();
}

/// Exercise actual keyboard activation and restoration through the Help route.
Future<void> exerciseHelpWithKeyboard(WidgetTester tester, Finder input) async {
  await tester.ensureVisible(input);
  final editable = tester.widget<EditableText>(
    find.descendant(of: input, matching: find.byType(EditableText)),
  );
  editable.focusNode.requestFocus();
  await tester.pumpAndSettle();
  final draft = editable.controller.value;
  final help = find.byTooltip('Task field help');
  await tester.ensureVisible(help);
  final helpFocus = Focus.of(tester.element(find.byIcon(Icons.help_outline)));
  expect(helpFocus.canRequestFocus, isTrue);
  expect(helpFocus.skipTraversal, isFalse);
  helpFocus.requestFocus();
  await tester.pumpAndSettle();
  expect(helpFocus.hasFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.text('Task field help'), findsOneWidget);
  final doneFocus = Focus.of(tester.element(find.text('Done')));
  doneFocus.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.text('Task field help'), findsNothing);
  expect(editable.controller.value, draft);
  expect(editable.focusNode.hasFocus, isTrue);
}

void main() {
  setUpAll(loadSdkRoboto);
  for (final bulk in [false, true]) {
    for (final panel in [true, false]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${bulk ? 'bulk' : 'single'} ${panel ? 'pane' : 'dialog'} header is title and accessible Help at x$scale',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              var writes = 0;
              await mountHeader(
                tester,
                bulk
                    ? BulkTaskEditor(
                        panel: panel,
                        tasks: [task('one'), task('two')],
                        onSave: (_) async {
                          writes++;
                        },
                      )
                    : TaskEditor(
                        panel: panel,
                        task: task('one'),
                        save: (_, _, _) async {
                          writes++;
                        },
                      ),
                width: panel ? 420 : 390,
                scale: scale,
                brightness: panel ? Brightness.dark : Brightness.light,
              );
              final title = find.text(bulk ? 'Edit 2 tasks' : 'Edit task');
              final help = find.byTooltip('Task field help');
              expect(title, findsOneWidget);
              expect(find.text('Clear Selection'), findsNothing);
              expect(find.textContaining(' selected'), findsNothing);
              await tester.ensureVisible(help);
              await tester.pumpAndSettle();
              expect(help.hitTestable(), findsOneWidget);
              expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
              expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
              final data = tester.getSemantics(help).getSemanticsData();
              expect(data.tooltip, 'Task field help');
              expect(data.hasAction(SemanticsAction.tap), isTrue);
              if (scale == 1) {
                expect(
                  tester.getCenter(help).dy,
                  closeTo(tester.getCenter(title).dy, 1),
                );
              }
              expect(
                find.widgetWithText(TextButton, 'Cancel').hitTestable(),
                findsOneWidget,
              );
              expect(writes, 0);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        '${bulk ? 'bulk' : 'single'} ${panel ? 'pane' : 'dialog'} keeps keyboard Help focus and dirty Cancel choices',
        (tester) async {
          var writes = 0, closed = 0;
          await mountHeader(
            tester,
            bulk
                ? BulkTaskEditor(
                    panel: panel,
                    tasks: [task('one'), task('two')],
                    onClose: () => closed++,
                    onSave: (_) async {
                      writes++;
                    },
                  )
                : TaskEditor(
                    panel: panel,
                    task: task('one'),
                    onClose: () => closed++,
                    save: (_, _, _) async {
                      writes++;
                    },
                  ),
            width: panel ? 420 : 390,
          );
          final input = find.byKey(ValueKey(bulk ? 'addTags' : 'title'));
          await tester.ensureVisible(input);
          await tester.enterText(input, 'Retained draft');
          final controller = tester.widget<TextField>(input).controller!;
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 7,
          );
          final draft = controller.value;
          await exerciseHelpWithKeyboard(tester, input);
          expect(controller.value, draft);
          final cancel = find.widgetWithText(TextButton, 'Cancel');
          await tester.ensureVisible(cancel);
          final cancelFocus = Focus.of(tester.element(find.text('Cancel')));
          cancelFocus.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Unsaved changes'), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
          await tester.pumpAndSettle();
          expect(closed, 0);
          expect(writes, 0);
          expect(controller.value, draft);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
          expect(closed, 1);
          expect(writes, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
