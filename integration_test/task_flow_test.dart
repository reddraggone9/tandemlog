import 'dart:async';
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
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/platform/view_time_source.dart';

Future<void> openFilters(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('task-filter'));
  if (button.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> chooseFilter(WidgetTester tester, String label) async {
  if (label == 'All tags') {
    final clear = find.byTooltip('Clear tag filters');
    if (clear.evaluate().isNotEmpty) {
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
    }
  } else if (label.startsWith('#')) {
    if (find
        .byKey(ValueKey('selected-tag-${label.substring(1)}'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    final search = find.byKey(const ValueKey('tag-search'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    await tester.enterText(search, label.substring(1));
    await tester.pumpAndSettle();
    final result = find.byKey(ValueKey('tag-option-${label.substring(1)}'));
    await tester.ensureVisible(result);
    await tester.pumpAndSettle();
    await tester.tap(result);
  } else {
    final choice = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(label),
    );
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
  }
  await tester.pumpAndSettle();
}

Future<void> filterChoice(WidgetTester tester, String label) async {
  await openFilters(tester);
  await chooseFilter(tester, label);
  await tester.tap(find.text('Done').last);
  await tester.pumpAndSettle();
}

Future<void> openSettings(WidgetTester tester) async {
  final direct = find.byTooltip('Settings');
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct);
  } else {
    await tester.tap(find.byKey(const ValueKey('identity-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
  }
  await tester.pumpAndSettle();
}

Future<void> selectTask(
  WidgetTester tester,
  String id, {
  bool control = true,
  bool shift = false,
  bool longPress = false,
}) async {
  final body = find.byKey(ValueKey('task-body-$id'));
  await tester.ensureVisible(body);
  await tester.pumpAndSettle();
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (longPress) {
    await tester.longPress(body);
  } else {
    await tester.tap(body);
  }
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone single and bulk editors keep fields usable with the IME', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('rc4-phone-editors-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4();
    final ids = [const Uuid().v4(), const Uuid().v4()];
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    for (var i = 0; i < ids.length; i++) {
      await writer.command(ids[i], 'task.created', {
        'title': 'Synthetic editor task ${i + 1}',
        'description': 'Reference notes for keyboard regression.',
        'assignee': user,
        'schedule': {
          'dueDate': '2030-05-01',
          'dueTime': i == 0 ? '12:30' : '13:45',
          'recurrence': 'every week when done',
        },
      });
    }
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(540, 960);
    tester.view.viewPadding = const FakeViewPadding(top: 36, bottom: 36);
    tester.view.padding = const FakeViewPadding(top: 36, bottom: 36);
    await tester.pumpAndSettle();
    Future<Map<String, String>> canonicalContents() async => {
      await for (final entry in folder.list())
        if (entry is File) entry.path: base64Encode(await entry.readAsBytes()),
    };
    final before = await canonicalContents();
    for (final scale in [1.0, 1.3, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      for (final bulk in [false, true]) {
        if (bulk) {
          await selectTask(tester, ids[0], control: false, longPress: true);
          await selectTask(tester, ids[1], control: false);
          // Large text can scroll the lazy contextual toolbar out of view.
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Open editor'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open editor'));
        } else {
          await selectTask(tester, ids[0], control: false);
        }
        await tester.pumpAndSettle();
        final initial = find.byKey(ValueKey(bulk ? 'addTags' : 'title'));
        await tester.ensureVisible(initial);
        await tester.pumpAndSettle();
        await tester.tap(initial);
        await tester.pumpAndSettle();
        tester.view.padding = const FakeViewPadding(top: 36);
        tester.view.viewInsets = const FakeViewPadding(bottom: 420);
        await tester.pumpAndSettle();
        void usable(Finder field) {
          final viewport = tester.getRect(
            find
                .ancestor(
                  of: field,
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          );
          expect(viewport.height, greaterThanOrEqualTo(48));
          final state = tester.state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(state.widget.focusNode.hasFocus, isTrue);
          final local = state.renderEditable.getLocalRectForCaret(
            state.widget.controller.selection.extent,
          );
          final caret = local.shift(
            state.renderEditable.localToGlobal(Offset.zero),
          );
          expect(caret.top, greaterThanOrEqualTo(viewport.top - 1));
          expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 1));
          expect(caret.bottom, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
        }

        usable(initial);
        for (final key in [
          'dueTime',
          bulk ? 'removeTags' : 'description',
          bulk ? 'addTags' : 'title',
        ]) {
          final field = find.byKey(ValueKey(key));
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.tap(field);
          await tester.pumpAndSettle();
          usable(field);
        }
        // Repeat keyboard closing/opening without another edit or route.
        tester.view.resetViewInsets();
        tester.view.padding = const FakeViewPadding(top: 36, bottom: 36);
        await tester.pumpAndSettle();
        tester.view.padding = const FakeViewPadding(top: 36);
        tester.view.viewInsets = const FakeViewPadding(bottom: 420);
        await tester.pumpAndSettle();
        usable(initial);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsNothing);
        tester.view.resetViewInsets();
        tester.view.padding = const FakeViewPadding(top: 36, bottom: 36);
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.byType(BulkTaskEditor), findsNothing);
      }
    }
    expect(await canonicalContents(), before);
    await writer.refresh();
    expect(writer.rows.where((row) => row['kind'] == 'task').length, 2);
    expect(
      writer.rows.firstWhere(
        (row) => row['id'] == ids[0],
      )['schedule']['dueTime'],
      '12:30',
    );
    expect(
      writer.rows.firstWhere(
        (row) => row['id'] == ids[1],
      )['schedule']['dueTime'],
      '13:45',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    tester.view.resetViewPadding();
    tester.view.resetPadding();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await writer.close();
    await root.delete(recursive: true);
  });
  testWidgets('phone tag dropdown stays tappable above an open keyboard', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('rc4-phone-picker-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4(), task = const Uuid().v4();
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    await writer.command(task, 'task.created', {
      'title': 'Review synthetic supplies',
      'description': '',
      'assignee': user,
    });
    await writer.edit(task, {}, tags: ['edgeqa', 'Other'], observedTagRefs: {});
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    // Android density 240: 540x960 physical pixels, 360x640 logical pixels.
    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(540, 960);
    await tester.pumpAndSettle();
    await openFilters(tester);
    final search = find.byKey(const ValueKey('tag-search'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand tag options'));
    await tester.pumpAndSettle();
    await tester.enterText(search, 'edge');
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 420);
    await tester.pumpAndSettle();
    final keyboardPopup = find.byKey(const ValueKey('tag-results'));
    if (keyboardPopup.evaluate().isNotEmpty) {
      expect(
        find.byKey(const ValueKey('tag-option-edgeqa')).hitTestable(),
        findsOneWidget,
      );
    }
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    final collapse = find.byTooltip('Collapse tag options');
    if (collapse.evaluate().isNotEmpty) {
      await tester.tap(collapse);
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Expand tag options'), findsOneWidget);
    final dialogRect = tester.getRect(find.byType(AlertDialog));
    await tester.tap(find.byTooltip('Expand tag options'));
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('tag-option-edgeqa'));
    final popup = find.byKey(const ValueKey('tag-results'));
    // Bounds alone can pass for a zero-height or entirely clipped popup.
    for (final query in ['does-not-exist', '', 'edge']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      final popupRect = tester.getRect(popup);
      expect(popupRect.height, greaterThanOrEqualTo(48));
      expect(popupRect.top, greaterThanOrEqualTo(0));
      expect(popupRect.bottom, lessThanOrEqualTo(360));
      expect(tester.getRect(find.byType(AlertDialog)), dialogRect);
      expect(
        query == 'does-not-exist'
            ? find.text('No matching tags').hitTestable()
            : result.hitTestable(),
        findsOneWidget,
      );
    }
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-tag-edgeqa')), findsOneWidget);
    expect(tester.getRect(find.byType(AlertDialog)), dialogRect);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await writer.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'multi-tag selection bulk editing deletion and guarded editor sessions',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('rc4-native-');
      final folder = await Directory('${root.path}/shared').create(),
          profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), other = const Uuid().v4();
      await writer.command(user, 'user.created', {'name': 'Alex Example'});
      await writer.command(other, 'user.created', {'name': 'Sam Example'});
      final ids = <String, String>{};
      Future<void> add(
        String title,
        List<String> tags, {
        String? assigned,
        bool done = false,
      }) async {
        final id = ids[title] = const Uuid().v4();
        await writer.command(id, 'task.created', {
          'title': title,
          'description': 'Reference notes for $title',
          'assignee': assigned ?? user,
          'schedule': {'dueDate': '2030-05-01'},
        });
        await writer.edit(id, {}, tags: tags, observedTagRefs: {});
        if (done) await writer.command(id, 'task.completed', {});
      }

      await add('Review household supplies', ['Home']);
      await add('Read planning notes', ['Planning']);
      await add('Arrange reference shelf', ['Home', 'Planning']);
      await add('Other user review', ['Home'], assigned: other);
      await add('Finished planning', ['Planning'], done: true);
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Task actions'), findsNothing);
      await openFilters(tester);
      final dialogRect = tester.getRect(find.byType(AlertDialog));
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      await tester.tap(find.byTooltip('Expand tag options'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AlertDialog)), dialogRect);
      final overlaySearch = find.byKey(const ValueKey('tag-search'));
      for (final query in ['Planning', 'no matching tag', '']) {
        await tester.enterText(overlaySearch, query);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(AlertDialog)), dialogRect);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.getRect(find.byType(AlertDialog)), dialogRect);
      await tester.tap(find.byTooltip('Expand tag options'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byTooltip('Expand tag options'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-results')), findsNothing);
      await chooseFilter(tester, '#Home');
      await chooseFilter(tester, '#Planning');
      expect(find.byType(InputChip), findsNWidgets(2));
      final tagSearch = find.byKey(const ValueKey('tag-search'));
      await tester.enterText(tagSearch, 'Planning');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('selected-tag-Planning')),
        findsOneWidget,
      );
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      for (final title in [
        'Review household supplies',
        'Read planning notes',
        'Arrange reference shelf',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Other user review'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'review',
      );
      await tester.pumpAndSettle();
      expect(find.text('Other user review'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await openFilters(tester);
      expect(find.byType(InputChip), findsNWidgets(2));
      final homeChip = find.byKey(const ValueKey('selected-tag-Home'));
      await tester.tap(
        find.descendant(of: homeChip, matching: find.byTooltip('Delete')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('selected-tag-Home')), findsNothing);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review household supplies'));
      await tester.pumpAndSettle();
      expect(tester.widget<TaskEditor>(find.byType(TaskEditor)).panel, isTrue);
      final titleField = find.widgetWithText(TextField, 'Title');
      await tester.enterText(titleField, 'Unsubmitted household edit');
      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      expect(tester.widget<TaskEditor>(find.byType(TaskEditor)).panel, isFalse);
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        'Unsubmitted household edit',
      );
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read planning notes'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        'Unsubmitted household edit',
      );
      await tester.tap(find.text('Read planning notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        'Read planning notes',
      );
      await tester.enterText(titleField, 'Read current planning notes');
      await tester.tap(find.text('Save changes'));
      for (
        var attempt = 0;
        attempt < 100 && find.byType(TaskEditor).evaluate().isNotEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsNothing);
      await writer.refresh();
      expect(
        writer.rows.firstWhere(
          (row) => row['id'] == ids['Review household supplies'],
        )['title'],
        'Review household supplies',
      );
      expect(
        writer.rows.firstWhere(
          (row) => row['id'] == ids['Read planning notes'],
        )['title'],
        'Read current planning notes',
      );
      for (
        var attempt = 0;
        attempt < 100 && find.byType(TaskEditor).evaluate().isNotEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(TaskEditor), findsNothing);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('select-tasks')), findsNothing);
      await selectTask(tester, ids['Review household supplies']!);
      expect(find.text('1 selected'), findsOneWidget);
      await selectTask(tester, ids['Read planning notes']!, control: false);
      expect(find.byType(BulkTaskEditor), findsOneWidget);
      expect(find.text('2 selected'), findsOneWidget);
      await selectTask(tester, ids['Read planning notes']!, control: false);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      await selectTask(tester, ids['Arrange reference shelf']!, control: false);
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        'Arrange reference shelf',
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsNothing);

      await selectTask(tester, ids['Arrange reference shelf']!, control: false);
      await selectTask(
        tester,
        ids['Review household supplies']!,
        control: false,
        shift: true,
      );
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await selectTask(
        tester,
        ids['Review household supplies']!,
        control: false,
        longPress: true,
      );
      await selectTask(tester, ids['Read planning notes']!, control: false);
      await tester.enterText(
        find.widgetWithText(TextField, 'Add tags'),
        'Selection draft',
      );
      await selectTask(tester, ids['Arrange reference shelf']!, control: false);
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add tags'))
            .controller!
            .text,
        'Selection draft',
      );
      await selectTask(tester, ids['Arrange reference shelf']!, control: false);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add tags'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(390, 900);
      await tester.pumpAndSettle();
      await selectTask(
        tester,
        ids['Review household supplies']!,
        control: false,
        longPress: true,
      );
      expect(find.byType(TaskEditor), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      await selectTask(tester, ids['Read planning notes']!, control: false);
      expect(find.byType(BulkTaskEditor), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byType(BulkTaskEditor), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();

      for (final title in [
        'Review household supplies',
        'Read planning notes',
      ]) {
        await selectTask(tester, ids[title]!);
      }
      final sourceRow = find.byKey(
        ValueKey('task-drop-${ids['Review household supplies']}'),
      );
      final targetRow = find.byKey(
        ValueKey('task-drop-${ids['Arrange reference shelf']}'),
      );
      final handle = find.descendant(
        of: sourceRow,
        matching: find.byType(Draggable<String>),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
      final targetRect = tester.getRect(targetRow);
      await gesture.moveTo(
        Offset(targetRect.right - 60, targetRect.bottom - 8),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await writer.refresh();
      final globalIds = writer.rows
          .where((row) => row['kind'] == 'task')
          .map((row) => row['id'])
          .toList();
      expect(
        globalIds.indexOf(ids['Arrange reference shelf']),
        lessThan(globalIds.indexOf(ids['Review household supplies'])),
      );
      expect(
        globalIds.indexOf(ids['Review household supplies']),
        lessThan(globalIds.indexOf(ids['Read planning notes'])),
      );

      expect(find.byType(BulkTaskEditor), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Title'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Add tags'),
        'Frozen draft',
      );
      await writer.command(ids['Review household supplies']!, 'task.edited', {
        'description': 'Updated reference notes',
      });
      await tester.tap(find.text('Save changes'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('changed'), findsWidgets);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add tags'))
            .controller!
            .text,
        'Frozen draft',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.firstWhere(
          (row) => row['id'] == ids['Review household supplies'],
        )['tags'],
        isNot(contains('Frozen draft')),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      for (final title in [
        'Review household supplies',
        'Read planning notes',
      ]) {
        await selectTask(tester, ids[title]!);
      }
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Add tags'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Add tags'),
        'Reviewed',
      );
      await tester.tap(find.text('Save changes'));
      for (
        var attempt = 0;
        attempt < 100 && find.byType(BulkTaskEditor).evaluate().isNotEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(BulkTaskEditor), findsNothing);
      await writer.refresh();
      for (final title in [
        'Review household supplies',
        'Read planning notes',
      ]) {
        expect(
          writer.rows.firstWhere((row) => row['id'] == ids[title])['tags'],
          contains('Reviewed'),
        );
      }
      for (final title in [
        'Review household supplies',
        'Read planning notes',
      ]) {
        await selectTask(tester, ids[title]!);
      }
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 tasks?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Review household supplies'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.any((row) => row['id'] == ids['Review household supplies']),
        isFalse,
      );
      expect(
        writer.rows.any((row) => row['id'] == ids['Read planning notes']),
        isFalse,
      );
      expect(find.text('Arrange reference shelf'), findsOneWidget);
      final checkbox = find.descendant(
        of: find.byKey(ValueKey('task-drop-${ids['Arrange reference shelf']}')),
        matching: find.byType(Checkbox),
      );
      final checkboxGesture = find.descendant(
        of: checkbox,
        matching: find.byType(GestureDetector),
      );
      Focus.of(tester.element(checkboxGesture.first)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.firstWhere(
          (row) => row['id'] == ids['Arrange reference shelf'],
        )['completed'],
        isTrue,
      );
      expect(find.byType(TaskEditor), findsNothing);
      expect(find.byType(BulkTaskEditor), findsNothing);
      expect(find.text('1 selected'), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await writer.close();
      await root.delete(recursive: true);
    },
  );

  testWidgets(
    'workspace search preserves filters drafts and completion sections',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('workspace-search-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), other = const Uuid().v4();
      await writer.command(user, 'user.created', {'name': 'Alex Example'});
      await writer.command(other, 'user.created', {'name': 'Sam Example'});
      final ids = <String>[];
      Future<void> add(
        String title, {
        String description = '',
        String? assigned,
        bool done = false,
        bool upcoming = false,
      }) async {
        final id = const Uuid().v4();
        ids.add(id);
        await writer.command(id, 'task.created', {
          'title': title,
          'description': description,
          'assignee': assigned ?? user,
          'schedule': upcoming ? {'startDate': '2099-01-01'} : {},
        });
        if (done) await writer.command(id, 'task.completed', {});
      }

      await add('Planning available');
      await add(
        'Other household task',
        description: 'Planning reference',
        assigned: other,
      );
      await add('Planning future', upcoming: true);
      await add('Planning finished', done: true);
      await add('Unrelated task');
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      await filterChoice(tester, 'Completed');
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.tap(find.byKey(const ValueKey('open-search')));
      await tester.pumpAndSettle();
      final searchField = find.byKey(const ValueKey('task-search'));
      await tester.enterText(searchField, '  PLANNING  ');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('task-filter')))
            .onPressed,
        isNull,
      );
      for (final title in [
        'Planning available',
        'Other household task',
        'Planning future',
        'Planning finished',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Unrelated task'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Planning finished')).dy,
        greaterThan(tester.getTopLeft(find.text('Planning available')).dy),
      );
      final doneRow = find.byKey(ValueKey('task-row-${ids[3]}'));
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(of: doneRow, matching: find.byType(Checkbox)),
            )
            .value,
        isTrue,
      );

      await selectTask(tester, ids[0], control: false);
      await selectTask(tester, ids[3], control: false, shift: true);
      expect(find.byType(BulkTaskEditor), findsOneWidget);
      expect(find.text('4 selected'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      Future<void> drag(String source, String target) async {
        final sourceRow = find.byKey(ValueKey('task-drop-$source'));
        final handle = find.descendant(
          of: sourceRow,
          matching: find.byType(Draggable<String>),
        );
        await tester.ensureVisible(handle);
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(-24, 0));
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(find.byKey(ValueKey('task-drop-$target'))),
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await writer.refresh();
      final beforeMove = writer.taskSnapshot;
      await drag(ids[0], ids[1]);
      await writer.refresh();
      expect(writer.taskSnapshot, isNot(beforeMove));
      final beforeRejected = writer.taskSnapshot;
      await drag(ids[0], ids[3]);
      await writer.refresh();
      expect(writer.taskSnapshot, beforeRejected);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(searchField);
      await tester.enterText(searchField, 'no matching task');
      await tester.pumpAndSettle();
      expect(find.text('No tasks match your search'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Planning finished'), findsOneWidget);
      expect(find.text('Planning available'), findsNothing);
      await filterChoice(tester, 'Open');
      await tester.enterText(capture, 'Unsubmitted household draft');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'planning');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Unsubmitted household draft',
      );
      await writer.command(const Uuid().v4(), 'task.created', {
        'title': 'Planning incoming',
        'description': '',
        'assignee': other,
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Planning incoming'), findsOneWidget);
      expect(
        tester.widget<TextField>(searchField).controller!.text,
        'planning',
      );

      final finished = find.byKey(ValueKey('task-row-${ids[3]}'));
      final reopen = find.descendant(
        of: finished,
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(reopen);
      await tester.pumpAndSettle();
      await tester.tap(reopen);
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.firstWhere((row) => row['id'] == ids[3])['completed'],
        isFalse,
      );
      expect(find.text('Completed'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await writer.close();
      await root.delete(recursive: true);
    },
  );
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
      await filterChoice(tester, 'Completed');
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
      await filterChoice(tester, 'Open');
      await tester.pumpAndSettle();
      expect(find.text('Buy oats'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
      await tester.tap(find.byTooltip('Complete Buy oats'));
      await tester.pumpAndSettle();
      await filterChoice(tester, 'Completed');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reopen Buy oats'));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      await filterChoice(tester, 'Open');
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
        await openSettings(tester);
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
      expect(find.textContaining('This task changed.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Title'))
            .controller!
            .text,
        'Local edited title',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original task'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
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
      await openSettings(tester);
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
  testWidgets(
    'compact filters compose reopen reset and keep identity separate',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('compact-filter-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), other = const Uuid().v4();
      const activeName = 'Alexandria Example Household Member';
      await writer.command(user, 'user.created', {'name': activeName});
      await writer.command(other, 'user.created', {'name': 'Sam Example'});
      Future<void> add(
        String title,
        String assignee, {
        bool future = false,
        bool done = false,
        String tag = 'Home',
      }) async {
        final id = const Uuid().v4();
        await writer.command(id, 'task.created', {
          'title': title,
          'description': '',
          'assignee': assignee,
          'schedule': future ? {'startDate': '2099-01-01'} : {},
        });
        await writer.edit(id, {}, tags: [tag], observedTagRefs: {});
        if (done) await writer.command(id, 'task.completed', {});
      }

      await add('Ready household task', user);
      await add('Future household task', user, future: true);
      await add('Other household task', other);
      await add('Completed household task', other, done: true);
      await add('Different tag task', user, tag: 'home');
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      const draft = TextEditingValue(
        text: 'Retain this draft',
        selection: TextSelection(baseOffset: 3, extentOffset: 9),
        composing: TextRange(start: 3, end: 9),
      );
      tester.widget<TextField>(capture).controller!.value = draft;
      await openFilters(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Everyone'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Everyone'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isFalse,
      );
      await chooseFilter(tester, 'Everyone');
      await chooseFilter(tester, 'Show upcoming');
      await chooseFilter(tester, '#Home');
      await chooseFilter(tester, 'Completed');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Completed household task'), findsOneWidget);
      expect(find.text('Different tag task'), findsNothing);
      expect(find.byTooltip('Active user: $activeName'), findsOneWidget);
      final badge = find.descendant(
        of: find.byKey(const ValueKey('task-filter')),
        matching: find.byType(Badge),
      );
      expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);
      await openFilters(tester);
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Everyone'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isTrue,
      );
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Completed'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isTrue,
      );
      expect(find.byKey(const ValueKey('selected-tag-Home')), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Show upcoming'),
            )
            .value,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);
      await tester.tap(find.byKey(const ValueKey('identity-menu')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.ancestor(
                of: find.text(activeName),
                matching: find.byType(CheckedPopupMenuItem<String>),
              ),
            )
            .checked,
        isTrue,
      );
      await tester.tap(
        find.ancestor(
          of: find.text('Sam Example').last,
          matching: find.byType(CheckedPopupMenuItem<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Active user: Sam Example'), findsOneWidget);
      expect(find.text('Completed household task'), findsOneWidget);
      await openFilters(tester);
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Everyone'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isTrue,
      );
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<bool>>(
              find.ancestor(
                of: find.text('Active user'),
                matching: find.byType(RadioGroup<bool>),
              ),
            )
            .groupValue,
        isFalse,
      );
      expect(find.byType(InputChip), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Show upcoming'),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Active user: Sam Example'), findsOneWidget);
      expect(find.text('Other household task'), findsOneWidget);
      expect(find.text('Ready household task'), findsNothing);
      expect(tester.widget<TextField>(capture).controller!.value, draft);
      expect(tester.widget<Badge>(badge).isLabelVisible, isFalse);
      await openSettings(tester);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Active user: Sam Example'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await writer.close();
      await root.delete(recursive: true);
    },
  );
  testWidgets('bounded tag search and responsive task metadata remain readable', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('tag-picker-rows-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4(), other = const Uuid().v4();
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    await writer.command(other, 'user.created', {'name': 'Sam Example'});
    final ids = <String, String>{};
    Future<void> add(
      String title, {
      String? assigned,
      List<String> tags = const [],
      Map<String, dynamic> schedule = const {},
      String description = '',
    }) async {
      final id = ids[title] = const Uuid().v4();
      await writer.command(id, 'task.created', {
        'title': title,
        'description': description,
        'assignee': assigned ?? user,
        'schedule': schedule,
      });
      if (tags.isNotEmpty) {
        await writer.edit(id, {}, tags: tags, observedTagRefs: {});
      }
    }

    const targetTag =
        'UniqueX099/VeryLongOrdinaryTagForNarrowAccessibilityInspection';
    await add(
      'Review supplies',
      tags: ['Home'],
      schedule: {'dueDate': '2030-04-23'},
    );
    const longTitle =
        'Read the complete notes for next month’s shared household planning and prepare a checklist for the weekend';
    await add(
      longTitle,
      tags: ['Planning'],
      schedule: {
        'dueDate': '2030-04-23',
        'dueTime': '17:30',
        'startDate': '2020-01-01',
        'timeZone': 'America/Argentina/Buenos_Aires',
      },
    );
    await add('A task without metadata');
    await add(
      'Bring the reference notes',
      tags: ['home'],
      description: 'Bring the current notes\nand checklist.',
    );
    await add('Search result target', tags: [targetTag]);
    await add(
      'Other user tag inventory',
      assigned: other,
      tags: List.generate(
        100,
        (i) =>
            'Planning/LongOrdinaryTagForSearchAndAccessibility${i.toString().padLeft(3, '0')}',
      ),
    );
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: profile.path,
        timeSourceFactory: (onChanged) =>
            ViewTimeSource(onChanged: onChanged, loadZone: () async => 'UTC'),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 820);
    await tester.pumpAndSettle();
    final shortTitle = find.byKey(
      ValueKey('task-title-${ids['Review supplies']}'),
    );
    final shortMeta = find.byKey(
      ValueKey('task-metadata-${ids['Review supplies']}'),
    );
    expect(tester.widget<Text>(shortMeta).data, '#Home');
    expect(tester.getRect(shortMeta).top, tester.getRect(shortTitle).top);
    expect(
      tester.getRect(shortMeta).left - tester.getRect(shortTitle).right,
      closeTo(12, 1),
    );
    final deadline = tester.widget<Text>(
      find.byKey(ValueKey('task-metadata-${ids[longTitle]}')),
    );
    expect(deadline.data, contains('Due 20:30'));
    expect(deadline.data, isNot(contains('2030-04-23')));
    expect(deadline.data, isNot(contains('2020-01-01')));
    expect(deadline.data, isNot(contains('Start')));
    expect(deadline.data, isNot(contains('America/')));
    expect(deadline.maxLines, isNull);
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('task-title-${ids[longTitle]}')))
          .maxLines,
      isNull,
    );
    expect(
      find.byKey(ValueKey('task-metadata-${ids['A task without metadata']}')),
      findsNothing,
    );
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('A task without metadata'),
              matching: find.byType(ListTile),
            ),
          )
          .subtitle,
      isNull,
    );
    expect(
      tester
          .widget<Text>(find.text('Bring the current notes and checklist.'))
          .maxLines,
      1,
    );
    await openFilters(tester);
    final search = find.byKey(const ValueKey('tag-search'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('tag-results'))).height,
      lessThanOrEqualTo(200),
    );
    expect(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is ListTile &&
                widget.key is ValueKey<String> &&
                ((widget.key as ValueKey<String>).value).startsWith(
                  'tag-option-',
                ),
          )
          .evaluate()
          .length,
      lessThan(30),
    );
    await tester.enterText(search, 'does-not-exist');
    await tester.pumpAndSettle();
    expect(find.text('No matching tags'), findsOneWidget);
    await tester.enterText(search, 'home');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-option-Home')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-option-home')), findsOneWidget);
    await tester.enterText(search, 'uniquex099');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-option-$targetTag')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('selected-tag-$targetTag')),
      findsOneWidget,
    );
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.text('Search result target'), findsOneWidget);
    expect(find.text('Review supplies'), findsNothing);
    await openFilters(tester);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(
      find.byKey(const ValueKey('selected-tag-$targetTag')),
      findsOneWidget,
    );
    await chooseFilter(tester, 'All tags');
    expect(find.byType(InputChip), findsNothing);
    await tester.enterText(search, 'home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    for (final scale in [1.0, 2.0]) {
      tester.view.physicalSize = const Size(390, 820);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      await tester.ensureVisible(shortTitle);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(shortMeta).top,
        greaterThanOrEqualTo(tester.getRect(shortTitle).bottom),
      );
      expect(tester.takeException(), isNull);
    }
    await openFilters(tester);
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-results')), findsOneWidget);
    // The keyboard may appear after opening; no typing or scrolling is needed
    // to update the overlay's bounds or hide a now-offscreen anchor.
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final movedPopup = find.byKey(const ValueKey('tag-results'));
    if (movedPopup.evaluate().isNotEmpty) {
      expect(tester.getRect(movedPopup).bottom, lessThanOrEqualTo(540));
    }
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    await tester.pumpAndSettle();
    final insetDialogRect = tester.getRect(find.byType(AlertDialog));
    for (final query in ['home', 'does-not-exist', '']) {
      await tester.enterText(search, query);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(AlertDialog)), insetDialogRect);
      final popup = tester.getRect(find.byKey(const ValueKey('tag-results')));
      expect(popup.top, greaterThanOrEqualTo(0));
      expect(popup.bottom, lessThanOrEqualTo(540));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-results')), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await writer.close();
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
      final userBefore = tester.getRect(
        find.byKey(const ValueKey('identity-menu')),
      );
      final filterBefore = tester.getRect(
        find.byKey(const ValueKey('task-filter')),
      );
      final headerBefore = tester.getRect(
        find.byKey(const ValueKey('task-header')),
      );
      final captureBefore = tester.getRect(
        find.widgetWithText(TextField, 'What needs doing?'),
      );
      expect(find.text('Everyone'), findsNothing);
      expect(find.text('Show upcoming'), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      await filterChoice(tester, 'Completed');
      expect(
        tester.getRect(find.byKey(const ValueKey('identity-menu'))),
        userBefore,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('task-filter'))),
        filterBefore,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('task-header'))),
        headerBefore,
      );
      expect(tester.takeException(), isNull);
      await filterChoice(tester, 'Open');
      expect(
        tester.getRect(find.widgetWithText(TextField, 'What needs doing?')),
        captureBefore,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('task-filter'))),
        filterBefore,
      );
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
        'schedule': {'scheduledDate': '2026-01-30', 'scheduledTime': '08:00'},
      });
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (onChanged) => ViewTimeSource(
            onChanged: onChanged,
            now: () => DateTime.utc(2026, 3, 1),
            loadZone: () async => 'UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly review'));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        if (label.startsWith('This occurrence') &&
            find.widgetWithText(TextField, label).evaluate().isEmpty) {
          await tester.tap(find.text('Edit existing override'));
          await tester.pumpAndSettle();
        }
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
      expect(find.byType(TaskEditor), findsOneWidget);
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
      await fill('This occurrence time', '08:00');
      await fill('Due time', '17:00');
      await fill('Time zone', 'UTC');
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
      expect(find.textContaining('Start 09:30'), findsOneWidget);
      expect(find.textContaining('09:30 UTC'), findsNothing);
      expect(find.byTooltip('Task actions'), findsNothing);
      final reorder = find
          .descendant(
            of: find.byKey(ValueKey('task-row-$task')),
            matching: find.byType(Semantics),
          )
          .evaluate()
          .map((element) => element.widget as Semantics)
          .firstWhere(
            (widget) =>
                widget.properties.customSemanticsActions?.keys.any(
                  (action) => action.label == 'Move down',
                ) ??
                false,
          );
      reorder.properties.customSemanticsActions!.entries
          .firstWhere((entry) => entry.key.label == 'Move down')
          .value();
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
      await filterChoice(tester, 'Completed');
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
  testWidgets(
    'native tag filters preserve drafts and selected block drag scrolls offscreen',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('tag-scroll-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), other = const Uuid().v4();
      await writer.command(user, 'user.created', {'name': 'Example'});
      await writer.command(other, 'user.created', {'name': 'Other'});
      final ids = <String>[];
      for (var i = 0; i < 35; i++) {
        final id = const Uuid().v4();
        ids.add(id);
        await writer.command(id, 'task.created', {
          'title': 'Task $i',
          'description': '',
          'assignee': i == 1 ? other : user,
          'schedule': i == 2 ? {'startDate': '2099-11-01'} : {},
        });
        await writer.edit(
          id,
          {},
          tags: [i == 3 ? 'OtherTag' : 'Home'],
          observedTagRefs: {},
        );
      }
      await writer.command(ids[4], 'task.completed', {});
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.enterText(capture, 'Keep this draft');
      await filterChoice(tester, '#Home');
      await tester.pumpAndSettle();
      expect(find.text('Task 3'), findsNothing);
      expect(find.text('Task 1'), findsNothing);
      expect(find.text('Task 2'), findsNothing);
      await filterChoice(tester, 'Everyone');
      await tester.pumpAndSettle();
      expect(find.text('Task 1'), findsOneWidget);
      await filterChoice(tester, 'Show upcoming');
      await tester.pumpAndSettle();
      expect(find.text('Task 2'), findsOneWidget);
      await filterChoice(tester, 'Completed');
      await tester.pumpAndSettle();
      expect(find.text('Task 4'), findsOneWidget);
      await filterChoice(tester, 'Open');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Keep this draft',
      );
      await filterChoice(tester, 'All tags');
      await tester.pumpAndSettle();
      expect(find.text('Task 3'), findsOneWidget);
      await filterChoice(tester, '#Home');
      await tester.pumpAndSettle();

      for (final id in ids.take(2)) {
        await selectTask(tester, id);
      }
      // Selecting another row may scroll the lazy list past the first handle.
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      final handle = find.descendant(
        of: find.byKey(ValueKey('task-drop-${ids[0]}')),
        matching: find.byType(Draggable<String>),
      );
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final beforeCancel = writer.taskSnapshot;
      final cancelGesture = await tester.startGesture(tester.getCenter(handle));
      await cancelGesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      final peer = tester.getRect(find.byKey(ValueKey('task-drop-${ids[5]}')));
      await cancelGesture.moveTo(peer.center);
      await tester.pump();
      await cancelGesture.cancel();
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(writer.taskSnapshot, beforeCancel);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      // Touch users may hold before moving; a tooltip must not win the gesture.
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.text('Drag to reorder within this date and time'),
        findsNothing,
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      final list = find.byType(ListView).first;
      final viewport = tester.getRect(list);
      expect(find.byKey(ValueKey('task-drop-${ids.last}')), findsNothing);
      await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 12));
      for (var i = 0; i < 250; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final last = find.byKey(ValueKey('task-drop-${ids.last}'));
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(viewport.bottom + 1),
      );
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.where((row) => row['kind'] == 'task').last['id'],
        ids[1],
      );
      expect(
        writer.rows
            .where((row) => row['kind'] == 'task')
            .map((row) => row['id'])
            .toList(),
        [...ids.skip(2), ...ids.take(2)],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(
              find.descendant(
                of: find.byKey(const ValueKey('task-filter')),
                matching: find.byType(Badge),
              ),
            )
            .isLabelVisible,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await writer.close();
      await root.delete(recursive: true);
    },
  );
  testWidgets(
    'native drag preserves hidden order and rejects other time buckets',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('drag-order-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), other = const Uuid().v4();
      await writer.command(user, 'user.created', {'name': 'Example'});
      await writer.command(other, 'user.created', {'name': 'Other'});
      final ids = <String, String>{};
      Future<void> add(
        String title, {
        String? assignee,
        Map<String, dynamic> schedule = const {},
      }) async {
        final id = ids[title] = const Uuid().v4();
        await writer.command(id, 'task.created', {
          'title': title,
          'description': '',
          'assignee': assignee ?? user,
          'schedule': schedule,
        });
      }

      await add('First');
      await add('Hidden assignee', assignee: other);
      await add('Second');
      await add('Hidden future', schedule: {'startDate': '2026-11-01'});
      await add('Third');
      await add('Dated', schedule: {'dueDate': '2026-10-02', 'dueMinDays': 1});
      await add(
        'Dated peer',
        schedule: {'scheduledDate': '2026-10-02', 'dueMinDays': 1},
      );
      await add(
        'Different time',
        schedule: {'dueDate': '2026-10-02', 'dueTime': '10:00'},
      );
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      var viewNow = DateTime.utc(2026, 10, 1);
      late ViewTimeSource source;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (onChanged) => source = ViewTimeSource(
            onChanged: onChanged,
            loadZone: () async => 'UTC',
            now: () => viewNow,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder target(String title) =>
          find.byKey(ValueKey('task-drop-${ids[title]}'));
      Finder handle(String title) => find.descendant(
        of: target(title),
        matching: find.byType(Draggable<String>),
      );
      Future<void> drag(
        String from,
        String to, {
        bool after = true,
        bool invalidate = false,
        bool advanceClock = false,
        bool invalidSelection = false,
      }) async {
        await tester.ensureVisible(handle(from));
        await tester.pumpAndSettle();
        final start = tester.getCenter(handle(from));
        final rect = tester.getRect(target(to));
        final point = Offset(
          rect.center.dx,
          after ? rect.bottom - 8 : rect.top + 8,
        );
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        await gesture.moveTo(point);
        await tester.pump();
        if (invalidate) {
          source.onChanged();
          await tester.pump();
        }
        if (invalidate || invalidSelection || to == 'Different time') {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label ==
                      'Cannot reorder here: different date or time, or the list changed.',
            ),
            findsOneWidget,
          );
        }
        if (advanceClock) viewNow = viewNow.add(const Duration(days: 1));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      expect(tester.getSize(handle('First')).width, greaterThanOrEqualTo(48));
      await drag('First', 'Third');
      await writer.refresh();
      List<String> order() => writer.rows
          .where((r) => r['kind'] == 'task')
          .map((r) => r['title'] as String)
          .toList();
      expect(order(), [
        'Hidden assignee',
        'Second',
        'Hidden future',
        'Third',
        'First',
        'Dated',
        'Dated peer',
        'Different time',
      ]);
      final before = order();
      final bytes = await folder
          .list()
          .where((f) => f.path.endsWith('.jsonl'))
          .asyncMap((f) => File(f.path).readAsString())
          .toList();
      await drag('Dated', 'Different time');
      expect(
        find.text(
          'Reorder canceled. Drop beside a task with the same date and time.',
        ),
        findsOneWidget,
      );
      await writer.refresh();
      expect(order(), before);
      expect(
        await folder
            .list()
            .where((f) => f.path.endsWith('.jsonl'))
            .asyncMap((f) => File(f.path).readAsString())
            .toList(),
        bytes,
      );

      for (final title in ['Dated', 'Third']) {
        await selectTask(tester, ids[title]!);
      }
      await drag('Dated', 'Dated peer', invalidSelection: true);
      await writer.refresh();
      expect(
        order(),
        before,
        reason: 'Every selected task must share the target key.',
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await drag('Second', 'First', invalidate: true);
      expect(
        find.text('The task list changed. Try dragging again.'),
        findsOneWidget,
      );
      await writer.refresh();
      expect(order(), before);
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold)),
      ).clearSnackBars();
      await tester.pumpAndSettle();
      await drag('Dated', 'Dated peer', advanceClock: true);
      expect(
        find.text('The task list changed. Try moving the task again.'),
        findsOneWidget,
      );
      await writer.refresh();
      expect(order(), before);
      viewNow = DateTime.utc(2026, 10, 1);
      source.onChanged();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dated peer'));
      await tester.pumpAndSettle();
      // Existing schedule starts expanded.
      await tester.pumpAndSettle();
      const warning = 'Existing occurrence override is preserved.';
      final repeat = find.widgetWithText(TextField, 'Repeat');
      await tester.ensureVisible(repeat);
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      await tester.enterText(repeat, 'every week');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('base due date and repeat cadence remain'),
        findsOneWidget,
      );
      await tester.enterText(repeat, '');
      await tester.pumpAndSettle();
      expect(find.text(warning), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await writer.refresh();
      final schedule =
          writer.rows.firstWhere(
                (row) => row['id'] == ids['Dated peer'],
              )['schedule']
              as Map;
      expect(schedule['scheduledDate'], '2026-10-02');
      expect(schedule['recurrence'], isNull);
      expect(find.text('Hidden future'), findsNothing);
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.enterText(capture, 'Keep this draft');
      await filterChoice(tester, 'Show upcoming');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Keep this draft',
      );
      await tester.scrollUntilVisible(
        find.text('Hidden future'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hidden future'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Edited before availability',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await writer.refresh();
      expect(
        writer.rows.firstWhere(
          (row) => row['id'] == ids['Hidden future'],
        )['description'],
        'Edited before availability',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (onChanged) => ViewTimeSource(
            onChanged: onChanged,
            loadZone: () async => 'UTC',
            now: () => DateTime.utc(2026, 10, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openFilters(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Show upcoming'),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Hidden future'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await writer.close();
      await root.delete(recursive: true);
    },
  );
  testWidgets('loaded startup marker waits for a rendered time projection', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('startup-projection-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4();
    await writer.command(user, 'user.created', {'name': 'Example user'});
    await writer.command(const Uuid().v4(), 'task.created', {
      'title': 'Ready after projection',
      'description': '',
      'assignee': user,
      'schedule': {
        'dueDate': '2026-10-01',
        'dueTime': '17:30',
        'timeZone': 'UTC',
      },
    });
    await writer.close();
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    final printed = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) printed.add(message);
      originalPrint(message, wrapWidth: wrapWidth);
    };
    try {
      var zone = Completer<String>();
      late ViewTimeSource source;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (onChanged) => source = ViewTimeSource(
            onChanged: onChanged,
            loadZone: () => zone.future,
            now: () => DateTime.utc(2026, 10, 1),
          ),
        ),
      );
      for (
        var attempt = 0;
        attempt < 100 &&
            !printed.any((line) => line.startsWith('TANDEMLOG_ROWS'));
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      expect(printed.any((line) => line.startsWith('TANDEMLOG_ROWS')), isTrue);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        printed.where((line) => line.startsWith('TANDEMLOG_READY_MS=')),
        isEmpty,
      );
      zone.complete('UTC');
      await tester.pumpAndSettle();
      expect(find.text('Ready after projection'), findsOneWidget);
      expect(
        printed.where((line) => line.startsWith('TANDEMLOG_READY_MS=')),
        hasLength(1),
      );
      source.onChanged();
      await tester.pumpAndSettle();
      expect(
        printed.where((line) => line.startsWith('TANDEMLOG_READY_MS=')),
        hasLength(1),
      );
      zone = Completer<String>();
      source.stop();
      source.start();
      source.onChanged();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Due 17:30'), findsOneWidget);
      zone.complete('UTC');
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    } finally {
      debugPrint = originalPrint;
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'timed task groups preserve drafts and editors without log writes',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('timed-view-ui-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4();
      final remote = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/reader',
      );
      await remote.command(user, 'user.created', {'name': 'Example user'});
      final ids = <String, String>{};
      Future<void> add(String title, Map<String, dynamic> schedule) async {
        final id = ids[title] = const Uuid().v4();
        await remote.command(id, 'task.created', {
          'title': title,
          'description': 'Original notes',
          'assignee': user,
          'schedule': schedule,
        });
      }

      await add('Scheduled before due', {
        'scheduledDate': '2026-10-02',
        'dueDate': '2026-10-10',
      });
      await add('Due earlier', {'dueDate': '2026-10-01'});
      await add('Someday example', {});
      await add('Boundary arrival', {
        'startDate': '2026-10-01',
        'startTime': '10:00',
        'dueDate': '2026-10-03',
      });
      await add('Second arrival', {
        'startDate': '2026-10-01',
        'startTime': '10:01',
        'dueDate': '2026-10-04',
      });
      await add('Completed future history', {
        'startDate': '2026-11-01',
        'dueDate': '2026-11-02',
      });
      await remote.complete(
        ids['Completed future history']!,
        completionDay: DateTime.utc(2026, 9, 30),
      );
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      Future<Map<String, String>> logs() async => {
        for (final file
            in await folder
                .list()
                .where((entry) => entry.path.endsWith('.jsonl'))
                .toList())
          file.path: await File(file.path).readAsString(),
      };
      final before = await logs();
      var base = DateTime.utc(2026, 10, 1, 9, 59, 30);
      final elapsed = Stopwatch()..start();
      late ViewTimeSource source;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (onChanged) => source = ViewTimeSource(
            onChanged: onChanged,
            now: () => base.add(elapsed.elapsed),
            loadZone: () async => 'UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Boundary arrival'), findsNothing);
      expect(find.text('Second arrival'), findsNothing);
      expect(find.text('Someday'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Due earlier')).dy,
        lessThan(tester.getTopLeft(find.text('Scheduled before due')).dy),
      );
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.tap(capture);
      await tester.enterText(capture, 'Unsubmitted draft');
      final captureWidget = tester.widget<TextField>(capture);
      final draft = captureWidget.controller!.value;
      expect(captureWidget.focusNode!.hasFocus, isTrue);
      base = DateTime.utc(2026, 10, 1, 9, 59, 59);
      elapsed.reset();
      source.onChanged();
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      await tester.pumpAndSettle();
      expect(find.text('Boundary arrival'), findsOneWidget);
      expect(tester.widget<TextField>(capture).controller!.value, draft);
      expect(tester.widget<TextField>(capture).focusNode!.hasFocus, isTrue);
      expect(await logs(), before);
      await tester.ensureVisible(find.text('Scheduled before due'));
      await tester.tap(find.text('Scheduled before due'));
      await tester.pumpAndSettle();
      final notes = find.widgetWithText(TextField, 'Notes');
      await tester.tap(notes);
      await tester.enterText(notes, 'An interrupted edit remains here.');
      final editing = tester.widget<TextField>(notes).controller!.value;
      base = DateTime.utc(2026, 10, 1, 10, 0, 59);
      elapsed.reset();
      source.onChanged();
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(tester.widget<TextField>(notes).controller!.value, editing);
      expect(await logs(), before);
      Future<void> fill(String label, String text) async {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
      }

      await fill('Minimum days', '5');
      await fill('Maximum days', '2');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('minimum no greater than maximum'),
        findsOneWidget,
      );
      expect(await logs(), before);
      await fill('Minimum days', '1');
      await fill('Maximum days', '3');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Second arrival'), findsOneWidget);
      expect(tester.widget<TextField>(capture).controller!.value, draft);
      await remote.refresh();
      final edited = remote.rows.firstWhere(
        (row) => row['id'] == ids['Scheduled before due'],
      );
      expect((edited['schedule'] as Map)['dueMinDays'], 1);
      expect((edited['schedule'] as Map)['dueMaxDays'], 3);
      expect((edited['schedule'] as Map)['dueDate'], '2026-10-10');
      await filterChoice(tester, 'Completed');
      await tester.pumpAndSettle();
      expect(find.text('Completed future history'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await remote.close();
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
