import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/agent/agent_workspace.dart';
import 'package:tandemlog/agent/cli.dart';
import 'package:tandemlog/agent/mcp_server.dart';
import 'package:tandemlog/agent/registry.dart';
import 'package:tandemlog/text/native_text_engine.dart';

/// In-process agent CLI against private synthetic workspaces; the packaged
/// executable gets the same calls in the process smoke test.
void main() {
  late Directory root;
  late Map<String, String> env;
  setUpAll(() {
    agentTextEngine = () => NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-agent-cli-');
    await Directory('${root.path}/ws').create();
    env = {
      'HOME': root.path,
      'XDG_DATA_HOME': '${root.path}/data',
      'TZ': 'America/Chicago',
    };
  });
  tearDown(() => root.delete(recursive: true));

  Future<(int, String)> cli(List<String> argv, {String profile = 'default'}) =>
      runCli([...argv, '--profile', profile], environment: env);
  Future<Map<String, dynamic>> json(
    List<String> argv, {
    String profile = 'default',
  }) async {
    final (code, out) = await cli([
      ...argv,
      '--format',
      'json',
    ], profile: profile);
    final value = jsonDecode(out) as Map<String, dynamic>;
    if (code != 0) return {'exit': code, ...value};
    return value;
  }

  /// All workspace and profile bytes, or only the canonical workspace.
  Future<String> bytes({bool canonicalOnly = false}) async {
    final files = await Directory(canonicalOnly ? '${root.path}/ws' : root.path)
        .list(recursive: true)
        .where((f) => f is File && !f.path.endsWith('agent.lock'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final out = StringBuffer();
    for (final f in files) {
      out.writeln('${f.path} ${sha256.convert(await f.readAsBytes())}');
    }
    return out.toString();
  }

  Future<void> setUpAgent({
    String profile = 'default',
    bool create = true,
  }) async {
    final (code, out) = await cli([
      'init',
      '--workspace',
      '${root.path}/ws',
      '--name',
      'Vex-$profile',
      if (create) '--create',
    ], profile: profile);
    expect(code, 0, reason: out);
  }

  test('init, capture, list and show; reads change no bytes', () async {
    await setUpAgent();
    expect((await cli(['people', 'add', 'Lee'])).$1, 0);
    final added = await json([
      'tasks',
      'add',
      'Pay water bill',
      'Buy milk',
      '--for',
      'Lee',
    ]);
    expect(added['affected'], hasLength(2));
    final before = await bytes();
    final list = await json(['tasks', 'list']);
    expect(list['total'], 2);
    final id = (list['tasks'] as List).first['id'] as String;
    final (code, text) = await cli(['tasks', 'show', id.substring(0, 8)]);
    expect(code, 0);
    expect(text, contains('rev '));
    expect((await cli(['context'])).$1, 0);
    expect((await cli(['verify'])).$1, 0);
    expect(await bytes(), before);
  });

  test('every existing-item write requires a current rev', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final added = await json(['tasks', 'add', 'Water plants', '--for', 'Lee']);
    final task = (added['affected'] as List).single as Map;
    final missing = await json(['tasks', 'complete', task['id'] as String]);
    expect(missing['error']['kind'], 'validation');
    final edited = await json([
      'tasks',
      'edit',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
      '--due',
      '2026-11-02',
    ]);
    expect(edited['affected'], isNotEmpty);
    final before = await bytes(canonicalOnly: true);
    final stale = await json([
      'tasks',
      'complete',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
    ]);
    expect(stale['error']['kind'], 'stale');
    expect(stale['exit'], 6);
    expect(await bytes(canonicalOnly: true), before);
  });

  test('request ID retry does not duplicate a capture', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    const request = '0d6c1f3e-5c55-4c8a-9a39-7a1f0b8e2f11';
    for (var i = 0; i < 2; i++) {
      expect(
        (await cli([
          'tasks',
          'add',
          'Once',
          '--for',
          'Lee',
          '--request-id',
          request,
        ])).$1,
        0,
      );
    }
    expect((await json(['tasks', 'list']))['total'], 1);
  });

  test('dry run appends nothing and reports a stable plan', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final added = await json(['tasks', 'add', 'Recycle', '--for', 'Lee']);
    final task = (added['affected'] as List).single as Map;
    final before = await bytes();
    final args = [
      'tasks',
      'complete',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
      '--dry-run',
    ];
    final first = await json(args), second = await json(args);
    expect(first['dryRun'], true);
    expect(first['planHash'], second['planHash']);
    expect(await bytes(), before);
  });

  test('whole-action undo, repeated undo, and refused text undo', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final added = await json(['tasks', 'add', 'Sweep', '--for', 'Lee']);
    final task = (added['affected'] as List).single as Map;
    final done = await json([
      'tasks',
      'complete',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
    ]);
    final action = (done['actions'] as List).single as String;
    final undone = await json(['undo', action]);
    expect(undone['alreadyUndone'], isNull);
    expect((await json(['tasks', 'list']))['total'], 1);
    final again = await json(['undo', action]);
    expect(again['alreadyUndone'], true);

    final food = await json([
      'food',
      'add',
      '--name',
      'Milk',
      '--expiry',
      '2026-11-03',
      '--count',
      '2',
    ]);
    expect(
      (await json([
        'undo',
        (food['actions'] as List).single as String,
      ]))['alreadyUndone'],
      isNull,
    );
    expect((await json(['food', 'list']))['total'], 0);

    final show = await json(['tasks', 'show', task['id'] as String]);
    final text = await json([
      'tasks',
      'edit',
      task['id'] as String,
      '--if-rev',
      show['rev'] as String,
      '--title',
      'Sweep porch',
    ]);
    final before = await bytes(canonicalOnly: true);
    final refused = await json([
      'undo',
      (text['actions'] as List).single as String,
    ]);
    expect(refused['error']['kind'], 'undo_unavailable');
    expect(await bytes(canonicalOnly: true), before);
  });

  test(
    'two agent identities have separate writers and see each other',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      await cli(['people', 'add', 'Lee'], profile: 'one');
      await cli(['tasks', 'add', 'From one', '--for', 'Lee'], profile: 'one');
      await cli(['tasks', 'add', 'From two', '--for', 'Lee'], profile: 'two');
      final context = await json(['context'], profile: 'one');
      final writers = (context['writers'] as List)
          .map((w) => w['name'])
          .toSet();
      expect(writers, containsAll(['Vex-one', 'Vex-two']));
      expect((await json(['tasks', 'list'], profile: 'one'))['total'], 2);
    },
  );

  test('a profile without the agent marker is refused', () async {
    await Directory('${root.path}/gui').create();
    final (code, out) = await cli([
      'tasks',
      'list',
    ], profile: '${root.path}/gui');
    expect(code, isNot(0));
    expect(out, contains('No agent profile'));
  });

  test('MCP lists every non-setup registry command and calls tools', () async {
    await setUpAgent();
    final server = McpServer(environment: env, profile: 'default');
    final list = await server.handle(
      jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}),
    );
    final names = ((list!['result'] as Map)['tools'] as List)
        .map((t) => t['name'])
        .toSet();
    expect(names, {
      for (final c in registry)
        if (c.name != 'init') c.toolName,
    });
    final call = await server.handle(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'context', 'arguments': {}},
      }),
    );
    expect((call!['result'] as Map)['isError'], false);
  });
}
