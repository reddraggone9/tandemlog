import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  test(
    'canceled untouched checklist successor cannot open a private native editor or become visible through capture',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'checklist-suppressed-capture-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4(),
            parent = const Uuid().v4(),
            item = const Uuid().v4();
        Map<String, dynamic> seed(String title) => {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText(title).bytes).toString(),
            'description': sha256.convert(engine.seedText('').bytes).toString(),
          },
        };
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(parent, 'task.createdWithText', {
          'title': 'Native parent',
          'description': '',
          'assignee': user,
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          'text': seed('Native parent'),
        });
        await store.command(item, 'checklist.itemCreated', {
          'parent': parent,
          'title': 'Untouched item',
          'description': '',
          'before': null,
          'text': seed('Untouched item'),
        });
        final completed = await store.complete(
          parent,
          completionDay: DateTime(2030, 5, 10),
        );
        expect(completed.type, 'task.completedWithChecklist');
        final child = const Uuid().v5(parent, 'successor');
        expect(store.rows.any((row) => row['id'] == child), true);
        expect(
          (await store.undoOperations([completed.id])).removedSuccessorCount,
          1,
        );
        expect(store.rows.any((row) => row['id'] == child), false);
        final views = jsonEncode(
          store.db
              .select('SELECT id,raw FROM views ORDER BY id')
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
        );
        final bytes = <String, String>{};
        for (final file in await folder.list()) {
          bytes[file.name] = sha256
              .convert(
                await File('${folder.location}/${file.name}').readAsBytes(),
              )
              .toString();
        }
        await expectLater(
          store.captureTaskText(child),
          throwsA(isA<FormatFailure>()),
        );
        expect(store.rows.any((row) => row['id'] == child), false);
        expect(
          jsonEncode(
            store.db
                .select('SELECT id,raw FROM views ORDER BY id')
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          ),
          views,
        );
        for (final entry in bytes.entries) {
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
        await store?.close();
        engine.dispose();
      }
    },
  );
}
