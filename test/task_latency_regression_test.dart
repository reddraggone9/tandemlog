import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/domain/checklist.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/checklist_expansion_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';
import 'package:sqlite3/sqlite3.dart';

import 'current_history_fixture.dart';

class _ListHookFolder extends LocalLogFolder {
  _ListHookFolder(super.location);
  Future<void> Function()? beforeList;

  @override
  Future<List<LogFileInfo>> list() async {
    await beforeList?.call();
    return super.list();
  }
}

void main() {
  for (final injectPeer in [false, true]) {
    test(
      'completion uses one admitted snapshot; peer race=$injectPeer',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'completion-snapshot-',
        );
        final folder = _ListHookFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        TaskStore? store;
        try {
          store = await TaskStore.open(folder, '${root.path}/profile');
          final current = store;
          final user = const Uuid().v4(), task = const Uuid().v4();
          await current.command(user, 'user.created', {
            'name': 'Synthetic user',
          });
          await current.command(task, 'task.created', {
            'title': 'Original title',
            'description': '',
            'assignee': user,
          });
          final ownedName = '${current.writer}.applog';
          final original = await folder.read(ownedName);
          final sequence = current.unified!.physicalSequence;
          final peer = const Uuid().v4();
          final peerBytes = peerBytesFor(
            current,
            LogEvent(
              current.space,
              peer,
              1,
              EventClock(current.unified!.maximumClock!.value + BigInt.one),
              task,
              'task.edited',
              {
                'schedule': {'dueDate': '2030-05-10'},
              },
            ),
          );
          var lists = 0, callbacks = 0, listsAtReservation = 0;
          folder.beforeList = () async {
            if (++lists == 2 && injectPeer) {
              folder.beforeList = null;
              await folder.create('$peer.applog', peerBytes);
            }
          };
          var samples = 0;
          final operation = current.complete(
            task,
            observeCompletionTime: () {
              samples++;
              expect(lists, 2);
              if (injectPeer) {
                expect(
                  current.visibleTaskRow(task)!['schedule']['dueDate'],
                  '2030-05-10',
                );
              }
              return ViewTime(
                instant: DateTime.utc(2030, 5, 10, 12, 34, 56, 123, 456),
                localZoneId: 'UTC',
                localOffset: Duration.zero,
              );
            },
            onPrepared: (_) {
              callbacks++;
              listsAtReservation = lists;
            },
          );
          final completion = await operation;
          expect(samples, 1);
          expect(
            completion.data['completedInstant'],
            '2030-05-10T12:34:56.123456Z',
          );
          expect(callbacks, 1);
          expect(current.unified!.physicalSequence, sequence + 1);
          expect(current.visibleTaskRow(task)!['completed'], isTrue);
          expect(listsAtReservation, 2);
          expect(
            (await folder.read(ownedName)).take(original.length),
            original,
          );
        } finally {
          await store?.close();
          await root.delete(recursive: true);
        }
      },
    );
  }

  test(
    'native Save builds from one fresh observation, guards stale nontext and retains Undo',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'native-save-refresh-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final folder = _ListHookFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final current = store;
        final user = const Uuid().v4(), task = const Uuid().v4();
        await current.command(user, 'user.created', {'name': 'Synthetic user'});
        expect(
          (await current.createTasks({task: 'Original title'}, user)).succeeded,
          isTrue,
        );
        final capture = await current.captureTaskText(task);
        final field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Saved title');
        final prepared = draft.prepareSave();
        try {
          final changes = {
            'title': {
              'context': field.context,
              'allocation': field.allocation,
              'actor': field.actor,
              'update': prepared.update.encoded,
            },
          };
          final ownedName = '${current.writer}.applog';
          final original = await folder.read(ownedName);
          final sequence = current.unified!.physicalSequence;
          final peer = const Uuid().v4();
          final peerBytes = peerBytesFor(
            current,
            LogEvent(
              current.space,
              peer,
              1,
              EventClock(current.unified!.maximumClock!.value + BigInt.one),
              task,
              'task.edited',
              {
                'schedule': {'dueDate': '2030-05-10'},
              },
            ),
          );
          final expectedSnapshot = current.taskSnapshot;
          var listsAfterArming = 0, callbacks = 0;
          folder.beforeList = () async {
            if (++listsAfterArming == 1) {
              folder.beforeList = null;
              await folder.create('$peer.applog', peerBytes);
            }
          };
          await expectLater(
            current.editNativeTask(
              task,
              changes,
              expectedSnapshot: expectedSnapshot,
              onPrepared: (_) => callbacks++,
            ),
            throwsA(isA<StaleTaskSnapshot>()),
          );
          expect(listsAfterArming, 1);
          expect(callbacks, 0);
          expect(current.unified!.hasPending, isFalse);
          expect(current.unified!.physicalSequence, sequence);
          expect(await folder.read(ownedName), original);
          expect(
            current.rows.singleWhere(
              (row) => row['id'] == task,
            )['schedule']['dueDate'],
            '2030-05-10',
          );
          OperationReceipt? saved;
          var retryLists = 0;
          folder.beforeList = () async {
            retryLists++;
          };
          await current.editNativeTask(
            task,
            changes,
            onPrepared: (receipt) {
              expect(
                retryLists,
                1,
                reason: 'Capture and reservation share one fresh observation.',
              );
              saved = receipt;
            },
          );
          prepared.commit(receiptUpdate: prepared.update);
          current.registerTextOperation(saved!, capture);
          expect(current.unified!.physicalSequence, sequence + 1);
          expect(
            current.rows.singleWhere((row) => row['id'] == task)['title'],
            'Saved title',
          );
          expect((await current.undoOperations([saved!.id])).error, isNull);
          final row = current.rows.singleWhere((row) => row['id'] == task);
          expect(row['title'], 'Original title');
          expect(row['schedule']['dueDate'], '2030-05-10');
        } finally {
          draft.cancel();
        }
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
  );

  for (final failure in [
    'ownReplacement',
    'completeInvalidPeer',
    'onPreparedThrows',
  ]) {
    test(
      'native fresh reservation retains exact receipt and Undo after $failure',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'native-fresh-recovery-',
        );
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        TaskStore? store;
        try {
          store = await TaskStore.open(
            folder,
            '${root.path}/profile',
            textEngine: engine,
          );
          final current = store;
          final user = const Uuid().v4(),
              task = const Uuid().v4(),
              peer = const Uuid().v4();
          await current.command(user, 'user.created', {'name': 'Synthetic'});
          expect(
            (await current.createTasks({
              task: 'Original title',
            }, user)).succeeded,
            isTrue,
          );
          final capture = await current.captureTaskText(task);
          final field = capture.fields['title']!;
          final draft = field.document.captureDraft(actorClientId: field.actor)
            ..replaceText('Saved title');
          final prepared = draft.prepareSave();
          try {
            final changes = {
              'title': {
                'context': field.context,
                'allocation': field.allocation,
                'actor': field.actor,
                'update': prepared.update.encoded,
              },
            };
            final file = File('${folder.location}/${current.writer}.applog');
            final before = await file.readAsBytes();
            final sequence = current.unified!.physicalSequence;
            final peerFile = File('${folder.location}/$peer.applog');
            OperationReceipt? receipt;
            var callbacks = 0;
            await expectLater(
              current.editNativeTask(
                task,
                changes,
                onPrepared: (saved) {
                  receipt = saved;
                  callbacks++;
                  if (failure == 'ownReplacement') {
                    final replacement = File(
                      '${folder.location}/replacement.tmp',
                    );
                    replacement.writeAsBytesSync(
                      Uint8List.fromList(before)..[10] ^= 1,
                      flush: true,
                    );
                    replacement.renameSync(file.path);
                  } else if (failure == 'completeInvalidPeer') {
                    peerFile.writeAsStringSync('{}\n', flush: true);
                  } else {
                    throw StateError('Synthetic onPrepared failure');
                  }
                },
              ),
              failure == 'onPreparedThrows'
                  ? throwsStateError
                  : throwsA(isA<FormatFailure>()),
            );
            expect(callbacks, 1);
            expect(receipt, isNotNull);
            expect(current.unified!.hasPending, isTrue);
            final exact = current.unified!.pendingRecords.single;
            expect(exact.effects.single.id, receipt!.id);
            expect(exact.effects.single.raw, receipt!.raw);
            expect(current.unified!.physicalSequence, sequence);
            if (failure == 'ownReplacement') {
              await file.writeAsBytes(before, flush: true);
            } else if (failure == 'completeInvalidPeer') {
              expect(await file.readAsBytes(), before);
              await peerFile.delete();
            } else {
              expect(await file.readAsBytes(), before);
            }
            await current.unified!.recoverPrepared();
            expect(await file.readAsBytes(), [
              ...before,
              ...utf8.encode('${exact.encode()}\n'),
            ]);
            expect(current.unified!.physicalSequence, sequence + 1);
            expect(current.unified!.hasPending, isFalse);
            prepared.commit(receiptUpdate: prepared.update);
            current.registerTextOperation(receipt!, capture);
            expect(
              current.rows.singleWhere((row) => row['id'] == task)['title'],
              'Saved title',
            );
            expect((await current.undoOperations([receipt!.id])).error, isNull);
            expect(
              current.rows.singleWhere((row) => row['id'] == task)['title'],
              'Original title',
            );
          } finally {
            draft.cancel();
            current.releaseTextCapture(capture);
          }
        } finally {
          await store?.close();
          engine.dispose();
          await root.delete(recursive: true);
        }
      },
      skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
    );
  }

  test(
    'dense native history reuses validation while Save, Undo and completion stay atomic',
    () async {
      final root = await Directory.systemTemp.createTemp('task-latency-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4();
        await store.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        final titles = {
          for (var i = 0; i < 600; i++)
            const Uuid().v4(): 'Synthetic household task $i',
        };
        expect((await store.createTasks(titles, user)).succeeded, isTrue);
        // A later-sorted peer makes local reservation order differ from physical
        // scan order. Both describe the same complete semantic history.
        const peer = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        await folder.create(
          '$peer.applog',
          peerBytesFor(
            store,
            LogEvent(
              store.space,
              peer,
              1,
              EventClock(store.unified!.maximumClock!.value + BigInt.one),
              const Uuid().v4(),
              'user.created',
              {'name': 'Synthetic peer'},
            ),
          ),
        );
        await store.refresh();
        final history = store.unified!;
        final snapshot = history.snapshot;
        final revision = TaskStore.canonicalTaskRevision(snapshot.tasks);
        final forged = UnifiedSnapshot(
          snapshot.revision,
          snapshot.records,
          snapshot.effects,
          snapshot.physical,
          snapshot.published,
          snapshot.incomplete,
          snapshot.foodAdmission,
          snapshot.pendingEffects,
          readyTaskIds: snapshot.readyTaskIds,
        );
        expect(history.verifiesTaskRevision(snapshot, revision), isTrue);
        expect(history.verifiesTaskRevision(forged, revision), isFalse);
        expect(
          history.selectTaskCopySeedRaws(forged, titles.keys.first),
          isNull,
        );
        expect(
          history.selectTaskCopySeedRaws(snapshot, titles.keys.first),
          isEmpty,
        );

        final task = titles.keys.first;
        final canonicalBefore = await folder.read('${store.writer}.applog');
        final decodedBefore = history.decodedRecords;
        final validationsBefore = history.semanticValidationRuns;
        final readinessBefore = history.fullTaskReadinessRuns;
        final readsBefore = history.readFiles;
        final capture = await store.captureTaskText(task);
        expect(
          history.readFiles,
          readsBefore,
        ); // ADR0007 unchanged-prefix reuse.
        expect(history.decodedRecords, decodedBefore);
        expect(history.semanticValidationRuns, validationsBefore);
        final field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Edited synthetic household task');
        final prepared = draft.prepareSave();
        OperationReceipt? saved;
        var sequence = history.physicalSequence;
        await store.editNativeTask(task, {
          'title': {
            'context': field.context,
            'allocation': field.allocation,
            'actor': field.actor,
            'update': prepared.update.encoded,
          },
        }, onPrepared: (receipt) => saved = receipt);
        prepared.commit(receiptUpdate: prepared.update);
        store.registerTextOperation(saved!, capture);
        draft.cancel();
        expect(history.physicalSequence, ++sequence);
        expect(
          history.semanticValidationRuns - validationsBefore,
          1,
          reason:
              'Reservation and readback must reuse the same exact semantic proof.',
        );
        expect(
          history.decodedRecords - decodedBefore,
          0,
          reason: 'Exact readback adopts the already validated private action.',
        );
        expect(
          history.fullTaskReadinessRuns,
          readinessBefore,
          reason:
              'A settled title edit must not restore every unrelated text field.',
        );
        expect(history.settledTextReadinessRuns, greaterThan(0));
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          'Edited synthetic household task',
        );
        var validations = history.semanticValidationRuns;
        expect((await store.undoOperations([saved!.id])).error, isNull);
        expect(history.physicalSequence, ++sequence);
        expect(history.semanticValidationRuns - validations, 1);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          titles[task],
        );
        expect(history.fullTaskReadinessRuns, readinessBefore);
        final accepted = history.snapshot.tasks.toList();
        final undo = accepted.lastWhere((e) => e.type == 'task.textEditUndone');
        final beforeUndo = accepted.where((e) => e.id != undo.id).toList();
        final userCreation = beforeUndo.firstWhere(
          (e) => e.type == 'user.created',
        );
        final target = beforeUndo.singleWhere((e) => e.id == saved!.id);
        for (final bad in [
          LogEvent(
            undo.space,
            undo.writer,
            undo.sequence,
            undo.clock,
            undo.entity,
            undo.type,
            {...undo.data, 'operation': userCreation.id},
          ),
          LogEvent(
            undo.space,
            undo.writer,
            undo.sequence,
            target.clock,
            undo.entity,
            undo.type,
            undo.data,
          ),
          LogEvent(
            undo.space,
            undo.writer,
            undo.sequence,
            undo.clock,
            titles.keys.last,
            undo.type,
            undo.data,
          ),
        ]) {
          final candidate = LogEvent.decode(
            bad.encode(previousHash: undo.previousHash),
          );
          final validator = TaskSemanticValidator(
            space: store.space,
            writer: store.writer,
            textEngine: engine,
          );
          try {
            validator.validate(beforeUndo);
            expect(
              () => validator.validate([...beforeUndo, candidate]),
              throwsA(isA<FormatFailure>()),
            );
            expect(
              () => TaskStore.validateSemanticHistory(
                [...beforeUndo, candidate],
                space: store!.space,
                writer: store.writer,
                textEngine: engine,
              ),
              throwsA(isA<FormatFailure>()),
            );
            // A failed incremental candidate must not poison the next replay.
            expect(
              validator.validate(accepted),
              accepted.map((e) => e.id).toSet(),
            );
          } finally {
            validator.close();
          }
        }
        expect(
          {for (final r in store.rows) r['id']: r},
          {
            for (final r in TaskStore.validateSemanticHistory(
              accepted,
              space: store.space,
              writer: store.writer,
              textEngine: engine,
            ))
              r['id']: r,
          },
        );
        validations = history.semanticValidationRuns;
        OperationReceipt? completed;
        await store.complete(
          task,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2026, 10, 22),
          onPrepared: (receipt) => completed = receipt,
        );
        expect(history.physicalSequence, ++sequence);
        expect(history.semanticValidationRuns - validations, 1);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['completed'],
          isTrue,
        );
        expect((await store.undoOperations([completed!.id])).error, isNull);
        expect(history.physicalSequence, ++sequence);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['completed'],
          isFalse,
        );
        store.releaseTextCapture(capture);
        // Explicit repair must bypass the unchanged-snapshot identity shortcut.
        store.db.execute(
          "UPDATE ${store.tables.views} SET raw=json_set(raw,'\$.title','Corrupted disposable cache') WHERE id=?",
          [task],
        );
        await store.rebuildCache();
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          titles[task],
        );
        final canonicalAfter = await folder.read('${store.writer}.applog');
        expect(canonicalAfter.take(canonicalBefore.length), canonicalBefore);
        final rows = jsonEncode(store.rows);
        ChecklistExpansionStore(
          store.db,
          tables: store.tables,
          profileDatabase: store.profileDatabase,
        ).setExpanded([task], true);
        await store.close();
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        expect(jsonEncode(store.rows), rows);
        expect(
          ChecklistExpansionStore(store.db, tables: store.tables).load(),
          contains(task),
        );
        expect(
          store.warmProjectionReuses,
          1,
          reason: 'Clean unchanged reopen must reuse verified projections.',
        );
        store.db.execute(
          "UPDATE ${store.tables.views} SET raw=json_set(raw,'\$.title','Corrupt after warm reopen') WHERE id=?",
          [task],
        );
        await store.rebuildCache();
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          titles[task],
        );
        expect(await folder.read('${store.writer}.applog'), canonicalAfter);
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'canonical native failures stay before reservation and allow valid retry',
    () async {
      final root = await Directory.systemTemp.createTemp('native-candidate-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        final activeStore = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        store = activeStore;
        final user = const Uuid().v4(), task = const Uuid().v4();
        await activeStore.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await activeStore.createTasks({
            task: 'Native task',
          }, user)).succeeded,
          isTrue,
        );
        final history = activeStore.unified!;
        if (!history.snapshot.tasks.any(
          (e) => e.type == 'text.baselineInitialized',
        )) {
          await activeStore.initializeSharedText();
        }

        final name = '${activeStore.writer}.applog';
        final original = await folder.read(name);
        final sequence = history.physicalSequence;
        final capture = await activeStore.captureTaskText(task);
        final field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Valid retry');
        try {
          final prepared = draft.prepareSave();
          final valid = <String, dynamic>{
            'context': field.context,
            'allocation': field.allocation,
            'actor': field.actor,
            'update': prepared.update.encoded,
          };
          final invalid = {...valid, 'context': '0' * 64};
          var preparedCallbacks = 0, reservedCallbacks = 0;
          await expectLater(
            activeStore.editNativeTask(task, {
              'title': invalid,
            }, onPrepared: (_) => preparedCallbacks++),
            throwsA(isA<FormatFailure>()),
          );
          expect(preparedCallbacks, 0);
          expect(history.hasPending, isFalse);
          expect(history.physicalSequence, sequence);
          expect(await folder.read(name), original);
          // The first effect is valid. A later invalid native packet must roll
          // back the entire candidate before reservation or receipt callbacks.
          await expectLater(
            history.prepareInProfileQueue([
              (seq, clock, head) => UnifiedEffect(
                'task',
                LogEvent(
                  activeStore.space,
                  activeStore.writer,
                  seq,
                  clock,
                  task,
                  'task.edited',
                  {
                    'schedule': {'dueDate': '2030-05-10'},
                  },
                ).encode(previousHash: head),
              ),
              (seq, clock, head) => UnifiedEffect(
                'task',
                LogEvent(
                  activeStore.space,
                  activeStore.writer,
                  seq,
                  clock,
                  task,
                  'task.textEdited',
                  {
                    'changes': {'title': invalid},
                  },
                ).encode(previousHash: head),
              ),
            ], onReserved: (_) => reservedCallbacks++),
            throwsA(isA<FormatFailure>()),
          );
          expect(reservedCallbacks, 0);
          expect(history.hasPending, isFalse);
          expect(history.physicalSequence, sequence);
          expect(await folder.read(name), original);
          expect(
            activeStore.rows.singleWhere((r) => r['id'] == task)['title'],
            'Native task',
          );
          final baseline = history.snapshot.tasks.singleWhere(
            (e) => e.type == 'text.baselineInitialized',
          );
          await expectLater(
            activeStore.command(
              activeStore.space,
              'text.baselineInitialized',
              baseline.data,
              onPrepared: (_) => preparedCallbacks++,
            ),
            throwsA(isA<FormatFailure>()),
          );
          expect(preparedCallbacks, 0);
          expect(history.hasPending, isFalse);
          expect(await folder.read(name), original);
          OperationReceipt? saved;
          await activeStore.editNativeTask(
            task,
            {'title': valid},
            onPrepared: (r) {
              saved = r;
              preparedCallbacks++;
            },
          );
          prepared.commit(receiptUpdate: prepared.update);
          activeStore.registerTextOperation(saved!, capture);
          expect(preparedCallbacks, 1);
          expect(history.physicalSequence, sequence + 1);
          expect(history.hasPending, isFalse);
          expect(
            activeStore.rows.singleWhere((r) => r['id'] == task)['title'],
            'Valid retry',
          );
          expect((await activeStore.undoOperations([saved!.id])).error, isNull);
          expect(
            activeStore.rows.singleWhere((r) => r['id'] == task)['title'],
            'Native task',
          );
        } finally {
          draft.cancel();
          activeStore.releaseTextCapture(capture);
        }
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'derived edits retain first-activity seed changes then use point validation',
    () async {
      final root = await Directory.systemTemp.createTemp('derived-point-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4(), parent = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await store.createTasks({parent: 'Recurring'}, user)).succeeded,
          isTrue,
        );
        await store.edit(
          parent,
          {
            'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          },
          tags: [],
          observedTagRefs: {},
        );
        final item = await store.addChecklistItem(parent, 'Original item');
        OperationReceipt? firstReceipt;
        final beforeFreshBirth = store.unified!.fullTaskReadinessRuns;
        final first = await store.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
          onPrepared: (r) => firstReceipt = r,
        );
        expect(store.unified!.fullTaskReadinessRuns, beforeFreshBirth);
        expect(store.unified!.snapshot.allVisibleTasksReady, isTrue);
        expect(
          {for (final row in store.rows) row['id']: row},
          {
            for (final row in TaskStore.validateSemanticHistory(
              store.unified!.snapshot.tasks,
              space: store.space,
              writer: store.writer,
              textEngine: engine,
            ))
              row['id']: row,
          },
        );
        final wholeEffects = store.unified!.fullEffectValidationRuns;
        final initialCopy = copiedChecklistId(
          const Uuid().v5(parent, 'successor'),
          item.entity,
        );
        final originalCapture = await store.captureTaskText(initialCopy);
        final originalCopyContext = originalCapture.fields['title']!.context;
        store.releaseTextCapture(originalCapture);
        expect((await store.undoOperations([firstReceipt!.id])).error, isNull);
        expect(store.unified!.fullEffectValidationRuns, wholeEffects);
        final beforeRecomplete = store.unified!.fullTaskReadinessRuns;
        await store.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
        );
        expect(store.unified!.fullTaskReadinessRuns, beforeRecomplete);
        expect(store.unified!.fullEffectValidationRuns, wholeEffects);
        final repeatedCapture = await store.captureTaskText(initialCopy);
        expect(repeatedCapture.fields['title']!.context, originalCopyContext);
        store.releaseTextCapture(repeatedCapture);
        final child = const Uuid().v5(parent, 'successor');
        final copied = copiedChecklistId(child, item.entity);
        final history = store.unified!;
        void oracle() {
          expect(
            {for (final r in store!.rows) r['id']: r},
            {
              for (final r in TaskStore.validateSemanticHistory(
                history.snapshot.tasks,
                space: store.space,
                writer: store.writer,
                textEngine: engine,
              ))
                r['id']: r,
            },
          );
        }

        oracle();
        final readyOracle = TaskSemanticValidator(
          space: store.space,
          writer: store.writer,
          textEngine: engine,
        );
        try {
          expect(
            readyOracle.validate(history.snapshot.tasks.toList()),
            history.snapshot.readyTaskIds,
          );
        } finally {
          readyOracle.close();
        }

        Future<void> nativeRound(String entity) async {
          final activeStore = store!;
          final before = history.fullTaskReadinessRuns;
          final capture = await activeStore.captureTaskText(entity);
          final field = capture.fields['title']!;
          final draft = field.document.captureDraft(actorClientId: field.actor)
            ..replaceText('Changed derived title');
          try {
            final prepared = draft.prepareSave();
            OperationReceipt? receipt;
            await activeStore.editNativeTask(entity, {
              'title': {
                'context': field.context,
                'allocation': field.allocation,
                'actor': field.actor,
                'update': prepared.update.encoded,
              },
            }, onPrepared: (r) => receipt = r);
            prepared.commit(receiptUpdate: prepared.update);
            activeStore.registerTextOperation(receipt!, capture);
            expect(history.fullTaskReadinessRuns, before);
            oracle();
            expect(
              (await activeStore.undoOperations([receipt!.id])).error,
              isNull,
            );
            expect(history.fullTaskReadinessRuns, before);
            oracle();
          } finally {
            draft.cancel();
            activeStore.releaseTextCapture(capture);
          }
        }

        final beforeFirst = history.fullTaskReadinessRuns;
        await store.edit(
          child,
          {},
          tags: ['First activity'],
          observedTagRefs: {},
        );
        expect(history.fullTaskReadinessRuns, greaterThan(beforeFirst));
        oracle();
        final established = history.fullTaskReadinessRuns;
        OperationReceipt? metadata;
        await store.edit(
          child,
          {
            'schedule': {'dueDate': '2030-05-12', 'recurrence': 'every day'},
          },
          tags: ['First activity'],
          observedTagRefs: Map<String, String>.from(
            (store.rows.singleWhere((r) => r['id'] == child)['tagRefs']
                    as Map?) ??
                {},
          ),
          onPrepared: (r) => metadata = r,
        );
        expect(history.fullTaskReadinessRuns, established);
        oracle();
        expect((await store.undoOperations([metadata!.id])).error, isNull);
        expect(history.fullTaskReadinessRuns, established);
        oracle();

        // The child activity above already protected the earliest parent
        // seed. First copy activity leaves both identities unchanged, so its
        // completed-only update can use the private exact-seed proof.
        expect(
          history.snapshot.tasks.where((event) => event.entity == copied),
          isEmpty,
        );
        final copyClaims = history.selectTaskCopySeedRaws(
          history.snapshot,
          copied,
        )!;
        expect(LogEvent.decode(copyClaims.first).id, first.id);
        expect(history.snapshot.readyTaskIds, contains(first.id));
        final childActivity = history.snapshot.tasks
            .where((event) => event.entity == child)
            .toList();
        expect(childActivity, isNotEmpty);
        expect(
          childActivity.every(
            (event) => history.snapshot.readyTaskIds.contains(event.id),
          ),
          isTrue,
        );
        Future<Map<String, String>> contextsFor(String entity) async {
          final activeStore = store!;
          final capture = await activeStore.captureTaskText(entity);
          try {
            return {
              for (final field in capture.fields.entries)
                field.key: field.value.context,
            };
          } finally {
            activeStore.releaseTextCapture(capture);
          }
        }

        final childContext = await contextsFor(child);
        final copyContext = await contextsFor(copied);
        expect(copyContext['title'], originalCopyContext);
        final beforeItem = history.fullTaskReadinessRuns;
        await store.setChecklistCompleted(copied, true);
        expect(history.fullTaskReadinessRuns, beforeItem);
        expect(await contextsFor(child), childContext);
        expect(await contextsFor(copied), copyContext);
        expect(history.snapshot.allVisibleTasksReady, isTrue);
        oracle();
        final itemEstablished = history.fullTaskReadinessRuns;
        await store.setChecklistCompleted(copied, false);
        expect(history.fullTaskReadinessRuns, itemEstablished);
        oracle();

        await nativeRound(child);
        await nativeRound(copied);

        // Arrival of a competing seed must receive full admission before the
        // next point update can use its new ready identity.
        const peer = '00000000-0000-4000-8000-000000000001';
        await folder.create(
          '$peer.applog',
          peerBytesFor(
            store,
            LogEvent(
              store.space,
              peer,
              1,
              first.clock,
              parent,
              first.type,
              first.data,
            ),
          ),
        );
        final beforePeer = history.fullTaskReadinessRuns;
        await store.refresh();
        expect(history.fullTaskReadinessRuns, greaterThan(beforePeer));
        oracle();
        final peerReady = history.fullTaskReadinessRuns;
        await store.edit(
          child,
          {
            'schedule': {'dueDate': '2030-05-13', 'recurrence': 'every day'},
          },
          tags: ['First activity'],
          observedTagRefs: Map<String, String>.from(
            (store.rows.singleWhere((r) => r['id'] == child)['tagRefs']
                    as Map?) ??
                {},
          ),
        );
        expect(history.fullTaskReadinessRuns, peerReady);
        oracle();
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('retained marker rebinding retains the full readiness oracle', () async {
    final root = await Directory.systemTemp.createTemp('retained-cut-cycle-');
    final engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    TaskStore? store;
    try {
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      store = await TaskStore.open(
        folder,
        '${root.path}/profile',
        textEngine: engine,
      );
      final user = const Uuid().v4(), parent = const Uuid().v4();
      await store.command(user, 'user.created', {'name': 'Synthetic'});
      expect(
        (await store.createTasks({parent: 'Recurring'}, user)).succeeded,
        isTrue,
      );
      await store.edit(
        parent,
        {
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
        },
        tags: [],
        observedTagRefs: {},
      );
      OperationReceipt? receipt;
      final first = await store.complete(
        parent,
        localZoneId: 'UTC',
        completionInstant: DateTime.utc(2030, 5, 10),
        onPrepared: (value) => receipt = value,
      );
      expect((await store.undoOperations([receipt!.id])).error, isNull);
      final child = const Uuid().v5(parent, 'successor');
      await store.command(parent, 'task.completedKeepingSuccessor', {
        'completedInstant': '2030-05-10T00:00:00.000000Z',
        'retainedSuccessor': {
          'id': child,
          'completion': first.id,
          'hash': first.hash,
        },
      });
      expect(store.unified!.snapshot.allVisibleTasksReady, isTrue);
      final before = await folder.read('${store.writer}.applog');
      final rows = jsonEncode(store.rows);
      final readiness = store.unified!.fullTaskReadinessRuns;
      var prepared = false;
      final replacement =
          jsonDecode(jsonEncode(first.data)) as Map<String, dynamic>;
      final heads = <String, dynamic>{};
      for (final event in store.unified!.snapshot.tasks) {
        final old = heads[event.writer] as Map?;
        if (old == null || event.sequence > (old['seq'] as int)) {
          heads[event.writer] = {'seq': event.sequence, 'hash': event.hash};
        }
      }
      (replacement['inheritance'] as Map)['frontiers'] = heads;
      final accepted = await store.command(
        parent,
        first.type,
        replacement,
        onPrepared: (_) => prepared = true,
      );
      expect(accepted.type, first.type);
      expect(prepared, isTrue);
      expect(store.unified!.hasPending, isFalse);
      expect(store.unified!.fullTaskReadinessRuns, greaterThan(readiness));
      final after = await folder.read('${store.writer}.applog');
      expect(after.length, greaterThan(before.length));
      expect(after.take(before.length).toList(), before);
      expect(jsonEncode(store.rows), isNot(rows));
      expect(
        {for (final row in store.rows) row['id']: row},
        {
          for (final row in TaskStore.validateSemanticHistory(
            store.unified!.snapshot.tasks,
            space: store.space,
            writer: store.writer,
            textEngine: engine,
          ))
            row['id']: row,
        },
      );
      final readyOracle = TaskSemanticValidator(
        space: store.space,
        writer: store.writer,
        textEngine: engine,
      );
      try {
        expect(
          readyOracle.validate(store.unified!.snapshot.tasks.toList()),
          store.unified!.snapshot.readyTaskIds,
        );
      } finally {
        readyOracle.close();
      }
      expect(
        (await store.createTasks({
          const Uuid().v4(): 'Ordinary retry',
        }, user)).succeeded,
        isTrue,
      );
    } finally {
      await store?.close();
      engine.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'move anchor updates a suppressed recurring successor like full replay',
    () async {
      final root = await Directory.systemTemp.createTemp('delta-anchor-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          LocalLogFolder(
            (await Directory('${root.path}/shared').create()).path,
          ),
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4(),
            parent = const Uuid().v4(),
            mover = const Uuid().v4(),
            child = const Uuid().v5(parent, 'successor');
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await store.createTasks({
            parent: 'Recurring task',
            mover: 'Other task',
          }, user)).succeeded,
          isTrue,
        );
        await store.command(parent, 'task.edited', {
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
        });
        OperationReceipt? completion;
        await store.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
          onPrepared: (r) => completion = r,
        );
        expect((await store.undoOperations([completion!.id])).error, isNull);
        expect(store.rows.where((r) => r['id'] == child), isEmpty);
        expect(
          jsonDecode(
            store.db.select(
                  'SELECT raw FROM ${store.tables.views} WHERE id=?',
                  [child],
                ).single['raw']
                as String,
          )['successorSuppressed'],
          isTrue,
        );
        await store.command(mover, 'task.moved', {'before': child});
        expect(
          store.rows.singleWhere(
            (r) => r['id'] == child,
          )['successorSuppressed'],
          isFalse,
        );
        final oracle = TaskStore.validateSemanticHistory(
          store.unified!.snapshot.tasks,
          space: store.space,
          writer: store.writer,
          textEngine: engine,
        );
        expect(
          {for (final r in store.rows) r['id']: r},
          {for (final r in oracle) r['id']: r},
        );
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'warm decode cache still detects changed prefixes and invalid complete records',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'task-latency-integrity-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      try {
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Synthetic',
        });
        await store.refresh();
        final history = store.unified!;
        final path = File('${folder.location}/${store.writer}.applog');
        final original = await path.readAsBytes();
        final decoded = history.decodedRecords;
        await store.refresh();
        expect(history.decodedRecords, decoded);
        final previous = history.snapshot;
        final changed = Uint8List.fromList(original);
        changed[changed.indexOf(83)] = 84;
        const peer = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        await folder.create(
          '$peer.applog',
          peerBytesFor(
            store,
            LogEvent(
              store.space,
              peer,
              1,
              EventClock(history.maximumClock!.value + BigInt.one),
              const Uuid().v4(),
              'user.created',
              {'name': 'Synthetic concurrent peer'},
            ),
          ),
        );
        await path.writeAsBytes(changed, flush: true);
        await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
        expect(history.snapshot, previous);
        // Only this disposable, never-admitted peer is removed for recovery.
        await File('${folder.location}/$peer.applog').delete();
        await path.writeAsBytes(original, flush: true);
        await store.refresh();
        final protected = store.db.select(
          'SELECT * FROM protected_app_heads WHERE writer=?',
          [store.writer],
        ).single;
        for (final change in <String, Object>{
          'digest': '0' * 64,
          'sequence': (protected['sequence'] as int) + 1,
          'bytes': (protected['bytes'] as int) - 1,
          'published': (protected['sequence'] as int) + 1,
        }.entries) {
          final accepted = history.snapshot;
          store.db.execute(
            'UPDATE protected_app_heads SET ${change.key}=? WHERE writer=?',
            [change.value, store.writer],
          );
          await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
          expect(history.snapshot, accepted);
          expect(await path.readAsBytes(), original);
          store.db.execute(
            'UPDATE protected_app_heads SET ${change.key}=? WHERE writer=?',
            [protected[change.key], store.writer],
          );
          await store.refresh();
        }
        final good = history.snapshot;
        await folder.append(
          '${store.writer}.applog',
          Uint8List.fromList(utf8.encode('{"unknown":true}\n')),
        );
        await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
        expect(history.snapshot, good);
        expect(history.hasPending, isFalse);
        await path.writeAsBytes(original, flush: true);
        await store.refresh();
        expect(await path.readAsBytes(), original);
        expect(
          () => history.snapshot.tasks.first.data['name'] = 'Mutated',
          throwsUnsupportedError,
        );
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'warm prefix proof distinguishes partial tails from new complete records',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'task-prefix-boundary-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      try {
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Synthetic',
        });
        final name = '${store.writer}.applog';
        final original = await folder.read(name);
        Map<String, Object?> head() => Map.from(
          store.db.select('SELECT * FROM protected_app_heads WHERE writer=?', [
            store.writer,
          ]).single,
        );
        final before = head();
        await folder.append(name, Uint8List.fromList(utf8.encode('{partial')));
        await store.refresh();
        expect(store.unified!.snapshot.incomplete, isTrue);
        expect(head()['digest'], before['digest']);
        expect(head()['sequence'], before['sequence']);
        expect(head()['bytes'], original.length);
        // Remove only the synthetic owner's uncommitted tail.
        await File(
          '${folder.location}/$name',
        ).writeAsBytes(original, flush: true);
        await store.refresh();
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Next synthetic',
        });
        final after = await folder.read(name);
        expect(after.take(original.length), original);
        expect(head()['sequence'], (before['sequence'] as int) + 1);
        expect(head()['bytes'], after.length);
        expect(head()['digest'], 'chain1:${head()['hash']}');
        expect(head()['digest'], isNot(before['digest']));
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'old malformed semantic cache rebuilds before expression indexes open',
    () async {
      final root = await Directory.systemTemp.createTemp('task-latency-cache-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(folder, '${root.path}/profile');
        final person = const Uuid().v4();
        await store.command(person, 'user.created', {'name': 'Synthetic'});
        final expected = jsonEncode(store.rows);
        final table = store.tables.events;
        final name = '${store.writer}.applog';
        final canonical = await folder.read(name);
        await store.close();
        store = null;
        final db = sqlite3.open('${root.path}/profile/local.sqlite');
        try {
          // Simulate a disposable malformed row produced by an older build,
          // which did not have these expression indexes.
          for (final suffix in [
            'entity',
            'successor',
            'type_parent',
            'type_before',
          ]) {
            db.execute('DROP INDEX IF EXISTS ${table}_$suffix');
          }
          db.execute('UPDATE $table SET semantic=? WHERE entity=?', [
            '{',
            person,
          ]);
        } finally {
          db.close();
        }
        store = await TaskStore.open(folder, '${root.path}/profile');
        expect(jsonEncode(store.rows), expected);
        expect(await folder.read(name), canonical);
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'failed projection rebuild does not retain an uncommitted index-ready flag',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'task-index-rollback-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      final blocker = Object();
      var fail = false;
      try {
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Synthetic',
        });
        final expected = jsonEncode(store.rows);
        final names = [
          'entity',
          'successor',
          'type_parent',
        ].map((suffix) => '${store.tables.events}_$suffix').toSet();
        for (final name in names) {
          store.db.execute('DROP INDEX IF EXISTS $name');
        }
        final app = store.unified!;
        await app.profile.serialize(() async {
          app.attachProjectionInProfileQueue(blocker, (snapshot) {
            if (fail) {
              throw FormatFailure('Synthetic late rebuild stage failure');
            }
            return () {};
          });
        });
        fail = true;
        await expectLater(store.rebuildCache(), throwsA(isA<FormatFailure>()));
        expect(jsonEncode(store.rows), expected);
        Set<String> indexes() => store.db
            .select("SELECT name FROM sqlite_master WHERE type='index'")
            .map((r) => r['name'] as String)
            .toSet();
        expect(indexes().intersection(names), isEmpty);
        fail = false;
        await store.refresh();
        expect(indexes().containsAll(names), isTrue);
        expect(jsonEncode(store.rows), expected);
      } finally {
        await store.unified!.profile.serialize(() async {
          store.unified!.detachProjectionInProfileQueue(blocker);
        });
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'delivered peer Task action validates only its delta, without a whole-history sort or scan',
    () async {
      final root = await Directory.systemTemp.createTemp('task-latency-peer-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final shared = await Directory('${root.path}/shared').create();
      final remote = await Directory('${root.path}/remote').create();
      TaskStore? store, peer;
      try {
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4();
        await store.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        final titles = {
          for (var i = 0; i < 120; i++)
            const Uuid().v4(): 'Synthetic household task $i',
        };
        expect((await store.createTasks(titles, user)).succeeded, isTrue);
        for (final id in titles.keys.take(3)) {
          await store.edit(
            id,
            {
              'schedule': {'dueDate': '2030-05-13'},
            },
            tags: ['Synthetic tag'],
            observedTagRefs: {},
          );
        }
        // A second installation shares the same history and publishes only
        // appended complete actions, like a Syncthing peer.
        for (final file in shared.listSync().whereType<File>()) {
          file.copySync('${remote.path}/${file.uri.pathSegments.last}');
        }
        peer = await TaskStore.open(
          LocalLogFolder(remote.path),
          '${root.path}/peer-profile',
          textEngine: engine,
        );
        final name = unifiedLogName(peer.writer);
        Future<void> deliver() async {
          final bytes = await File('${remote.path}/$name').readAsBytes();
          final target = File('${shared.path}/$name');
          final old = target.existsSync()
              ? target.readAsBytesSync()
              : Uint8List(0);
          expect(bytes.sublist(0, old.length), old);
          await target.writeAsBytes(
            bytes.sublist(old.length),
            mode: FileMode.append,
            flush: true,
          );
        }

        Future<String> peerTask(String title) async {
          final id = const Uuid().v4();
          expect(
            (await peer!.createTasks({id: title}, user)).succeeded,
            isTrue,
          );
          return id;
        }

        await peerTask('Synthetic peer task 0');
        await deliver();
        await store.refresh();
        final history = store.unified!;
        expect(history.snapshot.allVisibleTasksReady, isTrue);
        for (var round = 1; round <= 2; round++) {
          final sorts = history.semanticTaskSortRuns;
          final monotonic = history.monotonicTaskValidationRuns;
          final readiness = history.fullTaskReadinessRuns;
          final scans = history.taskHistoryScanReads;
          final id = await peerTask('Synthetic peer task $round');
          await deliver();
          await store.refresh();
          expect(
            store.rows.singleWhere((r) => r['id'] == id)['title'],
            'Synthetic peer task $round',
          );
          // O(delta): no whole-input regroup/sort, no full readiness pass and
          // no dependency read that scans every canonical row.
          expect(history.monotonicTaskValidationRuns, monotonic + 1);
          expect(history.semanticTaskSortRuns, sorts);
          expect(history.fullTaskReadinessRuns, readiness);
          expect(history.taskHistoryScanReads, scans);
        }
        expect(
          {for (final r in store.rows) r['id']: r},
          {
            for (final r in TaskStore.validateSemanticHistory(
              history.snapshot.tasks,
              space: store.space,
              writer: store.writer,
              textEngine: engine,
            ))
              r['id']: r,
          },
        );
        final readyOracle = TaskSemanticValidator(
          space: store.space,
          writer: store.writer,
          textEngine: engine,
        );
        try {
          expect(
            readyOracle.validate(history.snapshot.tasks.toList()),
            history.snapshot.readyTaskIds,
          );
        } finally {
          readyOracle.close();
        }
      } finally {
        await peer?.close();
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
