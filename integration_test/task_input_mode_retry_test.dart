import 'profile_fixture.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import '../test/batch_storage_test.dart' show CountingFolder;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi, waitForCaptureAction;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskInputModeRetryTests();
}

void registerTaskInputModeRetryTests() {
  for (final fault in ['before', 'prefix']) {
    testWidgets(
      'Search cannot discard a $fault capture awaiting confirmation',
      (tester) async {
        await _withWorkspace(tester, 390, (folder, _) async {
          final capture = await _openCapture(tester);
          const draft = 'New pending\nSecond pending';
          await tester.enterText(capture, draft);
          folder.fault = fault;
          await waitForCaptureAction(tester);
          await tester.tap(find.byKey(const ValueKey('capture-add')));
          await waitForUi(tester, () => folder.delayedSuffix != null);
          await tester.pumpAndSettle();
          final controller = tester.widget<TextField>(capture).controller!;
          expect(controller.text, draft);
          expect(tester.widget<TextField>(capture).readOnly, isTrue);
          expect(
            tester
                .widget<IconButton>(find.byKey(const ValueKey('open-search')))
                .onPressed,
            isNull,
          );
          final dynamic state = tester.state(find.byType(TasksPage));
          final failureText = state.error as String?;
          expect(failureText, isNotNull);
          debugPrint('INPUT_MODE_CAPTURE_FAILURE $fault: $failureText');
          expect(find.text(failureText!), findsOneWidget);
          expect(
            find.text('Retry to check these tasks before editing.'),
            findsOneWidget,
          );
          final reservedName = folder.delayedName!;
          final reservedSuffix = List<int>.of(folder.delayedSuffix!);
          final prefix =
              (await folder.delegate.list()).any(
                (file) => file.name == reservedName,
              )
              ? await folder.delegate.read(reservedName)
              : <int>[];
          final beforeSwitch = await _records(folder.delegate);
          final appendsBeforeSwitch = folder.appends;

          await _attemptSearch(tester);
          expect(find.byKey(const ValueKey('task-search')), findsNothing);
          expect(capture, findsOneWidget);
          expect(controller.text, draft);
          expect(tester.widget<TextField>(capture).readOnly, isTrue);
          expect(folder.delayedName, reservedName);
          expect(folder.delayedSuffix, reservedSuffix);
          expect(folder.appends, appendsBeforeSwitch);
          expect(await _records(folder.delegate), beforeSwitch);
          // Retrying an uncertain append cannot allocate a replacement packet
          // or abandon the original reserved capture identities.
          await tester.tap(find.byKey(const ValueKey('capture-add')));
          await tester.pumpAndSettle();
          expect(controller.text, draft);
          expect(tester.widget<TextField>(capture).readOnly, isTrue);
          expect(folder.delayedName, reservedName);
          expect(folder.delayedSuffix, reservedSuffix);
          expect(folder.appends, appendsBeforeSwitch);
          expect(await _records(folder.delegate), beforeSwitch);
          await captureNativeFixtureUi(
            tester,
            'input-mode-$fault-retry-retained',
          );

          // A creation-only prefix does not confirm its reserved initial move.
          // A normal refresh must still keep both original capture identities.
          final listsBefore = folder.lists;
          _resume(tester);
          await waitForUi(tester, () => folder.lists > listsBefore);
          await tester.pumpAndSettle();
          expect(controller.text, draft);
          expect(tester.widget<TextField>(capture).readOnly, isTrue);
          await _attemptSearch(tester);
          expect(find.byKey(const ValueKey('task-search')), findsNothing);
          expect(folder.delayedSuffix, reservedSuffix);
          expect(await _records(folder.delegate), beforeSwitch);

          await folder.revealPending();
          _resume(tester);
          await waitForUi(tester, () => controller.text.isEmpty);
          await tester.pumpAndSettle();
          expect(
            capture,
            findsOneWidget,
            reason: 'Confirmation keeps Add mode active.',
          );
          expect(tester.widget<TextField>(capture).readOnly, isFalse);
          expect(find.text('New pending'), findsOneWidget);
          expect(find.text('Second pending'), findsOneWidget);
          expect(await folder.delegate.read(reservedName), [
            ...prefix,
            ...reservedSuffix,
          ]);
          final confirmedBytes = await _records(folder.delegate);
          await tester.tap(find.byKey(const ValueKey('capture-add')));
          await tester.pumpAndSettle();
          expect(
            folder.appends,
            appendsBeforeSwitch,
            reason: 'Retry must not allocate or append replacement captures.',
          );
          expect(await _records(folder.delegate), confirmedBytes);
          await _attemptSearch(tester);
          expect(find.byKey(const ValueKey('task-search')), findsOneWidget);
          expect(capture, findsNothing);
          expect(await _records(folder.delegate), confirmedBytes);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }

  testWidgets('Search cannot clear capture during an unfinished append', (
    tester,
  ) async {
    await _withWorkspace(tester, 390, (folder, _) async {
      final capture = await _openCapture(tester);
      await tester.enterText(capture, 'Busy capture');
      folder.holdNextAppend();
      await waitForCaptureAction(tester);
      await tester.tap(find.byKey(const ValueKey('capture-add')));
      // The ordinary waitForUi helper settles animations after readiness.
      // This deliberately held save keeps its progress indicator animating.
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 100 && !folder.entered!.isCompleted;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(folder.entered!.isCompleted, isTrue);
      expect(tester.widget<TextField>(capture).enabled, isFalse);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('open-search')))
            .onPressed,
        isNull,
      );
      final beforeSwitch = await _records(folder.delegate);
      await _attemptSearch(tester, settle: false);
      expect(find.byKey(const ValueKey('task-search')), findsNothing);
      expect(capture, findsOneWidget);
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Busy capture',
      );
      expect(await _records(folder.delegate), beforeSwitch);
      folder.release();
      await waitForUi(
        tester,
        () => tester.widget<TextField>(capture).controller!.text.isEmpty,
      );
      await tester.pumpAndSettle();
      expect(capture, findsOneWidget);
      expect(find.text('Busy capture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'Cancel dirty editor keeps outgoing capture until a mode switch is accepted',
    (tester) async {
      await _withWorkspace(tester, 1200, (folder, anchor) async {
        final before = await _records(folder.delegate);
        final capture = await _openCapture(tester);
        await tester.enterText(capture, 'Unsubmitted capture draft');
        await tester.tap(find.byKey(ValueKey('task-title-$anchor')));
        await tester.pumpAndSettle();
        final notes = find.widgetWithText(TextField, 'Notes');
        await tester.enterText(notes, 'Unsaved editor draft');
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsOneWidget);
        expect(find.byKey(const ValueKey('task-search')), findsNothing);
        expect(
          tester.widget<TextField>(capture).controller!.text,
          'Unsubmitted capture draft',
        );
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Unsaved editor draft',
        );
        expect(await _records(folder.delegate), before);

        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.byKey(const ValueKey('task-search')), findsOneWidget);
        expect(capture, findsNothing);
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(capture).controller!.text, isEmpty);
        expect(await _records(folder.delegate), before);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Explicit input mode switch clears compact selection and its hidden editor',
    (tester) async {
      await _withWorkspace(tester, 390, (folder, anchor) async {
        final before = await _records(folder.delegate);
        final input = find.byKey(const ValueKey('task-search'));
        expect(input, findsOneWidget);
        await tester.enterText(input, 'Organized');
        await tester.pumpAndSettle();
        final body = find.byKey(ValueKey('task-body-$anchor'));
        await tester.longPress(body);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        expect(input.hitTestable(), findsNothing);
        expect(find.byType(TaskEditor), findsNothing);
        // Ctrl+F in the current Search mode must reveal/focus that same query,
        // even while compact selection owns the shared input slot.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(input.hitTestable(), findsOneWidget);
        expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
        expect(tester.widget<TextField>(input).controller!.text, 'Organized');
        expect(find.text('1 selected'), findsNothing);
        expect(find.byType(TaskEditor), findsNothing);
        await tester.longPress(body);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        expect(capture.hitTestable(), findsOneWidget);
        expect(find.text('1 selected'), findsNothing);
        expect(input, findsNothing);
        await tester.enterText(capture, 'Discarded selected capture draft');
        await tester.longPress(body);
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        expect(capture.hitTestable(), findsNothing);
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        expect(input.hitTestable(), findsOneWidget);
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        expect(find.text('1 selected'), findsNothing);
        expect(find.byType(TaskEditor), findsNothing);
        await tester.tap(body);
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(capture).controller!.text, isEmpty);
        expect(await _records(folder.delegate), before);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

Future<Finder> _openCapture(WidgetTester tester) async {
  expect(find.byKey(const ValueKey('task-search')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('open-capture')));
  await tester.pumpAndSettle();
  final capture = find.widgetWithText(TextField, 'What needs doing?');
  expect(capture, findsOneWidget);
  return capture;
}

Future<void> _attemptSearch(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.byKey(const ValueKey('open-search')));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<Map<String, List<int>>> _records(LocalLogFolder folder) async => {
  for (final info in await folder.list())
    if (info.name.endsWith('.applog')) info.name: await folder.read(info.name),
};

class _GatedFolder extends CountingFolder {
  _GatedFolder(super.delegate);
  Completer<void>? barrier;
  Completer<void>? entered;
  void holdNextAppend() {
    barrier = Completer<void>();
    entered = Completer<void>();
  }

  void release() {
    if (barrier != null && !barrier!.isCompleted) barrier!.complete();
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (barrier != null) {
      entered!.complete();
      await barrier!.future;
      barrier = null;
    }
    await super.append(name, bytes);
  }
}

Future<void> _withWorkspace(
  WidgetTester tester,
  double width,
  Future<void> Function(_GatedFolder folder, String anchor) inspect,
) async {
  final root = await Directory.systemTemp.createTemp(
    'input-mode-retry-synthetic-',
  );
  final data = await Directory('${root.path}/data').create();
  final profile = await Directory('${root.path}/profile').create();
  final user = const Uuid().v4(), anchor = const Uuid().v4();
  final seed = await openNativeFixtureStore(
    LocalLogFolder(data.path),
    '${root.path}/seed',
  );
  final folder = _GatedFolder(LocalLogFolder(data.path));
  try {
    await seed.command(user, 'user.created', {'name': 'Synthetic household'});
    await seed.createNativeFixtureTask(anchor, {
      'title': 'Organized anchor',
      'description': 'Existing notes',
      'assignee': user,
    });
    await seed.close();
    await seedNativeProfile(profile.path, {
      'folder': data.path,
      'user': user,
      'appearance': 'dark',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 850);
    await tester.pumpWidget(
      TandemlogApp(profilePath: profile.path, folderFactory: (_) => folder),
    );
    await waitForUi(
      tester,
      () => find.text('Organized anchor').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await inspect(folder, anchor);
  } finally {
    folder.release();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await seed.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    // Retain the isolated retry log/suffix for source/native inspection.
  }
}
