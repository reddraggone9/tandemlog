import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_import.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';

const space = '00000000-0000-4000-8000-000000000001';
const installation = '00000000-0000-4000-8000-000000000002';
const namespace = '00000000-0000-4000-8000-000000000003';
const otherNamespace = '00000000-0000-4000-8000-000000000004';
FoodImportPlan plan({
  String importId = namespace,
  int count = 3,
  String name = 'Synthetic beans',
  String? source,
}) => FoodImportPlan(
  space: space,
  importId: importId,
  sourceSha256: source ?? List.filled(64, 'a').join(),
  containers: [
    for (var n = 1; n <= count; n++)
      FoodImportContainer(
        sourceId: 'synthetic-row',
        ordinal: n,
        details: FoodDetails(
          name: name,
          brand: 'Example',
          expiry: '2027-03-01',
          retention: 'Fridge',
        ),
        contents: n == 1
            ? const Contents.fraction(1, 1)
            : const Contents.fraction(2, 6),
        createdAt: '2020-01-02T03:04:05+02:00',
      ),
  ],
);

class ImportFaultFolder extends LocalLogFolder {
  ImportFaultFolder(super.location);
  int? cut;
  bool failAfter = false;
  int writes = 0;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    writes++;
    final n = cut;
    cut = null;
    await super.append(
      name,
      n == null ? bytes : Uint8List.fromList(bytes.take(n).toList()),
    );
    if (n != null || failAfter) {
      failAfter = false;
      throw StateError('Synthetic uncertain append');
    }
  }
}

