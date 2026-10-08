import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/presentation/task_editor.dart';

Map<String, dynamic> task() => {
  'id': 'test',
  'title': 'Original',
  'description': '',
  'tags': ['old'],
  'tagRefs': {'ref': 'old'},
  'schedule': <String, dynamic>{},
};
Future<void> mount(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> query(WidgetTester tester, String key, String text) async {
  final input = find.byKey(ValueKey(key));
  await tester.ensureVisible(input);
  await tester.enterText(input, text);
  await tester.pump();
}

void main() {
  testWidgets(
    'removing a chip retains unrelated query, caret, and active composition',
    (tester) async {
      List<String>? added, removed;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () {},
          save: (_, a, r) async {
            added = a;
            removed = r;
          },
        ),
      );
      await query(tester, 'tags', 'Fresh');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('tags')),
      );
      const value = TextEditingValue(
        text: 'Fresh',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 5),
      );
      field.controller!.value = value;
      await tester.pump();
      tester
          .widget<InputChip>(find.byKey(const ValueKey('selected-tag-old')))
          .onDeleted!();
      await tester.pumpAndSettle();
      expect(
        field.controller!.value,
        value,
        reason: 'chip deletion must not consume query',
      );
      field.controller!.value = value.copyWith(composing: TextRange.empty);
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(added, ['Fresh']);
      expect(removed, ['old']);
    },
  );

  testWidgets(
    'Enter uses existing match idempotently and Save resolves opaque pending inventory tag',
    (tester) async {
      List<String>? added, removed;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () {},
          tagInventory: const ['Home Office', '#literal', 'Planning'],
          save: (_, a, r) async {
            added = a;
            removed = r;
          },
        ),
      );
      await query(tester, 'tags', 'plan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('selected-tag-Planning')),
        findsOneWidget,
      );
      await query(tester, 'tags', 'Planning');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('selected-tag-Planning')),
        findsOneWidget,
      );
      await query(tester, 'tags', 'Home Office');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(added, ['Planning', 'Home Office']);
      expect(removed, isEmpty);
    },
  );

  testWidgets(
    'touch creation adds all new tokens and invalid query never enables it',
    (tester) async {
      List<String>? added;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () {},
          save: (_, a, r) async {
            added = a;
          },
        ),
      );
      await query(tester, 'tags', '#');
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListTile>(find.byKey(const ValueKey('tag-create'))).onTap,
        isNull,
      );
      await query(tester, 'tags', 'new another');
      await tester.pumpAndSettle();
      final create = find.byKey(const ValueKey('tag-create'));
      expect(
        find.descendant(of: create, matching: find.text('Add tags')),
        findsOneWidget,
      );
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selected-tag-new')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('selected-tag-another')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(added, ['new', 'another']);
    },
  );

  testWidgets(
    'opaque original tags survive pending Save with exact case and spaces',
    (tester) async {
      List<String>? added, removed;
      final original = {
        ...task(),
        'tags': ['Home', 'home', 'legacy tag', '#literal'],
        'tagRefs': {
          'a': 'Home',
          'b': 'home',
          'c': 'legacy tag',
          'd': '#literal',
        },
      };
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: original,
          onClose: () {},
          save: (_, a, r) async {
            added = a;
            removed = r;
          },
        ),
      );
      await query(tester, 'tags', '#new');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(added, ['new']);
      expect(
        removed,
        isEmpty,
        reason: 'original values remain opaque identities',
      );
      for (final tag in original['tags'] as List<String>) {
        expect(find.byKey(ValueKey('selected-tag-$tag')), findsOneWidget);
      }
    },
  );

  testWidgets('failed Save retains selected chips and exact pending query', (
    tester,
  ) async {
    var attempts = 0;
    await mount(
      tester,
      TaskEditor(
        panel: true,
        task: task(),
        onClose: () {},
        save: (_, a, r) async {
          attempts++;
          throw const FormatException('Synthetic save failure');
        },
      ),
    );
    await query(tester, 'tags', '#new');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byKey(const ValueKey('selected-tag-old')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tags')))
          .controller!
          .text,
      '#new',
    );
  });

  testWidgets('active tag composition blocks Save and canClose Save', (
    tester,
  ) async {
    final key = GlobalKey<TaskEditorState>();
    var saves = 0;
    await mount(
      tester,
      TaskEditor(
        key: key,
        panel: true,
        task: task(),
        onClose: () {},
        save: (_, a, r) async {
          saves++;
        },
      ),
    );
    await query(tester, 'tags', 'new');
    final field = tester.widget<TextField>(find.byKey(const ValueKey('tags')));
    field.controller!.value = const TextEditingValue(
      text: 'new',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    final closing = key.currentState!.canClose();
    await tester.pumpAndSettle();
    expect(await closing, isFalse);
    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason:
          'Do not take focus and finalize active composition through a dialog.',
    );
    expect(saves, 0);
    expect(field.controller!.text, 'new');
  });

  testWidgets(
    'single Save adds pending query without replacing selected tags',
    (tester) async {
      List<String>? added, removed;
      await mount(
        tester,
        TaskEditor(
          panel: true,
          task: task(),
          onClose: () {},
          save: (_, a, r) async {
            added = a;
            removed = r;
          },
        ),
      );
      await query(tester, 'tags', '#new another');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(added, ['new', 'another']);
      expect(
        removed,
        isEmpty,
        reason: 'query entry does not replace the old chip',
      );
    },
  );

  testWidgets(
    'pending query participates in canClose; Cancel retains it, Save commits it',
    (tester) async {
      final key = GlobalKey<TaskEditorState>();
      final calls = <List<String>>[];
      await mount(
        tester,
        TaskEditor(
          key: key,
          panel: true,
          task: task(),
          onClose: () {},
          save: (_, added, removed) async => calls.add(removed),
        ),
      );
      expect(find.byKey(const ValueKey('selected-tag-old')), findsOneWidget);
      await query(tester, 'tags', 'new');
      final first = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tags')))
            .controller!
            .text,
        'new',
      );
      expect(calls, isEmpty);
      final second = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(await second, isTrue);
      expect(calls, [<String>[]]);
    },
  );

  testWidgets(
    'bulk Remove cannot create an unknown tag from an unfinished query',
    (tester) async {
      final saved = <BulkTaskEdit>[];
      await mount(
        tester,
        BulkTaskEditor(
          panel: true,
          tasks: [
            task(),
            {...task(), 'id': 'second'},
          ],
          onClose: () {},
          onSave: (edit) async => saved.add(edit),
        ),
      );
      await query(tester, 'removeTags', 'not-in-inventory');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        saved,
        isEmpty,
        reason:
            'Remove selects existing tags and must retain an unmatched query',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('removeTags')))
            .controller!
            .text,
        'not-in-inventory',
      );
    },
  );
}
