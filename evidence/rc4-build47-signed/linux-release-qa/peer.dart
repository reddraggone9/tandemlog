import 'dart:convert';
import 'dart:io';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<void> main(List<String> args) async {
  final root = args.single;
  final manifest = jsonDecode(await File('$root/manifest.json').readAsString());
  if (manifest['synthetic'] != true) {
    throw StateError('Only an explicitly synthetic QA fixture is permitted');
  }
  final engine = NativeTextEngine(
    libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
  );
  final store = await TaskStore.open(
    LocalLogFolder('$root/shared'),
    '$root/peer-profile',
    textEngine: engine,
  );
  try {
    final row = store.rows.singleWhere(
      (row) => row['id'] == manifest['tasks']['a'],
    );
    await store.edit(
      row['id'],
      {},
      tags: [...List<String>.from(row['tags']), 'peer'],
      observedTagRefs: Map<String, String>.from(row['tagRefs']),
    );
    await store.verifyHistory();
    stdout.writeln(
      jsonEncode({
        'source': 'production TaskStore edit',
        'id': row['id'],
        'peer_tag': 'peer',
      }),
    );
  } finally {
    await store.close();
    engine.dispose();
  }
}
