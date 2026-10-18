import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'unified_conversion_test.dart' as fixture;

const owner = fixture.owner, space = fixture.space;
const newTask = '55555555-5555-4555-8555-555555555555';
const newFood = '66666666-6666-4666-8666-666666666666';

class FaultFolder extends LocalLogFolder {
  FaultFolder(super.location);
  int? cut;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final stop = cut;
    cut = null;
    if (stop == null) return super.append(name, bytes);
    await super.append(name, Uint8List.fromList(bytes.take(stop).toList()));
    throw const FileSystemException('Synthetic append interruption');
  }
}

class AppendOnlyFolder implements LogFolder, BoundedLogFolder {
  AppendOnlyFolder(this.inner);
  final FaultFolder inner;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (maximumBytes > 32 * 1024 * 1024) {
      throw ArgumentError('Native read ceiling exceeded');
    }
    return inner.readBounded(name, maximumBytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
}

UnifiedEffectBuilder taskBuilder(String id) =>
    (seq, clock, head) => UnifiedEffect(
      'task',
      LogEvent(space, owner, seq, clock, id, 'user.created', {
        'name': 'Synthetic user',
      }).encode(previousHash: head),
    );
UnifiedEffectBuilder foodBuilder() =>
    (seq, clock, head) => UnifiedEffect(
      'food',
      FoodRecord(
        unified: true,
        space: space,
        writer: owner,
        sequence: seq,
        clock: clock,
        previousHash: head,
        operation: FoodOperation(
          id: '$owner:$seq',
          order: clock.value.toInt(),
          action: FoodAction.add,
          targets: [newFood],
          details: const FoodDetails(name: 'Beans'),
          createdAt: '2026-10-17T00:00:00Z',
        ),
      ).encode(),
    );

void main() {
  late Directory root;
  late FaultFolder folder;
  late UnifiedConversion converted;
  LocalProfileDatabase? profile;
  UnifiedHistory? history;
  Future<void> open() async {
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    final settings = profile!.database.select(
      'SELECT 1 FROM protected_settings',
    );
    if (settings.isEmpty) {
      profile!.transaction(
        () => profile!.database.execute(
          'INSERT INTO protected_settings VALUES (1,?,?)',
          [
            owner,
            utf8.encode(jsonEncode({'writer': owner, 'appearance': 'system'})),
          ],
        ),
      );
    }
    history = await UnifiedHistory.open(
      folder,
      profile: profile!,
      writer: owner,
      now: () => DateTime.utc(2026, 10, 17),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'tandemlog-disposable-unified-',
    );
    final shared = await Directory('${root.path}/shared').create();
    folder = FaultFolder(shared.path);
    final p = fixture.plan();
    converted = p.convert(fixture.ack(p));
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(utf8.encode(converted.manifest.encode())),
    );
    for (final entry in converted.files.entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    await open();
  });
  tearDown(() async {
    await history?.close();
    history = null;
    await profile?.close();
    profile = null;
    await root.delete(recursive: true);
  });

