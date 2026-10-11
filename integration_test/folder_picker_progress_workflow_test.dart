import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/platform/log_folder.dart' show AndroidLogFolder;
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'food_production_workflow_test.dart' show switchSection;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;
import '../test/support/toolbar_button.dart';

class _HeldPicker extends FolderActions {
  _HeldPicker(this.android);
  final bool android;
  int calls = 0;
  Completer<String?>? pending;
  @override
  bool get requiresPicker => android;
  Future<String?> request() {
    calls++;
    final result = pending = Completer<String?>();
    return result.future.whenComplete(() => pending = null);
  }

  @override
  Future<String?> pick() => android ? AndroidLogFolder.pick() : request();
  @override
  Future<bool> canOpen(String location) async => false;
}

class _FixtureFolder implements LogFolder, BoundedLogFolder {
  _FixtureFolder(this.location, String path) : delegate = LocalLogFolder(path);
  @override
  final String location;
  final LocalLogFolder delegate;
  Completer<void>? hold;
  Completer<void>? entered;
  @override
  Future<List<LogFileInfo>> list() async {
    if (hold != null) {
      if (!entered!.isCompleted) entered!.complete();
      await hold!.future;
      hold = null;
    }
    return delegate.list();
  }

  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      delegate.readBounded(name, maximumBytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      delegate.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: 'Expected bounded picker state');
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFolderPickerProgressTests();
}

