import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCompletionFocusTests();
}

void registerCompletionFocusTests() {
  for (final variant in const [
    (appearance: 'light', size: Size(1200, 800), scale: 1.0, repeating: false),
    (appearance: 'dark', size: Size(390, 800), scale: 1.0, repeating: false),
    (appearance: 'dark', size: Size(390, 800), scale: 2.0, repeating: true),
  ]) {
    testWidgets(
      'checkbox focus ${variant.appearance} ${variant.size.width} x${variant.scale}: ${variant.repeating ? 'historical v3 recurrence compatibility' : 'offline native task'}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('completion-focus-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final writer = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/writer',
        );
        final user = const Uuid().v4(), task = const Uuid().v4();
        try {
          await writer.command(user, 'user.created', {'name': 'Alex Example'});
          await (variant.repeating
              ? writer.createHistoricalRecurrenceFixtureTask
              : writer.createNativeFixtureTask)(task, {
            'title': 'Focus reference task',
            'description': '',
            'assignee': user,
            'schedule': {
              'dueDate': '2026-10-01',
              if (variant.repeating) 'recurrence': 'every week when done',
            },
          });
          await File('${profile.path}/settings.json').writeAsString(
            jsonEncode({
              'folder': folder.path,
              'user': user,
              'appearance': variant.appearance,
            }),
          );
          tester.view.physicalSize = variant.size;
          tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              timeSourceFactory: (onChanged) => ViewTimeSource(
                onChanged: onChanged,
                loadZone: () async => 'UTC',
                now: () => DateTime.utc(2026, 10, 2, 12),
              ),
            ),
          );
          Finder checkbox() => find.descendant(
            of: find.byKey(ValueKey('task-row-$task')),
            matching: find.byType(Checkbox),
          );
          FocusNode checkboxFocus() => Focus.of(
            tester.element(
              find
                  .descendant(
                    of: checkbox(),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            ),
          );
          await flows.waitForUi(tester, () => checkbox().evaluate().isNotEmpty);
          await tester.tap(find.byTooltip('Search all tasks (Ctrl+F)'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('task-search')),
            'Focus reference',
          );
          await tester.pumpAndSettle();
          final focus = checkboxFocus();
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(focus));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await flows.waitForUi(
            tester,
            () => tester.widget<Checkbox>(checkbox()).value == true,
          );
          expect(
            checkboxFocus(),
            same(focus),
            reason: 'The same visible task changed status group.',
          );
          expect(FocusManager.instance.primaryFocus, same(focus));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await flows.waitForUi(
            tester,
            () => tester.widget<Checkbox>(checkbox()).value == false,
          );
          expect(checkboxFocus(), same(focus));
          expect(FocusManager.instance.primaryFocus, same(focus));
          await writer.editNativeFixtureTask(task, {
            'schedule': {
              'dueDate': '2026-10-03',
              if (variant.repeating) 'recurrence': 'every week when done',
            },
          });
          await flows.waitForUi(
            tester,
            () => find.text('Saturday · 2026-10-03').evaluate().isNotEmpty,
          );
          expect(
            checkboxFocus(),
            same(focus),
            reason: 'A remote date edit regrouped the same visible task.',
          );
          expect(FocusManager.instance.primaryFocus, same(focus));
          Future<int> completionCount() async {
            var count = 0;
            await for (final file in folder.list()) {
              if (file is! File || !file.path.endsWith('.jsonl')) continue;
              for (final line in await file.readAsLines()) {
                final event = jsonDecode(line) as Map;
                if (event['entity'] == task &&
                    event['type'] == 'task.completed') {
                  count++;
                }
              }
            }
            return count;
          }

          // Two callbacks in one write window must not queue another command.
          final before = await completionCount();
          final onChanged = tester.widget<Checkbox>(checkbox()).onChanged!;
          onChanged(true);
          onChanged(true);
          await flows.waitForUi(
            tester,
            () => tester.widget<Checkbox>(checkbox()).value == true,
          );
          expect(await completionCount(), before + 1);
          expect(FocusManager.instance.primaryFocus, same(focus));

          // Deliberate traversal must remain deliberate: no post-write focus
          // restoration may pull focus back to this checkbox.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, isNot(same(focus)));
          final otherFocus = FocusManager.instance.primaryFocus;
          await writer.editNativeFixtureTask(task, {
            'schedule': {
              'dueDate': '2026-10-04',
              if (variant.repeating) 'recurrence': 'every week when done',
            },
          });
          await flows.waitForUi(
            tester,
            () => find.text('Sunday · 2026-10-04').evaluate().isNotEmpty,
          );
          expect(FocusManager.instance.primaryFocus, same(otherFocus));

          // Leaving the filtered view is different from regrouping a visible
          // row: release removed-row focus without reopening a hidden task.
          tester.widget<Checkbox>(checkbox()).onChanged!(false);
          await flows.waitForUi(
            tester,
            () => tester.widget<Checkbox>(checkbox()).value == false,
          );
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pumpAndSettle();
          final removedFocus = checkboxFocus();
          removedFocus.requestFocus();
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(removedFocus));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await flows.waitForUi(tester, () => checkbox().evaluate().isEmpty);
          expect(FocusManager.instance.primaryFocus, isNot(same(removedFocus)));
          final completed = await completionCount();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(await completionCount(), completed);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await writer.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
