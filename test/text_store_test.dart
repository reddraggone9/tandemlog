import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_context.dart';
import 'package:tandemlog/domain/text_actor.dart';

final _libraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];

void main() {
  group(
    'actual native TaskStore',
    () {
      test(
        'successive closed-editor replacements Undo without duplicating restored identities',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-undo-replacements-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final shared = await Directory('${root.path}/shared').create();
            final folder = LocalLogFolder(shared.path);
            final profile = '${root.path}/profile';
            store = await TaskStore.open(folder, profile, textEngine: engine);
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'Review household supplies'),
            );
            final receipts = <OperationReceipt>[];
            for (final title in [
              'Check household supplies',
              'Plan household supplies',
            ]) {
              final capture = await store.captureTaskText(task),
                  field = capture.fields['title']!;
              final draft = field.document.captureDraft(
                actorClientId: field.actor,
              )..replaceText(title);
              final prepared = draft.prepareSave();
              OperationReceipt? receipt;
              await store.editNativeTask(task, {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': prepared.update.encoded,
                },
              }, onPrepared: (value) => receipt = value);
              prepared.commit(receiptUpdate: prepared.update);
              store.registerTextOperation(receipt!, capture);
              receipts.add(receipt!);
              draft.cancel();
              store.releaseTextCapture(capture);
            }
            for (final (receipt, expected) in [
              (receipts.last, 'Check household supplies'),
              (receipts.first, 'Review household supplies'),
            ]) {
              final result = await store.undoOperations([receipt.id]);
              expect(
                result.remaining,
                isEmpty,
                reason: result.error?.toString(),
              );
              expect(
                store.rows.singleWhere((row) => row['id'] == task)['title'],
                expected,
              );
              store.releaseTextOperations([receipt.id]);
            }
            // After all original history owners are released, new editors
            // must still acknowledge and retain their own scoped Undo.
            for (var cycle = 0; cycle < 8; cycle++) {
              final capture = await store.captureTaskText(task),
                  field = capture.fields['title']!;
              final draft = field.document.captureDraft(
                actorClientId: field.actor,
              )..replaceText('Local edited supplies $cycle');
              final prepared = draft.prepareSave();
              OperationReceipt? receipt;
              await store.editNativeTask(task, {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': prepared.update.encoded,
                },
              }, onPrepared: (value) => receipt = value);
              prepared.commit(receiptUpdate: prepared.update);
              store.registerTextOperation(receipt!, capture);
              draft.cancel();
              store.releaseTextCapture(capture);
              final undone = await store.undoOperations([receipt!.id]);
              expect(
                undone.remaining,
                isEmpty,
                reason: undone.error?.toString(),
              );
              store.releaseTextOperations([receipt!.id]);
              expect(
                store.rows.singleWhere((row) => row['id'] == task)['title'],
                'Review household supplies',
              );
            }
            final canonical = await File(
              '${shared.path}/${store.writer}.jsonl',
            ).readAsBytes();
            await store.close();
            store = await TaskStore.open(folder, profile, textEngine: engine);
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'Review household supplies',
            );
            expect(store.readFiles, 0);
            expect(
              await File('${shared.path}/${store.writer}.jsonl').readAsBytes(),
              canonical,
            );
            await store.close();
            store = await TaskStore.open(
              folder,
              '${root.path}/rebuilt',
              textEngine: engine,
            );
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'Review household supplies',
            );
            expect(
              await File(
                '${shared.path}/${receipts.first.id.split(':').first}.jsonl',
              ).readAsBytes(),
              canonical,
            );
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'acknowledged unregistered Save blocks stale native Undo without appending',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-undo-registration-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final shared = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'A'),
            );
            final captures = <TaskTextCapture>[];
            final receipts = <OperationReceipt>[];
            for (final text in ['AX', 'AXY']) {
              final capture = await store.captureTaskText(task),
                  field = capture.fields['title']!;
              final draft = field.document.captureDraft(
                actorClientId: field.actor,
              )..replaceText(text);
              final prepared = draft.prepareSave();
              OperationReceipt? receipt;
              await store.editNativeTask(task, {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': prepared.update.encoded,
                },
              }, onPrepared: (value) => receipt = value);
              prepared.commit(receiptUpdate: prepared.update);
              if (receipts.isEmpty) {
                store.registerTextOperation(receipt!, capture);
              }
              captures.add(capture);
              receipts.add(receipt!);
            }
            final log = File('${shared.path}/${store.writer}.jsonl');
            final before = await log.readAsBytes();
            final blocked = await store.undoOperations([receipts.first.id]);
            expect(blocked.remaining, [receipts.first.id]);
            expect(blocked.error.toString(), contains('Undo registration'));
            expect(await log.readAsBytes(), before);
            expect(store.pendingTextOperations, isEmpty);
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'AXY',
            );
            store.registerTextOperation(receipts.last, captures.last);
            for (final receipt in receipts.reversed) {
              final undone = await store.undoOperations([receipt.id]);
              expect(
                undone.remaining,
                isEmpty,
                reason: undone.error?.toString(),
              );
            }
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'A',
            );
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'mixed native ordering survives warm reopen and canonical rebuild',
        () async {
          final root = await Directory.systemTemp.createTemp('text-order-');
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final shared = await Directory('${root.path}/shared').create();
            final folder = LocalLogFolder(shared.path);
            final profile = '${root.path}/profile';
            store = await TaskStore.open(folder, profile, textEngine: engine);
            final user = const Uuid().v4(),
                legacy = const Uuid().v4(),
                native = const Uuid().v4(),
                later = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(legacy, 'task.created', {
              'title': 'Legacy',
              'description': '',
              'assignee': user,
            });
            await store.command(
              native,
              'task.createdWithText',
              _creationData(engine, user, 'Native'),
            );
            await store.moveBefore(legacy, null);
            await store.command(
              later,
              'task.createdWithText',
              _creationData(engine, user, 'Later'),
            );
            List<String> order() => store!.rows
                .where((row) => row['kind'] == 'task')
                .map((row) => row['id'] as String)
                .toList();
            expect(order(), [native, legacy, later]);
            final canonical = await File(
              '${shared.path}/${store.writer}.jsonl',
            ).readAsBytes();
            // Simulate the prior isolated projection: native creations were
            // appended after moves. Repair only disposable positions, using
            // cached canonical events, without replaying shared log contents.
            store.db.execute('UPDATE positions SET rank=1 WHERE id=?', [
              legacy,
            ]);
            store.db.execute('UPDATE positions SET rank=2 WHERE id=?', [
              native,
            ]);
            store.db.execute('UPDATE positions SET rank=3 WHERE id=?', [later]);
            store.db.execute(
              "UPDATE metadata SET value='2' WHERE key='order_projection'",
            );
            await store.close();
            store = await TaskStore.open(folder, profile, textEngine: engine);
            expect(order(), [native, legacy, later]);
            expect(store.readFiles, 0);
            expect(
              store.db
                  .select(
                    "SELECT value FROM metadata WHERE key='order_projection'",
                  )
                  .single['value'],
              '3',
            );
            await store.close();
            store = await TaskStore.open(
              folder,
              '${root.path}/rebuild',
              textEngine: engine,
            );
            expect(order(), [native, legacy, later]);
            final logs = await shared
                .list()
                .where((entity) => entity.path.endsWith('.jsonl'))
                .toList();
            expect(logs, hasLength(1));
            expect(await File(logs.single.path).readAsBytes(), canonical);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      for (final nativeCreation in [true, false]) {
        test(
          'native recurring completion refuses before receipt (native creation: $nativeCreation)',
          () async {
            final root = await Directory.systemTemp.createTemp(
              'text-recurring-gate-',
            );
            final engine = NativeTextEngine(libraryPath: _libraryPath);
            TaskStore? store;
            try {
              final shared = await Directory('${root.path}/shared').create();
              store = await TaskStore.open(
                LocalLogFolder(shared.path),
                '${root.path}/profile',
                textEngine: engine,
              );
              final user = const Uuid().v4(), task = const Uuid().v4();
              await store.command(user, 'user.created', {'name': 'Synthetic'});
              final data = _creationData(engine, user, 'Recurring')
                ..['schedule'] = {
                  'dueDate': '2030-05-10',
                  'recurrence': 'every day',
                };
              if (!nativeCreation) data.remove('text');
              await store.command(
                task,
                nativeCreation ? 'task.createdWithText' : 'task.created',
                data,
              );
              if (!nativeCreation) await store.initializeSharedText();
              expect(
                store.db.select('SELECT 1 FROM text_fields WHERE entity=?', [
                  task,
                ]),
                isNotEmpty,
              );
              final log = File('${shared.path}/${store.writer}.jsonl');
              final before = await log.readAsBytes();
              final snapshot = store.taskSnapshot;
              final eventCount = store.db
                  .select('SELECT COUNT(*) AS n FROM events')
                  .single['n'];
              var prepared = false;
              await expectLater(
                store.complete(
                  task,
                  completionDay: DateTime(2030, 5, 10),
                  onPrepared: (_) => prepared = true,
                ),
                throwsA(
                  isA<FormatFailure>().having(
                    (error) => error.toString(),
                    'reason',
                    contains(
                      'Collaborative recurring completion is not available yet; existing history is retained.',
                    ),
                  ),
                ),
              );
              expect(prepared, isFalse);
              expect(await log.readAsBytes(), before);
              expect(store.taskSnapshot, snapshot);
              expect(
                store.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
                eventCount,
              );
              expect(store.pendingTextOperations, isEmpty);
            } finally {
              store?.close();
              await root.delete(recursive: true);
            }
          },
        );
      }
      test(
        'repeated cancelled editors release source documents while saved scoped Undo survives',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-capture-release-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(dir.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'AB'),
            );
            final savedCapture = await store.captureTaskText(task),
                field = savedCapture.fields['title']!;
            final draft = field.document.captureDraft(
                  actorClientId: field.actor,
                )..replaceText('A'),
                save = draft.prepareSave();
            OperationReceipt? receipt;
            await store.editNativeTask(task, {
              'title': {
                'context': field.context,
                'allocation': field.allocation,
                'actor': field.actor,
                'update': save.update.encoded,
              },
            }, onPrepared: (value) => receipt = value);
            save.commit(receiptUpdate: save.update);
            store.registerTextOperation(receipt!, savedCapture);
            draft.cancel();
            store.releaseTextCapture(savedCapture);
            expect(
              savedCapture.fields.values.every(
                (field) => field.document.isClosed,
              ),
              isTrue,
            );
            for (var i = 0; i < 60; i++) {
              final capture = await store.captureTaskText(task),
                  title = capture.fields['title']!;
              final abandoned = title.document.captureDraft(
                actorClientId: title.actor,
              )..replaceText('Unsaved $i');
              abandoned.cancel();
              store.releaseTextCapture(capture);
              expect(
                capture.fields.values.every((field) => field.document.isClosed),
                isTrue,
              );
            }
            final outcome = await store.undoOperations([receipt!.id]);
            expect(
              outcome.remaining,
              isEmpty,
              reason: outcome.error?.toString(),
            );
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'AB',
            );
            store.releaseTextOperations([receipt!.id]);
            expect(
              store.db.select('SELECT raw FROM events WHERE id=?', [
                receipt!.id,
              ]),
              hasLength(1),
            );
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'native guard ignores remote text while preserving metadata and creation tags',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-native-guard-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create(),
                folder = LocalLogFolder(dir.path);
            store = await TaskStore.open(
              folder,
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            final creation = await store.command(task, 'task.createdWithText', {
              ..._creationData(engine, user, 'A'),
              'tags': ['Initial'],
            });
            final context = TextFieldContext.fromCreation(
              creation,
              'title',
            ).hash;
            final observed = Map<String, String>.from(
              store.rows.singleWhere((row) => row['id'] == task)['tagRefs']
                  as Map,
            );
            final expected = store.taskSnapshot,
                remoteWriter = const Uuid().v4();
            final remote = LogEvent(
              store.space,
              remoteWriter,
              1,
              EventClock(creation.clock.value + BigInt.from(10)),
              task,
              'task.textEdited',
              {
                'changes': {
                  'title': _packet(engine, 'A', context, remoteWriter, 'AR'),
                },
              },
            );
            await folder.create(
              '$remoteWriter.jsonl',
              Uint8List.fromList('${remote.encode()}\n'.codeUnits),
            );
            await store.refresh();
            await store.editNativeTask(
              task,
              {'title': _packet(engine, 'A', context, store.writer, 'AL')},
              nonText: {'tagChanges': calculateTaskTagChanges([], observed)},
              expectedSnapshot: expected,
              canCommit: () => true,
            );
            final row = store.rows.singleWhere((row) => row['id'] == task);
            expect((row['title'] as String).split('').toSet(), {'A', 'R', 'L'});
            expect(row['tags'], isEmpty);
            final oldSnapshot = store.taskSnapshot;
            await store.command(task, 'task.edited', {
              'schedule': {'dueDate': '2026-10-06'},
            });
            final count = store.db
                .select('SELECT COUNT(*) AS n FROM events')
                .single['n'];
            final changes = {
              'title': _packet(engine, 'A', context, store.writer, 'AZ'),
            };
            await expectLater(
              store.editNativeTask(
                task,
                changes,
                expectedSnapshot: oldSnapshot,
              ),
              throwsA(isA<StaleTaskSnapshot>()),
            );
            await expectLater(
              store.editNativeTask(
                task,
                changes,
                expectedSnapshot: store.taskSnapshot,
                canCommit: () => false,
              ),
              throwsA(isA<StaleTaskSnapshot>()),
            );
            expect(
              store.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
              count,
            );
            expect(store.pendingTextOperations, isEmpty);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'Undo naming remote-deleted latest Save never consumes an older Save',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-undo-noop-regression-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create(),
                folder = LocalLogFolder(dir.path);
            store = await TaskStore.open(
              folder,
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'A'),
            );
            final capture = await store.captureTaskText(task),
                field = capture.fields['title']!;
            final originals = <OperationReceipt>[];
            late LogEvent latest;
            for (final text in ['AX', 'AXY']) {
              final allocation = const Uuid().v4(),
                  actor = deriveTextActor(
                    field.context,
                    store.writer,
                    allocation,
                  );
              store.registerTextDraftActor(capture, 'title', allocation, actor);
              final draft = field.document.captureDraft(actorClientId: actor)
                    ..replaceText(text),
                  save = draft.prepareSave();
              OperationReceipt? receipt;
              latest = await store.editNativeTask(task, {
                'title': {
                  'context': field.context,
                  'allocation': allocation,
                  'actor': actor,
                  'update': save.update.encoded,
                },
              }, onPrepared: (value) => receipt = value);
              save.commit(receiptUpdate: save.update);
              store.registerTextOperation(receipt!, capture);
              draft.cancel();
              originals.add(receipt!);
            }
            final remoteWriter = const Uuid().v4(),
                remoteAllocation = const Uuid().v4(),
                remoteActor = deriveTextActor(
                  field.context,
                  remoteWriter,
                  remoteAllocation,
                );
            final peer = engine.restoreDocument(
              actorClientId: 2,
              limits: const NativeTextLimits(visibleUtf16: 500),
              checkpoint: field.document.checkpoint(),
            );
            late NativeTextUpdate deletion;
            try {
              final draft = peer.captureDraft(actorClientId: remoteActor)
                ..replaceText('AX');
              deletion = draft.prepareSave().update;
            } finally {
              peer.dispose();
            }
            final remote = LogEvent(
              store.space,
              remoteWriter,
              1,
              EventClock(latest.clock.value + BigInt.from(10)),
              task,
              'task.textEdited',
              {
                'changes': {
                  'title': {
                    'context': field.context,
                    'allocation': remoteAllocation,
                    'actor': remoteActor,
                    'update': deletion.encoded,
                  },
                },
              },
            );
            await folder.create(
              '$remoteWriter.jsonl',
              Uint8List.fromList('${remote.encode()}\n'.codeUnits),
            );
            await store.refresh();
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'AX',
            );
            final result = await store.undoOperations([originals.last.id]);
            expect(result.remaining, isEmpty, reason: result.error?.toString());
            expect(result.keptNewerChanges, isTrue);
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'AX',
            );
            expect(field.document.read().text, 'AX');
            final older = await store.undoOperations([originals.first.id]);
            expect(older.remaining, isEmpty, reason: older.error?.toString());
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'A',
            );
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      for (final restart in [false, true]) {
        test(
          'unknown native Undo preserves exact compensation retry restart=$restart',
          () async {
            final root = await Directory.systemTemp.createTemp(
              'text-undo-intent-',
            );
            final engine = NativeTextEngine(libraryPath: _libraryPath);
            TaskStore? store;
            try {
              final dir = await Directory('${root.path}/shared').create(),
                  profile = '${root.path}/profile';
              final folder = _UnknownAppendFolder(LocalLogFolder(dir.path));
              store = await TaskStore.open(folder, profile, textEngine: engine);
              final user = const Uuid().v4(), task = const Uuid().v4();
              await store.command(user, 'user.created', {'name': 'Synthetic'});
              await store.command(
                task,
                'task.createdWithText',
                _creationData(engine, user, 'AB'),
              );
              final capture = await store.captureTaskText(task),
                  field = capture.fields['title']!;
              final draft = field.document.captureDraft(
                    actorClientId: field.actor,
                  )..replaceText('A'),
                  save = draft.prepareSave();
              OperationReceipt? original;
              await store.editNativeTask(task, {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': save.update.encoded,
                },
              }, onPrepared: (receipt) => original = receipt);
              save.commit(receiptUpdate: save.update);
              store.registerTextOperation(original!, capture);
              draft.cancel();
              folder.failNext = true;
              final uncertain = await store.undoOperations([original!.id]);
              expect(uncertain.remaining, [original!.id]);
              expect(field.document.read().text, 'A');
              final prepared = store.pendingTextOperations.single;
              expect(LogEvent.decode(prepared.raw).type, 'task.textEditUndone');
              if (restart) {
                await store.close();
                await File('$profile/cache.sqlite').delete();
                store = await TaskStore.open(
                  folder,
                  profile,
                  textEngine: engine,
                );
                expect(store.pendingTextOperations.single.raw, prepared.raw);
                final replay = await store.retryTextOperation(
                  store.pendingTextOperations.single,
                );
                expect(replay.canonicalRaw, prepared.raw);
              } else {
                final outcome = await store.undoOperations([original!.id]);
                expect(
                  outcome.remaining,
                  isEmpty,
                  reason: outcome.error?.toString(),
                );
                expect(field.document.read().text, 'AB');
              }
              expect(
                store.rows.singleWhere((row) => row['id'] == task)['title'],
                'AB',
              );
              expect(store.pendingTextOperations, isEmpty);
              expect(
                store.db.select('SELECT raw FROM events WHERE id=?', [
                  prepared.id,
                ]).single['raw'],
                prepared.raw,
              );
            } finally {
              await store?.close();
              engine.dispose();
              await root.delete(recursive: true);
            }
          },
        );
      }
      test(
        'session Undo survives editor close and touches only canonical changed fields',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-global-undo-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(dir.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'AB'),
            );
            final capture = await store.captureTaskText(task),
                field = capture.fields['title']!;
            final draft = field.document.captureDraft(
              actorClientId: field.actor,
            )..replaceText('A');
            final save = draft.prepareSave();
            OperationReceipt? receipt;
            await store.editNativeTask(
              task,
              {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': save.update.encoded,
                },
              },
              nonText: {
                'tagChanges': {
                  'add': ['Local'],
                  'remove': [],
                },
              },
              onPrepared: (value) => receipt = value,
            );
            save.commit(receiptUpdate: save.update);
            store.registerTextOperation(receipt!, capture);
            draft.cancel();
            final allocation = const Uuid().v4(),
                actor = deriveTextActor(
                  field.context,
                  store.writer,
                  allocation,
                );
            store.registerTextDraftActor(capture, 'title', allocation, actor);
            final nextDraft = field.document.captureDraft(actorClientId: actor)
                  ..replaceText('AC'),
                nextSave = nextDraft.prepareSave();
            OperationReceipt? nextReceipt;
            await store.editNativeTask(task, {
              'title': {
                'context': field.context,
                'allocation': allocation,
                'actor': actor,
                'update': nextSave.update.encoded,
              },
            }, onPrepared: (value) => nextReceipt = value);
            nextSave.commit(receiptUpdate: nextSave.update);
            store.registerTextOperation(nextReceipt!, capture);
            nextDraft.cancel();
            final wrongOrder = await store.undoOperations([receipt!.id]);
            expect(wrongOrder.remaining, [receipt!.id]);
            expect(field.document.read().text, 'AC');
            final latest = await store.undoOperations([nextReceipt!.id]);
            expect(latest.remaining, isEmpty, reason: latest.error?.toString());
            expect(field.document.read().text, 'A');
            final outcome = await store.undoOperations([receipt!.id]);
            expect(
              outcome.remaining,
              isEmpty,
              reason: outcome.error?.toString(),
            );
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'AB',
            );
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['tags'],
              isEmpty,
            );
            expect(capture.fields['description']!.document.read().text, '');
            expect(
              store.db.select(
                "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.textEditUndone'",
              ),
              hasLength(2),
            );
            final replay = await store.undoOperations([receipt!.id]);
            expect(replay.remaining, isEmpty);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'bulk capture with native engine creates independently editable native tasks',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'native-bulk-create-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(dir.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            final titles = {
              const Uuid().v4(): 'First offline',
              const Uuid().v4(): 'Second offline',
            };
            final result = await store.createTasks(titles, user);
            expect(result.succeeded, isTrue, reason: result.error?.toString());
            expect(
              store.db.select(
                "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='task.createdWithText'",
              ),
              hasLength(2),
            );
            for (final task in titles.keys) {
              final capture = await store.captureTaskText(task);
              expect(
                capture.fields['title']!.document.read().text,
                titles[task],
              );
            }
            expect(store.sharedTextInitialized, isFalse);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'native compensation restores deletion and retracts only original nontext effects',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-compensation-store-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(dir.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'AB'),
            );
            final capture = await store.captureTaskText(task),
                field = capture.fields['title']!;
            final draft = field.document.captureDraft(
              actorClientId: field.actor,
            )..replaceText('A');
            final save = draft.prepareSave();
            final original = await store.editNativeTask(
              task,
              {
                'title': {
                  'context': field.context,
                  'allocation': field.allocation,
                  'actor': field.actor,
                  'update': save.update.encoded,
                },
              },
              nonText: {
                'schedule': {'dueDate': '2026-10-05'},
                'tagChanges': {
                  'add': ['Local'],
                  'remove': [],
                },
              },
            );
            save.commit(receiptUpdate: save.update);
            await store.command(task, 'task.edited', {
              'schedule': {'dueDate': '2026-11-01'},
            });
            final undo = field.document.prepareUndo();
            final compensation = await store.command(
              task,
              'task.textEditUndone',
              {
                'operation': original.id,
                'changes': {
                  'title': {
                    'context': field.context,
                    'allocation': field.undoAllocation,
                    'actor': field.undoActor,
                    'update': undo.update.encoded,
                  },
                },
              },
            );
            undo.commit(receiptUpdate: undo.update);
            final row = store.rows.singleWhere((row) => row['id'] == task);
            expect(row['title'], 'AB');
            expect(row['tags'], isEmpty);
            expect((row['schedule'] as Map)['dueDate'], '2026-11-01');
            expect(field.document.read().text, 'AB');
            expect(
              store.db.select('SELECT raw FROM events WHERE id IN (?,?)', [
                original.id,
                compensation.id,
              ]),
              hasLength(2),
            );
            await expectLater(
              store.command(task, 'task.operationUndone', {
                'operation': original.id,
              }),
              throwsA(isA<FormatFailure>()),
            );
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'buffered native dependency survives full SQLite cache loss and settles on late parent',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-native-pending-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final dir = await Directory('${root.path}/shared').create();
            final folder = LocalLogFolder(dir.path),
                profile = '${root.path}/profile';
            store = await TaskStore.open(folder, profile, textEngine: engine);
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            final creation = await store.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'A'),
            );
            final context = TextFieldContext.fromCreation(
              creation,
              'title',
            ).hash;
            final wa = const Uuid().v4(), wb = const Uuid().v4();
            final packetA = _packet(engine, 'A', context, wa, 'AB');
            final allocationB = const Uuid().v4(),
                actorB = deriveTextActor(context, wb, allocationB);
            final source = engine.createDocument(
              actorClientId: 2,
              limits: const NativeTextLimits(visibleUtf16: 500),
              seed: engine.seedText('A'),
            );
            late final Map<String, dynamic> packetB;
            try {
              source.applyRemote(NativeTextUpdate.parse(packetA['update']));
              final draft = source.captureDraft(actorClientId: actorB)
                ..replaceText('ABC');
              packetB = {
                'context': context,
                'allocation': allocationB,
                'actor': actorB,
                'update': draft.prepareSave().update.encoded,
              };
            } finally {
              source.dispose();
            }
            final ea = LogEvent(
              store.space,
              wa,
              1,
              EventClock(creation.clock.value + BigInt.from(10)),
              task,
              'task.textEdited',
              {
                'changes': {'title': packetA},
              },
            );
            final eb = LogEvent(
              store.space,
              wb,
              1,
              EventClock(creation.clock.value + BigInt.from(20)),
              task,
              'task.textEdited',
              {
                'changes': {'title': packetB},
              },
            );
            await folder.create(
              '$wb.jsonl',
              Uint8List.fromList('${eb.encode()}\n'.codeUnits),
            );
            await store.refresh();
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'A',
            );
            await expectLater(
              store.captureTaskText(task),
              throwsA(isA<FormatFailure>()),
            );
            await store.close();
            await File('$profile/cache.sqlite').delete();
            store = await TaskStore.open(folder, profile, textEngine: engine);
            await expectLater(
              store.captureTaskText(task),
              throwsA(isA<FormatFailure>()),
            );
            await folder.create(
              '$wa.jsonl',
              Uint8List.fromList('${ea.encode()}\n'.codeUnits),
            );
            await store.refresh();
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'ABC',
            );
            final capture = await store.captureTaskText(task);
            expect(capture.fields['title']!.document.read().pending, isFalse);
            expect(capture.fields['title']!.document.read().text, 'ABC');
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'missing baseline prefixes stay pending and competing roots block only legacy text',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-baseline-dependencies-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? a, b, c;
          try {
            final da = await Directory('${root.path}/a').create(),
                db = await Directory('${root.path}/b').create(),
                dc = await Directory('${root.path}/c').create();
            a = await TaskStore.open(
              LocalLogFolder(da.path),
              '${root.path}/pa',
              textEngine: engine,
            );
            for (final dir in [db, dc]) {
              await File(
                '${da.path}/tandemlog-space.json',
              ).copy('${dir.path}/tandemlog-space.json');
            }
            final user = const Uuid().v4(), task = const Uuid().v4();
            await a.command(user, 'user.created', {'name': 'Synthetic'});
            await a.command(task, 'task.created', {
              'title': 'Shared legacy basis',
              'description': '',
              'assignee': user,
            });
            await File(
              '${da.path}/${a.writer}.jsonl',
            ).copy('${db.path}/${a.writer}.jsonl');
            b = await TaskStore.open(
              LocalLogFolder(db.path),
              '${root.path}/pb',
              textEngine: engine,
            );
            final baseline = await b.initializeSharedText();
            await expectLater(
              b.initializeSharedText(),
              throwsA(isA<FormatFailure>()),
            );
            await File(
              '${db.path}/${b.writer}.jsonl',
            ).copy('${dc.path}/${b.writer}.jsonl');
            c = await TaskStore.open(
              LocalLogFolder(dc.path),
              '${root.path}/pc',
              textEngine: engine,
            );
            expect(c.sharedTextInitialized, isFalse);
            expect(c.textWriteBlocked, contains('waiting'));
            expect(c.rows, isEmpty);
            await File(
              '${da.path}/${a.writer}.jsonl',
            ).copy('${dc.path}/${a.writer}.jsonl');
            await c.refresh();
            expect(c.sharedTextInitialized, isTrue);
            expect(
              c.rows.singleWhere((row) => row['id'] == task)['title'],
              'Shared legacy basis',
            );
            final lateTask = const Uuid().v4();
            await c.command(lateTask, 'task.created', {
              'title': 'Late old creation',
              'description': '',
              'assignee': user,
            });
            await c.command(lateTask, 'task.edited', {
              'title': 'Late scalar overwrite',
            });
            expect(
              c.rows.singleWhere((row) => row['id'] == lateTask)['title'],
              'Late old creation',
            );
            final competitor = const Uuid().v4();
            final second = LogEvent(
              c.space,
              competitor,
              1,
              EventClock(baseline.clock.value + BigInt.from(100)),
              c.space,
              'text.baselineInitialized',
              baseline.data,
            );
            await LocalLogFolder(dc.path).create(
              '$competitor.jsonl',
              Uint8List.fromList('${second.encode()}\n'.codeUnits),
            );
            await c.refresh();
            expect(c.textWriteBlocked, contains('Competing'));
            expect(
              c.rows.singleWhere((row) => row['id'] == task)['title'],
              'Shared legacy basis',
            );
            await expectLater(
              c.captureTaskText(task),
              throwsA(isA<FormatFailure>()),
            );
            final nativeTask = const Uuid().v4();
            await c.command(
              nativeTask,
              'task.createdWithText',
              _creationData(engine, user, 'Independent native'),
            );
            final captured = await c.captureTaskText(nativeTask);
            expect(
              captured.fields['title']!.document.read().text,
              'Independent native',
            );
            expect(
              c.db.select(
                "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='text.baselineInitialized'",
              ),
              hasLength(2),
            );
            await c.close();
            await File('${root.path}/pc/cache.sqlite').delete();
            c = await TaskStore.open(
              LocalLogFolder(dc.path),
              '${root.path}/pc',
              textEngine: engine,
            );
            expect(
              c.rows.singleWhere((row) => row['id'] == task)['textUnavailable'],
              contains('Competing'),
            );
            expect(
              c.rows.singleWhere((row) => row['id'] == nativeTask)['title'],
              'Independent native',
            );
            expect(
              c.rows
                  .singleWhere((row) => row['id'] == nativeTask)
                  .containsKey('textUnavailable'),
              isFalse,
            );
            await expectLater(
              c.command(task, 'task.edited', {
                'title': 'Forbidden local scalar fallback',
              }),
              throwsA(isA<FormatFailure>()),
            );
            await c.command(task, 'task.edited', {
              'schedule': {'dueDate': '2026-11-01'},
            });
            expect(
              (c.rows.singleWhere((row) => row['id'] == task)['schedule']
                  as Map)['dueDate'],
              '2026-11-01',
            );
          } finally {
            await a?.close();
            await b?.close();
            await c?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'offline peers merge owned packets and preserve atomic metadata after cache loss',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-peer-store-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? a, b;
          try {
            final aDir = await Directory('${root.path}/a').create();
            final bDir = await Directory('${root.path}/b').create();
            a = await TaskStore.open(
              LocalLogFolder(aDir.path),
              '${root.path}/pa',
              textEngine: engine,
            );
            await File(
              '${aDir.path}/tandemlog-space.json',
            ).copy('${bDir.path}/tandemlog-space.json');
            b = await TaskStore.open(
              LocalLogFolder(bDir.path),
              '${root.path}/pb',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await a.command(user, 'user.created', {'name': 'Synthetic'});
            final creation = await a.command(
              task,
              'task.createdWithText',
              _creationData(engine, user, 'A'),
            );
            await File(
              '${aDir.path}/${a.writer}.jsonl',
            ).copy('${bDir.path}/${a.writer}.jsonl');
            await b.refresh();
            final context = TextFieldContext.fromCreation(
              creation,
              'title',
            ).hash;
            final packetA = _packet(engine, 'A', context, a.writer, 'AB');
            final packetB = _packet(engine, 'A', context, b.writer, 'AC');
            await a.command(task, 'task.textEdited', {
              'changes': {'title': packetA},
              'tagChanges': {
                'add': ['From A'],
                'remove': [],
              },
              'schedule': {'dueDate': '2026-10-05'},
            });
            await b.command(task, 'task.textEdited', {
              'changes': {'title': packetB},
            });
            await File(
              '${aDir.path}/${a.writer}.jsonl',
            ).copy('${bDir.path}/${a.writer}.jsonl');
            await File(
              '${bDir.path}/${b.writer}.jsonl',
            ).copy('${aDir.path}/${b.writer}.jsonl');
            await a.refresh();
            await b.refresh();
            expect(a.rows, b.rows);
            final row = a.rows.singleWhere((row) => row['id'] == task);
            expect((row['title'] as String).split('').toSet(), {'A', 'B', 'C'});
            expect(row['tags'], ['From A']);
            expect((row['schedule'] as Map)['dueDate'], '2026-10-05');
            expect(await a.refresh(), isFalse);
            expect(await b.refresh(), isFalse);
            final before = b.rows;
            b.db.execute(
              'UPDATE text_fields SET frontier=? WHERE entity=? AND field=?',
              ['invalid disposable JSON', task, 'title'],
            );
            await b.command(task, 'task.edited', {
              'description': 'Excluded scalar on native task',
            });
            expect(b.rows, before);
            await b.close();
            await File('${root.path}/pb/cache.sqlite').delete();
            b = await TaskStore.open(
              LocalLogFolder(bDir.path),
              '${root.path}/pb',
              textEngine: engine,
            );
            expect(b.rows, before);
            final count = a.db
                .select('SELECT COUNT(*) AS n FROM events')
                .single['n'];
            final wrong = _packet(engine, 'A', '0' * 64, a.writer, 'AD');
            await expectLater(
              a.command(task, 'task.textEdited', {
                'changes': {'title': wrong},
              }),
              throwsA(isA<FormatFailure>()),
            );
            expect(
              a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
              count,
            );
            expect(a.rows, before);
            final forgedAllocation = const Uuid().v4();
            final forged = {
              'context': context,
              'allocation': forgedAllocation,
              'actor': deriveTextActor(context, a.writer, forgedAllocation),
              'update': engine.seedText('Unowned seed actor').encoded,
            };
            await expectLater(
              a.command(task, 'task.textEdited', {
                'changes': {'title': forged},
                'schedule': {'dueDate': '2026-12-01'},
              }),
              throwsA(isA<FormatFailure>()),
            );
            expect(
              a.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
              count,
            );
            expect(a.rows, before);
          } finally {
            await a?.close();
            await b?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'one legacy baseline excludes late scalar text and preserves nontext changes',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'text-baseline-store-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final shared = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4(), task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            final creation = await store.command(task, 'task.created', {
              'title': 'Legacy basis',
              'description': 'Notes',
              'assignee': user,
            });
            final digest = textBaselineSeedDigest({
              task: {
                'title': sha256
                    .convert(engine.seedText('Legacy basis').bytes)
                    .toString(),
                'description': sha256
                    .convert(engine.seedText('Notes').bytes)
                    .toString(),
              },
            });
            final baseline = await store.command(
              store.space,
              'text.baselineInitialized',
              {
                'codec': 'yrs-v1',
                'adapter': 1,
                'frontiers': {
                  store.writer: {
                    'seq': creation.sequence,
                    'hash': creation.hash,
                  },
                },
                'seedDigest': digest,
              },
            );
            expect(store.textWriteBlocked, isNull);
            expect(
              store.db.select('SELECT * FROM text_fields WHERE entity=?', [
                task,
              ]),
              hasLength(2),
            );
            await store.command(task, 'task.edited', {
              'title': 'Excluded late legacy value',
              'description': 'Excluded notes',
              'schedule': {'dueDate': '2026-10-05'},
              'tagChanges': {
                'add': ['Late metadata'],
                'remove': [],
              },
            });
            final row = store.rows.singleWhere((row) => row['id'] == task);
            expect(row['title'], 'Legacy basis');
            expect(row['description'], 'Notes');
            expect((row['schedule'] as Map)['dueDate'], '2026-10-05');
            expect(row['tags'], ['Late metadata']);
            expect(
              store.db.select('SELECT raw FROM events WHERE id=?', [
                baseline.id,
              ]).single['raw'],
              baseline.canonicalRaw,
            );
            final before = store.rows;
            await store.close();
            await File('${root.path}/profile/cache.sqlite').delete();
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            expect(store.rows, before);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      for (final (cacheLoss, afterAppend) in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ]) {
        test(
          'unknown append exact receipt after restart cacheLoss=$cacheLoss afterAppend=$afterAppend',
          () async {
            final root = await Directory.systemTemp.createTemp(
              'text-intent-retry-',
            );
            final engine = NativeTextEngine(libraryPath: _libraryPath);
            TaskStore? store;
            try {
              final shared = await Directory('${root.path}/shared').create();
              final folder = _UnknownAppendFolder(LocalLogFolder(shared.path));
              final profile = '${root.path}/profile';
              store = await TaskStore.open(folder, profile, textEngine: engine);
              final user = const Uuid().v4();
              await store.command(user, 'user.created', {'name': 'Synthetic'});
              final task = const Uuid().v4();
              OperationReceipt? prepared;
              folder.failNext = true;
              folder.throwAfterWriting = afterAppend;
              await expectLater(
                store.command(task, 'task.createdWithText', {
                  'title': 'Exact retry',
                  'description': '',
                  'assignee': user,
                  'text': {
                    'codec': 'yrs-v1',
                    'adapter': 1,
                    'seeds': {
                      'title': sha256
                          .convert(engine.seedText('Exact retry').bytes)
                          .toString(),
                      'description': sha256
                          .convert(engine.seedText('').bytes)
                          .toString(),
                    },
                  },
                }, onPrepared: (receipt) => prepared = receipt),
                throwsA(isA<FolderAccessFailure>()),
              );
              expect(prepared, isNotNull);
              expect(store.pendingTextOperations.single.raw, prepared!.raw);
              await store.close();
              if (cacheLoss) await File('$profile/cache.sqlite').delete();
              store = await TaskStore.open(folder, profile, textEngine: engine);
              if (afterAppend) {
                expect(store.pendingTextOperations, isEmpty);
              } else {
                expect(store.pendingTextOperations.single.raw, prepared!.raw);
              }
              final event = await store.retryTextOperation(prepared!);
              expect(event.canonicalRaw, prepared!.raw);
              expect(store.pendingTextOperations, isEmpty);
              expect(
                await Directory('$profile/text-intents').list().toList(),
                isEmpty,
              );
              expect(
                store.rows.singleWhere((row) => row['id'] == task)['title'],
                'Exact retry',
              );
            } finally {
              await store?.close();
              engine.dispose();
              await root.delete(recursive: true);
            }
          },
        );
      }
      test(
        'new native creation verifies actor1 seed and persists full native state',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'native-create-store-',
          );
          final engine = NativeTextEngine(libraryPath: _libraryPath);
          TaskStore? store;
          try {
            final shared = await Directory('${root.path}/shared').create();
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            final user = const Uuid().v4();
            final task = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            final data = <String, dynamic>{
              'title': 'Offline creation',
              'description': 'Notes',
              'assignee': user,
              'text': {
                'codec': 'yrs-v1',
                'adapter': 1,
                'seeds': {
                  'title': sha256
                      .convert(engine.seedText('Offline creation').bytes)
                      .toString(),
                  'description': sha256
                      .convert(engine.seedText('Notes').bytes)
                      .toString(),
                },
              },
            };
            await store.command(task, 'task.createdWithText', data);
            expect(
              store.rows.singleWhere((row) => row['id'] == task)['title'],
              'Offline creation',
            );
            expect(
              store.db.select('SELECT * FROM text_fields WHERE entity=?', [
                task,
              ]),
              hasLength(2),
            );
            expect(store.pendingTextOperations, isEmpty);
            final before = store.rows;
            await store.close();
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            expect(store.readFiles, 0);
            expect(store.rows, before);
            final invalid = const Uuid().v4();
            final bad = <String, dynamic>{
              ...data,
              'text': {
                'codec': 'yrs-v1',
                'adapter': 1,
                'seeds': {
                  'title': '0' * 64,
                  'description': (data['text'] as Map)['seeds']['description'],
                },
              },
            };
            final previousCount = store.db
                .select('SELECT COUNT(*) AS n FROM events')
                .single['n'];
            await expectLater(
              store.command(invalid, 'task.createdWithText', bad),
              throwsA(isA<Exception>()),
            );
            expect(
              store.db.select('SELECT COUNT(*) AS n FROM events').single['n'],
              previousCount,
            );
            expect(store.pendingTextOperations, isEmpty);
          } finally {
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
      );
      test(
        'native storage extends cache13 without replaying frozen v3 logs',
        () async {
          final root = await Directory.systemTemp.createTemp('text-store-');
          TaskStore? store;
          NativeTextEngine? engine;
          try {
            final shared = await Directory('${root.path}/shared').create();
            for (final source in Directory(
              'test/fixtures/stable-v3-2026.10.0',
            ).listSync().whereType<File>()) {
              if (source.path.endsWith('.jsonl') ||
                  source.path.endsWith('tandemlog-space.json')) {
                await source.copy(
                  '${shared.path}/${source.uri.pathSegments.last}',
                );
              }
            }
            final folder = LocalLogFolder(shared.path);
            final profile = '${root.path}/profile';
            store = await TaskStore.open(folder, profile);
            final before = store.rows;
            await store.close();
            engine = NativeTextEngine(libraryPath: _libraryPath);
            store = await TaskStore.open(folder, profile, textEngine: engine);
            expect(store.rows, before);
            expect(store.readFiles, 0);
            expect(
              store.db.select('PRAGMA user_version').single.values.single,
              14,
            );
            expect(
              store.db.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='text_fields'",
              ),
              hasLength(1),
            );
            expect(store.db.select('SELECT * FROM text_fields'), isEmpty);
          } finally {
            await store?.close();
            engine?.dispose();
            await root.delete(recursive: true);
          }
        },
      );
    },
    skip: _libraryPath == null
        ? 'Set TANDEMLOG_TEXT_LIBRARY for required actual native storage acceptance.'
        : false,
  );
}

