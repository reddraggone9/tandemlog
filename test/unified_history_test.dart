import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_admission.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
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

class CountingFolder extends FaultFolder {
  CountingFolder(super.location);
  int fullReads = 0, suffixReads = 0, suffixBytes = 0, nonemptySuffixReads = 0;
  bool fixedStamp = false, noSeek = false;
  List<LogFileInfo>? staleInventory;
  Uint8List? returnedSuffix;
  @override
  Future<List<LogFileInfo>> list() async =>
      staleInventory ??
      [
        for (final info in await super.list())
          LogFileInfo(
            info.name,
            fixedStamp ? 'fixed' : info.stamp,
            size: info.size,
            identity: info.identity,
          ),
      ];
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (name.endsWith('.applog')) fullReads++;
    return super.readBounded(name, maximumBytes);
  }

  @override
  Future<Uint8List?> readFromBounded(
    String name,
    int offset,
    int maximumBytes,
  ) async {
    suffixReads++;
    if (noSeek) return null;
    final bytes = await super.readFromBounded(name, offset, maximumBytes);
    returnedSuffix = bytes;
    suffixBytes += bytes?.length ?? 0;
    if (bytes != null && bytes.isNotEmpty) nonemptySuffixReads++;
    return bytes;
  }
}

class PreparationCountingFolder extends CountingFolder {
  PreparationCountingFolder(super.location);
  int lists = 0;
  @override
  Future<List<LogFileInfo>> list() {
    lists++;
    return super.list();
  }
}

class AfterAppendFolder extends CountingFolder {
  AfterAppendFolder(super.location);
  Future<void> Function()? afterAppend;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    await super.append(name, bytes);
    final action = afterAppend;
    afterAppend = null;
    await action?.call();
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

  Future<void> openAfterClosingProfile() async {
    await profile!.close();
    profile = null;
    await open();
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
    'fresh input callback uses one observation and preserves reservation order',
    () async {
      await history!.close();
      history = null;
      final counted = PreparationCountingFolder(folder.location);
      folder = counted;
      await openAfterClosingProfile();
      final h = history!, sequence = h.physicalSequence;
      final before = await folder.read(unifiedLogName(owner));
      counted.lists = 0;
      final order = <String>[];
      final reservation = await profile!.serialize(
        () => h.prepareFromFreshInputsInProfileQueue(
          () {
            order.add('build');
            expect(counted.lists, 1);
            expect(h.hasPending, isFalse);
            return [taskBuilder(newTask)];
          },
          onReserved: (records) {
            order.add('reserved');
            expect(h.hasPending, isTrue);
            expect(records.single.sequence, sequence + 1);
            expect(counted.lists, 1);
          },
        ),
      );
      expect(order, ['build', 'reserved']);
      expect(await folder.read(unifiedLogName(owner)), before);
      await profile!.serialize(h.commitInProfileQueue);
      expect(
        counted.lists,
        greaterThan(1),
        reason:
            'Final commit still observes canonical bytes and confirms its suffix.',
      );
      expect(await folder.read(unifiedLogName(owner)), [
        ...before,
        ...reservation.bytes,
      ]);
      expect(h.snapshot.tasks.any((e) => e.entity == newTask), isTrue);
      expect(h.physicalSequence, sequence + 1);
    },
  );

