import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/presentation/task_editor.dart';

const applyLabels = {
  'startDate': 'Apply Start date',
  'startTime': 'Apply Start time',
  'dueDate': 'Apply Due date',
  'dueTime': 'Apply Due time',
  'recurrence': 'Apply Repeat',
  'scheduledDate': 'Apply This occurrence date',
  'scheduledTime': 'Apply This occurrence time',
  'timeZone': 'Apply Time zone',
  'dueMinDays': 'Apply Minimum days',
  'dueMaxDays': 'Apply Maximum days',
  'assignee': 'Apply Assignee',
};

List<Map<String, dynamic>> fixtureTasks() => [
  for (final id in ['first', 'second'])
    {
      'id': id,
      'title': 'Task $id',
      'description': '',
      'assignee': 'alex',
      'tags': ['retained'],
      'tagRefs': {'ref-$id': 'retained'},
      'schedule': {
        'dueDate': id == 'first' ? '2026-10-02' : '2026-10-03',
        'dueTime': id == 'first' ? '12:30' : '13:45',
        'recurrence': 'every week when done',
        'timeZone': 'UTC',
      },
    },
];

Future<void> mountBulk(
  WidgetTester tester, {
  double width = 900,
  double scale = 1,
  required Future<void> Function(BulkTaskEdit) save,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: BulkTaskEditor(
            panel: true,
            tasks: fixtureTasks(),
            users: const [
              {'id': 'alex', 'name': 'Alex'},
              {'id': 'sam', 'name': 'Sam'},
            ],
            onClose: () {},
            onSave: save,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Finder> revealApply(WidgetTester tester, String label) async {
  // Identify the checkbox from its accessible name, rather than a nearby field
  // label or order. Missing names must fail even when visual controls work.
  final finder = find.byWidgetPredicate(
    (widget) => widget is Checkbox && widget.semanticLabel == label,
    description: 'checkbox named "$label"',
  );
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  return finder;
}

void main() {
  for (final geometry in [(900.0, 1.0), (390.0, 2.0)]) {
    testWidgets(
      'bulk apply names and accessible actions isolate fields at $geometry',
      (tester) async {
        final semantics = tester.ensureSemantics();
        addTearDown(semantics.dispose);
        await mountBulk(
          tester,
          width: geometry.$1,
          scale: geometry.$2,
          save: (_) async {},
        );
        expect(find.byType(Checkbox), findsNWidgets(applyLabels.length));
        for (final entry in applyLabels.entries) {
          final checkbox = await revealApply(tester, entry.value);
          final node = tester.getSemantics(checkbox);
          final data = node.getSemanticsData();
          expect(data.label, entry.value);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(
            node,
            matchesSemantics(
              label: entry.value,
              hasCheckedState: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          // Assistive activation goes through the actual semantics action.
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(checkbox).getSemanticsData().label,
            entry.value,
          );
          expect(tester.widget<Checkbox>(checkbox).value, isTrue);
          expect(
            tester
                .widgetList<Checkbox>(find.byType(Checkbox))
                .where((widget) => widget.value == true)
                .map((widget) => widget.semanticLabel),
            [entry.value],
          );
          expect(
            tester.getSemantics(checkbox),
            matchesSemantics(
              label: entry.value,
              hasCheckedState: true,
              isChecked: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
          // Touch reverses exactly the same field. Keep existing hit targets.
          expect(
            tester.getSize(checkbox).shortestSide,
            greaterThanOrEqualTo(40),
          );
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<Checkbox>(find.byType(Checkbox))
                .where((widget) => widget.value == true),
            isEmpty,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keyboard applies only Due time; tag operations stay distinct', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    BulkTaskEdit? saved;
    await mountBulk(tester, save: (draft) async => saved = draft);
    final checkbox = await revealApply(tester, 'Apply Due time');
    expect(tester.getSize(checkbox), const Size(48, 48));
    final paint = find
        .descendant(of: checkbox, matching: find.byType(CustomPaint))
        .first;
    final focus = Focus.of(tester.element(paint));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    for (final key in ['addTags', 'removeTags']) {
      final input = find.byKey(ValueKey(key));
      await tester.ensureVisible(input);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(input).getSemanticsData().label,
        key == 'addTags' ? 'Add tags' : 'Remove tags',
      );
      await tester.enterText(input, key == 'addTags' ? 'new' : 'retained');
    }
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.schedulePatch, {'dueTime': null});
    expect(saved!.assignee, isNull);
    expect(saved!.addTags, ['new']);
    expect(saved!.removeTags, ['retained']);
  });

  testWidgets('saving retains field names but disables all apply actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final saving = Completer<void>();
    await mountBulk(tester, save: (_) => saving.future);
    await tester.enterText(find.byKey(const ValueKey('dueTime')), '14:00');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    for (final entry in applyLabels.entries) {
      final checkbox = await revealApply(tester, entry.value);
      expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
      final data = tester.getSemantics(checkbox).getSemanticsData();
      expect(data.label, entry.value);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, entry.key == 'dueTime');
    }
    saving.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
