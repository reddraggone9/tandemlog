import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_import.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:uuid/uuid.dart';

const writer = '22222222-2222-4222-8222-222222222222';
const person = '33333333-3333-4333-8333-333333333333';
const container = '44444444-4444-4444-8444-444444444444';

class ActionFolder extends LocalLogFolder {
  ActionFolder(super.location);
  int? cut;
  bool uncertain = false, ignoreCleanup = false;
  int writes = 0, cleanups = 0;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    writes++;
    final n = cut;
    cut = null;
    await super.append(
      name,
      n == null ? bytes : Uint8List.fromList(bytes.take(n).toList()),
    );
    if (n != null || uncertain) {
      uncertain = false;
      throw StateError('synthetic uncertain append');
    }
  }

  @override
  Future<void> create(String name, Uint8List bytes) async {
    writes++;
    final n = cut;
    cut = null;
    await super.create(
      name,
      n == null ? bytes : Uint8List.fromList(bytes.take(n).toList()),
    );
    if (n != null || uncertain) {
      uncertain = false;
      throw StateError('synthetic uncertain create');
    }
  }

  @override
  Future<void> truncateOwnedTail(
    String name,
    Uint8List expected,
    int keepBytes,
  ) async {
    cleanups++;
    if (ignoreCleanup) {
      return;
    }
    await super.truncateOwnedTail(name, expected, keepBytes);
  }
}

