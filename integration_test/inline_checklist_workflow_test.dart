import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
          await peer.refresh();
          expect(peer.checklistItems(parent), hasLength(2));
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
