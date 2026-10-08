import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/checklist_completion_command.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

// Parent-reported Android sequence at exact17ae5e5. The Library packet's
// consumer transfer returned403; reproduce its ordered actions through the
// production commands instead of inventing its canonical bytes/clocks/writers.
const _parent = '84b20089-b9e9-4a2d-8d91-c205631e7c09';
const _child = 'a119a352-62a0-5475-ad33-0f4cd75d636a';
const _parentItem = '8dede838-27a9-4ead-8088-5f532a9956f0';
const _childItem = '57fed6a9-c36b-58e1-b122-bc7a6b356331';

Future<void> _copyCanonical(LocalLogFolder from, LocalLogFolder to) async {
  for (final file in await from.list()) {
    await File(
      '${from.location}/${file.name}',
    ).copy('${to.location}/${file.name}');
  }
}

Future<void> _saveTitle(TaskStore store, String entity, String value) async {
  final capture = await store.captureTaskText(entity);
  final session = TaskTextSession(
    capture,
    registerDraftActor: (name, allocation, actor) =>
        store.registerTextDraftActor(capture, name, allocation, actor),
  );
  try {
    session.replace('title', value);
    final result = await TextSaveCommand(
      store,
      session,
    ).save(fields: {}, tags: [], observedTagRefs: {});
    expect(result.receipt, isNotNull);
    expect(result.undoError, isNull);
    expect(result.sessionError, isNull);
  } finally {
    session.cancel();
    store.releaseTextCapture(capture);
  }
}

Map<String, dynamic> _childRow(TaskStore store) =>
    store.rows.singleWhere((row) => row['id'] == _child);

Map<String, dynamic> _copiedItem(TaskStore store) => store
    .checklistItems(_child)
    .singleWhere((item) => item['id'] == _childItem);

Future<LogEvent> _completeWithConsent(TaskStore store) async {
  var confirmations = 0;
  final event = await ChecklistCompletionCommand(store).complete(
    _parent,
    completionInstant: DateTime.utc(2026, 10, 8, 12),
    localZoneId: 'UTC',
    confirmUnfinished: (items) async {
      confirmations++;
      expect(items, hasLength(5));
      expect(items.every((item) => item['completed'] == false), true);
      return true;
    },
  );
  expect(confirmations, 1);
  expect(event, isNotNull);
  return event!;
}

void main() {
  for (final phase in [
    'recompletion',
    'Undo',
    'recompletion cold replay',
    'Undo cold replay',
  ]) {
    test(
      'native offline checklist successor keeps its edited item after $phase',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'native-checklist-recompletion-',
        );
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        final offline = LocalLogFolder(
          (await Directory('${root.path}/offline').create()).path,
        );
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        TaskStore? a, b, cold;
        try {
          a = await TaskStore.open(
            folder,
            '${root.path}/a',
            textEngine: engine,
          );
          final user = const Uuid().v4();
          const title = 'Pack for a walk';
          await a.command(user, 'user.created', {'name': 'Alex Example'});
          await a.command(_parent, 'task.createdWithText', {
            'title': title,
            'description': '',
            'assignee': user,
            'schedule': {
              'dueDate': '2026-10-01',
              'recurrence': 'every week when done',
            },
            'text': {
              'codec': 'yrs-v1',
              'adapter': 1,
              'seeds': {
                'title': sha256
                    .convert(engine.seedText(title).bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('').bytes)
                    .toString(),
              },
            },
          });
          await a.addChecklistItem(
            _parent,
            'Native item Saved',
            id: _parentItem,
          );
          for (var index = 0; index < 4; index++) {
            await a.addChecklistItem(_parent, 'Other unchecked item $index');
          }
          expect(const Uuid().v5(_parent, 'successor'), _child);
          expect(const Uuid().v5(_child, 'checklist:$_parentItem'), _childItem);

          // B remains offline with only the pre-completion prefix. No suffix
          // trimming, hand-authored records or user profile identities are used.
          await _copyCanonical(folder, offline);
          b = await TaskStore.open(
            offline,
            '${root.path}/b',
            textEngine: engine,
          );
          final first = await _completeWithConsent(a);
          expect(first.type, 'task.completedWithChecklist');
          expect(first.data, contains('inheritance'));
          expect(_copiedItem(a)['title'], 'Native item Saved');
          expect(_childRow(a)['schedule']['dueDate'], '2026-10-15');
          await _saveTitle(a, _child, 'Pack for a walk ChildA');
          await _saveTitle(a, _childItem, 'Native item Saved ChildItemA');

          final concurrent = await _completeWithConsent(b);
          expect(concurrent.data, contains('inheritance'));
          final frontiers = concurrent.data['inheritance']['frontiers'] as Map;
          expect(frontiers[a.writer]['seq'], lessThan(first.sequence));
          final editedChild = jsonEncode(_childRow(a));
          await File(
            '${offline.location}/${b.writer}.jsonl',
          ).copy('${folder.location}/${b.writer}.jsonl');
          await a.refresh();
          expect(jsonEncode(_childRow(a)), editedChild);

          await _saveTitle(a, _parentItem, 'Native item Saved ParentLater');
          expect(_copiedItem(a)['title'], 'Native item Saved ChildItemA');
          await a.reopen(_parent, [first.id, concurrent.id]);
          expect(a.currentTextRow(_parent)!['completed'], false);
          expect(jsonEncode(_childRow(a)), editedChild);

          final before = jsonEncode(_childRow(a));
          final beforeItems = jsonEncode(a.checklistItems(_child));
          final again = await _completeWithConsent(a);
          if (phase.startsWith('Undo')) {
            final undo = await a.undoOperations([again.id]);
            expect(undo.remaining, isEmpty);
            expect(a.currentTextRow(_parent)!['completed'], false);
          }
          var observed = a;
          if (phase.endsWith('cold replay')) {
            // A fresh cache/profile reconstructs intact canonical history.
            // Existing caches, logs and private profiles are not deleted.
            cold = await TaskStore.open(
              folder,
              '${root.path}/cold',
              textEngine: engine,
            );
            observed = cold;
            expect(cold.readFiles, greaterThan(0));
            await cold.verifyHistory();
          }
          // Print the observed native value so each frozen red explains whether
          // recompletion, Undo and reconstruction all retained the same leak.
          // ignore: avoid_print
          print(
            'HISTORICAL_RECOMPLETION $phase: ${_copiedItem(observed)['title']}',
          );
          expect(_childRow(observed)['title'], 'Pack for a walk ChildA');
          expect(
            observed.rows.where(
              (row) => row['id'] == const Uuid().v5(_child, 'successor'),
            ),
            isEmpty,
          );
          expect(
            _copiedItem(observed)['title'],
            'Native item Saved ChildItemA',
          );
          expect(jsonEncode(observed.checklistItems(_child)), beforeItems);
          expect(jsonEncode(_childRow(observed)), before);
        } finally {
          await cold?.close();
          await b?.close();
          await a?.close();
          engine.dispose();
          // Preserve these synthetic reproductions while the native blocker is
          // investigated; no live synced data or original candidate is touched.
        }
      },
    );
  }
}
