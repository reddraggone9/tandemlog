import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/presentation/task_editor.dart';

Map<String, dynamic> fixture(String id) => {
  'id': id,
  'title': 'Occurrence row fixture',
  'description': '',
  'assignee': 'a',
  'tags': <String>[],
  'tagRefs': <String, String>{},
  'schedule': {
    'startDate': '2026-10-01',
    'dueDate': '2026-10-03',
    'scheduledDate': '2026-10-05',
    'recurrence': 'every week when done',
    'timeZone': 'America/Chicago',
  },
};

Finder input(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('occurrence pairs date and time and clears time independently', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<TaskEditorState>();
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskEditor(
            key: key,
            panel: true,
            task: fixture('one'),
            onClose: () {},
            save: (fields, _, _) async => saved = fields,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(input('scheduledTime'));
    expect(
      tester.getTopLeft(input('scheduledDate')).dy,
      tester.getTopLeft(input('scheduledTime')).dy,
    );
    expect(
      tester.getSize(input('scheduledDate')).width,
      greaterThan(tester.getSize(input('scheduledTime')).width),
    );
    expect(
      tester.widget<TextField>(input('scheduledTime')).decoration!.labelText,
      'Time',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'This occurrence',
      ),
      findsOneWidget,
    );
    await tester.tap(input('scheduledTime'));
    await tester.pumpAndSettle();
    expect(await key.currentState!.canClose(), isTrue);
    await tester.enterText(input('scheduledTime'), '00:00');
    await tester.pump();
    final clear = find.byTooltip('Clear This occurrence time');
    expect(tester.getSize(clear).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input('scheduledTime')).controller!.text,
      '',
    );
    expect(find.text('2026-10-05'), findsOneWidget);
    expect(await key.currentState!.canClose(), isTrue);
    await tester.enterText(input('scheduledTime'), '00:00');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final schedule = saved!['schedule'] as Map;
    expect(schedule['scheduledDate'], '2026-10-05');
    expect(schedule['scheduledTime'], '00:00');
    expect(schedule['startDate'], '2026-10-01');
    expect(schedule['dueDate'], '2026-10-03');
    expect(schedule['recurrence'], 'every week when done');
    expect(schedule['timeZone'], 'America/Chicago');
    expect(tester.takeException(), isNull);
  });

  for (final fieldKey in ['scheduledDate', 'scheduledTime']) {
    testWidgets(
      'occurrence $fieldKey draft survives row stacking and enlarged text',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<TaskEditorState>();
        Widget host(double scale) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(600, 1400),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: TaskEditor(
                key: key,
                panel: true,
                task: fixture('one'),
                onClose: () {},
                save: (_, _, _) async {},
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(1));
        await tester.pumpAndSettle();
        await tester.ensureVisible(input(fieldKey));
        final draft = fieldKey == 'scheduledTime' ? '13:45' : '2026-10-06';
        await tester.enterText(input(fieldKey), draft);
        final before = tester.widget<TextField>(input(fieldKey));
        before.controller!.value = TextEditingValue(
          text: draft,
          selection: const TextSelection.collapsed(offset: 2),
          composing: const TextRange(start: 0, end: 2),
        );
        final focus = tester
            .widget<EditableText>(
              find.descendant(
                of: input(fieldKey),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode;
        for (final configuration in [
          (290.0, 1.0),
          (600.0, 2.0),
          (600.0, 1.0),
        ]) {
          await tester.binding.setSurfaceSize(Size(configuration.$1, 1400));
          await tester.pumpWidget(host(configuration.$2));
          await tester.pumpAndSettle();
          await tester.ensureVisible(input(fieldKey));
          final after = tester.widget<TextField>(input(fieldKey));
          expect(after.controller, same(before.controller));
          expect(after.controller!.text, draft);
          expect(
            after.controller!.value.composing,
            const TextRange(start: 0, end: 2),
          );
          expect(
            after.controller!.selection,
            const TextSelection.collapsed(offset: 2),
          );
          final afterFocus = tester
              .widget<EditableText>(
                find.descendant(
                  of: input(fieldKey),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode;
          expect(afterFocus, same(focus));
          expect(afterFocus.hasFocus, isTrue);
          final dateY = tester.getTopLeft(input('scheduledDate')).dy;
          final timeY = tester.getTopLeft(input('scheduledTime')).dy;
          if (configuration == (600.0, 1.0)) {
            expect(timeY, dateY);
          } else {
            expect(timeY, greaterThan(dateY));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('bulk occurrence retains independent date and time apply masks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    try {
      BulkTaskEdit? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkTaskEditor(
              panel: true,
              tasks: [fixture('one'), fixture('two')],
              onClose: () {},
              onSave: (edit) async => saved = edit,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(input('scheduledTime'));
      expect(
        tester.getTopLeft(input('scheduledDate')).dy,
        tester.getTopLeft(input('scheduledTime')).dy,
      );
      expect(
        find.bySemanticsLabel('Apply This occurrence date'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Apply This occurrence time'),
        findsOneWidget,
      );
      await tester.enterText(input('scheduledTime'), '11:30');
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(input('scheduledTimeApply')).value,
        isTrue,
      );
      expect(
        tester.widget<Checkbox>(input('scheduledDateApply')).value,
        isFalse,
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.schedulePatch.keys, ['scheduledTime']);
      expect(saved!.schedulePatch['scheduledTime'], '11:30');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'nonrepeating existing occurrence stays paired and disabled until prerequisites are set',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = fixture('one');
      (source['schedule'] as Map).remove('recurrence');
      final key = GlobalKey<TaskEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              key: key,
              panel: true,
              task: source,
              onClose: () {},
              save: (_, _, _) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(input('scheduledDate'), findsOneWidget);
      expect(tester.widget<TextField>(input('scheduledDate')).enabled, isFalse);
      expect(tester.widget<TextField>(input('scheduledTime')).enabled, isFalse);
      expect(
        tester.getTopLeft(input('scheduledDate')).dy,
        tester.getTopLeft(input('scheduledTime')).dy,
      );
      expect(
        tester.widget<TextField>(input('scheduledDate')).controller!.text,
        '2026-10-05',
      );
      expect(await key.currentState!.canClose(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stacked mixed bulk clear applies only occurrence time', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(290, 1400));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final first = fixture('one'), second = fixture('two');
    (first['schedule'] as Map)['scheduledTime'] = '08:00';
    (second['schedule'] as Map).addAll(<String, String>{
      'scheduledDate': '2026-10-08',
      'scheduledTime': '09:00',
    });
    BulkTaskEdit? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkTaskEditor(
            panel: true,
            tasks: [first, second],
            onClose: () {},
            onSave: (edit) async => saved = edit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(input('scheduledTime'));
    expect(
      tester.getTopLeft(input('scheduledTime')).dy,
      greaterThan(tester.getTopLeft(input('scheduledDate')).dy),
    );
    expect(
      tester.widget<TextField>(input('scheduledDate')).controller!.text,
      '',
    );
    expect(tester.widget<Checkbox>(input('scheduledDateApply')).value, isFalse);
    expect(tester.widget<Checkbox>(input('scheduledTimeApply')).value, isFalse);
    expect(
      tester.getSize(input('scheduledDateApply')).width,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(input('scheduledTimeApply')).height,
      greaterThanOrEqualTo(48),
    );
    await tester.enterText(input('scheduledTime'), '11:30');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear This occurrence time'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input('scheduledTime')).controller!.text,
      '',
    );
    expect(tester.widget<Checkbox>(input('scheduledDateApply')).value, isFalse);
    expect(tester.widget<Checkbox>(input('scheduledTimeApply')).value, isTrue);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.schedulePatch, {'scheduledTime': null});
    expect(tester.takeException(), isNull);
  });
}
