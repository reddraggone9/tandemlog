import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  for (final installer in [false, true]) {
    test(
      '${installer ? 'installer' : 'startup'} synthetic seed is admitted by the actual startup contract without rewriting scalar history',
      () async {
        final root = await Directory.systemTemp.createTemp('smoke-contract-');
        final engine = NativeTextEngine(
          libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
        );
        final folder = LocalLogFolder('${root.path}/shared');
        TaskStore? store;
        try {
          final result = await Process.run(
            Platform.isWindows ? 'python' : 'python3',
            installer
                ? [
                    'packaging/smoke.py',
                    '--workspace',
                    root.path,
                    '--report',
                    '${root.path}/installer.json',
                    '--phase',
                    'seed-contract',
                    '--seed',
                  ]
                : [
                    'tool/measure_startup.py',
                    '--workspace',
                    root.path,
                    '--tasks',
                    '3',
                    '--runs',
                    '1',
                    '--binary',
                    '${root.path}/absent-synthetic-executable',
                    '--native-library',
                    Platform.environment['TANDEMLOG_TEXT_LIBRARY']!,
                  ],
          );
          // Startup deliberately stops at its absent launch target after seed
          // preparation. The installer seed has no launch command at all.
          if (installer) expect(result.exitCode, 0, reason: '${result.stderr}');
          final before = {
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          };
          expect(before, contains('tandemlog-space.json'));
          final receipt =
              jsonDecode(
                    await File(
                      '${root.path}/synthetic-text-fixture.json',
                    ).readAsString(),
                  )
                  as Map;
          expect(receipt['initialized'], isTrue);
          expect(receipt['rows'], installer ? 2 : 4);
          expect(
            receipt['native_sha256'],
            sha256
                .convert(
                  await File(
                    Platform.environment['TANDEMLOG_TEXT_LIBRARY']!,
                  ).readAsBytes(),
                )
                .toString(),
          );
          expect(
            await File('${root.path}/profile/local.sqlite').exists(),
            isFalse,
            reason: 'Fixture construction must not warm the measured profile.',
          );
          // This is the same admission flag used by main, rather than a SQL
          // projection/window check that could precede startup refusal.
          store = await TaskStore.open(
            folder,
            '${root.path}/probe-private',
            textEngine: engine,
            initializeNewWorkspaceText: true,
          );
          expect(store.sharedTextInitialized, isTrue);
          expect(store.rows, hasLength(installer ? 2 : 4));
          expect(
            store.rows.where((row) => row['kind'] == 'task'),
            hasLength(installer ? 1 : 3),
          );
          await store.verifyHistory();
          final records = <Map<String, dynamic>>[
            for (final file in await folder.list())
              if (file.name.endsWith('.jsonl'))
                for (final line in const LineSplitter().convert(
                  utf8.decode(await folder.read(file.name)),
                ))
                  (jsonDecode(line) as Map).cast<String, dynamic>(),
          ];
          expect(
            records.where((record) => record['type'] == 'task.created'),
            hasLength(installer ? 1 : 3),
            reason: 'The historical scalar workload stays comparable.',
          );
          expect(
            records.where(
              (record) => record['type'] == 'text.baselineInitialized',
            ),
            hasLength(1),
          );
          if (installer) {
            final expected =
                jsonDecode(
                      await File('${root.path}/expected.json').readAsString(),
                    )
                    as Map;
            expect(expected['canonical'], {
              for (final entry in before.entries)
                entry.key: sha256.convert(base64Decode(entry.value)).toString(),
            });
          }
          await store.close();
          store = await TaskStore.open(
            folder,
            '${root.path}/cold-probe-private',
            textEngine: engine,
            initializeNewWorkspaceText: true,
          );
          expect(store.sharedTextInitialized, isTrue);
          expect({
            for (final file in await folder.list())
              file.name: base64Encode(await folder.read(file.name)),
          }, before);
        } finally {
          await store?.close();
          engine.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