  test(
    'poisoned profile still drains and releases unified workspace on shutdown',
    () async {
      final task = await TaskStore.openUnified(history!);
      final p = profile!;
      p.database.close();
      expect(
        () => p.rollbackAfterFailure(StateError('Synthetic lost SQL handle')),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      await task.close();
      await history!.close();
      history = null;
      await p.close();
      profile = null;
      final reopened = await LocalProfileDatabase.open('${root.path}/profile');
      await reopened.close();
    },
  );

  test(
    'one future allocator/chain commits Tasks and Food as one frame',
    () async {
      final before = history!.physicalSequence;
      final after = await history!.appendAtomic([
        taskBuilder(newTask),
        foodBuilder(),
      ]);
      final added = after.records.where((r) => r.sequence > before).toList();
      expect(added.map((r) => r.sequence), [before + 1, before + 2]);
      expect(added.first.transactionCount, 2);
      expect(added.last.previousHash, added.first.hash);
      expect(added.map((r) => r.effect.id), ['$owner:6', '$owner:7']);
      expect(after.tasks.any((e) => e.entity == newTask), isTrue);
      expect(after.food.any((op) => op.targets.contains(newFood)), isTrue);
      expect(history!.hasPending, isFalse);
      expect(
        profile!.database.select('SELECT * FROM protected_app_outbox'),
        isEmpty,
      );
      expect(
        profile!.database.select('SELECT * FROM protected_writer_guards'),
        isEmpty,
      );
      expect(
        profile!.database.select('SELECT * FROM protected_food_intents'),
        isEmpty,
      );
      expect(
        (await folder.list())
            .map((i) => i.name)
            .where((n) => n.endsWith('.foodlog')),
        isEmpty,
      );
    },
  );

  for (final cut in [0, 1, 1200, 1000000]) {
    test(
      'interrupted atomic frame $cut recovers exact bytes once across reopen',
      () async {
        final baseline = history!.snapshot;
        folder.cut = cut;
        await expectLater(
          history!.appendAtomic([taskBuilder(newTask), foodBuilder()]),
          throwsA(isA<FileSystemException>()),
        );
        final observed = await history!.refresh();
        final complete = cut >= 1000000;
        expect(observed.tasks.any((e) => e.entity == newTask), complete);
        expect(
          observed.food.any((op) => op.targets.contains(newFood)),
          complete,
        );
        if (!complete) {
          expect(history!.hasPending, isTrue);
          expect(observed.effects.length, baseline.effects.length);
          await expectLater(
            history!.renameDevice('blocked'),
            throwsA(isA<FormatFailure>()),
          );
        }
        final attempt = profile!.database.select(
          'SELECT raw FROM protected_app_outbox',
        );
        final expected = attempt.isEmpty
            ? null
            : Uint8List.fromList(attempt.single['raw'] as List<int>);
        await history!.close();
        history = null;
        await profile!.close();
        profile = null;
        await open();
        final result = await history!.recoverPrepared();
        expect(result.tasks.where((e) => e.entity == newTask), hasLength(1));
        expect(
          result.food.where((op) => op.targets.contains(newFood)),
          hasLength(1),
        );
        expect(history!.physicalSequence, 7);
        final bytes = await folder.read(unifiedLogName(owner));
        if (expected != null) {
          expect(bytes.sublist(baseline.physical[owner]!.length), expected);
        }
        await history!.recoverPrepared();
        expect(await folder.read(unifiedLogName(owner)), bytes);
      },
    );
  }

  test(
    'rename is synced metadata; immutable identities and original attribution remain',
    () async {
      final baseline = history!.snapshot.effects
          .where((e) => e.isData)
          .map((e) => e.raw)
          .toList();
      await history!.renameDevice('  Office laptop  ');
      expect(history!.snapshot.deviceName(owner), 'Office laptop');
      expect(
        history!.snapshot.deviceLabel(fixture.peer),
        startsWith('Unnamed device'),
      );
      await history!.renameDevice('Travel laptop');
      expect(history!.snapshot.deviceName(owner), 'Travel laptop');
      final records = history!.snapshot.records.where(
        (r) => r.effect.kind == 'writer.named',
      );
      expect(records.map((r) => r.effect.name), [
        'Office laptop',
        'Travel laptop',
      ]);
      expect(
        history!.snapshot.effects.where((e) => e.isData).map((e) => e.raw),
        baseline,
      );
      await history!.renameDevice(' ');
      expect(history!.snapshot.deviceName(owner), isNull);
      expect(
        history!.snapshot.deviceLabel(owner),
        contains(owner.substring(0, 8)),
      );
      await expectLater(
        history!.renameDevice('bad\nname'),
        throwsA(isA<FormatFailure>()),
      );
      expect(history!.hasPending, isFalse);
    },
  );

  test(
    'same-size rewrite, truncation and stale replacement preserve guards and block writes',
    () async {
      await history!.renameDevice('Name one');
      final original = await folder.read(unifiedLogName(owner));
      final file = folder.file(unifiedLogName(owner));
      final before = profile!.database
          .select('SELECT * FROM protected_app_heads')
          .map((r) => r.toString())
          .toList();
      for (final corrupt in [
        Uint8List.fromList(original.take(original.length - 1).toList()),
        Uint8List.fromList(
          utf8.encode(
            utf8.decode(original).replaceFirst('Name one', 'Name two'),
          ),
        ),
        Uint8List.fromList(converted.files[unifiedLogName(owner)]!),
      ]) {
        await file.writeAsBytes(corrupt, flush: true);
        await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
        await expectLater(
          history!.appendAtomic([taskBuilder(newTask)]),
          throwsA(isA<FormatFailure>()),
        );
        expect(
          profile!.database
              .select('SELECT * FROM protected_app_heads')
              .map((r) => r.toString())
              .toList(),
          before,
        );
        await file.writeAsBytes(original, flush: true);
        await history!.refresh();
      }
    },
  );

  test(
    'late legacy tail and unknown active writer block the entire workspace',
    () async {
      final old = fixture.sources().entries.first;
      await folder.file(old.key).writeAsBytes(old.value, flush: true);
      await history!.refresh(); // exact sealed transport repeat is harmless
      await folder.file(old.key).writeAsBytes([...old.value, 10], flush: true);
      await expectLater(
        history!.renameDevice('blocked'),
        throwsA(isA<FormatFailure>()),
      );
      await folder.file(old.key).writeAsBytes(old.value, flush: true);
      final unknown = '77777777-7777-4777-8777-777777777777';
      await folder.create(unifiedLogName(unknown), Uint8List(0));
      await expectLater(
        history!.appendAtomic([foodBuilder()]),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'normal self rebuild is byte-identical and snapshots cannot be mutated',
    () async {
      await history!.renameDevice('A device');
      final before = await folder.read(unifiedLogName(owner));
      final revision = history!.snapshot.revision;
      expect(
        () => history!.snapshot.physical[owner]![0] = 0,
        throwsUnsupportedError,
      );
      await history!.rebuildOwned();
      expect(await folder.read(unifiedLogName(owner)), before);
      expect(history!.snapshot.revision, revision);
    },
  );

  test(
    'new common writer can undo its own legacy Food contribution without rewriting attribution',
    () async {
      final old = fixture.foodHistory().first;
      await history!.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'food',
          FoodRecord(
            unified: true,
            space: space,
            writer: owner,
            sequence: seq,
            clock: clock,
            previousHash: head,
            createdWith: {fixture.container: old.id},
            operation: FoodOperation(
              id: '$owner:$seq',
              order: clock.value.toInt(),
              action: FoodAction.undo,
              targets: [fixture.container],
              retracts: old.id,
              undoOwner: owner,
            ),
          ).encode(),
        ),
      ]);
      final effect = history!.snapshot.effects.last;
      expect(effect.food!.writer, owner);
      expect(effect.food!.operation.retracts, old.id);
      final state = projectFood(
        history!.snapshot.food,
        legacyOwners: {
          foodWriter(owner): owner,
          foodWriter(fixture.peer): fixture.peer,
        },
      );
      expect(state.containers.where((c) => c.id == fixture.container), isEmpty);
      expect(
        history!.snapshot.effects.where((e) => e.food?.id == old.id).single.raw,
        old.encode(),
      );
    },
  );

