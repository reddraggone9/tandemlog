import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native capture, edit, completion, undo, restart and error recovery',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tandemlog-ui');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/private').create();
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': null}));
      // Interrupt startup before settling; discarded states must not retain a store/timer.
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(find.byType(TextField), 'Lee');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('No open tasks'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Pick up groceries');
      await tester.tap(find.byTooltip('Add tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Pick up groceries'), findsOneWidget);
      await tester.tap(find.text('Pick up groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Buy oats',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Large bag',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Large bag'), findsOneWidget);
      await tester.tap(find.byTooltip('Complete Buy oats'));
      await tester.pumpAndSettle();
      expect(find.text('No open tasks'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      await tester.tap(find.byTooltip('Complete Buy oats'));
      await tester.pumpAndSettle();
      // Persistent completed browsing works even after dismissing transient Undo.
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(
        tester.getSize(find.byType(Checkbox)).width,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(Checkbox)).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.text('Large bag'), findsOneWidget);
      await tester.tap(find.byTooltip('Reopen Buy oats'));
      await tester.pumpAndSettle();
      expect(find.text('No completed tasks'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
      await tester.tap(find.byTooltip('Complete Buy oats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reopen Buy oats'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Periodic ingestion must not steal an unfinished capture's input/focus.
      await tester.enterText(find.byType(TextField), 'Unsubmitted draft');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Unsubmitted draft'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Large bag'), findsOneWidget);
      final bad = File(
        '${folder.path}/11111111-1111-4111-8111-111111111111.jsonl',
      );
      await bad.writeAsString('{"v":99}\n');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsupported event version'), findsOneWidget);
      expect(find.text('Buy oats'), findsOneWidget);
      await bad.delete();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unsupported event version'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await root.delete(recursive: true);
    },
  );
  testWidgets(
    'desktop onboarding, live theme, inline retry and folder actions',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'tandemlog-onboarding',
      );
      final profile = Directory('${root.path}/profile');
      final actions = TestFolders();
      Future<void> launch() async {
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderActions: actions),
        );
        await tester.pumpAndSettle();
      }

      Future<void> settings() async {
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
      }

      Future<void> theme(String name) async {
        await settings();
        await tester.tap(find.text('Theme'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold))).brightness;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await launch();
      expect(brightness(), Brightness.dark);
      expect(await Directory('${profile.path}/data').exists(), isFalse);
      await settings();
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(brightness(), Brightness.dark);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await theme('Light');
      expect(brightness(), Brightness.light);
      expect(await Directory('${profile.path}/data').exists(), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launch();
      expect(brightness(), Brightness.light);
      await theme('System');
      expect(brightness(), Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      // Canceling the secondary chooser must not create the default workspace.
      await tester.tap(find.text('Choose an existing folder'));
      await tester.pumpAndSettle();
      expect(actions.picks, 1);
      expect(await Directory('${profile.path}/data').exists(), isFalse);
      final start = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start'))
          .onPressed!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final name = tester.widget<TextField>(find.byType(TextField));
      expect(name.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '   ');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Lee');
      final manifest = File('${profile.path}/data/tandemlog-space.json');
      final originalManifest = await manifest.readAsString();
      await manifest.rename('${manifest.path}.removed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Lee'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await File('${manifest.path}.removed').rename(manifest.path);
      final submit = tester
          .widget<TextField>(find.byType(TextField))
          .onSubmitted!;
      final blockedSettings = Directory('${profile.path}/settings.json.tmp');
      await blockedSettings.create();
      submit('Lee');
      submit('Lee');
      await tester.pumpAndSettle();
      expect(find.text('Lee'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await blockedSettings.delete();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('No open tasks'), findsOneWidget);
      final records = <dynamic>[];
      await for (final f in Directory('${profile.path}/data').list()) {
        if (f.path.endsWith('.jsonl')) {
          records.addAll((await File(f.path).readAsLines()).map(jsonDecode));
        }
      }
      expect(records.where((r) => r['type'] == 'user.created').length, 1);
      expect(await manifest.readAsString(), originalManifest);
      await theme('Dark');
      expect(brightness(), Brightness.dark);
      await settings();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Open data folder'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      actions.available = true;
      actions.failOpen = true;
      await settings();
      await tester.tap(find.text('Open data folder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Test file manager failure'), findsOneWidget);
      expect(find.text('No open tasks'), findsOneWidget);
      // Failed folder switching keeps the old workspace and preference intact.
      actions.selection = '${root.path}/missing';
      await settings();
      await tester.tap(find.text('Use a different folder'));
      await tester.pumpAndSettle();
      expect(find.text('No open tasks'), findsOneWidget);
      final saved = jsonDecode(
        await File('${profile.path}/settings.json').readAsString(),
      );
      expect(saved['folder'], '${profile.path}/data');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await launch();
      expect(brightness(), Brightness.dark);
      expect(find.text('No open tasks'), findsOneWidget);
      expect(await manifest.readAsString(), originalManifest);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await root.delete(recursive: true);
    },
  );

  testWidgets(
    'automatic imports preserve edit/capture buffers and keyboard submission',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tandemlog-input');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4(), task = const Uuid().v4();
      final remote = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/remote',
      );
      await remote.command(user, 'user.created', {'name': 'Lee'});
      await remote.command(task, 'task.created', {
        'title': 'Original task',
        'description': 'Original notes',
        'assignee': user,
      });
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      expect(await Directory('${profile.path}/data').exists(), isFalse);
      expect(find.byTooltip('Refresh folder'), findsNothing);
      expect(find.textContaining('Saved on this device'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Enter task');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Enter task'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Line one');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Line one\n',
      );
      await tester.enterText(
        find.byType(TextField),
        'Line one\nLine two\n  \n',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Line one'), findsOneWidget);
      expect(find.text('Line two'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '買い物');
      final capture = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      capture.value = capture.value.copyWith(
        composing: const TextRange(start: 0, end: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(capture.text, '買い物');
      expect(find.byTooltip('Complete 買い物'), findsNothing);
      capture.value = capture.value.copyWith(composing: TextRange.empty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Complete 買い物'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Unsent draft');
      await tester.tap(find.text('Original task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Local edited title',
      );
      await remote.command(task, 'task.edited', {
        'description': 'Arrived automatically',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Title'))
            .controller!
            .text,
        'Local edited title',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Local edited title'), findsOneWidget);
      expect(find.text('Arrived automatically'), findsOneWidget);
      expect(capture.text, 'Unsent draft');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await remote.command(task, 'task.edited', {
        'description': 'Changed while suspended',
      });
      // Hidden native windows do not schedule frames: resume before pumping.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Changed while suspended'), findsOneWidget);
      expect(capture.text, 'Unsent draft');
      const notes =
          'Bring reusable bags and check the pantry before shopping.\n'
          'Include fruit, vegetables and ingredients for the weekend meals.';
      await tester.tap(find.text('Local edited title'));
      await tester.pumpAndSettle();
      final notesField = find.widgetWithText(TextField, 'Notes');
      await tester.tap(notesField);
      await tester.pumpAndSettle();
      await tester.enterText(notesField, notes);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(notesField).controller!.text, notes);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(
        find.text(notes.replaceAll('\n', ' ')),
      );
      expect(preview.maxLines, 1);
      expect(preview.overflow, TextOverflow.ellipsis);
      await tester.tap(find.text('Local edited title'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Notes'))
            .controller!
            .text,
        notes,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('System'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await remote.close();
      await root.delete(recursive: true);
    },
  );

  testWidgets('missing saved workspace does not silently create a default', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('tandemlog-missing');
    await File('${root.path}/settings.json').writeAsString(
      jsonEncode({'folder': '${root.path}/absent', 'user': null}),
    );
    await tester.pumpWidget(TandemlogApp(profilePath: root.path));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(await Directory('${root.path}/data').exists(), isFalse);
    expect(
      jsonDecode(
        await File('${root.path}/settings.json').readAsString(),
      )['folder'],
      '${root.path}/absent',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });

  testWidgets(
    'Android Start keeps picker and cancel creates no private workspace',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tandemlog-picker');
      final actions = TestFolders(android: true);
      await tester.pumpWidget(
        TandemlogApp(profilePath: root.path, folderActions: actions),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(actions.picks, 1);
      expect(await Directory('${root.path}/data').exists(), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await root.delete(recursive: true);
    },
  );
  testWidgets('Shift+Enter reveals caret before any further input', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('capture-scroll-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final user = const Uuid().v4();
    final store = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    await store.command(user, 'user.created', {'name': 'Test user'});
    await store.close();
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    final controller = tester.widget<TextField>(field).controller!;
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    Future<void> newline() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    void expectVisible() {
      final render = editable.renderEditable;
      final caret = render.getLocalRectForCaret(controller.selection.extent);
      expect(caret.top, greaterThanOrEqualTo(-1));
      expect(caret.bottom, lessThanOrEqualTo(render.size.height + 1));
    }

    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      await tester.enterText(field, 'One\nTwo\nThree\nFour');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await newline();
        expectVisible();
      }
      // Multiline paste, then replace a middle selection rather than append.
      await Clipboard.setData(
        const ClipboardData(text: 'One\nTwo\nThree\nFour\nFive\nSix'),
      );
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await editable.pasteText(SelectionChangedCause.keyboard);
      await tester.pumpAndSettle();
      expectVisible();
      controller.selection = const TextSelection(
        baseOffset: 8,
        extentOffset: 13,
      );
      await newline();
      expect(controller.text, 'One\nTwo\n\n\nFour\nFive\nSix');
      expect(controller.selection, const TextSelection.collapsed(offset: 9));
      expectVisible();
      // Composition must not be replaced by the desktop shortcut.
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 3),
      );
      final composingValue = controller.value;
      await newline();
      expect(controller.value, composingValue);
      controller.value = controller.value.copyWith(composing: TextRange.empty);
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });
  testWidgets('header controls stay fixed between open and completed tabs', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('header-layout-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final user = const Uuid().v4();
    final store = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    await store.command(user, 'user.created', {
      'name': 'Alexandria Example Household Member',
    });
    for (var i = 0; i <= 1000; i++) {
      final id = const Uuid().v4();
      await store.command(id, 'task.created', {
        'title': 'Example task $i',
        'description': '',
        'assignee': user,
      });
      if (i == 0) await store.command(id, 'task.completed', {});
    }
    await store.close();
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    for (final sample in [
      (1000, 1.0),
      (390, 1.0),
      (320, 1.0),
      (350, 2.0),
      (390, 2.0),
      (390, 2.5),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(sample.$1.toDouble(), 820);
      tester.platformDispatcher.textScaleFactorTestValue = sample.$2;
      await tester.pumpAndSettle();
      final userBefore = tester.getRect(find.byTooltip('Switch user'));
      final filterBefore = tester.getRect(find.byType(FilterChip));
      final tabsBefore = tester.getRect(find.byType(SegmentedButton<bool>));
      void expectSingleLineLabels() {
        for (final label in ['Open', 'Completed']) {
          final text = tester.renderObject<RenderParagraph>(find.text(label));
          expect(
            text.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: label.length),
            ),
            hasLength(1),
          );
        }
      }

      expectSingleLineLabels();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byTooltip('Switch user')), userBefore);
      expect(tester.getRect(find.byType(FilterChip)), filterBefore);
      expect(tester.getRect(find.byType(SegmentedButton<bool>)), tabsBefore);
      expectSingleLineLabels();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byTooltip('Switch user')), userBefore);
      expect(tester.getRect(find.byType(FilterChip)), filterBefore);
      expect(tester.getRect(find.byType(SegmentedButton<bool>)), tabsBefore);
      expectSingleLineLabels();
      expect(tester.takeException(), isNull);
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });
  testWidgets(
    'dates, zones, tags, order and recurring history work through native UI',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('parity-ui-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4(), task = const Uuid().v4();
      final remote = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/reader',
      );
      await remote.command(user, 'user.created', {'name': 'Example user'});
      await remote.command(task, 'task.created', {
        'title': 'Monthly review',
        'description': 'Keep the original notes.',
        'assignee': user,
        'tags': ['original'],
        'schedule': {
          'startDate': '2026-01-29',
          'scheduledDate': '2026-01-30',
          'dueDate': '2026-01-31',
          'startTime': null,
          'timeZone': null,
          'recurrence': 'every month',
        },
      });
      await remote.command(const Uuid().v4(), 'task.created', {
        'title': 'Second task',
        'description': '',
        'assignee': user,
      });
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly review'));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, value);
      }

      await fill('Start date', '2026-02-01');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Start date'))
            .controller!
            .text,
        '2026-02-01',
      );
      await remote.refresh();
      expect(
        (remote.rows.firstWhere((r) => r['id'] == task)['schedule']
            as Map)['startDate'],
        '2026-01-29',
      );
      await fill('Start date', '2026-01-29');
      await fill('Start time', '09:30');
      await fill('Scheduled time', '08:00');
      await fill('Due time', '17:00');
      await tester.ensureVisible(find.text('Local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UTC').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('On this device:'), findsOneWidget);
      await fill('Tags', '#home #weekly');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Text),
              ),
            )
            .map((w) => w.data)
            .join(' | '),
      );
      await remote.refresh();
      var state = remote.rows.firstWhere((r) => r['id'] == task);
      expect(state['tags'], unorderedEquals(['home', 'weekly']));
      expect((state['schedule'] as Map)['timeZone'], 'UTC');
      expect((state['schedule'] as Map)['dueTime'], '17:00');
      expect((state['schedule'] as Map)['scheduledTime'], '08:00');
      expect(find.textContaining('09:30 UTC'), findsOneWidget);
      await tester.tap(find.byTooltip('Task actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Second task')).dy,
        lessThan(tester.getTopLeft(find.text('Monthly review')).dy),
      );
      await tester.tap(find.byTooltip('Complete Monthly review'));
      await tester.pumpAndSettle();
      await remote.refresh();
      final occurrences = remote.rows
          .where((r) => r['title'] == 'Monthly review')
          .toList();
      expect(occurrences.length, 2);
      final successor = occurrences.singleWhere((r) => r['id'] != task);
      expect((successor['schedule'] as Map)['dueDate'], '2026-02-28');
      expect((successor['schedule'] as Map)['scheduledDate'], isNull);
      expect((successor['schedule'] as Map)['timeZone'], 'UTC');
      expect(
        tester.getTopLeft(find.text('Second task')).dy,
        lessThan(tester.getTopLeft(find.text('Monthly review')).dy),
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reopen Monthly review'));
      await tester.pumpAndSettle();
      await remote.refresh();
      expect(
        remote.rows.where((r) => r['title'] == 'Monthly review').length,
        2,
      );
      expect(
        remote.rows
            .where((r) => r['title'] == 'Monthly review')
            .every((r) => r['completed'] == false),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await remote.close();
      await root.delete(recursive: true);
    },
  );
  testWidgets('future event clock warns without blocking capture', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('clock-warning-ui-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final user = const Uuid().v4();
    final remote = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/remote',
      now: () => DateTime.now().add(const Duration(minutes: 10)),
    );
    await remote.command(user, 'user.created', {'name': 'Example user'});
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    expect(find.textContaining('ahead of this device'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'What needs doing?');
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Capture remains available');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Capture remains available'), findsOneWidget);
    expect(find.textContaining('ahead of this device'), findsOneWidget);
    await remote.refresh();
    expect(remote.rows.where((r) => r['kind'] == 'task').length, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await remote.close();
    await root.delete(recursive: true);
  });
}

class TestFolders extends FolderActions {
  TestFolders({this.android = false});
  final bool android;
  bool available = false, failOpen = false;
  int picks = 0;
  String? selection;
  @override
  bool get requiresPicker => android;
  @override
  Future<String?> pick() async {
    picks++;
    return selection;
  }

  @override
  Future<bool> canOpen(String location) async => available;
  @override
  Future<void> open(String location) async {
    if (failOpen) throw StateError('Test file manager failure');
  }
}
