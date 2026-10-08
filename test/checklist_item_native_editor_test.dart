import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:uuid/uuid.dart';

void main() {
  testWidgets(
    'remote deleted parent rejects private native Save without receipt and permits Discard',
    (tester) async {
      late TaskStore store, peer;
      late NativeTextEngine engine;
      late TaskTextSession session;
      late TaskTextCapture capture;
      late LocalLogFolder folder, remote;
      late String parent, item;
      Future<void> copy(LocalLogFolder from, LocalLogFolder to) async {
        for (final file in await from.list()) {
          await File(
            '${from.location}/${file.name}',
          ).copy('${to.location}/${file.name}');
        }
      }

      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'checklist-editor-rejection-',
        );
        folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        remote = LocalLogFolder(
          (await Directory('${root.path}/remote').create()).path,
        );
        engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4();
        parent = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(parent, 'task.created', {
          'title': 'Parent',
          'description': '',
          'assignee': user,
          'schedule': {},
        });
        item = (await store.addChecklistItem(parent, 'Original item')).entity;
        capture = await store.captureTaskText(item);
        session = TaskTextSession(
          capture,
          registerDraftActor: (field, allocation, actor) =>
              store.registerTextDraftActor(capture, field, allocation, actor),
        );
        await copy(folder, remote);
        peer = await TaskStore.open(
          remote,
          '${root.path}/peer-profile',
          textEngine: engine,
        );
      });
      final key = GlobalKey<ChecklistItemEditorState>();
      final closed = <bool>[];
      // Keep the real store's IO in runAsync while forwarding its exact outcome
      // through the host callback already awaited by the widget.
      final saveResult = Completer<void>();
      var saveInvoked = false;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChecklistItemEditor(
                key: key,
                item: {'id': item, 'title': 'Original item', 'description': ''},
                textSession: session,
                save: (_, _) {
                  saveInvoked = true;
                  return saveResult.future;
                },
                onClose: () => closed.add(true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('checklist-item-title')),
          'Private changed item',
        );
        late Map<String, String> before;
        await tester.runAsync(() async {
          await peer.command(parent, 'task.deleted', {});
          await copy(remote, folder);
          await store.refresh();
          before = {
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          };
        });
        await tester.tap(find.byKey(const Key('checklist-item-save')));
        expect(saveInvoked, isTrue);
        await tester.runAsync(() async {
          try {
            await TextSaveCommand(
              store,
              session,
            ).save(fields: {}, tags: [], observedTagRefs: {});
            saveResult.complete();
          } catch (error, stack) {
            saveResult.completeError(error, stack);
          }
        });
        await tester.pumpAndSettle();
        expect(session.frozen, isTrue);
        expect(session.hasPendingReceipt, isFalse);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('checklist-item-title')))
              .enabled,
          isFalse,
        );
        expect(find.text('Retry Save'), findsOneWidget);
        final close = key.currentState!.canClose();
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(await close, isTrue);
        expect(closed, isEmpty);
        await tester.runAsync(() async {
          expect({
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          }, before);
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          session.cancel();
          store.releaseTextCapture(capture);
          await peer.close();
          await store.close();
          engine.dispose();
        });
      }
    },
  );
  testWidgets(
    'native caret-only edits stay clean; composition propagates; committed merged text renews before close',
    (tester) async {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      addTearDown(engine.dispose);
      const id = '00000000-0000-4000-8000-000000000001';
      final fields = <String, TaskTextFieldCapture>{};
      for (final field in ['title', 'description']) {
        final actor = field == 'title' ? 101 : 201;
        fields[field] = TaskTextFieldCapture(
          field: field,
          context: (field == 'title' ? 'a' : 'b') * 64,
          allocation: id,
          actor: actor + 1,
          undoActor: actor,
          undoAllocation: id,
          document: engine.createDocument(
            actorClientId: actor,
            limits: NativeTextLimits(
              visibleUtf16: field == 'title' ? 500 : 10000,
            ),
            seed: engine.seedText(field == 'title' ? 'Base' : 'Notes'),
          ),
        );
      }
      final session = TaskTextSession(TaskTextCapture(id, fields, writer: id));
      addTearDown(session.cancel);
      final key = GlobalKey<ChecklistItemEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistItemEditor(
              key: key,
              item: {'id': id, 'title': 'Base', 'description': 'Notes'},
              textSession: session,
              onClose: () {},
              save: (_, _) async {
                final remote = fields['title']!.document.captureDraft(
                  actorClientId: 103,
                )..replaceText('Remote Base');
                final packet = remote.prepareSave();
                packet.commit(receiptUpdate: packet.update);
                final prepared = session.prepare();
                final event = LogEvent(
                  id,
                  id,
                  1,
                  EventClock(BigInt.one),
                  id,
                  'task.textEdited',
                  {'changes': prepared.changes},
                );
                final receipt = OperationReceipt(event.id, event.encode(), id);
                prepared.bindReceipt(receipt);
                prepared.commitReceipt(receipt);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester
          .widget<TextField>(find.byKey(const Key('checklist-item-title')))
          .controller!;
      title.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      expect(session.hasTextChanges, isFalse);
      expect(await key.currentState!.canClose(), isTrue);
      title.value = const TextEditingValue(
        text: 'Base local',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 5, end: 10),
      );
      await tester.pump();
      expect(session.prepare, throwsStateError);
      title.value = title.value.copyWith(composing: TextRange.empty);
      await tester.pump();
      final close = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        await close,
        isTrue,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(" | "),
      );
      expect(title.text, 'Remote Base local');
      expect(title.text, session.text('title'));
      expect(session.hasTextChanges, isFalse);
      expect(await key.currentState!.canClose(), isTrue);
      expect(fields['title']!.document.isClosed, isFalse);
    },
  );
}