  test(
    'invalid whole frame is rejected before any reservation or canonical append',
    () async {
      final before = await folder.read(unifiedLogName(owner));
      await expectLater(
        history!.appendAtomic([taskBuilder(newTask), taskBuilder(newTask)]),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read(unifiedLogName(owner)), before);
      expect(history!.hasPending, isFalse);
    },
  );

  test(
    'mixed frame waits for missing Task creation without a declared peer frontier',
    () async {
      const peer = fixture.peer;
      final m = history!.manifest;
      final birthClock = EventClock(BigInt.from(3000000000));
      final editClock = EventClock(BigInt.from(4000000000));
      final first = UnifiedRecord(
        space: space,
        epoch: m.epoch,
        writer: owner,
        sequence: 6,
        clock: editClock,
        previousHash: history!.commonHead,
        effect: UnifiedEffect(
          'task',
          LogEvent(space, owner, 6, editClock, newTask, 'task.edited', {
            'title': 'Edited incoming task',
          }).encode(previousHash: history!.commonHead),
        ),
        transactionStart: 6,
        transactionCount: 2,
        transactionIndex: 0,
        observed: {owner: UnifiedFrontier(5, history!.commonHead)},
      );
      final foodClock = EventClock(BigInt.from(4000000001));
      final second = UnifiedRecord(
        space: space,
        epoch: m.epoch,
        writer: owner,
        sequence: 7,
        clock: foodClock,
        previousHash: first.hash,
        effect: foodBuilder()(7, foodClock, first.hash),
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
      final waiting = await history!.refresh();
      expect(waiting.pendingEffects, isTrue);
      expect(waiting.food.any((e) => e.targets.contains(newFood)), isFalse);
      expect(waiting.tasks.any((e) => e.entity == newTask), isFalse);
      final genesis = unifiedGenesis(space, m.epoch, peer);
      final birth = UnifiedRecord(
        space: space,
        epoch: m.epoch,
        writer: peer,
        sequence: 1,
        clock: birthClock,
        previousHash: genesis,
        effect: UnifiedEffect(
          'task',
          LogEvent(space, peer, 1, birthClock, newTask, 'task.created', {
            'title': 'Incoming task',
            'description': '',
            'assignee': fixture.peer,
          }).encode(previousHash: genesis),
        ),
        transactionStart: 1,
        transactionCount: 1,
        transactionIndex: 0,
        observed: {peer: UnifiedFrontier(0, genesis)},
      );
      await folder.append(
        unifiedLogName(peer),
        Uint8List.fromList(utf8.encode('${birth.encode()}\n')),
      );
      final ready = await history!.refresh();
      expect(ready.pendingEffects, isFalse);
      expect(ready.food.any((e) => e.targets.contains(newFood)), isTrue);
      expect(
        ready.tasks.any((e) => e.entity == newTask && e.type == 'task.edited'),
        isTrue,
      );
    },
  );

  test(
    'local missing Task dependency never reserves a partial domain command',
    () async {
      final before = await folder.read(unifiedLogName(owner));
      await expectLater(
        history!.appendAtomic([
          (seq, clock, head) => UnifiedEffect(
            'task',
            LogEvent(space, owner, seq, clock, newTask, 'task.edited', {
              'title': 'Missing creation',
            }).encode(previousHash: head),
          ),
          foodBuilder(),
        ]),
        throwsA(isA<FormatFailure>()),
      );
      expect(history!.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), before);
    },
  );

