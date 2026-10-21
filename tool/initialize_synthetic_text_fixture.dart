// QA-only: build a new current-format workload in an empty synthetic folder.
// Never invoked by the application or used to adopt retained user history.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Supply empty synthetic folder, NEW seed cache, native library.',
    );
  }
  final folder = LocalLogFolder(Directory(arguments[0]).absolute.path);
  final private = Directory(arguments[1]).absolute;
  final workspace = private.parent;
  final library = File(arguments[2]).absolute;
  if (await private.exists()) throw StateError('Seed cache already exists.');
  if (!await library.exists() || (await folder.list()).isNotEmpty) {
    throw StateError('Pinned library and empty synthetic folder are required.');
  }
  final spec =
      jsonDecode(
            await File(
              '${workspace.path}/synthetic-workload.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  if (spec['synthetic'] != true || spec['version'] != 1) {
    throw StateError('Expected explicit synthetic workload.');
  }
  final writer = spec['writer'] as String, user = spec['user'] as String;
  final tasks = (spec['tasks'] as List).cast<Map<String, dynamic>>();
  if (!isCanonicalId(writer) || !isCanonicalId(user) || tasks.length > 10000) {
    throw StateError('Invalid synthetic identities/budget.');
  }
  final profilePath = Directory(spec['profile'] as String).absolute;
  final relative = profilePath.uri.path.substring(workspace.uri.path.length);
  if (!profilePath.uri.path.startsWith(workspace.uri.path) ||
      relative.isEmpty ||
      relative.split('/').contains('..')) {
    throw StateError(
      'Measured profile must be inside its synthetic workspace.',
    );
  }
  if (await profilePath.exists() && !(await profilePath.list().isEmpty)) {
    throw StateError('Measured profile is not empty.');
  }
  final engine = NativeTextEngine(libraryPath: library.path);
  TaskStore? store;
  try {
    store = await TaskStore.open(
      folder,
      private.path,
      writerIdentity: writer,
      textEngine: engine,
    );
    await store.command(user, 'user.created', {
      'name': spec['userName'] as String,
    });
    // Preserve the scalar workload, then construct its native baseline through
    // current production APIs. Chunking bounds seed-generation memory only.
    for (var offset = 0; offset < tasks.length; offset += 500) {
      final chunk = tasks.skip(offset).take(500);
      await store.unified!.appendAtomic([
        for (final task in chunk)
          (sequence, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              store!.space,
              writer,
              sequence,
              clock,
              task['id'] as String,
              'task.created',
              {
                'title': task['title'],
                'description': task['description'],
                'assignee': user,
              },
            ).encode(previousHash: head),
          ),
      ]);
    }
    final baseline = await store.initializeSharedText();
    await store.verifyHistory();
    final count = store.rows.length;
    if (!store.sharedTextInitialized || count != tasks.length + 1) {
      throw StateError('Synthetic workload admission failed.');
    }
    await store.close();
    store = null;
    // Preferences only: deliberately leave all projections/observations cold.
    final profile = await LocalProfileDatabase.open(profilePath.path);
    final settings = utf8.encode(
      jsonEncode({
        'writer': writer,
        'folder': folder.location,
        'user': user,
        'appearance': 'system',
      }),
    );
    try {
      profile.transaction(
        () => profile.database.execute(
          'INSERT INTO protected_settings VALUES(1,?,?)',
          [writer, settings],
        ),
      );
    } finally {
      await profile.close();
    }
    stdout.writeln(
      jsonEncode({
        'synthetic': true,
        'initialized': true,
        'format': 'app-action-v5',
        'baseline': baseline.id,
        'writer': writer,
        'user': user,
        'rows': count,
        'settings_sha256': sha256.convert(settings).toString(),
        'native_sha256': sha256.convert(await library.readAsBytes()).toString(),
      }),
    );
  } finally {
    await store?.close();
    engine.dispose();
  }
}
