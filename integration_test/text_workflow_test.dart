import 'profile_fixture.dart';
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
    'fresh application workspace initializes automatically and cold reopens without setup',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('fresh-text-ui-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      await seedNativeProfile(profile.path, {
        'folder': folder.path,
        'user': null,
      });
      Future<Map<String, String>> canonical() async => {
        await for (final file in folder.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      Future<void> closeApp() async {
        final retired = tester.state(find.byType(TasksPage)) as dynamic;
        await tester.pumpWidget(const SizedBox.shrink());
        await flows.waitForUi(tester, () {
          final owner = retired.profileDatabase;
          if (owner == null) return false;
          try {
            owner.database;
            return false;
          } on StateError {
            return true;
          }
        });
      }

      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find
              .widgetWithText(FilledButton, 'Continue')
              .evaluate()
              .isNotEmpty,
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect((state.store as TaskStore).sharedTextInitialized, isTrue);
        await tester.enterText(find.byType(TextField), 'Fresh user');
        final continueButton = find.widgetWithText(FilledButton, 'Continue');
        // The name's onChanged schedules the rebuild that enables Continue.
        // Act only on that enabled, visible button, not its previous frame.
        await flows.waitForUi(
          tester,
          () => tester.widget<FilledButton>(continueButton).onPressed != null,
        );
        expect(continueButton.hitTestable(), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Fresh user',
        );
        await tester.tap(continueButton);
        await flows.waitForUi(
          tester,
          () => find.text('No open tasks').evaluate().isNotEmpty,
        );
        await flows.openCaptureForTest(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'One task per line'),
          'Fresh initialized task',
        );
        await flows.waitForCaptureAction(tester);
        await tester.tap(find.byKey(const ValueKey('capture-add')));
        await flows.waitForUi(
          tester,
          () => find.text('Fresh initialized task').evaluate().isNotEmpty,
        );
        await flows.openSettings(tester);
        expect(
          find.byKey(const ValueKey('initialize-shared-text')),
          findsNothing,
        );
        expect(find.text('Set up shared text editing'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        await _capture(tester, 'fresh-auto-initialized');
        final before = await canonical();
        await closeApp();
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Fresh initialized task').evaluate().isNotEmpty,
        );
        final reopened = tester.state(find.byType(TasksPage)) as dynamic;
        expect((reopened.store as TaskStore).sharedTextInitialized, isTrue);
        expect(await canonical(), before);
        expect(tester.takeException(), isNull);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) await closeApp();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'existing uninitialized application workspace preserves bytes and offers no setup migration',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'uninitialized-text-ui-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4(), task = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Historical user'});
      await seed.command(task, 'task.created', {
        'title': 'Retained legacy task',
        'description': '',
        'assignee': user,
      });
      await seed.close();
      await seedNativeProfile(profile.path, {
        'folder': folder.path,
        'user': user,
      });
      Future<Map<String, String>> canonical() async => {
        await for (final file in folder.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      final before = await canonical();
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find
              .textContaining('no verified shared-text initialization')
              .evaluate()
              .isNotEmpty,
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(state.store, isNull);
        await flows.openSettings(tester);
        expect(
          find.byKey(const ValueKey('initialize-shared-text')),
          findsNothing,
        );
        expect(find.text('Set up shared text editing'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await tester.pumpAndSettle();
        expect(await canonical(), before);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'uninitialized-history-preserved');
      } finally {
        final retired = tester.state(find.byType(TasksPage)) as dynamic;
        await tester.pumpWidget(const SizedBox.shrink());
        await flows.waitForUi(tester, () {
          final owner = retired.profileDatabase;
          if (owner == null) return false;
          try {
            owner.database;
            return false;
          } on StateError {
            return true;
          }
        });
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets(
    'initialized text, remote draft Save, Undo and restart without migration workflow',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('native-text-ui-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
        initializeNewWorkspaceText: false,
      );
      final user = const Uuid().v4(), legacy = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Alex Example'});
      await seed.command(legacy, 'task.created', {
        'title': 'Legacy reference',
        'description': '',
        'assignee': user,
      });
      await seed.close();
      await seedNativeProfile(profile.path, {
        'folder': folder.path,
        'user': user,
      });
      final engine = NativeTextEngine();
      final peer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/peer',
        textEngine: engine,
      );
      try {
        await peer.initializeSharedText();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Legacy reference').evaluate().isNotEmpty,
        );
        await flows.openCaptureForTest(tester);
        final capture = find.widgetWithText(TextField, 'One task per line');
        await tester.enterText(capture, 'Shared draft');
        await flows.waitForCaptureAction(tester);
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
        expect(peer.sharedTextInitialized, isTrue);
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

        await flows.openSettings(tester);
        expect(
          find.byKey(const ValueKey('initialize-shared-text')),
          findsNothing,
        );
        expect(find.text('Set up shared text editing'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
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
        initializeNewWorkspaceText: false,
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
        await seedNativeProfile(profile.path, {
          'folder': shared.path,
          'user': user,
          'appearance': 'dark',
        });
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
          final original = base64Decode(entry.value);
          final grown = base64Decode(after[entry.key]!);
          expect(grown.length, greaterThanOrEqualTo(original.length));
          expect(grown.sublist(0, original.length), original);
        }
        expect(
          store.unified!.snapshot.tasks.where(
            (event) => event.type == 'task.completedKeepingSuccessor',
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
