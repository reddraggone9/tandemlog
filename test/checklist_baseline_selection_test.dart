import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> _copy(LocalLogFolder from, LocalLogFolder to) async {
  for (final file in await from.list()) {
    await File(
      '${from.location}/${file.name}',
    ).copy('${to.location}/${file.name}');
  }
}

void main() {
  for (final disposition in [
    'checked',
    'undone and deleted',
    'after baseline only',
  ]) {
    test(
      'shared baseline preserves earliest scalar successor protected by $disposition copied-item history',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'checklist-baseline-selection-',
        );
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        final peerFolder = LocalLogFolder(
          (await Directory('${root.path}/peer').create()).path,
        );
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        TaskStore? a, b;
        try {
          a = await TaskStore.open(
            folder,
            '${root.path}/profile',
            textEngine: engine,
          );
          final user = const Uuid().v4(),
              parent = const Uuid().v4(),
              item = const Uuid().v4();
          await a.command(user, 'user.created', {'name': 'Synthetic'});
          await a.command(parent, 'task.created', {
            'title': 'Earliest scalar successor',
            'description': 'Original scalar notes',
            'assignee': user,
            'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          });
          await a.command(item, 'checklist.itemCreated', {
            'parent': parent,
            'title': 'Native item',
            'description': '',
            'before': null,
            'text': {
              'codec': 'yrs-v1',
              'adapter': 1,
              'seeds': {
                'title': sha256
                    .convert(engine.seedText('Native item').bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('').bytes)
                    .toString(),
              },
            },
          });
          await _copy(folder, peerFolder);
          b = await TaskStore.open(
            peerFolder,
            '${root.path}/peer-profile',
            textEngine: engine,
          );
          final earliest = await a.complete(
            parent,
            completionDay: DateTime(2030, 5, 10),
          );
          expect(earliest.type, 'task.completedWithChecklist');
          expect(earliest.data.containsKey('inheritance'), false);
          final child = const Uuid().v5(parent, 'successor'),
              copy = const Uuid().v5(child, 'checklist:$item');
          final lateOnly = disposition == 'after baseline only';
          if (!lateOnly) {
            final checked = await a.command(copy, 'checklist.itemEdited', {
              'completed': true,
            });
            if (disposition == 'undone and deleted') {
              expect((await a.undoOperations([checked.id])).remaining, isEmpty);
              await a.command(copy, 'checklist.itemDeleted', {});
            }
          }
          await b.command(parent, 'task.edited', {
            'title': 'Later scalar successor',
            'description': 'Different later notes',
          });
          final later = await b.complete(
            parent,
            completionDay: DateTime(2030, 5, 11),
          );
          expect(compareEvents(earliest, later), lessThan(0));
          expect(later.data.containsKey('inheritance'), false);
          await File(
            '${peerFolder.location}/${b.writer}.jsonl',
          ).copy('${folder.location}/${b.writer}.jsonl');
          await a.refresh();
          expect(
            (await a.undoOperations([earliest.id])).retainedSuccessorCount,
            1,
          );
          final retained = a.rows.singleWhere((row) => row['id'] == child);
          final expectedTitle = lateOnly
              ? 'Later scalar successor'
              : 'Earliest scalar successor';
          final expectedNotes = lateOnly
              ? 'Different later notes'
              : 'Original scalar notes';
          expect(retained['title'], expectedTitle);
          expect(retained['description'], expectedNotes);
          final beforeChecklist = jsonEncode(retained['checklist']);
          expect(a.sharedTextInitialized, false);
          await a.initializeSharedText();
          final initialized = a.rows.singleWhere((row) => row['id'] == child);
          expect(
            initialized['title'],
            expectedTitle,
            reason:
                'A shared-text baseline must preserve the already protected scalar seed.',
          );
          expect(initialized['description'], expectedNotes);
          expect(jsonEncode(initialized['checklist']), beforeChecklist);
          if (lateOnly) {
            // Later durable work must not alter the already declared baseline
            // prefix, its native identities, or its digest during cold replay.
            await a.command(copy, 'checklist.itemEdited', {'completed': true});
          }
          final capture = await a.captureTaskText(child);
          expect(capture.fields['title']!.document.read().text, expectedTitle);
          a.releaseTextCapture(capture);
          final expected = jsonEncode(a.rows), canonical = <String, String>{};
          for (final file in await folder.list()) {
            canonical[file.name] = sha256
                .convert(
                  await File('${folder.location}/${file.name}').readAsBytes(),
                )
                .toString();
          }
          await a.close();
          a = null;
          a = await TaskStore.open(
            folder,
            '${root.path}/cold',
            textEngine: engine,
          );
          expect(jsonEncode(a.rows), expected);
          final coldCapture = await a.captureTaskText(child);
          expect(
            coldCapture.fields['title']!.document.read().text,
            expectedTitle,
          );
          a.releaseTextCapture(coldCapture);
          for (final entry in canonical.entries) {
            expect(
              sha256
                  .convert(
                    await File('${folder.location}/${entry.key}').readAsBytes(),
                  )
                  .toString(),
              entry.value,
            );
          }
        } finally {
          await a?.close();
          await b?.close();
          engine.dispose();
          // Retain the synthetic canonical fixture for inspection.
        }
      },
    );
  }
}