  for (final observeMissingPeer in [false, true]) {
    test(
      'mixed frame and later writer commands wait together for peer dependency, observed=$observeMissingPeer',
      () async {
        const peer = fixture.peer;
        final m = history!.manifest, foodAuthor = foodWriter(owner);
        final peerClock = EventClock(BigInt.from(1000000000000000000));
        final taskClock = EventClock(BigInt.from(2000000000000000000));
        final ownClock = EventClock(taskClock.value + BigInt.one);
        final peerHead = unifiedGenesis(space, m.epoch, peer);
        final prerequisite = FoodRecord(
          unified: true,
          space: space,
          writer: peer,
          sequence: 1,
          clock: peerClock,
          previousHash: peerHead,
          createdWith: {fixture.container: '$foodAuthor:1'},
          operation: FoodOperation(
            id: '$peer:1',
            order: peerClock.value.toInt(),
            action: FoodAction.edit,
            targets: [fixture.container],
            contents: const Contents.fraction(1, 2),
          ),
        );
        final peerRecord = UnifiedRecord(
          space: space,
          epoch: m.epoch,
          writer: peer,
          sequence: 1,
          clock: peerClock,
          previousHash: peerHead,
          effect: UnifiedEffect('food', prerequisite.encode()),
          transactionStart: 1,
          transactionCount: 1,
          transactionIndex: 0,
          observed: {peer: UnifiedFrontier(0, peerHead)},
        );
        final observed = {
          owner: UnifiedFrontier(5, history!.commonHead),
          if (observeMissingPeer) peer: UnifiedFrontier(1, peerRecord.hash),
        };
        final first = UnifiedRecord(
          space: space,
          epoch: m.epoch,
          writer: owner,
          sequence: 6,
          clock: taskClock,
          previousHash: history!.commonHead,
          effect: taskBuilder(newTask)(6, taskClock, history!.commonHead),
          transactionStart: 6,
          transactionCount: 2,
          transactionIndex: 0,
          observed: observed,
        );
        final pending = FoodRecord(
          unified: true,
          space: space,
          writer: owner,
          sequence: 7,
          clock: ownClock,
          previousHash: first.hash,
          createdWith: {fixture.container: '$foodAuthor:1'},
          operation: FoodOperation(
            id: '$owner:7',
            order: ownClock.value.toInt(),
            action: FoodAction.edit,
            targets: [fixture.container],
            contents: const Contents.fraction(1, 4),
            observedEdits: ['$peer:1'],
          ),
        );
        final second = UnifiedRecord(
          space: space,
          epoch: m.epoch,
          writer: owner,
          sequence: 7,
          clock: ownClock,
          previousHash: first.hash,
          effect: UnifiedEffect('food', pending.encode()),
          transactionStart: 6,
          transactionCount: 2,
          transactionIndex: 1,
          observed: observed,
        );
        final later = UnifiedRecord(
          space: space,
          epoch: m.epoch,
          writer: owner,
          sequence: 8,
          clock: EventClock(ownClock.value + BigInt.one),
          previousHash: second.hash,
          effect: UnifiedEffect.named('Must wait with earlier frame'),
          transactionStart: 8,
          transactionCount: 1,
          transactionIndex: 0,
          observed: {owner: UnifiedFrontier(7, second.hash)},
        );
        final suffix = utf8.encode(
          '${[first, second, later].map((r) => r.encode()).join('\n')}\n',
        );
        await folder.append(unifiedLogName(owner), Uint8List.fromList(suffix));
        final waiting = await history!.refresh();
        expect(waiting.pendingEffects, isTrue);
        expect(waiting.tasks.any((e) => e.entity == newTask), isFalse);
        expect(waiting.food.any((e) => e.id == pending.id), isFalse);
        expect(waiting.deviceName(owner), isNull);
        expect(waiting.published[owner], 5);
        expect(history!.physicalSequence, 8);
        await expectLater(
          history!.renameDevice('blocked'),
          throwsA(isA<FormatFailure>()),
        );
        await history!.close();
        history = null;
        await profile!.close();
        profile = null;
        await open();
        expect(history!.snapshot.pendingEffects, isTrue);
        expect(
          history!.snapshot.tasks.any((e) => e.entity == newTask),
          isFalse,
        );
        await folder.append(
          unifiedLogName(peer),
          Uint8List.fromList(utf8.encode('${peerRecord.encode()}\n')),
        );
        final ready = await history!.refresh();
        expect(ready.pendingEffects, isFalse);
        expect(ready.tasks.any((e) => e.entity == newTask), isTrue);
        expect(ready.food.any((e) => e.id == pending.id), isTrue);
        expect(ready.deviceName(owner), 'Must wait with earlier frame');
        expect(ready.published[owner], 8);
        expect(
          ready.foodAdmission.state.containers.single.contents.toJson(),
          const Contents.fraction(1, 4).toJson(),
        );
        expect(
          (await folder.read(
            unifiedLogName(owner),
          )).sublist(converted.files[unifiedLogName(owner)]!.length),
          suffix,
        );
      },
    );
  }

