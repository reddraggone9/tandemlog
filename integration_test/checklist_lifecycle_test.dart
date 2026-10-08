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

class _LateAcknowledgementFolder implements LogFolder {
  _LateAcknowledgementFolder(this.inner);
  final LocalLogFolder inner;
  bool loseNextAcknowledgement = false;
  int appends = 0;
  void Function()? beforeNextAppend;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final entry in await inner.list()) LogFileInfo(entry.name, ''),
  ];
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerChecklistLifecycleTests();
}

void registerChecklistLifecycleTests() {
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
      await flows.selectTask(tester, parent, control: false);
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
  for (final unknownAppend in [true, false]) {
    testWidgets(
      unknownAppend
          ? 'new item late acknowledgement remains frozen until exact Retry Save'
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
          await flows.selectTask(tester, parent, control: false);
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
            await _tap(tester, _key('checklist-check-${original!.entity}'));
            await _tap(tester, _key('checklist-edit-${original.entity}'));
            final editor = tester.widget<ChecklistItemEditor>(
              find.byType(ChecklistItemEditor),
            );
            final document =
                editor.textSession!.capture.fields['title']!.document;
            await tester.enterText(
              _key('checklist-item-title'),
              'Private draft',
            );
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
