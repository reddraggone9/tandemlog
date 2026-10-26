import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    test('Task proof keeps original digest bytes; cache=$cacheState', () async {
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
          // Independent old-format oracle over the actual sealed database.
          final names = [
            tables.events,
            tables.views,
            tables.streams,
            tables.streamRanges,
            tables.textFields,
            tables.textActors,
            tables.textOutbox,
            tables.positions,
            tables.metadata,
          ];
          final rows = [
            for (final entry in names.indexed)
              profile.database
                  .select(
                    'SELECT * FROM ${entry.$2} '
                    '${entry.$1 == 8 ? "WHERE key IN ('order_projection','text_baseline_verified') " : ''}'
                    'ORDER BY ${[3, 4, 5].contains(entry.$1) ? '1,2' : '1'}',
                  )
                  .map((row) => row.values.toList())
                  .toList(),
          ];
          expect(
            rows.expand((t) => t).expand((r) => r).whereType<Uint8List>(),
            isNotEmpty,
            reason: 'Native checkpoints must participate as real SQLite BLOBs.',
          );
          expect(
            proof['digest'],
            sha256
                .convert(
                  utf8.encode(
                    jsonEncode({'rows': rows, 'ready': proof['ready']}),
                  ),
                )
                .toString(),
          );
          if (oldGeneration) {
            proof['generation'] = 3;
            profile.database.execute(
              'UPDATE profile_metadata SET value=? WHERE key=?',
              [jsonEncode(proof), proofRow['key']],
            );
            profile.database.execute(
              "UPDATE ${tables.views} SET raw=json_remove(raw,'\$.completionOrder')",
            );
          }
          if (damaged) {
            profile.database.execute(
              "UPDATE ${tables.views} SET raw=json_set(raw,'\$.title','Forged cache') WHERE id=?",
              [task],
            );
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
