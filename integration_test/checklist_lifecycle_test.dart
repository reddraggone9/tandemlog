import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

class _LateAcknowledgementFolder implements LogFolder, BoundedLogFolder {
  _LateAcknowledgementFolder(this.inner);
  final LocalLogFolder inner;
  bool loseNextAcknowledgement = false;
  int appends = 0;
  void Function()? beforeNextAppend;
  Completer<void>? appendStarted, releaseAppend;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final entry in await inner.list()) LogFileInfo(entry.name, ''),
  ];
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    final callback = beforeNextAppend;
    beforeNextAppend = null;
    callback?.call();
    if (releaseAppend != null) {
      appendStarted!.complete();
      await releaseAppend!.future;
    }
    await inner.append(name, bytes);
    if (loseNextAcknowledgement) {
      loseNextAcknowledgement = false;
      throw StateError('Synthetic acknowledgement lost after durable append.');
    }
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _expandChecklist(WidgetTester tester, String parent) async {
  final disclosure = _key('checklist-disclosure-$parent');
  if (disclosure.evaluate().isEmpty) {
    // An empty parent exposes Add checklist in its task menu, which creates
    // only local disclosure state before the first independent item Save.
    await _tap(tester, _key('task-menu-$parent'));
    await _tap(tester, find.text('Add checklist'));
  } else if (_key('inline-checklist-$parent').evaluate().isEmpty) {
    await _tap(tester, disclosure);
  }
  expect(_key('inline-checklist-$parent'), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerChecklistLifecycleTests();
}

void registerChecklistLifecycleTests() {
  for (final lostAcknowledgement in [false, true]) {
    testWidgets(
      'application disposal during item Save ${lostAcknowledgement ? 'unknown' : 'confirmed'} preserves durable intent',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'checklist-save-exit-',
        );
        final shared = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final inner = LocalLogFolder(shared.path);
        final folder = _LateAcknowledgementFolder(inner);
        final peer = await openNativeFixtureStore(inner, '${root.path}/peer');
        final user = const Uuid().v4(), parent = const Uuid().v4();
        try {
          await peer.command(user, 'user.created', {'name': 'Alex Example'});
          await peer.createNativeFixtureTask(parent, {
            'title': 'Synthetic disposal task',
            'description': '',
            'assignee': user,
          });
          final item = await peer.addChecklistItem(parent, 'Original');
          await File(
            '${profile.path}/settings.json',
          ).writeAsString(jsonEncode({'folder': shared.path, 'user': user}));
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              folderFactory: (_) => folder,
            ),
          );
          await flows.waitForUi(
            tester,
            () => _key('task-row-$parent').evaluate().isNotEmpty,
          );
          await _expandChecklist(tester, parent);
          await _tap(tester, _key('checklist-edit-${item.entity}'));
          final session = tester
              .widget<ChecklistItemEditor>(find.byType(ChecklistItemEditor))
              .textSession!;
          final document = session.capture.fields['title']!.document;
          await tester.enterText(_key('checklist-item-title'), 'Saved at exit');
          folder.appendStarted = Completer<void>();
          folder.releaseAppend = Completer<void>();
          folder.loseNextAcknowledgement = lostAcknowledgement;
          await tester.tap(_key('checklist-item-save'));
          for (
            var attempt = 0;
            attempt < 100 && !folder.appendStarted!.isCompleted;
            attempt++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(folder.appendStarted!.isCompleted, true);
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          final done = state.checklistEditorDone as Completer<void>;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            done.isCompleted,
            false,
            reason: 'In-flight append still owns the captured native document.',
          );
          expect(session.hasPendingReceipt, true);
          expect(() => document.read(), returnsNormally);
          folder.releaseAppend!.complete();
          for (var attempt = 0; attempt < 100 && !done.isCompleted; attempt++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            done.isCompleted,
            true,
            reason: 'Save and native route teardown must finish on exit.',
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(() => document.read(), throwsStateError);
          await peer.refresh();
          expect(peer.checklistItems(parent).single['title'], 'Saved at exit');
          // Restart the exact former application profile, recovering its original
          // outbox intent rather than creating a second edit after lost ack.
          folder.releaseAppend = null;
          await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
          await flows.waitForUi(
            tester,
            () => _key('task-row-$parent').evaluate().isNotEmpty,
          );
          await _expandChecklist(tester, parent);
          expect(find.text('Saved at exit'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          if (folder.releaseAppend?.isCompleted == false) {
            folder.releaseAppend!.complete();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await peer.close();
        }
      },
    );
  }
  testWidgets('application disposal finishes item route ownership teardown', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('checklist-disposal-');
    final shared = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final peer = await openNativeFixtureStore(
      LocalLogFolder(shared.path),
      '${root.path}/peer',
    );
    final user = const Uuid().v4(), parent = const Uuid().v4();
    try {
      await peer.command(user, 'user.created', {'name': 'Alex Example'});
      await peer.createNativeFixtureTask(parent, {
        'title': 'Synthetic disposal task',
        'description': '',
        'assignee': user,
      });
      final item = await peer.addChecklistItem(parent, 'Original');
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': shared.path, 'user': user}));
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      await flows.waitForUi(
        tester,
        () => _key('task-row-$parent').evaluate().isNotEmpty,
      );
      await _expandChecklist(tester, parent);
      await _tap(tester, _key('checklist-edit-${item.entity}'));
      await tester.enterText(_key('checklist-item-title'), 'Private draft');
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      final done = state.checklistEditorDone as Completer<void>;
      final document = tester
          .widget<ChecklistItemEditor>(find.byType(ChecklistItemEditor))
          .textSession!
          .capture
          .fields['title']!
          .document;
      await tester.pumpWidget(const SizedBox.shrink());
      for (var attempt = 0; attempt < 50 && !done.isCompleted; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        done.isCompleted,
        true,
        reason: 'Disposed item routes must release the host native ownership.',
      );
      expect(() => document.read(), throwsStateError);
      await peer.refresh();
      expect(peer.checklistItems(parent).single['title'], 'Original');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await peer.close();
    }
  });
  for (final scenario in ['unknown', 'undo', 'switch', 'switch-save']) {
    final unknownAppend = scenario == 'unknown';
    testWidgets(
      unknownAppend
          ? 'new item late acknowledgement remains frozen until exact Retry Save'
          : scenario.startsWith('switch')
          ? scenario == 'switch-save'
                ? 'user switch saves private item before changing identity'
                : 'user switch waits only for item Save and route teardown'
          : 'task Undo waits for item route and native lease teardown once',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'checklist-lifecycle-',
        );
        final inner = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        final folder = _LateAcknowledgementFolder(inner);
        final profile = await Directory('${root.path}/profile').create();
        final peer = await openNativeFixtureStore(inner, '${root.path}/peer');
        final user = const Uuid().v4(), parent = const Uuid().v4();
        try {
          await peer.command(user, 'user.created', {'name': 'Synthetic'});
          final otherUser = const Uuid().v4();
          if (scenario.startsWith('switch')) {
            await peer.command(otherUser, 'user.created', {'name': 'Another'});
          }
          await peer.createNativeFixtureTask(parent, {
            'title': 'Checklist lifecycle',
            'description': '',
            'assignee': user,
          });
          final original = unknownAppend
              ? null
              : await peer.addChecklistItem(parent, 'Original');
          await File('${profile.path}/settings.json').writeAsString(
            jsonEncode({
              'folder': inner.location,
              'user': user,
              'appearance': 'dark',
            }),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 850);
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              folderFactory: (_) => folder,
            ),
          );
          await flows.waitForUi(
            tester,
            () => _key('task-row-$parent').evaluate().isNotEmpty,
          );
          await _expandChecklist(tester, parent);
          if (unknownAppend) {
            await _tap(tester, _key('checklist-add'));
            await tester.enterText(
              _key('checklist-item-title'),
              'Exactly once',
            );
            await tester.enterText(
              _key('checklist-item-notes'),
              'Prepared notes',
            );
            folder.loseNextAcknowledgement = true;
            await _tap(tester, _key('checklist-item-save'));
            await flows.waitForUi(
              tester,
              () => find
                  .textContaining('Synthetic acknowledgement lost')
                  .evaluate()
                  .isNotEmpty,
            );
            await flows.waitForUi(
              tester,
              () => find.text('0/1').evaluate().isNotEmpty,
            );
            await peer.refresh();
            expect(peer.checklistItems(parent).single['title'], 'Exactly once');
            final before = {
              for (final entry in await inner.list())
                entry.name: base64Encode(await inner.read(entry.name)),
            };
            final calls = folder.appends;
            // Genuine geometry change rebuilds the editor after background ack.
            tester.view.physicalSize = const Size(1180, 850);
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(_key('checklist-item-title')).enabled,
              false,
            );
            expect(
              tester
                  .widget<TextButton>(_key('checklist-item-cancel'))
                  .onPressed,
              isNull,
            );
            expect(find.text('Retry Save'), findsOneWidget);
            await _tap(tester, _key('checklist-item-save'));
            await flows.waitForUi(
              tester,
              () => find.byType(ChecklistItemEditor).evaluate().isEmpty,
            );
            expect(folder.appends, calls);
            expect({
              for (final entry in await inner.list())
                entry.name: base64Encode(await inner.read(entry.name)),
            }, before);
          } else {
            if (scenario == 'undo') {
              await _tap(tester, _key('checklist-check-${original!.entity}'));
            }
            await _tap(tester, _key('checklist-edit-${original!.entity}'));
            final editor = tester.widget<ChecklistItemEditor>(
              find.byType(ChecklistItemEditor),
            );
            final document =
                editor.textSession!.capture.fields['title']!.document;
            await tester.enterText(
              _key('checklist-item-title'),
              'Private draft',
            );
            if (scenario.startsWith('switch')) {
              // A host navigation request can overlap the modal's closing
              // transition. Invoke its actual user-menu callback and verify
              // that its own _act is never awaited by the item teardown.
              tester
                  .widget<PopupMenuButton<String>>(_key('identity-menu'))
                  .onSelected!(otherUser);
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.text('Unsaved changes'), findsOneWidget);
              await tester.tap(
                find.text(scenario == 'switch-save' ? 'Save' : 'Discard'),
              );
              await flows.waitForUi(
                tester,
                () => find
                    .byTooltip('Active user: Another')
                    .evaluate()
                    .isNotEmpty,
              );
              expect(find.byType(ChecklistItemEditor), findsNothing);
              expect(() => document.read(), throwsStateError);
              await peer.refresh();
              expect(
                peer.checklistItems(parent).single['title'],
                scenario == 'switch-save' ? 'Private draft' : 'Original',
              );
              expect(tester.takeException(), isNull);
              return;
            }
            var leaseClosedAtUndo = false;
            folder.beforeNextAppend = () {
              try {
                document.read();
              } on StateError {
                leaseClosedAtUndo = true;
              }
            };
            // Invoke the same host action twice, representing overlapping native
            // shortcut/navigation requests while one dirty-close prompt is open.
            final undo = tester
                .widget<IconButton>(_key('undo-task-action'))
                .onPressed!;
            undo();
            undo();
            await tester.pumpAndSettle();
            expect(find.text('Unsaved changes'), findsOneWidget);
            await _tap(tester, find.text('Discard'));
            await flows.waitForUi(
              tester,
              () => find
                  .textContaining('Undid checking 1 checklist item')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(
              leaseClosedAtUndo,
              true,
              reason:
                  'The route and native item lease must close before Undo appends.',
            );
            await peer.refresh();
            expect(peer.checklistItems(parent).single['completed'], false);
            expect(peer.checklistItems(parent).single['title'], 'Original');
            expect(find.byType(TasksPage), findsOneWidget);
            expect(find.byType(ChecklistItemEditor), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await peer.close();
          // Retain fresh fixtures and immutable receipts for review.
        }
      },
    );
  }
}
