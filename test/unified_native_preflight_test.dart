import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/text_context.dart';
import 'package:tandemlog/domain/text_actor.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_record.dart';
import 'unified_conversion_test.dart' as fixture;
import 'unified_history_test.dart' show FaultFolder;
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/text/native_text_engine.dart';

const owner = '22222222-2222-4222-8222-222222222222';
const user = '33333333-3333-4333-8333-333333333333';
const task = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'actual native creation/edit lineage and both protected domain heads survive conversion',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'unified-native-disposable-',
      );
      final folder = FaultFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? tasks;
      FoodStore? food;
      UnifiedHistory? app;
      try {
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              owner,
              utf8.encode(
                jsonEncode({'writer': owner, 'appearance': 'system'}),
              ),
            ],
          ),
        );
        tasks = await TaskStore.open(
          folder,
          profile.root,
          writerIdentity: owner,
          profileDatabase: profile,
          textEngine: engine,
          initializeNewWorkspaceText: true,
        );
        final space = tasks.space;
        await tasks.command(user, 'user.created', {'name': 'Synthetic person'});
        await tasks.createTasks({task: 'Original native text'}, user);
        final capture = await tasks.captureTaskText(task),
            field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Native text through one app history');
        final prepared = draft.prepareSave();
        final change = <String, dynamic>{
          'context': field.context,
          'allocation': field.allocation,
          'actor': field.actor,
          'update': prepared.update.encoded,
        };
        draft.cancel();
        tasks.releaseTextCapture(capture);
        food = await FoodStore.open(
          folder,
          profile: profile,
          installationWriter: owner,
          space: space,
        );
        await food.add(const FoodDetails(name: 'Synthetic beans'), 1);
        final baseline = tasks.rows.map(canonicalDataJson).toList();
        await food.close();
        food = null;
        await tasks.close();
        tasks = null;
        final sources = <String, List<int>>{};
        for (final info in await folder.list()) {
          if (info.name.endsWith('.jsonl') || info.name.endsWith('.foodlog')) {
            sources[info.name] = await folder.read(info.name);
          }
        }
        final plan = UnifiedCutoverPlan.inspect(
          space: space,
          owners: {owner},
          participants: {owner},
          sources: sources,
          hasUnresolvedPreparedWrites: false,
        );
        final converted = plan.convert([
          CutoverAcknowledgement(
            owner,
            plan.sourceDigest,
            quiesced: true,
            pendingResolved: true,
          ),
        ]);
        for (final e in converted.files.entries) {
          await folder.create(e.key, Uint8List.fromList(e.value));
        }
        await folder
            .file('tandemlog-space.json')
            .writeAsString(converted.manifest.encode(), flush: true);
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: owner,
          textEngine: engine,
        );
        tasks = await TaskStore.openUnified(app);
        food = await FoodStore.openUnified(app);
        expect(tasks.rows.map(canonicalDataJson).toList(), baseline);
        final replay = TaskStore.validateSemanticHistory(
          app.snapshot.tasks,
          space: space,
          writer: owner,
          textEngine: engine,
        );
        expect(replay.map(canonicalDataJson).toList(), baseline);
        await app.renameDevice('Synthetic desktop');
        final edited = await tasks.command(task, 'task.textEdited', {
          'changes': {'title': change},
        });
        expect(edited.sequence, app.physicalSequence);
        expect(
          tasks.rows.singleWhere((r) => r['id'] == task)['title'],
          'Native text through one app history',
        );
        const extra = '55555555-5555-4555-8555-555555555555';
        await food.add(const FoodDetails(name: 'Interleaved Food command'), 1);
        await tasks.createTasks({extra: 'Future native task'}, user);
        expect(tasks.isCaptureConfirmed(extra), isTrue);
        {
          final snapshot = tasks.taskSnapshot;
          final bytes = await folder.read(unifiedLogName(owner));
          var allowed = false;
          await expectLater(
            tasks.moveBefore(
              extra,
              task,
              expectedTaskSnapshot: snapshot,
              canCommit: () => allowed,
            ),
            throwsA(isA<StaleTaskSnapshot>()),
          );
          expect(app.hasPending, isFalse);
          expect(await folder.read(unifiedLogName(owner)), bytes);
          allowed = true;
          await tasks.moveBefore(
            extra,
            task,
            expectedTaskSnapshot: snapshot,
            canCommit: () => allowed,
            onPrepared: (_) {
              allowed = false;
            },
          );
          expect(app.hasPending, isFalse);
          expect(await folder.read(unifiedLogName(owner)), isNot(bytes));
        }

        final item = await tasks.addChecklistItem(
          extra,
          'Future checklist item',
        );
        await tasks.setChecklistCompleted(item.entity, true);
        expect(tasks.checklistItems(extra).single['completed'], isTrue);
        {
          final capture = await tasks.captureTaskText(extra),
              field = capture.fields['title']!;
          final draft = field.document.captureDraft(actorClientId: field.actor)
            ..replaceText('Recovered through one app receipt');
          final prepared = draft.prepareSave();
          final change = {
            'context': field.context,
            'allocation': field.allocation,
            'actor': field.actor,
            'update': prepared.update.encoded,
          };
          draft.cancel();
          tasks.releaseTextCapture(capture);
          OperationReceipt? receipt;
          folder.cut = 60;
          await expectLater(
            tasks.command(
              extra,
              'task.textEdited',
              {
                'changes': {'title': change},
              },
              onPrepared: (value) {
                receipt = value;
                expect(
                  profile.database.select('SELECT * FROM protected_app_outbox'),
                  hasLength(1),
                );
                expect(
                  profile.database.select(
                    'SELECT * FROM protected_text_intents',
                  ),
                  isEmpty,
                );
              },
            ),
            throwsA(isA<FileSystemException>()),
          );
          expect(tasks.pendingTextOperations.map((r) => r.raw), [receipt!.raw]);
          await tasks.retryTextOperation(receipt!);
          expect(tasks.pendingTextOperations, isEmpty);
          expect(
            tasks.rows.singleWhere((r) => r['id'] == extra)['title'],
            'Recovered through one app receipt',
          );
        }

        {
          final rows = tasks.rows.map(canonicalDataJson).toList();
          final fields = tasks.db
              .select(
                'SELECT entity,field,state_hash FROM ${tasks.tables.textFields} ORDER BY entity,field',
              )
              .map((r) => r.toString())
              .toList();
          final bytes = await folder.read(unifiedLogName(owner));
          await tasks.rebuildCache();
          expect(tasks.rows.map(canonicalDataJson).toList(), rows);
          expect(
            tasks.db
                .select(
                  'SELECT entity,field,state_hash FROM ${tasks.tables.textFields} ORDER BY entity,field',
                )
                .map((r) => r.toString())
                .toList(),
            fields,
          );
          expect(await folder.read(unifiedLogName(owner)), bytes);
          expect(app.hasPending, isFalse);
        }
        {
          final capture = await tasks.captureTaskText(extra);
          final session = TaskTextSession(
            capture,
            registerDraftActor: (field, allocation, actor) => tasks!
                .registerTextDraftActor(capture, field, allocation, actor),
          );
          try {
            session.replace('title', 'Native callback failure recovered');
            final before = await folder.read(unifiedLogName(owner));
            var allowed = true;
            final command = TextSaveCommand(tasks, session);
            await expectLater(
              command.save(
                fields: {},
                tags: [],
                observedTagRefs: {},
                canCommit: () => allowed,
                onPrepared: (receipt) {
                  allowed = false;
                  expect(
                    profile.database.select(
                      'SELECT * FROM protected_app_outbox',
                    ),
                    hasLength(1),
                  );
                  throw StateError(
                    'Synthetic callback failure after native receipt binding',
                  );
                },
              ),
              throwsStateError,
            );
            final receipt = session.prepare().receipt!;
            expect(app.hasPending, isTrue);
            expect(session.hasPendingReceipt, isTrue);
            expect(
              app.pendingRecords.single.effect.task!.canonicalRaw,
              receipt.raw,
            );
            expect(await folder.read(unifiedLogName(owner)), before);
            final result = await command.save(
              fields: {},
              tags: [],
              observedTagRefs: {},
              canCommit: () => false,
            );
            expect(result.receipt!.raw, receipt.raw);
            expect(
              result.currentRow!['title'],
              'Native callback failure recovered',
            );
            expect(session.hasPendingReceipt, isFalse);
            expect(app.hasPending, isFalse);
          } finally {
            session.cancel();
            tasks.releaseTextCapture(capture);
          }
        }
        final after = TaskStore.validateSemanticHistory(
          app.snapshot.tasks,
          space: space,
          writer: owner,
          textEngine: engine,
        );
        expect(
          after.singleWhere((r) => r['id'] == task)['title'],
          'Native text through one app history',
        );
        expect(
          app.snapshot.foodAdmission.state.containers.map(
            (c) => c.details.name,
          ),
          containsAll(['Synthetic beans', 'Interleaved Food command']),
        );
        expect(
          profile.database.select('SELECT * FROM protected_app_outbox'),
          isEmpty,
        );
        expect(tasks.pendingTextOperations, isEmpty);
        expect(
          profile.database.select('SELECT * FROM protected_text_intents'),
          isEmpty,
        );
        for (final e in sources.entries) {
          expect(
            await folder.read(e.key),
            e.value,
            reason: 'Original semantic bytes remain exact',
          );
        }
      } finally {
        await food?.close();
        await tasks?.close();
        await app?.close();
        await profile.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'mixed native edit and Food add wait for delayed text initialization',
    () async {
      const peer = fixture.peer, space = fixture.space;
      final root = await Directory.systemTemp.createTemp(
        'unified-native-wait-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      LocalProfileDatabase? profile;
      TaskStore? legacy;
      UnifiedHistory? app;
      try {
        final source = LocalLogFolder(
          (await Directory('${root.path}/source').create()).path,
        );
        await source.create(
          'tandemlog-space.json',
          Uint8List.fromList(utf8.encode(jsonEncode({'v': 3, 'id': space}))),
        );
        await source.create(
          '$owner.jsonl',
          Uint8List.fromList(fixture.sources()['$owner.jsonl']!),
        );
        legacy = await TaskStore.open(
          source,
          '${root.path}/peer',
          writerIdentity: peer,
          textEngine: engine,
        );
        final baseline = await legacy
            .initializeSharedTextForHistoricalFixture();
        await legacy.close();
        legacy = null;
        legacy = await TaskStore.open(
          source,
          '${root.path}/owner',
          writerIdentity: owner,
          textEngine: engine,
        );
        final capture = await legacy.captureTaskText(task);
        final field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Delayed native basis arrived');
        final prepared = draft.prepareSave();
        final change = {
          'context': field.context,
          'allocation': field.allocation,
          'actor': field.actor,
          'update': prepared.update.encoded,
        };
        draft.cancel();
        legacy.releaseTextCapture(capture);
        await legacy.close();
        legacy = null;
        final folder = LocalLogFolder(
          (await Directory('${root.path}/shared').create()).path,
        );
        final plan = fixture.plan(),
            converted = plan.convert(fixture.ack(plan));
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(utf8.encode(converted.manifest.encode())),
        );
        for (final e in converted.files.entries) {
          await folder.create(e.key, Uint8List.fromList(e.value));
        }
        profile = await LocalProfileDatabase.open('${root.path}/profile');
        profile.transaction(
          () => profile!.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              owner,
              utf8.encode(
                jsonEncode({'writer': owner, 'appearance': 'system'}),
              ),
            ],
          ),
        );
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: owner,
          textEngine: engine,
        );
        final epoch = app.manifest.epoch, head = app.commonHead;
        final editClock = EventClock(baseline.clock.value + BigInt.one);
        final first = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: owner,
          sequence: 6,
          clock: editClock,
          previousHash: head,
          effect: UnifiedEffect(
            'task',
            LogEvent(space, owner, 6, editClock, task, 'task.textEdited', {
              'changes': {'title': change},
            }).encode(previousHash: head),
          ),
          transactionStart: 6,
          transactionCount: 2,
          transactionIndex: 0,
          observed: {owner: UnifiedFrontier(5, head)},
        );
        final clock = EventClock(editClock.value + BigInt.one);
        final second = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: owner,
          sequence: 7,
          clock: clock,
          previousHash: first.hash,
          effect: UnifiedEffect(
            'food',
            FoodRecord(
              unified: true,
              space: space,
              writer: owner,
              sequence: 7,
              clock: clock,
              previousHash: first.hash,
              operation: FoodOperation(
                id: '$owner:7',
                order: clock.value.toInt(),
                action: FoodAction.add,
                targets: ['55555555-5555-4555-8555-555555555555'],
                details: const FoodDetails(name: 'Wait for native edit'),
                createdAt: '2026-10-18T00:00:00Z',
              ),
            ).encode(),
          ),
          transactionStart: 6,
          transactionCount: 2,
          transactionIndex: 1,
          observed: first.observed,
        );
        await folder.append(
          unifiedLogName(owner),
          Uint8List.fromList(
            utf8.encode('${first.encode()}\n${second.encode()}\n'),
          ),
        );
        final waiting = await app.refresh();
        expect(waiting.pendingEffects, isTrue);
        expect(waiting.tasks.any((e) => e.id == '$owner:6'), isFalse);
        expect(waiting.food.any((e) => e.id == '$owner:7'), isFalse);
        await app.close();
        app = null;
        await profile.close();
        profile = null;
        profile = await LocalProfileDatabase.open('${root.path}/profile');
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: owner,
          textEngine: engine,
        );
        expect(app.snapshot.pendingEffects, isTrue);
        final genesis = unifiedGenesis(space, epoch, peer);
        final rootRecord = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: peer,
          sequence: 1,
          clock: baseline.clock,
          previousHash: genesis,
          effect: UnifiedEffect(
            'task',
            LogEvent(
              space,
              peer,
              1,
              baseline.clock,
              space,
              'text.baselineInitialized',
              baseline.data,
            ).encode(previousHash: genesis),
          ),
          transactionStart: 1,
          transactionCount: 1,
          transactionIndex: 0,
          observed: {peer: UnifiedFrontier(0, genesis)},
        );
        await folder.append(
          unifiedLogName(peer),
          Uint8List.fromList(utf8.encode('${rootRecord.encode()}\n')),
        );
        final ready = await app.refresh();
        expect(ready.pendingEffects, isFalse);
        expect(ready.food.any((e) => e.id == '$owner:7'), isTrue);
        final rows = TaskStore.validateSemanticHistory(
          ready.tasks,
          space: space,
          writer: owner,
          textEngine: engine,
        );
        expect(
          rows.singleWhere((r) => r['id'] == task)['title'],
          'Delayed native basis arrived',
        );
      } finally {
        await app?.close();
        await legacy?.close();
        await profile?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'buffered native suffix preserves a previously published v4 Task across reopen',
    () async {
      const wa = fixture.peer,
          wb = '77777777-7777-4777-8777-777777777777',
          freshTask = '55555555-5555-4555-8555-555555555555',
          container = '66666666-6666-4666-8666-666666666666';
      final root = await Directory.systemTemp.createTemp(
        'unified-buffered-native-',
      );
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profile = await LocalProfileDatabase.open('${root.path}/profile');
      UnifiedHistory? app;
      try {
        final plan = UnifiedCutoverPlan.inspect(
          space: fixture.space,
          owners: {owner, wa, wb},
          participants: {owner, wa, wb},
          sources: fixture.sources(),
          hasUnresolvedPreparedWrites: false,
        );
        final cv = plan.convert(
          [owner, wa, wb].map(
            (w) => CutoverAcknowledgement(
              w,
              plan.sourceDigest,
              quiesced: true,
              pendingResolved: true,
            ),
          ),
        );
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(utf8.encode(cv.manifest.encode())),
        );
        for (final e in cv.files.entries) {
          await folder.create(e.key, Uint8List.fromList(e.value));
        }
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              owner,
              utf8.encode(
                jsonEncode({'writer': owner, 'appearance': 'system'}),
              ),
            ],
          ),
        );
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: owner,
          textEngine: engine,
        );
        await app.appendAtomic([
          (seq, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              fixture.space,
              owner,
              seq,
              clock,
              freshTask,
              'task.createdWithText',
              _unifiedCreationData(engine, fixture.peer, 'A'),
            ).encode(previousHash: head),
          ),
        ]);
        final creation = app.snapshot.tasks.singleWhere(
          (e) => e.entity == freshTask,
        );
        final context = TextFieldContext.fromCreation(creation, 'title').hash;
        final packetA = _unifiedPacket(engine, 'A', context, wa, 'AB');
        const allocationB = '88888888-8888-4888-8888-888888888888';
        final actorB = deriveTextActor(context, wb, allocationB);
        final source = engine.createDocument(
          actorClientId: 2,
          limits: const NativeTextLimits(visibleUtf16: 500),
          seed: engine.seedText('A'),
        );
        late Map<String, dynamic> packetB;
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
        final epoch = app.manifest.epoch, space = fixture.space;
        UnifiedRecord edit(
          String writer,
          int delta,
          Map<String, dynamic> packet,
          int count,
        ) {
          final clock = EventClock(creation.clock.value + BigInt.from(delta)),
              genesis = unifiedGenesis(space, epoch, writer);
          return UnifiedRecord(
            space: space,
            epoch: epoch,
            writer: writer,
            sequence: 1,
            clock: clock,
            previousHash: genesis,
            effect: UnifiedEffect(
              'task',
              LogEvent(space, writer, 1, clock, freshTask, 'task.textEdited', {
                'changes': {'title': packet},
              }).encode(previousHash: genesis),
            ),
            transactionStart: 1,
            transactionCount: count,
            transactionIndex: 0,
            observed: {
              writer: UnifiedFrontier(0, genesis),
              owner: UnifiedFrontier(6, app!.commonHead),
            },
          );
        }

        final ea = edit(wa, 10, packetA, 1), eb = edit(wb, 20, packetB, 2);
        final clock = EventClock(eb.clock.value + BigInt.one);
        final food = UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: wb,
          sequence: 2,
          clock: clock,
          previousHash: eb.hash,
          effect: UnifiedEffect(
            'food',
            FoodRecord(
              unified: true,
              space: space,
              writer: wb,
              sequence: 2,
              clock: clock,
              previousHash: eb.hash,
              operation: FoodOperation(
                id: '$wb:2',
                order: clock.value.toInt(),
                action: FoodAction.add,
                targets: [container],
                details: const FoodDetails(name: 'Atomic native suffix'),
                createdAt: '2026-10-18T00:00:00Z',
              ),
            ).encode(),
          ),
          transactionStart: 1,
          transactionCount: 2,
          transactionIndex: 1,
          observed: eb.observed,
        );
        await folder.append(
          unifiedLogName(wb),
          Uint8List.fromList(utf8.encode('${eb.encode()}\n${food.encode()}\n')),
        );
        String title(UnifiedSnapshot s) =>
            TaskStore.validateSemanticHistory(
                  s.tasks,
                  space: space,
                  writer: owner,
                  textEngine: engine,
                ).singleWhere((r) => r['id'] == freshTask)['title']
                as String;
        final waiting = await app.refresh();
        expect(waiting.pendingEffects, isTrue);
        expect(waiting.published[owner], 6);
        expect(title(waiting), 'A');
        expect(waiting.food.any((e) => e.targets.contains(container)), isFalse);
        await app.close();
        app = null;
        app = await UnifiedHistory.open(
          folder,
          profile: profile,
          writer: owner,
          textEngine: engine,
        );
        expect(title(app.snapshot), 'A');
        expect(app.snapshot.published[owner], 6);
        await folder.append(
          unifiedLogName(wa),
          Uint8List.fromList(utf8.encode('${ea.encode()}\n')),
        );
        final ready = await app.refresh();
        expect(ready.pendingEffects, isFalse);
        expect(title(ready), 'ABC');
        expect(ready.food.any((e) => e.targets.contains(container)), isTrue);
        expect(ready.published[owner], 6);
        expect(ready.published[wb], 2);
      } finally {
        await app?.close();
        await profile.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}

Map<String, dynamic> _unifiedCreationData(
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

Map<String, dynamic> _unifiedPacket(
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
