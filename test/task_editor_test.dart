import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/tag_input.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/platform/log_folder.dart';

Map<String, dynamic> task([Map<String, dynamic> schedule = const {}]) => {
  'id': 'test',
  'title': 'Original',
  'description': '',
  'assignee': 'a',
  'tags': ['old'],
  'tagRefs': {'ref': 'old'},
  'schedule': schedule,
};
Future<void> mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Finder input(String key) => find.byKey(ValueKey(key));
Future<void> edit(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(input(key));
  await tester.enterText(input(key), value);
  await tester.pump();
}

Finder get primaryAction => find.descendant(
  of: find.byType(ValidationActionButton),
  matching: find.byType(FilledButton),
);
Future<void> activatePrimary(WidgetTester tester) async {
  await tester.ensureVisible(primaryAction);
  await tester.tap(primaryAction);
  await tester.pumpAndSettle();
}

Future<void> settleValidation(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

String? fieldError(WidgetTester tester, String key) {
  if (const {'tags', 'addTags', 'removeTags'}.contains(key)) {
    return tester
        .widget<TagInput>(
          find.ancestor(of: input(key), matching: find.byType(TagInput)),
        )
        .queryErrorText;
  }
  return tester.widget<TextField>(input(key)).decoration!.errorText;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'sort bounds stay compact and field help preserves focus at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 820);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            home: Scaffold(
              body: TaskEditor(
                panel: true,
                task: task({'dueMinDays': 0}),
                save: (_, a, r) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(input('dueMinDays'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Days from today; affects listing order, not the deadline.',
          ),
          findsNothing,
        );
        final heading = find.text('Sort-date bounds');
        final label = find.descendant(
          of: input('dueMinDays'),
          matching: find.text('Minimum days'),
        );
        expect(
          tester.getRect(label).top,
          greaterThanOrEqualTo(tester.getRect(heading).bottom),
          reason: 'The floating label must not overlap the remaining heading',
        );
        await tester.tap(input('dueMinDays'));
        await tester.pumpAndSettle();
        final focus = tester.widget<TextField>(input('dueMinDays')).focusNode!;
        expect(focus.hasFocus, isTrue);
        expect(FocusManager.instance.primaryFocus, same(focus));
        await tester.ensureVisible(find.byTooltip('Task field help'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Task field help').hitTestable(), findsOneWidget);
        expect(
          focus.hasFocus,
          isTrue,
          reason:
              'Scrolling the Help control into view must preserve input focus',
        );
        expect(FocusManager.instance.primaryFocus, same(focus));
        await tester.tap(
          find.byTooltip('Task field help'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        for (final term in [
          'Start',
          'Due',
          'Repeat',
          'This occurrence',
          'Sort-date bounds',
        ]) {
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text(term),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.textContaining('Values are calendar days from today'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextButton, 'Done').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(
          find.widgetWithText(TextButton, 'Done'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(input('dueMinDays').hitTestable(), findsOneWidget);
        final inputRect = tester.getRect(input('dueMinDays'));
        final viewportRect = tester.getRect(
          find
              .ancestor(
                of: input('dueMinDays'),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        expect(
          inputRect.top,
          greaterThanOrEqualTo(viewportRect.top),
          reason: 'Help must restore the whole input, not only its caret',
        );
        expect(
          inputRect.bottom,
          lessThanOrEqualTo(viewportRect.bottom),
          reason: 'The restored input border must clear the fixed footer',
        );
        expect(
          tester.widget<TextField>(input('dueMinDays')).controller!.text,
          '0',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.linux,
      }),
    );
  }
  testWidgets(
    'blocked text instruction wraps with full semantics at narrow 200 percent',
    (tester) async {
      const instruction =
          'This workspace has no verified shared text setup. Restore its initialized history before editing.';
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: TaskEditor(
                panel: true,
                task: task(),
                disableTextFields: true,
                textStatus: instruction,
                onClose: () {},
                save: (_, _, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final status = find.text(instruction);
      expect(status, findsOneWidget);
      final text = tester.widget<Text>(status);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      expect(text.softWrap, isTrue);
      expect(
        tester.widget<TextField>(input('title')).decoration!.helperText,
        isNull,
      );
      expect(find.bySemanticsLabel(instruction), findsOneWidget);
      expect(tester.getSize(status).height, greaterThan(50));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'unactivated text stays visible and disabled while scheduling saves',
    (tester) async {
      Map<String, dynamic>? saved;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          disableTextFields: true,
          textStatus: 'Initialize collaborative text in Settings.',
          onClose: () {},
          save: (fields, _, _) async => saved = fields,
        ),
      );
      expect(tester.widget<TextField>(input('title')).enabled, isFalse);
      expect(tester.widget<TextField>(input('description')).enabled, isFalse);
      expect(
        tester.widget<TextField>(input('title')).controller!.text,
        'Original',
      );
      expect(
        find.text('Initialize collaborative text in Settings.'),
        findsOneWidget,
      );
      await edit(tester, 'dueDate', '2026-10-05');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved!.containsKey('title'), isFalse);
      expect(saved!.containsKey('description'), isFalse);
      expect((saved!['schedule'] as Map)['dueDate'], '2026-10-05');
    },
  );

  testWidgets(
    'blank Time focus preserves date precision and midnight is explicit',
    (tester) async {
      for (final zone in [null, 'UTC', 'America/Chicago']) {
        Map<String, dynamic>? saved;
        final key = GlobalKey<TaskEditorState>();
        await mount(
          tester,
          TaskEditor(
            key: key,
            panel: true,
            task: task({'dueDate': '2026-10-04', 'timeZone': ?zone}),
            onClose: () {},
            save: (fields, _, _) async => saved = fields,
          ),
        );
        await tester.ensureVisible(input('dueTime'));
        await tester.tap(input('dueTime'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input('dueTime')).controller!.text, '');
        expect(await key.currentState!.canClose(), isTrue);
        await edit(tester, 'dueTime', '00:00');
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        final schedule = saved!['schedule'] as Map;
        expect(schedule['dueDate'], '2026-10-04');
        expect(schedule['dueTime'], '00:00');
        expect(schedule['timeZone'], zone);
      }
    },
  );

  testWidgets(
    'single and bulk editors put tags and assignee after scheduling',
    (tester) async {
      const users = [
        {'id': 'a', 'name': 'Alex'},
      ];
      for (final bulk in [false, true]) {
        await mount(
          tester,
          bulk
              ? BulkTaskEditor(
                  panel: true,
                  tasks: [task(), task()],
                  users: users,
                  onSave: (_) async {},
                )
              : TaskEditor(
                  panel: true,
                  task: task(),
                  users: users,
                  save: (_, _, _) async {},
                ),
        );
        final keys = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => (field.key! as ValueKey<String>).value)
            .toList();
        expect(keys, [
          if (!bulk) ...['title', 'description'],
          'startDate',
          'startTime',
          'dueDate',
          'dueTime',
          'recurrence',
          'timeZone',
          'dueMinDays',
          'dueMaxDays',
          if (bulk) ...['addTags', 'removeTags'] else 'tags',
        ]);
        final lastTags = input(bulk ? 'removeTags' : 'tags');
        final assignee = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(assignee);
        expect(
          tester.getTopLeft(assignee).dy,
          greaterThan(tester.getTopLeft(lastTags).dy),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'date and optional time share rows and clear time independently',
    (tester) async {
      Map<String, dynamic>? saved;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task({'dueDate': '2026-10-04', 'dueTime': '00:00'}),
          save: (fields, _, _) async => saved = fields,
          onClose: () {},
        ),
      );
      await tester.ensureVisible(input('dueDate'));
      expect(
        tester.getTopLeft(input('dueDate')).dy,
        tester.getTopLeft(input('dueTime')).dy,
      );
      expect(
        tester.getSize(input('dueDate')).width,
        greaterThan(tester.getSize(input('dueTime')).width),
      );
      expect(input('startTime'), findsOneWidget);
      expect(tester.widget<TextField>(input('startTime')).controller!.text, '');
      expect(
        tester.widget<TextField>(input('startTime')).decoration!.labelText,
        'Time',
      );
      expect(
        tester.widget<TextField>(input('dueTime')).decoration!.labelText,
        'Time',
      );
      await tester.tap(find.byTooltip('Clear Due time'));
      await tester.pump();
      expect(
        tester.widget<TextField>(input('dueDate')).controller!.text,
        '2026-10-04',
      );
      expect(input('dueTime'), findsOneWidget);
      await tester.tap(input('dueTime'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('dueTime')).focusNode!.hasFocus,
        isTrue,
      );
      expect(tester.widget<TextField>(input('dueTime')).controller!.text, '');
      await tester.enterText(input('dueTime'), '00:00');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear Due time'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect((saved!['schedule'] as Map)['dueTime'], isNull);
      expect((saved!['schedule'] as Map)['dueDate'], '2026-10-04');
    },
  );

  testWidgets('date rows stack at narrow widths and enlarged text', (
    tester,
  ) async {
    // Widget tests use the wider Ahem font; native tests retain 390px coverage.
    for (final configuration in [(500.0, 1.0), (290.0, 1.0), (600.0, 2.0)]) {
      await tester.binding.setSurfaceSize(Size(configuration.$1, 1000));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(configuration.$2),
            ),
            child: Scaffold(
              body: TaskEditor(
                panel: true,
                task: task({'dueDate': '2026-10-04', 'dueTime': '00:00'}),
                save: (_, _, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(input('dueTime'));
      if (configuration.$1 == 500) {
        expect(
          tester.getTopLeft(input('dueTime')).dy,
          tester.getTopLeft(input('dueDate')).dy,
        );
      } else {
        expect(
          tester.getTopLeft(input('dueTime')).dy,
          greaterThan(tester.getTopLeft(input('dueDate')).dy),
        );
      }
      expect(tester.takeException(), isNull);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  for (final fieldKey in ['title', 'description']) {
    testWidgets(
      '$fieldKey caret survives viewport and text scale changes without unrelated jumps',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 820);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final text = fieldKey == 'description'
            ? List.generate(
                40,
                (i) => 'Reference note ${i + 1} with full detail.',
              ).join('\n')
            : List.filled(35, 'reference').join(' ');
        final source = task()..[fieldKey] = text;
        final key = GlobalKey<TaskEditorState>();
        Widget host({bool dark = false}) => MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: TaskEditor(
              key: key,
              panel: true,
              task: source,
              save: (_, a, r) async {},
            ),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        final field = input(fieldKey);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        // A resize must preserve the selection and unconfirmed IME candidate.
        controller.value = controller.value.copyWith(
          selection: TextSelection(
            baseOffset: text.length - 2,
            extentOffset: text.length,
          ),
          composing: TextRange(start: text.length - 2, end: text.length),
        );
        await tester.pumpAndSettle();
        final draft = controller.value;
        EditableTextState editable() => tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        void check(String label) {
          final state = editable();
          final render = state.renderEditable;
          final caret = render
              .getLocalRectForCaret(controller.selection.extent)
              .shift(render.localToGlobal(Offset.zero));
          final viewport = tester.getRect(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(
            caret.top,
            greaterThanOrEqualTo(viewport.top - 1),
            reason: label,
          );
          expect(
            caret.bottom,
            lessThanOrEqualTo(viewport.bottom + 1),
            reason: label,
          );
          expect(controller.value, draft, reason: label);
          expect(find.text('Save changes').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        check('initial');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        check('keyboard');
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        check('large text');
        tester.view.physicalSize = const Size(360, 740);
        await tester.pumpAndSettle();
        check('shrink pane');
        tester.view.physicalSize = const Size(900, 1000);
        await tester.pumpAndSettle();
        check('expand pane');
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        check('restore');
        (editable().renderEditable.offset as ScrollPosition).jumpTo(0);
        await tester.pumpAndSettle();
        final offset = editable().renderEditable.offset.pixels;
        await tester.pumpWidget(host(dark: true));
        await tester.pumpAndSettle();
        expect(editable().renderEditable.offset.pixels, offset);
        expect(controller.value, draft);
        source[fieldKey] = 'Incoming content';
        await tester.pumpWidget(host(dark: true));
        await tester.pumpAndSettle();
        expect(editable().renderEditable.offset.pixels, offset);
        expect(controller.value, draft);
      },
    );
  }

  testWidgets('changed composing title cannot save until normalized commit', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final key = GlobalKey<TaskEditorState>();
    await mount(
      tester,
      TaskEditor(
        key: key,
        panel: true,
        task: task(),
        onClose: () {},
        save: (fields, a, r) async {
          saved = fields;
        },
      ),
    );
    await tester.tap(input('title'));
    await tester.pump();
    final field = tester.widget<TextField>(input('title'));
    expect(field.keyboardType, TextInputType.text);
    expect(field.textInputAction, TextInputAction.next);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'candidate',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(primaryAction).onPressed, isNotNull);
    expect(fieldError(tester, 'title'), isNull);
    tester.widget<FilledButton>(primaryAction).onPressed!();
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(
      fieldError(tester, 'title'),
      'Finish entering the title before saving.',
    );
    expect(find.text('Review errors'), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      field.controller!.value.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    expect(fieldError(tester, 'title'), isNull);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'new\ntitle',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      ),
    );
    await tester.pump();
    tester.widget<FilledButton>(primaryAction).onPressed!();
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(
      field.controller!.value.composing,
      const TextRange(start: 0, end: 9),
    );
    expect(
      find.text('Finish entering the title before saving.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(primaryAction).onPressed, isNotNull);
    expect(saved, isNull);
    final closing = key.currentState!.canClose();
    await tester.pumpAndSettle();
    // Opening a dialog can finalize composition on focus loss. Restore the
    // active candidate to exercise the guard against a still-composing IME.
    field.controller!.value = const TextEditingValue(
      text: 'new\ntitle',
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 0, end: 9),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await closing, false);
    expect(saved, isNull);
    expect(field.controller!.text, 'new\ntitle');
    tester.testTextInput.updateEditingValue(
      field.controller!.value.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    expect(field.controller!.text, 'new title');
    await settleValidation(tester);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved, {'title': 'new title'});
  });

  testWidgets('title input normalizes paste selection after IME commits', (
    tester,
  ) async {
    await mount(
      tester,
      TaskEditor(panel: true, task: task(), save: (_, a, r) async {}),
    );
    await tester.tap(input('title'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ab\r\ncd\nef',
        selection: TextSelection(
          baseOffset: 4,
          extentOffset: 7,
          isDirectional: true,
        ),
      ),
    );
    await tester.pump();
    final controller = tester.widget<TextField>(input('title')).controller!;
    expect(controller.text, 'ab cd ef');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 3, extentOffset: 6, isDirectional: true),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '候補\n文字',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    expect(controller.text, '候補\n文字');
    expect(controller.value.composing, const TextRange(start: 0, end: 5));
    tester.testTextInput.updateEditingValue(
      controller.value.copyWith(composing: TextRange.empty),
    );
    await tester.pump();
    expect(controller.text, '候補 文字');
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets(
    'historical multiline title opens clean and notes save preserves title',
    (tester) async {
      final source = task()..['title'] = '  historical\nsecond\r\nthird  ';
      final key = GlobalKey<TaskEditorState>();
      Map<String, dynamic>? saved;
      await mount(
        tester,
        TaskEditor(
          key: key,
          panel: true,
          task: source,
          onClose: () {},
          save: (fields, a, r) async {
            saved = fields;
          },
        ),
      );
      final controller = tester.widget<TextField>(input('title')).controller!;
      expect(controller.text, source['title']);
      await tester.tap(input('title'));
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      expect(await key.currentState!.canClose(), true);
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 4),
      );
      await tester.pump();
      await edit(tester, 'description', 'new notes');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved, {'description': 'new notes'});
      expect(controller.text, source['title']);
    },
  );

  testWidgets(
    'title grows from one to two lines and notes grow then scroll with caret',
    (tester) async {
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () {},
          save: (_, a, r) async {},
        ),
      );
      final shortTitle = tester.getSize(input('title')).height;
      await edit(tester, 'title', List.filled(40, 'wrapped').join(' '));
      final longTitle = tester.getSize(input('title')).height;
      expect(longTitle, greaterThan(shortTitle));
      await edit(tester, 'title', List.filled(60, 'wrapped').join(' '));
      expect(tester.getSize(input('title')).height, longTitle);
      final initialNotes = tester.getSize(input('description')).height;
      await edit(
        tester,
        'description',
        List.generate(8, (i) => 'line $i').join('\n'),
      );
      final grownNotes = tester.getSize(input('description')).height;
      expect(grownNotes, greaterThan(initialNotes));
      await edit(
        tester,
        'description',
        List.generate(80, (i) => 'line $i').join('\n'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(input('description')).height,
        greaterThanOrEqualTo(grownNotes),
      );
      expect(
        tester.getSize(input('description')).height,
        lessThanOrEqualTo(360),
      );
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: input('description'),
          matching: find.byType(EditableText),
        ),
      );
      expect(
        (editable.renderEditable.offset as ScrollPosition).maxScrollExtent,
        greaterThan(0),
      );
      expect(editable.renderEditable.offset.pixels, greaterThan(0));
      expect(
        tester.getRect(find.text('Save changes')).bottom,
        lessThanOrEqualTo(1400),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard and large text bound notes and keep modal actions reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: 300),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: TaskEditor(
                task: task()
                  ..['description'] = List.filled(60, 'notes').join('\n'),
                onClose: () {},
                save: (_, a, r) async {
                  saved = true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(input('description')).height,
        lessThanOrEqualTo(200),
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved, true);
      expect(
        find.widgetWithText(TextButton, 'Cancel').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'close guards dirty draft and preserves text after keep editing',
    (tester) async {
      final key = GlobalKey<TaskEditorState>();
      await mount(
        tester,
        TaskEditor(
          key: key,
          panel: true,
          task: task(),
          save: (_, a, r) async {},
        ),
      );
      expect(await key.currentState!.canClose(), true);
      await edit(tester, 'title', 'Draft');
      final closing = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(await closing, false);
      expect(find.text('Draft'), findsOneWidget);
    },
  );
  testWidgets(
    'schedule review reveals first input and repeat conditional fields',
    (tester) async {
      var saves = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          save: (_, _, _) async {
            saves++;
          },
        ),
      );
      expect(input('scheduledDate'), findsNothing);
      expect(fieldError(tester, 'dueDate'), isNull);
      await edit(tester, 'dueDate', 'bad');
      expect(
        fieldError(tester, 'dueDate'),
        isNull,
        reason: 'Partial typing is quiet until blur or review',
      );
      await settleValidation(tester);
      expect(fieldError(tester, 'dueDate'), 'Date must be YYYY-MM-DD.');
      expect(find.text('Review errors'), findsOneWidget);
      await activatePrimary(tester);
      expect(saves, 0);
      expect(
        tester.widget<TextField>(input('dueDate')).focusNode!.hasFocus,
        isTrue,
      );
      await edit(tester, 'dueDate', '2026-10-01');
      await edit(tester, 'startDate', '2026-10-02');
      await settleValidation(tester);
      expect(
        fieldError(tester, 'startDate'),
        'Start must be on or before the due date and time.',
      );
      await activatePrimary(tester);
      expect(saves, 0);
      await edit(tester, 'startDate', '2026-09-30');
      await edit(tester, 'recurrence', 'every week');
      await settleValidation(tester);
      expect(input('scheduledDate'), findsOneWidget);
      expect(fieldError(tester, 'startDate'), isNull);
      expect(find.text('Review errors'), findsNothing);
      expect(saves, 0);
    },
  );
  testWidgets(
    'nonrepeat override survives title edit and frozen original ignores incoming data',
    (tester) async {
      final source = task({'scheduledDate': '2026-10-02'});
      Map<String, dynamic>? saved;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: source,
          onClose: () {},
          save: (fields, a, r) async {
            saved = fields;
          },
        ),
      );
      expect(input('scheduledDate'), findsOneWidget);
      final occurrence = tester.widget<TextField>(input('scheduledDate'));
      expect(occurrence.controller!.text, '2026-10-02');
      expect(occurrence.enabled == false || occurrence.readOnly, isTrue);
      expect(
        find.text('Existing occurrence override is preserved.'),
        findsOneWidget,
      );
      source['title'] = 'Incoming';
      await edit(tester, 'title', 'Draft');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved, {'title': 'Draft'});
    },
  );
  testWidgets('bulk caret and focus changes do not apply mixed fields', (
    tester,
  ) async {
    final key = GlobalKey<BulkTaskEditorState>();
    BulkTaskEdit? saved;
    await mount(
      tester,
      BulkTaskEditor(
        key: key,
        panel: true,
        tasks: [
          task({'dueDate': '2026-10-02', 'dueTime': '12:30'}),
          task({'dueDate': '2026-10-03', 'dueTime': '13:45'}),
        ],
        onClose: () {},
        onSave: (edit) async {
          saved = edit;
        },
      ),
    );
    for (final field in ['dueDate', 'dueTime', 'startDate']) {
      await tester.ensureVisible(input(field));
      await tester.tap(input(field));
      await tester.pumpAndSettle();
      final text = tester.widget<TextField>(input(field));
      text.controller!.selection = TextSelection.collapsed(
        offset: text.controller!.text.length,
      );
      await tester.pumpAndSettle();
    }
    expect(await key.currentState!.canClose(), isTrue);
    await edit(tester, 'addTags', 'new');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.schedulePatch, isEmpty);
    expect(saved!.addTags, ['new']);
  });
  testWidgets(
    'bulk blank untouched preserves mixed precision; explicit blank clears',
    (tester) async {
      BulkTaskEdit? saved;
      await mount(
        tester,
        BulkTaskEditor(
          panel: true,
          tasks: [
            task({'dueDate': '2026-10-02', 'dueTime': '12:30'}),
            task({'dueDate': '2026-10-03', 'dueTime': '13:45'}),
          ],
          onClose: () {},
          onSave: (edit) async {
            saved = edit;
          },
        ),
      );
      await edit(tester, 'addTags', 'new');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved!.schedulePatch, isEmpty);
      expect(saved!.addTags, ['new']);
      await mount(
        tester,
        BulkTaskEditor(
          key: UniqueKey(),
          panel: true,
          tasks: [
            task({'dueDate': '2026-10-02', 'dueTime': '12:30'}),
            task({'dueDate': '2026-10-03', 'dueTime': '13:45'}),
          ],
          onClose: () {},
          onSave: (edit) async {
            saved = edit;
          },
        ),
      );
      await tester.ensureVisible(input('dueTime'));
      await tester.tap(find.byKey(const ValueKey('dueTimeApply')));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved!.schedulePatch, {'dueTime': null});
    },
  );
  testWidgets('bulk coupled validation reviews every task without writing', (
    tester,
  ) async {
    final writes = <BulkTaskEdit>[];
    await mount(
      tester,
      BulkTaskEditor(
        panel: true,
        tasks: [
          task({'dueDate': '2026-10-02'}),
          task({'dueDate': '2026-10-05'}),
        ],
        onSave: (edit) async {
          writes.add(edit);
        },
      ),
    );
    await edit(tester, 'startDate', '2026-10-03');
    await settleValidation(tester);
    expect(
      fieldError(tester, 'startDate'),
      'Start must be on or before the due date and time.',
    );
    expect(tester.widget<FilledButton>(primaryAction).onPressed, isNotNull);
    await activatePrimary(tester);
    expect(writes, isEmpty);
    expect(
      tester.widget<TextField>(input('startDate')).focusNode!.hasFocus,
      isTrue,
    );
    await edit(tester, 'startDate', '2026-10-01');
    await settleValidation(tester);
    await activatePrimary(tester);
    expect(writes, hasLength(1));
    expect(writes.single.schedulePatch, {'startDate': '2026-10-01'});
  });
  testWidgets(
    'async save disables controls, rejects duplicate submit and keeps failed draft',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          save: (_, a, r) {
            calls++;
            return pending.future;
          },
        ),
      );
      await edit(tester, 'title', 'Draft');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(tester.widget<TextField>(input('title')).enabled, false);
      await tester.tap(find.text('Saving…'));
      expect(calls, 1);
      pending.completeError(StateError('Disk unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);
      expect(find.textContaining('Disk unavailable'), findsOneWidget);
    },
  );
  testWidgets(
    'deletion requires confirmation and delete failure preserves draft',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          save: (_, a, r) async {},
          onDelete: () async {
            calls++;
            throw StateError('failed delete');
          },
        ),
      );
      await edit(tester, 'title', 'Draft');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.textContaining('failed delete'), findsOneWidget);
    },
  );
  testWidgets(
    'invalid tags timezone recurrence and bounds review without submission',
    (tester) async {
      var saves = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task({'dueDate': '2026-10-01'}),
          save: (_, _, _) async {
            saves++;
          },
        ),
      );
      for (final (key, invalid, valid, message) in [
        ('tags', '#', 'old', 'Invalid tags'),
        ('timeZone', 'Imaginary/Zone', '', 'Unknown time zone identifier.'),
        ('recurrence', 'never heard of this', '', 'Unsupported recurrence'),
        (
          'dueMinDays',
          '2.5',
          '',
          'Sort-date bounds must be whole numbers of days.',
        ),
      ]) {
        await edit(tester, key, invalid);
        await settleValidation(tester);
        expect(fieldError(tester, key), contains(message));
        await activatePrimary(tester);
        expect(saves, 0, reason: key);
        expect(
          tester.widget<TextField>(input(key)).focusNode!.hasFocus,
          isTrue,
        );
        await edit(tester, key, valid);
        await settleValidation(tester);
        expect(fieldError(tester, key), isNull);
      }
    },
  );
  testWidgets('panel flag changes retain draft and public close guard', (
    tester,
  ) async {
    final key = GlobalKey<TaskEditorState>();
    final source = task();
    await mount(
      tester,
      TaskEditor(key: key, panel: true, task: source, save: (_, a, r) async {}),
    );
    await edit(tester, 'title', 'Resized draft');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskEditor(
            key: key,
            panel: false,
            task: source,
            save: (_, a, r) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resized draft'), findsOneWidget);
    final closing = key.currentState!.canClose();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await closing, true);
  });
  testWidgets(
    'title and notes limits reveal field-local errors and never save invalid drafts',
    (tester) async {
      var saves = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          save: (_, _, _) async {
            saves++;
          },
        ),
      );
      await edit(tester, 'title', 'x' * 501);
      expect(fieldError(tester, 'title'), isNull);
      await settleValidation(tester);
      expect(
        fieldError(tester, 'title'),
        'Title must be 500 characters or fewer.',
      );
      expect(tester.widget<FilledButton>(primaryAction).onPressed, isNotNull);
      await activatePrimary(tester);
      expect(saves, 0);
      await edit(tester, 'title', 'x' * 500);
      await edit(tester, 'description', 'x' * 10001);
      await settleValidation(tester);
      expect(
        fieldError(tester, 'description'),
        'Notes must be 10000 characters or fewer.',
      );
      await activatePrimary(tester);
      expect(saves, 0);
      expect(
        tester.widget<TextField>(input('description')).focusNode!.hasFocus,
        isTrue,
      );
      await edit(tester, 'description', 'x' * 10000);
      await settleValidation(tester);
      expect(fieldError(tester, 'description'), isNull);
      expect(find.text('Review errors'), findsNothing);
      expect(saves, 0);
    },
  );
  testWidgets('settled Repeat removal clears draft occurrence before Save', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    var saves = 0;
    final original = task({'dueDate': '2026-10-02'});
    await mount(
      tester,
      TaskEditor(
        panel: true,
        task: original,
        onClose: () {},
        save: (fields, _, _) async {
          saves++;
          saved = fields;
        },
      ),
    );
    await edit(tester, 'recurrence', 'every week');
    await edit(tester, 'scheduledDate', '2026-10-03');
    await edit(tester, 'recurrence', '');
    expect(
      tester.widget<TextField>(input('scheduledDate')).controller!.text,
      '2026-10-03',
      reason: 'Transient typing retains the occurrence',
    );
    expect(saved, isNull);
    await settleValidation(tester);
    expect(
      tester.widget<TextField>(input('scheduledDate')).controller!.text,
      '',
    );
    expect(
      tester.widget<TextField>(input('scheduledTime')).controller!.text,
      '',
    );
    expect(
      find.byKey(const ValueKey('occurrence-prerequisite-notice')),
      findsOneWidget,
    );
    expect(saved, isNull);
    await activatePrimary(tester);
    expect(saves, 1);
    expect(
      saved,
      isEmpty,
      reason:
          'Adding and then removing the draft-only Repeat and occurrence '
          'returns to the original schedule without a redundant schedule edit',
    );
    expect(original['schedule'], {'dueDate': '2026-10-02'});
  });
  testWidgets('override actions wrap with narrow viewport and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: TaskEditor(
              panel: true,
              task: task({'scheduledDate': '2026-10-03'}),
              save: (_, a, r) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit existing override'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Edit existing override'),
        matching: find.byType(Wrap),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('host owns Back and opens exactly one discard prompt', (
    tester,
  ) async {
    final key = GlobalKey<TaskEditorState>();
    var guardCalls = 0, closes = 0;
    await mount(
      tester,
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) {
            guardCalls++;
            if (await key.currentState!.canClose()) closes++;
          }
        },
        child: TaskEditor(
          key: key,
          panel: true,
          task: task(),
          onClose: () {
            closes++;
          },
          save: (_, a, r) async {},
        ),
      ),
    );
    expect(
      find.byWidgetPredicate((widget) => widget is PopScope),
      findsOneWidget,
    );
    await edit(tester, 'title', 'Back draft');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(guardCalls, 1);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(closes, 0);
    expect(find.text('Back draft'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(guardCalls, 2);
    expect(closes, 1);
  });
  testWidgets('guard Save commits frozen single draft without closing', (
    tester,
  ) async {
    final key = GlobalKey<TaskEditorState>();
    final source = task();
    Map<String, dynamic>? saved;
    var closed = 0;
    await mount(
      tester,
      TaskEditor(
        key: key,
        panel: true,
        task: source,
        onClose: () {
          closed++;
        },
        save: (fields, a, r) async {
          saved = fields;
        },
      ),
    );
    await edit(tester, 'title', 'Current draft');
    source['description'] = 'Incoming notes';
    final closing = key.currentState!.canClose();
    final duplicate = key.currentState!.canClose();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await closing, true);
    expect(await duplicate, true);
    expect(saved, {'title': 'Current draft'});
    expect(closed, 0);
    expect(find.text('Current draft'), findsOneWidget);
  });
  testWidgets('folder failure is readable and retains the draft for retry', (
    tester,
  ) async {
    var failing = true, attempts = 0, closed = 0;
    final saved = <Map<String, dynamic>>[];
    const message =
        'The data folder is missing tandemlog-space.json. Restore this file or wait for folder sync, then retry.';
    await mount(
      tester,
      TaskEditor(
        task: task(),
        panel: true,
        onClose: () => closed++,
        save: (changes, added, removed) async {
          attempts++;
          if (failing) throw FolderAccessFailure(message);
          saved.add(Map.of(changes));
        },
      ),
    );
    await edit(tester, 'title', 'Retained draft');
    final draft = tester.widget<TextField>(input('title')).controller!.value;
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('Bad state:'), findsNothing);
    expect(tester.widget<TextField>(input('title')).controller!.value, draft);
    expect(attempts, 1);
    expect(closed, 0);
    expect(saved, isEmpty);
    failing = false;
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(closed, 1);
    expect(saved.single['title'], 'Retained draft');
  });

  testWidgets(
    'guard Save validation and write failure retain draft and selection',
    (tester) async {
      final key = GlobalKey<TaskEditorState>();
      var calls = 0, clears = 0;
      final pending = Completer<void>();
      await mount(
        tester,
        TaskEditor(
          key: key,
          panel: true,
          task: task(),
          selectionCount: 1,
          onClearSelection: () async {
            clears++;
          },
          onClose: () {},
          save: (_, a, r) {
            calls++;
            return pending.future;
          },
        ),
      );
      await edit(tester, 'title', '');
      final invalid = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await invalid, false);
      expect(calls, 0);
      expect(find.text('1 selected'), findsOneWidget);
      await edit(tester, 'title', 'Failed draft');
      final failing = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Clear Selection'),
            )
            .onPressed,
        isNull,
      );
      expect(await key.currentState!.canClose(), false);
      pending.completeError(StateError('Storage failure'));
      await tester.pumpAndSettle();
      expect(await failing, false);
      expect(find.text('Failed draft'), findsOneWidget);
      expect(find.textContaining('Storage failure'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(clears, 0);
      await tester.tap(find.text('Clear Selection'));
      await tester.pump();
      expect(clears, 1);
    },
  );
  testWidgets(
    'bulk guard Save applies patch against frozen tasks without closing',
    (tester) async {
      final key = GlobalKey<BulkTaskEditorState>();
      final source = task({'dueDate': '2026-10-05'});
      BulkTaskEdit? saved;
      var closed = 0, clears = 0;
      await mount(
        tester,
        BulkTaskEditor(
          key: key,
          panel: true,
          tasks: [
            source,
            task({'dueDate': '2026-10-06'}),
          ],
          selectionCount: 2,
          onClearSelection: () async {
            clears++;
          },
          onClose: () {
            closed++;
          },
          onSave: (edit) async {
            saved = edit;
          },
        ),
      );
      await tester.tap(find.text('Clear Selection'));
      expect(clears, 1);
      await edit(tester, 'startDate', '2026-10-04');
      source['schedule'] = {'dueDate': '2026-10-01'};
      final closing = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await closing, true);
      expect(saved!.schedulePatch, {'startDate': '2026-10-04'});
      expect(closed, 0);
      expect(find.text('2 selected'), findsNothing);
      expect(find.text('Edit 2 tasks'), findsOneWidget);
    },
  );
  testWidgets('selection header wraps at narrow large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: TaskEditor(
              panel: true,
              task: task(),
              selectionCount: 1,
              onClearSelection: () async {},
              save: (_, a, r) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Clear Selection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'bulk header is compact, wraps accessibly, and Clear retains dirty guard',
    (tester) async {
      final key = GlobalKey<BulkTaskEditorState>();
      var cleared = false;
      Future<void> clear() async {
        if (await key.currentState!.canClose()) cleared = true;
      }

      await mount(
        tester,
        BulkTaskEditor(
          key: key,
          panel: true,
          tasks: [task(), task()],
          selectionCount: 2,
          onClearSelection: clear,
          onSave: (_) async {},
          onClose: () {},
        ),
      );
      final title = find.text('Edit 2 tasks');
      final action = find.text('Clear Selection');
      expect(find.text('2 selected'), findsNothing);
      expect(find.textContaining('Only checked schedule'), findsNothing);
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(action).dy, 1),
      );
      expect(
        tester.getRect(action).left,
        greaterThan(tester.getRect(title).right),
      );
      await edit(tester, 'addTags', 'draft');
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(cleared, false);
      expect(
        tester.widget<TextField>(input('addTags')).controller!.text,
        'draft',
      );
      await tester.binding.setSurfaceSize(const Size(360, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: BulkTaskEditor(
                panel: true,
                tasks: [task(), task()],
                selectionCount: 2,
                onClearSelection: () async {},
                onSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(action).top,
        greaterThanOrEqualTo(tester.getRect(title).bottom),
      );
      expect(tester.getRect(action).right, lessThanOrEqualTo(340));
      expect(tester.takeException(), isNull);
    },
  );
  for (final bulk in [false, true]) {
    testWidgets(
      '${bulk ? 'Bulk' : 'Single'} Task help owns close readiness and stale Done cannot close the editor',
      (tester) async {
        final singleKey = GlobalKey<TaskEditorState>();
        final bulkKey = GlobalKey<BulkTaskEditorState>();
        var writes = 0;
        await mount(
          tester,
          bulk
              ? BulkTaskEditor(
                  key: bulkKey,
                  panel: true,
                  tasks: [
                    task({'dueDate': '2026-10-20'}),
                    task({'dueDate': '2026-10-21'}),
                  ],
                  onSave: (_) async {
                    writes++;
                  },
                )
              : TaskEditor(
                  key: singleKey,
                  panel: true,
                  task: task({'dueDate': '2026-10-20'}),
                  save: (_, _, _) async {
                    writes++;
                  },
                ),
        );
        if (bulk) {
          await edit(tester, 'dueTime', '10:00');
        } else {
          await edit(tester, 'title', 'Synthetic help draft');
        }
        await tester.tap(find.byTooltip('Task field help'));
        await tester.pumpAndSettle();
        expect(
          bulk
              ? bulkKey.currentState!.closeBusy
              : singleKey.currentState!.closeBusy,
          isTrue,
        );
        expect(
          await (bulk
              ? bulkKey.currentState!.canClose()
              : singleKey.currentState!.canClose()),
          isFalse,
        );
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'No draft guard is pushed above owned Help',
        );
        final done = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Done'))
            .onPressed!;
        done();
        done();
        await tester.pumpAndSettle();
        expect(
          bulk
              ? bulkKey.currentState!.closeBusy
              : singleKey.currentState!.closeBusy,
          isFalse,
        );
        expect(find.byType(bulk ? BulkTaskEditor : TaskEditor), findsOneWidget);
        expect(
          tester
              .widget<TextField>(input(bulk ? 'dueTime' : 'title'))
              .controller!
              .text,
          bulk ? '10:00' : 'Synthetic help draft',
        );
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Task held Save disables Help and rejects its captured stale callback',
    (tester) async {
      final completed = Completer<void>();
      var writes = 0, closed = 0;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () => closed++,
          save: (_, _, _) {
            writes++;
            return completed.future;
          },
        ),
      );
      final staleHelp = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Task field help',
            ),
          )
          .onPressed!;
      await edit(tester, 'title', 'Synthetic saving draft');
      await activatePrimary(tester);
      expect(writes, 1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Task field help',
              ),
            )
            .onPressed,
        isNull,
      );
      staleHelp();
      await tester.pumpAndSettle();
      expect(find.text('Task field help'), findsNothing);
      expect(writes, 1);
      completed.complete();
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'occurrence conversion conflict keeps nonrepeat controls editable and values unchanged',
    (tester) async {
      Map<String, dynamic>? saved;
      final original = <String, dynamic>{
        'startDate': '2026-10-06',
        'scheduledDate': '2026-10-05',
        'scheduledTime': '10:00',
        'timeZone': 'America/Chicago',
      };
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: {...task(original), 'kind': 'task'},
          onClose: () {},
          save: (fields, _, _) async {
            saved = fields;
          },
        ),
      );
      expect(
        find.textContaining('This occurrence could not be moved to Due'),
        findsOneWidget,
      );
      expect(input('scheduledDate'), findsOneWidget);
      expect(input('scheduledTime'), findsOneWidget);
      expect(
        tester.widget<TextField>(input('startDate')).controller!.text,
        '2026-10-06',
      );
      expect(
        tester.widget<TextField>(input('scheduledDate')).controller!.text,
        '2026-10-05',
      );
      expect(
        tester.widget<TextField>(input('scheduledTime')).controller!.text,
        '10:00',
      );
      expect(tester.widget<TextField>(input('dueDate')).controller!.text, '');
      expect(saved, isNull);
      await edit(tester, 'dueDate', '2026-10-07');
      await settleValidation(tester);
      await activatePrimary(tester);
      final schedule = saved!['schedule'] as Map;
      expect(schedule['startDate'], '2026-10-06');
      expect(schedule['dueDate'], '2026-10-07');
      expect(schedule['scheduledDate'], '2026-10-05');
      expect(schedule['scheduledTime'], '10:00');
      expect(schedule['timeZone'], 'America/Chicago');
      expect(original, {
        'startDate': '2026-10-06',
        'scheduledDate': '2026-10-05',
        'scheduledTime': '10:00',
        'timeZone': 'America/Chicago',
      });
    },
  );
}
