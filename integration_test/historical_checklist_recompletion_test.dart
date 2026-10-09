import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (
    var attempt = 0;
    attempt < 100 &&
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        find.text('Unfinished checklist items').evaluate().isEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 300));
  if (find.text('Unfinished checklist items').evaluate().isEmpty) {
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // A row control aligned at the viewport top can sit behind its sticky heading.
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await _settle(tester);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerHistoricalChecklistRecompletionTests();
}

void registerHistoricalChecklistRecompletionTests() {
  testWidgets(
    'native historical checklist recompletion and Undo keep child text',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'historical-checklist-ui-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final offlineFolder = await Directory('${root.path}/offline').create();
      final profile = await Directory('${root.path}/profile').create();
      final peer = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4();
      const parent = '84b20089-b9e9-4a2d-8d91-c205631e7c09';
      const child = 'a119a352-62a0-5475-ad33-0f4cd75d636a';
      const item = '8dede838-27a9-4ead-8088-5f532a9956f0';
      const copiedItem = '57fed6a9-c36b-58e1-b122-bc7a6b356331';
      try {
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        await peer.createNativeFixtureTask(parent, {
          'title': 'Pack for a walk',
          'description': '',
          'assignee': user,
          'schedule': {
            'dueDate': '2026-10-01',
            'recurrence': 'every week when done',
          },
        });
        await peer.addChecklistItem(parent, 'Native item Saved', id: item);
        for (var index = 0; index < 4; index++) {
          await peer.addChecklistItem(parent, 'Other unchecked item $index');
        }
        await for (final file in folder.list()) {
          if (file is File) {
            await file.copy(
              '${offlineFolder.path}/${file.uri.pathSegments.last}',
            );
          }
        }
        final offline = await openNativeFixtureStore(
          LocalLogFolder(offlineFolder.path),
          '${root.path}/offline-profile',
        );
        addTearDown(offline.close);
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (changed) => ViewTimeSource(
              onChanged: changed,
              loadZone: () async => 'UTC',
              now: () => DateTime.utc(2026, 10, 8, 12),
            ),
          ),
        );
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('task-row-$parent'))
              .evaluate()
              .isNotEmpty,
        );
        // Establish the actual GTK window geometry before the evidence frames.
        await captureNativeFixtureUi(tester, 'historical-checklist-ready');
        Finder checkbox(String id) => find.descendant(
          of: find.byKey(ValueKey('task-drop-$id')),
          matching: find.byType(Checkbox),
        );
        Future<void> expandChecklist(String id) async {
          final disclosure = find.byKey(ValueKey('checklist-disclosure-$id'));
          await flows.waitForUi(tester, () => disclosure.evaluate().isNotEmpty);
          if (find.byKey(ValueKey('inline-checklist-$id')).evaluate().isEmpty) {
            await _tap(tester, disclosure);
          }
          expect(find.byKey(ValueKey('inline-checklist-$id')), findsOneWidget);
        }

        Future<void> completeParent() async {
          await _tap(tester, checkbox(parent));
          expect(find.text('Unfinished checklist items'), findsOneWidget);
          await _tap(tester, find.text('Complete anyway'));
          await flows.waitForUi(
            tester,
            () => checkbox(child).evaluate().isNotEmpty,
          );
          await peer.refresh();
        }

        await completeParent();
        await flows.selectTask(tester, child, control: false);
        await flows.waitForUi(
          tester,
          () => find.byKey(const ValueKey('title')).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Pack for a walk ChildA',
        );
        await _tap(tester, find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () => find.byType(TaskEditor).evaluate().isEmpty,
        );
        // Parent task editing is only needed for the successor's title Save.
        // Its independently saved children now live under the list row.
        await expandChecklist(child);
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('checklist-edit-$copiedItem'))
              .evaluate()
              .isNotEmpty,
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('checklist-edit-$copiedItem')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('checklist-item-title')),
          'Native item Saved ChildItemA',
        );
        await _tap(tester, find.byKey(const ValueKey('checklist-item-save')));
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('checklist-item-title'))
              .evaluate()
              .isEmpty,
        );
        expect(find.byType(TaskEditor), findsNothing);
        await peer.refresh();
        expect(peer.currentTextRow(child)!['title'], 'Pack for a walk ChildA');
        expect(
          peer
              .checklistItems(child)
              .singleWhere((row) => row['id'] == copiedItem)['title'],
          'Native item Saved ChildItemA',
        );
        final before = jsonEncode(peer.currentTextRow(child));

        await offline.complete(parent, completionDay: DateTime(2026, 10, 8));
        await File(
          '${offlineFolder.path}/${offline.writer}.jsonl',
        ).copy('${folder.path}/${offline.writer}.jsonl');
        await peer.refresh();
        expect(jsonEncode(peer.currentTextRow(child)), before);
        await flows.filterChoice(tester, 'Completed');
        await expandChecklist(parent);
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('checklist-edit-$item'))
              .evaluate()
              .isNotEmpty,
        );
        await _tap(tester, find.byKey(const ValueKey('checklist-edit-$item')));
        await tester.enterText(
          find.byKey(const ValueKey('checklist-item-title')),
          'Native item Saved ParentLater',
        );
        await _tap(tester, find.byKey(const ValueKey('checklist-item-save')));
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('checklist-item-title'))
              .evaluate()
              .isEmpty,
        );
        // Editing the historical item never opens or changes its parent draft.
        expect(find.byType(TaskEditor), findsNothing);
        await peer.refresh();
        expect(peer.currentTextRow(parent)!['title'], 'Pack for a walk');
        expect(jsonEncode(peer.currentTextRow(child)), before);
        await _tap(tester, checkbox(parent));
        await peer.refresh();
        expect(peer.currentTextRow(parent)!['completed'], false);
        expect(jsonEncode(peer.currentTextRow(child)), before);
        await flows.filterChoice(tester, 'Open');
        await completeParent();
        expect(find.textContaining('Next occurrence kept'), findsWidgets);
        await expandChecklist(child);
        await flows.waitForUi(
          tester,
          () => find
              .byKey(const ValueKey('checklist-edit-$copiedItem'))
              .evaluate()
              .isNotEmpty,
        );
        await captureNativeFixtureUi(
          tester,
          'historical-checklist-recompleted',
        );
        expect(jsonEncode(peer.currentTextRow(child)), before);
        expect(find.byType(TaskEditor), findsNothing);
        await _tap(tester, find.byKey(const ValueKey('undo-task-action')));
        await peer.refresh();
        expect(peer.currentTextRow(parent)!['completed'], false);
        expect(jsonEncode(peer.currentTextRow(child)), before);
        await expandChecklist(child);
        await flows.waitForUi(
          tester,
          () => find.text('Native item Saved ChildItemA').evaluate().isNotEmpty,
        );
        expect(find.text('Native item Saved ChildItemA'), findsWidgets);
        await captureNativeFixtureUi(tester, 'historical-checklist-after-undo');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await peer.close();
      }
    },
  );
}
