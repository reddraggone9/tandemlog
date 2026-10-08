import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

class TimingLogFolder extends LocalLogFolder {
  TimingLogFolder(super.path);
  int appendMicroseconds = 0;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final watch = Stopwatch()..start();
    try {
      await super.append(name, bytes);
    } finally {
      appendMicroseconds += watch.elapsedMicroseconds;
    }
  }
}

class CountingEngine extends NativeTextEngine {
  CountingEngine({super.libraryPath});
  int creations = 0, seedCalls = 0, inspections = 0;
  int restorations = 0;
  int materializerCreations = 0;
  @override
  NativeTextMaterializer createMaterializer({
    required NativeTextState seed,
    required NativeTextLimits limits,
  }) {
    materializerCreations++;
    return super.createMaterializer(seed: seed, limits: limits);
  }

  @override
  NativeTextDocument createDocument({
    required int actorClientId,
    required NativeTextLimits limits,
    NativeTextUpdate? seed,
  }) {
    creations++;
    return super.createDocument(
      actorClientId: actorClientId,
      limits: limits,
      seed: seed,
    );
  }

  @override
  NativeTextDocument restoreDocument({
    required int actorClientId,
    required NativeTextLimits limits,
    required NativeTextCheckpoint checkpoint,
  }) {
    restorations++;
    return super.restoreDocument(
      actorClientId: actorClientId,
      limits: limits,
      checkpoint: checkpoint,
    );
  }

  @override
  NativeTextUpdate seedText(String text) {
    seedCalls++;
    return super.seedText(text);
  }

  @override
  List<int> inspect(NativeTextUpdate update, {int admissionUnits = 100000}) {
    inspections++;
    return super.inspect(update, admissionUnits: admissionUnits);
  }
}

Future<void> editChild(TaskStore store, String id, int generation) async {
  final capture = await store.captureTaskText(id);
  final saves = <String, NativeTextPreparedSave>{};
  final changes = <String, dynamic>{};
  try {
    for (final entry in {
      'title': 'Review plan $generation',
      'description': 'Synthetic note $generation',
    }.entries) {
      final field = capture.fields[entry.key]!;
      final draft = field.document.captureDraft(actorClientId: field.actor)
        ..replaceText(entry.value);
      final prepared = draft.prepareSave();
      saves[entry.key] = prepared;
      changes[entry.key] = {
        'context': field.context,
        'allocation': field.allocation,
        'actor': field.actor,
        'update': prepared.update.encoded,
      };
    }
    await store.editNativeTask(id, changes);
    for (final prepared in saves.values) {
      prepared.commit(receiptUpdate: prepared.update);
    }
  } finally {
    store.releaseTextCapture(capture);
  }
}