void registerFolderPickerProgressTests() {
  for (final android in [false, true]) {
    testWidgets(
      'folder picker waits without work progress ${android ? 'Android adapter' : 'desktop'}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'folder-picker-synthetic-',
        );
        final first = await Directory('${root.path}/first').create();
        final second = await Directory('${root.path}/second').create();
        final bad = await Directory('${root.path}/bad').create();
        final profile = await Directory('${root.path}/profile').create();
        final user = const Uuid().v4(), task = const Uuid().v4();
        for (final target in [(first, 'First'), (second, 'Second')]) {
          final seed = await openNativeFixtureStore(
            LocalLogFolder(target.$1.path),
            '${root.path}/${target.$2}-seed',
          );
          await seed.command(user, 'user.created', {
            'name': 'Synthetic household',
          });
          await seed.createTasks({task: '${target.$2} picker task'}, user);
          await seed.close();
        }
        await File(
          '${bad.path}/tandemlog-space.json',
        ).writeAsString('invalid synthetic manifest');
        String alias(Directory directory, String name) =>
            android ? 'content://synthetic/tree/$name' : directory.path;
        final a = _FixtureFolder(alias(first, 'first'), first.path);
        final b = _FixtureFolder(alias(second, 'second'), second.path);
        final broken = _FixtureFolder(alias(bad, 'bad'), bad.path);
        final folders = {a.location: a, b.location: b, broken.location: broken};
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': a.location,
            'user': user,
            'appearance': 'dark',
          }),
        );
        final picker = _HeldPicker(android);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        if (android) {
          messenger.setMockMethodCallHandler(AndroidLogFolder.channel, (
            call,
          ) async {
            expect(call.method, 'pick');
            return picker.request();
          });
        }
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        Future<Map<String, List<int>>> canonical() async => {
          for (final file
              in await first
                  .list()
                  .where((e) => e is File)
                  .cast<File>()
                  .toList())
            file.path: await file.readAsBytes(),
        };
        try {
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              folderActions: picker,
              folderFactory: (location) => folders[location]!,
            ),
          );
          await _waitFor(
            tester,
            () => find.text('First picker task').evaluate().isNotEmpty,
          );
          await switchSection(tester, food: true);
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          final origin = state.store;
          final writer = state.settings.writer;
          final before = await canonical();
          Future<void> choose() async {
            await flows.openSettings(tester);
            await tester.tap(
              find.widgetWithText(TextButton, 'Use a different folder'),
            );
            await _waitFor(tester, () => picker.pending != null);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              state.busy,
              false,
              reason: 'user choice is not running work',
            );
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Add'),
                  )
                  .onPressed,
              isNotNull,
            );
          }

          Future<void> answer(String? selected) async {
            picker.pending!.complete(selected);
            await _waitFor(
              tester,
              () => state.choosingFolder == false && state.busy == false,
            );
            await tester.pumpAndSettle();
          }

          await choose();
          final calls = picker.calls;
          await flows.openSettings(tester);
          final duplicate = tester.widget<TextButton>(
            find.widgetWithText(TextButton, 'Use a different folder'),
          );
          expect(duplicate.onPressed, isNull);
          await tester.tap(find.widgetWithText(TextButton, 'Done'));
          await tester.pumpAndSettle();
          expect(picker.calls, calls);
          await captureNativeFixtureUi(
            tester,
            'folder-picker-${android ? 'adapter' : 'desktop'}-waiting',
          );
          await answer(null);
          expect(identical(state.store, origin), true);
          expect(await canonical(), before);
          await choose();
          picker.pending!.completeError(
            android
                ? PlatformException(
                    code: 'launch',
                    message: 'Synthetic picker launch failed',
                  )
                : StateError('Synthetic picker failed'),
          );
          await _waitFor(tester, () => state.choosingFolder == false);
          expect(state.busy, false);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          final error = state.error;
          expect(error, isNotNull);
          await choose();
          await answer(null);
          expect(
            state.error,
            error,
            reason: 'cancelling the chooser preserves the prior diagnostic',
          );
          await choose();
          await answer(a.location);
          expect(state.error, error);
          expect(identical(state.store, origin), true);
          expect(await canonical(), before);
          await choose();
          await tester.tap(find.byTooltip('Add food'));
          await tester.pumpAndSettle();
          final name = find.widgetWithText(TextField, 'Food name');
          await tester.enterText(name, 'Draft created during picker wait');
          final value = tester.widget<TextField>(name).controller!.value;
          picker.pending!.complete(b.location);
          await _waitFor(
            tester,
            () => find.text('Discard food changes?').evaluate().isNotEmpty,
          );
          await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
          await _waitFor(tester, () => state.choosingFolder == false);
          expect(identical(state.store, origin), true);
          expect(state.settings.folder, a.location);
          expect(tester.widget<TextField>(name).controller!.value, value);
          expect(await canonical(), before);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
          await tester.pumpAndSettle();
          await choose();
          await answer(broken.location);
          expect(identical(state.store, origin), true);
          expect(state.settings.folder, a.location);
          expect(state.settings.writer, writer);
          expect(state.error, isNotNull);
          expect(await canonical(), before);
          b.hold = Completer<void>();
          b.entered = Completer<void>();
          await choose();
          await switchSection(tester, food: false);
          a.hold = Completer<void>();
          a.entered = Completer<void>();
          await tester.tap(find.byKey(ValueKey('task-body-$task')));
          await _waitFor(tester, () => a.entered!.isCompleted);
          picker.pending!.complete(b.location);
          await _waitFor(tester, () => state.busy == true);
          a.hold!.complete();
          await _waitFor(tester, () => b.entered!.isCompleted);
          await tester.pump();
          expect(
            state.editingTask,
            isNull,
            reason:
                'an old-folder capture cannot publish an editor during loading',
          );
          await tester.pump();
          expect(
            state.busy,
            true,
            reason: 'selected-folder validation/loading is actual work',
          );
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(
            toolbarButton(
              tester,
              find.byKey(const ValueKey('open-capture')),
            ).onPressed,
            isNull,
          );
          await captureNativeFixtureUi(
            tester,
            'folder-picker-${android ? 'adapter' : 'desktop'}-loading',
            waitingForConsent: true,
          );
          b.hold!.complete();
          await _waitFor(
            tester,
            () =>
                state.busy == false &&
                state.choosingFolder == false &&
                state.store?.folder.location == b.location,
          );
          expect(state.settings.writer, writer);
          expect(state.settings.folder, b.location);
          expect(state.error, isNull);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(await canonical(), before);
          await switchSection(tester, food: false);
          expect(find.text('Second picker task'), findsOneWidget);
          await switchSection(tester, food: true);
          await choose();
          await tester.pumpWidget(const SizedBox.shrink());
          picker.pending!.complete(a.location);
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            state.settings.folder,
            b.location,
            reason: 'late disposed picker result cannot change settings',
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (picker.pending != null && !picker.pending!.isCompleted) {
            picker.pending!.complete(null);
          }
          if (b.hold != null && !b.hold!.isCompleted) b.hold!.complete();
          if (a.hold != null && !a.hold!.isCompleted) a.hold!.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 500));
          messenger.setMockMethodCallHandler(AndroidLogFolder.channel, null);
        }
      },
    );
  }
}
