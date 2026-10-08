import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:uuid/uuid.dart';

import 'task_flow_test.dart' as flows;
import 'native_text_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTextWorkflowTests();
}

void registerTextWorkflowTests() {
  testWidgets(
    'offline new text, remote draft Save, Undo and explicit legacy setup',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('native-text-ui-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4(), legacy = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Alex Example'});
      await seed.command(legacy, 'task.created', {
        'title': 'Legacy reference',
        'description': '',
        'assignee': user,
      });
      await seed.close();
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      final engine = NativeTextEngine();
      final peer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/peer',
        textEngine: engine,
      );
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Legacy reference').evaluate().isNotEmpty,
        );
        final capture = find.widgetWithText(TextField, 'One task per line');
        await tester.enterText(capture, 'Shared draft');
        await tester.tap(find.byKey(const ValueKey('capture-add')));
        await flows.waitForUi(
          tester,
          () => find.text('Shared draft').evaluate().isNotEmpty,
        );
        await peer.refresh();
        final created = peer.rows.singleWhere(
          (row) => row['title'] == 'Shared draft',
        );
        final id = created['id'] as String;
        expect(peer.sharedTextInitialized, isFalse);
        await flows.selectTask(tester, id, control: false);
        final title = find.byKey(const ValueKey('title'));
        expect(tester.widget<TextField>(title).enabled, isTrue);
        await tester.enterText(title, 'Shared draft locally');
        final captured = await peer.captureTaskText(id);
        final remote = TaskTextSession(
          captured,
          registerDraftActor: (field, allocation, actor) =>
              peer.registerTextDraftActor(captured, field, allocation, actor),
        );
        remote.replace('title', 'Remote Shared draft');
        await TextSaveCommand(
          peer,
          remote,
        ).save(fields: {}, tags: [], observedTagRefs: {});
        remote.cancel();
        peer.releaseTextCapture(captured);
        await flows.waitForUi(
          tester,
          () => find.text('Remote Shared draft').evaluate().isNotEmpty,
        );
        expect(
          tester.widget<TextField>(title).controller!.text,
          'Shared draft locally',
        );
        await _capture(tester, 'wide-private-draft');
        await tester.tap(find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () => find.text('Remote Shared draft locally').evaluate().isNotEmpty,
        );
        if (find.text('Cancel').evaluate().isNotEmpty) {
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('undo-task-action')));
        await flows.waitForUi(
          tester,
          () => find.text('Remote Shared draft').evaluate().isNotEmpty,
        );
        await peer.refresh();
        expect(
          peer.rows.singleWhere((row) => row['id'] == id)['title'],
          'Remote Shared draft',
        );

        await flows.selectTask(tester, legacy, control: false);
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('title'))).enabled,
          isFalse,
        );
        expect(
          find.textContaining('Set up shared text editing in Settings'),
          findsOneWidget,
        );
        await _capture(tester, 'wide-legacy-gate');
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        await flows.openSettings(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('initialize-shared-text')),
        );
        await tester.tap(find.byKey(const ValueKey('initialize-shared-text')));
        await tester.pumpAndSettle();
        await _capture(tester, 'wide-shared-setup');
        await tester.tap(find.widgetWithText(FilledButton, 'Set up'));
        await tester.pumpAndSettle();
        await peer.refresh();
        expect(peer.sharedTextInitialized, isTrue);
        tester.view.physicalSize = const Size(390, 820);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        await flows.selectTask(tester, legacy, control: false);
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('title'))).enabled,
          isTrue,
        );
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Legacy reference edited',
        );
        await _capture(tester, 'narrow-dark200-legacy-edit');
        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () => find.text('Legacy reference edited').evaluate().isNotEmpty,
        );
        await peer.refresh();
        expect(
          peer.rows.singleWhere((row) => row['id'] == legacy)['title'],
          'Legacy reference edited',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Legacy reference edited').evaluate().isNotEmpty,
        );
        expect(find.text('Remote Shared draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'narrow-dark200-restart');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await peer.close();
        engine.dispose();
        // Synthetic profile remains available for a failed test's diagnosis.
      }
    },
  );
  testWidgets(
    'historical successor recompletion completes parent and keeps independent child',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'native-recurring-guard-ui-',
      );
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final store = await openNativeFixtureStore(
        LocalLogFolder(shared.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4(), task = const Uuid().v4();
      try {
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.createHistoricalRecurrenceFixtureTask(task, {
          'title': 'Native recurring reference',
          'description': '',
          'assignee': user,
          'schedule': {
            'dueDate': '2026-10-01',
            'recurrence': 'every day when done',
          },
        });
        // This historical child already has scalar initialization. Activating
        // its parent must not silently rebase the child's native identities.
        final completion = await store.complete(
          task,
          completionDay: DateTime(2026, 10, 1),
        );
        await store.command(const Uuid().v5(task, 'successor'), 'task.edited', {
          'title': 'Existing next occurrence',
          'description': 'Independent child notes',
        });
        await store.initializeSharedText();
        await store.reopen(task, [completion.id]);
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        final parentCheckbox = find.descendant(
          of: find.byKey(ValueKey('task-row-$task')),
          matching: find.byType(Checkbox),
        );
        await flows.waitForUi(
          tester,
          () => parentCheckbox.evaluate().isNotEmpty,
        );
        Future<Map<String, String>> canonical() async => {
          await for (final file in shared.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        };
        final before = await canonical();
        final child = const Uuid().v5(task, 'successor');
        final beforeChild = store.rows.singleWhere((row) => row['id'] == child);
        await _capture(tester, 'historical-recompletion-before');
        await tester.tap(parentCheckbox);
        await flows.waitForUi(tester, () => parentCheckbox.evaluate().isEmpty);
        await store.refresh();
        final after = await canonical();
        for (final entry in before.entries) {
          expect(after[entry.key], entry.value);
        }
        expect(
          store.db.select(
            "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.completedKeepingSuccessor'",
          ),
          hasLength(1),
        );
        expect(
          store.rows.singleWhere((row) => row['id'] == task)['completed'],
          isTrue,
        );
        expect(
          store.rows.singleWhere((row) => row['id'] == child),
          beforeChild,
        );
        await _capture(tester, 'historical-recompletion-after');
        expect(store.rows.where((row) => row['kind'] == 'task'), hasLength(2));
        expect(store.pendingTextOperations, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['TANDEMLOG_TEXT_QA_SCREENSHOTS'];
  if (output == null || !Platform.isLinux) return;
  await Directory(output).create(recursive: true);
  final found = await Process.run('xdotool', [
    'search',
    '--onlyvisible',
    '--name',
    r'^tandemlog$',
  ]);
  expect(found.exitCode, 0);
  final window = (found.stdout as String).trim().split('\n').last;
  await Process.run('xdotool', ['windowmove', window, '0', '0']);
  await Process.run('xdotool', [
    'windowsize',
    window,
    tester.view.physicalSize.width.round().toString(),
    tester.view.physicalSize.height.round().toString(),
  ]);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  final result = await Process.run('import', [
    '-window',
    window,
    '$output/$name.png',
  ]);
  expect(result.exitCode, 0);
}
