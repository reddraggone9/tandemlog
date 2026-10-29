// Frozen-stable106 refusal probe for the writer-cap removal (writer-cap
// review follow-up). Run it inside a checkout of stable106 source (452fe88),
// not this tree, against a fixture written by this tree's
// test/writer_count_test.dart:
//
//   TANDEMLOG_WRITER_FIXTURE_OUT=<dir> flutter test test/writer_count_test.dart
//   cp test/support/stable106_writer_cap_probe.dart <stable106>/test/
//   cd <stable106> && TANDEMLOG_WRITER_FIXTURE=<dir> \
//     flutter test test/stable106_writer_cap_probe.dart
//
// Expected: stable106 refuses the 258-installation workspace with "Too many
// installation histories" and leaves every workspace and profile byte as it
// was. The receipt is evidence/agent-interface-feasibility/
// stable106-writer-cap-refusal.json.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';

String identity(int index) =>
    '${index.toRadixString(16).padLeft(8, '0')}-3333-4333-8333-444444444444';

Map<String, String> digests(Directory dir) => {
  for (final f
      in dir.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    f.path.substring(dir.path.length): sha256
        .convert(f.readAsBytesSync())
        .toString(),
};

void main() {
  test(
    'stable106 refuses more than 256 installations and writes nothing',
    () async {
      final source = Platform.environment['TANDEMLOG_WRITER_FIXTURE']!;
      final root = await Directory.systemTemp.createTemp(
        'tandemlog-106-probe-',
      );
      addTearDown(() => root.delete(recursive: true));
      for (final name in ['shared', 'p0']) {
        final target = Directory('${root.path}/$name')..createSync();
        for (final f in Directory(
          '$source/$name',
        ).listSync().whereType<File>()) {
          f.copySync('${target.path}/${f.uri.pathSegments.last}');
        }
      }
      final histories = Directory(
        '${root.path}/shared',
      ).listSync().where((f) => f.path.endsWith('.applog')).length;
      final before = digests(root);
      final profile = await LocalProfileDatabase.open('${root.path}/p0');
      Object? failure;
      try {
        final history = await UnifiedHistory.open(
          LocalLogFolder('${root.path}/shared'),
          profile: profile,
          writer: identity(1),
        );
        await history.close();
      } catch (e) {
        failure = e;
      } finally {
        await profile.close();
      }
      // The profile database's own open may checkpoint its WAL; compare the
      // canonical workspace exactly and report the profile separately.
      final after = digests(root);
      final workspaceUnchanged = before.entries
          .where((e) => e.key.startsWith('/shared/'))
          .every((e) => after[e.key] == e.value);
      final newFiles = after.keys.where((k) => !before.containsKey(k)).toList();
      stdout.writeln(
        jsonEncode({
          'histories': histories,
          'failure': '$failure',
          'workspace_unchanged': workspaceUnchanged,
          'workspace_new_files': [
            for (final k in newFiles)
              if (k.startsWith('/shared/')) k,
          ],
          'profile_changed': [
            for (final e in before.entries)
              if (e.key.startsWith('/p0/') && after[e.key] != e.value) e.key,
          ],
        }),
      );
      expect(failure.toString(), contains('Too many installation histories'));
      expect(workspaceUnchanged, isTrue);
      expect(newFiles.where((k) => k.startsWith('/shared/')), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
