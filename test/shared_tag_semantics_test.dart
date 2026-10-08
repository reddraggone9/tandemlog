import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/bulk_task_edit.dart';
import 'package:tandemlog/presentation/task_editor.dart';

Map<String, dynamic> taggedTask(String id) => {
  'id': id,
  'title': 'Task $id',
  'description': '',
  'tags': ['retained'],
  'tagRefs': {'reference-$id': 'retained'},
  'schedule': {
    'dueDate': '2026-10-02',
    'dueTime': id == 'first' ? '12:30' : '13:45',
    'recurrence': 'every week when done',
    'timeZone': 'UTC',
  },
};

Future<void> mountTags(WidgetTester tester, Widget editor) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await tester.pumpAndSettle();
}

Future<Finder> tagQuery(WidgetTester tester, String key, String label) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(editable, findsOneWidget);
  final data = tester.getSemantics(editable).getSemanticsData();
  // Material may append its focused hint after the field name.
  expect(data.label.split('\n').first, label);
  expect(data.hasAction(SemanticsAction.setText), isTrue);
  return field;
}

Future<void> submitTag(WidgetTester tester, Finder field, String value) async {
  await tester.enterText(field, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> activateRemove(
  WidgetTester tester,
  String tag,
  String contextLabel,
) async {
  final remove = find.byTooltip('Remove #$tag from $contextLabel');
  expect(remove, findsOneWidget);
  final node = tester.getSemantics(remove);
  expect(node.getSemanticsData().tooltip, 'Remove #$tag from $contextLabel');
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await tester.pumpAndSettle();
}

// The pinned testWidgets API enables semantics by default. Icon controls expose
// contextual names in SemanticsData.tooltip, while query labels use .label.
void main() {
  testWidgets(
    'query clear and dropdown actions identify every editing context',
    (tester) async {
      for (final context in [
        ('tags', 'Tags'),
        ('addTags', 'Add tags'),
        ('removeTags', 'Remove tags'),
      ]) {
        await mountTags(
          tester,
          context.$1 == 'tags'
              ? TaskEditor(
                  panel: true,
                  task: taggedTask('first'),
                  onClose: () {},
                  save: (_, _, _) async {},
                )
              : BulkTaskEditor(
                  panel: true,
                  tasks: [taggedTask('first'), taggedTask('second')],
                  onClose: () {},
                  onSave: (_) async {},
                ),
        );
        final expand = find.byTooltip('Expand ${context.$2} options');
        expect(expand, findsOneWidget);
        await tester.ensureVisible(expand);
        await tester.pumpAndSettle();
        final expandNode = tester.getSemantics(expand);
        expect(
          expandNode.getSemanticsData().tooltip,
          'Expand ${context.$2} options',
        );
        expect(
          expandNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expandNode.owner!.performAction(expandNode.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Collapse ${context.$2} options'),
          findsOneWidget,
        );
        final field = await tagQuery(tester, context.$1, context.$2);
        await tester.enterText(field, 'ret');
        await tester.pumpAndSettle();
        final clear = find.byTooltip('Clear ${context.$2}');
        expect(clear, findsOneWidget);
        final clearNode = tester.getSemantics(clear);
        expect(clearNode.getSemanticsData().tooltip, 'Clear ${context.$2}');
        expect(
          clearNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        clearNode.owner!.performAction(clearNode.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        expect(find.byType(InputChip), findsNothing);
        expect(find.byKey(const ValueKey('tag-option-retained')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editor exposes named query and removable selected tags', (
    tester,
  ) async {
    List<String>? added;
    List<String>? removed;
    await mountTags(
      tester,
      TaskEditor(
        panel: true,
        task: taggedTask('first'),
        onClose: () {},
        save: (_, a, r) async {
          added = a;
          removed = r;
        },
      ),
    );
    await tagQuery(tester, 'tags', 'Tags');
    expect(find.byKey(const ValueKey('selected-tag-retained')), findsOneWidget);
    await activateRemove(tester, 'retained', 'Tags');
    expect(find.byKey(const ValueKey('selected-tag-retained')), findsNothing);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(added, isEmpty);
    expect(removed, ['retained']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bulk suggestions are readable and semantics activation is local',
    (tester) async {
      await mountTags(
        tester,
        BulkTaskEditor(
          panel: true,
          tasks: [taggedTask('first'), taggedTask('second')],
          onClose: () {},
          onSave: (_) async {},
        ),
      );
      for (final context in [
        ('addTags', 'Add tags'),
        ('removeTags', 'Remove tags'),
      ]) {
        final query = await tagQuery(tester, context.$1, context.$2);
        await tester.enterText(query, 'ret');
        await tester.pumpAndSettle();
        final suggestion = find.byKey(const ValueKey('tag-option-retained'));
        expect(suggestion, findsOneWidget);
        final node = tester.getSemantics(suggestion);
        final data = node.getSemanticsData();
        expect(data.label, contains('#retained'));
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.flagsCollection.isSelected, Tristate.isFalse);
        expect(tester.getRect(suggestion).height, greaterThanOrEqualTo(48));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-option-retained')), findsNothing);
        expect(
          find.byTooltip('Remove #retained from ${context.$2}'),
          findsOneWidget,
        );
        await tester.enterText(query, 'ret');
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(suggestion)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        // Removal activates only this context; another bulk field has its own
        // selected set even when the tag text is identical.
        await activateRemove(tester, 'retained', context.$2);
        expect(
          find.byTooltip('Remove #retained from ${context.$2}'),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bulk chip actions preserve independent deltas and Apply state', (
    tester,
  ) async {
    BulkTaskEdit? saved;
    await mountTags(
      tester,
      BulkTaskEditor(
        panel: true,
        tasks: [taggedTask('first'), taggedTask('second')],
        onClose: () {},
        onSave: (edit) async => saved = edit,
      ),
    );
    final apply = find.byWidgetPredicate(
      (widget) =>
          widget is Checkbox && widget.semanticLabel == 'Apply Due time',
    );
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(apply);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    await submitTag(
      tester,
      await tagQuery(tester, 'addTags', 'Add tags'),
      'new',
    );
    await submitTag(
      tester,
      await tagQuery(tester, 'removeTags', 'Remove tags'),
      'retained',
    );
    expect(find.byTooltip('Remove #new from Add tags'), findsOneWidget);
    expect(find.byTooltip('Remove #retained from Remove tags'), findsOneWidget);
    await activateRemove(tester, 'new', 'Add tags');
    expect(find.byTooltip('Remove #retained from Remove tags'), findsOneWidget);
    await submitTag(
      tester,
      await tagQuery(tester, 'addTags', 'Add tags'),
      'new',
    );
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((widget) => widget.value == true)
          .map((widget) => widget.semanticLabel),
      ['Apply Due time'],
    );
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.addTags, ['new']);
    expect(saved!.removeTags, ['retained']);
    expect(saved!.schedulePatch, {'dueTime': null});
    expect(saved!.assignee, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Saving freezes tag editing and chip removal in both bulk contexts',
    (tester) async {
      final saving = Completer<void>();
      var calls = 0, closed = 0;
      await mountTags(
        tester,
        BulkTaskEditor(
          panel: true,
          tasks: [taggedTask('first'), taggedTask('second')],
          onClose: () => closed++,
          onSave: (_) {
            calls++;
            return saving.future;
          },
        ),
      );
      await submitTag(
        tester,
        await tagQuery(tester, 'addTags', 'Add tags'),
        'new',
      );
      await submitTag(
        tester,
        await tagQuery(tester, 'removeTags', 'Remove tags'),
        'retained',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      for (final key in ['addTags', 'removeTags']) {
        final field = find.byKey(ValueKey(key));
        expect(tester.widget<TextField>(field).enabled, isFalse);
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final data = tester.getSemantics(editable).getSemanticsData();
        expect(
          data.label.split('\n').first,
          key == 'addTags' ? 'Add tags' : 'Remove tags',
        );
        expect(data.hasAction(SemanticsAction.setText), isFalse);
        final label = key == 'addTags' ? 'Add tags' : 'Remove tags';
        for (final tooltip in ['Clear $label', 'Expand $label options']) {
          final named = find.byTooltip(tooltip);
          expect(named, findsOneWidget);
          expect(
            tester
                .getSemantics(named)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
        }
      }
      expect(find.byType(InputChip), findsNWidgets(2));
      for (final chip in tester.widgetList<InputChip>(find.byType(InputChip))) {
        expect(chip.onDeleted, isNull);
      }
      expect(find.byKey(const ValueKey('tag-option-retained')), findsNothing);
      expect(calls, 1);
      saving.complete();
      await tester.pumpAndSettle();
      expect(closed, 1, reason: 'successful Submit asks the host to close');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(find.byType(BulkTaskEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
