// QA-only: append a verified baseline to newly generated scalar fixtures.
// Never invoked by the application or used to adopt retained user history.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Supply synthetic folder, NEW seed cache, native library.',
    );
  }
  final folder = LocalLogFolder(Directory(arguments[0]).absolute.path);
  final private = Directory(arguments[1]).absolute;
  final library = File(arguments[2]).absolute;
  if (await private.exists()) throw StateError('Seed cache already exists.');
  if (!await library.exists()) {
    throw StateError('Pinned native library missing.');
  }
  final before = {
    for (final file in await folder.list())
      file.name: await folder.read(file.name),
  };
  if (!before.containsKey('tandemlog-space.json') || before.length < 2) {
    throw StateError('Expected a newly generated scalar fixture.');
  }
  final engine = NativeTextEngine(libraryPath: library.path);
  TaskStore? store;
  try {
    store = await TaskStore.open(folder, private.path, textEngine: engine);
    final count = store.rows.length;
    final baseline = await store.initializeSharedTextForHistoricalFixture();
    if (!store.sharedTextInitialized || store.rows.length != count) {
      throw StateError('Synthetic baseline did not preserve the workload.');
    }
    await store.verifyHistory();
    for (final entry in before.entries) {
      final actual = await folder.read(entry.key);
      if (base64Encode(actual) != base64Encode(entry.value)) {
        throw StateError('Initialization changed original fixture bytes.');
      }
    }
    stdout.writeln(
      jsonEncode({
        'synthetic': true,
        'initialized': true,
        'baseline': baseline.id,
        'native_sha256': sha256.convert(await library.readAsBytes()).toString(),
        'rows': count,
      }),
    );
  } finally {
    await store?.close();
    engine.dispose();
  }
}