// Private bounded measurement of production domain/storage/native code.
// No Flutter UI, real profile, public benchmark fixture, or history rewrite.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('tandemlog-aot-cost-');
  final folder = await Directory('${root.path}/shared').create();
  final logFolder = TimingLogFolder(folder.path);
  final profile = '${root.path}/profile';
  var engine = CountingEngine(
    libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
  );
  final generations = int.parse(
    Platform.environment['PROBE_GENERATIONS'] ?? '80',
  );
  final edits = Platform.environment['PROBE_EDITS'] == 'yes';
  final editEvery = int.parse(Platform.environment['PROBE_EDIT_EVERY'] ?? '1');
  final otherTasks = int.parse(
    Platform.environment['PROBE_OTHER_TASKS'] ?? '0',
  );
  final recurrence =
      Platform.environment['PROBE_RECURRENCE'] ?? 'every day when done';
  final start = DateTime.parse(
    Platform.environment['PROBE_START_DATE'] ?? '2026-10-01',
  );
  final daySpacing = int.parse(
    Platform.environment['PROBE_DAY_SPACING'] ?? '1',
  );
  if (editEvery < 1 || otherTasks < 0 || daySpacing < 1)
    throw ArgumentError('Invalid fixture parameters');
  final report = Platform.environment['PROBE_REPORT']!;
  final initialRss = ProcessInfo.currentRss;
  TaskStore? store;
  final samples = <Map<String, Object>>[];
  final wall = Stopwatch()..start();
  try {
    store = await TaskStore.open(logFolder, profile, textEngine: engine);
    final user = const Uuid().v4();
    var id = const Uuid().v4();
    final lineageIds = <String>{id};
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    for (var index = 0; index < otherTasks; index++) {
      final title = 'Independent active task $index';
      const description = 'Synthetic independent work';
      await store.command(const Uuid().v4(), 'task.createdWithText', {
        'title': title,
        'description': description,
        'assignee': user,
        'schedule': <String, dynamic>{},
        'text': {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText(title).bytes).toString(),
            'description': sha256
                .convert(engine.seedText(description).bytes)
                .toString(),
          },
        },
      });
    }
    await store.command(id, 'task.createdWithText', {
      'title': 'Review plan',
      'description': 'Synthetic cost probe',
      'assignee': user,
      'schedule': {
        'dueDate': start.toIso8601String().split('T').first,
        'recurrence': recurrence,
      },
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256
              .convert(engine.seedText('Review plan').bytes)
              .toString(),
          'description': sha256
              .convert(engine.seedText('Synthetic cost probe').bytes)
              .toString(),
        },
      },
    });
    for (var generation = 1; generation <= generations; generation++) {
      if (edits && (generation - 1) % editEvery == 0)
        await editChild(store, id, generation);
      final creationsBefore = engine.creations,
          restorationsBefore = engine.restorations,
          inspectionsBefore = engine.inspections;
      final watch = Stopwatch()..start();
      final priorAppendUs = logFolder.appendMicroseconds;
      var preparedUs = 0;
      await store.complete(
        id,
        completionDay: start.add(Duration(days: (generation - 1) * daySpacing)),
        onPrepared: (_) => preparedUs = watch.elapsedMicroseconds,
      );
      id = const Uuid().v5(id, 'successor');
      lineageIds.add(id);
      watch.stop();
      samples.add({
        'generation': generation,
        'completion_ms': watch.elapsedMicroseconds / 1000,
        'before_receipt_ms': preparedUs / 1000,
        'after_receipt_ms': (watch.elapsedMicroseconds - preparedUs) / 1000,
        'canonical_append_ms':
            (logFolder.appendMicroseconds - priorAppendUs) / 1000,
        'native_creations': engine.creations - creationsBefore,
        'native_restore_calls': engine.restorations - restorationsBefore,
        'inspections': engine.inspections - inspectionsBefore,
      });
      if (watch.elapsedMilliseconds > 2000 ||
          wall.elapsedMilliseconds > 180000) {
        break;
      }
    }
    final snapshot = jsonEncode(store.taskSnapshot);
    final cachePath =
        store.db.select('PRAGMA database_list').single['file'] as String;
    final count = store.db
        .select('SELECT COUNT(*) AS n FROM events')
        .single['n'];
    final canonicalBefore = <String, String>{};
    await for (final file in folder.list()) {
      if (file is File) {
        canonicalBefore[file.path] = sha256
            .convert(await file.readAsBytes())
            .toString();
      }
    }
    final nativeBytes = store.db
        .select('SELECT SUM(length(state)) AS n FROM text_fields')
        .single['n'];
    final frontierBytes = store.db
        .select('SELECT SUM(length(frontier)) AS n FROM text_fields')
        .single['n'];
    final lineageNativeBytes = store.db
        .select('SELECT entity,length(state) AS n FROM text_fields')
        .where((row) => lineageIds.contains(row['entity']))
        .fold<int>(0, (total, row) => total + (row['n'] as int));
    final sqlBytes =
        (store.db.select('PRAGMA page_count').single['page_count'] as int) *
        (store.db.select('PRAGMA page_size').single['page_size'] as int);
    var canonicalBytes = 0;
    await for (final file in folder.list()) {
      if (file is File) canonicalBytes += await file.length();
    }
    final beforeCloseRss = ProcessInfo.currentRss, peakRss = ProcessInfo.maxRss;
    await store.close();
    store = null;
    final warm = Stopwatch()..start();
    store = await TaskStore.open(logFolder, profile, textEngine: engine);
    warm.stop();
    if (jsonEncode(store.taskSnapshot) != snapshot || store.readFiles != 0) {
      throw StateError('Warm cache projection or zero-read invariant failed');
    }
    await store.close();
    store = null;
    // A fresh private profile simulates cache loss without deleting any files.
    final coldProfile = '${root.path}/cold-profile';
    final priorCreations = engine.creations,
        priorRestorations = engine.restorations,
        priorSeedCalls = engine.seedCalls,
        priorInspections = engine.inspections,
        priorMaterializers = engine.materializerCreations;
    engine.dispose();
    engine = CountingEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    final cold = Stopwatch()..start();
    store = await TaskStore.open(logFolder, coldProfile, textEngine: engine);
    cold.stop();
    if (jsonEncode(store.taskSnapshot) != snapshot) {
      throw StateError('Rebuild projection mismatch');
    }
    await for (final file in folder.list()) {
      if (file is File &&
          canonicalBefore.containsKey(file.path) &&
          canonicalBefore[file.path] !=
              sha256.convert(await file.readAsBytes()).toString()) {
        throw StateError('Canonical file mutated during cache probe');
      }
    }
    final result = {
      'source': const String.fromEnvironment('PROBE_SOURCE'),
      'generations_requested': generations,
      'edits_enabled': edits,
      'edits_each_generation': edits && editEvery == 1,
      'edit_every_generations': editEvery,
      'independent_active_tasks': otherTasks,
      'recurrence': recurrence,
      'synthetic_start_day': start.toIso8601String().split('T').first,
      'completion_day_spacing': daySpacing,
      'mode':
          'Dart AOT executable; actual production TaskStore/native FFI; no Flutter UI or process-to-ready timing',
      'tasks': samples.length + 1 + otherTasks,
      'lineage_tasks': samples.length + 1,
      'history_events': count,
      'samples': samples,
      'warm_open_ms': warm.elapsedMicroseconds / 1000,
      'warm_canonical_reads': 0,
      'cache_rebuild_ms': cold.elapsedMicroseconds / 1000,
      'cache_rebuild_reads': store.readFiles,
      'wall_ms': wall.elapsedMilliseconds,
      'canonical_unchanged': true,
      'cache_states_identical': true,
      'canonical_bytes': canonicalBytes,
      'sqlite_bytes': sqlBytes,
      'native_state_blob_bytes': nativeBytes,
      'lineage_native_state_blob_bytes': lineageNativeBytes,
      'frontier_json_bytes': frontierBytes,
      'rss_initial_bytes': initialRss,
      'rss_before_close_bytes': beforeCloseRss,
      'rss_peak_before_close_bytes': peakRss,
      'rss_peak_bytes': ProcessInfo.maxRss,
      'fresh_engine_for_rebuild': true,
      'native_document_creations': priorCreations + engine.creations,
      'native_restore_document_calls': priorRestorations + engine.restorations,
      'document_counter_scope':
          'createDocument and restoreDocument calls counted separately; materializer creation has its own counter',
      'native_seed_calls': priorSeedCalls + engine.seedCalls,
      'native_inspections': priorInspections + engine.inspections,
      'native_history_materializers':
          priorMaterializers + engine.materializerCreations,
      'cold_history_materializers': engine.materializerCreations,
      'preserved_fixture_directory': root.path,
      'original_cache_path': cachePath,
    };
    await File(
      report,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
    stdout.writeln(jsonEncode(result));
  } finally {
    await store?.close();
    engine.dispose();
    // Retain every fresh synthetic file for diagnostics.
  }
}
