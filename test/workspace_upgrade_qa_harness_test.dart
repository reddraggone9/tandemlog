// Linux real-filesystem/native-engine smoke only: never Android or SAF proof.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import '../tool/android_workspace_upgrade/harness.dart';

class _LinuxFilesystemSmoke extends AndroidLogFolder {
  _LinuxFilesystemSmoke(this.filesystem) : super(filesystem.location);
  final LocalLogFolder filesystem;
  int replacements = 0;
  @override
  Future<List<LogFileInfo>> list() => filesystem.list();
  @override
  Future<Uint8List> read(String name) => filesystem.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      filesystem.readBounded(name, maximumBytes);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      filesystem.readFrom(name, offset);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      filesystem.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      filesystem.append(name, bytes);
  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) =>
      filesystem.checkReplacementSupport(name, maximumBytes);
  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    await filesystem.replaceOwned(name, expected, bytes);
    replacements++;
  }
}

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  test(
    'Linux filesystem QA harness: two cold recoveries preserve native fixture; NOT SAF acceptance',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'workspace-upgrade-qa-linux-smoke-',
      );
      try {
        final privateRoot = await Directory('${root.path}/private').create();
        final shared = await Directory(
          '${root.path}/synthetic-shared',
        ).create();
        final adapter = _LinuxFilesystemSmoke(LocalLogFolder(shared.path));
        final progress = <String>[];
        final report = await runWorkspaceUpgradeSafQa(
          privateRoot,
          adapter,
          progress: progress.add,
          libraryPath: library,
        );
        expect(
          report['passed'],
          true,
          reason: [report['error'], report['stack']].join('\n'),
        );
        expect(report['runtimePlatform'], 'linux');
        expect(report['actualAndroidSafAcceptance'], false);
        expect(report['transport'], contains('not Android or SAF acceptance'));
        final faults = (report['faults'] as List).cast<Map>();
        expect(faults.map((f) => f['phase']), ['staging', 'activating']);
        expect(
          faults.every(
            (f) => f['checkedTransportPrefixReplacementConfirmed'] == true,
          ),
          true,
        );
        expect(
          faults.every(
            (f) => f['realAndroidProviderReplacementConfirmed'] == false,
          ),
          true,
        );
        expect(adapter.replacements, 4);
        expect(progress.where((s) => s.startsWith('Recovered ')), hasLength(2));
        final saved =
            jsonDecode(
                  await File('${privateRoot.path}/report.json').readAsString(),
                )
                as Map;
        expect(saved['passed'], true);
        for (final phase in ['staging', 'activating']) {
          final prefix = await File(
            '${privateRoot.path}/$phase-partial-manifest.bin',
          ).readAsBytes();
          final fault = faults.singleWhere((f) => f['phase'] == phase);
          expect(prefix.length, (fault['prefix'] as Map)['bytes']);
          expect(
            sha256.convert(prefix).toString(),
            (fault['prefix'] as Map)['sha256'],
          );
        }
        // Independently reopen the actually closed SQLite connection and inspect
        // completion/writer authority rather than relying only on report flags.
        final profile = await LocalProfileDatabase.open(
          '${privateRoot.path}/qa-private-profile',
        );
        try {
          final settings = LocalSettings.protectedValues(profile);
          final migration = profile.database.select(
            'SELECT state FROM protected_app_migrations',
          );
          expect(migration.single['state'], 'complete');
          for (final table in [
            'protected_app_outbox',
            'protected_text_intents',
            'protected_food_intents',
          ]) {
            expect(profile.database.select('SELECT * FROM $table'), isEmpty);
          }
          final manifest =
              jsonDecode(
                    await File(
                      '${shared.path}/tandemlog-space.json',
                    ).readAsString(),
                  )
                  as Map;
          expect(manifest['v'], 4);
          expect(manifest['ready'], true);
          expect(
            (manifest['owners'] as Map).containsKey(settings['writer']),
            true,
          );
        } finally {
          await profile.close();
        }
        // Inspect retained files independently against the pre-conversion
        // inventory. The run never imports external data or uses a saved profile.
        final baseline = report['baseline'] as Map;
        for (final entry in baseline.entries) {
          if (entry.key == 'tandemlog-space.json') continue;
          final bytes = await File('${shared.path}/${entry.key}').readAsBytes();
          expect(bytes.length, (entry.value as Map)['bytes']);
          expect(
            sha256.convert(bytes).toString(),
            (entry.value as Map)['sha256'],
          );
        }
        final projection = report['baselineProjection'] as Map;
        expect(projection['nativeFields'], hasLength(greaterThanOrEqualTo(4)));
        final rows = (projection['tasks'] as List)
            .map((r) => (r as Map)['raw'] as Map)
            .toList();
        expect(
          rows.singleWhere((r) => r['kind'] == 'task')['title'],
          'Synthetic native task edited before upgrade',
        );
        expect(
          rows.singleWhere((r) => r['kind'] == 'checklistItem')['completed'],
          true,
        );
        expect(projection['food'], hasLength(3));
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux || library == null
        ? 'Linux smoke only: set TANDEMLOG_TEXT_LIBRARY to the reviewed native engine'
        : false,
  );
}
