import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
  registerCompletionActionTests();
}

void registerCompletionActionTests() {
  testWidgets(
    'historical v3 recurrence compatibility: checked completion, failed reopen and Undo',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('completion-native-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(),
          plain = const Uuid().v4(),
          repeat = const Uuid().v4();
      try {
        await writer.command(user, 'user.created', {'name': 'Alex Example'});
        for (final id in [plain, repeat]) {
          await (id == repeat
              ? writer.createHistoricalRecurrenceFixtureTask
              : writer.createNativeFixtureTask)(id, {
            'title': id == plain ? 'Buy envelopes' : 'Water plants',
            'description': '',
            'assignee': user,
            'schedule': {
              'dueDate': '2026-10-01',
              if (id == repeat) 'recurrence': 'every week when done',
            },
          });
        }
        await writer.complete(plain, completionDay: DateTime.utc(2026, 10, 2));
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
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
        Finder check(String id) => find.descendant(
          of: find.byKey(ValueKey('task-row-$id')),
          matching: find.byType(Checkbox),
        );
        Finder vector(String id) => find.descendant(
          of: find.byKey(ValueKey('task-row-$id')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.size == const Size(18, 26),
          ),
        );
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        expect(vector(repeat), findsOneWidget);
        await tester.tap(check(repeat));
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        await flows.filterChoice(tester, 'Completed');
        for (final id in [plain, repeat]) {
          expect(tester.widget<Checkbox>(check(id)).value, isTrue);
          expect(tester.widget<Checkbox>(check(id)).side, isNull);
          expect(tester.getSize(check(id)), const Size(48, 48));
          expect(vector(id), findsNothing);
        }
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();
        final canonical = {
          await for (final file in folder.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        };
        final manifest = File('${folder.path}/tandemlog-space.json');
        final saved = await manifest.rename(
          '${root.path}/manifest-backup.json',
        );
        await tester.tap(check(repeat));
        await flows.waitForUi(
          tester,
          () =>
              find.textContaining('tandemlog-space.json').evaluate().isNotEmpty,
        );
        expect(find.text('Task reopened; next occurrence kept.'), findsNothing);
        await flows.waitForUi(
          tester,
          () => find.text('Retry').evaluate().isNotEmpty,
        );
        await saved.rename(manifest.path);
        await tester.tap(find.text('Retry').first);
        await flows.waitForUi(
          tester,
          () => find.textContaining('tandemlog-space.json').evaluate().isEmpty,
        );
        expect({
          await for (final file in folder.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        }, canonical);
        expect(tester.widget<Checkbox>(check(repeat)).value, isTrue);
        await tester.tap(check(repeat));
        await flows.waitForUi(
          tester,
          () => find
              .text('Task reopened; next occurrence kept.')
              .evaluate()
              .isNotEmpty,
        );
        await flows.filterChoice(tester, 'Open');
        expect(tester.widget<Checkbox>(check(repeat)).value, isFalse);
        expect(vector(repeat), findsOneWidget);
        await writer.refresh();
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 3);
        // Checkbox Reopen retains the successor. Undo reopening restores
        // completion; true Undo completion retracts its untouched successor.
        final undo = find.byKey(const ValueKey('undo-task-action'));
        await tester.tap(undo);
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        await tester.tap(undo);
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        await writer.refresh();
        expect(
          writer.rows.firstWhere((r) => r['id'] == repeat)['completed'],
          false,
        );
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 2);
        expect(
          find.textContaining('Untouched next occurrence retracted.'),
          findsOneWidget,
        );
        await tester.tap(check(repeat));
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        final next = const Uuid().v5(repeat, 'successor');
        // This derived successor retains its original unactivated v3 text semantics.
        await writer.command(next, 'task.edited', {
          'title': 'Water balcony plants',
        });
        await flows.waitForUi(
          tester,
          () => find.text('Water balcony plants').evaluate().isNotEmpty,
        );
        await tester.tap(undo);
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        expect(
          find.textContaining(
            'Next occurrence kept to preserve other changes.',
          ),
          findsOneWidget,
        );
        expect(find.text('Water balcony plants'), findsOneWidget);
        await writer.refresh();
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 3);
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
