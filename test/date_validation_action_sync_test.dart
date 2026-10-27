import 'package:tandemlog/presentation/civil_date_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/task_editor.dart';

import 'food_editor_pane_test.dart' as food;

Finder get _action => find.descendant(
  of: find.byType(ValidationActionButton),
  matching: find.byType(FilledButton),
);
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _chooseDate(WidgetTester tester, String label) async {
  await _tap(tester, find.byTooltip('Choose $label'));
  await tester.tap(find.text('12').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Food Add another blank calendar selection restores Add without Review',
    (tester) async {
      var writes = 0;
      await food.mountFoodPane(tester, height: 1000, onAdd: (_, _) => writes++);
      await _tap(tester, find.byTooltip('Actions for Pane beans 1'));
      await _tap(
        tester,
        find.widgetWithText(PopupMenuItem<String>, 'Add another…'),
      );
      final expiry = food.foodField('Expiration');
      expect(food.controller(tester, 'Expiration').text, isEmpty);
      expect(tester.widget<TextField>(expiry).focusNode!.hasFocus, isTrue);
      await _tap(tester, find.byTooltip('Choose Expiration'));
      // Opening the calendar settles the focused blank field, exposing its issue.
      final validation = tester
          .widget<ValidationActionButton>(find.byType(ValidationActionButton))
          .validation;
      expect(validation.reviewRequired, isTrue);
      expect(writes, 0);
      await tester.tap(find.text('12').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(expiry).decoration!.errorText, isNull);
      expect(find.text('Review errors'), findsNothing);
      expect(
        find.descendant(of: _action, matching: find.text('Add')),
        findsOneWidget,
      );
      expect(writes, 0);
      await _tap(tester, _action);
      expect(writes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in ['Add', 'Add another', 'Edit']) {
    testWidgets('Food $mode calendar correction immediately restores action', (
      tester,
    ) async {
      var writes = 0;
      await food.mountFoodPane(
        tester,
        height: 1000,
        onAdd: (_, _) => writes++,
        onDetails: (_, _, _) => writes++,
      );
      if (mode == 'Add') {
        await food.openPaneAdd(tester);
        await tester.enterText(food.foodField('Food name'), 'Trial beans');
      } else if (mode == 'Edit') {
        await _tap(tester, find.text('Pane beans 1'));
      } else {
        await _tap(tester, find.byTooltip('Actions for Pane beans 1'));
        await _tap(
          tester,
          find.widgetWithText(PopupMenuItem<String>, 'Add another…'),
        );
      }
      final field = food.foodField('Expiration');
      await _tap(tester, field);
      await tester.enterText(field, 'bad');
      await _tap(tester, _action);
      expect(writes, 0);
      expect(find.text('Review errors'), findsOneWidget);
      final original = food.controller(tester, 'Expiration').value;
      await _tap(tester, find.byTooltip('Choose Expiration'));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(CivilDatePickerDialog),
          matching: find.text('Cancel'),
        ),
      );
      expect(food.controller(tester, 'Expiration').value.text, original.text);
      expect(find.text('Review errors'), findsOneWidget);
      expect(writes, 0);
      await _chooseDate(tester, 'Expiration');
      expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
      expect(
        find.text('Review errors'),
        findsNothing,
        reason:
            'A calendar-confirmed correction must not require a blur/review.',
      );
      expect(writes, 0);
      await _tap(tester, _action);
      expect(writes, 1, reason: 'The first corrected Add/Save writes once.');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final bulk in [false, true]) {
    for (final key in [
      'startDate',
      'dueDate',
      'scheduledDate',
      'startTime',
      'dueTime',
      'scheduledTime',
    ]) {
      testWidgets(
        'Task $bulk $key correction synchronizes action before blur',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1000, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var writes = 0;
          final task = <String, dynamic>{
            'id': 'synthetic-one',
            'title': 'Trial task',
            'description': '',
            'tags': <String>[],
            'schedule': <String, dynamic>{
              if (key.startsWith('scheduled')) ...{
                'dueDate': '2026-10-12',
                'recurrence': 'every day',
                'scheduledDate': '2026-10-12',
              },
              if (key.endsWith('Time'))
                key.replaceFirst('Time', 'Date'): '2026-10-12',
            },
          };
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: bulk
                    ? BulkTaskEditor(
                        panel: true,
                        tasks: [
                          task,
                          {...task, 'id': 'synthetic-two'},
                        ],
                        onSave: (_) async {
                          writes++;
                        },
                      )
                    : TaskEditor(
                        panel: true,
                        task: task,
                        save: (_, _, _) async {
                          writes++;
                        },
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final input = find.byKey(ValueKey(key));
          final valid = key.endsWith('Date') ? '2026-10-12' : '12:34';
          await _tap(tester, input);
          await tester.enterText(input, 'bad');
          await _tap(tester, _action);
          expect(writes, 0);
          expect(find.text('Review errors'), findsOneWidget);
          final controller = tester.widget<TextField>(input).controller!;
          final focus = tester.widget<TextField>(input).focusNode!;
          focus.requestFocus();
          await tester.pumpAndSettle();
          // A controller notification is the common boundary for typed values,
          // calendar selection, clear actions and other programmatic changes.
          controller.text = valid;
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(tester.widget<TextField>(input).decoration!.errorText, isNull);
          expect(find.text('Review errors'), findsNothing);
          expect(writes, 0);
          await _tap(tester, _action);
          expect(writes, 1);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