void main() {
  late Directory root;
  late LocalProfileDatabase db;
  late ImportFaultFolder folder;
  late TaskStore tasks;
  late FoodStore store;
  late String taskPrefix;
  Future<String> bytes() =>
      File('${folder.location}/$installation.applog').readAsString();
  Future<void> reopen({bool fresh = false}) async {
    await store.close();
    await tasks.close();
    await db.close();
    db = await LocalProfileDatabase.open(
      '${root.path}/${fresh ? 'fresh' : 'profile'}',
    );
    tasks = await TaskStore.open(
      folder,
      db.root,
      profileDatabase: db,
      writerIdentity: installation,
    );
    store = await FoodStore.openUnified(tasks.unified!);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'synthetic-current-food-import-',
    );
    db = await LocalProfileDatabase.open('${root.path}/profile');
    folder = ImportFaultFolder(
      (await Directory('${root.path}/data').create()).path,
    );
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(
        utf8.encode(UnifiedManifest.empty(space, installation).encode()),
      ),
    );
    tasks = await TaskStore.open(
      folder,
      db.root,
      profileDatabase: db,
      writerIdentity: installation,
    );
    await tasks.command(namespace, 'user.created', {'name': 'Synthetic owner'});
    await tasks.command(otherNamespace, 'task.created', {
      'title': 'Preserved task',
      'description': 'Exact notes',
      'assignee': namespace,
    });
    taskPrefix = await bytes();
    store = await FoodStore.openUnified(tasks.unified!);
    folder.writes = 0;
  });
  tearDown(() async {
    await store.close();
    await tasks.close();
    await db.close();
    await root.delete(recursive: true);
  });
  void noPrivateIntent() {
    expect(
      db.database.select(
        "SELECT name FROM sqlite_schema WHERE type='table' AND name IN ('protected_app_outbox','protected_food_intents')",
      ),
      isEmpty,
    );
    expect(
      db.database.select(
        "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
      ),
      isEmpty,
    );
  }

  test(
    'strict v1 contract canonical fractions stable identities and invalid inputs',
    () {
      final p = plan();
      final decoded = FoodImportPlan.decode(jsonEncode(p.toJson()));
      expect(decoded.planHash, p.planHash);
      expect(decoded.targetIds, p.targetIds);
      expect(p.containers[1].contents.toJson()['denominator'], 3);
      expect(
        () => FoodImportPlan.decode(jsonEncode({...p.toJson(), 'extra': true})),
        throwsFormatException,
      );
      expect(
        () => FoodImportPlan.decode(jsonEncode({...p.toJson(), 'v': 1.0})),
        throwsFormatException,
      );
      expect(
        () => FoodImportPlan(
          space: space,
          importId: namespace,
          sourceSha256: p.sourceSha256,
          containers: [p.containers.first, p.containers.first],
        ),
        throwsFormatException,
      );
      expect(() => plan(count: 1001), throwsFormatException);
      final row = {
        ...p.containers.first.toJson(),
        'createdAt': '2020-02-31T03:04:05Z',
      };
      expect(
        () => FoodImportPlan.decode(
          jsonEncode({
            ...p.toJson(),
            'containers': [row],
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'dry run writes nothing; one commit preserves Full partial contents and task prefix',
    () async {
      final p = plan();
      expect((await store.dryRunImport(p)).status, FoodImportStatus.ready);
      expect(folder.writes, 0);
      expect(await bytes(), taskPrefix);
      noPrivateIntent();
      final done = await store.commitImport(p);
      expect(done.status, FoodImportStatus.committed);
      expect(
        store.state.containers.map((c) => c.id).toSet(),
        p.targetIds.toSet(),
      );
      for (var i = 0; i < p.containers.length; i++) {
        final c = store.state.containers.singleWhere(
          (c) => c.id == p.targetIds[i],
        );
        expect(c.createdAt, p.containers[i].createdAt);
        expect(c.details.toJson(), p.containers[i].details.toJson());
        expect(c.contents.toJson(), p.containers[i].contents.toJson());
      }
      expect(folder.writes, 1);
      expect((await bytes()).startsWith(taskPrefix), isTrue);
      expect(
        (await bytes())
            .substring(taskPrefix.length)
            .split('\n')
            .where((l) => l.isNotEmpty),
        hasLength(1),
      );
      expect(
        tasks.unified!.snapshot.records.last.provenance!['planHash'],
        p.planHash,
      );
      noPrivateIntent();
    },
  );
  test(
    'cold retry after later edits and deletion uses canonical provenance',
    () async {
      final p = plan(), first = await store.commitImport(plan());
      await store.changeDetails(
        [p.targetIds.first],
        const FoodDetails(name: 'Later edit'),
        ['name'],
      );
      await store.remove([p.targetIds.last]);
      final prior = await bytes(), writes = folder.writes;
      await reopen(fresh: true);
      final repeated = await store.commitImport(p);
      expect(repeated.recordIds, first.recordIds);
      expect(await bytes(), prior);
      expect(folder.writes, writes);
      expect(
        store.state.containers
            .singleWhere((c) => c.id == p.targetIds.first)
            .details
            .name,
        'Later edit',
      );
      expect(
        store.state.containers
            .singleWhere((c) => c.id == p.targetIds.last)
            .deleted,
        isTrue,
      );
    },
  );
  test(
    'same-session partial retry uses only memory and publishes all containers together',
    () async {
      final p = plan();
      folder.cut = 71;
      await expectLater(store.commitImport(p), throwsStateError);
      final pending = tasks.unified!.pendingRecords.single,
          partial = await bytes();
      expect(store.state.containers, isEmpty);
      noPrivateIntent();
      expect(
        (await store.dryRunImport(p)).status,
        FoodImportStatus.pendingRecovery,
      );
      expect(await bytes(), partial);
      final done = await store.commitImport(p);
      expect(done.recordIds, pending.effects.map((e) => e.food!.id).toList());
      expect(await bytes(), '$taskPrefix${pending.encode()}\n');
      expect(store.state.containers, hasLength(3));
      final writes = folder.writes;
      await store.commitImport(p);
      expect(folder.writes, writes);
    },
  );
  for (final cut in [0, 71]) {
    test(
      'restart abandons incomplete import cut=$cut; preview is read-only and explicit commit replaces it',
      () async {
        final p = plan();
        folder.cut = cut;
        await expectLater(store.commitImport(p), throwsStateError);
        final partial = await bytes(), writes = folder.writes;
        await reopen();
        expect(store.hasPreparedAppend, isFalse);
        expect(store.state.containers, isEmpty);
        expect((await store.dryRunImport(p)).status, FoodImportStatus.ready);
        expect(await bytes(), partial);
        expect(folder.writes, writes);
        expect(
          (await store.commitImport(p)).status,
          FoodImportStatus.committed,
        );
        expect(
          store.state.containers.map((c) => c.id).toSet(),
          p.targetIds.toSet(),
        );
        expect((await bytes()).startsWith(taskPrefix), isTrue);
        expect(
          (await bytes())
              .substring(taskPrefix.length)
              .split('\n')
              .where((l) => l.isNotEmpty),
          hasLength(1),
        );
        noPrivateIntent();
      },
    );
  }
  test(
    'complete uncertain append survives without any private import ledger or second append',
    () async {
      folder.failAfter = true;
      await expectLater(store.commitImport(plan()), throwsStateError);
      final prior = await bytes(), writes = folder.writes;
      await reopen(fresh: true);
      expect(
        (await store.commitImport(plan())).status,
        FoodImportStatus.committed,
      );
      expect(await bytes(), prior);
      expect(folder.writes, writes);
      noPrivateIntent();
    },
  );
  test(
    'changed count source payload and source namespace refuse after canonical commit',
    () async {
      await store.commitImport(plan());
      final prior = await bytes();
      for (final p in [
        plan(count: 2),
        plan(name: 'Changed'),
        plan(source: List.filled(64, 'b').join()),
        plan(importId: otherNamespace),
      ]) {
        await expectLater(store.commitImport(p), throwsFormatException);
      }
      expect(await bytes(), prior);
    },
  );
  test(
    'a different source with a new namespace remains a distinct explicit import',
    () async {
      await store.commitImport(plan());
      final second = plan(
        importId: otherNamespace,
        source: List.filled(64, 'b').join(),
      );
      expect(
        (await store.commitImport(second)).status,
        FoodImportStatus.committed,
      );
      expect(store.state.containers, hasLength(6));
    },
  );
  test(
    'unrelated in-memory pending save is not retried by a completed import',
    () async {
      final p = plan();
      await store.commitImport(p);
      folder.cut = 3;
      await expectLater(
        store.add(const FoodDetails(name: 'Unrelated'), 1),
        throwsStateError,
      );
      final pending = tasks.unified!.pendingRecords.single.encode(),
          prior = await bytes(),
          writes = folder.writes;
      expect((await store.commitImport(p)).status, FoodImportStatus.committed);
      expect(tasks.unified!.pendingRecords.single.encode(), pending);
      expect(await bytes(), prior);
      expect(folder.writes, writes);
    },
  );
  test(
    'concurrent identical callbacks serialize into one canonical action',
    () async {
      final reports = await Future.wait([
        store.commitImport(plan()),
        store.commitImport(plan()),
      ]);
      expect(reports.first.recordIds, reports.last.recordIds);
      expect(folder.writes, 1);
      expect(
        (await bytes())
            .substring(taskPrefix.length)
            .split('\n')
            .where((l) => l.isNotEmpty),
        hasLength(1),
      );
    },
  );
  test(
    'maximum 1000-container import retains all IDs and cold retry does not append',
    () async {
      final p = plan(count: 1000),
          done = await store.commitImport(plan(count: 1000));
      final prior = await bytes(), writes = folder.writes;
      expect(done.recordIds, hasLength(1000));
      await reopen();
      expect((await store.commitImport(p)).recordIds, done.recordIds);
      expect(
        store.state.containers.map((c) => c.id).toSet(),
        p.targetIds.toSet(),
      );
      expect(await bytes(), prior);
      expect(folder.writes, writes);
    },
  );
  test('wrong workspace and protected writer refuse before append', () async {
    final p = plan(),
        wrong = FoodImportPlan(
          space: otherNamespace,
          importId: p.importId,
          sourceSha256: p.sourceSha256,
          containers: p.containers,
        );
    await expectLater(store.dryRunImport(wrong), throwsFormatException);
    await expectLater(store.commitImport(wrong), throwsFormatException);
    db.database.execute('UPDATE protected_settings SET writer=?,raw=?', [
      otherNamespace,
      utf8.encode(
        jsonEncode({'writer': otherNamespace, 'appearance': 'system'}),
      ),
    ]);
    await expectLater(store.commitImport(p), throwsFormatException);
    expect(folder.writes, 0);
    expect(await bytes(), taskPrefix);
  });
  test(
    'shared manifest change remains fatal and leaves import unstaged',
    () async {
      await File(
        '${folder.location}/tandemlog-space.json',
      ).writeAsString('{"v":3,"id":"$otherNamespace"}');
      await expectLater(
        store.commitImport(plan()),
        throwsA(isA<FormatFailure>()),
      );
      expect(folder.writes, 0);
      expect(await bytes(), taskPrefix);
      noPrivateIntent();
    },
  );
  test(
    'physical collision from a valid remote common action refuses before import',
    () async {
      final p = plan(),
          peer = otherNamespace,
          epoch = tasks.unified!.manifest.epoch;
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
      final clock = EventClock(BigInt.one);
      final birth = FoodRecord(
        space: space,
        writer: peer,
        sequence: 1,
        clock: clock,
        previousHash: header.hash,
        operation: FoodOperation(
          id: '$peer:1',
          order: 1,
          action: FoodAction.add,
          targets: [p.targetIds.first],
          details: p.containers.first.details,
          contents: p.containers.first.contents,
          createdAt: p.containers.first.createdAt,
        ),
      );
      final action = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: peer,
        sequence: 2,
        clock: clock,
        previousHash: header.hash,
        effect: UnifiedEffect('food', birth.encode()),
        observed: {peer: UnifiedFrontier(1, header.hash)},
      );
      await folder.create(
        unifiedLogName(peer),
        Uint8List.fromList(
          utf8.encode('${header.encode()}\n${action.encode()}\n'),
        ),
      );
      await expectLater(store.commitImport(p), throwsFormatException);
      expect(folder.writes, 0);
      expect(await bytes(), taskPrefix);
    },
  );
  test(
    'malformed complete common record blocks import and retains all bytes',
    () async {
      final peer = File('${folder.location}/$otherNamespace.applog');
      await peer.writeAsString('synthetic malformed common record\n');
      await expectLater(
        store.commitImport(plan()),
        throwsA(isA<FormatFailure>()),
      );
      expect(await peer.readAsString(), 'synthetic malformed common record\n');
      expect(await bytes(), taskPrefix);
      expect(folder.writes, 0);
    },
  );
}
