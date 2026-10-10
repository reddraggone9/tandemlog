import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_import.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_food_intents.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/domain/event.dart';

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
          estimated: null,
          retention: 'Fridge',
        ),
        contents: n == 1
            ? const Contents.unknown()
            : const Contents.fraction(2, 6),
        createdAt: '2020-01-02T03:04:05+02:00',
      ),
  ],
);

class ImportFaultFolder implements LogFolder, BoundedLogFolder {
  ImportFaultFolder(this.inner);
  final LocalLogFolder inner;
  int? cut;
  bool failAfter = false;
  int writes = 0;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String n) => inner.read(n);
  @override
  Future<Uint8List> readBounded(String n, int max) => inner.readBounded(n, max);
  Future<void> write(String n, Uint8List b, bool create) async {
    writes++;
    final prefix = cut;
    cut = null;
    final bytes = prefix == null
        ? b
        : Uint8List.sublistView(b, 0, prefix.clamp(0, b.length));
    if (create) {
      await inner.create(n, bytes);
    } else {
      await inner.append(n, bytes);
    }
    if (prefix != null || failAfter) {
      failAfter = false;
      throw StateError('Synthetic uncertain append');
    }
  }

  @override
  Future<void> create(String n, Uint8List b) => write(n, b, true);
  @override
  Future<void> append(String n, Uint8List b) => write(n, b, false);
}

