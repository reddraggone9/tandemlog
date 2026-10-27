import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/checklist.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  test(
    'late peer failure discards speculative input and native fields before retry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'text-input-rollback-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? a, b;
      final blocker = Object();
      var attached = false;
      try {
        a = await TaskStore.open(folder, '${root.path}/a', textEngine: engine);
        final user = const Uuid().v4(), parent = const Uuid().v4();
        await a.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await a.createTasks({parent: 'Recurring'}, user)).succeeded,
          isTrue,
        );
        await a.edit(
          parent,
          {
            'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          },
          tags: [],
          observedTagRefs: {},
        );
        final item = await a.addChecklistItem(parent, 'Copied field');
        await a.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
        );
        b = await TaskStore.open(folder, '${root.path}/b', textEngine: engine);
        await a.refresh();
        final child = const Uuid().v5(parent, 'successor');
        final copy = copiedChecklistId(child, item.entity);
        final captures = [
          await a.captureTaskText(child),
          await a.captureTaskText(copy),
        ];
        final texts = [
          for (final capture in captures)
            {
              for (final entry in capture.fields.entries)
                entry.key: entry.value.document.read().text,
            },
        ];
        final beforeView = a.currentView, beforeRows = jsonEncode(a.rows);
        final app = a.unified!;
        final beforeRevision = app.snapshot.revision;
        List<List<Object?>> heads() => app.profile.database
            .select('SELECT * FROM protected_app_heads ORDER BY writer')
            .map((row) => row.values.toList())
            .toList();
        final beforeHeads = heads();
        final ownedName = '${a.writer}.applog';
        final ownedBytes = await folder.read(ownedName);
        await b.reopen(parent, b.activeCompletionIds(parent));
        await b.edit(
          parent,
          {
            'schedule': {'dueDate': '2030-05-11', 'recurrence': 'every day'},
          },
          tags: [],
          observedTagRefs: {},
        );
        await b.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 11),
        );
        var fail = false, publications = 0, rejectedStage = false;
        await app.profile.serialize(() async {
          app.attachProjectionInProfileQueue(blocker, (snapshot) {
            if (fail && snapshot.revision != beforeRevision) {
              rejectedStage = true;
              throw FormatFailure('Synthetic late peer projection failure');
            }
            return () {
              publications++;
            };
          });
        });
        attached = true;
        publications = 0;
        fail = true;
        await expectLater(a.refresh(), throwsA(isA<FormatFailure>()));
        expect(rejectedStage, isTrue);
        expect(publications, 0);
        expect(identical(a.currentView, beforeView), isTrue);
        expect(jsonEncode(a.rows), beforeRows);
        expect(app.snapshot.revision, beforeRevision);
        expect(heads(), beforeHeads);
        expect(await folder.read(ownedName), ownedBytes);
        for (var i = 0; i < captures.length; i++) {
          expect({
            for (final entry in captures[i].fields.entries)
              entry.key: entry.value.document.read().text,
          }, texts[i]);
        }
        fail = false;
        await a.refresh();
        expect(publications, 1);
        expect(a.taskSnapshot, b.taskSnapshot);
        for (var i = 0; i < captures.length; i++) {
          final peerCapture = await b.captureTaskText(i == 0 ? child : copy);
          for (final field in ['title', 'description']) {
            expect(
              captures[i].fields[field]!.context,
              peerCapture.fields[field]!.context,
            );
            expect(
              captures[i].fields[field]!.document.read().text,
              peerCapture.fields[field]!.document.read().text,
            );
            expect(
              captures[i].fields[field]!.document.fullState.encoded,
              peerCapture.fields[field]!.document.fullState.encoded,
            );
          }
          b.releaseTextCapture(peerCapture);
          a.releaseTextCapture(captures[i]);
        }
        await a.edit(
          child,
          {
            'schedule': {'dueDate': '2030-05-20'},
          },
          tags: [],
          observedTagRefs: {},
        );
        expect(
          {for (final row in a.rows) row['id']: row},
          {
            for (final row in TaskStore.validateSemanticHistory(
              app.snapshot.tasks,
              space: a.space,
              writer: a.writer,
              textEngine: engine,
            ))
              row['id']: row,
          },
        );
        expect(app.snapshot.allVisibleTasksReady, isTrue);
      } finally {
        if (attached && a != null) {
          await a.unified!.profile.serialize(() async {
            a!.unified!.detachProjectionInProfileQueue(blocker);
          });
        }
        await b?.close();
        await a?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
  );
}
