import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../lib/storage/log_folder.dart';
import '../lib/storage/task_store.dart';
import '../lib/text/native_text_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1)
    throw ArgumentError('Provide a new synthetic fixture directory.');
  final root = Directory(args.single);
  if (await root.exists())
    throw ArgumentError('Preserve existing fixtures; use a new directory.');
  final shared = await Directory('${root.path}/shared').create(recursive: true);
  final engine = NativeTextEngine(
    libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
  );
  final store = await TaskStore.open(
    LocalLogFolder(shared.path),
    '${root.path}/creator-profile',
    textEngine: engine,
  );
  final user = const Uuid().v4(), a = const Uuid().v4(), b = const Uuid().v4();
  try {
    await store.command(user, 'user.created', {'name': 'Synthetic rank demo'});
    await store.createTasks({a: 'Earlier A', b: 'Earlier B'}, user);
    for (final id in [a, b]) {
      await store.command(id, 'task.edited', {
        'description': 'Already organized',
      });
    }
    await store.moveBefore(b, a);
    final files = <String, String>{};
    await for (final file in shared.list()) {
      if (file is File)
        files[file.uri.pathSegments.last] = sha256
            .convert(await file.readAsBytes())
            .toString();
    }
    await File('${root.path}/manifest.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'synthetic': true,
        'user': user,
        'tasks': {'a': a, 'b': b},
        'initialManualOrder': [b, a],
        'sha256': files,
      })}\n',
    );
  } finally {
    await store.close();
    engine.dispose();
  }
}
