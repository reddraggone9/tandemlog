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
  final user = const Uuid().v4(), task = const Uuid().v4();
  try {
    await store.command(user, 'user.created', {'name': 'Alex Example'});
    const title = 'Pack for a walk', notes = 'Keep the route notes here.';
    await store.command(task, 'task.createdWithText', {
      'title': title,
      'description': notes,
      'assignee': user,
      'schedule': {
        'dueDate': '2026-10-01',
        'recurrence': 'every week when done',
      },
      'text': {
        'codec': 'yrs-v1',
        'adapter': 1,
        'seeds': {
          'title': sha256.convert(engine.seedText(title).bytes).toString(),
          'description': sha256
              .convert(engine.seedText(notes).bytes)
              .toString(),
        },
      },
    });
    await store.addChecklistItem(task, 'Water bottle');
    await store.addChecklistItem(task, 'Map', notes: 'Printed route');
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
      'task': task,
      'successor': const Uuid().v5(task, 'successor'),
      'files': files,
    }),
  );
  stdout.writeln(root.path);
}
