import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

void main() {
  for (final cacheState in ['current', 'damaged', 'pre-completion-order']) {
    final damaged = cacheState == 'damaged';
    final oldGeneration = cacheState == 'pre-completion-order';
    test('Task proof is guarded by row triggers; cache=$cacheState', () async {
      final root = await Directory.systemTemp.createTemp('task-proof-bytes-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final profilePath = '${root.path}/profile';
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(folder, profilePath, textEngine: engine);
        final user = const Uuid().v4(), task = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'É😀\n"\\'});
        expect(
          (await store.createTasks({task: 'Task 😀\t"\\'}, user)).succeeded,
          isTrue,
        );
        final tables = store.tables;
        final expected = jsonEncode(store.rows);
        final bytes = await folder.read('${store.writer}.applog');
        await store.close();
        store = null;
        final profile = await LocalProfileDatabase.open(profilePath);
        try {
          final proofRow = profile.database
              .select(
                "SELECT key,value FROM profile_metadata WHERE key LIKE 'app5.task.cache.%'",
              )
              .single;
          final proof = jsonDecode(proofRow['value'] as String) as Map;
          // Lee 11-05: no full re-hash at start. Row triggers delete the
          // witness on any sealed-row change instead of a row digest.
          expect(proof['generation'], 6);
          expect(proof.containsKey('digest'), isFalse);
          expect(
            profile.database.select(
              "SELECT COUNT(*) AS n FROM sqlite_schema WHERE type='trigger' AND name LIKE ?",
              ['${tables.events.replaceAll('_events', '')}_%_proof_%'],
            ).single['n'],
            27,
          );
          Iterable<Object?> witness() => profile.database.select(
            'SELECT 1 FROM profile_metadata WHERE key=?',
            [proofRow['key']],
          );
          if (oldGeneration) {
            proof['generation'] = 5;
            profile.database.execute(
              'UPDATE profile_metadata SET value=? WHERE key=?',
              [jsonEncode(proof), proofRow['key']],
            );
            expect(witness(), hasLength(1));
          }
          if (damaged) {
            profile.database.execute(
              "UPDATE ${tables.views} SET raw=json_set(raw,'\$.title','Forged cache') WHERE id=?",
              [task],
            );
            expect(witness(), isEmpty, reason: 'The change consumed it.');
          }
        } finally {
          await profile.close();
        }
        store = await TaskStore.open(folder, profilePath, textEngine: engine);
        expect(store.warmProjectionReuses, (damaged || oldGeneration) ? 0 : 1);
        expect(jsonEncode(store.rows), expected);
        await store.verifyHistory();
        expect(jsonEncode(store.rows), expected);
        expect(await folder.read('${store.writer}.applog'), bytes);
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    });
  }
}