void main() {
  late Directory root;
  late ActionFolder folder;
  late LocalProfileDatabase profile;
  late UnifiedHistory history;
  TaskStore? tasks;
  FoodStore? food;
  Future<LocalProfileDatabase> openProfile(String path) async {
    final p = await LocalProfileDatabase.open(path);
    if (p.database.select('SELECT 1 FROM protected_settings').isEmpty) {
      p.transaction(
        () => p.database.execute(
          'INSERT INTO protected_settings VALUES (1,?,?)',
          [
            writer,
            utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
          ],
        ),
      );
    }
    return p;
  }

  UnifiedEffectBuilder user(String id, String name) =>
      (seq, clock, head) => UnifiedEffect(
        'task',
        LogEvent(
          history.manifest.space,
          writer,
          seq,
          clock,
          id,
          'user.created',
          {'name': name},
        ).encode(previousHash: head),
      );
  UnifiedEffectBuilder beans() =>
      (seq, clock, head) => UnifiedEffect(
        'food',
        FoodRecord(
          space: history.manifest.space,
          writer: writer,
          sequence: seq,
          clock: clock,
          previousHash: head,
          operation: FoodOperation(
            id: '$writer:$seq',
            order: clock.value.toInt(),
            action: FoodAction.add,
            targets: [container],
            details: const FoodDetails(name: 'Beans'),
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-21T00:00:00Z',
          ),
        ).encode(),
      );
  Future<Uint8List> bytes() => folder.read(unifiedLogName(writer));
  Future<void> reopen({bool fresh = false}) async {
    await food?.close();
    food = null;
    await tasks?.close();
    tasks = null;
    await history.close();
    await profile.close();
    profile = await openProfile('${root.path}/${fresh ? 'fresh' : 'profile'}');
    history = await UnifiedHistory.open(
      folder,
      profile: profile,
      writer: writer,
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('synthetic-action-history-');
    folder = ActionFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    profile = await openProfile('${root.path}/profile');
    history = await UnifiedHistory.create(
      folder,
      profile: profile,
      writer: writer,
    );
  });
  tearDown(() async {
    await food?.close();
    food = null;
    await tasks?.close();
    tasks = null;
    await history.close();
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'the first effect cannot precede the action observed head even if its last effect has a later clock',
    () async {
      await history.appendAtomic([user(person, 'Before')]);
      final old = history.snapshot, prior = history.maximumClock!;
      final seq = history.logicalSequence;
      final first = user(const Uuid().v4(), 'Early')(
        seq + 1,
        EventClock(prior.value - BigInt.one),
        history.commonHead,
      );
      final last = user(const Uuid().v4(), 'Late')(
        seq + 2,
        EventClock(prior.value + BigInt.one),
        first.integrityHash,
      );
      final action = UnifiedRecord(
        space: history.manifest.space,
        epoch: history.manifest.epoch,
        writer: writer,
        sequence: history.physicalSequence + 1,
        clock: last.clock,
        previousHash: history.commonHead,
        effects: [first, last],
        observed: {
          writer: UnifiedFrontier(history.physicalSequence, history.commonHead),
        },
      );
      await folder.append(
        unifiedLogName(writer),
        Uint8List.fromList(utf8.encode('${action.encode()}\n')),
      );
      final evidence = await bytes();
      await expectLater(history.refresh(), throwsA(isA<FormatFailure>()));
      expect(history.snapshot, old);
      final cold = await openProfile('${root.path}/independent-cold');
      try {
        await expectLater(
          UnifiedHistory.open(folder, profile: cold, writer: writer),
          throwsA(isA<FormatFailure>()),
        );
      } finally {
        await cold.close();
      }
      expect(await bytes(), evidence);
    },
  );

  test(
    'all effects must follow a declared peer frontier, not only the outer last clock',
    () async {
      await history.appendAtomic([user(person, 'Observed')]);
      final peer = const Uuid().v4(),
          firstId = const Uuid().v4(),
          lastId = const Uuid().v4();
      final genesis = unifiedGenesis(
        history.manifest.space,
        history.manifest.epoch,
        peer,
      );
      final joined = UnifiedRecord(
        space: history.manifest.space,
        epoch: history.manifest.epoch,
        writer: peer,
        sequence: 1,
        clock: EventClock(BigInt.one),
        previousHash: genesis,
        effect: UnifiedEffect.joined(),
        observed: {peer: UnifiedFrontier(0, genesis)},
      );
      final base = history.maximumClock!.value;
      UnifiedEffect create(int seq, BigInt clock, String id, String head) =>
          UnifiedEffect(
            'task',
            LogEvent(
              history.manifest.space,
              peer,
              seq,
              EventClock(clock),
              id,
              'user.created',
              {'name': 'Peer'},
            ).encode(previousHash: head),
          );
      final first = create(1, base - BigInt.one, firstId, joined.hash);
      final last = create(2, base + BigInt.one, lastId, first.integrityHash);
      final bad = UnifiedRecord(
        space: history.manifest.space,
        epoch: history.manifest.epoch,
        writer: peer,
        sequence: 2,
        clock: last.clock,
        previousHash: joined.hash,
        effects: [first, last],
        observed: {
          peer: UnifiedFrontier(1, joined.hash),
          writer: UnifiedFrontier(history.physicalSequence, history.commonHead),
        },
      );
      await folder.create(
        unifiedLogName(peer),
        Uint8List.fromList(
          utf8.encode('${joined.encode()}\n${bad.encode()}\n'),
        ),
      );
      final before = history.snapshot,
          evidence = await folder.read(unifiedLogName(peer));
      await expectLater(history.refresh(), throwsA(isA<FormatFailure>()));
      expect(history.snapshot, before);
      final cold = await openProfile('${root.path}/peer-cold');
      try {
        await expectLater(
          UnifiedHistory.open(folder, profile: cold, writer: writer),
          throwsA(isA<FormatFailure>()),
        );
      } finally {
        await cold.close();
      }
      expect(await folder.read(unifiedLogName(peer)), evidence);
    },
  );

  test(
    'unconfirmed provider suffix cleanup refuses before appending another action',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      final baseline = await bytes();
      folder.cut = 20;
      await expectLater(history.appendAtomic([beans()]), throwsStateError);
      await reopen();
      final partial = await bytes(), writes = folder.writes;
      final next = const Uuid().v4();
      folder.ignoreCleanup = true;
      await expectLater(
        history.appendAtomic([user(next, 'New explicit action')]),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        folder.writes,
        writes,
        reason:
            'A provider acknowledgement alone cannot authorize appending after an unchanged suffix.',
      );
      expect(await bytes(), partial);
      expect(history.hasPending, isFalse);
      folder.ignoreCleanup = false;
      await history.appendAtomic([user(next, 'New explicit action')]);
      final committed = await bytes();
      expect(committed.take(baseline.length), baseline);
      expect(
        const LineSplitter().convert(utf8.decode(committed)),
        hasLength(2),
      );
      expect(history.snapshot.food, isEmpty);
      await reopen();
      expect(await bytes(), committed);
      expect(
        history.snapshot.tasks.where((e) => e.entity == next),
        hasLength(1),
      );
    },
  );

  test(
    'oversized actions stop building at the byte bound before any write',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      final before = await bytes(), writes = folder.writes;
      var built = 0;
      final description = String.fromCharCode(0x20ac) * 10000;
      await expectLater(
        history.appendAtomic([
          for (var i = 0; i < 600; i++)
            (seq, clock, head) {
              built++;
              return UnifiedEffect(
                'task',
                LogEvent(
                  history.manifest.space,
                  writer,
                  seq,
                  clock,
                  const Uuid().v4(),
                  'task.created',
                  {
                    'title': 'Bounded task',
                    'description': description,
                    'assignee': person,
                  },
                ).encode(previousHash: head),
              );
            },
        ]),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.toString(),
            'size',
            contains('safe record size'),
          ),
        ),
      );
      expect(built, lessThan(600));
      expect(folder.writes, writes);
      expect(await bytes(), before);
      expect(history.hasPending, isFalse);
    },
  );

  test(
    'mixed effects commit in one line and replay without private state',
    () async {
      tasks = await TaskStore.openUnified(history);
      food = await FoodStore.openUnified(history);
      await history.appendAtomic([user(person, 'Person'), beans()]);
      final original = await bytes();
      expect(original.where((b) => b == 10).length, 1);
      final action = UnifiedRecord.decode(utf8.decode(original).trim());
      expect(action.effects.length, 2);
      expect(action.effects.map((e) => e.sequence), [1, 2]);
      expect(action.sequence, 1);
      expect(tasks!.rows.single['name'], 'Person');
      expect(food!.state.active.single.id, container);
      expect(
        profile.database.select(
          "SELECT name FROM sqlite_schema WHERE type='table' AND name='protected_app_outbox'",
        ),
        isEmpty,
      );
      await reopen(fresh: true);
      expect(history.snapshot.tasks.single.id, '$writer:1');
      expect(history.snapshot.food.single.id, '$writer:2');
      await history.appendAtomic([user(const Uuid().v4(), 'Next')]);
      expect(history.snapshot.tasks.last.sequence, 3);
      expect(history.physicalSequence, 2);
      expect((await bytes()).take(original.length).toList(), original);
    },
  );

  test('bulk create delete and Undo each use one canonical action', () async {
    tasks = await TaskStore.openUnified(history);
    await history.appendAtomic([user(person, 'Person')]);
    final titles = {for (var i = 0; i < 100; i++) const Uuid().v4(): 'Task $i'};
    final before = history.physicalSequence;
    final created = await tasks!.createTasks(titles, person);
    expect(created.succeeded, isTrue);
    expect(created.committedIds, titles.keys);
    expect(history.physicalSequence, before + 1);
    expect(history.snapshot.records.last.effects, hasLength(100));
    final receipts = <OperationReceipt>[];
    final deleted = await tasks!.deleteTasks(
      titles.keys.toList(),
      expectedTaskSnapshot: tasks!.taskSnapshot,
      onPrepared: receipts.add,
    );
    expect(deleted.succeeded, isTrue);
    expect(
      tasks!.confirmedOperations(receipts),
      receipts.map((r) => r.id).toSet(),
    );
    expect(history.physicalSequence, before + 2);
    expect(
      (await tasks!.undoOperations(receipts.map((r) => r.id).toList())).error,
      isNull,
    );
    expect(history.physicalSequence, before + 3);
    expect(
      tasks!.rows.where((r) => r['kind'] == 'task' && r['deleted'] != true),
      hasLength(100),
    );
  });

  for (final fragment in ['json-prefix', 'complete-json-without-newline']) {
    test(
      'restart forgets intent and owner discards only $fragment before next save',
      () async {
        await history.appendAtomic([user(person, 'Person')]);
        final committed = await bytes();
        await history.prepareInProfileQueue([
          user(const Uuid().v4(), 'Abandoned'),
        ]);
        final prepared = history.pendingRecords.single;
        final encoded = utf8.encode('${prepared.encode()}\n');
        folder.cut = fragment == 'json-prefix' ? 71 : encoded.length - 1;
        await expectLater(history.commitInProfileQueue(), throwsStateError);
        final interrupted = await bytes();
        expect(history.snapshot.tasks.length, 1);
        expect(
          profile.database.select(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name='protected_app_outbox'",
          ),
          isEmpty,
        );
        await reopen();
        expect(history.hasPending, isFalse);
        expect(await bytes(), interrupted);
        final writes = folder.writes;
        await history.validateInProfileQueue([
          user(const Uuid().v4(), 'Preview only'),
        ]);
        expect(
          await bytes(),
          interrupted,
          reason: 'Preview never cleans or appends',
        );
        expect(folder.cleanups, 0);
        expect(folder.writes, writes);
        await history.recoverPrepared();
        expect(
          folder.writes,
          writes,
          reason: 'No automatic replay after restart',
        );
        await history.appendAtomic([user(const Uuid().v4(), 'Replacement')]);
        expect(folder.cleanups, 1);
        expect((await bytes()).take(committed.length).toList(), committed);
        expect(history.snapshot.tasks.map((e) => e.data['name']), [
          'Person',
          'Replacement',
        ]);
        expect(history.snapshot.tasks.last.sequence, 2);
      },
    );
  }

  test(
    'nonowner waits for an unterminated peer line without modifying or blocking independent saves',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      final peer = const Uuid().v4(),
          epoch = history.manifest.epoch,
          space = history.manifest.space;
      final genesis = unifiedGenesis(space, epoch, peer);
      final header = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: peer,
        sequence: 1,
        clock: EventClock(BigInt.zero),
        previousHash: genesis,
        effect: UnifiedEffect.joined(),
        observed: {peer: UnifiedFrontier(0, genesis)},
      );
      final peerBytes = utf8.encode('${header.encode()}\n{"v":5,"partial":');
      await folder.create(unifiedLogName(peer), Uint8List.fromList(peerBytes));
      await history.refresh();
      expect(history.snapshot.incomplete, isTrue);
      await history.appendAtomic([user(const Uuid().v4(), 'Independent')]);
      expect(folder.cleanups, 0);
      expect(await folder.read(unifiedLogName(peer)), peerBytes);
      expect(history.snapshot.tasks, hasLength(2));
    },
  );

  test(
    'complete invalid owned record remains corruption and is never truncated',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      final committed = await bytes();
      final corrupt = Uint8List.fromList([
        ...committed,
        ...utf8.encode('{"invalid":true}\n'),
      ]);
      await File(
        '${folder.location}/${unifiedLogName(writer)}',
      ).writeAsBytes(corrupt);
      await expectLater(history.refresh(), throwsA(isA<FormatFailure>()));
      await expectLater(
        history.appendAtomic([beans()]),
        throwsA(isA<FormatFailure>()),
      );
      expect(folder.cleanups, 0);
      expect(await bytes(), corrupt);
    },
  );

  test(
    'uncertain complete same-session write reconciles once from canonical bytes',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      folder.uncertain = true;
      await expectLater(history.appendAtomic([beans()]), throwsStateError);
      final committed = await bytes(), writes = folder.writes;
      await history.refresh();
      expect(history.hasPending, isFalse);
      expect(history.snapshot.food, hasLength(1));
      await history.recoverPrepared();
      expect(folder.writes, writes);
      expect(await bytes(), committed);
    },
  );

  test(
    'same-session partial reconciliation uses memory only and cannot expose an effect prefix',
    () async {
      await history.appendAtomic([user(person, 'Person')]);
      folder.cut = 71;
      await expectLater(
        history.appendAtomic([user(const Uuid().v4(), 'Second'), beans()]),
        throwsStateError,
      );
      expect(history.snapshot.tasks, hasLength(1));
      expect(history.snapshot.food, isEmpty);
      expect(history.hasPending, isTrue);
      expect(
        profile.database.select(
          "SELECT name FROM sqlite_schema WHERE type='table' AND name='protected_app_outbox'",
        ),
        isEmpty,
      );
      await history.recoverPrepared();
      expect(history.snapshot.tasks, hasLength(2));
      expect(history.snapshot.food, hasLength(1));
      expect(history.physicalSequence, 2);
    },
  );

  test(
    'maximum import provenance and all physical IDs commit together and cold retries do not write',
    () async {
      food = await FoodStore.openUnified(history);
      final plan = FoodImportPlan(
        space: history.manifest.space,
        importId: const Uuid().v4(),
        sourceSha256: List.filled(64, 'a').join(),
        containers: [
          for (var i = 1; i <= 1000; i++)
            FoodImportContainer(
              sourceId: 'row',
              ordinal: i,
              details: const FoodDetails(name: 'Synthetic'),
              contents: const Contents.fraction(1, 1),
              createdAt: '2026-10-21T00:00:00Z',
            ),
        ],
      );
      final first = await food!.commitImport(plan);
      expect(first.status, FoodImportStatus.committed);
      final committed = await bytes();
      expect(committed.where((b) => b == 10).length, 1);
      expect(
        history.snapshot.records.single.provenance!['planHash'],
        plan.planHash,
      );
      expect(
        profile.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
      await reopen(fresh: true);
      food = await FoodStore.openUnified(history);
      final writes = folder.writes;
      final repeated = await food!.commitImport(plan);
      expect(repeated.recordIds, first.recordIds);
      expect(
        food!.state.containers.map((c) => c.id).toSet(),
        plan.targetIds.toSet(),
      );
      expect(await bytes(), committed);
      expect(folder.writes, writes);
    },
  );
}
