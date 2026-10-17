import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/task_editor.dart';

const _noticeKey = ValueKey('occurrence-prerequisite-notice');
Finder _input(String field) => find.byKey(ValueKey(field));
Finder _apply(String field) => find.byKey(ValueKey('${field}Apply'));
Finder get _action => find.descendant(
  of: find.byType(ValidationActionButton),
  matching: find.byType(FilledButton),
);
TextEditingController _controller(WidgetTester tester, String field) =>
    tester.widget<TextField>(_input(field)).controller!;

Map<String, dynamic> _task(
  String id, {
  Map<String, dynamic> schedule = const {},
}) => {
  'kind': 'task',
  'id': id,
  'title': 'Synthetic prerequisite $id',
  'description': '',
  'assignee': 'a',
  'tags': <String>[],
  'tagRefs': <String, String>{},
  'schedule': <String, dynamic>{
    'startDate': '2026-10-15',
    'dueDate': '2026-10-20',
    'recurrence': 'every week',
    'scheduledDate': '2026-10-21',
    'scheduledTime': '10:15',
    'timeZone': 'UTC',
    'dueMinDays': 1,
    'dueMaxDays': 20,
    ...schedule,
  },
};

Future<void> _mount(
  WidgetTester tester, {
  bool bulk = false,
  List<Map<String, dynamic>>? tasks,
  Future<void> Function(Map<String, dynamic>, List<String>, List<String>)? save,
  Future<void> Function(BulkTaskEdit)? saveBulk,
  VoidCallback? close,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final rows = tasks ?? [_task('first'), _task('second')];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: bulk
            ? BulkTaskEditor(
                panel: true,
                tasks: rows,
                onClose: close ?? () {},
                onSave: saveBulk ?? (_) async {},
              )
            : TaskEditor(
                panel: true,
                task: rows.first,
                onClose: close ?? () {},
                save: save ?? (_, _, _) async {},
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester, String field, String text) async {
  await tester.ensureVisible(_input(field));
  await tester.enterText(_input(field), text);
  await tester.pump();
}

Future<void> _blur(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(_action);
  await tester.tap(_action);
  await tester.pumpAndSettle();
}

void _occurrence(WidgetTester tester, String date, String time) {
  expect(_input('scheduledDate'), findsOneWidget);
  expect(_input('scheduledTime'), findsOneWidget);
  expect(_controller(tester, 'scheduledDate').text, date);
  expect(_controller(tester, 'scheduledTime').text, time);
}

void main() {
  for (final removed in ['dueDate', 'recurrence']) {
    final originalValue = removed == 'dueDate' ? '2026-10-20' : 'every week';
    testWidgets(
      'single $removed empty is settled on blur; re-adding restores precise occurrence',
      (tester) async {
        final original = _task('first');
        final raw = jsonEncode(original);
        var writes = 0;
        await _mount(
          tester,
          tasks: [original],
          save: (_, _, _) async {
            writes++;
          },
        );
        final date = _controller(tester, 'scheduledDate');
        final time = _controller(tester, 'scheduledTime');
        await _edit(tester, removed, '');
        expect(
          date.text,
          '2026-10-21',
          reason: 'Transient empty typing does not clear an occurrence',
        );
        expect(time.text, '10:15');
        expect(find.byKey(_noticeKey), findsNothing);
        await _blur(tester);
        _occurrence(tester, '', '');
        expect(find.byKey(_noticeKey), findsOneWidget);
        expect(writes, 0);
        expect(jsonEncode(original), raw);
        await _edit(tester, removed, originalValue);
        await _blur(tester);
        _occurrence(tester, '2026-10-21', '10:15');
        expect(find.byKey(_noticeKey), findsOneWidget);
        expect(find.textContaining('Removal cancelled'), findsOneWidget);
        expect(jsonEncode(original), raw);
        expect(writes, 0);
      },
    );

    testWidgets(
      'single $removed first Save shows clear notice before writing',
      (tester) async {
        final writes = <Map<String, dynamic>>[];
        await _mount(
          tester,
          save: (fields, _, _) async {
            writes.add(fields);
          },
        );
        await _edit(tester, removed, '');
        await _save(tester);
        expect(
          writes,
          isEmpty,
          reason: 'A Save that first clears dependent values is review only',
        );
        _occurrence(tester, '', '');
        expect(
          find.byKey(_noticeKey).hitTestable(),
          findsOneWidget,
          reason: 'The user must see the clear notice before a second Save',
        );
        await _save(tester);
        expect(writes, hasLength(1));
        final schedule = writes.single['schedule'] as Map;
        expect(schedule[removed], isNull);
        expect(schedule['scheduledDate'], isNull);
        expect(schedule['scheduledTime'], isNull);
        expect(schedule['startDate'], '2026-10-15');
        expect(schedule['timeZone'], 'UTC');
        expect(schedule['dueMinDays'], 1);
        expect(schedule['dueMaxDays'], 20);
      },
    );

    testWidgets(
      'bulk $removed first Save shows notice then emits exactly the dependent clear mask',
      (tester) async {
        final rows = [_task('first'), _task('second')];
        final writes = <BulkTaskEdit>[];
        await _mount(
          tester,
          bulk: true,
          tasks: rows,
          saveBulk: (edit) async {
            writes.add(edit);
          },
        );
        await _edit(tester, removed, '');
        await _save(tester);
        expect(writes, isEmpty);
        expect(find.byKey(_noticeKey).hitTestable(), findsOneWidget);
        _occurrence(tester, '', '');
        await _save(tester);
        expect(writes, hasLength(1));
        expect(writes.single.schedulePatch, {
          removed: null,
          'scheduledDate': null,
          'scheduledTime': null,
        });
        for (final row in rows) {
          final schedule = writes.single.fieldsFor(row)['schedule'] as Map;
          expect(schedule[removed], isNull);
          expect(schedule['scheduledDate'], isNull);
          expect(schedule['scheduledTime'], isNull);
          expect(schedule['startDate'], '2026-10-15');
          expect(schedule['timeZone'], 'UTC');
          expect(schedule['dueMinDays'], 1);
          expect(schedule['dueMaxDays'], 20);
        }
      },
    );

    testWidgets(
      'bulk $removed removal applies both dependent clears; unapply restores original masks',
      (tester) async {
        final rows = [_task('first'), _task('second')];
        final raw = jsonEncode(rows);
        final writes = <BulkTaskEdit>[];
        await _mount(
          tester,
          bulk: true,
          tasks: rows,
          saveBulk: (edit) async {
            writes.add(edit);
          },
        );
        await _edit(tester, removed, '');
        await _blur(tester);
        _occurrence(tester, '', '');
        for (final field in [removed, 'scheduledDate', 'scheduledTime']) {
          expect(
            tester.widget<Checkbox>(_apply(field)).value,
            isTrue,
            reason: field,
          );
        }
        expect(writes, isEmpty);
        await tester.ensureVisible(_apply(removed));
        await tester.tap(_apply(removed));
        await tester.pumpAndSettle();
        _occurrence(tester, '2026-10-21', '10:15');
        for (final field in [removed, 'scheduledDate', 'scheduledTime']) {
          expect(
            tester.widget<Checkbox>(_apply(field)).value,
            isFalse,
            reason: field,
          );
        }
        await _save(tester);
        expect(writes, hasLength(1));
        expect(writes.single.schedulePatch, isEmpty);
        for (final row in rows) {
          expect(writes.single.fieldsFor(row), isEmpty);
        }
        expect(jsonEncode(rows), raw);
      },
    );
  }

  testWidgets(
    'both removed prerequisites must be restored before the occurrence returns',
    (tester) async {
      var writes = 0;
      await _mount(
        tester,
        save: (_, _, _) async {
          writes++;
        },
      );
      await _edit(tester, 'dueDate', '');
      await _blur(tester);
      _occurrence(tester, '', '');
      await _edit(tester, 'recurrence', '');
      await _blur(tester);
      await _edit(tester, 'dueDate', '2026-10-20');
      await _blur(tester);
      _occurrence(tester, '', '');
      expect(
        tester.widget<TextField>(_input('scheduledDate')).enabled,
        isFalse,
      );
      expect(find.textContaining('Removal cancelled'), findsNothing);
      await _edit(tester, 'recurrence', 'every week');
      await _blur(tester);
      _occurrence(tester, '2026-10-21', '10:15');
      expect(tester.widget<TextField>(_input('scheduledDate')).enabled, isTrue);
      expect(find.textContaining('Removal cancelled'), findsOneWidget);
      expect(writes, 0);
    },
  );

  testWidgets(
    'invalid partial prerequisite and active composition never auto-clear occurrence',
    (tester) async {
      var writes = 0;
      await _mount(
        tester,
        save: (_, _, _) async {
          writes++;
        },
      );
      await _edit(tester, 'dueDate', '2026-');
      await _blur(tester);
      _occurrence(tester, '2026-10-21', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
      await _edit(tester, 'dueDate', '2026-10-20');
      await _edit(tester, 'recurrence', ' ');
      final controller = _controller(tester, 'recurrence');
      controller.value = const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );
      tester
          .widget<ValidationActionButton>(find.byType(ValidationActionButton))
          .validation
          .blur('recurrence');
      expect(controller.value.composing, const TextRange(start: 0, end: 1));
      _occurrence(tester, '2026-10-21', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
      tester.widget<FilledButton>(_action).onPressed!();
      await tester.pumpAndSettle();
      expect(writes, 0);
      _occurrence(tester, '2026-10-21', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
    },
  );

  testWidgets(
    'pointer-down revision prevents blur-cleared occurrence saving on the same release',
    (tester) async {
      var writes = 0;
      await _mount(
        tester,
        save: (_, _, _) async {
          writes++;
        },
      );
      await _edit(tester, 'recurrence', '');
      final gesture = await tester.startGesture(tester.getCenter(_action));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.byKey(_noticeKey).hitTestable(), findsOneWidget);
      _occurrence(tester, '', '');
      await _save(tester);
      expect(writes, 1);
    },
  );

  testWidgets(
    'mixed unapplied prerequisites remain eligible and restore mixed occurrence masks',
    (tester) async {
      final rows = [
        _task('first'),
        _task(
          'second',
          schedule: {
            'dueDate': '2026-10-22',
            'recurrence': 'every month',
            'scheduledDate': '2026-10-23',
            'scheduledTime': '00:00',
          },
        ),
      ];
      final raw = jsonEncode(rows);
      final writes = <BulkTaskEdit>[];
      await _mount(
        tester,
        bulk: true,
        tasks: rows,
        saveBulk: (edit) async {
          writes.add(edit);
        },
      );
      expect(_controller(tester, 'dueDate').text, '');
      expect(_controller(tester, 'recurrence').text, '');
      expect(
        tester.widget<TextField>(_input('scheduledDate')).enabled,
        isTrue,
        reason: 'Mixed display does not mean an absent per-task prerequisite',
      );
      await tester.ensureVisible(_apply('dueDate'));
      await tester.tap(_apply('dueDate'));
      await tester.pumpAndSettle();
      expect(find.byKey(_noticeKey), findsOneWidget);
      expect(tester.widget<Checkbox>(_apply('scheduledDate')).value, isTrue);
      expect(tester.widget<Checkbox>(_apply('scheduledTime')).value, isTrue);
      await tester.tap(_apply('dueDate'));
      await tester.pumpAndSettle();
      for (final field in ['dueDate', 'scheduledDate', 'scheduledTime']) {
        expect(tester.widget<Checkbox>(_apply(field)).value, isFalse);
      }
      expect(_controller(tester, 'scheduledDate').text, '');
      expect(_controller(tester, 'scheduledTime').text, '');
      await _save(tester);
      expect(writes.single.schedulePatch, isEmpty);
      for (final row in rows) {
        expect(writes.single.fieldsFor(row), isEmpty);
      }
      expect(jsonEncode(rows), raw);
    },
  );

  testWidgets(
    'bulk restoring prerequisites restores earlier explicit occurrence mask',
    (tester) async {
      final writes = <BulkTaskEdit>[];
      await _mount(
        tester,
        bulk: true,
        saveBulk: (edit) async {
          writes.add(edit);
        },
      );
      await _edit(tester, 'scheduledDate', '2026-10-25');
      await _edit(tester, 'recurrence', '');
      await _blur(tester);
      _occurrence(tester, '', '');
      await tester.ensureVisible(_apply('recurrence'));
      await tester.tap(_apply('recurrence'));
      await tester.pumpAndSettle();
      _occurrence(tester, '2026-10-25', '10:15');
      expect(tester.widget<Checkbox>(_apply('scheduledDate')).value, isTrue);
      expect(tester.widget<Checkbox>(_apply('scheduledTime')).value, isFalse);
      expect(tester.widget<Checkbox>(_apply('recurrence')).value, isFalse);
      await _save(tester);
      expect(writes.single.schedulePatch, {'scheduledDate': '2026-10-25'});
    },
  );

  testWidgets(
    'Cancel after draft auto-clear preserves original task with no save',
    (tester) async {
      final original = _task('first');
      final raw = jsonEncode(original);
      var writes = 0, closed = 0;
      await _mount(
        tester,
        tasks: [original],
        close: () => closed++,
        save: (_, _, _) async {
          writes++;
        },
      );
      await _edit(tester, 'dueDate', '');
      await _blur(tester);
      _occurrence(tester, '', '');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(writes, 0);
      expect(jsonEncode(original), raw);
    },
  );

  testWidgets(
    'clearing only Due time preserves date prerequisites and occurrence',
    (tester) async {
      await _mount(
        tester,
        tasks: [
          _task('first', schedule: {'dueTime': '17:00'}),
        ],
      );
      await tester.ensureVisible(find.byTooltip('Clear Due time'));
      await tester.tap(find.byTooltip('Clear Due time'));
      await tester.pumpAndSettle();
      _occurrence(tester, '2026-10-21', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
      expect(_controller(tester, 'dueDate').text, '2026-10-20');
    },
  );
  testWidgets(
    'restoring a prerequisite never overwrites a changed dependent draft',
    (tester) async {
      var writes = 0;
      await _mount(
        tester,
        save: (_, _, _) async {
          writes++;
        },
      );
      final occurrence = _controller(tester, 'scheduledDate');
      await _edit(tester, 'recurrence', '');
      await _blur(tester);
      _occurrence(tester, '', '');
      // Model a late controller-owned picker result, not editing a disabled field.
      occurrence.text = '2026-10-24';
      await _edit(tester, 'recurrence', 'every week');
      await _blur(tester);
      _occurrence(tester, '2026-10-24', '');
      expect(writes, 0);
    },
  );

  testWidgets(
    'legacy occurrence is readable until prerequisites are added, with no unrelated rewrite',
    (tester) async {
      final original = _task('first', schedule: {'recurrence': null});
      final raw = jsonEncode(original);
      final writes = <Map<String, dynamic>>[];
      await _mount(
        tester,
        tasks: [original],
        save: (fields, _, _) async {
          writes.add(fields);
        },
      );
      _occurrence(tester, '2026-10-21', '10:15');
      for (final key in ['scheduledDate', 'scheduledTime']) {
        final field = tester.widget<TextField>(_input(key));
        expect(field.enabled == false || field.readOnly, isTrue, reason: key);
      }
      await _edit(tester, 'title', 'Synthetic unrelated title');
      await _blur(tester);
      expect(find.byKey(_noticeKey), findsNothing);
      await _save(tester);
      expect(writes, [
        {'title': 'Synthetic unrelated title'},
      ]);
      expect(jsonEncode(original), raw);
    },
  );

  testWidgets(
    'legacy repeating occurrence without Due retains an explicit Clear action',
    (tester) async {
      final original = _task('first', schedule: {'dueDate': null});
      final raw = jsonEncode(original);
      final writes = <Map<String, dynamic>>[];
      await _mount(
        tester,
        tasks: [original],
        save: (fields, _, _) async {
          writes.add(fields);
        },
      );
      _occurrence(tester, '2026-10-21', '10:15');
      expect(
        tester.widget<TextField>(_input('scheduledDate')).enabled,
        isFalse,
      );
      expect(writes, isEmpty);
      final clear = find.widgetWithText(TextButton, 'Clear override');
      expect(clear, findsOneWidget);
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(jsonEncode(original), raw);
      await _save(tester);
      expect(writes, hasLength(1));
      final schedule = writes.single['schedule'] as Map;
      expect(schedule['scheduledDate'], isNull);
      expect(schedule['scheduledTime'], isNull);
      expect(schedule['dueDate'], isNull);
      expect(schedule['recurrence'], 'every week');
      expect(schedule['startDate'], '2026-10-15');
    },
  );

  testWidgets(
    'explicit Clear applies both fields for mixed bulk legacy occurrences',
    (tester) async {
      final rows = [
        _task('first', schedule: {'recurrence': null}),
        _task(
          'second',
          schedule: {
            'recurrence': null,
            'scheduledDate': '2026-10-23',
            'scheduledTime': '00:00',
          },
        ),
      ];
      final raw = jsonEncode(rows);
      final writes = <BulkTaskEdit>[];
      await _mount(
        tester,
        bulk: true,
        tasks: rows,
        saveBulk: (edit) async {
          writes.add(edit);
        },
      );
      _occurrence(tester, '', '');
      final clear = find.widgetWithText(TextButton, 'Clear override');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(jsonEncode(rows), raw);
      await _save(tester);
      expect(writes, hasLength(1));
      expect(writes.single.schedulePatch, {
        'scheduledDate': null,
        'scheduledTime': null,
      });
      for (final row in rows) {
        final schedule = writes.single.fieldsFor(row)['schedule'] as Map;
        expect(schedule['scheduledDate'], isNull);
        expect(schedule['scheduledTime'], isNull);
        expect(schedule['dueDate'], '2026-10-20');
        expect(schedule['startDate'], '2026-10-15');
        expect(schedule['recurrence'], isNull);
      }
    },
  );

  testWidgets(
    'legacy occurrence becomes editable when Due and Repeat are both available',
    (tester) async {
      await _mount(
        tester,
        tasks: [
          _task('first', schedule: {'recurrence': null}),
        ],
      );
      _occurrence(tester, '2026-10-21', '10:15');
      await _edit(tester, 'recurrence', 'every week');
      await _blur(tester);
      for (final key in ['scheduledDate', 'scheduledTime']) {
        final field = tester.widget<TextField>(_input(key));
        expect(field.enabled, isTrue);
        expect(field.readOnly, isFalse);
      }
      _occurrence(tester, '2026-10-21', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
    },
  );

  testWidgets(
    'original migration conflict keeps occurrence editable as a resolution exception',
    (tester) async {
      await _mount(
        tester,
        tasks: [
          _task(
            'first',
            schedule: {
              'startDate': '2026-10-22',
              'dueDate': null,
              'recurrence': null,
            },
          ),
        ],
      );
      _occurrence(tester, '2026-10-21', '10:15');
      expect(
        find.textContaining('This occurrence could not be moved to Due'),
        findsOneWidget,
      );
      for (final key in ['scheduledDate', 'scheduledTime']) {
        final field = tester.widget<TextField>(_input(key));
        expect(field.enabled, isTrue);
        expect(field.readOnly, isFalse);
      }
      await _edit(tester, 'scheduledDate', '2026-10-23');
      await _blur(tester);
      _occurrence(tester, '2026-10-23', '10:15');
      expect(find.byKey(_noticeKey), findsNothing);
    },
  );
}
