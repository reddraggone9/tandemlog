import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/checklist_panel.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

class _FailingMenuFolder implements LogFolder {
  _FailingMenuFolder(this.inner);
  final LocalLogFolder inner;
  bool failLists = false;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() {
    if (failLists) throw StateError('Synthetic menu refresh failure.');
    return inner.list();
  }

  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
}

Finder _key(String key) => find.byKey(ValueKey(key));
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Inline checklist UI did not become ready.');
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerInlineChecklistWorkflowTests();
}

void registerInlineChecklistWorkflowTests() {
  testWidgets(
    'checklist toggle acts directly on shown parents and follows live state',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'inline-display-toggle-',
      );
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final folder = LocalLogFolder(shared.path);
      final peer = await openNativeFixtureStore(folder, '${root.path}/peer');
      final user = const Uuid().v4(),
          first = const Uuid().v4(),
          second = const Uuid().v4();
      try {
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        for (final entry in [
          (first, 'First parent', ['visible']),
          (second, 'Second parent', ['hidden']),
        ]) {
          await peer.createNativeFixtureTask(entry.$1, {
            'title': entry.$2,
            'description': '',
            'assignee': user,
            'tags': entry.$3,
          });
        }
        final firstItem = (await peer.addChecklistItem(
          first,
          'First item',
        )).entity;
        final secondItem = (await peer.addChecklistItem(
          second,
          'Second item',
        )).entity;
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await _until(
          tester,
          () => _key('task-row-$first').evaluate().isNotEmpty,
        );
        final dynamic state = tester.state(find.byType(TasksPage));
        final before = {
          for (final file in await folder.list())
            file.name: base64Encode(await folder.read(file.name)),
        };
        void action(String next, IconData icon) {
          expect(find.byTooltip('$next shown checklists'), findsOneWidget);
          expect(
            find.descendant(
              of: _key('checklist-display-toggle'),
              matching: find.byIcon(icon),
            ),
            findsOneWidget,
          );
          expect(
            tester.getSize(_key('checklist-display-toggle')).width,
            greaterThanOrEqualTo(48),
          );
        }

        action('Expand', Icons.unfold_more);
        await _tap(tester, _key('checklist-disclosure-$first'));
        expect(find.byType(ChecklistPanel), findsOneWidget);
        action('Collapse', Icons.unfold_less);
        await _tap(tester, _key('checklist-display-toggle'));
        expect(find.byType(ChecklistPanel), findsNothing);
        expect(find.byType(PopupMenuItem<bool>), findsNothing);
        action('Expand', Icons.unfold_more);
        await _tap(tester, _key('checklist-display-toggle'));
        expect(find.byType(ChecklistPanel), findsNWidgets(2));
        action('Collapse', Icons.unfold_less);
        await _tap(tester, _key('checklist-disclosure-$first'));
        action('Collapse', Icons.unfold_less);
        await flows.filterChoice(tester, '#visible');
        expect(_key('task-row-$second'), findsNothing);
        action('Expand', Icons.unfold_more);
        await _tap(tester, _key('checklist-display-toggle'));
        expect(find.byType(ChecklistPanel), findsOneWidget);
        action('Collapse', Icons.unfold_less);
        await _tap(tester, _key('checklist-display-toggle'));
        expect(find.byType(ChecklistPanel), findsNothing);
        await flows.filterChoice(tester, 'All tags');
        expect(
          _key('checklist-check-$secondItem'),
          findsOneWidget,
          reason: 'Hidden expansion is untouched.',
        );
        expect(_key('checklist-check-$firstItem'), findsNothing);
        action('Collapse', Icons.unfold_less);
        await _tap(tester, _key('checklist-display-toggle'));
        expect(find.byType(ChecklistPanel), findsNothing);
        expect({
          for (final file in await folder.list())
            file.name: base64Encode(await folder.read(file.name)),
        }, before);
        await peer.deleteChecklistItem(firstItem);
        await peer.deleteChecklistItem(secondItem);
        await _until(
          tester,
          () =>
              (state.store as TaskStore).checklistItems(first).isEmpty &&
              (state.store as TaskStore).checklistItems(second).isEmpty,
        );
        expect(_key('checklist-display-toggle'), findsNothing);
        await peer.addChecklistItem(first, 'Incoming replacement');
        await _until(
          tester,
          () => (state.store as TaskStore).checklistItems(first).isNotEmpty,
        );
        action('Expand', Icons.unfold_more);
        await _tap(tester, _key('checklist-display-toggle'));
        action('Collapse', Icons.unfold_less);
        expect(find.byType(ChecklistPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureNativeFixtureUi(tester, 'direct-toggle-narrow');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await peer.close();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      }
    },
  );

  testWidgets('task row inset follows available width including desktop resize', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('inline-responsive-');
    final shared = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final folder = LocalLogFolder(shared.path);
    final peer = await openNativeFixtureStore(folder, '${root.path}/peer');
    final user = const Uuid().v4(),
        parent = const Uuid().v4(),
        other = const Uuid().v4();
    try {
      await peer.command(user, 'user.created', {'name': 'Alex Example'});
      for (final task in [parent, other]) {
        await peer.createNativeFixtureTask(task, {
          'title':
              'A long parent title that wraps on narrow windows while controls remain separate',
          'description': '',
          'tags': task == parent ? ['chore'] : <String>[],
          'assignee': user,
        });
      }
      // Put the untagged parent in the same order bucket while retaining no secondary text.
      await peer.editNativeFixtureTask(other, {'assignee': user});
      final item = (await peer.addChecklistItem(
        parent,
        'Long checklist item title that still leaves space for independent trailing controls',
      )).entity;
      await peer.addChecklistItem(parent, 'Second item');
      await peer.addChecklistItem(other, 'Collapsed item');
      await File('${profile.path}/settings.json').writeAsString(
        jsonEncode({'folder': shared.path, 'user': user, 'appearance': 'dark'}),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await _until(
        tester,
        () => _key('task-row-$parent').evaluate().isNotEmpty,
      );
      await _tap(tester, _key('checklist-disclosure-$parent'));
      for (final geometry in [
        (599.0, 1.0, 0.0, 0.0),
        (1200.0, 1.0, 0.0, 0.0),
        (600.0, 1.0, 0.0, 0.0),
        (390.0, 1.0, 0.0, 0.0),
        (360.0, 2.0, 0.0, 0.0),
        (390.0, 2.0, 0.0, 0.0),
        (620.0, 1.0, 12.0, 20.0),
        (390.0, 1.0, 12.0, 20.0),
      ]) {
        tester.view.physicalSize = Size(geometry.$1, 1000);
        tester.platformDispatcher.textScaleFactorTestValue = geometry.$2;
        tester.view.padding = FakeViewPadding(
          left: geometry.$3,
          right: geometry.$4,
        );
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('task-row-$parent'));
        final viewport = tester.getRect(find.byType(CustomScrollView).last);
        final row = tester.getRect(_key('task-row-$parent'));
        final inset = viewport.width < 600 ? 0.0 : 16.0;
        expect(row.left, closeTo(viewport.left + inset, 0.01));
        expect(row.right, closeTo(viewport.right - inset, 0.01));
        final parentHandle = find.descendant(
          of: _key('task-block-$parent'),
          matching: find.byType(Draggable<String>),
        );
        final menu = tester.getRect(_key('task-menu-$parent'));
        final handle = tester.getRect(parentHandle);
        expect(
          menu.right,
          closeTo(handle.left, 0.01),
          reason: 'Adjacent independent targets have no added gap.',
        );
        expect(menu.width, greaterThanOrEqualTo(48));
        expect(handle.width, greaterThanOrEqualTo(48));
        expect(
          tester.getCenter(_key('checklist-drag-$item')).dx,
          closeTo(handle.center.dx, 0.01),
        );
        expect(
          tester.getCenter(_key('checklist-delete-$item')).dx,
          closeTo(menu.center.dx, 0.01),
        );
        await captureNativeFixtureUi(
          tester,
          'row-width-${geometry.$1.toInt()}-scale-${geometry.$2.toInt()}-safe-${geometry.$3.toInt()}',
        );
        for (final taskId in [parent, other]) {
          for (
            var attempt = 0;
            attempt < 12 && _key('task-body-$taskId').evaluate().isEmpty;
            attempt++
          ) {
            await tester.drag(
              find.byType(CustomScrollView).last,
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(_key('task-body-$taskId'));
          await tester.pumpAndSettle();
          final body = tester.getRect(_key('task-body-$taskId'));
          final disclosure = _key('checklist-disclosure-$taskId');
          final target = tester.getRect(disclosure);
          final count = tester.getRect(
            find.descendant(of: disclosure, matching: find.byType(Text)),
          );
          final texts = find.descendant(
            of: _key('task-body-$taskId'),
            matching: find.byType(Text),
          );
          final lastTextBottom = texts
              .evaluate()
              .map(
                (element) =>
                    tester.getRect(find.byWidget(element.widget)).bottom,
              )
              .reduce((a, b) => a > b ? a : b);
          debugPrint(
            'CHECKLIST_DISCLOSURE_GEOMETRY width=${geometry.$1} scale=${geometry.$2} secondary=${taskId == parent} body=$body target=$target count=$count textBottom=$lastTextBottom',
          );
          expect(
            count.top - lastTextBottom,
            closeTo(2, 0.01),
            reason:
                'Match the 2px title/secondary line gap without overlapping touch targets.',
          );
          expect(target.height, greaterThanOrEqualTo(48));
          expect(body.bottom, lessThanOrEqualTo(target.top));
        }
        expect(tester.takeException(), isNull);
      }
      await peer.deleteTask(other, expectedTaskSnapshot: peer.taskSnapshot);
      await _until(tester, () => _key('task-row-$other').evaluate().isEmpty);
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _key('task-block-$parent'),
          matching: find.byType(Draggable<String>),
        ),
        findsNothing,
      );
      expect(
        tester.getCenter(_key('checklist-delete-$item')).dx,
        closeTo(tester.getCenter(_key('task-menu-$parent')).dx, 0.01),
        reason:
            'Checklist columns remain aligned when the parent has no reorder neighbor.',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await peer.close();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetPadding();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
  });

  testWidgets('task menu follows live item counts for mouse and keyboard', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('inline-live-menu-');
    final shared = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final folder = LocalLogFolder(shared.path);
    final peer = await openNativeFixtureStore(folder, '${root.path}/peer');
    final user = const Uuid().v4(), parent = const Uuid().v4();
    try {
      await peer.command(user, 'user.created', {'name': 'Alex Example'});
      await peer.createNativeFixtureTask(parent, {
        'title': 'Live checklist parent',
        'description': '',
        'assignee': user,
      });
      await File('${profile.path}/settings.json').writeAsString(
        jsonEncode({'folder': shared.path, 'user': user, 'appearance': 'dark'}),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await _until(
        tester,
        () => _key('task-row-$parent').evaluate().isNotEmpty,
      );
      final dynamic state = tester.state(find.byType(TasksPage));
      for (final invocation in ['button', 'right click', 'keyboard']) {
        if (invocation == 'button') {
          await _tap(tester, _key('task-menu-$parent'));
        } else if (invocation == 'right click') {
          await tester.tap(
            _key('task-body-$parent'),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
        } else {
          (state.rowFocus[parent] as FocusNode).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
          await tester.pumpAndSettle();
        }
        expect(find.text('Add checklist'), findsOneWidget);
        expect(find.text('Delete task'), findsOneWidget);
        final item = (await peer.addChecklistItem(
          parent,
          'Incoming item',
        )).entity;
        await _until(
          tester,
          () => (state.store as TaskStore).checklistItems(parent).length == 1,
        );
        expect(find.text('Add checklist'), findsNothing, reason: invocation);
        expect(find.text('Delete task'), findsOneWidget);
        if (invocation == 'keyboard') {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Delete task?'), findsOneWidget);
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
          (state.rowFocus[parent] as FocusNode).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
          await tester.pumpAndSettle();
        }
        await peer.deleteChecklistItem(item);
        await _until(
          tester,
          () => (state.store as TaskStore).checklistItems(parent).isEmpty,
        );
        expect(find.text('Add checklist'), findsOneWidget, reason: invocation);
        expect(find.text('Delete task'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final retained = (await peer.addChecklistItem(
          parent,
          'Existing item',
        )).entity;
        await _until(
          tester,
          () => (state.store as TaskStore).checklistItems(parent).length == 1,
        );
        await _tap(tester, _key('task-menu-$parent'));
        expect(find.text('Add checklist'), findsNothing);
        expect(find.text('Delete task'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await peer.deleteChecklistItem(retained);
        await _until(
          tester,
          () => (state.store as TaskStore).checklistItems(parent).isEmpty,
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await peer.close();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }
  });

  testWidgets(
    'task menu refresh failure, keyboard, right click, selected-row Delete and Undo',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('inline-menu-guard-');
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final inner = LocalLogFolder(shared.path);
      final folder = _FailingMenuFolder(inner);
      final peer = await openNativeFixtureStore(inner, '${root.path}/peer');
      final user = const Uuid().v4(),
          parent = const Uuid().v4(),
          other = const Uuid().v4();
      try {
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        await peer.createNativeFixtureTask(parent, {
          'title': 'Chosen parent',
          'description': '',
          'assignee': user,
        });
        await peer.createNativeFixtureTask(other, {
          'title': 'Other selected parent',
          'description': '',
          'assignee': user,
        });
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderFactory: (_) => folder),
        );
        await _until(
          tester,
          () => _key('task-row-$parent').evaluate().isNotEmpty,
        );
        final dynamic state = tester.state(find.byType(TasksPage));
        final before = {
          for (final file in await inner.list())
            file.name: base64Encode(await inner.read(file.name)),
        };
        await _tap(tester, _key('task-menu-$parent'));
        folder.failLists = true;
        await _tap(tester, find.text('Delete task'));
        await _until(
          tester,
          () => find
              .textContaining('Synthetic menu refresh failure.')
              .evaluate()
              .isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        expect(state.busy, false);
        expect(find.text('Delete task?'), findsNothing);
        folder.failLists = false;
        expect({
          for (final file in await inner.list())
            file.name: base64Encode(await inner.read(file.name)),
        }, before);
        // Keyboard and pointer context invocation share the exact actions.
        (state.rowFocus[parent] as FocusNode).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();
        expect(find.text('Add checklist'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('Delete task'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(
          _key('task-body-$parent'),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('Add checklist'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Consent does not authorize deleting a changed parent snapshot.
        await _tap(tester, _key('task-menu-$parent'));
        await _tap(tester, find.text('Delete task'));
        await peer.editNativeFixtureTask(parent, {'title': 'Changed parent'});
        final incoming = {
          for (final file in await inner.list())
            file.name: base64Encode(await inner.read(file.name)),
        };
        await _tap(tester, find.widgetWithText(FilledButton, 'Delete'));
        await _until(tester, () => state.busy == false && state.error != null);
        await peer.refresh();
        expect(peer.currentTextRow(parent), isNotNull);
        expect({
          for (final file in await inner.list())
            file.name: base64Encode(await inner.read(file.name)),
        }, incoming);
        await tester.longPress(_key('task-body-$parent'));
        await tester.pumpAndSettle();
        await _tap(tester, _key('task-body-$other'));
        expect(state.selectedTasks, {parent, other});
        await _tap(tester, _key('task-menu-$parent'));
        await _tap(tester, find.text('Delete task'));
        expect(find.text('Delete task?'), findsOneWidget);
        final confirm = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed!;
        confirm();
        confirm();
        await _until(
          tester,
          () =>
              _key('task-row-$parent').evaluate().isEmpty &&
              state.busy == false,
        );
        await peer.refresh();
        expect(peer.currentTextRow(parent), isNull);
        expect(peer.currentTextRow(other), isNotNull);
        expect(state.selectedTasks, {other});
        expect(find.byType(TasksPage), findsOneWidget);
        await _tap(tester, _key('undo-task-action'));
        await _until(
          tester,
          () =>
              _key('task-row-$parent').evaluate().isNotEmpty &&
              state.busy == false,
        );
        await peer.refresh();
        expect(peer.currentTextRow(parent), isNotNull);
        expect(peer.currentTextRow(other), isNotNull);
        expect(tester.takeException(), isNull);
      } finally {
        folder.failLists = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await peer.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  for (final narrow in [false, true]) {
    testWidgets(
      'inline checklist ${narrow ? 'phone enlarged' : 'desktop'} menu and item ownership',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'inline-checklist-ui-',
        );
        final shared = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final folder = LocalLogFolder(shared.path);
        final peer = await openNativeFixtureStore(folder, '${root.path}/peer');
        final user = const Uuid().v4(),
            parent = const Uuid().v4(),
            empty = const Uuid().v4();
        try {
          await peer.command(user, 'user.created', {'name': 'Alex Example'});
          for (final entry in [
            (parent, 'Pack for a walk'),
            (empty, 'Empty parent'),
          ]) {
            await peer.createNativeFixtureTask(entry.$1, {
              'title': entry.$2,
              'description': '',
              'assignee': user,
            });
          }
          final water = (await peer.addChecklistItem(
            parent,
            'Water bottle',
          )).entity;
          await peer.addChecklistItem(parent, 'Map', notes: 'Printed route');
          await File('${profile.path}/settings.json').writeAsString(
            jsonEncode({
              'folder': shared.path,
              'user': user,
              'appearance': narrow ? 'light' : 'dark',
            }),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = narrow
              ? const Size(390, 820)
              : const Size(1200, 850);
          if (narrow) tester.platformDispatcher.textScaleFactorTestValue = 2;
          TandemlogApp app() => TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (changed) => ViewTimeSource(
              onChanged: changed,
              loadZone: () async => 'UTC',
              now: () => DateTime.utc(2026, 10, 8, 12),
            ),
          );
          await tester.pumpWidget(app());
          await _until(
            tester,
            () => _key('task-row-$parent').evaluate().isNotEmpty,
          );
          expect(_key('task-menu-$empty'), findsOneWidget);
          expect(_key('checklist-disclosure-$parent'), findsOneWidget);
          expect(_key('checklist-disclosure-$empty'), findsNothing);
          expect(find.byType(ChecklistPanel), findsNothing);
          final before = {
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          };
          await _tap(tester, _key('checklist-disclosure-$parent'));
          expect(_key('checklist-check-$water'), findsOneWidget);
          expect(_key('checklist-menu-$water'), findsNothing);
          expect(_key('checklist-delete-$water'), findsOneWidget);
          final parentHandle = find.descendant(
            of: _key('task-block-$parent'),
            matching: find.byType(Draggable<String>),
          );
          expect(parentHandle, findsOneWidget);
          debugPrint(
            'CHECKLIST_TRAILING_GEOMETRY narrow=$narrow '
            'menu=${tester.getRect(_key('task-menu-$parent'))} '
            'parent=${tester.getRect(parentHandle)} '
            'child=${tester.getRect(_key('checklist-drag-$water'))} '
            'delete=${tester.getRect(_key('checklist-delete-$water'))}',
          );
          expect(
            tester.getCenter(_key('checklist-drag-$water')).dx,
            closeTo(tester.getCenter(parentHandle).dx, 0.01),
            reason: 'Child and parent reorder handles share the right column.',
          );
          expect(
            tester.getCenter(_key('checklist-delete-$water')).dx,
            closeTo(tester.getCenter(_key('task-menu-$parent')).dx, 0.01),
            reason: 'Child Delete and parent menu share the trailing column.',
          );
          expect({
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          }, before);
          // Normal recreation retains local disclosure without canonical writes.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpWidget(app());
          await _until(
            tester,
            () => _key('checklist-check-$water').evaluate().isNotEmpty,
          );
          await _tap(tester, _key('task-menu-$empty'));
          expect(find.text('Add checklist'), findsOneWidget);
          expect(find.text('Delete task'), findsOneWidget);
          await _tap(tester, find.text('Add checklist'));
          final emptyPanel = find.descendant(
            of: _key('task-block-$empty'),
            matching: find.byType(ChecklistPanel),
          );
          expect(emptyPanel, findsOneWidget);
          final add = find.descendant(
            of: emptyPanel,
            matching: _key('checklist-add'),
          );
          expect(tester.widget<TextButton>(add).focusNode!.hasFocus, true);
          expect({
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          }, before);
          await _tap(tester, add);
          await tester.enterText(
            _key('checklist-item-title'),
            'Fresh first item',
          );
          await tester.enterText(
            _key('checklist-item-notes'),
            'Independent notes',
          );
          await _tap(tester, _key('checklist-item-save'));
          await _until(
            tester,
            () => _key('checklist-item-title').evaluate().isEmpty,
          );
          await peer.refresh();
          expect(
            peer.checklistItems(empty).single['title'],
            'Fresh first item',
          );
          expect(peer.currentTextRow(empty)!['title'], 'Empty parent');
          expect(find.byType(TaskEditor), findsNothing);
          // The parent editor no longer owns an independently saved checklist.
          await _tap(tester, _key('task-body-$parent'));
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(TaskEditor),
              matching: find.byType(ChecklistPanel),
            ),
            findsNothing,
          );
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
          await _tap(tester, _key('checklist-delete-$water'));
          expect(find.text('Delete checklist item?'), findsOneWidget);
          final cancelItem = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
              .onPressed!;
          cancelItem();
          cancelItem();
          await tester.pumpAndSettle();
          expect(find.byType(TasksPage), findsOneWidget);
          await peer.refresh();
          expect(peer.checklistItems(parent), hasLength(2));
          await _tap(tester, _key('checklist-delete-$water'));
          final deleteItem = tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
              .onPressed!;
          deleteItem();
          deleteItem();
          await _until(
            tester,
            () => _key('checklist-check-$water').evaluate().isEmpty,
          );
          expect(find.byType(TasksPage), findsOneWidget);
          await peer.refresh();
          expect(peer.checklistItems(parent), hasLength(1));
          await _tap(tester, _key('undo-task-action'));
          await _until(
            tester,
            () => _key('checklist-check-$water').evaluate().isNotEmpty,
          );
          await peer.refresh();
          expect(peer.checklistItems(parent), hasLength(2));
          final beforeDisplay = {
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          };
          await _tap(tester, _key('checklist-display-toggle'));
          expect(find.text('Collapse shown checklists'), findsNothing);
          expect(find.byType(ChecklistPanel), findsNothing);
          await _tap(tester, _key('checklist-display-toggle'));
          expect(find.text('Expand shown checklists'), findsNothing);
          expect(find.byType(ChecklistPanel), findsNWidgets(2));
          expect({
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          }, beforeDisplay);
          await _tap(tester, _key('task-menu-$empty'));
          await _tap(tester, find.text('Delete task'));
          expect(find.text('Delete task?'), findsOneWidget);
          expect(find.textContaining('Empty parent'), findsWidgets);
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
          await peer.refresh();
          expect(peer.currentTextRow(empty), isNotNull);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 300));
          await peer.close();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
      },
    );
  }
}
