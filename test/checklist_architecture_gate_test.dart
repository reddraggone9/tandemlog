import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

class _Fixture {
  _Fixture(this.root, this.folder, this.engine, this.store, this.parent);
  final Directory root;
  final LocalLogFolder folder;
  final NativeTextEngine engine;
  final TaskStore store;
  final String parent;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'checklist-architecture-',
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
    final user = const Uuid().v4(), parent = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(parent, 'task.createdWithText', {
      'title': 'Parent',
      'description': '',
      'assignee': user,
      'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256.convert(engine.seedText('Parent').bytes).toString(),
          'description': sha256.convert(engine.seedText('').bytes).toString(),
        },
      },
    });
    return _Fixture(root, folder, engine, store, parent);
  }

  Future<Map<String, String>> canonical() async => {
    for (final file in await folder.list())
      file.name: sha256.convert(await folder.read(file.name)).toString(),
  };

  String cached() => jsonEncode({
    for (final table in ['events', 'views', 'text_fields', 'text_outbox'])
      table: store.db
          .select('SELECT * FROM $table')
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  });

  TaskTextSession session(TaskTextCapture capture) => TaskTextSession(
    capture,
    registerDraftActor: (field, allocation, actor) =>
        store.registerTextDraftActor(capture, field, allocation, actor),
  );

  Future<void> close() async {
    await store.close();
    engine.dispose();
    // Preserve all synthetic fixtures for review; no live data is used.
  }
}

void main() {
  test(
    'genuine offline item activity arriving after cancellation restores its task',
    () async {
      final f = await _Fixture.create();
      TaskStore? peer;
      try {
        final source = await f.store.addChecklistItem(
          f.parent,
          'Original item',
        );
        final completion = await f.store.complete(
          f.parent,
          completionDay: DateTime(2030, 5, 10),
        );
        final child = const Uuid().v5(f.parent, 'successor');
        final copied = const Uuid().v5(child, 'checklist:${source.entity}');
        final peerDirectory = await Directory(
          '${f.root.path}/peer-shared',
        ).create();
        for (final file in await f.folder.list()) {
          await File(
            '${f.folder.location}/${file.name}',
          ).copy('${peerDirectory.path}/${file.name}');
        }
        peer = await TaskStore.open(
          LocalLogFolder(peerDirectory.path),
          '${f.root.path}/peer-profile',
          textEngine: f.engine,
        );
        await peer.setChecklistCompleted(copied, true);
        expect(
          (await f.store.undoOperations([completion.id])).removedSuccessorCount,
          1,
        );
        expect(f.store.rows.any((row) => row['id'] == child), false);
        await File(
          '${peerDirectory.path}/${peer.writer}.jsonl',
        ).copy('${f.folder.location}/${peer.writer}.jsonl');
        await f.store.refresh();
        expect(f.store.rows.any((row) => row['id'] == child), true);
        expect(f.store.checklistItems(child).single['completed'], true);
        final snapshot = jsonEncode(f.store.rows),
            canonical = await f.canonical();
        await f.store.refresh();
        expect(jsonEncode(f.store.rows), snapshot);
        expect(await f.canonical(), canonical);
      } finally {
        await peer?.close();
        await f.close();
      }
    },
  );

  for (final action in ['create', 'check', 'move', 'delete', 'native Save']) {
    test('local item $action cannot resurrect a canceled successor', () async {
      final f = await _Fixture.create();
      TaskTextCapture? capture;
      TaskTextSession? session;
      try {
        final original = await f.store.addChecklistItem(
          f.parent,
          'Untouched item',
          notes: 'Original notes',
        );
        final completed = await f.store.complete(
          f.parent,
          completionDay: DateTime(2030, 5, 10),
        );
        final child = const Uuid().v5(f.parent, 'successor');
        final copied = const Uuid().v5(child, 'checklist:${original.entity}');
        if (action == 'native Save') {
          capture = await f.store.captureTaskText(copied);
          session = f.session(capture)..replace('title', 'Private child edit');
        }
        final undone = await f.store.undoOperations([completed.id]);
        expect(undone.removedSuccessorCount, 1);
        expect(f.store.rows.any((row) => row['id'] == child), isFalse);
        final canonical = await f.canonical(), cached = f.cached();
        var prepared = false;
        void onPrepared(OperationReceipt receipt) => prepared = true;
        final operation = switch (action) {
          'create' => f.store.addChecklistItem(
            child,
            'New item in canceled task',
            onPrepared: onPrepared,
          ),
          'check' => f.store.setChecklistCompleted(
            copied,
            true,
            onPrepared: onPrepared,
          ),
          'move' => f.store.moveChecklistItem(
            copied,
            null,
            onPrepared: onPrepared,
          ),
          'delete' => f.store.deleteChecklistItem(
            copied,
            onPrepared: onPrepared,
          ),
          _ => TextSaveCommand(f.store, session!).save(
            fields: {},
            tags: [],
            observedTagRefs: {},
            onPrepared: onPrepared,
          ),
        };
        await expectLater(operation, throwsA(isA<FormatFailure>()));
        expect(prepared, false);
        expect(await f.canonical(), canonical);
        expect(f.cached(), cached);
        expect(f.store.rows.any((row) => row['id'] == child), isFalse);
        if (session != null) {
          expect(session.text('title'), 'Private child edit');
          expect(session.hasPendingReceipt, false);
        }
      } finally {
        session?.cancel();
        if (capture != null) f.store.releaseTextCapture(capture);
        await f.close();
      }
    });
  }

  test(
    'item Save returns its current merged item rather than a deleted row',
    () async {
      final f = await _Fixture.create();
      TaskTextCapture? capture;
      TaskTextSession? session;
      try {
        final item = await f.store.addChecklistItem(
          f.parent,
          'Original title',
          notes: 'Original notes',
        );
        capture = await f.store.captureTaskText(item.entity);
        session = f.session(capture)..replace('title', 'Saved title');
        // Separately acknowledged status and notes must appear in the Save result.
        await f.store.setChecklistCompleted(item.entity, true);
        final otherCapture = await f.store.captureTaskText(item.entity);
        final otherSession = f.session(otherCapture)
          ..replace('description', 'Separately saved notes');
        try {
          await TextSaveCommand(
            f.store,
            otherSession,
          ).save(fields: {}, tags: [], observedTagRefs: {});
        } finally {
          otherSession.cancel();
          f.store.releaseTextCapture(otherCapture);
        }
        final result = await TextSaveCommand(
          f.store,
          session,
        ).save(fields: {}, tags: [], observedTagRefs: {});
        expect(result.status, TextSaveStatus.saved);
        expect(result.receipt, isNotNull);
        expect(result.currentRow, isNotNull);
        expect(result.currentRow!['id'], item.entity);
        expect(result.currentRow!['kind'], 'checklistItem');
        expect(result.currentRow!['parent'], f.parent);
        expect(result.currentRow!['title'], 'Saved title');
        expect(result.currentRow!['description'], 'Separately saved notes');
        expect(result.currentRow!['completed'], true);
        expect(result.currentRow!['deleted'], false);
      } finally {
        session?.cancel();
        if (capture != null) f.store.releaseTextCapture(capture);
        await f.close();
      }
    },
  );
}
