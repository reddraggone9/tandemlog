import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:tandemlog/domain/text_inheritance.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/checklist.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';

List<LogEvent> unrelatedHistory(
  String space, {
  required int count,
  required int notesLength,
}) {
  const writer = '00000000-0000-4000-8000-000000000019';
  const user = '00000000-0000-4000-8000-000000000029';
  const task = '00000000-0000-4000-8000-000000000039';
  final result = <LogEvent>[];
  var head = eventGenesisHash(space, writer);
  for (var i = 0; i < count; i++) {
    final event = LogEvent.decode(
      LogEvent(
        space,
        writer,
        i + 1,
        EventClock(BigInt.from(i + 1)),
        i == 0 ? user : task,
        i == 0
            ? 'user.created'
            : i == 1
            ? 'task.created'
            : 'task.edited',
        i == 0
            ? {'name': 'Synthetic unrelated user'}
            : i == 1
            ? {
                'title': 'Unrelated history',
                'description': '',
                'assignee': user,
              }
            : {'description': '${'n' * notesLength}${i % 2}'},
      ).encode(previousHash: head),
    );
    head = event.integrityHash!;
    result.add(event);
  }
  return result;
}

Future<OperationReceipt> save(
  TaskStore store,
  String entity,
  String text,
) async {
  final capture = await store.captureTaskText(entity);
  OperationReceipt? receipt;
  try {
    final field = capture.fields['title']!;
    final draft = field.document.captureDraft(actorClientId: field.actor)
      ..replaceText(text);
    final prepared = draft.prepareSave();
    await store.editNativeTask(entity, {
      'title': {
        'context': field.context,
        'allocation': field.allocation,
        'actor': field.actor,
        'update': prepared.update.encoded,
      },
    }, onPrepared: (value) => receipt = value);
    prepared.commit(receiptUpdate: prepared.update);
    store.registerTextOperation(receipt!, capture);
    return receipt!;
  } finally {
    store.releaseTextCapture(capture);
  }
}

Future<void> seedHistorical(
  Directory shared,
  int count,
  int notesLength,
) async {
  const space = '00000000-0000-4000-8000-000000000049';
  const epoch = '00000000-0000-4000-8000-000000000059';
  final events = unrelatedHistory(
    space,
    count: count,
    notesLength: notesLength,
  );
  final writer = events.first.writer;
  var head = unifiedGenesis(space, epoch, writer);
  final text = StringBuffer();
  for (final event in events) {
    final record = UnifiedRecord(
      space: space,
      epoch: epoch,
      writer: writer,
      sequence: event.sequence,
      clock: event.clock,
      previousHash: head,
      effect: UnifiedEffect('history.task', event.canonicalRaw!),
    );
    text.writeln(record.encode());
    head = record.hash;
  }
  final bytes = utf8.encode(text.toString());
  final manifest = UnifiedManifest(
    space,
    epoch,
    bytesDigest(utf8.encode('Synthetic adaptive fixture')),
    {
      writer: {
        'count': events.length,
        'head': head,
        'digest': bytesDigest(bytes),
      },
    },
    {writer: writer},
  );
  await File(
    '${shared.path}/${unifiedLogName(writer)}',
  ).writeAsBytes(bytes, flush: true);
  await File(
    '${shared.path}/tandemlog-space.json',
  ).writeAsString(manifest.encode(), flush: true);
}

@pragma('vm:never-inline')
WeakReference<TextResolutionCut> rememberSelected(
  NativeTextEngine engine,
  RecurringTextMemo memo,
  List<String> records,
  Map<String, String> heads,
  Map<String, int> sequences,
  LogEvent completion,
  String grandchild,
) {
  final input = RecurringTextInput.fromSelectedCanonical(
    records,
    heads,
    sequences,
  );
  final cut = input.verifyInheritance(
    completion.data['inheritance'] as Map<String, dynamic>,
    completion: completion,
  );
  expect(
    RecurringTextResolver.fromInput(
      engine,
      input,
      memo: memo,
    ).resolve(grandchild)['title']!.text,
    'Native parent',
  );
  return WeakReference(cut);
}