  test(
    'wrong-entity Task Undo fails before reservation using existing semantic validators',
    () async {
      final original = history!.snapshot.tasks.firstWhere(
        (e) => e.type == 'task.created',
      );
      await history!.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'task',
          LogEvent(space, owner, seq, clock, original.entity, 'task.edited', {
            'title': 'Edited',
          }).encode(previousHash: head),
        ),
      ]);
      final edit = history!.snapshot.tasks.last;
      final before = await folder.read(unifiedLogName(owner));
      await expectLater(
        history!.appendAtomic([
          (seq, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              space,
              owner,
              seq,
              clock,
              newTask,
              'task.operationUndone',
              {'operation': edit.id},
            ).encode(previousHash: head),
          ),
        ]),
        throwsA(isA<FormatFailure>()),
      );
      expect(history!.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), before);
    },
  );

  test(
    'protected installation identity prevents naming or writing as another writer',
    () async {
      await expectLater(
        UnifiedHistory.open(folder, profile: profile!, writer: fixture.peer),
        throwsA(anyOf(isA<FormatFailure>(), isA<StateError>())),
      );
    },
  );
  test(
    'cross-writer fixed point holds reverse-scanned frames across reopen',
    () async {
      const b = '66666666-6666-4666-8666-666666666666',
          c = '77777777-7777-4777-8777-777777777777',
          d = '88888888-8888-4888-8888-888888888888';
      final f = LocalLogFolder(
        (await Directory('${root.path}/transitive').create()).path,
      );
      final owners = {owner, fixture.peer, b, c, d};
      final plan = UnifiedCutoverPlan.inspect(
        space: space,
        owners: owners,
        participants: owners,
        sources: fixture.sources(),
        hasUnresolvedPreparedWrites: false,
      );
      final cv = plan.convert(
        owners.map(
          (w) => CutoverAcknowledgement(
            w,
            plan.sourceDigest,
            quiesced: true,
            pendingResolved: true,
          ),
        ),
      );
      await f.create(
        'tandemlog-space.json',
        Uint8List.fromList(utf8.encode(cv.manifest.encode())),
      );
      for (final e in cv.files.entries) {
        await f.create(e.key, Uint8List.fromList(e.value));
      }
      final db = await LocalProfileDatabase.open(
        '${root.path}/transitive-profile',
      );
      db.transaction(
        () => db.database.execute(
          'INSERT INTO protected_settings VALUES (1,?,?)',
          [
            owner,
            utf8.encode(jsonEncode({'writer': owner, 'appearance': 'system'})),
          ],
        ),
      );
      UnifiedHistory? app;
      try {
        app = await UnifiedHistory.open(f, profile: db, writer: owner);
        final epoch = app.manifest.epoch;
        UnifiedRecord record(
          String writer,
          int seq,
          int start,
          int count,
          int index,
          int time,
          String head,
          Map<String, UnifiedFrontier> observed,
          UnifiedEffect effect,
        ) => UnifiedRecord(
          space: space,
          epoch: epoch,
          writer: writer,
          sequence: seq,
          clock: EventClock(BigInt.from(time)),
          previousHash: head,
          effect: effect,
          transactionStart: start,
          transactionCount: count,
          transactionIndex: index,
          observed: observed,
        );
        UnifiedEffect editFood(
          String writer,
          int seq,
          int time,
          String head,
          List<String> refs,
        ) => UnifiedEffect(
          'food',
          FoodRecord(
            unified: true,
            space: space,
            writer: writer,
            sequence: seq,
            clock: EventClock(BigInt.from(time)),
            previousHash: head,
            createdWith: {fixture.container: fixture.foodHistory().first.id},
            operation: FoodOperation(
              id: '$writer:$seq',
              order: time,
              action: FoodAction.edit,
              targets: [fixture.container],
              contents: const Contents.fraction(1, 2),
              observedEdits: refs,
            ),
          ).encode(),
        );
        final dg = unifiedGenesis(space, epoch, d);
        final prerequisite = record(d, 1, 1, 1, 0, 3000000000, dg, {
          d: UnifiedFrontier(0, dg),
        }, editFood(d, 1, 3000000000, dg, []));
        List<UnifiedRecord> frame(
          String writer,
          int start,
          int time,
          String head,
          String dependency,
          int depSeq,
          String depHash, {
          bool missingFood = false,
        }) {
          final observed = {
            writer: UnifiedFrontier(start - 1, head),
            dependency: UnifiedFrontier(depSeq, depHash),
          };
          final first = record(
            writer,
            start,
            start,
            2,
            0,
            time,
            head,
            observed,
            UnifiedEffect(
              'task',
              LogEvent(
                space,
                writer,
                start,
                EventClock(BigInt.from(time)),
                writer,
                'user.created',
                {'name': 'Synthetic $writer'},
              ).encode(previousHash: head),
            ),
          );
          final second = record(
            writer,
            start + 1,
            start,
            2,
            1,
            time + 1,
            first.hash,
            observed,
            missingFood
                ? editFood(writer, start + 1, time + 1, first.hash, ['$d:1'])
                : UnifiedEffect(
                    'food',
                    FoodRecord(
                      unified: true,
                      space: space,
                      writer: writer,
                      sequence: start + 1,
                      clock: EventClock(BigInt.from(time + 1)),
                      previousHash: first.hash,
                      operation: FoodOperation(
                        id: '$writer:${start + 1}',
                        order: time + 1,
                        action: FoodAction.add,
                        targets: [writer],
                        details: const FoodDetails(name: 'Atomic'),
                        createdAt: '2026-10-18T00:00:00Z',
                      ),
                    ).encode(),
                  ),
          );
          final last = record(
            writer,
            start + 2,
            start + 2,
            1,
            0,
            time + 2,
            second.hash,
            {writer: UnifiedFrontier(start + 1, second.hash)},
            UnifiedEffect.named('Same label'),
          );
          return [first, second, last];
        }

        final cf = frame(
          c,
          1,
          4000000000,
          unifiedGenesis(space, epoch, c),
          d,
          1,
          prerequisite.hash,
          missingFood: true,
        );
        final bf = frame(
          b,
          1,
          5000000000,
          unifiedGenesis(space, epoch, b),
          c,
          2,
          cf[1].hash,
        );
        final af = frame(
          owner,
          6,
          6000000000,
          app.commonHead,
          b,
          2,
          bf[1].hash,
        );
        for (final records in [af, bf, cf]) {
          await f.append(
            unifiedLogName(records.first.writer),
            Uint8List.fromList(
              utf8.encode(records.map((r) => '${r.encode()}\n').join()),
            ),
          );
        }
        final waiting = await app.refresh();
        expect(waiting.pendingEffects, isTrue);
        for (final author in [owner, b, c]) {
          expect(waiting.deviceName(author), isNull);
          expect(waiting.effects.any((e) => e.task?.entity == author), isFalse);
        }
        expect(waiting.published[owner], 5);
        expect(waiting.published[b], 0);
        expect(waiting.published[c], 0);
        final bytes = {
          for (final author in [owner, b, c])
            author: await f.read(unifiedLogName(author)),
        };
        await app.close();
        app = null;
        app = await UnifiedHistory.open(f, profile: db, writer: owner);
        expect(app.snapshot.pendingEffects, isTrue);
        for (final author in bytes.keys) {
          expect(app.snapshot.physical[author], bytes[author]);
        }
        final wrong = record(d, 1, 1, 1, 0, 3000000000, dg, {
          d: UnifiedFrontier(0, dg),
        }, UnifiedEffect.named('Wrong promised event'));
        await f.append(
          unifiedLogName(d),
          Uint8List.fromList(utf8.encode('${wrong.encode()}\n')),
        );
        final before = db.database
            .select('SELECT * FROM protected_app_heads')
            .map((r) => r.toString())
            .toList();
        await expectLater(app.refresh(), throwsA(isA<FormatFailure>()));
        expect(
          db.database
              .select('SELECT * FROM protected_app_heads')
              .map((r) => r.toString())
              .toList(),
          before,
        );
        await f
            .file(unifiedLogName(d))
            .writeAsString('${prerequisite.encode()}\n', flush: true);
        final ready = await app.refresh();
        expect(ready.pendingEffects, isFalse);
        for (final author in [owner, b, c]) {
          expect(ready.deviceName(author), 'Same label');
          expect(ready.effects.any((e) => e.task?.entity == author), isTrue);
          expect(ready.physical[author], bytes[author]);
        }
      } finally {
        await app?.close();
        await db.close();
      }
    },
  );
  test(
    'removing a derived recurring tag depends on its real completion',
    () async {
      final original = history!.snapshot.tasks.firstWhere(
        (e) => e.type == 'task.created',
      );
      final successor = const Uuid().v5(original.entity, 'successor');
      await history!.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'task',
          LogEvent(
            space,
            owner,
            seq,
            clock,
            original.entity,
            'task.completed',
            {
              'completedAt': '2026-10-18T00:00:00Z',
              'successor': {
                'id': successor,
                'title': 'Next',
                'description': '',
                'assignee': fixture.peer,
                'tags': ['inherited'],
              },
            },
          ).encode(previousHash: head),
        ),
      ]);
      final token = '${const Uuid().v5(successor, 'tag:inherited')}:1:0';
      final result = await history!.appendAtomic([
        (seq, clock, head) => UnifiedEffect(
          'task',
          LogEvent(space, owner, seq, clock, successor, 'task.edited', {
            'tagChanges': {
              'add': <String>[],
              'remove': [token],
            },
          }).encode(previousHash: head),
        ),
        foodBuilder(),
      ]);
      expect(result.pendingEffects, isFalse);
      final rows = TaskStore.validateSemanticHistory(
        result.tasks,
        space: space,
        writer: owner,
      );
      expect(rows.singleWhere((r) => r['id'] == successor)['tags'], isEmpty);
      expect(result.food.any((op) => op.targets.contains(newFood)), isTrue);
      expect(history!.hasPending, isFalse);
    },
  );
  test(
    'append-only provider resumes only exact missing bytes after repeated partial writes',
    () async {
      await history!.close();
      history = null;
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
      );
      final before = await folder.read(unifiedLogName(owner));
      folder.cut = 60;
      await expectLater(
        history!.appendAtomic([taskBuilder(newTask), foodBuilder()]),
        throwsA(isA<FileSystemException>()),
      );
      final exact =
          profile!.database
                  .select('SELECT raw FROM protected_app_outbox')
                  .single['raw']
              as List<int>;
      folder.cut = 7;
      await expectLater(
        history!.recoverPrepared(),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await folder.read(unifiedLogName(owner))).sublist(before.length),
        exact.take(67).toList(),
      );
      await history!.close();
      history = null;
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
      );
      await history!.recoverPrepared();
      expect(await folder.read(unifiedLogName(owner)), [...before, ...exact]);
      expect(history!.hasPending, isFalse);
      expect(history!.snapshot.tasks.any((e) => e.entity == newTask), isTrue);
      expect(
        history!.snapshot.food.any((e) => e.targets.contains(newFood)),
        isTrue,
      );
    },
  );

  test(
    'a corrupted reserved clock cannot append below the trusted common head',
    () async {
      await profile!.serialize(() async {
        await history!.prepareInProfileQueue([
          (seq, clock, head) => UnifiedEffect.named('Reserved'),
        ]);
      });
      final p = profile!.database
          .select('SELECT * FROM protected_app_outbox')
          .single;
      final original = Uint8List.fromList(p['raw'] as List<int>);
      final decoded = UnifiedRecord.decode(utf8.decode(original).trim());
      final corrupt = UnifiedRecord(
        space: space,
        epoch: decoded.epoch,
        writer: owner,
        sequence: decoded.sequence,
        clock: EventClock(BigInt.zero),
        previousHash: decoded.previousHash,
        effect: decoded.effect,
        transactionStart: decoded.transactionStart,
        transactionCount: 1,
        transactionIndex: 0,
        observed: decoded.observed,
      );
      final before = await folder.read(unifiedLogName(owner));
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_outbox SET raw=?',
          [utf8.encode('${corrupt.encode()}\n')],
        ),
      );
      await expectLater(
        history!.recoverPrepared(),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read(unifiedLogName(owner)), before);
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_outbox SET raw=?',
          [original],
        ),
      );
      await history!.recoverPrepared();
      expect(history!.snapshot.deviceName(owner), 'Reserved');
    },
  );
}