  test(
    'reusing a callback refreshes every call and refuses newly corrupt input',
    () async {
      final h = history!;
      var calls = 0;
      List<UnifiedEffectBuilder> build() {
        calls++;
        return [taskBuilder(const Uuid().v4())];
      }

      await profile!.serialize(
        () => h.prepareFromFreshInputsInProfileQueue(build),
      );
      await profile!.serialize(h.commitInProfileQueue);
      expect(calls, 1);
      final before = await folder.read(unifiedLogName(owner));
      await folder.append(
        unifiedLogName(owner),
        Uint8List.fromList(utf8.encode('{}\n')),
      );
      await expectLater(
        profile!.serialize(() => h.prepareFromFreshInputsInProfileQueue(build)),
        throwsA(isA<FormatFailure>()),
      );
      expect(calls, 1);
      expect(h.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), [
        ...before,
        ...utf8.encode('{}\n'),
      ]);
    },
  );

  test(
    'default preparation still refreshes and refuses newly corrupt input',
    () async {
      final h = history!;
      await folder.append(
        unifiedLogName(owner),
        Uint8List.fromList(utf8.encode('{}\n')),
      );
      var reserved = false;
      await expectLater(
        profile!.serialize(
          () => h.prepareInProfileQueue([
            taskBuilder(newTask),
          ], onReserved: (_) => reserved = true),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(reserved, isFalse);
      expect(h.hasPending, isFalse);
    },
  );

  test(
    'throwing fresh callback allocates nothing and keeps next sequence',
    () async {
      final h = history!, sequence = h.physicalSequence;
      final before = await folder.read(unifiedLogName(owner));
      final failure = StateError('Synthetic fresh input failure');
      await expectLater(
        profile!.serialize(
          () => h.prepareFromFreshInputsInProfileQueue(() => throw failure),
        ),
        throwsA(same(failure)),
      );
      expect(h.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), before);
      final reserved = await profile!.serialize(
        () => h.prepareFromFreshInputsInProfileQueue(
          () => [taskBuilder(newTask)],
        ),
      );
      expect(reserved.records.single.sequence, sequence + 1);
      await profile!.serialize(h.commitInProfileQueue);
    },
  );

  test(
    'fresh callback cannot begin closing its history and reserve an action',
    () async {
      final h = history!, before = await folder.read(unifiedLogName(owner));
      Future<void>? closing;
      await expectLater(
        profile!.serialize(
          () => h.prepareFromFreshInputsInProfileQueue(() {
            closing = h
                .close(); // Queued cleanup has not run while this callback executes.
            return [taskBuilder(newTask)];
          }),
        ),
        throwsA(isA<FormatFailure>()),
      );
      await closing;
      expect(h.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), before);
      history = null;
    },
  );

  for (final mutation in ['heads', 'writer', 'safety', 'manifest']) {
    test(
      'fresh callback rejects synchronous $mutation mutation before reservation',
      () async {
        final h = history!, before = await folder.read(unifiedLogName(owner));
        final db = profile!.database;
        final heads = db.select(
          'SELECT digest FROM protected_app_heads WHERE writer=?',
          [owner],
        ).single['digest'];
        final settings = db
            .select('SELECT writer,raw FROM protected_settings')
            .single;
        final originalManifest = h.manifest;
        var reserved = false;
        await expectLater(
          profile!.serialize(
            () => h.prepareFromFreshInputsInProfileQueue(() {
              if (mutation == 'heads') {
                db.execute(
                  'UPDATE protected_app_heads SET digest=? WHERE writer=?',
                  ['changed', owner],
                );
              } else if (mutation == 'writer') {
                final writer = const Uuid().v4();
                final raw =
                    jsonDecode(utf8.decode(settings['raw'] as List<int>))
                        as Map<String, dynamic>;
                raw['writer'] = writer;
                db.execute('UPDATE protected_settings SET writer=?,raw=?', [
                  writer,
                  utf8.encode(jsonEncode(raw)),
                ]);
              } else if (mutation == 'manifest') {
                h.manifest = UnifiedManifest.decode(h.manifest.encode());
              } else {
                h.safetyFailure = StateError('Synthetic safety report');
              }
              return [taskBuilder(newTask)];
            }, onReserved: (_) => reserved = true),
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(reserved, isFalse);
        expect(h.hasPending, isFalse);
        expect(await folder.read(unifiedLogName(owner)), before);
        db.execute('UPDATE protected_app_heads SET digest=? WHERE writer=?', [
          heads,
          owner,
        ]);
        db.execute('UPDATE protected_settings SET writer=?,raw=?', [
          settings['writer'],
          settings['raw'],
        ]);
        h.manifest = originalManifest;
        h.safetyFailure = null;
      },
    );
  }

  test(
    'owned incomplete tail is cleaned and reconfirmed before fresh callback',
    () async {
      final h = history!, before = await folder.read(unifiedLogName(owner));
      await folder.append(
        unifiedLogName(owner),
        Uint8List.fromList(utf8.encode('{"partial":')),
      );
      var called = false;
      final reserved = await profile!.serialize(
        () => h.prepareFromFreshInputsInProfileQueue(() {
          called = true;
          expect(h.snapshot.physical[owner], before);
          expect(folder.file(unifiedLogName(owner)).readAsBytesSync(), before);
          return [taskBuilder(newTask)];
        }),
      );
      expect(called, isTrue);
      await profile!.serialize(h.commitInProfileQueue);
      expect(await folder.read(unifiedLogName(owner)), [
        ...before,
        ...reserved.bytes,
      ]);
    },
  );

  test(
    'unsupported owned tail cleanup never enters the fresh callback',
    () async {
      await history!.close();
      history = null;
      await profile!.close();
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      history = await UnifiedHistory.open(
        AppendOnlyFolder(folder),
        profile: profile!,
        writer: owner,
        now: () => DateTime.utc(2026, 10, 17),
      );
      final before = await folder.read(unifiedLogName(owner));
      final tail = utf8.encode('{"unfinished":');
      await folder.append(unifiedLogName(owner), Uint8List.fromList(tail));
      var called = false;
      await expectLater(
        profile!.serialize(
          () => history!.prepareFromFreshInputsInProfileQueue(() {
            called = true;
            return [taskBuilder(newTask)];
          }),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(called, isFalse);
      expect(history!.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), [...before, ...tail]);
    },
  );

  test(
    'pending reservation refuses fresh builder without changing exact bytes',
    () async {
      final h = history!;
      final first = await profile!.serialize(
        () => h.prepareInProfileQueue([taskBuilder(newTask)]),
      );
      var called = false;
      await expectLater(
        profile!.serialize(
          () => h.prepareFromFreshInputsInProfileQueue(() {
            called = true;
            return [foodBuilder()];
          }),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(called, isFalse);
      expect(h.pendingRecords.single.encode(), first.records.single.encode());
      await profile!.serialize(h.commitInProfileQueue);
      expect(h.hasPending, isFalse);
    },
  );

  test(
    'fresh onReserved failure rolls back reservation and preserves next allocation',
    () async {
      final h = history!, sequence = h.physicalSequence;
      final before = await folder.read(unifiedLogName(owner));
      final failure = StateError('Synthetic reservation callback failure');
      await expectLater(
        profile!.serialize(
          () => h.prepareFromFreshInputsInProfileQueue(
            () => [taskBuilder(newTask)],
            onReserved: (_) => throw failure,
          ),
        ),
        throwsA(same(failure)),
      );
      expect(h.hasPending, isFalse);
      expect(await folder.read(unifiedLogName(owner)), before);
      final next = await profile!.serialize(
        () => h.prepareFromFreshInputsInProfileQueue(
          () => [taskBuilder(newTask)],
        ),
      );
      expect(next.records.single.sequence, sequence + 1);
      await profile!.serialize(h.commitInProfileQueue);
    },
  );

  for (final corruption in ['ownReplacement', 'completeInvalidPeer']) {
    test(
      'fresh reservation retains final commit safety after $corruption',
      () async {
        final h = history!, before = await folder.read(unifiedLogName(owner));
        final reservation = await profile!.serialize(
          () => h.prepareFromFreshInputsInProfileQueue(
            () => [taskBuilder(newTask)],
          ),
        );
        final raw = reservation.records.single.encode();
        if (corruption == 'ownReplacement') {
          final replacement = File('${folder.location}/replacement.tmp');
          await replacement.writeAsBytes(
            Uint8List.fromList(before)..[10] ^= 1,
            flush: true,
          );
          await replacement.rename(folder.file(unifiedLogName(owner)).path);
        } else {
          final peer = const Uuid().v4();
          await folder.create(
            unifiedLogName(peer),
            Uint8List.fromList(utf8.encode('{}\n')),
          );
        }
        await expectLater(
          profile!.serialize(h.commitInProfileQueue),
          throwsA(isA<FormatFailure>()),
        );
        expect(h.hasPending, isTrue);
        expect(h.pendingRecords.single.encode(), raw);
        if (corruption == 'completeInvalidPeer') {
          expect(await folder.read(unifiedLogName(owner)), before);
        }
      },
    );
  }

  test('peer Food deltas reuse exact admitted base; missing references wait '
      'and resolve with the same full replay', () async {
    final h = history!, peer = const Uuid().v4(), other = const Uuid().v4();
    final first = const Uuid().v4(), second = const Uuid().v4();
    final time = h.maximumClock!.value.toInt();
    final joined = actionRecord(
      peer,
      1,
      time + 1,
      unifiedGenesis(space, _actionEpoch, peer),
      [(_, _, _) => UnifiedEffect.joined()],
    );
    await folder.create(
      unifiedLogName(peer),
      Uint8List.fromList(utf8.encode('${joined.encode()}\n')),
    );
    await h.refresh();
    final beforeFull = h.fullFoodAdmissionRuns;
    final beforeDelta = h.incrementalFoodAdmissionRuns;
    final beforeTaskSorts = h.semanticTaskSortRuns;
    final added = actionRecord(peer, 2, time + 2, joined.hash, [
      (seq, clock, head) => UnifiedEffect(
        'food',
        FoodRecord(
          space: space,
          writer: peer,
          sequence: seq,
          clock: clock,
          previousHash: head,
          operation: FoodOperation(
            id: '$peer:$seq',
            order: clock.value.toInt(),
            action: FoodAction.add,
            targets: [first, second],
            details: const FoodDetails(name: 'Synthetic peer'),
            createdAt: '2026-10-22T00:00:00Z',
          ),
        ).encode(),
      ),
    ]);
    await folder.append(
      unifiedLogName(peer),
      Uint8List.fromList(utf8.encode('${added.encode()}\n')),
    );
    await h.refresh();
    expect(h.incrementalFoodAdmissionRuns, greaterThan(beforeDelta));
    expect(h.fullFoodAdmissionRuns, beforeFull);
    expect(h.semanticTaskSortRuns, beforeTaskSorts);
    void oracle() {
      final full = admitFoodRecords(
        h.snapshot.effects.map((e) => e.food).whereType<FoodRecord>().toList(),
        legacyOwners: h.manifest.referenceAuthors,
      );
      expect(h.snapshot.foodAdmission.readyIds, full.readyIds);
      expect(
        h.snapshot.foodAdmission.births.keys.toSet(),
        full.births.keys.toSet(),
      );
      expect(
        h.snapshot.foodAdmission.state.containers
            .map((c) => c.toJson())
            .toList(),
        full.state.containers.map((c) => c.toJson()).toList(),
      );
    }

    oracle();
    // A missing observed deletion cannot be marked ready by incremental reuse.
    final waiting = actionRecord(peer, 3, time + 20, added.hash, [
      (seq, clock, head) => UnifiedEffect(
        'food',
        FoodRecord(
          space: space,
          writer: peer,
          sequence: seq,
          clock: clock,
          previousHash: head,
          createdWith: {first: '$peer:2', second: '$peer:2'},
          operation: FoodOperation(
            id: '$peer:$seq',
            order: clock.value.toInt(),
            action: FoodAction.restore,
            targets: [first, second],
            observedDeletes: ['$other:2'],
          ),
        ).encode(),
      ),
    ]);
    final beforePending = h.fullFoodAdmissionRuns;
    await folder.append(
      unifiedLogName(peer),
      Uint8List.fromList(utf8.encode('${waiting.encode()}\n')),
    );
    await h.refresh();
    expect(h.fullFoodAdmissionRuns, greaterThan(beforePending));
    expect(h.snapshot.foodAdmission.readyIds, isNot(contains('$peer:3')));
    oracle();
    final otherJoined = actionRecord(
      other,
      1,
      time + 3,
      unifiedGenesis(space, _actionEpoch, other),
      [(_, _, _) => UnifiedEffect.joined()],
    );
    final removed = actionRecord(other, 2, time + 4, otherJoined.hash, [
      (seq, clock, head) => UnifiedEffect(
        'food',
        FoodRecord(
          space: space,
          writer: other,
          sequence: seq,
          clock: clock,
          previousHash: head,
          createdWith: {first: '$peer:2', second: '$peer:2'},
          operation: FoodOperation(
            id: '$other:$seq',
            order: clock.value.toInt(),
            action: FoodAction.remove,
            targets: [first, second],
          ),
        ).encode(),
      ),
    ]);
    await folder.create(
      unifiedLogName(other),
      Uint8List.fromList(
        utf8.encode('${otherJoined.encode()}\n${removed.encode()}\n'),
      ),
    );
    await h.refresh();
    expect(
      h.snapshot.foodAdmission.readyIds,
      containsAll(['$other:2', '$peer:3']),
    );
    oracle();
    expect(
      h.snapshot.foodAdmission.state.containers
          .where((c) => c.id == first || c.id == second)
          .every((c) => !c.deleted),
      isTrue,
    );
    expect(h.semanticTaskSortRuns, beforeTaskSorts);
    final newUser = const Uuid().v4();
    final taskChange = actionRecord(peer, 4, time + 21, waiting.hash, [
      (seq, clock, head) => UnifiedEffect(
        'task',
        LogEvent(space, peer, seq, clock, newUser, 'user.created', {
          'name': 'Synthetic changed Task input',
        }).encode(previousHash: head),
      ),
    ]);
    await folder.append(
      unifiedLogName(peer),
      Uint8List.fromList(utf8.encode('${taskChange.encode()}\n')),
    );
    await h.refresh();
    expect(h.semanticTaskSortRuns, greaterThan(beforeTaskSorts));
    expect(h.snapshot.readyTaskIds, contains('$peer:4'));
    expect(h.snapshot.tasks.any((event) => event.entity == newUser), isTrue);
    oracle();
  });

  test(
    'Food clears common pending warning after a held Task-only action resolves',
    () async {
      final food = await FoodStore.openUnified(history!);
      try {
        final admission = history!.snapshot.foodAdmission;
        final peer = const Uuid().v4();
        final time = history!.maximumClock!.value.toInt();
        final joined = actionRecord(
          peer,
          1,
          time + 5,
          unifiedGenesis(space, history!.manifest.epoch, peer),
          [(seq, clock, head) => UnifiedEffect.joined()],
        );
        final held = actionRecord(
          owner,
          history!.physicalSequence + 1,
          time + 10,
          history!.commonHead,
          [taskBuilder(newTask)],
          logicalStart: history!.logicalSequence + 1,
          observed: {
            owner: UnifiedFrontier(
              history!.physicalSequence,
              history!.commonHead,
            ),
            peer: UnifiedFrontier(1, joined.hash),
          },
        );
        await folder.append(
          unifiedLogName(owner),
          Uint8List.fromList(utf8.encode('${held.encode()}\n')),
        );
        await history!.refresh();
        expect(history!.snapshot.pendingEffects, isTrue);
        expect(identical(history!.snapshot.foodAdmission, admission), isTrue);
        expect(food.pendingReferences, 1);
        await folder.create(
          unifiedLogName(peer),
          Uint8List.fromList(utf8.encode('${joined.encode()}\n')),
        );
        await history!.refresh();
        expect(history!.snapshot.pendingEffects, isFalse);
        expect(identical(history!.snapshot.foodAdmission, admission), isTrue);
        expect(food.pendingReferences, 0);
        expect(food.pendingOperationIds, isEmpty);
        await food.add(const FoodDetails(name: 'After recovery'), 1);
        expect(
          food.state.active.any((c) => c.details.name == 'After recovery'),
          isTrue,
        );
      } finally {
        await food.close();
      }
    },
  );

  test(
    'peer arriving after owned append is admitted next poll without mixing action snapshots',
    () async {
      await history!.close();
      history = null;
      final counted = AfterAppendFolder(folder.location);
      folder = counted;
      await openAfterClosingProfile();
      final peer = const Uuid().v4();
      final baseSequence = history!.physicalSequence;
      final joined = actionRecord(
        peer,
        1,
        9000000000000000,
        unifiedGenesis(space, history!.manifest.epoch, peer),
        [(seq, clock, head) => UnifiedEffect.joined()],
      );
      counted.afterAppend = () => counted.create(
        unifiedLogName(peer),
        Uint8List.fromList(utf8.encode('${joined.encode()}\n')),
      );
      await history!.appendAtomic([taskBuilder(newTask)]);
      expect(history!.physicalSequence, baseSequence + 1);
      expect(history!.snapshot.records.any((r) => r.writer == peer), isFalse);
      await history!.refresh();
      expect(history!.snapshot.records.any((r) => r.writer == peer), isTrue);
      expect(history!.snapshot.tasks.any((e) => e.entity == newTask), isTrue);
    },
  );

  test(
    'pending own append is reconciled from actual suffix despite stale metadata',
    () async {
      await history!.close();
      history = null;
      final counted = CountingFolder(folder.location);
      folder = counted;
      await openAfterClosingProfile();
      final reservation = await profile!.serialize(
        () => history!.prepareInProfileQueue([taskBuilder(newTask)]),
      );
      counted.staleInventory = await counted.list();
      final before = await counted.read(unifiedLogName(owner));
      await counted.append(unifiedLogName(owner), reservation.bytes);
      // Simulate append reaching disk without acknowledgment and stale list hints.
      await expectLater(
        profile!.serialize(() => history!.commitInProfileQueue()),
        throwsA(isA<FormatFailure>()),
      );
      expect(history!.hasPending, false);
      expect(await counted.read(unifiedLogName(owner)), [
        ...before,
        ...reservation.bytes,
      ]);
      await history!.recoverPrepared();
      expect(history!.physicalSequence, reservation.records.single.sequence);
      expect(await counted.read(unifiedLogName(owner)), [
        ...before,
        ...reservation.bytes,
      ]);
    },
  );

  test(
    'unseekable provider never skips history based only on metadata',
    () async {
      await history!.close();
      history = null;
      final counted = CountingFolder(folder.location)..noSeek = true;
      folder = counted;
      await openAfterClosingProfile();
      counted.fullReads = 0;
      await history!.refresh();
      expect(counted.fullReads, converted.files.length);
      counted.fullReads = 0;
      await history!.refresh();
      expect(counted.fullReads, converted.files.length);
    },
  );

  test(
    'protected chain head must occur at the exact protected byte boundary',
    () async {
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_heads SET bytes=bytes-1 WHERE writer=?',
          [owner],
        ),
      );
      await expectLater(
        profile!.serialize(
          () => history!.refreshInProfileQueue(forceFullAudit: true),
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test('local actual seek rejects a suffix exceeding its read bound', () async {
    final name = unifiedLogName(owner);
    final bytes = await folder.read(name);
    final end = bytes.length - 2;
    await expectLater(
      folder.readFromBounded(name, end, 1),
      throwsA(isA<FormatException>()),
    );
    expect(await folder.readFromBounded(name, end, 2), bytes.sublist(end));
  });

  test(
    'normal unchanged refresh reads no history; growth reads one suffix; audit reads all',
    () async {
      await history!.close();
      history = null;
      final counted = CountingFolder(folder.location);
      folder = counted;
      await openAfterClosingProfile();
      counted.fullReads = counted.suffixReads = counted.suffixBytes =
          counted.nonemptySuffixReads = 0;
      await history!.refresh();
      expect(counted.fullReads, 0);
      expect(counted.suffixReads, 0);
      final reservation = await profile!.serialize(
        () => history!.prepareInProfileQueue([taskBuilder(newTask)]),
      );
      await profile!.serialize(() => history!.commitInProfileQueue());
      expect(counted.fullReads, 0);
      expect(
        counted.suffixReads,
        2,
      ); // Fresh preappend observation and readback.
      expect(counted.suffixBytes, reservation.bytes.length);
      expect(counted.nonemptySuffixReads, 1);
      expect(history!.hasPending, false);
      counted.fullReads = counted.suffixReads = 0;
      await profile!.serialize(
        () => history!.refreshInProfileQueue(forceFullAudit: true),
      );
      expect(counted.fullReads, converted.files.length);
      expect(
        counted.suffixReads,
        converted.files.length,
      ); // Actual seek probes.
    },
  );

  test(
    'unchanged metadata defers unread prefix damage to explicit full audit',
    () async {
      await history!.close();
      history = null;
      final counted = CountingFolder(folder.location)..fixedStamp = true;
      folder = counted;
      await openAfterClosingProfile();
      final target = counted.file(unifiedLogName(owner));
      final bytes = await target.readAsBytes();
      final changed = Uint8List.fromList(bytes);
      changed[10] ^= 1;
      await target.writeAsBytes(changed, flush: true);
      counted.fullReads = counted.suffixReads = 0;
      await history!.refresh();
      expect(counted.fullReads, 0);
      expect(counted.suffixReads, 0);
      await expectLater(
        profile!.serialize(
          () => history!.refreshInProfileQueue(forceFullAudit: true),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(counted.fullReads, greaterThan(0));
      expect(history!.snapshot.physical[owner], bytes);
    },
  );

  test(
    'legacy full-byte checkpoint is verified before chain commitment promotion',
    () async {
      final actual = await folder.read(unifiedLogName(owner));
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_heads SET digest=? WHERE writer=?',
          [bytesDigest(actual), owner],
        ),
      );
      await profile!.serialize(
        () => history!.refreshInProfileQueue(forceFullAudit: true),
      );
      expect(
        profile!.database.select(
          'SELECT digest FROM protected_app_heads WHERE writer=?',
          [owner],
        ).single['digest'],
        'chain1:${history!.commonHead}',
      );
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_heads SET digest=? WHERE writer=?',
          [List.filled(64, '0').join(), owner],
        ),
      );
      await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
    },
  );

  test('unknown and mismatched chain commitment tags fail closed', () async {
    for (final digest in [
      'chain2:unknown',
      'chain1:${List.filled(64, '0').join()}',
    ]) {
      profile!.transaction(
        () => profile!.database.execute(
          'UPDATE protected_app_heads SET digest=? WHERE writer=?',
          [digest, owner],
        ),
      );
      await expectLater(history!.refresh(), throwsA(isA<FormatFailure>()));
    }
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
    'original reservation bytes resist aliases and lost acknowledgement never rebases or duplicates',
    () async {
      final before = await folder.read(unifiedLogName(owner));
      final baseSequence = history!.physicalSequence;
      final reservation = await profile!.serialize(
        () => history!.prepareInProfileQueue([
          taskBuilder(newTask),
          foodBuilder(),
        ]),
      );
      final exact = List<int>.from(reservation.bytes);
      expect(() => reservation.bytes[0] ^= 1, throwsUnsupportedError);
      expect(
        () => Uint8List.sublistView(reservation.bytes)[0] ^= 1,
        throwsUnsupportedError,
      );
      expect(
        () => reservation.bytes.buffer.asUint8List(
          reservation.bytes.offsetInBytes,
          reservation.bytes.lengthInBytes,
        )[0] ^= 1,
        throwsUnsupportedError,
      );
      expect(
        () => reservation.bytes.buffer
            .asByteData(
              reservation.bytes.offsetInBytes,
              reservation.bytes.lengthInBytes,
            )
            .setUint8(0, 0),
        throwsUnsupportedError,
      );
      expect(reservation.bytes, exact);
      final ids = history!.pendingRecords.single.effects
          .map((e) => e.id)
          .toList();
      folder.cut =
          1000000; // Writes the whole action, then loses acknowledgement.
      await expectLater(
        profile!.serialize(history!.commitInProfileQueue),
        throwsA(isA<FileSystemException>()),
      );
      expect(history!.hasPending, isTrue);
      expect(await folder.read(unifiedLogName(owner)), [...before, ...exact]);
      await history!.recoverPrepared();
      expect(history!.hasPending, isFalse);
      expect(history!.physicalSequence, baseSequence + 1);
      expect(
        history!.snapshot.recordsByWriter[owner]!.last.effects.map((e) => e.id),
        ids,
      );
      expect(
        profile!.database.select(
          'SELECT sequence FROM protected_app_heads WHERE writer=?',
          [owner],
        ).single['sequence'],
        baseSequence + 1,
      );
      final acknowledged = await folder.read(unifiedLogName(owner));
      await history!.recoverPrepared();
      await history!.recoverPrepared();
      expect(await folder.read(unifiedLogName(owner)), acknowledged);
    },
  );

  test(
    'callback failure retains original base proof and mutated prefix cannot change its receipt',
    () async {
      final store = await TaskStore.openUnified(history!);
      try {
        final before = await folder.read(unifiedLogName(owner));
        OperationReceipt? receipt;
        await expectLater(
          store.command(
            newTask,
            'user.created',
            {'name': 'Retained synthetic receipt'},
            onPrepared: (r) {
              receipt = r;
              throw StateError('Synthetic callback failure');
            },
          ),
          throwsStateError,
        );
        expect(receipt, isNotNull);
        expect(history!.hasPending, isTrue);
        expect(await folder.read(unifiedLogName(owner)), before);
        final exact = utf8.encode(
          '${history!.pendingRecords.single.encode()}\n',
        );
        final changed = Uint8List.fromList(before)..[10] ^= 1;
        await File(
          '${folder.location}/${unifiedLogName(owner)}',
        ).writeAsBytes(changed, flush: true);
        await expectLater(
          history!.recoverPrepared(),
          throwsA(isA<FormatFailure>()),
        );
        expect(history!.pendingRecords.single.effects.single.id, receipt!.id);
        expect(history!.pendingRecords.single.effects.single.raw, receipt!.raw);
        expect(await folder.read(unifiedLogName(owner)), changed);
        await File(
          '${folder.location}/${unifiedLogName(owner)}',
        ).writeAsBytes(before, flush: true);
        await history!.recoverPrepared();
        expect(await folder.read(unifiedLogName(owner)), [...before, ...exact]);
        expect(store.confirmedOperations([receipt!]), contains(receipt!.id));
        expect(history!.hasPending, isFalse);
      } finally {
        await store.close();
      }
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
        final visibleRevision = TaskStore.canonicalTaskRevision(waiting.tasks);
        final blockedRevision = TaskStore.canonicalTaskRevision([
          ...waiting.tasks,
          ...mixed.effects.map((e) => e.task).whereType<LogEvent>(),
        ]);
        expect(visibleRevision, isNot(blockedRevision));
        expect(history!.verifiesTaskRevision(waiting, visibleRevision), isTrue);
        expect(
          history!.verifiesTaskRevision(waiting, blockedRevision),
          isFalse,
        );
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
        final readyRevision = TaskStore.canonicalTaskRevision(ready.tasks);
        expect(history!.verifiesTaskRevision(ready, readyRevision), isTrue);
        expect(history!.verifiesTaskRevision(ready, visibleRevision), isFalse);
        expect(
          history!.verifiesTaskRevision(waiting, visibleRevision),
          isFalse,
        );
        final unchanged = await history!.refresh();
        expect(history!.verifiesTaskRevision(unchanged, readyRevision), isTrue);
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
              'completedInstant': '2026-10-18T00:00:00.000000Z',
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
