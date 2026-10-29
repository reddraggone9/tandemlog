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
    for (var i = 0; i < 2; i++) {
      final added = await json([
        'food',
        'add',
        '--name',
        'Beans',
        '--inbox',
        '--count',
        '2',
        '--request-id',
        request,
      ]);
      expect(added['actions'], i == 0 ? hasLength(1) : isEmpty);
    }
    expect(((await json(['food', 'list']))['rows'] as List).single['count'], 2);
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

  test('whole-action undo across processes, including text', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final added = await json(['tasks', 'add', 'Sweep', '--for', 'Lee']);
    final task = (added['affected'] as List).single as Map;
    final id = task['id'] as String;
    String rev(Map result) =>
        ((result['affected'] as List).single as Map)['rev'] as String;
    String action(Map result) => (result['actions'] as List).single as String;
    final done = await json([
      'tasks',
      'complete',
      id,
      '--if-rev',
      task['rev'] as String,
    ]);
    final needsRev = await json(['undo', action(done)]);
    expect(needsRev['error']['kind'], 'validation');
    final undone = await json(['undo', action(done), '--rev=$id=${rev(done)}']);
    expect(undone['alreadyUndone'], isNull, reason: '$undone');
    expect((await json(['tasks', 'list']))['total'], 1);
    final again = await json([
      'undo',
      action(done),
      '--rev=$id=${rev(undone)}',
    ]);
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
    final foodRevs = [
      for (final c in food['affected'] as List) '--rev=${c['id']}=${c['rev']}',
    ];
    final foodUndo = await json(['undo', action(food), ...foodRevs]);
    expect(foodUndo['alreadyUndone'], isNull, reason: '$foodUndo');
    expect((await json(['food', 'list']))['total'], 0);

    // Each edit and Undo runs in a fresh open; selective Undo keeps later
    // edits, and a repeated Undo appends nothing.
    final first = await json([
      'tasks',
      'edit',
      id,
      '--if-rev',
      rev(again),
      '--title',
      'Sweep porch',
    ]);
    final second = await json([
      'tasks',
      'edit',
      id,
      '--if-rev',
      rev(first),
      '--notes',
      'Use the big broom',
    ]);
    final u1 = await json(['undo', action(first), '--rev=$id=${rev(second)}']);
    expect(u1['error'], isNull, reason: '$u1');
    var shown = await json(['tasks', 'show', id]);
    expect(shown['title'], 'Sweep');
    expect(shown['notes'], 'Use the big broom');
    final u2 = await json([
      'undo',
      action(second),
      '--rev=$id=${shown['rev']}',
    ]);
    expect(u2['error'], isNull, reason: '$u2');
    shown = await json(['tasks', 'show', id]);
    expect(shown['notes'], '');
    final third = await json([
      'tasks',
      'edit',
      id,
      '--if-rev',
      shown['rev'] as String,
      '--title',
      'Sweep garage',
    ]);
    final u3 = await json(['undo', action(third), '--rev=$id=${rev(third)}']);
    expect(u3['error'], isNull, reason: '$u3');
    shown = await json(['tasks', 'show', id]);
    expect(shown['title'], 'Sweep');
    final before = await bytes(canonicalOnly: true);
    final repeat = await json([
      'undo',
      action(first),
      '--rev=$id=${shown['rev']}',
    ]);
    expect(repeat['alreadyUndone'], true);
    expect(await bytes(canonicalOnly: true), before);
  });

  test('text undo keeps another agent\'s later edit', () async {
    await setUpAgent(profile: 'one');
    await setUpAgent(profile: 'two', create: false);
    await cli(['people', 'add', 'Lee'], profile: 'one');
    final added = await json([
      'tasks',
      'add',
      'Review notes',
      '--for',
      'Lee',
    ], profile: 'one');
    final task = (added['affected'] as List).single as Map;
    final id = task['id'] as String;
    final mine = await json([
      'tasks',
      'edit',
      id,
      '--if-rev',
      task['rev'] as String,
      '--title',
      'Review notes today',
    ], profile: 'one');
    final peerView = await json(['tasks', 'show', id], profile: 'two');
    expect(peerView['title'], 'Review notes today');
    final peer = await json([
      'tasks',
      'edit',
      id,
      '--if-rev',
      peerView['rev'] as String,
      '--notes',
      'peer notes',
    ], profile: 'two');
    expect(peer['error'], isNull, reason: '$peer');
    final now = await json(['tasks', 'show', id], profile: 'one');
    final undone = await json([
      'undo',
      (mine['actions'] as List).single as String,
      '--rev=$id=${now['rev']}',
    ], profile: 'one');
    expect(undone['error'], isNull, reason: '$undone');
    final after = await json(['tasks', 'show', id], profile: 'two');
    expect(after['title'], 'Review notes');
    expect(after['notes'], 'peer notes');
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

  test('newer history stops reads and writes with update_required', () async {
    await setUpAgent(profile: 'one');
    await setUpAgent(profile: 'two', create: false);
    await cli(['people', 'add', 'Lee'], profile: 'two');
    final ws = Directory('${root.path}/ws');
    final context = await json(['context'], profile: 'two');
    final two =
        (context['writers'] as List).firstWhere((w) => w['self'] == true)['id']
            as String;
    final log = File('${ws.path}/$two.applog');
    final last = const LineSplitter().convert(log.readAsStringSync()).last;
    final future = jsonDecode(last) as Map<String, dynamic>
      ..['futureField'] = 1;
    log.writeAsStringSync('${jsonEncode(future)}\n', mode: FileMode.append);
    final before = await bytes(canonicalOnly: true);
    final read = await json(['tasks', 'list'], profile: 'one');
    expect(read['error']['kind'], 'update_required', reason: '$read');
    expect(read['exit'], 3);
    final write = await json(['people', 'add', 'Hester'], profile: 'one');
    expect(write['error']['kind'], 'update_required', reason: '$write');
    expect(await bytes(canonicalOnly: true), before);
  });

  test('JSON output is capped with an explicit marker', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    await cli([
      'tasks',
      'add',
      for (var i = 0; i < 60; i++) 'Task $i ${'x' * 400}',
      '--for',
      'Lee',
    ]);
    final (_, out) = await cli([
      'tasks',
      'list',
      '--limit',
      '60',
      '--format',
      'json',
    ]);
    expect(utf8.encode(out).length, lessThanOrEqualTo(32 * 1024));
    final page = jsonDecode(out) as Map;
    expect(page['truncated'], true);
    expect(page['total'], 60);
  });

  test('a profile without the agent marker is refused', () async {
    await Directory('${root.path}/gui').create();
    final (code, out) = await cli([
      'tasks',
      'list',
    ], profile: '${root.path}/gui');
    expect(code, isNot(0));
    expect(out, contains('No agent profile'));
  });

  test(
    'bulk edit needs the dry-run planHash and applies as one action',
    () async {
      await setUpAgent();
      await cli(['people', 'add', 'Lee']);
      final added = await json(['tasks', 'add', 'A', 'B', '--for', 'Lee']);
      final revs = [
        for (final a in added['affected'] as List)
          '--rev=${a['id']}=${a['rev']}',
      ];
      final ids = [
        for (final a in added['affected'] as List) a['id'] as String,
      ];
      final args = ['tasks', 'bulk-edit', ...ids, ...revs, '--tag', 'home'];
      final missing = await json(args);
      expect(missing['error']['kind'], 'validation');
      final dry = await json([...args, '--dry-run']);
      expect(dry['effects'], hasLength(2));
      final wrong = await json([...args, '--expect-plan', 'deadbeef']);
      expect(wrong['error']['kind'], 'plan_changed');
      final done = await json([
        ...args,
        '--expect-plan',
        dry['planHash'] as String,
      ]);
      expect(done['actions'], hasLength(1));
      final list = await json(['tasks', 'list', '--tag', 'home']);
      expect(list['total'], 2);
    },
  );

  test('checklist add, check and delete with revisions', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final task =
        ((await json(['tasks', 'add', 'Pack', '--for', 'Lee']))['affected']
                    as List)
                .single
            as Map;
    final item = await json([
      'checklist',
      'add',
      task['id'] as String,
      'Socks',
      '--if-rev',
      task['rev'] as String,
    ]);
    final checked = await json([
      'checklist',
      'check',
      item['id'] as String,
      '--if-rev',
      item['rev'] as String,
    ]);
    expect(checked['actions'], hasLength(1));
    final show = await json(['tasks', 'show', task['id'] as String]);
    final items = show['checklist'] as List;
    expect(items.single['completed'], true);
    final deleted = await json([
      'checklist',
      'delete',
      item['id'] as String,
      '--if-rev',
      checked['rev'] as String,
    ]);
    expect(deleted['actions'], hasLength(1));
  });

  test('food edit, products set and purchase import', () async {
    await setUpAgent();
    final added = await json([
      'food',
      'add',
      '--name',
      'Milk',
      '--brand',
      'GV',
      '--size',
      '1 gal',
      '--expiry',
      '2026-11-03',
      '--location',
      'Fridge',
    ]);
    final c = (added['affected'] as List).single as Map;
    final moved = await json([
      'food',
      'edit',
      c['id'] as String,
      '--rev=${c['id']}=${c['rev']}',
      '--location',
      'Pantry',
    ]);
    expect(moved['actions'], hasLength(1));
    final products = await json(['products', 'list']);
    final p = (products['products'] as List).single as Map;
    final set = await json([
      'products',
      'set',
      p['id'] as String,
      '--if-rev',
      p['rev'] as String,
      '--min',
      '2',
      '--link',
      'https://example.com/milk',
    ]);
    expect(set['product']['minimum'], 2);
    expect((await json(['products', 'list', '--running-low']))['total'], 1);
    final lines = File('${root.path}/lines.json')
      ..writeAsStringSync(
        jsonEncode([
          {
            'source': {'kind': 'test', 'key': 'r1#1'},
            'date': '2026-10-28',
            'store': 'Walmart',
            'amount': 348,
            'quantity': 1,
            'product': p['id'],
          },
        ]),
      );
    final plan = await json(['purchases', 'plan', lines.path]);
    final dry = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--dry-run',
    ]);
    expect(dry['status'], 'ready');
    final refused = await json(['purchases', 'import', plan['plan'] as String]);
    expect(refused['error']['kind'], 'plan_changed');
    final done = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(done['actions'], hasLength(1));
    final again = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(again['actions'], isEmpty);
    expect((await json(['purchases', 'list']))['total'], 1);
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
