import 'package:tandemlog/presentation/unsaved_draft_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';

void main() {
  for (final checklist in [false, true]) {
    for (final answer in ['Cancel', 'Discard', 'Save']) {
      testWidgets(
        '${checklist ? 'checklist' : 'task'} repeated unsaved $answer owns only its dialog',
        (tester) async {
          var saves = 0;
          String? savedNotes;
          await tester.binding.setSurfaceSize(const Size(900, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: Column(
                            children: [
                              const Text('Containing route'),
                              TextButton(
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => checklist
                                      ? ChecklistItemEditor(
                                          item: const {
                                            'id': 'synthetic-item',
                                            'title': 'Original item',
                                            'description': 'Original notes',
                                          },
                                          save: (_, notes) async {
                                            saves++;
                                            savedNotes = notes;
                                          },
                                        )
                                      : TaskEditor(
                                          task: const {
                                            'id': 'synthetic-task',
                                            'title': 'Original task',
                                            'description': 'Original notes',
                                            'assignee': null,
                                            'tags': <String>[],
                                            'tagRefs': <String, String>{},
                                            'schedule': <String, Object?>{},
                                          },
                                          save: (changes, _, _) async {
                                            saves++;
                                            savedNotes =
                                                changes['description']
                                                    as String?;
                                          },
                                        ),
                                ),
                                child: const Text('Open editor'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open containing route'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open containing route'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open editor'));
          await tester.pumpAndSettle();
          final notes = find.byKey(
            ValueKey(checklist ? 'checklist-item-notes' : 'description'),
          );
          await tester.ensureVisible(notes);
          await tester.enterText(notes, 'Preserve this draft');
          await tester.pump();
          await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
          await tester.pumpAndSettle();
          expect(find.text('Unsaved changes'), findsOneWidget);
          final button = answer == 'Save'
              ? tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, answer).last,
                    )
                    .onPressed!
              : tester
                    .widget<TextButton>(
                      find.widgetWithText(TextButton, answer).last,
                    )
                    .onPressed!;
          // Two queued activations can arrive before the pop transition removes
          // the first button. Both must refer to this same confirmation route.
          button();
          button();
          await tester.pumpAndSettle();
          expect(find.text('Containing route'), findsOneWidget);
          expect(find.text('Unsaved changes'), findsNothing);
          expect(saves, answer == 'Save' ? 1 : 0);
          if (answer == 'Cancel') {
            expect(notes, findsOneWidget);
            expect(
              tester.widget<TextField>(notes).controller!.text,
              'Preserve this draft',
            );
          } else {
            expect(
              find.byType(checklist ? ChecklistItemEditor : TaskEditor),
              findsNothing,
            );
          }
          if (answer == 'Save') expect(savedNotes, 'Preserve this draft');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  testWidgets('externally dismissed dialog ignores retained late answers', (
    tester,
  ) async {
    Future<String?>? pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pending = askUnsavedDraft(context),
              child: const Text('Synthetic root'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Synthetic root'));
    await tester.pumpAndSettle();
    final staleAnswer = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
        .onPressed!;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await pending, isNull);
    expect(staleAnswer, returnsNormally);
    expect(staleAnswer, returnsNormally);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