void main() {
  late Directory root;
  late LocalProfileDatabase db;
  late ImportFaultFolder folder;
  late FoodStore store;
  late TaskStore tasks;
  late String taskBytes;
  Future<void> reopen() async {
    await store.close();
    await tasks.close();
    await db.close();
    db = await LocalProfileDatabase.open('${root.path}/profile');
    tasks = await TaskStore.open(
      folder,
      db.root,
      profileDatabase: db,
      writerIdentity: installation,
    );
    store = await FoodStore.open(
      folder,
      profile: db,
      installationWriter: installation,
      space: space,
    );
  }

  Future<String> bytes() =>
      File('${folder.location}/${foodLogName(store.writer)}').readAsString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('synthetic-food-import-');
    db = await LocalProfileDatabase.open('${root.path}/profile');
    folder = ImportFaultFolder(
      LocalLogFolder((await Directory('${root.path}/data').create()).path),
    );
    await File(
      '${folder.location}/tandemlog-space.json',
    ).writeAsString('{"v":3,"id":"$space"}');
    tasks = await TaskStore.open(
      folder,
      db.root,
      profileDatabase: db,
      writerIdentity: installation,
    );
    await tasks.command(namespace, 'user.created', {'name': 'Synthetic owner'});
    await tasks.command(otherNamespace, 'task.created', {
      'title': 'Preserved scalar v3 task',
      'description': 'Exact notes',
      'assignee': namespace,
    });
    taskBytes = await File(
      '${folder.location}/$installation.jsonl',
    ).readAsString();
    folder.writes = 0;
    db.database.execute("INSERT INTO protected_settings VALUES (1,?,?)", [
      installation,
      utf8.encode(jsonEncode({'writer': installation, 'appearance': 'dark'})),
    ]);
    store = await FoodStore.open(
      folder,
      profile: db,
      installationWriter: installation,
      space: space,
    );
  });
  tearDown(() async {
    await store.close();
    await tasks.close();
    await db.close();
    await root.delete(recursive: true);
  });
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
    'dry run stages nothing and explicit commit preserves physical and unknown data',
    () async {
      final p = plan();
      final report = await store.dryRunImport(p);
      expect(report.status, FoodImportStatus.ready);
      expect(folder.writes, 0);
      expect(ProfileFoodIntents(db).pending(space, store.writer), isEmpty);
      expect(
        db.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
      final done = await store.commitImport(p);
      expect(done.status, FoodImportStatus.committed);
      expect(
        store.state.containers.map((c) => c.id).toSet(),
        p.targetIds.toSet(),
      );
      for (var n = 0; n < 3; n++) {
        final c = store.state.containers.singleWhere(
          (c) => c.id == p.targetIds[n],
        );
        expect(c.createdAt, p.containers[n].createdAt);
        expect(c.details.toJson(), p.containers[n].details.toJson());
        expect(c.contents.toJson(), p.containers[n].contents.toJson());
      }
      expect(
        await File('${folder.location}/$installation.jsonl').readAsString(),
        taskBytes,
      );
      expect(
        utf8.decode(
          db.database.select("SELECT raw FROM protected_settings").single['raw']
              as List<int>,
        ),
        jsonEncode({'writer': installation, 'appearance': 'dark'}),
      );
    },
  );
  test(
    'cold retry after later edit and deletion uses original admission not projection',
    () async {
      final p = plan();
      final first = await store.commitImport(p);
      await store.changeDetails(
        [p.targetIds.first],
        const FoodDetails(name: 'Later edit'),
        ['name'],
      );
      await store.remove([p.targetIds.last]);
      final prior = await bytes();
      final writes = folder.writes;
      await reopen();
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
    'partial append cold retry recovers exact reserved bytes without fresh IDs',
    () async {
      final p = plan();
      folder.cut = 71;
      await expectLater(store.commitImport(p), throwsStateError);
      final prepared = ProfileFoodIntents(db)
          .pending(space, store.writer)
          .map((b) => FoodRecord.decode(utf8.decode(b)))
          .toList();
      final expected = prepared.map((r) => '${r.encode()}\n').join();
      expect(prepared.length, 3);
      await reopen();
      expect(
        (await store.dryRunImport(p)).status,
        FoodImportStatus.pendingRecovery,
      );
      final done = await store.commitImport(p);
      expect(done.recordIds, prepared.map((r) => r.id).toList());
      expect(await bytes(), expected);
      expect(ProfileFoodIntents(db).pending(space, store.writer), isEmpty);
      await reopen();
      expect((await store.commitImport(p)).status, FoodImportStatus.committed);
      expect(await bytes(), expected);
    },
  );
  test(
    'uncertain full append cold retry admits originals without second append',
    () async {
      final p = plan();
      folder.failAfter = true;
      await expectLater(store.commitImport(p), throwsStateError);
      final prior = await bytes();
      final writes = folder.writes;
      await reopen();
      expect((await store.commitImport(p)).status, FoodImportStatus.committed);
      expect(folder.writes, writes);
      expect(await bytes(), prior);
    },
  );
  test(
    'changed count source payload and namespace refuse after attempt',
    () async {
      final p = plan();
      await store.commitImport(p);
      final prior = await bytes();
      for (final changed in [
        plan(count: 2),
        plan(name: 'Changed'),
        plan(source: List.filled(64, 'b').join()),
        plan(importId: otherNamespace),
      ]) {
        await expectLater(store.commitImport(changed), throwsFormatException);
      }
      expect(await bytes(), prior);
    },
  );
  test(
    'atomic ledger staging failure preserves canonical guard and intents',
    () async {
      final guardBefore = List<int>.from(
        db.database.select(
              'SELECT raw FROM protected_writer_guards WHERE writer=?',
              [store.writer],
            ).single['raw']
            as List<int>,
      );
      db.database.execute(
        "CREATE TRIGGER import_fail BEFORE INSERT ON profile_metadata WHEN NEW.key LIKE 'food.import.%' BEGIN SELECT RAISE(ABORT,'synthetic import ledger fault'); END",
      );
      await expectLater(store.commitImport(plan()), throwsA(anything));
      expect(folder.writes, 0);
      expect(ProfileFoodIntents(db).pending(space, store.writer), isEmpty);
      expect(
        db.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
      expect(
        db.database.select('SELECT * FROM protected_food_import_witnesses'),
        isEmpty,
      );
      expect(
        db.database.select(
          'SELECT raw FROM protected_writer_guards WHERE writer=?',
          [store.writer],
        ).single['raw'],
        guardBefore,
      );
      db.database.execute('DROP TRIGGER import_fail');
      expect(
        (await store.commitImport(plan())).status,
        FoodImportStatus.committed,
      );
    },
  );
  test('missing attempt or source witness fails closed', () async {
    final p = plan();
    await store.commitImport(p);
    final prior = await bytes();
    db.database.execute(
      "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%attempt.%'",
    );
    await expectLater(store.commitImport(p), throwsFormatException);
    expect(await bytes(), prior);
  });
  test('unrelated pending receipt is not recovered as import', () async {
    final p = plan();
    await store.commitImport(p);
    folder.cut = 3;
    await expectLater(
      store.add(const FoodDetails(name: 'Unrelated'), 1),
      throwsStateError,
    );
    final pending = ProfileFoodIntents(db).pending(space, store.writer);
    final prior = await bytes();
    final writes = folder.writes;
    expect((await store.commitImport(p)).status, FoodImportStatus.committed);
    expect(
      ProfileFoodIntents(
        db,
      ).pending(space, store.writer).map((v) => utf8.decode(v)).toList(),
      pending.map((v) => utf8.decode(v)).toList(),
    );
    expect(await bytes(), prior);
    expect(folder.writes, writes);
  });
  test('wrong workspace refuses without reserving or appending', () async {
    final p = plan();
    final wrong = FoodImportPlan(
      space: otherNamespace,
      importId: p.importId,
      sourceSha256: p.sourceSha256,
      containers: p.containers,
    );
    await expectLater(store.dryRunImport(wrong), throwsFormatException);
    await expectLater(store.commitImport(wrong), throwsFormatException);
    expect(folder.writes, 0);
  });
  test(
    'missing index with retained attempt refuses a new source namespace',
    () async {
      await store.commitImport(plan());
      final prior = await bytes();
      db.database.execute(
        "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%index'",
      );
      await expectLater(
        store.commitImport(
          plan(importId: otherNamespace, source: List.filled(64, 'b').join()),
        ),
        throwsFormatException,
      );
      expect(await bytes(), prior);
    },
  );
  test(
    'pre-byte crash changed plan and missing ledger cannot restamp prepared receipts',
    () async {
      final p = plan();
      folder.cut = 0;
      await expectLater(store.commitImport(p), throwsStateError);
      final intents = ProfileFoodIntents(
        db,
      ).pending(space, store.writer).map(utf8.decode).toList();
      await expectLater(
        store.commitImport(plan(count: 2)),
        throwsFormatException,
      );
      db.database.execute(
        "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%attempt.%'",
      );
      await expectLater(store.commitImport(p), throwsFormatException);
      expect(
        ProfileFoodIntents(
          db,
        ).pending(space, store.writer).map(utf8.decode).toList(),
        intents,
      );
      expect(await bytes(), '');
    },
  );
  test(
    'physical collision with remote birth without local ledger refuses',
    () async {
      final p = plan();
      final clock = EventClock(BigInt.one);
      final remote = foodWriter(otherNamespace);
      final birth = FoodRecord(
        space: space,
        writer: remote,
        sequence: 1,
        clock: clock,
        operation: FoodOperation(
          id: '$remote:1',
          order: 1,
          action: FoodAction.add,
          targets: [p.targetIds.first],
          details: p.containers.first.details,
          contents: p.containers.first.contents,
          createdAt: p.containers.first.createdAt,
        ),
        previousHash: eventGenesisHash(space, remote),
      );
      await folder.inner.create(
        foodLogName(remote),
        Uint8List.fromList(utf8.encode('${birth.encode()}\n')),
      );
      await expectLater(store.commitImport(p), throwsFormatException);
      expect(folder.writes, 0);
      expect(
        db.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'concurrent identical commit callbacks serialize into one original batch',
    () async {
      final p = plan();
      final reports = await Future.wait([
        store.commitImport(p),
        store.commitImport(p),
      ]);
      expect(reports.first.recordIds, reports.last.recordIds);
      expect(folder.writes, 1);
      expect(
        (await bytes()).split('\n').where((line) => line.isNotEmpty).length,
        3,
      );
    },
  );
  test(
    'fully staged maximum batch preserves all 1000 physical identities',
    () async {
      final p = plan(count: 1000);
      expect((await store.dryRunImport(p)).targetIds.length, 1000);
      final result = await store.commitImport(p);
      expect(result.recordIds.length, 1000);
      await reopen();
      expect((await store.commitImport(p)).recordIds, result.recordIds);
      expect(store.state.containers.length, 1000);
      expect(
        await File('${folder.location}/$installation.jsonl').readAsString(),
        taskBytes,
      );
    },
  );
  test(
    'shared manifest change remains hard and leaves import unstaged',
    () async {
      await File(
        '${folder.location}/tandemlog-space.json',
      ).writeAsString('{"v":3,"id":"$otherNamespace"}');
      await expectLater(
        store.commitImport(plan()),
        throwsA(
          isA<FormatException>().having(
            (e) => e is FoodHistoryFailure,
            'module-only',
            false,
          ),
        ),
      );
      expect(folder.writes, 0);
      expect(
        db.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'import cannot select a writer different from protected settings',
    () async {
      await store.close();
      // Fresh Food initialization: no canonical stream or reservation exists.
      db.database.execute('DELETE FROM protected_food_heads WHERE space=?', [
        space,
      ]);
      store = await FoodStore.open(
        folder,
        profile: db,
        installationWriter: otherNamespace,
        space: space,
      );
      await expectLater(store.commitImport(plan()), throwsFormatException);
      expect(folder.writes, 0);
      expect(
        db.database.select(
          "SELECT * FROM profile_metadata WHERE key LIKE 'food.import.%'",
        ),
        isEmpty,
      );
    },
  );
  test(
    'oversized local import metadata is refused before ledger materialization',
    () async {
      db.database.execute(
        "INSERT INTO profile_metadata VALUES (?,CAST(zeroblob(1048576) AS TEXT))",
        ['food.import.v1.$space.index'],
      );
      await expectLater(store.dryRunImport(plan()), throwsFormatException);
      expect(folder.writes, 0);
    },
  );

  test(
    'all metadata ledger loss with surviving initialization refuses new namespace',
    () async {
      await store.commitImport(plan());
      final prior = await bytes();
      db.database.execute(
        "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%'",
      );
      await expectLater(
        store.commitImport(plan(importId: otherNamespace)),
        throwsFormatException,
      );
      expect(await bytes(), prior);
    },
  );
  test(
    'malformed Food cannot mask lost protected import evidence on refresh',
    () async {
      await store.commitImport(plan());
      db.database.execute(
        "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%attempt.%'",
      );
      await File(
        '${folder.location}/${foodLogName(foodWriter(otherNamespace))}',
      ).writeAsString('synthetic malformed Food\n');
      await expectLater(
        store.refresh(),
        throwsA(
          isA<FormatException>().having(
            (e) => e is FoodHistoryFailure,
            'module-only',
            false,
          ),
        ),
      );
    },
  );
  test(
    'malformed Food cannot mask protected settings binding on import',
    () async {
      db.database.execute('UPDATE protected_settings SET raw=?', [
        utf8.encode(jsonEncode({'writer': otherNamespace})),
      ]);
      await File(
        '${folder.location}/${foodLogName(foodWriter(otherNamespace))}',
      ).writeAsString('synthetic malformed Food\n');
      await expectLater(
        store.dryRunImport(plan()),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      await expectLater(
        store.commitImport(plan()),
        throwsA(isA<LocalDatabaseFailure>()),
      );
      expect(folder.writes, 0);
    },
  );

  test(
    'zero-byte attempt all metadata loss refuses original and new namespace',
    () async {
      folder.cut = 0;
      await expectLater(store.commitImport(plan()), throwsStateError);
      final pending = ProfileFoodIntents(
        db,
      ).pending(space, store.writer).map(utf8.decode).toList();
      db.database.execute(
        "DELETE FROM profile_metadata WHERE key LIKE 'food.import.%'",
      );
      for (final p in [plan(), plan(importId: otherNamespace)]) {
        await expectLater(store.commitImport(p), throwsFormatException);
      }
      expect(
        ProfileFoodIntents(
          db,
        ).pending(space, store.writer).map(utf8.decode).toList(),
        pending,
      );
      expect(await bytes(), '');
    },
  );
  test(
    'missing initialization witness with retained ledgers fails closed',
    () async {
      final p = plan();
      await store.commitImport(p);
      final prior = await bytes();
      db.database.execute(
        'DELETE FROM protected_food_import_witnesses WHERE space=?',
        [space],
      );
      await expectLater(store.commitImport(p), throwsFormatException);
      expect(await bytes(), prior);
    },
  );
}
