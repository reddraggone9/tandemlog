import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

class _Fixture {
  _Fixture(
    this.root,
    this.folder,
    this.engine,
    this.store,
    this.parent,
    this.child,
    this.original,
  );
  final Directory root, folder;
  final NativeTextEngine engine;
  TaskStore store;
  final String parent, child;
  final LogEvent original;
  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'historical-recompletion-',
    );
    final folder = await Directory('${root.path}/shared').create();
    final engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    final store = await TaskStore.open(
      LocalLogFolder(folder.path),
      '${root.path}/profile',
      textEngine: engine,
    );
    final user = const Uuid().v4(), parent = const Uuid().v4();
    final child = const Uuid().v5(parent, 'successor');
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(parent, 'task.created', {
      'title': 'Old parent',
      'description': 'Old notes',
      'assignee': user,
      'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
    });
    final original = await store.complete(
      parent,
      completionDay: DateTime(2030, 5, 10),
    );
    await store.command(child, 'task.edited', {
      'title': 'Independent child',
      'description': 'Independent notes',
      'schedule': {'dueDate': '2030-07-20', 'recurrence': 'every week'},
      'tagChanges': {
        'add': ['Child tag'],
        'remove': [],
      },
    });
    await store.initializeSharedText();
    await store.reopen(parent, [original.id]);
    return _Fixture(root, folder, engine, store, parent, child, original);
  }

  Map<String, dynamic> row(String id) =>
      jsonDecode(
            store.db.select('SELECT raw FROM views WHERE id=?', [
                  id,
                ]).single['raw']
                as String,
          )
          as Map<String, dynamic>;
  Future<OperationReceipt> save(String entity, String title) async {
    final capture = await store.captureTaskText(entity);
    return _saveCapture(capture, entity, title);
  }

  Future<OperationReceipt> _saveCapture(
    TaskTextCapture capture,
    String entity,
    String title,
  ) async {
    final field = capture.fields['title']!;
    final draft = field.document.captureDraft(actorClientId: field.actor)
      ..replaceText(title);
    final saved = draft.prepareSave();
    OperationReceipt? receipt;
    try {
      await store.editNativeTask(entity, {
        'title': {
          'context': field.context,
          'allocation': field.allocation,
          'actor': field.actor,
          'update': saved.update.encoded,
        },
      }, onPrepared: (value) => receipt = value);
      saved.commit(receiptUpdate: saved.update);
      store.registerTextOperation(receipt!, capture);
      return receipt!;
    } finally {
      store.releaseTextCapture(capture);
    }
  }

  Future<Map<String, String>> canonical() async => {
    await for (final file in folder.list())
      if (file is File)
        file.path: sha256.convert(await file.readAsBytes()).toString(),
  };
  Future<void> close() async {
    await store.close();
    engine.dispose();
  }
}

