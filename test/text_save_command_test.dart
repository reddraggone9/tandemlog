import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

final _libraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];

void main() {
  group(
    'production native Save coordinator',
    () {
      test(
        'canonical acknowledgement precedes commit and enables selective Undo',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final session = await fixture.session();
          session.replace('title', 'AX');
          final owner = session.capture.fields['title']!.document;
          final before = owner.fullState.encoded;
          final observedRefs = fixture.tagRefs;
          fixture.folder.beforeAppend = () {
            expect(owner.fullState.encoded, before);
            expect(session.hasPendingReceipt, isTrue);
            expect(
              fixture.store.confirmedOperations([session.prepare().receipt!]),
              isEmpty,
            );
          };
          OperationReceipt? observed;
          final result = await TextSaveCommand(fixture.store, session).save(
            fields: {
              'schedule': {'dueDate': '2026-10-07'},
            },
            tags: ['new'],
            observedTagRefs: observedRefs,
            expectedSnapshot: fixture.store.taskSnapshot,
            onPrepared: (receipt) {
              observed = receipt;
              expect(session.prepare().receipt!.raw, receipt.raw);
            },
          );
          expect(result.status, TextSaveStatus.saved);
          expect(result.receipt!.raw, observed!.raw);
          expect(result.currentRow!['title'], 'AX');
          expect(result.currentRow!['tags'], ['new']);
          expect(session.frozen, isFalse);
          final data = LogEvent.decode(result.receipt!.raw).data;
          expect(data['title'], isNull);
          expect(data['tagChanges'], {
            'add': ['new'],
            'remove': observedRefs.keys.toList(),
          });
          fixture.folder.beforeAppend = null;
          final undo = await fixture.store.undoOperations([result.receipt!.id]);
          expect(undo.remaining, isEmpty, reason: undo.error?.toString());
          expect(fixture.row['title'], 'A');
          expect(fixture.row['tags'], ['old']);
          expect((fixture.row['schedule'] as Map)['dueDate'], isNull);
        },
      );

      for (final afterWriting in [false, true]) {
        test(
          'unknown append retains exact packet and nontext intent afterWriting=$afterWriting',
          () async {
            final fixture = await _Fixture.open();
            addTearDown(fixture.close);
            final session = await fixture.session();
            final command = TextSaveCommand(fixture.store, session);
            session.replace('title', 'AX');
            final owner = session.capture.fields['title']!.document;
            final before = owner.fullState.encoded;
            fixture.folder.failNext = true;
            fixture.folder.throwAfterWriting = afterWriting;
            await expectLater(
              command.save(
                fields: {
                  'schedule': {'dueDate': '2026-10-07'},
                },
                tags: ['new'],
                observedTagRefs: fixture.tagRefs,
              ),
              throwsA(isA<FolderAccessFailure>()),
            );
            final prepared = session.prepare(), receipt = prepared.receipt!;
            expect(session.hasPendingReceipt, isTrue);
            expect(prepared.committed, isFalse);
            expect(owner.fullState.encoded, before);
            expect(
              () => session.replace('title', 'different'),
              throwsStateError,
            );
            final result = await command.save(
              fields: {
                'schedule': {'dueDate': '2030-01-01'},
              },
              tags: ['different'],
              observedTagRefs: {},
              expectedSnapshot: 'invalid new snapshot',
              canCommit: () => false,
            );
            expect(result.receipt!.raw, receipt.raw);
            expect(result.receipt!.id, receipt.id);
            expect(result.currentRow!['title'], 'AX');
            expect(result.currentRow!['schedule'], {'dueDate': '2026-10-07'});
            expect(result.currentRow!['tags'], ['new']);
            final lines = const LineSplitter().convert(
              utf8.decode(
                await fixture.folder.read('${fixture.store.writer}.jsonl'),
              ),
            );
            expect(
              lines.where((line) => LogEvent.decode(line).id == receipt.id),
              [receipt.raw],
            );
            expect(session.frozen, isFalse);
          },
        );
      }

      test(
        'bound retry completes frozen intent after remote metadata changes',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final refs = fixture.tagRefs;
          final session = await fixture.session();
          session.replace('title', 'AX');
          final command = TextSaveCommand(fixture.store, session);
          fixture.folder.failNext = true;
          await expectLater(
            command.save(
              fields: {
                'schedule': {'dueDate': '2026-10-07'},
              },
              tags: ['old'],
              observedTagRefs: refs,
            ),
            throwsA(isA<FolderAccessFailure>()),
          );
          final receipt = session.prepare().receipt!;
          final peer = await TaskStore.open(
            LocalLogFolder(fixture.folder.location),
            '${fixture.root.path}/peer',
            textEngine: fixture.engine,
          );
          try {
            await peer.edit(
              fixture.task,
              {
                'schedule': {'dueDate': '2026-10-09'},
              },
              tags: ['old', 'remote'],
              observedTagRefs: refs,
            );
          } finally {
            await peer.close();
          }
          final result = await command.save(
            fields: {},
            tags: [],
            observedTagRefs: {},
            expectedSnapshot: 'changed',
            canCommit: () => false,
          );
          expect(result.receipt!.raw, receipt.raw);
          expect(LogEvent.decode(result.receipt!.raw).data['schedule'], {
            'dueDate': '2026-10-07',
          });
          expect(result.currentRow!['title'], 'AX');
          expect(result.currentRow!['schedule'], {'dueDate': '2026-10-09'});
          expect(result.currentRow!['tags'], ['old', 'remote']);
        },
      );

      test(
        'unchanged Save preserves captured lease and nontext-only Save uses ordinary edit',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final session = await fixture.session();
          final command = TextSaveCommand(fixture.store, session);
          final originalActor = session.capture.fields['title']!.actor;
          final count = fixture.store.db
              .select('SELECT COUNT(*) AS n FROM events')
              .single['n'];
          final unchanged = await command.save(
            fields: {},
            tags: ['old'],
            observedTagRefs: fixture.tagRefs,
          );
          expect(unchanged.status, TextSaveStatus.unchanged);
          expect(unchanged.receipt, isNull);
          expect(
            fixture.store.db
                .select('SELECT COUNT(*) AS n FROM events')
                .single['n'],
            count,
          );
          final metadata = await command.save(
            fields: {
              'schedule': {'dueDate': '2026-10-07'},
            },
            tags: ['new'],
            observedTagRefs: fixture.tagRefs,
          );
          expect(LogEvent.decode(metadata.receipt!.raw).type, 'task.edited');
          expect(session.frozen, isFalse);
          session.replace('title', 'AX');
          expect(session.prepare().changes['title']!['actor'], originalActor);
        },
      );

      test(
        'nontext guard rejects before append without consuming private edits',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final session = await fixture.session();
          final snapshot = fixture.store.taskSnapshot;
          session.replace('title', 'AX');
          await fixture.store.edit(
            fixture.task,
            {
              'schedule': {'dueDate': '2026-10-08'},
            },
            tags: ['old'],
            observedTagRefs: fixture.tagRefs,
          );
          await expectLater(
            TextSaveCommand(fixture.store, session).save(
              fields: {},
              tags: ['old'],
              observedTagRefs: fixture.tagRefs,
              expectedSnapshot: snapshot,
            ),
            throwsA(isA<StaleTaskSnapshot>()),
          );
          expect(session.text('title'), 'AX');
          expect(session.hasPendingReceipt, isFalse);
          expect(fixture.row['title'], 'A');
        },
      );

      test(
        'remote text merges into the returned row without rebasing private intent',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final session = await fixture.session();
          final snapshot = fixture.store.taskSnapshot;
          final observedRefs = fixture.tagRefs;
          session.replace('title', 'AX');
          final peer = await TaskStore.open(
            LocalLogFolder(fixture.folder.location),
            '${fixture.root.path}/peer',
            textEngine: fixture.engine,
          );
          try {
            final capture = await peer.captureTaskText(fixture.task);
            final remote = TaskTextSession(
              capture,
              registerDraftActor: (field, allocation, actor) => peer
                  .registerTextDraftActor(capture, field, allocation, actor),
            );
            try {
              remote.replace('title', 'RA');
              await TextSaveCommand(
                peer,
                remote,
              ).save(fields: {}, tags: ['old'], observedTagRefs: observedRefs);
              await fixture.store.refresh();
              expect(session.text('title'), 'AX');
              expect(fixture.row['title'], 'RA');
              final result = await TextSaveCommand(fixture.store, session).save(
                fields: {},
                tags: ['old'],
                observedTagRefs: observedRefs,
                expectedSnapshot: snapshot,
              );
              expect(result.status, TextSaveStatus.saved);
              expect(result.currentRow!['title'], 'RAX');
              expect(session.text('title'), 'RAX');
              final undo = await fixture.store.undoOperations([
                result.receipt!.id,
              ]);
              expect(undo.remaining, isEmpty, reason: undo.error?.toString());
              expect(fixture.row['title'], 'RA');
            } finally {
              remote.cancel();
            }
          } finally {
            await peer.close();
          }
        },
      );

      test(
        'nontext-only native session permits remote text under the same guard',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final session = await fixture.session();
          final snapshot = fixture.store.taskSnapshot;
          final refs = fixture.tagRefs;
          final other = await fixture.session();
          other.replace('title', 'Remote');
          await TextSaveCommand(
            fixture.store,
            other,
          ).save(fields: {}, tags: ['old'], observedTagRefs: refs);
          expect(session.text('title'), 'A');
          final result = await TextSaveCommand(fixture.store, session).save(
            fields: {
              'schedule': {'dueDate': '2026-10-09'},
            },
            tags: ['old'],
            observedTagRefs: refs,
            expectedSnapshot: snapshot,
          );
          expect(result.status, TextSaveStatus.saved);
          expect(result.currentRow!['title'], 'Remote');
          expect(session.text('title'), 'A');
        },
      );

      test(
        'Undo registration failure reports the already saved result',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final capture = await fixture.store.captureTaskText(fixture.task);
          // Same real retained owner, but a capture not registered by this store.
          final session = TaskTextSession(
            TaskTextCapture(
              capture.entity,
              capture.fields,
              writer: capture.writer,
            ),
            registerDraftActor: (field, allocation, actor) => fixture.store
                .registerTextDraftActor(capture, field, allocation, actor),
          );
          fixture.sessions.add(session);
          session.replace('title', 'AX');
          final result = await TextSaveCommand(
            fixture.store,
            session,
          ).save(fields: {}, tags: ['old'], observedTagRefs: fixture.tagRefs);
          expect(result.status, TextSaveStatus.savedUndoUnavailable);
          expect(result.undoError, isNotNull);
          expect(result.currentRow!['title'], 'AX');
          expect(fixture.store.confirmedOperations([result.receipt!]), {
            result.receipt!.id,
          });
          expect(session.frozen, isFalse);
        },
      );

      test(
        'postcommit draft allocation failure reports saved and can finish renewal',
        () async {
          final fixture = await _Fixture.open();
          addTearDown(fixture.close);
          final capture = await fixture.store.captureTaskText(fixture.task);
          var failRenewal = true;
          final session = TaskTextSession(
            capture,
            registerDraftActor: (field, allocation, actor) {
              if (failRenewal) {
                throw StateError('Synthetic draft allocation failure');
              }
              fixture.store.registerTextDraftActor(
                capture,
                field,
                allocation,
                actor,
              );
            },
          );
          fixture.sessions.add(session);
          session.replace('title', 'AX');
          final command = TextSaveCommand(fixture.store, session);
          final result = await command.save(
            fields: {},
            tags: ['old'],
            observedTagRefs: fixture.tagRefs,
          );
          expect(result.status, TextSaveStatus.saved);
          expect(result.sessionError, isNotNull);
          expect(result.undoError, isNull);
          expect(result.currentRow!['title'], 'AX');
          expect(session.prepare().committed, isTrue);
          final receipt = result.receipt!;
          failRenewal = false;
          final retry = await command.save(
            fields: {},
            tags: ['different'],
            observedTagRefs: {},
          );
          expect(retry.receipt!.raw, receipt.raw);
          expect(retry.status, TextSaveStatus.saved);
          expect(session.frozen, isFalse);
        },
      );

      test('native Save rejects whole-string fields', () async {
        final fixture = await _Fixture.open();
        addTearDown(fixture.close);
        final session = await fixture.session();
        await expectLater(
          TextSaveCommand(fixture.store, session).save(
            fields: {'title': 'replacement'},
            tags: ['old'],
            observedTagRefs: fixture.tagRefs,
          ),
          throwsArgumentError,
        );
        expect(fixture.row['title'], 'A');
        expect(session.frozen, isFalse);
      });
    },
    skip: _libraryPath == null
        ? 'Set TANDEMLOG_TEXT_LIBRARY for actual native Save acceptance.'
        : false,
  );
}

