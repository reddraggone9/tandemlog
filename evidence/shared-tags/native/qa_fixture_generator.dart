// Creates a new, synthetic acceptance fixture using production commands.
// Refuses existing destinations; never reads or changes a live user profile.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Supply a NEW fixture directory and native library.');
  }
  final root = Directory(arguments[0]).absolute;
  if (await root.exists()) throw StateError('Fixture destination exists.');
  await root.create(recursive: true);
  final shared = await Directory('${root.path}/shared').create();
  final engine = NativeTextEngine(libraryPath: arguments[1]);
  final store = await TaskStore.open(
    LocalLogFolder(shared.path),
    '${root.path}/seed-private',
    textEngine: engine,
    now: () => DateTime.utc(2026, 10, 2, 12),
  );
  final user = const Uuid().v4();
  final first = const Uuid().v4(), second = const Uuid().v4();
  final completed = const Uuid().v4();
  try {
    await store.command(user, 'user.created', {'name': 'Alex Example'});
    for (final entry in [
      (first, 'Plan weekend', ['Home Office', '#Legacy']),
      (second, 'Review supplies', ['Planning']),
      (completed, 'Finished reference', ['ArchivedOnly']),
    ]) {
      await store.command(entry.$1, 'task.createdWithText', {
        'title': entry.$2,
        'description': '',
        'assignee': user,
        'text': {
          'codec': 'yrs-v1',
          'adapter': 1,
          'seeds': {
            'title': sha256.convert(engine.seedText(entry.$2).bytes).toString(),
            'description': sha256.convert(engine.seedText('').bytes).toString(),
          },
        },
      });
      await store.edit(entry.$1, {}, tags: entry.$3, observedTagRefs: {});
    }
    await store.command(completed, 'task.completed', {});
    await store.verifyHistory();
  } finally {
    await store.close();
    engine.dispose();
  }
  final files = <String, String>{};
  await for (final file in shared.list()) {
    if (file is File) {
      files[file.uri.pathSegments.last] = sha256
          .convert(await file.readAsBytes())
          .toString();
    }
  }
  await File('${root.path}/manifest.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'synthetic': true,
      'user': user,
      'tasks': {
        'plan_weekend': first,
        'review_supplies': second,
        'finished_reference': completed,
      },
      'exact_initial_tags': {
        first: ['#Legacy', 'Home Office'],
        second: ['Planning'],
        completed: ['ArchivedOnly'],
      },
      'files': files,
    }),
  );
  stdout.writeln(root.path);
}