Map<String, dynamic> _creationData(
  NativeTextEngine engine,
  String user,
  String title,
) => {
  'title': title,
  'description': '',
  'assignee': user,
  'text': {
    'codec': 'yrs-v1',
    'adapter': 1,
    'seeds': {
      'title': sha256.convert(engine.seedText(title).bytes).toString(),
      'description': sha256.convert(engine.seedText('').bytes).toString(),
    },
  },
};

Map<String, dynamic> _packet(
  NativeTextEngine engine,
  String seed,
  String context,
  String writer,
  String next,
) {
  final allocation = const Uuid().v4();
  final actor = deriveTextActor(context, writer, allocation);
  final source = engine.createDocument(
    actorClientId: 2,
    limits: const NativeTextLimits(visibleUtf16: 500),
    seed: engine.seedText(seed),
  );
  try {
    final draft = source.captureDraft(actorClientId: actor)..replaceText(next);
    return {
      'context': context,
      'allocation': allocation,
      'actor': actor,
      'update': draft.prepareSave().update.encoded,
    };
  } finally {
    source.dispose();
  }
}

class _UnknownAppendFolder implements LogFolder, RangeLogFolder {
  _UnknownAppendFolder(this.inner);
  final LocalLogFolder inner;
  bool failNext = false;
  bool throwAfterWriting = false;
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
    if (failNext) {
      failNext = false;
      if (throwAfterWriting) await inner.append(name, bytes);
      throw FolderAccessFailure('Synthetic unknown append outcome');
    }
    await inner.append(name, bytes);
  }
}
