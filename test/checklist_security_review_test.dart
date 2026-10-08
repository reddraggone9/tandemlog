import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/checklist.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  test(
    'admissible large checklist copy has bounded decode work and preserves canonical bytes',
    () {
      const space = '00000000-0000-4000-8000-000000000001',
          parent = '00000000-0000-4000-8000-000000000002',
          writer = '00000000-0000-4000-8000-000000000003';
      final successor = const Uuid().v5(parent, 'successor');
      final frontiers = {
        for (var head = 0; head < 3000; head++)
          const Uuid().v5(space, 'writer$head'): {'seq': 1, 'hash': '0' * 64},
      };
      final descriptor = {
        'codec': 'yrs-v1',
        'adapter': 2,
        'frontiers': frontiers,
        'items': [
          for (var index = 0; index < 900; index++)
            (() {
              final source = const Uuid().v5(parent, 'item$index');
              return {
                'id': copiedChecklistId(successor, source),
                'source': source,
                'title': 'X',
                'description': '',
                'fields': {
                  for (final field in ['title', 'description'])
                    field: {
                      'parentContext': '0' * 64,
                      'seedHash': '0' * 64,
                      'historyHash': '0' * 64,
                    },
                },
              };
            })(),
        ],
      };
      // These are shape-valid wire frontiers/proofs. Canonical semantic ingestion
      // separately verifies that their source records have actually arrived.
      final event = LogEvent(
        space,
        writer,
        1,
        EventClock(BigInt.one),
        parent,
        'task.completedWithChecklist',
        {
          'completedAt': '2030-05-01',
          'successor': {
            'id': successor,
            'title': 'Scalar',
            'description': '',
            'assignee': writer,
            'tags': <String>[],
            'schedule': {'dueDate': '2030-05-02', 'recurrence': 'every day'},
          },
          'checklist': descriptor,
        },
      );
      final raw = event.encode();
      expect(utf8.encode(raw).length, lessThan(1024 * 1024));
      final originalHash = (jsonDecode(raw) as Map)['hash'];
      // Warm ordinary codec work before measuring the one adversarial frame.
      LogEvent.decode(
        LogEvent(
          space,
          writer,
          1,
          EventClock(BigInt.one),
          parent,
          'task.created',
          {'title': 'Warm', 'description': '', 'assignee': writer},
        ).encode(),
      );
      final timer = Stopwatch()..start();
      final decoded = LogEvent.decode(raw);
      timer.stop();
      expect(decoded.canonicalRaw, raw);
      expect(decoded.hash, originalHash);
      expect(decoded.encode(), raw);
      expect(
        timer.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason:
            'One bounded canonical frame must not revalidate its full '
            'frontier map once for every copied item.',
      );
    },
  );

  test(
    'scalar checklist historical recompletion preserves protected child without shared-text initialization',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'checklist-security-scalar-history-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final store = await TaskStore.open(
        folder,
        '${root.path}/profile',
        textEngine: engine,
      );
      try {
        final user = const Uuid().v4(), parent = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.command(parent, 'task.created', {
          'title': 'Scalar parent',
          'description': '',
          'assignee': user,
          'schedule': {'dueDate': '2030-05-01', 'recurrence': 'every day'},
        });
        final source = await store.addChecklistItem(parent, 'Original');
        final original = await store.complete(
          parent,
          completionDay: DateTime(2030, 5, 1),
        );
        final child = const Uuid().v5(parent, 'successor');
        final copied = const Uuid().v5(child, 'checklist:${source.entity}');
        await store.setChecklistCompleted(copied, true);
        await store.undoOperations([original.id]);
        expect(store.sharedTextInitialized, false);
        expect(
          store.db.select('SELECT 1 FROM text_fields WHERE entity=?', [parent]),
          isEmpty,
        );
        final before = jsonEncode(store.checklistItems(child));
        await store.addChecklistItem(parent, 'Later old item');
        final recompleted = await store.complete(
          parent,
          completionDay: DateTime(2030, 5, 2),
        );
        expect(recompleted.type, 'task.completedKeepingSuccessor');
        expect(jsonEncode(store.checklistItems(child)), before);
        expect(store.checklistItems(child).single['completed'], true);
      } finally {
        await store.close();
        engine.dispose();
        // Retain synthetic files for diagnostics; never touch synced user data.
      }
    },
  );
}
