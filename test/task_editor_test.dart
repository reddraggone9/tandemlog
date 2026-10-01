import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';

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

void main() {
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
  testWidgets('live schedule validation and repeat conditional fields', (
    tester,
  ) async {
    await mount(
      tester,
      TaskEditor(panel: true, task: task(), save: (_, a, r) async {}),
    );
    expect(input('scheduledDate'), findsNothing);
    expect(find.text('Date must be YYYY-MM-DD.'), findsNothing);
    await edit(tester, 'dueDate', 'bad');
    expect(find.text('Date must be YYYY-MM-DD.'), findsOneWidget);
    await edit(tester, 'dueDate', '2026-10-01');
    await edit(tester, 'startDate', '2026-10-02');
    expect(
      find.text('Start must be on or before the due date and time.'),
      findsOneWidget,
    );
    await edit(tester, 'startDate', '2026-09-30');
    await edit(tester, 'recurrence', 'every week');
    expect(input('scheduledDate'), findsOneWidget);
    expect(
      find.text('Start must be on or before the due date and time.'),
      findsNothing,
    );
  });
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
      expect(input('scheduledDate'), findsNothing);
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
      final row = find
          .ancestor(of: input('dueTime'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved!.schedulePatch, {'dueTime': null});
    },
  );
  testWidgets('bulk coupled validation checks every task', (tester) async {
    await mount(
      tester,
      BulkTaskEditor(
        panel: true,
        tasks: [
          task({'dueDate': '2026-10-02'}),
          task({'dueDate': '2026-10-05'}),
        ],
        onSave: (edit) async {},
      ),
    );
    await edit(tester, 'startDate', '2026-10-03');
    expect(
      find.text('Start must be on or before the due date and time.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
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
    'invalid tags timezone recurrence and bounds block submission live',
    (tester) async {
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task({'dueDate': '2026-10-01'}),
          save: (_, a, r) async {},
        ),
      );
      await edit(tester, 'tags', '#');
      expect(find.textContaining('Invalid tags'), findsOneWidget);
      await edit(tester, 'tags', 'old');
      await edit(tester, 'timeZone', 'Imaginary/Zone');
      expect(find.text('Unknown time zone identifier.'), findsOneWidget);
      await edit(tester, 'timeZone', '');
      await edit(tester, 'recurrence', 'never heard of this');
      expect(find.textContaining('Unsupported recurrence'), findsOneWidget);
      await edit(tester, 'recurrence', '');
      await edit(tester, 'dueMinDays', '2.5');
      expect(
        find.text('Sort-date bounds must be whole numbers of days.'),
        findsOneWidget,
      );
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
  testWidgets('title and notes wire limits validate before save', (
    tester,
  ) async {
    var saves = 0;
    await mount(
      tester,
      TaskEditor(
        panel: true,
        task: task(),
        save: (_, a, r) async {
          saves++;
        },
      ),
    );
    await edit(tester, 'title', 'x' * 501);
    expect(find.text('Title must be 500 characters or fewer.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    await edit(tester, 'title', 'x' * 500);
    await edit(tester, 'description', 'x' * 10001);
    expect(
      find.text('Notes must be 10000 characters or fewer.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed,
      isNull,
    );
    expect(saves, 0);
    await edit(tester, 'description', 'x' * 10000);
    expect(find.text('Notes must be 10000 characters or fewer.'), findsNothing);
  });
  testWidgets('draft occurrence remains accessible after removing repeat', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await mount(
      tester,
      TaskEditor(
        panel: true,
        task: task({'dueDate': '2026-10-02'}),
        onClose: () {},
        save: (fields, a, r) async {
          saved = fields;
        },
      ),
    );
    await edit(tester, 'recurrence', 'every week');
    await edit(tester, 'scheduledDate', '2026-10-03');
    await edit(tester, 'recurrence', '');
    expect(input('scheduledDate'), findsNothing);
    expect(
      find.text('Existing occurrence override is preserved.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Edit existing override'));
    await tester.tap(find.text('Edit existing override'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-03'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect((saved!['schedule'] as Map)['scheduledDate'], '2026-10-03');
    expect((saved!['schedule'] as Map)['recurrence'], null);
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
}
