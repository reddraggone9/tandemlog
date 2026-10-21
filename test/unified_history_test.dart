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

UnifiedRecord actionRecord(
  String writer,
  int sequence,
  int time,
  String head,
  List<UnifiedEffectBuilder> builders, {
  Map<String, UnifiedFrontier>? observed,
  int? logicalStart,
}) {
  final effects = <UnifiedEffect>[];
  var predecessor = head;
  for (var i = 0; i < builders.length; i++) {
    final effect = builders[i](
      (logicalStart ?? sequence) + i,
      EventClock(BigInt.from(time + i)),
      predecessor,
    );
    effects.add(effect);
    if (effect.isData) predecessor = effect.integrityHash;
  }
  return UnifiedRecord(
    space: space,
    epoch: _actionEpoch,
    writer: writer,
    sequence: sequence,
    clock: EventClock(BigInt.from(time + builders.length - 1)),
    previousHash: head,
    effects: effects,
    observed: observed ?? {writer: UnifiedFrontier(sequence - 1, head)},
  );
}

late String _actionEpoch;

void main() {
  late Directory root;
  late FaultFolder folder;
  late fixture.FixtureConversion converted;
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
    _actionEpoch = history!.manifest.epoch;
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
    'one allocator commits mixed typed effects in one action without coupling effect IDs to line count',
    () async {
      final before = history!.physicalSequence,
          logicalBefore = history!.logicalSequence,
          head = history!.commonHead;
      final after = await history!.appendAtomic([
        taskBuilder(newTask),
        foodBuilder(),
      ]);
      final added = after.records
          .where((r) => r.writer == owner && r.sequence > before)
          .single;
      expect(added.sequence, before + 1);
      expect(added.previousHash, head);
      expect(added.effects.map((e) => e.id), [
        '$owner:${logicalBefore + 1}',
        '$owner:${logicalBefore + 2}',
      ]);
      expect(
        added.effects.last.previousHash,
        added.effects.first.integrityHash,
      );
      expect(after.tasks.any((e) => e.entity == newTask), isTrue);
      expect(after.food.any((op) => op.targets.contains(newFood)), isTrue);
      expect(history!.hasPending, isFalse);
      expect(
        profile!.database.select(
          "SELECT name FROM sqlite_schema WHERE type='table' AND name IN ('protected_app_outbox','protected_writer_guards','protected_food_intents')",
        ),
        isEmpty,
      );
    },
  );
  for (final cut in [0, 1, 1200, 1000000]) {
    test(
      'converted prefix survives interrupted action cut=$cut; restart has no implicit retry',
      () async {
        final baseline = history!.snapshot;
        folder.cut = cut;
        await expectLater(
          history!.appendAtomic([taskBuilder(newTask), foodBuilder()]),
          throwsA(isA<FileSystemException>()),
        );
        final interrupted = await folder.read(unifiedLogName(owner));
        final complete =
            interrupted.last == 10 &&
            interrupted.length > baseline.physical[owner]!.length;
        await history!.refresh();
        expect(
          history!.snapshot.tasks.any((e) => e.entity == newTask),
          complete,
        );
        expect(
          history!.snapshot.food.any((e) => e.targets.contains(newFood)),
          complete,
        );
        await history!.close();
        history = null;
        await profile!.close();
        profile = null;
        await open();
        expect(history!.hasPending, isFalse);
        await history!.recoverPrepared();
        await history!.recoverPrepared();
        expect(await folder.read(unifiedLogName(owner)), interrupted);
        if (!complete) {
          await history!.appendAtomic([taskBuilder(newTask), foodBuilder()]);
        }
        final result = history!.snapshot;
        expect(result.tasks.where((e) => e.entity == newTask), hasLength(1));
        expect(
          result.food.where((e) => e.targets.contains(newFood)),
          hasLength(1),
        );
        expect(history!.physicalSequence, 6);
        expect(
          (await folder.read(
            unifiedLogName(owner),
          )).take(baseline.physical[owner]!.length).toList(),
          baseline.physical[owner],
        );
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
        (r) => r.effects.length == 1 && r.effect.kind == 'writer.named',
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
    'legacy files and unjoined complete current writers block the entire workspace',
    () async {
      final legacy = folder.file('$owner.jsonl');
      final evidence = utf8.encode('{"v":3}\n');
      await legacy.writeAsBytes(evidence);
      await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
      await expectLater(
        history!.renameDevice('blocked'),
        throwsA(isA<FormatFailure>()),
      );
      expect(await legacy.readAsBytes(), evidence);
      await legacy.delete();
      await history!.refresh();
      const unknown = '77777777-7777-4777-8777-777777777777';
      final genesis = unifiedGenesis(space, history!.manifest.epoch, unknown);
      final unjoined = actionRecord(unknown, 1, 3000000000, genesis, [
        (seq, clock, head) => UnifiedEffect.named('No installation header'),
      ]);
      await folder.create(
        unifiedLogName(unknown),
        Uint8List.fromList(utf8.encode('${unjoined.encode()}\n')),
      );
      await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
      expect(
        await folder.read(unifiedLogName(unknown)),
        utf8.encode('${unjoined.encode()}\n'),
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
    'mapped device can undo historical Food while retaining normalized evidence',
    () async {
      final old = fixture.foodHistory().first;
      final normalized = history!.snapshot.effects
          .where((e) => e.food?.id == old.id)
          .single;
      expect(normalized.food!.author, owner);
      expect(normalized.food!.hash, old.hash);
      final originalNormalizedRaw = normalized.raw;
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
        originalNormalizedRaw,
      );
    },
  );

  test(
    'invalid whole action is rejected before any reservation or canonical append',
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
    'mixed action waits for Task creation even without a declared peer frontier',
    () async {
      final head = history!.commonHead;
      final mixed = actionRecord(owner, 6, 4000000000, head, [
        (seq, clock, previous) => UnifiedEffect(
          'task',
          LogEvent(space, owner, seq, clock, newTask, 'task.edited', {
            'title': 'Edited incoming task',
          }).encode(previousHash: previous),
        ),
        foodBuilder(),
      ]);
      await folder.append(
        unifiedLogName(owner),
        Uint8List.fromList(utf8.encode('${mixed.encode()}\n')),
      );
      final waiting = await history!.refresh();
      expect(waiting.pendingEffects, isTrue);
      expect(waiting.food.any((e) => e.targets.contains(newFood)), isFalse);
      expect(waiting.tasks.any((e) => e.entity == newTask), isFalse);
      final genesis = unifiedGenesis(space, _actionEpoch, fixture.peer);
      final birth = actionRecord(fixture.peer, 1, 3000000000, genesis, [
        (seq, clock, previous) => UnifiedEffect(
          'task',
          LogEvent(space, fixture.peer, seq, clock, newTask, 'task.created', {
            'title': 'Incoming task',
            'description': '',
            'assignee': fixture.peer,
          }).encode(previousHash: previous),
        ),
      ]);
      await folder.append(
        unifiedLogName(fixture.peer),
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
      'mixed action and later metadata wait for peer dependency observed=$observeMissingPeer',
      () async {
        final peerHead = unifiedGenesis(space, _actionEpoch, fixture.peer);
        final foodAuthor = foodWriter(owner);
        final prerequisite = actionRecord(
          fixture.peer,
          1,
          1000000000000000000,
          peerHead,
          [
            (seq, clock, head) => UnifiedEffect(
              'food',
              FoodRecord(
                space: space,
                writer: fixture.peer,
                sequence: seq,
                clock: clock,
                previousHash: head,
                createdWith: {fixture.container: '$foodAuthor:1'},
                operation: FoodOperation(
                  id: '${fixture.peer}:$seq',
                  order: clock.value.toInt(),
                  action: FoodAction.edit,
                  targets: [fixture.container],
                  contents: const Contents.fraction(1, 2),
                ),
              ).encode(),
            ),
          ],
        );
        final observed = {
          owner: UnifiedFrontier(5, history!.commonHead),
          if (observeMissingPeer)
            fixture.peer: UnifiedFrontier(1, prerequisite.hash),
        };
        final mixed = actionRecord(
          owner,
          6,
          2000000000000000000,
          history!.commonHead,
          [
            taskBuilder(newTask),
            (seq, clock, head) => UnifiedEffect(
              'food',
              FoodRecord(
                space: space,
                writer: owner,
                sequence: seq,
                clock: clock,
                previousHash: head,
                createdWith: {fixture.container: '$foodAuthor:1'},
                operation: FoodOperation(
                  id: '$owner:$seq',
                  order: clock.value.toInt(),
                  action: FoodAction.edit,
                  targets: [fixture.container],
                  contents: const Contents.fraction(1, 4),
                  observedEdits: ['${fixture.peer}:1'],
                ),
              ).encode(),
            ),
          ],
          observed: observed,
        );
        final pending = mixed.effects.last.food!;
        final later = actionRecord(owner, 7, 2000000000000000002, mixed.hash, [
          (seq, clock, head) =>
              UnifiedEffect.named('Must wait with earlier action'),
        ]);
        final suffix = utf8.encode('${mixed.encode()}\n${later.encode()}\n');
        await folder.append(unifiedLogName(owner), Uint8List.fromList(suffix));
        final waiting = await history!.refresh();
        expect(waiting.pendingEffects, isTrue);
        expect(waiting.tasks.any((e) => e.entity == newTask), isFalse);
        expect(waiting.food.any((e) => e.id == pending.id), isFalse);
        expect(waiting.deviceName(owner), isNull);
        expect(waiting.published[owner], 5);
        expect(history!.physicalSequence, 7);
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
        await folder.append(
          unifiedLogName(fixture.peer),
          Uint8List.fromList(utf8.encode('${prerequisite.encode()}\n')),
        );
        final ready = await history!.refresh();
        expect(ready.pendingEffects, isFalse);
        expect(ready.tasks.any((e) => e.entity == newTask), isTrue);
        expect(ready.food.any((e) => e.id == pending.id), isTrue);
        expect(ready.deviceName(owner), 'Must wait with earlier action');
        expect(ready.published[owner], 7);
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
    'cross-writer fixed point holds reverse-scanned actions across reopen',
    () async {
      const b = '66666666-6666-4666-8666-666666666666',
          c = '77777777-7777-4777-8777-777777777777',
          d = '88888888-8888-4888-8888-888888888888';
      final f = LocalLogFolder(
        (await Directory('${root.path}/transitive').create()).path,
      );
      final owners = {owner, fixture.peer, b, c, d};
      final plan = fixture.FixturePlan.inspect(
        space: space,
        owners: owners,
        participants: owners,
        sources: fixture.sources(),
        hasUnresolvedPreparedWrites: false,
      );
      final cv = plan.prepareConversion();
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
        _actionEpoch = app.manifest.epoch;
        UnifiedEffectBuilder editFood(String author, List<String> refs) =>
            (seq, clock, head) => UnifiedEffect(
              'food',
              FoodRecord(
                space: space,
                writer: author,
                sequence: seq,
                clock: clock,
                previousHash: head,
                createdWith: {
                  fixture.container: fixture.foodHistory().first.id,
                },
                operation: FoodOperation(
                  id: '$author:$seq',
                  order: clock.value.toInt(),
                  action: FoodAction.edit,
                  targets: [fixture.container],
                  contents: const Contents.fraction(1, 2),
                  observedEdits: refs,
                ),
              ).encode(),
            );
        final dg = unifiedGenesis(space, _actionEpoch, d);
        final prerequisite = actionRecord(d, 1, 3000000000, dg, [
          editFood(d, []),
        ]);
        List<UnifiedRecord> chain(
          String author,
          int start,
          int time,
          String head,
          String dependency,
          UnifiedRecord requiredAction, {
          bool missingFood = false,
        }) {
          final mixed = actionRecord(
            author,
            start,
            time,
            head,
            [
              (seq, clock, previous) => UnifiedEffect(
                'task',
                LogEvent(space, author, seq, clock, author, 'user.created', {
                  'name': 'Synthetic $author',
                }).encode(previousHash: previous),
              ),
              if (missingFood)
                editFood(author, ['$dependency:1'])
              else
                (seq, clock, previous) => UnifiedEffect(
                  'food',
                  FoodRecord(
                    space: space,
                    writer: author,
                    sequence: seq,
                    clock: clock,
                    previousHash: previous,
                    operation: FoodOperation(
                      id: '$author:$seq',
                      order: clock.value.toInt(),
                      action: FoodAction.add,
                      targets: [author],
                      details: const FoodDetails(name: 'Atomic'),
                      createdAt: '2026-10-18T00:00:00Z',
                    ),
                  ).encode(),
                ),
            ],
            observed: {
              author: UnifiedFrontier(start - 1, head),
              dependency: UnifiedFrontier(
                requiredAction.sequence,
                requiredAction.hash,
              ),
            },
          );
          final later = actionRecord(author, start + 1, time + 2, mixed.hash, [
            (seq, clock, previous) => UnifiedEffect.named('Same label'),
          ]);
          return [mixed, later];
        }

        final cf = chain(
          c,
          1,
          4000000000,
          unifiedGenesis(space, _actionEpoch, c),
          d,
          prerequisite,
          missingFood: true,
        );
        final bf = chain(
          b,
          1,
          5000000000,
          unifiedGenesis(space, _actionEpoch, b),
          c,
          cf.first,
        );
        final af = chain(owner, 6, 6000000000, app.commonHead, b, bf.first);
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
        app = await UnifiedHistory.open(f, profile: db, writer: owner);
        expect(app.snapshot.pendingEffects, isTrue);
        final wrong = actionRecord(d, 1, 3000000000, dg, [
          (seq, clock, head) => UnifiedEffect.named('Wrong promised event'),
        ]);
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
    'same-session append-only reconciliation completes only exact bytes after repeated partial writes',
    () async {
      await history!.close();
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
      final exact = utf8.encode('${history!.pendingRecords.single.encode()}\n');
      folder.cut = 7;
      await expectLater(
        history!.recoverPrepared(),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        (await folder.read(unifiedLogName(owner))).sublist(before.length),
        exact.take(67).toList(),
      );
      await history!.recoverPrepared();
      expect(await folder.read(unifiedLogName(owner)), [...before, ...exact]);
      expect(history!.hasPending, isFalse);
      expect(history!.snapshot.tasks.any((e) => e.entity == newTask), isTrue);
      expect(
        history!.snapshot.food.any((e) => e.targets.contains(newFood)),
        isTrue,
      );
      await history!.close();
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
      );
      final confirmed = await folder.read(unifiedLogName(owner));
      await history!.recoverPrepared();
      expect(await folder.read(unifiedLogName(owner)), confirmed);
    },
  );
  test(
    'append-only provider cannot invent restart recovery or rewrite a committed prefix',
    () async {
      await history!.close();
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
      );
      folder.cut = 60;
      await expectLater(
        history!.appendAtomic([taskBuilder(newTask), foodBuilder()]),
        throwsA(isA<FileSystemException>()),
      );
      final partial = await folder.read(unifiedLogName(owner));
      await history!.close();
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
      );
      expect(history!.hasPending, isFalse);
      await history!.recoverPrepared();
      expect(await folder.read(unifiedLogName(owner)), partial);
      await expectLater(
        history!.appendAtomic([taskBuilder(newTask), foodBuilder()]),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.toString(),
            'provider',
            contains('cannot discard'),
          ),
        ),
      );
      expect(await folder.read(unifiedLogName(owner)), partial);
      expect(history!.snapshot.tasks.any((e) => e.entity == newTask), isFalse);
    },
  );
  test(
    'a complete decreasing-clock action cannot be admitted below the trusted common head',
    () async {
      final before = await folder.read(unifiedLogName(owner));
      final heads = profile!.database
          .select('SELECT * FROM protected_app_heads')
          .map((r) => r.toString())
          .toList();
      final corrupt = actionRecord(
        owner,
        history!.physicalSequence + 1,
        0,
        history!.commonHead,
        [(seq, clock, head) => UnifiedEffect.named('Corrupt clock')],
      );
      await folder.append(
        unifiedLogName(owner),
        Uint8List.fromList(utf8.encode('${corrupt.encode()}\n')),
      );
      final evidence = await folder.read(unifiedLogName(owner));
      await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
      await expectLater(
        history!.renameDevice('blocked'),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        profile!.database
            .select('SELECT * FROM protected_app_heads')
            .map((r) => r.toString())
            .toList(),
        heads,
      );
      expect(await folder.read(unifiedLogName(owner)), evidence);
      // Restore only this synthetic injected corruption to check subsequent clock continuation.
      await folder.file(unifiedLogName(owner)).writeAsBytes(before);
      await history!.refresh();
      await history!.renameDevice('Valid');
      expect(history!.snapshot.deviceName(owner), 'Valid');
    },
  );
}