class _Fixture {
  _Fixture(this.root, this.engine, this.folder, this.store, this.task);
  final Directory root;
  final NativeTextEngine engine;
  final _AppendFolder folder;
  final TaskStore store;
  final String task;
  final sessions = <TaskTextSession>[];
  Map<String, dynamic> get row =>
      store.rows.singleWhere((row) => row['id'] == task);
  Map<String, String> get tagRefs =>
      Map<String, String>.from(row['tagRefs'] as Map);
  static Future<_Fixture> open() async {
    final root = await Directory.systemTemp.createTemp('text-save-command-');
    final engine = NativeTextEngine(libraryPath: _libraryPath);
    final shared = await Directory('${root.path}/shared').create();
    final folder = _AppendFolder(LocalLogFolder(shared.path));
    final store = await TaskStore.open(
      folder,
      '${root.path}/profile',
      textEngine: engine,
    );
    final user = const Uuid().v4(), task = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(task, 'task.createdWithText', {
      'title': 'A',
      'description': '',
      'assignee': user,
      'tags': ['old'],
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256.convert(engine.seedText('A').bytes).toString(),
          'description': sha256.convert(engine.seedText('').bytes).toString(),
        },
      },
    });
    return _Fixture(root, engine, folder, store, task);
  }

  Future<TaskTextSession> session() async {
    final capture = await store.captureTaskText(task);
    final session = TaskTextSession(
      capture,
      registerDraftActor: (field, allocation, actor) =>
          store.registerTextDraftActor(capture, field, allocation, actor),
    );
    sessions.add(session);
    return session;
  }

  Future<void> close() async {
    for (final session in sessions) {
      if (!session.hasPendingReceipt) session.cancel();
    }
    await store.close();
    engine.dispose();
    await root.delete(recursive: true);
  }
}

class _AppendFolder implements LogFolder, RangeLogFolder {
  _AppendFolder(this.inner);
  final LocalLogFolder inner;
  bool failNext = false, throwAfterWriting = false;
  void Function()? beforeAppend;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      inner.readFrom(name, offset);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    beforeAppend?.call();
    if (failNext) {
      failNext = false;
      if (throwAfterWriting) await inner.append(name, bytes);
      throw FolderAccessFailure('Synthetic unknown append outcome');
    }
    await inner.append(name, bytes);
  }
}
