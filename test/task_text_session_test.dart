import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  final path = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  test(
    'private UTF16 edits survive remote arrival; composition blocks preparation; cancel retains live owner',
    () {
      final engine = NativeTextEngine(libraryPath: path);
      addTearDown(engine.dispose);
      final live = engine.createDocument(
        actorClientId: 100,
        limits: const NativeTextLimits(visibleUtf16: 500),
        seed: engine.seedText('A😀B'),
      );
      final session = TaskTextSession(
        TaskTextCapture('task', {
          'title': TaskTextFieldCapture(
            field: 'title',
            context: 'a' * 64,
            allocation: 'lease',
            actor: 102,
            undoActor: 100,
            undoAllocation: 'undo-lease',
            document: live,
          ),
        }, writer: '00000000-0000-4000-8000-000000000001'),
      );
      session.replace('title', 'A😀localB', composing: true);
      expect(() => session.prepare(), throwsStateError);
      final remote = live.captureDraft(actorClientId: 101);
      remote.replaceText('remoteA😀B');
      final packet = remote.prepareSave();
      packet.commit(receiptUpdate: packet.update);
      expect(session.text('title'), 'A😀localB');
      session.replace('title', 'A😀localB', composing: false);
      final prepared = session.prepare();
      expect(prepared.changes['title']!['actor'], 102);
      expect(() => session.replace('title', 'other'), throwsStateError);
      expect(identical(session.prepare(), prepared), isTrue);
      session.cancel();
      session.cancel();
      expect(live.isClosed, isFalse);
      expect(live.read().text, 'remoteA😀B');
      const id = '00000000-0000-4000-8000-000000000001';
      final savedSession = TaskTextSession(
        TaskTextCapture(id, {
          'title': TaskTextFieldCapture(
            field: 'title',
            context: 'a' * 64,
            allocation: id,
            actor: 103,
            undoActor: 100,
            undoAllocation: id,
            document: live,
          ),
        }, writer: '00000000-0000-4000-8000-000000000001'),
      );
      savedSession.replace('title', 'Saved😀');
      final saved = savedSession.prepare();
      final event = LogEvent(
        id,
        id,
        1,
        EventClock(BigInt.one),
        id,
        'task.textEdited',
        {'changes': saved.changes},
      );
      final receipt = OperationReceipt(event.id, event.encode(), id);
      final beforeReceipt = live.fullState.encoded;
      expect(saved.preCommitCheckpoints['title']!.state.encoded, beforeReceipt);
      expect(() => saved.preCommitCheckpoints.clear(), throwsUnsupportedError);
      expect(
        () => saved.bindReceipt(
          OperationReceipt(event.id, event.encode(), 'wrong'),
        ),
        throwsStateError,
      );
      expect(live.fullState.encoded, beforeReceipt);
      saved.bindReceipt(receipt);
      expect(() => savedSession.cancel(), throwsStateError);
      expect(identical(savedSession.prepare(), saved), isTrue);
      saved.commitReceipt(receipt);
      saved.commitReceipt(receipt);
      expect(live.read().text, 'Saved😀');
      expect(savedSession.frozen, isFalse);
      savedSession.replace('title', 'cancelled😀');
      final cancelledState = live.fullState.encoded;
      savedSession.restart();
      expect(live.fullState.encoded, cancelledState);
      expect(savedSession.text('title'), 'Saved😀');
      savedSession.replace('title', 'Saved😀 twice');
      final lateRemote = live.captureDraft(actorClientId: 104)
        ..replaceText('Remote Saved😀');
      final latePacket = lateRemote.prepareSave();
      latePacket.commit(receiptUpdate: latePacket.update);
      expect(savedSession.text('title'), 'Saved😀 twice');
      final second = savedSession.prepare();
      expect(
        second.changes['title']!['allocation'],
        isNot(saved.changes['title']!['allocation']),
      );
      expect(
        second.changes['title']!['actor'],
        isNot(saved.changes['title']!['actor']),
      );
      final secondEvent = LogEvent(
        id,
        id,
        2,
        EventClock(BigInt.two),
        id,
        'task.textEdited',
        {'changes': second.changes},
        previousHash: event.toJson()['hash'] as String,
      );
      second.commitReceipt(
        OperationReceipt(secondEvent.id, secondEvent.encode(), id),
      );
      expect(live.read().text, 'Remote Saved😀 twice');
      expect(savedSession.text('title'), 'Remote Saved😀 twice');
      savedSession.cancel();
      expect(live.isClosed, isFalse);
      final undo = savedSession.prepareUndo('title');
      expect(undo.change['actor'], 100);
      expect(undo.change['allocation'], id);
      undo.packet.commit(receiptUpdate: undo.packet.update);
      expect(live.read().text, contains('Remote '));
      expect(live.read().text, isNot('Remote Saved😀 twice'));
    },
    skip: path == null
        ? 'Actual production native library must be supplied explicitly.'
        : false,
  );
  testWidgets(
    'confirmed Save keeps an open editor editable with a fresh lease',
    (tester) async {
      final engine = NativeTextEngine(libraryPath: path);
      addTearDown(engine.dispose);
      const id = '00000000-0000-4000-8000-000000000001';
      final fields = <String, TaskTextFieldCapture>{};
      for (final field in ['title', 'description']) {
        final actor = field == 'title' ? 201 : 203;
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
            seed: engine.seedText(field == 'title' ? 'Original' : ''),
          ),
        );
      }
      final session = TaskTextSession(TaskTextCapture(id, fields, writer: id));
      addTearDown(session.cancel);
      final key = GlobalKey<TaskEditorState>();
      final claims = <Object?>[];
      final changedFields = <Set<String>>[];
      var sequence = 0;
      var failNext = false;
      String? previous;
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              key: key,
              panel: true,
              task: {
                'id': id,
                'title': 'Original',
                'description': '',
                'tags': [],
                'schedule': {},
              },
              textSession: session,
              onClose: () {},
              save: (nonText, _, _) async {
                if (nonText.containsKey('title')) {
                  throw StateError('Scalar text leaked.');
                }
                final prepared = session.prepare();
                if (session.hasPendingReceipt) {
                  prepared.commitReceipt(prepared.receipt!);
                  return;
                }
                claims.add(prepared.changes['title']?['actor']);
                changedFields.add(prepared.changedFields);
                final event = LogEvent(
                  id,
                  id,
                  ++sequence,
                  EventClock(BigInt.from(sequence)),
                  id,
                  'task.textEdited',
                  {'changes': prepared.changes},
                  previousHash: previous,
                );
                final receipt = OperationReceipt(event.id, event.encode(), id);
                previous = event.toJson()['hash'] as String;
                prepared.bindReceipt(receipt);
                if (failNext) {
                  failNext = false;
                  throw StateError('Append outcome unknown.');
                }
                prepared.commitReceipt(receipt);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in ['First', 'Second😀']) {
        await tester.enterText(find.byKey(const ValueKey('title')), title);
        final closing = key.currentState!.canClose();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          await closing,
          isTrue,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '),
        );
        expect(
          tester.widget<TextField>(find.byKey(const ValueKey('title'))).enabled,
          isTrue,
        );
        expect(await key.currentState!.canClose(), isTrue);
        expect(fields['title']!.document.read().text, title);
      }
      expect(claims[0], isNot(claims[1]));
      expect(session.hasTextChanges, isFalse);
      expect(session.frozen, isFalse);
      expect(sequence, 2);
      await tester.enterText(
        find.byKey(const ValueKey('description')),
        'Notes only',
      );
      failNext = true;
      final notesClosing = key.currentState!.canClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await notesClosing, isFalse);
      expect(session.hasPendingReceipt, isTrue);
      expect(await key.currentState!.canClose(), isFalse);
      for (final field in [
        'title',
        'description',
        'tags',
        'dueDate',
        'dueTime',
      ]) {
        expect(
          tester.widget<TextField>(find.byKey(ValueKey(field))).enabled,
          isFalse,
        );
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Retry Save'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Retry Save'));
      await tester.tap(find.text('Retry Save'));
      await tester.pumpAndSettle();
      expect(session.hasPendingReceipt, isFalse);
      expect(changedFields.last, {'description'});
      final notesUndo = session.prepareUndo('description');
      notesUndo.packet.commit(receiptUpdate: notesUndo.packet.update);
      expect(fields['title']!.document.read().text, 'Second😀');
      expect(fields['description']!.document.read().text, '');
      session.replace('title', 'Second😀 transient');
      session.replace('title', 'Second😀');
      expect(session.prepare().changedFields, {'title'});
    },
    skip: path == null,
  );
  test('later-field preparation failure retains earlier packet for retry', () {
    final engine = NativeTextEngine(libraryPath: path);
    addTearDown(engine.dispose);
    const id = '00000000-0000-4000-8000-000000000001';
    final fields = <String, TaskTextFieldCapture>{};
    for (final field in ['title', 'description']) {
      final actor = field == 'title' ? 301 : 303;
      final live = engine.createDocument(
        actorClientId: actor,
        limits: const NativeTextLimits(visibleUtf16: 500),
        seed: engine.seedText('Base'),
      );
      final initial = live.captureDraft(actorClientId: actor + 10)
        ..replaceText('Previous');
      final initialPacket = initial.prepareSave();
      initialPacket.commit(receiptUpdate: initialPacket.update);
      fields[field] = TaskTextFieldCapture(
        field: field,
        context: (field == 'title' ? 'a' : 'b') * 64,
        allocation: id,
        actor: actor + 1,
        undoActor: actor,
        undoAllocation: id,
        document: live,
      );
    }
    final session = TaskTextSession(TaskTextCapture(id, fields, writer: id));
    addTearDown(session.cancel);
    session.replace('title', 'Title private');
    session.replace('description', 'Notes private');
    expect(session.hasTextChanges, isTrue);
    expect(session.frozen, isFalse);
    final blocked = fields['description']!.document.prepareUndo();
    expect(session.prepare, throwsStateError);
    expect(session.text('title'), 'Title private');
    expect(session.text('description'), 'Notes private');
    expect(session.frozen, isTrue);
    expect(session.hasPendingReceipt, isFalse);
    blocked.cancel();
    final prepared = session.prepare();
    expect(prepared.changedFields, {'title', 'description'});
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
    expect(session.hasPendingReceipt, isTrue);
    prepared.commitReceipt(receipt);
    expect(session.hasPendingReceipt, isFalse);
    expect(fields['title']!.document.read().text, 'Title private');
    expect(fields['description']!.document.read().text, 'Notes private');
  }, skip: path == null);
}