void main() {
  test('standalone validator cannot mint owning complete-cut selections', () {
    const space = '00000000-0000-4000-8000-000000000049';
    final events = unrelatedHistory(space, count: 4100, notesLength: 2);
    final validator = TaskSemanticValidator(
      space: space,
      writer: events.first.writer,
    );
    try {
      expect(
        validator.validate(events, inputKey: 'caller-key'),
        hasLength(events.length),
      );
      expect(validator.selectText('caller-key', [events.last.entity]), isNull);
      expect(
        validator.selectCopySeedRaws('caller-key', events.last.entity),
        isNull,
      );
      expect(
        validator.selectTagMutationRaws('caller-key', events.last),
        isNull,
      );
      expect(validator.selectedTextReadCount, 0);
    } finally {
      validator.close();
    }
  });

  test(
    'selected memo mode survives weak cut expiry and cannot bless a sparse generic cut',
    () async {
      final root = await Directory.systemTemp.createTemp('adaptive-memo-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final memo = RecurringTextMemo();
      TaskStore? store;
      try {
        final shared = await Directory('${root.path}/shared').create();
        await seedHistorical(shared, 5, 2);
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${root.path}/profile',
          textEngine: engine,
        );
        await store.initializeSharedText();
        final user = const Uuid().v4(), parent = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await store.createTasks({parent: 'Native parent'}, user)).succeeded,
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
        await store.complete(
          parent,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
        );
        final child = const Uuid().v5(parent, 'successor'),
            grandchild = const Uuid().v5(
              const Uuid().v5(parent, 'successor'),
              'successor',
            );
        await store.complete(
          child,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 11),
        );
        final all = store.unified!.snapshot.tasks;
        const historical = '00000000-0000-4000-8000-000000000019';
        final innerHead = all.where((e) => e.writer == historical).last;
        final outerHead = LogEvent.decode(
          LogEvent(
            store.space,
            historical,
            innerHead.sequence + 1,
            EventClock(innerHead.clock.value + BigInt.one),
            innerHead.entity,
            'task.edited',
            {'description': 'Synthetic later historical head'},
          ).encode(previousHash: innerHead.hash),
        );
        final original = all.lastWhere(
          (e) => (e.data['successor'] as Map?)?['id'] == grandchild,
        );
        final proof =
            jsonDecode(jsonEncode(original.data['inheritance']))
                as Map<String, dynamic>;
        (proof['frontiers'] as Map)[historical] = {
          'seq': outerHead.sequence,
          'hash': outerHead.hash,
        };
        final completion = LogEvent.decode(
          LogEvent(
            original.space,
            original.writer,
            original.sequence,
            original.clock,
            original.entity,
            original.type,
            {...original.data, 'inheritance': proof},
          ).encode(previousHash: original.previousHash),
        );
        // The selected index holds the inner head separately. The generic sparse
        // input contains the later head but lacks that nested dependency record.
        final records = [
          for (final e in all)
            if (e.writer != historical && e.id != original.id) e.canonicalRaw!,
          outerHead.canonicalRaw!,
          completion.canonicalRaw!,
        ];
        final heads = {
          for (final e in all) e.id: e.canonicalRaw!,
          outerHead.id: outerHead.canonicalRaw!,
          completion.id: completion.canonicalRaw!,
        };
        final sequences = <String, int>{};
        for (final raw in heads.values) {
          final e = LogEvent.decode(raw);
          if (e.sequence > (sequences[e.writer] ?? 0)) {
            sequences[e.writer] = e.sequence;
          }
        }
        final receipt = rememberSelected(
          engine,
          memo,
          records,
          heads,
          sequences,
          completion,
          grandchild,
        );
        expect(memo.entryCount, greaterThan(0));
        // Bounded heap pressure expires weak receipts without changing cache mode.
        // The correctness assertion is unconditional, including when a VM retains
        // a receipt longer; it never depends on a GC timing success.
        for (var i = 0; i < 8 && receipt.target != null; i++) {
          final pressure = List.generate(16, (_) => Uint8List(4 * 1024 * 1024));
          expect(pressure.length, 16);
          await Future<void>.delayed(Duration.zero);
        }
        // ignore: avoid_print
        print(
          jsonEncode({'adaptiveWeakReceiptExpired': receipt.target == null}),
        );
        final misses = memo.misses;
        expect(
          () => RecurringTextResolver.fromCanonical(
            engine,
            records,
            memo: memo,
          ).resolve(grandchild),
          throwsA(isA<FormatFailure>()),
        );
        expect(memo.misses, greaterThan(misses));
      } finally {
        memo.clear();
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
  );

  for (final copied in [false, true]) {
    for (final laterSeed in [false, true]) {
      test(
        'first derived text ${copied ? 'copy' : 'successor'} ${laterSeed ? 'retains seed-rebind fallback' : 'reuses unchanged earliest readiness'}',
        () async {
          final root = await Directory.systemTemp.createTemp('first-derived-');
          final engine = NativeTextEngine(
            libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
          );
          TaskStore? store;
          TaskSemanticValidator? incremental;
          try {
            final shared = await Directory('${root.path}/shared').create();
            await seedHistorical(shared, 5, 2);
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            await store.initializeSharedText();
            final user = const Uuid().v4(), parent = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            expect(
              (await store.createTasks({
                parent: 'Native parent',
              }, user)).succeeded,
              isTrue,
            );
            await store.edit(
              parent,
              {
                'schedule': {
                  'dueDate': '2030-05-10',
                  'recurrence': 'every day',
                },
              },
              tags: [],
              observedTagRefs: {},
            );
            final item = await store.addChecklistItem(
              parent,
              'Native item',
              notes: 'Notes',
            );
            OperationReceipt? completion;
            await store.complete(
              parent,
              localZoneId: 'UTC',
              completionInstant: DateTime.utc(2030, 5, 10),
              onPrepared: (value) => completion = value,
            );
            final child = const Uuid().v5(parent, 'successor');
            final copy = copiedChecklistId(child, item.entity);
            if (laterSeed) {
              expect(
                (await store.undoOperations([completion!.id])).error,
                isNull,
              );
              await store.edit(
                parent,
                {
                  'schedule': {
                    'dueDate': '2030-05-12',
                    'recurrence': 'every day',
                  },
                },
                tags: [],
                observedTagRefs: {},
              );
              await store.complete(
                parent,
                localZoneId: 'UTC',
                completionInstant: DateTime.utc(2030, 5, 12),
              );
            }
            final target = copied ? copy : child;
            final history = store.unified!;
            final prior = List<LogEvent>.unmodifiable(history.snapshot.tasks);
            expect(prior.where((e) => e.entity == target), isEmpty);
            expect(prior.where((e) => e.entity == child), isEmpty);
            expect(history.snapshot.allVisibleTasksReady, isTrue);
            Map<String, dynamic> childRow() =>
                store!.rows.singleWhere((row) => row['id'] == child);
            expect(
              (childRow()['schedule'] as Map)['dueDate'],
              laterSeed ? '2030-05-13' : '2030-05-11',
            );
            final originalTitle = store.currentTextRow(target)!['title'];
            incremental = TaskSemanticValidator(
              space: store.space,
              writer: store.writer,
              textEngine: engine,
            );
            final priorReady = incremental.validate(
              prior,
              inputKey: 'synthetic-prior',
            );
            expect(priorReady, history.snapshot.readyTaskIds);
            final genericFull = incremental.fullReadinessRuns;
            final full = history.fullTaskReadinessRuns;
            final receipt = await save(store, target, 'First derived title');
            final after = history.snapshot;
            if (laterSeed) {
              expect(history.fullTaskReadinessRuns, greaterThan(full));
            } else {
              expect(history.fullTaskReadinessRuns, full);
            }
            final ready = incremental.validate(
              List<LogEvent>.unmodifiable(after.tasks),
              inputKey: 'synthetic-after',
            );
            if (laterSeed) {
              expect(incremental.fullReadinessRuns, greaterThan(genericFull));
            } else {
              expect(incremental.fullReadinessRuns, genericFull);
            }
            expect(ready, after.readyTaskIds);
            expect(after.allVisibleTasksReady, isTrue);
            expect(
              store.currentTextRow(target)!['title'],
              'First derived title',
            );
            // A first copy activity protects its derived parent too. A later
            // survivor must rebind under the original full readiness policy.
            expect((childRow()['schedule'] as Map)['dueDate'], '2030-05-11');
            expect(
              store.rows,
              TaskStore.validateSemanticHistory(
                after.tasks,
                space: store.space,
                writer: store.writer,
                textEngine: engine,
              ),
            );
            final capture = await store.captureTaskText(target);
            try {
              final field = capture.fields['title']!;
              final resolution = RecurringTextResolver.fromCanonical(
                engine,
                after.tasks.map((e) => e.canonicalRaw!),
              ).resolve(target)['title']!;
              expect(field.context, resolution.context.hash);
              expect(field.document.read().text, resolution.text);
            } finally {
              store.releaseTextCapture(capture);
            }
            expect((await store.undoOperations([receipt.id])).error, isNull);
            expect(store.currentTextRow(target)!['title'], originalTitle);
            expect(
              store.rows,
              TaskStore.validateSemanticHistory(
                history.snapshot.tasks,
                space: store.space,
                writer: store.writer,
                textEngine: engine,
              ),
            );
          } finally {
            incremental?.close();
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(seconds: 120)),
        skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
      );
    }
  }

  for (final action in ['tags', 'mixed', 'checkbox', 'references']) {
    for (final laterSeed in [false, true]) {
      if (action == 'references' && laterSeed) continue;
      test(
        'first derived $action ${laterSeed ? 'retains real seed-rebind fallback' : 'reuses exact earliest readiness'}',
        () async {
          final root = await Directory.systemTemp.createTemp('first-metadata-');
          final engine = NativeTextEngine(
            libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
          );
          TaskStore? store;
          TaskSemanticValidator? incremental;
          TaskTextSession? session;
          TaskTextCapture? heldCapture;
          try {
            final shared = await Directory('${root.path}/shared').create();
            await seedHistorical(shared, 5, 2);
            store = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/profile',
              textEngine: engine,
            );
            await store.initializeSharedText();
            final user = const Uuid().v4(), parent = const Uuid().v4();
            await store.command(user, 'user.created', {'name': 'Synthetic'});
            expect(
              (await store.createTasks({
                parent: 'Native parent',
              }, user)).succeeded,
              isTrue,
            );
            await store.edit(
              parent,
              {
                'schedule': {
                  'dueDate': '2030-05-10',
                  'recurrence': 'every day',
                },
              },
              tags: [],
              observedTagRefs: {},
            );
            final item = await store.addChecklistItem(
              parent,
              'Native item',
              notes: 'Notes',
            );
            OperationReceipt? completion;
            await store.complete(
              parent,
              localZoneId: 'UTC',
              completionInstant: DateTime.utc(2030, 5, 10),
              onPrepared: (value) => completion = value,
            );
            final child = const Uuid().v5(parent, 'successor');
            final copy = copiedChecklistId(child, item.entity);
            if (laterSeed) {
              expect(
                (await store.undoOperations([completion!.id])).error,
                isNull,
              );
              await store.edit(
                parent,
                {
                  'schedule': {
                    'dueDate': '2030-05-12',
                    'recurrence': 'every day',
                  },
                },
                tags: [],
                observedTagRefs: {},
              );
              await store.complete(
                parent,
                localZoneId: 'UTC',
                completionInstant: DateTime.utc(2030, 5, 12),
              );
            }
            final target = action == 'checkbox' ? copy : child;
            final history = store.unified!;
            final prior = List<LogEvent>.unmodifiable(history.snapshot.tasks);
            expect(prior.where((e) => e.entity == target), isEmpty);
            expect(prior.where((e) => e.entity == child), isEmpty);
            expect(history.snapshot.allVisibleTasksReady, isTrue);
            Map<String, dynamic> childRow() =>
                store!.rows.singleWhere((row) => row['id'] == child);
            expect(
              (childRow()['schedule'] as Map)['dueDate'],
              laterSeed ? '2030-05-13' : '2030-05-11',
            );
            final originalTitle = store.currentTextRow(target)!['title'];
            final originalAssignee = childRow()['assignee'];
            if (action == 'references') {
              // A private seed proof must never stand in for a ready user or
              // observed tag dependency. Neither failure may reserve bytes.
              final before = history.snapshot;
              final beforeRows = store.rows;
              final beforeBytes = await File(
                '${shared.path}/${store.writer}.applog',
              ).readAsBytes();
              var prepared = false;
              for (final fields in [
                {'assignee': const Uuid().v4()},
                {'assignee': parent},
              ]) {
                await expectLater(
                  store.edit(
                    target,
                    fields,
                    tags: [],
                    observedTagRefs: {},
                    onPrepared: (_) => prepared = true,
                  ),
                  throwsA(isA<FormatFailure>()),
                );
              }
              await expectLater(
                store.edit(
                  target,
                  {},
                  tags: [],
                  observedTagRefs: {'${store.writer}:999999:0': 'missing'},
                  onPrepared: (_) => prepared = true,
                ),
                throwsA(isA<FormatFailure>()),
              );
              expect(prepared, isFalse);
              expect(history.hasPending, isFalse);
              expect(identical(history.snapshot, before), isTrue);
              expect(store.rows, beforeRows);
              expect(
                await File(
                  '${shared.path}/${store.writer}.applog',
                ).readAsBytes(),
                beforeBytes,
              );
            }
            incremental = TaskSemanticValidator(
              space: store.space,
              writer: store.writer,
              textEngine: engine,
            );
            final priorReady = incremental.validate(
              prior,
              inputKey: 'synthetic-prior',
            );
            expect(priorReady, history.snapshot.readyTaskIds);
            final genericFull = incremental.fullReadinessRuns;
            final full = history.fullTaskReadinessRuns;
            OperationReceipt? receipt;
            if (action == 'checkbox') {
              await store.setChecklistCompleted(
                target,
                true,
                onPrepared: (value) => receipt = value,
              );
            } else if (action == 'tags' || action == 'references') {
              await store.edit(
                target,
                {'assignee': user},
                tags: ['First metadata'],
                observedTagRefs: {},
                onPrepared: (value) => receipt = value,
              );
            } else {
              final capture = await store.captureTaskText(target);
              heldCapture = capture;
              session = TaskTextSession(
                capture,
                registerDraftActor: (field, allocation, actor) => store!
                    .registerTextDraftActor(capture, field, allocation, actor),
              );
              session.replace('title', 'First mixed title');
              final result = await TextSaveCommand(store, session).save(
                fields: {
                  'schedule': {
                    ...childRow()['schedule'] as Map<String, dynamic>,
                    'dueDate': '2030-05-14',
                  },
                },
                tags: ['First mixed'],
                observedTagRefs: {},
                expectedSnapshot: store.taskSnapshot,
              );
              expect(result.status, TextSaveStatus.saved);
              expect(result.undoError, isNull);
              expect(result.sessionError, isNull);
              receipt = result.receipt;
            }
            expect(receipt, isNotNull);
            final after = history.snapshot;
            if (laterSeed) {
              expect(history.fullTaskReadinessRuns, greaterThan(full));
            } else if (action != 'references') {
              expect(history.fullTaskReadinessRuns, full);
            }
            // A rejected candidate may discard scratch SQL. The references
            // case checks recovery, independently of warm-path counters.
            final ready = incremental.validate(
              List<LogEvent>.unmodifiable(after.tasks),
              inputKey: 'synthetic-after',
            );
            if (laterSeed) {
              expect(incremental.fullReadinessRuns, greaterThan(genericFull));
            } else {
              expect(incremental.fullReadinessRuns, genericFull);
            }
            expect(ready, after.readyTaskIds);
            expect(after.allVisibleTasksReady, isTrue);
            if (action == 'mixed') {
              expect(
                store.currentTextRow(target)!['title'],
                'First mixed title',
              );
              expect(childRow()['tags'], contains('First mixed'));
            } else if (action == 'tags' || action == 'references') {
              expect(childRow()['tags'], contains('First metadata'));
              expect(childRow()['assignee'], user);
            } else {
              expect(store.currentTextRow(target)!['completed'], isTrue);
            }
            // A first copy activity protects its derived parent too. A later
            // survivor must rebind under the original full readiness policy.
            expect(
              (childRow()['schedule'] as Map)['dueDate'],
              action == 'mixed' ? '2030-05-14' : '2030-05-11',
            );
            expect(
              store.rows,
              TaskStore.validateSemanticHistory(
                after.tasks,
                space: store.space,
                writer: store.writer,
                textEngine: engine,
              ),
            );
            final capture = await store.captureTaskText(target);
            try {
              final field = capture.fields['title']!;
              final resolution = RecurringTextResolver.fromCanonical(
                engine,
                after.tasks.map((e) => e.canonicalRaw!),
              ).resolve(target)['title']!;
              expect(field.context, resolution.context.hash);
              expect(field.document.read().text, resolution.text);
            } finally {
              store.releaseTextCapture(capture);
            }
            expect((await store.undoOperations([receipt!.id])).error, isNull);
            expect(store.currentTextRow(target)!['title'], originalTitle);
            expect(childRow()['tags'], isEmpty);
            expect(childRow()['assignee'], originalAssignee);
            if (action == 'checkbox') {
              expect(store.currentTextRow(target)!['completed'], isFalse);
            }
            expect((childRow()['schedule'] as Map)['dueDate'], '2030-05-11');
            final undoReady = incremental.validate(
              List<LogEvent>.unmodifiable(history.snapshot.tasks),
              inputKey: 'synthetic-undo',
            );
            expect(undoReady, history.snapshot.readyTaskIds);
            expect(history.snapshot.allVisibleTasksReady, isTrue);
            expect(
              store.rows,
              TaskStore.validateSemanticHistory(
                history.snapshot.tasks,
                space: store.space,
                writer: store.writer,
                textEngine: engine,
              ),
            );
          } finally {
            session?.cancel();
            if (heldCapture != null) store?.releaseTextCapture(heldCapture);
            incremental?.close();
            await store?.close();
            engine.dispose();
            await root.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(seconds: 120)),
        skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
      );
    }
  }

  test(
    'owned copy seeds stay scoped beyond the real descriptor payload budget',
    () async {
      final root = await Directory.systemTemp.createTemp('copy-budget-');
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
        final user = const Uuid().v4(),
            unrelated = const Uuid().v4(),
            target = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        expect(
          (await store.createTasks({
            unrelated: 'Unrelated recurring history',
            target: 'Target parent',
          }, user)).succeeded,
          isTrue,
        );
        for (final id in [unrelated, target]) {
          await store.edit(
            id,
            {
              'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
            },
            tags: [],
            observedTagRefs: {},
          );
        }
        for (var i = 0; i < 32; i++) {
          await store.addChecklistItem(
            unrelated,
            '${'x' * 480} $i',
            notes: 'Long synthetic item',
          );
        }
        int descriptorBytes() =>
            store!.db
                    .select(
                      "SELECT COALESCE(SUM(length(CAST(raw AS BLOB))),0) AS bytes FROM ${store.tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist'",
                    )
                    .single['bytes']
                as int;
        var cycles = 0;
        while (descriptorBytes() * 4 <= 4 * 1024 * 1024 && cycles < 32) {
          OperationReceipt? completion;
          await store.complete(
            unrelated,
            localZoneId: 'UTC',
            completionInstant: DateTime.utc(2030, 5, 10),
            onPrepared: (value) => completion = value,
          );
          expect((await store.undoOperations([completion!.id])).error, isNull);
          cycles++;
        }
        expect(
          descriptorBytes() * 4,
          greaterThan(4 * 1024 * 1024),
          reason:
              'Actual app-produced copied descriptors, not unrelated Notes, must exceed the unchanged fallback cap.',
        );
        final item = await store.addChecklistItem(
          target,
          'Target item',
          notes: 'Target Notes',
        );
        await store.complete(
          target,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2030, 5, 10),
        );
        final child = const Uuid().v5(target, 'successor');
        final copy = copiedChecklistId(child, item.entity);
        final current = store.unified!.snapshot;
        expect(
          store.unified!.selectTaskCopySeedRaws(current, unrelated),
          isEmpty,
          reason:
              'A parent has no copy claim even when its text closure contains many completions.',
        );
        expect(
          store.unified!.selectTaskCopySeedRaws(current, copy),
          hasLength(1),
        );
        final reads = store.selectedCopySeedReads,
            visited = store.selectedCopySeedRecords,
            readiness = store.unified!.fullTaskReadinessRuns;
        final receipt = await save(store, copy, 'Changed copied title');
        expect(store.unified!.fullTaskReadinessRuns, readiness);
        expect(store.selectedCopySeedReads, greaterThan(reads));
        final saveVisits = store.selectedCopySeedRecords - visited;
        expect(
          saveVisits,
          lessThan(20),
          reason:
              'The target closure must not scan unrelated historical completions.',
        );
        expect(
          store.rows.singleWhere((r) => r['id'] == child)['checklist'],
          contains(
            isA<Map>().having(
              (r) => r['title'],
              'title',
              'Changed copied title',
            ),
          ),
        );
        expect((await store.undoOperations([receipt.id])).error, isNull);
        final oracle = TaskStore.validateSemanticHistory(
          store.unified!.snapshot.tasks,
          space: store.space,
          writer: store.writer,
          textEngine: engine,
        );
        expect(store.rows, oracle);
        // ignore: avoid_print
        print(
          jsonEncode({
            'copyDescriptorBytes': descriptorBytes(),
            'completionUndoCycles': cycles,
            'saveDescriptorVisits': saveVisits,
            'saveAndUndoDescriptorVisits':
                store.selectedCopySeedRecords - visited,
          }),
        );
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 120)),
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
  );

  for (final shape in [(120, 2), (4100, 2), (450, 9900)]) {
    test(
      'owned physical workspace selection matches full oracle past caps $shape',
      () async {
        final root = await Directory.systemTemp.createTemp('adaptive-text-');
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        TaskStore? producer, peer, competitor;
        Object? blocker;
        try {
          final shared = await Directory('${root.path}/shared').create();
          await seedHistorical(shared, shape.$1, shape.$2);
          producer = await TaskStore.open(
            LocalLogFolder(shared.path),
            '${root.path}/profile',
            textEngine: engine,
          );
          await producer.initializeSharedText();
          final user = const Uuid().v4(), parent = const Uuid().v4();
          await producer.command(user, 'user.created', {'name': 'Synthetic'});
          expect(
            (await producer.createTasks({
              parent: 'Native parent',
            }, user)).succeeded,
            isTrue,
          );
          await producer.edit(
            parent,
            {
              'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
            },
            tags: [],
            observedTagRefs: {},
          );
          final item = await producer.addChecklistItem(
            parent,
            'Native item',
            notes: 'Notes',
          );
          Directory? competitorShared;
          if (shape.$1 > 4096) {
            competitorShared = await Directory(
              '${root.path}/competitor-shared',
            ).create();
            for (final entry
                in await shared
                    .list()
                    .where((f) => f is File)
                    .cast<File>()
                    .toList()) {
              await entry.copy(
                '${competitorShared.path}/${entry.uri.pathSegments.last}',
              );
            }
            competitor = await TaskStore.open(
              LocalLogFolder(competitorShared.path),
              '${root.path}/competitor-profile',
              textEngine: engine,
            );
          }
          await producer.complete(
            parent,
            localZoneId: 'UTC',
            completionInstant: DateTime.utc(2030, 5, 10),
          );
          if (competitor != null) {
            await competitor.complete(
              parent,
              localZoneId: 'UTC',
              completionInstant: DateTime.utc(2030, 5, 10),
            );
            await File(
              '${competitorShared!.path}/${competitor.writer}.applog',
            ).copy('${shared.path}/${competitor.writer}.applog');
            await producer.refresh();
            await competitor.close();
            competitor = null;
          }

          final child = const Uuid().v5(parent, 'successor'),
              copy = copiedChecklistId(child, item.entity);
          final history = producer.unified!, snapshot = history.snapshot;
          final selected = history.selectTaskText(snapshot, [child, copy])!;
          expect(selected.records.length, lessThan(40));
          expect(selected.lookups, lessThan(100));
          expect(
            selected.records.any((raw) => raw.contains('Unrelated history')),
            isFalse,
          );
          final input = RecurringTextInput.fromSelectedCanonical(
            selected.records,
            selected.heads,
            selected.sequences,
          );
          expect(input.isSelected, isTrue);
          expect(input.cacheable, isFalse);
          final full = RecurringTextInput.fromCanonical(
            snapshot.tasks.map((e) => e.canonicalRaw!),
          );
          expect(full.cacheable, shape == (120, 2));
          for (final id in [child, copy]) {
            final a = RecurringTextResolver.fromInput(
              engine,
              input,
            ).resolve(id);
            final b = RecurringTextResolver.fromInput(engine, full).resolve(id);
            for (final field in ['title', 'description']) {
              expect(a[field]!.text, b[field]!.text);
              expect(a[field]!.context.hash, b[field]!.context.hash);
              expect(
                a[field]!.historyReference!.hash,
                b[field]!.historyReference!.hash,
              );
            }
          }
          expect(input.selectedDecodedRecordCount, lessThan(50));
          // ignore: avoid_print
          print(
            jsonEncode({
              'adaptiveHistoricalRecords': shape.$1,
              'notesChars': shape.$2,
              'selectedRecords': selected.records.length,
              'relationLookups': selected.lookups,
              'strictSelectedAndHeadDecodes': input.selectedDecodedRecordCount,
            }),
          );

          final completion = snapshot.tasks.lastWhere(
            (event) => (event.data['successor'] as Map?)?['id'] == child,
          );
          final descriptor =
              completion.data['inheritance'] as Map<String, dynamic>;
          final frontier = (descriptor['frontiers'] as Map).entries.firstWhere(
            (entry) => (entry.value as Map)['seq'] != 0,
          );
          final id = '${frontier.key}:${(frontier.value as Map)['seq']}';
          final withoutHead = {...selected.heads}..remove(id);
          expect(
            RecurringTextInput.fromSelectedCanonical(
              selected.records,
              withoutHead,
              selected.sequences,
            ).verifyInheritance(descriptor, completion: completion).isPending,
            isTrue,
          );
          final originalHead = LogEvent.decode(selected.heads[id]!);
          for (final forward in [false, true]) {
            final badHead = LogEvent.decode(
              LogEvent(
                forward ? originalHead.space : const Uuid().v4(),
                originalHead.writer,
                originalHead.sequence,
                forward
                    ? EventClock(completion.clock.value + BigInt.one)
                    : originalHead.clock,
                originalHead.entity,
                originalHead.type,
                originalHead.data,
                hash: originalHead.hash,
              ).encode(previousHash: originalHead.previousHash),
            );
            final badHeads = {...selected.heads, id: badHead.canonicalRaw!};
            expect(
              () => RecurringTextInput.fromSelectedCanonical(
                selected.records,
                badHeads,
                selected.sequences,
              ).verifyInheritance(descriptor, completion: completion),
              throwsA(isA<FormatFailure>()),
            );
          }

          final beforeReads = producer.selectedTextReads;
          final beforeCopies = producer.selectedCopySeedReads;
          final beforeCopyRecords = producer.selectedCopySeedRecords;
          await save(producer, child, 'Changed derived title');
          expect(producer.selectedCopySeedReads, greaterThan(beforeCopies));
          expect(
            producer.selectedCopySeedRecords - beforeCopyRecords,
            lessThan(40),
            reason:
                'Owned copy lookup must visit the selected claims, including competing seeds, rather than all historical descriptors.',
          );
          expect(
            history.selectTaskText(snapshot, [child]),
            isNull,
            reason:
                'Old owning snapshot cannot borrow advanced candidate scratch SQL.',
          );
          expect(producer.selectedTextReads, greaterThan(beforeReads));
          final next = history.selectTaskText(history.snapshot, [child])!;
          expect(
            RecurringTextResolver.fromInput(
              engine,
              RecurringTextInput.fromSelectedCanonical(
                next.records,
                next.heads,
                next.sequences,
              ),
            ).resolve(child)['title']!.text,
            'Changed derived title',
          );
          await save(producer, copy, 'Changed copied title');
          final oracle = TaskStore.validateSemanticHistory(
            history.snapshot.tasks,
            space: producer.space,
            writer: producer.writer,
            textEngine: engine,
          );
          final liveChild = producer.rows.singleWhere((r) => r['id'] == child);
          final oracleChild = oracle.singleWhere((r) => r['id'] == child);
          expect(liveChild, oracleChild);
          expect(
            (liveChild['checklist'] as List).cast<Map>().singleWhere(
              (item) => item['id'] == copy,
            )['title'],
            'Changed copied title',
          );

          if (shape.$1 > 4096) {
            peer = await TaskStore.open(
              LocalLogFolder(shared.path),
              '${root.path}/peer-profile',
              textEngine: engine,
            );
            await producer.refresh();
            final scratchBefore = history.taskSelectedReadCount;
            await save(peer, child, 'Peer admitted title');
            await producer.refresh();
            expect(
              history.taskSelectedReadCount,
              scratchBefore,
              reason:
                  'Generic above-cap peer validation must use the full oracle.',
            );
            expect(
              producer.rows.singleWhere((row) => row['id'] == child)['title'],
              'Peer admitted title',
            );
            final oldSnapshot = history.snapshot;
            final oldRows = producer.taskSnapshot;
            blocker = Object();
            var reject = false;
            await history.profile.serialize(() async {
              history.attachProjectionInProfileQueue(blocker!, (candidate) {
                if (reject && candidate.revision != oldSnapshot.revision) {
                  throw FormatFailure(
                    'Synthetic late adaptive projection failure',
                  );
                }
                return () {};
              });
            });
            reject = true;
            await save(peer, child, 'Peer after rollback');
            await expectLater(
              producer.refresh(),
              throwsA(isA<FormatFailure>()),
            );
            expect(producer.taskSnapshot, oldRows);
            expect(identical(history.snapshot, oldSnapshot), isTrue);
            expect(history.selectTaskCopySeedRaws(oldSnapshot, copy), isNull);
            expect(
              history.selectTaskText(oldSnapshot, [child]),
              isNull,
              reason:
                  'Rolled-back main SQL cannot borrow advanced scratch state.',
            );
            reject = false;
            await producer.refresh();
            expect(
              producer.rows.singleWhere((row) => row['id'] == child)['title'],
              'Peer after rollback',
            );
            final fallbackOracle = TaskStore.validateSemanticHistory(
              history.snapshot.tasks,
              space: producer.space,
              writer: producer.writer,
              textEngine: engine,
            );
            expect(producer.rows, fallbackOracle);
            await history.profile.serialize(() async {
              history.detachProjectionInProfileQueue(blocker!);
            });
            blocker = null;
            await peer.close();
            peer = null;
          }
          if (shape.$1 > 4096) {
            const legacy = '00000000-0000-4000-8000-000000000039';
            await producer.edit(
              legacy,
              {
                'schedule': {
                  'dueDate': '2030-05-10',
                  'recurrence': 'every day',
                },
              },
              tags: [],
              observedTagRefs: {},
            );
            await producer.complete(
              legacy,
              localZoneId: 'UTC',
              completionInstant: DateTime.utc(2030, 5, 10),
            );
            final legacyChild = const Uuid().v5(legacy, 'successor');
            final capture = await producer.captureTaskText(legacyChild);
            expect(capture.fields['description']!.document.read().text, 'nn1');
            producer.releaseTextCapture(capture);
            final legacyOracle = TaskStore.validateSemanticHistory(
              history.snapshot.tasks,
              space: producer.space,
              writer: producer.writer,
              textEngine: engine,
            );
            expect(producer.rows, legacyOracle);
          }
          final before = producer.taskSnapshot;
          final logs = {
            for (final f in await LocalLogFolder(shared.path).list())
              f.name: await File('${shared.path}/${f.name}').readAsBytes(),
          };
          await producer.close();
          producer = null;
          producer = await TaskStore.open(
            LocalLogFolder(shared.path),
            '${root.path}/profile',
            textEngine: engine,
          );
          expect(producer.taskSnapshot, before);
          for (final entry in logs.entries) {
            expect(
              await File('${shared.path}/${entry.key}').readAsBytes(),
              entry.value,
            );
          }
        } finally {
          if (blocker != null && producer != null) {
            await producer.unified!.profile.serialize(() async {
              producer!.unified!.detachProjectionInProfileQueue(blocker!);
            });
          }
          await competitor?.close();
          await peer?.close();
          await producer?.close();
          engine.dispose();
          await root.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
      skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null,
    );
  }
}
