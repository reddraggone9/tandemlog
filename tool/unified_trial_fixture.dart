import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_trial.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/text/native_text_engine.dart';

/// Creates only fresh owned synthetic temp data, never reads an existing
/// inventory/workspace/profile. Optional argument names the reviewed FFI library.
Future<void> main(List<String> args) async {
  if (args.length > 1) {
    throw ArgumentError('Expected optional native library path.');
  }
  final engine = NativeTextEngine(
    libraryPath: args.isEmpty ? null : args.single,
  );
  final seedRoot = await Directory.systemTemp.createTemp(
    'tandemlog-unified-synthetic-source-',
  );
  final folder = LocalLogFolder(
    (await Directory('${seedRoot.path}/shared').create()).path,
  );
  final profile = await LocalProfileDatabase.open('${seedRoot.path}/profile');
  await LocalProfileMigration(profile).run();
  final settings = LocalSettings(profile.root, profileDatabase: profile);
  await settings.load();
  final writer = settings.writer, user = const Uuid().v4();
  final tasks = await TaskStore.open(
    folder,
    profile.root,
    profileDatabase: profile,
    writerIdentity: writer,
    textEngine: engine,
    initializeNewWorkspaceText: true,
  );
  final food = await FoodStore.open(
    folder,
    profile: profile,
    installationWriter: writer,
    space: tasks.space,
  );
  String space = tasks.space;
  try {
    await tasks.command(user, 'user.created', {'name': 'Alex Example'});
    for (final title in [
      'Plan the weekend',
      'Collect groceries',
      'Water the plants',
      'Review project notes',
      'Call the workshop',
    ]) {
      await tasks.command(const Uuid().v4(), 'task.createdWithText', {
        'title': title,
        'description': 'Synthetic native trial',
        'assignee': user,
        'text': {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText(title).bytes).toString(),
            'description': sha256
                .convert(engine.seedText('Synthetic native trial').bytes)
                .toString(),
          },
        },
      });
    }
    await food.add(
      const FoodDetails(
        name: 'Rice',
        brand: 'Example pantry',
        location: 'Shelf',
      ),
      2,
    );
    await food.add(const FoodDetails(name: 'Beans', location: 'Cupboard'), 1);
    final rice = food.state.containers.firstWhere(
      (c) => c.details.name == 'Rice',
    );
    await food.remove([rice.id]);
    await food.undoOperations(food.lastPreparedRecords);
  } finally {
    await food.close();
    await tasks.close();
    await profile.close();
  }
  final sources = <String, List<int>>{};
  for (final info in await folder.list()) {
    if (info.name.endsWith('.jsonl') || info.name.endsWith('.foodlog')) {
      sources[info.name] = await folder.read(info.name);
    }
  }
  final trial = await UnifiedTrial.createSynthetic(
    space: space,
    owners: {writer},
    participants: {writer},
    sources: sources,
  );
  final participant = Directory(trial.profileRoot(writer));
  await participant.create();
  await for (final file in Directory('${seedRoot.path}/profile').list()) {
    if (file is File) {
      await file.copy('${participant.path}/${file.uri.pathSegments.last}');
    }
  }
  try {
    await trial.acknowledgeInput(writer, textEngine: engine);
    await trial.stage();
    await trial.acknowledgeOutput(writer, textEngine: engine);
    await trial.activate(textEngine: engine);
    await trial.retireSyntheticSources();
    final p = await trial.openParticipant(writer);
    try {
      final preferences = LocalSettings(p.root, profileDatabase: p);
      await preferences.load();
      preferences.folder = trial.folder.location;
      preferences.user = user;
      preferences.appearance = Appearance.light;
      await preferences.save();
    } finally {
      await p.close();
    }
    stdout.writeln(
      jsonEncode({
        'trialRoot': trial.root.path,
        'profile': participant.path,
        'shared': trial.folder.location,
        'space': space,
        'writer': writer,
        'user': user,
        'phase': trial.phase,
        'sourceDigest': trial.plan.sourceDigest,
        'outputDigest': trial.outputDigest,
        'seedEvidence': seedRoot.path,
        'syntheticOnly': true,
      }),
    );
  } finally {
    await trial.close();
    engine.dispose();
  }
}
