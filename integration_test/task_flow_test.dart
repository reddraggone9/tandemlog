import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
      await tester.enterText(find.widgetWithText(TextField, 'Notes'), notes);
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
