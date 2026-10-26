// Public synthetic benchmark data. Never reads a user workspace or profile.
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/checklist_completion_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';

// New prospective timestamp-aware fixture contract; old sealed v1 evidence stays immutable.
const fixtureSchemaVersion = 2;
const _namespace = 'a5c957b6-29ca-43e5-8bee-0c5c4852dced';
String benchmarkId(String value) => const Uuid().v5(_namespace, value);
void fixtureCheck(bool value, String message) {
  if (!value) throw StateError(message);
}

({int baseRecords, String growthKind}) parseSyntheticFixtureSpec(String value) {
  final parts = value.split(':');
  final kind = parts.length == 1 ? 'task' : parts.first;
  final count = int.tryParse(parts.last);
  fixtureCheck(
    count != null &&
        ((parts.length == 1 && [60, 1320, 2640].contains(count)) ||
            (parts.length == 2 && kind == 'food' && count == 2640)),
    'Unknown versioned fixture specification',
  );
  return (baseRecords: count!, growthKind: kind);
}

Future<Map<String, dynamic>> buildSyntheticFixture(
  Directory root,
  int baseRecords, {
  required String nativeLibrary,
  String growthKind = 'task',
}) async {
  fixtureCheck(
    (growthKind == 'task' && [60, 1320, 2640].contains(baseRecords)) ||
        (growthKind == 'food' && baseRecords == 2640),
    'Unknown versioned fixture size',
  );
  fixtureCheck(!await root.exists(), 'Refuse existing synthetic fixture');
  await root.create(recursive: true);
  final shared = await Directory('${root.path}/workspace').create();
  final initialRecords = baseRecords == 60 ? 60 : 1320,
      baseIdentity = baseRecords == 60 ? 60 : 1320;
  final space = benchmarkId('space:$baseIdentity'),
      epoch = benchmarkId('epoch:$baseIdentity');
  final writers = List.generate(
    3,
    (i) => benchmarkId('writer:$baseIdentity:$i'),
  );
  final users = List.generate(3, (i) => benchmarkId('user:$baseIdentity:$i'));
  final foodWriters = List.generate(
    3,
    (i) => benchmarkId('food-writer:$baseIdentity:$i'),
  );
  final physicalSeq = List.filled(3, 0),
      taskSeq = List.filled(3, 0),
      foodSeq = List.filled(3, 0);
  final physicalHead = [
    for (final w in writers) unifiedGenesis(space, epoch, w),
  ];
  final taskHead = [for (final w in writers) eventGenesisHash(space, w)];
  final foodHead = [for (final w in foodWriters) eventGenesisHash(space, w)];
  final buffers = List.generate(3, (_) => StringBuffer()),
      taskIds = List.generate(3, (_) => <String>[]);
  final baseNotes = <String, String>{};
  final foodSeeds = List.generate(
    3,
    (_) => <({String id, String creation, FoodDetails details})>[],
  );
  for (var i = 0; i < initialRecords; i++) {
    final n = i % 3,
        w = writers[n],
        clock = EventClock(BigInt.from(1000000 + i));
    UnifiedEffect effect;
    if (i >= 3 && i % 4 == 0) {
      final seq = ++foodSeq[n], id = benchmarkId('food:$baseIdentity:$i');
      final operation = FoodOperation(
        id: '${foodWriters[n]}:$seq',
        order: clock.value.toInt(),
        action: FoodAction.add,
        targets: [id],
        details: FoodDetails(
          name: 'Benchmark food $i',
          brand: 'Benchmark brand ${i % 5}',
          location: 'Benchmark shelf ${i % 4}',
          expiry: i % 3 == 0 ? null : '2026-11-10',
          retention: i % 3 == 0 ? 'Benchmark retained' : '',
        ),
        createdAt: '2026-10-22T00:00:00Z',
      );
      final record = FoodRecord(
        space: space,
        writer: foodWriters[n],
        sequence: seq,
        clock: clock,
        operation: operation,
        previousHash: foodHead[n],
        attributedWriter: w,
      );
      foodHead[n] = record.integrityHash;
      foodSeeds[n].add((
        id: id,
        creation: operation.id,
        details: operation.details!,
      ));
      effect = UnifiedEffect('history.food', record.encode());
    } else {
      final seq = ++taskSeq[n];
      String entity, type;
      Map<String, dynamic> data;
      if (i < 3) {
        entity = users[n];
        type = 'user.created';
        data = {'name': 'Benchmark user $n'};
      } else if (taskIds[n].isNotEmpty && i % 5 == 0) {
        entity = taskIds[n][i % taskIds[n].length];
        type = 'task.edited';
        data = {'description': 'Benchmark historical Notes $i'};
      } else {
        entity = benchmarkId('task:$baseIdentity:$i');
        type = 'task.created';
        data = {
          'title': 'Benchmark historical task $i',
          'description': 'Benchmark Notes $i',
          'assignee': users[n],
        };
        taskIds[n].add(entity);
      }
      if (type.startsWith('task.') && data['description'] is String) {
        baseNotes[entity] = data['description'] as String;
      }
      final event = LogEvent.decode(
        LogEvent(
          space,
          w,
          seq,
          clock,
          entity,
          type,
          data,
        ).encode(previousHash: taskHead[n]),
      );
      taskHead[n] = event.integrityHash!;
      effect = UnifiedEffect('history.task', event.canonicalRaw!);
    }
    final record = UnifiedRecord(
      space: space,
      epoch: epoch,
      writer: w,
      sequence: ++physicalSeq[n],
      clock: clock,
      previousHash: physicalHead[n],
      effect: effect,
    );
    physicalHead[n] = record.hash;
    buffers[n].writeln(record.encode());
  }
  final initialPrefixes = [for (final b in buffers) utf8.encode(b.toString())];
  final initialTaskEffects = taskSeq.reduce((a, b) => a + b),
      initialFoodEffects = foodSeq.reduce((a, b) => a + b);
  if (growthKind == 'task') {
    // Both paired fixtures have identical IDs, current values and initial1320
    // records. Extra history alternates a Notes edit and its exact value restore.
    for (var j = 0; j < baseRecords - initialRecords; j++) {
      final n = j % 3,
          w = writers[n],
          entity = taskIds[n][(j ~/ 6) % taskIds[n].length],
          seq = ++taskSeq[n],
          clock = EventClock(BigInt.from(1000000 + initialRecords + j));
      final notes = j % 6 < 3
          ? 'Benchmark historical growth ${j ~/ 6}'
          : baseNotes[entity]!;
      final event = LogEvent.decode(
        LogEvent(space, w, seq, clock, entity, 'task.edited', {
          'description': notes,
        }).encode(previousHash: taskHead[n]),
      );
      taskHead[n] = event.integrityHash!;
      final record = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: w,
        sequence: ++physicalSeq[n],
        clock: clock,
        previousHash: physicalHead[n],
        effect: UnifiedEffect('history.task', event.canonicalRaw!),
      );
      physicalHead[n] = record.hash;
      buffers[n].writeln(record.encode());
    }
  } else {
    // The SAME initial canonical prefixes receive only Food detail edits.
    // Each edit/restore pair targets the same existing creation; contents,
    // deletion references, timestamps and all current values remain unchanged.
    for (var j = 0; j < baseRecords - initialRecords; j++) {
      final n = j % 3, w = writers[n];
      final seed = foodSeeds[n][(j ~/ 6) % foodSeeds[n].length];
      final clock = EventClock(BigInt.from(1000000 + initialRecords + j));
      final details = FoodDetails.fromJson({
        ...seed.details.toJson(),
        'brand': j % 6 < 3
            ? 'Benchmark Food growth ${j ~/ 6}'
            : seed.details.brand,
      });
      final record = FoodRecord(
        space: space,
        writer: foodWriters[n],
        sequence: ++foodSeq[n],
        clock: clock,
        previousHash: foodHead[n],
        attributedWriter: w,
        operation: FoodOperation(
          id: '${foodWriters[n]}:${foodSeq[n]}',
          order: clock.value.toInt(),
          action: FoodAction.edit,
          targets: [seed.id],
          details: details,
          fields: ['brand'],
        ),
        createdWith: {seed.id: seed.creation},
      );
      foodHead[n] = record.integrityHash;
      final outer = UnifiedRecord(
        space: space,
        epoch: epoch,
        writer: w,
        sequence: ++physicalSeq[n],
        clock: clock,
        previousHash: physicalHead[n],
        effect: UnifiedEffect('history.food', record.encode()),
      );
      physicalHead[n] = outer.hash;
      buffers[n].writeln(outer.encode());
    }
  }
  final growthTaskEffects =
          taskSeq.reduce((a, b) => a + b) - initialTaskEffects,
      growthFoodEffects = foodSeq.reduce((a, b) => a + b) - initialFoodEffects;
  fixtureCheck(
    growthTaskEffects + growthFoodEffects == baseRecords - initialRecords &&
        (growthKind == 'food'
            ? growthTaskEffects == 0
            : growthFoodEffects == 0),
    'Synthetic growth changed the wrong module',
  );
  final bytes = [for (final b in buffers) utf8.encode(b.toString())];
  final manifest = UnifiedManifest(
    space,
    epoch,
    bytesDigest(
      utf8.encode(
        growthKind == 'task'
            ? 'public-benchmark-v2:$baseRecords'
            : 'public-benchmark-v2:food:$baseRecords',
      ),
    ),
    {
      for (var i = 0; i < 3; i++)
        writers[i]: {
          'count': physicalSeq[i],
          'head': physicalHead[i],
          'digest': bytesDigest(bytes[i]),
        },
    },
    {
      for (var i = 0; i < 3; i++) ...{
        writers[i]: writers[i],
        foodWriters[i]: writers[i],
      },
    },
  );
  for (var i = 0; i < 3; i++) {
    final f = File('${shared.path}/${unifiedLogName(writers[i])}');
    await f.create(exclusive: true);
    await f.writeAsBytes(bytes[i], flush: true);
  }
  final mf = File('${shared.path}/tandemlog-space.json');
  await mf.create(exclusive: true);
  await mf.writeAsString(manifest.encode(), flush: true);
  final engine = NativeTextEngine(libraryPath: nativeLibrary);
  LocalProfileDatabase? profile;
  UnifiedHistory? history;
  TaskStore? store;
  FoodStore? food;
  try {
    profile = await LocalProfileDatabase.open('${root.path}/producer-profile');
    profile.transaction(
      () => profile!.database.execute(
        'INSERT INTO protected_settings VALUES (1,?,?)',
        [
          writers.first,
          utf8.encode(
            jsonEncode({
              'writer': writers.first,
              'folder': shared.path,
              'user': users.first,
              'appearance': 'system',
              'lastSection': 'tasks',
            }),
          ),
        ],
      ),
    );
    history = await UnifiedHistory.open(
      LocalLogFolder(shared.path),
      profile: profile,
      writer: writers.first,
      textEngine: engine,
      now: () => DateTime.utc(2026, 10, 22),
    );
    store = await TaskStore.openUnified(history);
    await store.initializeSharedText();
    final parent = benchmarkId('native-parent:$baseIdentity');
    fixtureCheck(
      (await store.createTasks({
        parent: 'Benchmark native recurring parent',
      }, users.first)).succeeded,
      'Native fixture creation failed',
    );
    await store.edit(
      parent,
      {
        'schedule': {'dueDate': '2026-10-22', 'recurrence': 'every day'},
      },
      tags: [],
      observedTagRefs: {},
    );
    final item = benchmarkId('native-item:$baseIdentity');
    await store.addChecklistItem(
      parent,
      'Benchmark native item',
      notes: 'Benchmark item Notes',
      id: item,
    );
    await ChecklistCompletionCommand(store).complete(
      parent,
      completionInstant: DateTime.utc(2026, 10, 22, 12),
      localZoneId: 'UTC',
      confirmUnfinished: (_) async => true,
    );
    fixtureCheck(
      history.snapshot.records.length > baseRecords && store.rows.length > 10,
      'Synthetic fixture shape not admitted',
    );
    food = await FoodStore.openUnified(history);
    final stateDigest = bytesDigest(
      utf8.encode(
        jsonEncode({
          'tasks': store.rows,
          'food': food.state.containers.map((c) => c.toJson()).toList(),
        }),
      ),
    );
    final summary = <String, dynamic>{
      'scalingShape': 'history-only; identical current state',
      'initialHistoricalRecords': initialRecords,
      'growthHistoricalRecords': baseRecords - initialRecords,
      'growthKind': baseRecords == initialRecords ? 'none' : growthKind,
      'initialTaskEffects': initialTaskEffects,
      'initialFoodEffects': initialFoodEffects,
      'growthTaskEffects': growthTaskEffects,
      'growthFoodEffects': growthFoodEffects,
      'currentStateSHA256': stateDigest,
      'foodContainers': food.state.containers.length,
      'initialPrefixSHA256': {
        for (var i = 0; i < 3; i++)
          unifiedLogName(writers[i]): bytesDigest(initialPrefixes[i]),
      },
      'schemaVersion': fixtureSchemaVersion,
      'syntheticOnly': true,
      'baseHistoricalRecords': baseRecords,
      'actualPhysicalRecords': history.snapshot.records.length,
      'taskEffects': history.snapshot.tasks.length,
      'foodEffects': history.snapshot.records
          .expand((r) => r.effects)
          .where((e) => e.food != null)
          .length,
      'taskRows': store.rows.length,
      'writer': writers.first,
      'user': users.first,
      'workspace': shared.absolute.path,
    };
    await food.close();
    food = null;
    await store.close();
    store = null;
    await history.close();
    history = null;
    await profile.close();
    profile = null;
    summary['files'] = {
      for (final f
          in await shared.list().where((e) => e is File).cast<File>().toList())
        f.uri.pathSegments.last: bytesDigest(await f.readAsBytes()),
    };
    final out = File('${root.path}/fixture.json');
    await out.create(exclusive: true);
    await out.writeAsString(jsonEncode(summary), flush: true);
    return summary;
  } finally {
    await food?.close();
    await store?.close();
    await history?.close();
    await profile?.close();
    engine.dispose();
  }
}