void main() {
  test(
    'offline historical recompletions converge without reseeding or suppressing the existing child',
    () async {
      final f = await _Fixture.create();
      TaskStore? peer;
      try {
        final peerFolder = await Directory(
          '${f.root.path}/peer-shared',
        ).create();
        await for (final file in f.folder.list()) {
          if (file is File)
            await file.copy('${peerFolder.path}/${file.uri.pathSegments.last}');
        }
        peer = await TaskStore.open(
          LocalLogFolder(peerFolder.path),
          '${f.root.path}/peer-profile',
          textEngine: f.engine,
        );
        final before = jsonEncode(f.row(f.child));
        final a = await f.store.complete(
          f.parent,
          completionDay: DateTime(2030, 8, 1),
        );
        final b = await peer.complete(
          f.parent,
          completionDay: DateTime(2030, 8, 2),
        );
        await File(
          '${peerFolder.path}/${peer.writer}.jsonl',
        ).copy('${f.folder.path}/${peer.writer}.jsonl');
        await f.store.refresh();
        await File(
          '${f.folder.path}/${f.store.writer}.jsonl',
        ).copy('${peerFolder.path}/${f.store.writer}.jsonl');
        await peer.refresh();
        expect(f.store.activeCompletionIds(f.parent).toSet(), {a.id, b.id});
        expect(peer.activeCompletionIds(f.parent).toSet(), {a.id, b.id});
        expect(jsonEncode(f.row(f.child)), before);
        expect(
          jsonEncode(peer.rows.singleWhere((r) => r['id'] == f.child)),
          before,
        );
        final eventCount = f.store.db
            .select('SELECT COUNT(*) AS n FROM events')
            .single['n'];
        await f.store.refresh();
        expect(
          f.store.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
          eventCount,
        );
        final undo = await f.store.undoOperations([a.id]);
        expect(undo.remaining, isEmpty);
        expect(f.row(f.parent)['completed'], true);
        expect(jsonEncode(f.row(f.child)), before);
        expect(f.store.rows.where((r) => r['id'] == f.child), hasLength(1));
      } finally {
        await peer?.close();
        await f.close();
      }
    },
  );
  test(
    'known wrong historical initialization rejects before receipt preparation',
    () async {
      final f = await _Fixture.create();
      try {
        final before = await f.canonical();
        var prepared = false;
        await expectLater(
          f.store.command(f.parent, 'task.completedKeepingSuccessor', {
            'completedAt': '2030-08-01',
            'retainedSuccessor': {
              'id': f.child,
              'completion': f.original.id,
              'hash': 'f' * 64,
            },
          }, onPrepared: (_) => prepared = true),
          throwsA(isA<FormatFailure>()),
        );
        expect(prepared, false);
        expect(await f.canonical(), before);
        expect(f.row(f.parent)['completed'], false);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'historical recompletion preserves independent child draft, context and scoped Undo',
    () async {
      final f = await _Fixture.create();
      try {
        final savedChild = await f.save(f.child, 'Next: independent child');
        final capture = await f.store.captureTaskText(f.child);
        final title = capture.fields['title']!;
        final private = title.document.captureDraft(actorClientId: title.actor)
          ..replaceText('Private child draft');
        final state = title.document.fullState.encoded;
        await f.save(f.parent, 'Edited old parent');
        final before = jsonEncode(f.row(f.child));
        final completion = await f.store.complete(
          f.parent,
          completionDay: DateTime(2030, 8, 1),
        );
        expect(completion.type, 'task.completedKeepingSuccessor');
        expect(completion.data['retainedSuccessor'], {
          'id': f.child,
          'completion': f.original.id,
          'hash': f.original.hash,
        });
        expect(completion.data, isNot(contains('successor')));
        expect(completion.data, isNot(contains('inheritance')));
        expect(f.row(f.parent)['completed'], true);
        expect(jsonEncode(f.row(f.child)), before);
        expect(title.document.fullState.encoded, state);
        expect(private.capturedText, 'Private child draft');
        private.cancel();
        f.store.releaseTextCapture(capture);
        final undone = await f.store.undoOperations([completion.id]);
        expect(undone.remaining, isEmpty);
        expect(undone.retainedSuccessorCount, 1);
        expect(f.row(f.parent)['completed'], false);
        expect(jsonEncode(f.row(f.child)), before);
        final childUndo = await f.store.undoOperations([savedChild.id]);
        expect(childUndo.remaining, isEmpty);
        expect(f.row(f.child)['title'], 'Independent child');
      } finally {
        await f.close();
      }
    },
  );
  for (final disposition in ['open', 'completed', 'deleted']) {
    test(
      'historical recompletion leaves $disposition child unchanged through warm and cold replay',
      () async {
        final f = await _Fixture.create();
        try {
          if (disposition == 'completed') {
            await f.store.complete(
              f.child,
              completionDay: DateTime(2030, 7, 20),
            );
          } else if (disposition == 'deleted') {
            await f.store.command(f.child, 'task.deleted', {});
          }
          final before = jsonEncode(f.row(f.child));
          final contexts = f.store.db
              .select(
                'SELECT field,context FROM text_fields WHERE entity=? ORDER BY field',
                [f.child],
              )
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          await f.store.complete(f.parent, completionDay: DateTime(2030, 8, 1));
          expect(jsonEncode(f.row(f.child)), before);
          final snapshot = jsonEncode(f.store.taskSnapshot),
              canonical = await f.canonical();
          await f.store.close();
          f.store = await TaskStore.open(
            LocalLogFolder(f.folder.path),
            '${f.root.path}/profile',
            textEngine: f.engine,
          );
          expect(f.store.readFiles, 0);
          expect(jsonEncode(f.store.taskSnapshot), snapshot);
          await f.store.close();
          f.store = await TaskStore.open(
            LocalLogFolder(f.folder.path),
            '${f.root.path}/cold',
            textEngine: f.engine,
          );
          expect(jsonEncode(f.store.taskSnapshot), snapshot);
          expect(
            f.store.db
                .select(
                  'SELECT field,context FROM text_fields WHERE entity=? ORDER BY field',
                  [f.child],
                )
                .map((r) => Map<String, dynamic>.from(r))
                .toList(),
            contexts,
          );
          for (final entry in canonical.entries) {
            expect(
              sha256.convert(await File(entry.key).readAsBytes()).toString(),
              entry.value,
            );
          }
        } finally {
          await f.close();
        }
      },
    );
  }
}
