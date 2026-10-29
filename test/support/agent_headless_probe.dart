// Synthetic section-9 feasibility probe: no Flutter/display initialization.
import 'dart:convert';
import 'dart:io';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply a new synthetic root.');
  final root = Directory(args.single);
  if (await root.exists()) throw StateError('Synthetic root must not exist.');
  final engine = NativeTextEngine();
  final profile = await LocalProfileDatabase.open('${root.path}/profile');
  UnifiedHistory? history;
  TaskStore? tasks;
  FoodStore? food;
  try {
    await LocalSettings.initialize(profile);
    final settings = LocalSettings(profile.root, profileDatabase: profile);
    await settings.load();
    await Directory('${root.path}/workspace').create();
    history = await UnifiedHistory.create(
      LocalLogFolder('${root.path}/workspace'),
      profile: profile,
      writer: settings.writer,
      textEngine: engine,
    );
    tasks = await TaskStore.openUnified(history);
    await tasks.initializeSharedText();
    food = await FoodStore.openUnified(history);
    stdout.writeln(
      jsonEncode({
        'headless': true,
        'nativeText': engine.seedText('Synthetic probe').encoded.isNotEmpty,
        'writer': settings.writer,
        'foodContainers': food.state.containers.length,
        'dart': Platform.version.split(' ').first,
      }),
    );
  } finally {
    await food?.close();
    await tasks?.close();
    await history?.close();
    await profile.close();
    engine.dispose();
  }
}
