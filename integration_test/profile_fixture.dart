import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'dart:convert';
import 'dart:io';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

/// Seed only a disposable current profile; never exercise retired file imports.
/// Enroll ordinary real-file fixtures before tests seal a no-action baseline.
Future<void> seedNativeProfile(String root, Map<String, dynamic> values) async {
  final profile = await LocalProfileDatabase.open(root);
  try {
    await LocalSettings.initialize(profile);
    final current = LocalSettings.protectedValues(profile)..addAll(values);
    profile.transaction(
      () => profile.database.execute(
        'UPDATE protected_settings SET writer=?,raw=? WHERE singleton=1',
        [current['writer'], utf8.encode(jsonEncode(current))],
      ),
    );
    LocalSettings.protectedValues(profile);
    final folder = current['folder'] as String?;
    if (folder != null && await File('$folder/tandemlog-space.json').exists()) {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          LocalLogFolder(folder),
          root,
          profileDatabase: profile,
          textEngine: engine,
        );
      } finally {
        await store?.close();
        engine.dispose();
      }
    }
  } finally {
    await profile.close();
  }
}

Iterable<LogEvent> taskEffectsFromAction(String raw) =>
    UnifiedRecord.decode(raw).effects.map((e) => e.task).whereType<LogEvent>();

Iterable<FoodRecord> foodEffectsFromAction(String raw) => UnifiedRecord.decode(
  raw,
).effects.map((e) => e.food).whereType<FoodRecord>();

Iterable<Map<String, dynamic>> taskEffectMapsFromAction(String raw) =>
    taskEffectsFromAction(raw).map(
      (e) => {'id': e.id, 'type': e.type, 'entity': e.entity, 'data': e.data},
    );
