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
