import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

Finder _key(String value) => find.byKey(ValueKey(value));
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // Consent holds command admission without showing background work. Settle the
  // modal's entrance separately from progress while an actual write is running.
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
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _expandChecklist(WidgetTester tester, String parent) async {
  expect(_key('checklist-disclosure-$parent'), findsOneWidget);
  if (_key('inline-checklist-$parent').evaluate().isEmpty) {
    await _tap(tester, _key('checklist-disclosure-$parent'));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerChecklistWorkflowTests();
}

void registerChecklistWorkflowTests() {
  for (final narrow in [false, true]) {
    testWidgets(
      'native checklist ${narrow ? 'narrow enlarged light' : 'desktop dark'} repeated editors and refreshed completion warning',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('checklist-ui-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final peer = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/peer',
        );
        final user = const Uuid().v4(), parent = const Uuid().v4();
        final child = const Uuid().v5(parent, 'successor');
        try {
          await peer.command(user, 'user.created', {'name': 'Alex Example'});
          await peer.createNativeFixtureTask(parent, {
            'title': 'Pack for a walk',
            'description': 'Keep the route notes here.',
            'assignee': user,
            'schedule': {
              'dueDate': '2026-10-01',
              'recurrence': 'every week when done',
            },
          });
          final first = await peer.addChecklistItem(parent, 'Water bottle');
          await peer.addChecklistItem(parent, 'Map', notes: 'Printed route');
          await File('${profile.path}/settings.json').writeAsString(
            jsonEncode({
              'folder': folder.path,
              'user': user,
              'appearance': narrow ? 'light' : 'dark',
            }),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = narrow
              ? const Size(390, 820)
              : const Size(1200, 850);
          if (narrow) tester.platformDispatcher.textScaleFactorTestValue = 2;
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              timeSourceFactory: (changed) => ViewTimeSource(
                onChanged: changed,
                loadZone: () async => 'UTC',
                now: () => DateTime.utc(2026, 10, 2, 12),
              ),
            ),
          );
          await flows.waitForUi(
            tester,
            () => _key('task-row-$parent').evaluate().isNotEmpty,
          );
          expect(_key('inline-checklist-$parent'), findsNothing);
          await _expandChecklist(tester, parent);
          await flows.selectTask(tester, parent, control: false);
          expect(_key('checklist-add'), findsOneWidget);
          await tester.enterText(_key('title'), 'Pack for a walk locally');
          if (narrow) {
            // The parent modal owns narrow-screen input until its dirty draft
            // is resolved. Cancel must retain it; Discard makes the inline
            // children reachable without publishing parent text.
            await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
            expect(find.text('Unsaved changes'), findsOneWidget);
            await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
            expect(
              tester.widget<TextField>(_key('title')).controller!.text,
              'Pack for a walk locally',
            );
            await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
            await _tap(tester, find.text('Discard'));
            expect(_key('title'), findsNothing);
            await peer.refresh();
            expect(peer.currentTextRow(parent)!['title'], 'Pack for a walk');
          }
          await _tap(tester, _key('checklist-add'));
          await tester.enterText(_key('checklist-item-title'), 'Snacks');
          await tester.enterText(
            _key('checklist-item-notes'),
            'Trail mix\nNo peanuts',
          );
          await captureNativeFixtureUi(
            tester,
            'checklist-${narrow ? 'narrow-light-200' : 'desktop-dark'}-item-draft',
          );
          await _tap(tester, _key('checklist-item-save'));
          await flows.waitForUi(
            tester,
            () => _key('checklist-item-title').evaluate().isEmpty,
          );
          if (narrow) {
            expect(_key('title'), findsNothing);
          } else {
            expect(
              tester.widget<TextField>(_key('title')).controller!.text,
              'Pack for a walk locally',
            );
          }
          await peer.refresh();
          expect(peer.checklistItems(parent), hasLength(3));
          final snack = peer
              .checklistItems(parent)
              .singleWhere((item) => item['title'] == 'Snacks');
          expect(snack['description'], 'Trail mix\nNo peanuts');
          expect(peer.currentTextRow(parent)!['title'], 'Pack for a walk');
          for (var repeat = 0; repeat < 2; repeat++) {
            await _tap(tester, _key('checklist-edit-${snack['id']}'));
            await tester.enterText(
              _key('checklist-item-title'),
              'Private snack',
            );
            await _tap(tester, _key('checklist-item-cancel'));
            expect(find.text('Unsaved changes'), findsOneWidget);
            await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
            expect(
              tester
                  .widget<TextField>(_key('checklist-item-title'))
                  .controller!
                  .text,
              'Private snack',
            );
            await _tap(tester, _key('checklist-item-cancel'));
            await _tap(tester, find.text('Discard'));
            await peer.refresh();
            expect(peer.checklistItems(parent).last['title'], 'Snacks');
          }
          await _tap(tester, _key('checklist-check-${first.entity}'));
          await peer.refresh();
          expect(peer.checklistItems(parent).first['completed'], true);
          if (narrow) {
            // Reopen after independently saving child work and check the other
            // direction of isolation: discarding a new parent draft retains it.
            await flows.selectTask(tester, parent, control: false);
            await tester.enterText(_key('title'), 'Pack for a walk locally');
          }
          await captureNativeFixtureUi(
            tester,
            'checklist-${narrow ? 'narrow-light-200' : 'desktop-dark'}-parent-draft',
          );
          // Canceling the parent draft keeps separately acknowledged item work.
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
          await _tap(tester, find.text('Discard'));
          await peer.refresh();
          expect(peer.currentTextRow(parent)!['title'], 'Pack for a walk');
          expect(peer.checklistItems(parent), hasLength(3));
          expect(peer.checklistItems(parent).first['completed'], true);
          expect(peer.checklistItems(parent).last['title'], 'Snacks');
          expect(
            peer.checklistItems(parent).last['description'],
            'Trail mix\nNo peanuts',
          );
          Finder checkbox() => find.descendant(
            // The drop subtree contains only the parent tile; children now
            // intentionally live below it and have their own checkboxes.
            of: _key('task-drop-$parent'),
            matching: find.byType(Checkbox),
          );
          final before = {
            await for (final file in folder.list())
              if (file is File)
                file.path: base64Encode(await file.readAsBytes()),
          };
          await _tap(tester, checkbox());
          expect(find.text('Unfinished checklist items'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await _tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
          expect({
            await for (final file in folder.list())
              if (file is File)
                file.path: base64Encode(await file.readAsBytes()),
          }, before);
          // Space uses the same native checkbox/application warning path.
          Focus.of(
            tester.element(
              find
                  .descendant(
                    of: checkbox(),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            ),
          ).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await _settle(tester);
          expect(find.text('Unfinished checklist items'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await peer.addChecklistItem(parent, 'Incoming raincoat');
          await _tap(tester, find.text('Complete anyway'));
          expect(find.text('Unfinished checklist items'), findsOneWidget);
          await peer.refresh();
          expect(peer.currentTextRow(parent)!['completed'], false);
          await captureNativeFixtureUi(
            tester,
            'checklist-${narrow ? 'narrow-light-200' : 'desktop-dark'}-warning',
            waitingForConsent: true,
          );
          await _tap(tester, find.text('Complete anyway'));
          await flows.waitForUi(
            tester,
            () => _key('task-row-$child').evaluate().isNotEmpty,
          );
          await peer.refresh();
          expect(peer.checklistItems(child), hasLength(4));
          expect(
            peer
                .checklistItems(child)
                .every((item) => item['completed'] == false),
            true,
          );
          expect(_key('inline-checklist-$child'), findsNothing);
          await _expandChecklist(tester, child);
          for (final item in peer.checklistItems(child)) {
            expect(
              tester
                  .widget<Checkbox>(_key('checklist-check-${item['id']}'))
                  .value,
              false,
            );
          }
          await captureNativeFixtureUi(
            tester,
            'checklist-${narrow ? 'narrow-light-200' : 'desktop-dark'}-fresh-successor',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await peer.close();
          // Preserve this fresh synthetic fixture and actual screenshots.
        }
      },
    );
  }
}
