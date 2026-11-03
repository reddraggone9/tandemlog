import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/agent/cli.dart';
import 'package:tandemlog/agent/agent_workspace.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import '../integration_test/native_text_fixtures.dart';

/// A planned commit opens the profile copy on a worker isolate while the real
/// workspace opens here. Both rebuild stale text caches on the one native
/// engine of the process; neither may collide with the other.
void main() {
  late Directory root;
  late Map<String, String> env;
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  setUpAll(() {
    agentTextEngine = () => NativeTextEngine(libraryPath: library);
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-planned-text-');
    await Directory('${root.path}/ws').create();
    env = {
      'HOME': root.path,
      'XDG_DATA_HOME': '${root.path}/data',
      'APPDATA': '${root.path}/appdata',
      'TZ': 'America/Chicago',
    };
  });
  tearDown(() => root.delete(recursive: true));

  Future<Map<String, dynamic>> json(List<String> argv) async {
    final (code, out) = await runCli([
      ...argv,
      '--profile',
      'default',
      '--format',
      'json',
    ], environment: env);
    return {'exit': code, ...jsonDecode(out) as Map<String, dynamic>};
  }

  test('planned commits after peer text edits never collide', () async {
    expect(
      (await json([
        'init',
        '--workspace',
        '${root.path}/ws',
        '--name',
        'Vex-default',
        '--create',
      ]))['exit'],
      0,
    );
    await json(['people', 'add', 'Lee']);
    final added = await json([
      'tasks',
      'add',
      for (var i = 0; i < 24; i++) 'Synthetic task $i',
      '--for',
      'Lee',
    ]);
    final all = [for (final a in added['affected'] as List) a['id'] as String];
    final ids = all.sublist(0, 12), others = all.sublist(12);
    final peer = await openNativeFixtureStore(
      LocalLogFolder('${root.path}/ws'),
      '${root.path}/peer',
      nativeLibraryPath: library,
    );
    addTearDown(peer.close);
    final failures = <String>[];
    for (var round = 0; round < 6; round++) {
      final listed = await json(['tasks', 'list']);
      final revs = [
        for (final t in listed['tasks'] as List)
          if (ids.contains(t['id'])) '--rev=${t['id']}=${t['rev']}',
      ];
      // Another device edits other titles: every agent text cache is stale.
      await peer.refresh();
      for (final id in others) {
        await peer.editNativeFixtureTask(id, {
          'title': 'Synthetic other ${others.indexOf(id)} r$round',
        });
      }
      final args = ['tasks', 'bulk-edit', ...ids, ...revs, '--tag', 'r$round'];
      // The dry run warms only a disposable copy, as in a separate process.
      final dry = await json([...args, '--dry-run']);
      expect(dry['exit'], 0, reason: '$dry');
      final hash = dry['planHash'];
      final done = await json([...args, '--expect-plan', hash as String]);
      if (done['exit'] != 0) failures.add('round $round: $done');
    }
    expect(failures, isEmpty);
  });
}
