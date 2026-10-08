import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> _save(TaskStore store, String entity, String title) async {
  final capture = await store.captureTaskText(entity);
  final field = capture.fields['title']!;
  final draft = field.document.captureDraft(actorClientId: field.actor)
    ..replaceText(title);
  final save = draft.prepareSave();
  try {
    await store.editNativeTask(entity, {
      'title': {
        'context': field.context,
        'allocation': field.allocation,
        'actor': field.actor,
        'update': save.update.encoded,
      },
    });
    save.commit(receiptUpdate: save.update);
  } finally {
    store.releaseTextCapture(capture);
  }
}

void main() {
  test(
    'shared recurrence cache stores references and survives warm/cold reconstruction',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'shared-history-storage-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          LocalLogFolder(folder.path),
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4();
        var entity = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(entity, 'task.createdWithText', {
          'title': 'AB',
          'description': 'Notes',
          'assignee': user,
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          'text': {
            'codec': 'yrs-v1',
            'adapter': 1,
            'seeds': {
              'title': sha256.convert(engine.seedText('AB').bytes).toString(),
              'description': sha256
                  .convert(engine.seedText('Notes').bytes)
                  .toString(),
            },
          },
        });
        for (var generation = 0; generation < 12; generation++) {
          await _save(store, entity, 'Task $generation');
          final completion = await store.complete(
            entity,
            completionDay: DateTime(2030, 5, 10 + generation),
          );
          final proof = completion.data['inheritance'] as Map;
          expect(proof['adapter'], 2);
          expect((proof['fields'] as Map)['title'], contains('historyHash'));
          expect(
            (proof['fields'] as Map)['title'],
            isNot(contains('stateHash')),
          );
          entity = const Uuid().v5(entity, 'successor');
        }
        expect(
          store.rows.singleWhere((row) => row['id'] == entity)['title'],
          'Task 11',
        );
        final bytes =
            store.db
                    .select('SELECT SUM(length(state)) AS n FROM text_fields')
                    .single['n']
                as int;
        expect(
          bytes,
          lessThan(1024),
          reason:
              'Completed occurrences retain references, not growing inherited BLOBs.',
        );
        final snapshot = jsonEncode(store.taskSnapshot);
        final canonical = <String, String>{};
        await for (final file in folder.list()) {
          if (file is File) {
            canonical[file.path] = sha256
                .convert(await file.readAsBytes())
                .toString();
          }
        }
        await store.close();
        store = await TaskStore.open(
          LocalLogFolder(folder.path),
          '${root.path}/profile',
          textEngine: engine,
        );
        expect(store.readFiles, 0);
        expect(jsonEncode(store.taskSnapshot), snapshot);
        await store.close();
        store = await TaskStore.open(
          LocalLogFolder(folder.path),
          '${root.path}/cold-profile',
          textEngine: engine,
        );
        expect(jsonEncode(store.taskSnapshot), snapshot);
        final capture = await store.captureTaskText(entity);
        expect(capture.fields['title']!.document.read().text, 'Task 11');
        store.releaseTextCapture(capture);
        for (final entry in canonical.entries) {
          expect(
            sha256.convert(await File(entry.key).readAsBytes()).toString(),
            entry.value,
          );
        }
      } finally {
        await store?.close();
        engine.dispose();
        // Keep this synthetic fixture for diagnostics; no existing files removed.
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
        ? 'Actual native library required'
        : false,
  );
}
