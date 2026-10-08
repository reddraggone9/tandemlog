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
          await _tap(tester, _key('checklist-display-menu'));
          await _tap(tester, find.text('Collapse shown checklists'));
          expect(find.byType(ChecklistPanel), findsNothing);
          await _tap(tester, _key('checklist-display-menu'));
          await _tap(tester, find.text('Expand shown checklists'));
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
