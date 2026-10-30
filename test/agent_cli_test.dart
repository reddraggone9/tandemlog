import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/agent/agent_workspace.dart';
import 'package:tandemlog/agent/agent_profile.dart';
import 'package:tandemlog/agent/cli.dart';
import 'package:tandemlog/agent/command.dart';
import 'package:tandemlog/agent/commands_read.dart' show taskRevSql;
import 'package:tandemlog/agent/mcp_server.dart';
import 'package:tandemlog/agent/registry.dart';
import 'package:tandemlog/agent/render.dart' show revOf;
import 'package:tandemlog/food/food_store.dart' show StaleFoodState;
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

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
      'APPDATA': '${root.path}/appdata',
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
    expect(refused['error']['kind'], 'validation');
    final done = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(done['actions'], hasLength(1));
    // The plan binds its effects: a retry plans nothing and appends nothing.
    final stale = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(stale['error']['kind'], 'plan_changed');
    final retry = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--dry-run',
    ]);
    expect(retry['effects'], isEmpty);
    final again = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--expect-plan',
      retry['planHash'] as String,
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

  /// The advertised Undo command of a write result, as argv.
  List<String> undoArgv(Map result) {
    final hint = result['undo'] as String?;
    expect(hint, isNotNull, reason: '$result');
    return hint!.split(' ').sublist(1);
  }

  Future<Map<String, dynamic>> planned(List<String> args) async {
    final dry = await json([...args, '--dry-run']);
    expect(dry['planHash'], isNotNull, reason: '$dry');
    return json([...args, '--expect-plan', dry['planHash'] as String]);
  }

  Future<List<Map>> products() async => [
    for (final p in (await json(['products', 'list']))['products'] as List)
      p as Map,
  ];

  test(
    'product, purchase and product-changing actions undo as one unit',
    () async {
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
      ]);
      final c = (added['affected'] as List).first as Map;

      final renamed = await planned([
        'food',
        'edit',
        c['id'] as String,
        '--rev=${c['id']}=${c['rev']}',
        '--name',
        'Whole milk',
      ]);
      expect(renamed['error'], isNull, reason: '$renamed');
      expect((await products()).single['name'], 'Whole milk');
      final undoRename = await json(undoArgv(renamed));
      expect(undoRename['error'], isNull, reason: '$undoRename');
      expect((await products()).single['name'], 'Milk');

      var p = (await products()).single;
      final set = await json([
        'products',
        'set',
        p['id'] as String,
        '--if-rev',
        p['rev'] as String,
        '--min',
        '3',
      ]);
      expect(set['error'], isNull, reason: '$set');
      final undoSet = await json(undoArgv(set));
      expect(undoSet['error'], isNull, reason: '$undoSet');
      p = (await products()).single;
      expect(p['minimum'], isNull);

      final lines = File('${root.path}/lines.json')
        ..writeAsStringSync(
          jsonEncode([
            {
              'source': {'kind': 'test', 'key': 'r1#1'},
              'date': '2026-10-28',
              'store': 'Walmart',
              'amount': 348,
              'quantity': 2,
              'product': p['id'],
            },
          ]),
        );
      final plan = await json(['purchases', 'plan', lines.path]);
      final imported = await planned([
        'purchases',
        'import',
        plan['plan'] as String,
      ]);
      expect(imported['actions'], hasLength(1), reason: '$imported');
      expect((await json(['purchases', 'list']))['total'], 1);
      final undoImport = await json(undoArgv(imported));
      expect(undoImport['error'], isNull, reason: '$undoImport');
      expect((await json(['purchases', 'list']))['total'], 0);

      await json(['food', 'add', '--name', 'Lait', '--expiry', '2026-11-04']);
      final all = await products();
      final src = all.firstWhere((x) => x['name'] == 'Lait');
      final dst = all.firstWhere((x) => x['name'] == 'Milk');
      final mergeArgs = [
        'products',
        'merge',
        src['id'] as String,
        '--into',
        dst['id'] as String,
        '--rev=${src['id']}=${src['rev']}',
        '--rev=${dst['id']}=${dst['rev']}',
      ];
      final dry = await json([...mergeArgs, '--dry-run']);
      final mergeEffect =
          (dry['effects'] as List).firstWhere((e) => e['id'] == src['id'])
              as Map;
      expect(mergeEffect['fields']['mergedInto']['to'], dst['id']);
      final merged = await json([
        ...mergeArgs,
        '--expect-plan',
        dry['planHash'] as String,
      ]);
      expect(merged['error'], isNull, reason: '$merged');
      expect(await products(), hasLength(1));
      final undoMerge = await json(undoArgv(merged));
      expect(undoMerge['error'], isNull, reason: '$undoMerge');
      expect(await products(), hasLength(2));
    },
  );

  test('dry runs report moves and product changes in the plan', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    await cli(['tasks', 'add', 'A1', 'A2', 'A3', '--for', 'Lee']);
    final list = (await json(['tasks', 'list']))['tasks'] as List;
    final first = list.first as Map, last = list.last as Map;
    final args = [
      'tasks',
      'bulk-move',
      last['id'] as String,
      '--before',
      first['id'] as String,
      '--rev=${last['id']}=${last['rev']}',
      '--rev=${first['id']}=${first['rev']}',
    ];
    final dry = await json([...args, '--dry-run']);
    final moved = (dry['effects'] as List).where((e) => e['change'] == 'moved');
    expect(moved.single['id'], last['id']);
    expect(moved.single['fields']['before']['to'], first['id']);
    final done = await json([
      ...args,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(done['error'], isNull, reason: '$done');
    final after = (await json(['tasks', 'list']))['tasks'] as List;
    expect(after.first['id'], last['id']);

    final single = await json([
      'tasks',
      'move',
      after.first['id'] as String,
      '--before',
      'end',
      '--rev=${after.first['id']}=${after.first['rev']}',
      '--dry-run',
    ]);
    expect(single['effects'], isNotEmpty);

    await json(['food', 'add', '--name', 'Rice', '--expiry', '2027-01-01']);
    final p = (await products()).single;
    final set = await json([
      'products',
      'set',
      p['id'] as String,
      '--if-rev',
      p['rev'] as String,
      '--min',
      '2',
      '--dry-run',
    ]);
    final effect =
        (set['effects'] as List).firstWhere((e) => e['id'] == p['id']) as Map;
    expect(effect['fields']['minimum'], {'from': null, 'to': 2});
  });

  test(
    'a planned commit refuses when the workspace changed after the plan check',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      await cli(['people', 'add', 'Lee'], profile: 'one');
      final added = await json([
        'tasks',
        'add',
        'A',
        'B',
        '--for',
        'Lee',
      ], profile: 'one');
      final args = [
        'tasks',
        'bulk-edit',
        for (final a in added['affected'] as List) a['id'] as String,
        for (final a in added['affected'] as List)
          '--rev=${a['id']}=${a['rev']}',
        '--tag',
        'home',
      ];
      final dry = await json([...args, '--dry-run'], profile: 'one');
      debugAfterPlanCheck = () async {
        final (code, out) = await cli([
          'tasks',
          'add',
          'Peer',
          '--for',
          'Lee',
        ], profile: 'two');
        expect(code, 0, reason: out);
      };
      try {
        final refused = await json([
          ...args,
          '--expect-plan',
          dry['planHash'] as String,
        ], profile: 'one');
        expect(refused['error']['kind'], 'plan_changed', reason: '$refused');
      } finally {
        debugAfterPlanCheck = null;
      }
      expect(
        (await json([
          'tasks',
          'list',
          '--tag',
          'home',
        ], profile: 'one'))['total'],
        0,
      );
      // The peer's task is unrelated, so the same plan applies on a retry.
      final again = await json([
        ...args,
        '--expect-plan',
        dry['planHash'] as String,
      ], profile: 'one');
      expect(again['actions'], hasLength(1), reason: '$again');
    },
  );

  test('Undo and checklist add check their guard inside the append', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final task =
        ((await json(['tasks', 'add', 'Pack', '--for', 'Lee']))['affected']
                    as List)
                .single
            as Map;
    final done = await json([
      'tasks',
      'complete',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
    ]);
    final food = await json([
      'food',
      'add',
      '--name',
      'Beans',
      '--expiry',
      '2027-01-01',
    ]);
    final ws = await AgentWorkspace.open(
      AgentProfile.resolve(selection: 'default', environment: env),
      readOnly: false,
    );
    try {
      final own = ws.session.history.snapshot.recordsByWriter[ws.writer]!;
      UnifiedRecord record(Map result) {
        final seq = int.parse(
          ((result['actions'] as List).single as String).split(':').last,
        );
        return own.firstWhere((r) => r.sequence == seq);
      }

      final before = await bytes(canonicalOnly: true);
      final taskOp = record(done).effects.single.task!.id;
      final undo = await ws.session.tasks.undoOperations([
        taskOp,
      ], canCommit: () => false);
      expect(undo.error, isA<StaleTaskSnapshot>());
      await expectLater(
        ws.session.food.undoOperations([
          for (final e in record(food).effects) e.food!,
        ], canCommit: () => false),
        throwsA(isA<StaleFoodState>()),
      );
      await expectLater(
        ws.session.tasks.addChecklistItem(
          task['id'] as String,
          'Socks',
          canCommit: () => false,
        ),
        throwsA(isA<StaleTaskSnapshot>()),
      );
      expect(await bytes(canonicalOnly: true), before);
    } finally {
      await ws.close();
    }
  });

  test(
    'complete refuses an unseen peer checklist change before receipt',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      await cli(['people', 'add', 'Lee'], profile: 'one');
      final task =
          ((await json([
                        'tasks',
                        'add',
                        'Pack',
                        '--for',
                        'Lee',
                      ], profile: 'one'))['affected']
                      as List)
                  .single
              as Map;
      final id = task['id'] as String;
      final ws = await AgentWorkspace.open(
        AgentProfile.resolve(selection: 'one', environment: env),
        readOnly: false,
      );
      try {
        final item = await json([
          'checklist',
          'add',
          id,
          'Incoming socks',
          '--if-rev',
          task['rev'] as String,
        ], profile: 'two');
        expect(item['error'], isNull, reason: '$item');
        final before = await bytes(canonicalOnly: true);
        final complete = registry.firstWhere((c) => c.name == 'tasks complete');
        await expectLater(
          complete.run(
            AgentCall(
              complete.validate({'id': id, 'if-rev': task['rev']}),
              ws,
              AgentOptions(timeZone: 'America/Chicago', environment: env),
            ),
          ),
          throwsA(isA<StaleTaskSnapshot>()),
        );
        expect(await bytes(canonicalOnly: true), before);
      } finally {
        await ws.close();
      }
      expect(
        (await json(['tasks', 'show', id], profile: 'one'))['completed'],
        false,
      );
    },
  );

  test('concurrent init of one profile keeps exactly one identity', () async {
    final results = await Future.wait([
      for (var i = 0; i < 6; i++)
        cli([
          'init',
          '--workspace',
          '${root.path}/ws',
          '--name',
          'Vex',
          '--create',
        ]),
    ]);
    expect(results.where((r) => r.$1 == 0), hasLength(1), reason: '$results');
    for (final (code, out) in results.where((r) => r.$1 != 0)) {
      expect(code, 2);
      expect(out, contains('not empty'));
    }
    final logs = Directory(
      '${root.path}/ws',
    ).listSync().where((f) => f.path.endsWith('.applog'));
    expect(logs, hasLength(1));
    expect((await cli(['context'])).$1, 0);
    final again = await cli([
      'init',
      '--workspace',
      '${root.path}/ws',
      '--name',
      'Vex',
    ]);
    expect(again.$1, 2);
    expect((await cli(['context'])).$1, 0);
  });

  test(
    'Food paging and truncated output resume at the first dropped row',
    () async {
      await setUpAgent();
      for (final name in ['Apples', 'Beans', 'Corn']) {
        await cli(['food', 'add', '--name', name, '--expiry', '2027-01-01']);
      }
      final page1 = await json(['food', 'list', '--limit', '1']);
      final page2 = await json([
        'food',
        'list',
        '--limit',
        '1',
        '--cursor',
        page1['next'] as String,
      ]);
      expect(page2['error'], isNull, reason: '$page2');
      expect(page2['rows'].single['name'], 'Beans');

      await cli(['people', 'add', 'Lee']);
      await cli([
        'tasks',
        'add',
        for (var i = 0; i < 130; i++)
          'T${i.toString().padLeft(3, '0')} ${'é' * 300}',
        '--for',
        'Lee',
      ]);
      final (_, all) = await cli(['tasks', 'list', '--format', 'jsonl']);
      final ids = [
        for (final l in const LineSplitter().convert(all))
          (jsonDecode(l) as Map)['id'],
      ];
      expect(ids, hasLength(130));
      final (_, out) = await cli([
        'tasks',
        'list',
        '--limit',
        '130',
        '--format',
        'json',
      ]);
      expect(utf8.encode(out).length, lessThanOrEqualTo(32 * 1024));
      final page = jsonDecode(out) as Map;
      expect(page['truncated'], true);
      final shown = page['shown'] as int;
      expect(shown, lessThan(130));
      final rest = await json([
        'tasks',
        'list',
        '--limit',
        '130',
        '--cursor',
        page['next'] as String,
      ]);
      expect(rest['tasks'].first['id'], ids[shown]);
      final (_, text) = await cli(['tasks', 'list', '--limit', '130']);
      expect(utf8.encode(text).length, lessThanOrEqualTo(32 * 1024));
      final textShown = int.parse(
        RegExp(r'truncated at 32 KB after (\d+) rows').firstMatch(text)![1]!,
      );
      final textNext = RegExp(
        r'^next: (\S+)$',
        multiLine: true,
      ).firstMatch(text)![1]!;
      final resumed = await json([
        'tasks',
        'list',
        '--limit',
        '130',
        '--cursor',
        textNext,
      ]);
      expect(resumed['tasks'].first['id'], ids[textShown]);

      final server = McpServer(environment: env, profile: 'default');
      final reply = await server.handle(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'tasks_list',
            'arguments': {'limit': 130},
          },
        }),
      );
      final structured = (reply!['result'] as Map)['structuredContent'] as Map;
      expect(structured['truncated'], true);
      expect(structured['next'], page['next']);
      expect(
        utf8.encode(jsonEncode(structured)).length,
        lessThanOrEqualTo(32 * 1024),
      );
    },
  );

  test(
    'an oversized Food row pages its containers and always advances',
    () async {
      await setUpAgent();
      for (var i = 0; i < 6; i++) {
        final (code, out) = await cli([
          'food',
          'add',
          '--name',
          'Beans',
          '--expiry',
          '2027-01-01',
          '--count',
          '100',
        ]);
        expect(code, 0, reason: out);
      }
      final (_, all) = await cli(['food', 'list', '--format', 'jsonl']);
      final expected = [
        for (final l in const LineSplitter().convert(all))
          for (final c in (jsonDecode(l) as Map)['containers'] as List)
            (c as Map)['id'],
      ];
      expect(expected, hasLength(600));

      Future<List<Object?>> collect(
        Future<Map> Function(String? cursor) page,
      ) async {
        final seen = <Object?>[];
        String? cursor;
        final cursors = <String>{};
        for (var n = 0; n < 50; n++) {
          final p = await page(cursor);
          expect(p['error'], isNull, reason: '$p');
          expect(
            utf8.encode(jsonEncode(p)).length,
            lessThanOrEqualTo(32 * 1024),
          );
          final rows = p['rows'] as List;
          expect(rows, isNotEmpty);
          final row = rows.single as Map;
          expect(row['count'], 600);
          expect(row['containersFrom'] ?? 0, seen.length);
          seen.addAll([for (final c in row['containers'] as List) c['id']]);
          cursor = p['next'] as String?;
          if (cursor == null) return seen;
          expect(cursors.add(cursor), isTrue, reason: 'cursor repeated');
          if (seen.length < 600) expect(row['membersShown'], isPositive);
        }
        fail('paging did not finish');
      }

      final viaCli = await collect(
        (cursor) => json([
          'food',
          'list',
          if (cursor != null) ...['--cursor', cursor],
        ]),
      );
      expect(viaCli, expected);

      final server = McpServer(environment: env, profile: 'default');
      var id = 0;
      final viaMcp = await collect((cursor) async {
        final reply = await server.handle(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': ++id,
            'method': 'tools/call',
            'params': {
              'name': 'food_list',
              'arguments': {'cursor': ?cursor},
            },
          }),
        );
        return (reply!['result'] as Map)['structuredContent'] as Map;
      });
      expect(viaMcp, expected);
    },
  );

  test(
    'a member cursor restarts the row when rows before it changed',
    () async {
      await setUpAgent();
      final (code, out) = await cli([
        'food',
        'add',
        '--name',
        'Apples',
        '--expiry',
        '2026-12-01',
      ]);
      expect(code, 0, reason: out);
      for (final (name, expiry) in [
        ('Beans', '2027-01-01'),
        ('Carrots', '2027-02-01'),
      ]) {
        for (var i = 0; i < 6; i++) {
          final (code, out) = await cli([
            'food',
            'add',
            '--name',
            name,
            '--expiry',
            expiry,
            '--count',
            '100',
          ]);
          expect(code, 0, reason: out);
        }
      }
      // Page 1: Apples; page 2: Beans' first members, resuming inside Beans.
      final first = await json(['food', 'list']);
      final apples = (first['rows'] as List).first as Map;
      expect(apples['name'], 'Apples');
      final second = await json([
        'food',
        'list',
        '--cursor',
        first['next'] as String,
      ]);
      final beans = (second['rows'] as List).single as Map;
      expect(beans['name'], 'Beans');
      expect(beans['membersShown'], isPositive);
      final inside = second['next'] as String;
      // Removing Apples shifts Carrots to Beans' old offset.
      final container = (apples['containers'] as List).single as Map;
      final removed = await json([
        'food',
        'remove',
        container['id'] as String,
        '--if-rev',
        container['rev'] as String,
      ]);
      expect(removed['error'], isNull, reason: '$removed');
      final third = await json(['food', 'list', '--cursor', inside]);
      final row = (third['rows'] as List).first as Map;
      expect(row['name'], 'Carrots');
      expect(row.containsKey('containersFrom'), isFalse);
      // Unchanged rows still resume inside the row.
      final again = await json(['food', 'list']);
      final b2 = ((again['rows'] as List).single as Map);
      expect(b2['name'], 'Beans');
      final resumed = await json([
        'food',
        'list',
        '--cursor',
        again['next'] as String,
      ]);
      expect(
        ((resumed['rows'] as List).first as Map)['containersFrom'],
        b2['membersShown'],
      );
    },
  );

  test('a huge Food row in text clips its ID list and advances', () async {
    await setUpAgent();
    for (var i = 0; i < 37; i++) {
      final (code, out) = await cli([
        'food',
        'add',
        '--name',
        'Beans',
        '--expiry',
        '2027-01-01',
        '--count',
        '100',
      ]);
      expect(code, 0, reason: out);
    }
    await cli(['food', 'add', '--name', 'Apples', '--expiry', '2027-02-01']);
    final (code, text) = await cli(['food', 'list']);
    expect(code, 0, reason: text);
    expect(utf8.encode(text).length, lessThanOrEqualTo(32 * 1024));
    final lines = text.split('\n');
    final beans = lines.singleWhere((l) => l.contains('Beans'));
    expect(beans, contains('(+3200 more; --format json pages them)'));
    expect(lines.where((l) => l.contains('Apples')), hasLength(1));
    expect(lines.where((l) => l.startsWith('next: ')), isEmpty);
  });

  test(
    'a peer checklist change invalidates the task rev completion names',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      await cli(['people', 'add', 'Lee'], profile: 'one');
      final task =
          ((await json([
                        'tasks',
                        'add',
                        'Pack',
                        '--for',
                        'Lee',
                      ], profile: 'one'))['affected']
                      as List)
                  .single
              as Map;
      final id = task['id'] as String;
      final read = await json(['tasks', 'show', id], profile: 'one');
      expect(read['rev'], task['rev']);
      final item = await json([
        'checklist',
        'add',
        id,
        'Socks',
        '--if-rev',
        read['rev'] as String,
      ], profile: 'two');
      expect(item['error'], isNull, reason: '$item');
      final before = await bytes(canonicalOnly: true);
      final stale = await json([
        'tasks',
        'complete',
        id,
        '--if-rev',
        read['rev'] as String,
      ], profile: 'one');
      expect((stale['error'] as Map)['kind'], 'stale', reason: '$stale');
      expect(await bytes(canonicalOnly: true), before);
      final reread = await json(['tasks', 'show', id], profile: 'one');
      expect(reread['completed'], false);
      expect(reread['rev'], isNot(read['rev']));
      expect((reread['checklist'] as List).single['title'], 'Socks');
      final done = await json([
        'tasks',
        'complete',
        id,
        '--if-rev',
        reread['rev'] as String,
      ], profile: 'one');
      expect(done['actions'], hasLength(1), reason: '$done');
    },
  );

  test(
    'a peer change to an inherited checklist item invalidates the successor rev',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      await cli(['people', 'add', 'Lee'], profile: 'one');
      final added =
          ((await json([
                        'tasks',
                        'add',
                        'Pack',
                        '--for',
                        'Lee',
                      ], profile: 'one'))['affected']
                      as List)
                  .single
              as Map;
      final id = added['id'] as String;
      final edited = await json([
        'tasks',
        'edit',
        id,
        '--if-rev',
        added['rev'] as String,
        '--due',
        '2030-05-10',
        '--repeat',
        'every day',
      ], profile: 'one');
      expect(edited['error'], isNull, reason: '$edited');
      var show = await json(['tasks', 'show', id], profile: 'one');
      final item = await json([
        'checklist',
        'add',
        id,
        'Socks',
        '--if-rev',
        show['rev'] as String,
      ], profile: 'one');
      expect(item['error'], isNull, reason: '$item');
      show = await json(['tasks', 'show', id], profile: 'one');
      final done = await json([
        'tasks',
        'complete',
        id,
        '--if-rev',
        show['rev'] as String,
      ], profile: 'one');
      expect(done['error'], isNull, reason: '$done');
      final child = const Uuid().v5(id, 'successor');
      final read = await json(['tasks', 'show', child], profile: 'one');
      expect(read['error'], isNull, reason: '$read');
      final copy = (read['checklist'] as List).single as Map;
      // Neither the successor nor its untouched copy has the rev of an entity
      // without operations: both cover the completion that created them.
      expect(read['rev'], isNot(revOf(const [])));
      expect(copy['rev'], isNot(revOf(const [])));
      final checked = await json([
        'checklist',
        'check',
        copy['id'] as String,
        '--if-rev',
        copy['rev'] as String,
      ], profile: 'two');
      expect(checked['error'], isNull, reason: '$checked');
      final parent =
          (checked['affected'] as List).firstWhere(
                (a) => (a as Map)['id'] == child,
                orElse: () => null,
              )
              as Map?;
      expect(parent, isNotNull, reason: '$checked');
      expect(parent!['rev'], isNot(read['rev']));
      final before = await bytes(canonicalOnly: true);
      final stale = await json([
        'tasks',
        'complete',
        child,
        '--if-rev',
        read['rev'] as String,
      ], profile: 'one');
      expect((stale['error'] as Map)['kind'], 'stale', reason: '$stale');
      expect(await bytes(canonicalOnly: true), before);
      final reread = await json(['tasks', 'show', child], profile: 'one');
      expect(reread['rev'], isNot(read['rev']));
      final ok = await json([
        'tasks',
        'complete',
        child,
        '--if-rev',
        reread['rev'] as String,
      ], profile: 'one');
      expect(ok['actions'], hasLength(1), reason: '$ok');
    },
  );

  test(
    'an inherited item re-seeded after Undo and re-complete gets a new rev',
    () async {
      await setUpAgent();
      await cli(['people', 'add', 'Lee']);
      final added =
          ((await json(['tasks', 'add', 'Pack', '--for', 'Lee']))['affected']
                      as List)
                  .single
              as Map;
      final id = added['id'] as String;
      final edited = await json([
        'tasks',
        'edit',
        id,
        '--if-rev',
        added['rev'] as String,
        '--due',
        '2030-05-10',
        '--repeat',
        'every day',
      ]);
      expect(edited['error'], isNull, reason: '$edited');
      var show = await json(['tasks', 'show', id]);
      final item = await json([
        'checklist',
        'add',
        id,
        'Socks',
        '--if-rev',
        show['rev'] as String,
      ]);
      expect(item['error'], isNull, reason: '$item');
      show = await json(['tasks', 'show', id]);
      final done = await json([
        'tasks',
        'complete',
        id,
        '--if-rev',
        show['rev'] as String,
      ]);
      expect(done['error'], isNull, reason: '$done');
      final child = const Uuid().v5(id, 'successor');
      final first = await json(['tasks', 'show', child]);
      final copy = (first['checklist'] as List).single as Map;
      expect(copy['title'], 'Socks');
      final undone = await json(
        (done['undo'] as String).split(' ').skip(1).toList(),
      );
      expect(undone['error'], isNull, reason: '$undone');
      show = await json(['tasks', 'show', id]);
      final source = (show['checklist'] as List).single as Map;
      final renamed = await json([
        'checklist',
        'edit',
        source['id'] as String,
        '--title',
        'Shoes',
        '--if-rev',
        source['rev'] as String,
      ]);
      expect(renamed['error'], isNull, reason: '$renamed');
      show = await json(['tasks', 'show', id]);
      final again = await json([
        'tasks',
        'complete',
        id,
        '--if-rev',
        show['rev'] as String,
      ]);
      expect(again['error'], isNull, reason: '$again');
      final second = await json(['tasks', 'show', child]);
      final reseeded = (second['checklist'] as List).single as Map;
      // Same deterministic ID, new content: the item's rev must move too.
      expect(reseeded['id'], copy['id']);
      expect(reseeded['title'], 'Shoes');
      expect(reseeded['rev'], isNot(copy['rev']));
      final before = await bytes(canonicalOnly: true);
      final stale = await json([
        'checklist',
        'check',
        copy['id'] as String,
        '--if-rev',
        copy['rev'] as String,
      ]);
      expect((stale['error'] as Map)['kind'], 'stale', reason: '$stale');
      expect(await bytes(canonicalOnly: true), before);
      final ok = await json([
        'checklist',
        'check',
        reseeded['id'] as String,
        '--if-rev',
        reseeded['rev'] as String,
      ]);
      expect(ok['error'], isNull, reason: '$ok');
      // Revs are read per task and item: every lookup stays an index search
      // (a type-index lookup would scan every checklist completion).
      final ws = await AgentWorkspace.open(
        AgentProfile.resolve(selection: 'default', environment: env),
        readOnly: true,
      );
      try {
        final store = ws.session.tasks;
        final plan = [
          for (final r in store.db.select(
            'EXPLAIN QUERY PLAN '
            '${taskRevSql(store.tables.events, store.tables.views)}',
            [reseeded['id']],
          ))
            r['detail'] as String,
        ];
        expect(plan.where((d) => d.contains('_type_before')), isEmpty);
        expect(
          plan.where((d) => d.startsWith('SCAN') && !d.startsWith('SCAN item')),
          isEmpty,
          reason: plan.join('\n'),
        );
        expect(plan.where((d) => d.contains('_successor')), hasLength(3));
      } finally {
        await ws.close();
      }
    },
  );

  test('MCP answers malformed messages and keeps serving', () async {
    await setUpAgent();
    final server = McpServer(environment: env, profile: 'default');
    final input = Stream.fromIterable(
      [
        '[{"jsonrpc":"2.0","id":2,"method":"ping"}]',
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":"x"}',
        '"just a string"',
        '{bad json',
        '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"context","arguments":[1]}}',
        '{"jsonrpc":"2.0","id":5,"method":"ping"}',
      ].map<List<int>>((l) => utf8.encode('$l\n')),
    );
    final controller = StreamController<List<int>>();
    final collected = controller.stream.expand((b) => b).toList();
    final sink = IOSink(controller);
    await server.serve(input, sink);
    await sink.close();
    final replies = [
      for (final l in const LineSplitter().convert(
        utf8.decode(await collected),
      ))
        jsonDecode(l) as Map,
    ];
    expect(
      [for (final r in replies) r['error']?['code']],
      [-32600, -32602, -32600, -32700, -32602, null],
    );
    expect(replies.last['id'], 5);
  });

  test('undo of an undo is refused cleanly and never advertised', () async {
    await setUpAgent();
    final person = await json(['people', 'add', 'Lee']);
    expect(person['undo'], isNull);
    final added = await json(['tasks', 'add', 'Mop', '--for', 'Lee']);
    expect(added['undo'], isNull);
    final task = (added['affected'] as List).single as Map;
    final done = await json([
      'tasks',
      'complete',
      task['id'] as String,
      '--if-rev',
      task['rev'] as String,
    ]);
    final undone = await json(undoArgv(done));
    expect(undone['error'], isNull, reason: '$undone');
    expect(undone['undo'], isNull);
    final before = await bytes(canonicalOnly: true);
    final again = await json([
      'undo',
      (undone['actions'] as List).single as String,
      '--rev=${task['id']}=${undone['affected'].first['rev']}',
    ]);
    expect(again['error']['kind'], 'undo_unavailable', reason: '$again');
    expect(again['exit'], 2);
    final empty = await json(['undo', ':1']);
    expect(empty['error']['kind'], 'validation');
    expect(await bytes(canonicalOnly: true), before);
  });

  test(
    'multi-container remove needs a plan; MCP marks destructive tools',
    () async {
      await setUpAgent();
      await json([
        'food',
        'add',
        '--name',
        'Eggs',
        '--expiry',
        '2027-01-01',
        '--count',
        '2',
      ]);
      final containers =
          ((await json(['food', 'list']))['rows'] as List).single['containers']
              as List;
      final args = [
        'food',
        'remove',
        for (final c in containers) c['id'] as String,
        for (final c in containers) ...['--if-rev', c['rev'] as String],
      ];
      final missing = await json(args);
      expect(missing['error']['kind'], 'validation');
      expect(missing['error']['details']['field'], 'expect-plan');
      final removed = await planned(args);
      expect(removed['actions'], hasLength(1), reason: '$removed');

      final server = McpServer(environment: env, profile: 'default');
      final list = await server.handle(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}),
      );
      final hints = {
        for (final t in (list!['result'] as Map)['tools'] as List)
          t['name']: t['annotations']['destructiveHint'],
      };
      for (final name in [
        'tasks_delete',
        'tasks_bulk-delete',
        'food_remove',
        'products_merge',
        'checklist_delete',
      ]) {
        expect(hints[name], true, reason: name);
      }
      expect(hints['tasks_add'], false);
    },
  );

  test(
    'only commands with a tested in-append plan check skip the pre-check',
    () {
      // Each name here needs a test that a peer change after the plan check is
      // refused inside the append (below for purchases import).
      expect(
        [
          for (final c in registry)
            if (c.planCheckedInAppend) c.name,
        ],
        ['purchases import'],
      );
    },
  );

  test(
    'purchase commit guards fresh admission and pins one exact file input',
    () async {
      await setUpAgent(profile: 'one');
      await setUpAgent(profile: 'two', create: false);
      final lines = File('${root.path}/receipt-lines.json')
        ..writeAsStringSync(
          jsonEncode([
            {
              'source': {'kind': 'test', 'key': 'guarded-receipt'},
              'date': '2026-10-28',
              'store': 'Synthetic',
              'amount': 100,
              'quantity': 1,
              'name': 'Guarded beans',
            },
          ]),
        );
      final planned = await json([
        'purchases',
        'plan',
        lines.path,
      ], profile: 'one');
      final file = File(planned['plan'] as String);
      final original = await file.readAsString();
      final args = ['purchases', 'import', file.path];
      var dry = await json([...args, '--dry-run'], profile: 'one');
      await file.writeAsString('$original ');
      final changed = await json([
        ...args,
        '--expect-plan',
        dry['planHash'] as String,
      ], profile: 'one');
      expect(changed['error']['kind'], 'plan_changed', reason: '$changed');
      await file.writeAsString(original);
      debugAfterPlanCheck = () async {
        final peer = await json([
          'food',
          'add',
          '--name',
          'Peer tea',
          '--inbox',
        ], profile: 'two');
        expect(peer['error'], isNull, reason: '$peer');
      };
      try {
        final refused = await json([
          ...args,
          '--expect-plan',
          dry['planHash'] as String,
        ], profile: 'one');
        expect(refused['error']['kind'], 'plan_changed', reason: '$refused');
        expect((await json(['purchases', 'list'], profile: 'one'))['total'], 0);
      } finally {
        debugAfterPlanCheck = null;
      }
      dry = await json([...args, '--dry-run'], profile: 'one');
      debugAfterPlanCheck = () async {
        final p =
            ((await json(['products', 'list'], profile: 'two'))['products']
                        as List)
                    .single
                as Map;
        final edited = await json([
          'products',
          'set',
          p['id'] as String,
          '--if-rev',
          p['rev'] as String,
          '--min',
          '2',
        ], profile: 'two');
        final undone = await json(undoArgv(edited), profile: 'two');
        expect(undone['error'], isNull, reason: '$undone');
      };
      try {
        final hidden = await json([
          ...args,
          '--expect-plan',
          dry['planHash'] as String,
        ], profile: 'one');
        expect(hidden['error']['kind'], 'plan_changed', reason: '$hidden');
        expect((await json(['purchases', 'list'], profile: 'one'))['total'], 0);
      } finally {
        debugAfterPlanCheck = null;
      }
      dry = await json([...args, '--dry-run'], profile: 'one');
      debugAfterPlanCheck = () async {
        await file.writeAsString('{invalid input now}');
      };
      try {
        final done = await json([
          ...args,
          '--expect-plan',
          dry['planHash'] as String,
        ], profile: 'one');
        expect(done['actions'], hasLength(1), reason: '$done');
        expect((await json(['purchases', 'list'], profile: 'one'))['total'], 1);
      } finally {
        debugAfterPlanCheck = null;
      }
    },
  );

  test('purchase plans never overwrite and dry runs write nothing', () async {
    await setUpAgent();
    await json(['food', 'add', '--name', 'Tea', '--expiry', '2027-01-01']);
    final p = (await products()).single;
    final lines = File('${root.path}/lines.json')
      ..writeAsStringSync(
        jsonEncode([
          {
            'source': {'kind': 'test', 'key': 'r2#1'},
            'date': '2026-10-28',
            'store': 'Aldi',
            'amount': 199,
            'quantity': 1,
            'product': p['id'],
          },
        ]),
      );
    final plan = await json(['purchases', 'plan', lines.path]);
    expect(plan['error'], isNull, reason: '$plan');
    final exists = await json(['purchases', 'plan', lines.path]);
    expect(exists['error']['details']['error'], 'exists');
    expect(
      (await json(['purchases', 'plan', lines.path, '--force']))['error'],
      isNull,
    );
    final inside = await json([
      'purchases',
      'plan',
      lines.path,
      '--out',
      '${root.path}/ws/plan.json',
    ]);
    expect(inside['error']['details']['error'], 'inside_workspace');
    final before = await bytes();
    final dry = await json([
      'purchases',
      'import',
      plan['plan'] as String,
      '--dry-run',
    ]);
    expect(dry['status'], 'ready', reason: '$dry');
    expect(
      (dry['effects'] as List).where((e) => e['fields']?['kind'] == 'purchase'),
      hasLength(1),
    );
    expect(await bytes(), before);
  });

  test('checklist item revs reach JSON clients', () async {
    await setUpAgent();
    await cli(['people', 'add', 'Lee']);
    final task =
        ((await json(['tasks', 'add', 'Trip', '--for', 'Lee']))['affected']
                    as List)
                .single
            as Map;
    final item = await json([
      'checklist',
      'add',
      task['id'] as String,
      'Tickets',
      '--if-rev',
      task['rev'] as String,
    ]);
    final shown = await json(['tasks', 'show', task['id'] as String]);
    final row = (shown['checklist'] as List).single as Map;
    expect(row['rev'], item['rev']);
    final edited = await json([
      'checklist',
      'edit',
      item['id'] as String,
      '--if-rev',
      row['rev'] as String,
      '--title',
      'Train tickets',
    ]);
    final affected = {
      for (final a in edited['affected'] as List) a['id']: a['rev'],
    };
    expect(affected.keys, contains(item['id']));
    final again = await json(['tasks', 'show', task['id'] as String]);
    expect(
      ((again['checklist'] as List).single as Map)['rev'],
      affected[item['id']],
    );
  });

  test(
    'reads and dry runs reuse the warm cache; writes still seal it',
    () async {
      await setUpAgent();
      await cli(['people', 'add', 'Lee']);
      final added = await json([
        'tasks',
        'add',
        'Sweep',
        'Mop',
        '--for',
        'Lee',
      ]);
      final task = (added['affected'] as List).first as Map;
      final opened = <({bool disposable, int reuses})>[];
      debugAgentWorkspaceOpened = (ws) => opened.add((
        disposable: ws.disposable,
        reuses: ws.session.history.decodedCacheReuses,
      ));
      addTearDown(() => debugAgentWorkspaceOpened = null);
      final before = await bytes();
      final list = await json(['tasks', 'list']);
      final dry = await json([
        'tasks',
        'complete',
        task['id'] as String,
        '--if-rev',
        task['rev'] as String,
        '--dry-run',
      ]);
      expect(list['total'], 2);
      expect(dry['effects'], isNotEmpty);
      expect(await bytes(), before);
      // Both ran on disposable profile copies bound to the real location, so
      // the decoded cache sealed by the last write applied (no cold replay).
      expect(opened, hasLength(2));
      expect(opened.every((o) => o.disposable && o.reuses > 0), isTrue);

      // The seal itself: opening consumes the proof. A disposable close does
      // not re-seal; an ordinary close (the app's) does, as before.
      debugAgentWorkspaceOpened = null;
      final profile = AgentProfile.resolve(
        selection: 'default',
        environment: env,
      );
      Future<int> openClose({required bool disposable}) async {
        final ws = await AgentWorkspace.open(
          profile,
          readOnly: false,
          disposable: disposable,
        );
        final reuses = ws.session.history.decodedCacheReuses;
        await ws.close();
        return reuses;
      }

      expect(await openClose(disposable: true), greaterThan(0));
      expect(await openClose(disposable: false), 0);
      expect(await openClose(disposable: false), greaterThan(0));
    },
  );

  test(
    'a planned commit plans on a worker isolate beside the real open',
    () async {
      await setUpAgent();
      final added = await json([
        'food',
        'add',
        '--name',
        'Rice',
        '--expiry',
        '2027-03-01',
        '--location',
        'Pantry',
        '--count',
        '3',
      ]);
      expect(added['error'], isNull, reason: '$added');
      final id = ((added['affected'] as List).first as Map)['id'] as String;
      final rev = (await json(['food', 'show', id]))['rev'] as String;
      final args = [
        'food',
        'move-some',
        id,
        '--if-rev',
        rev,
        '--count',
        '2',
        '--location',
        'Freezer',
      ];
      final opened = <bool>[];
      debugAgentWorkspaceOpened = (ws) => opened.add(ws.disposable);
      addTearDown(() => debugAgentWorkspaceOpened = null);
      // A plain dry run still plans here, on its disposable copy.
      final dry = await json([...args, '--dry-run']);
      expect(opened, [true]);
      opened.clear();
      // The planned commit's own dry run opens its copy on a worker isolate
      // (whose hooks start unset), so only the real workspace opens here;
      // the plan is still checked before the command runs.
      final committed = await json([
        ...args,
        '--expect-plan',
        dry['planHash'] as String,
      ]);
      expect(committed['actions'], hasLength(1), reason: '$committed');
      expect(opened, [false]);
      opened.clear();
      // Failures inside the worker keep their stable kinds: a refused dry
      // run (validation) and a changed plan.
      final bad = [...args];
      bad[bad.indexOf('--count') + 1] = '9';
      bad[bad.indexOf('--if-rev') + 1] =
          (await json(['food', 'show', id]))['rev'] as String;
      final invalid = await json([...bad, '--expect-plan', 'x']);
      expect(invalid['error']['kind'], 'validation', reason: '$invalid');
      // The old rev is stale now; the worker's dry run refuses it.
      final stale = await json([
        ...args,
        '--expect-plan',
        dry['planHash'] as String,
      ]);
      expect(stale['error']['kind'], 'stale', reason: '$stale');
      // Each refused commit opened and closed the real workspace cleanly.
      final next = await json(['food', 'show', id]);
      expect(next['error'], isNull, reason: '$next');
    },
  );

  test(
    'tasks list renders people and revs identically in both formats',
    () async {
      await setUpAgent();
      await cli(['people', 'add', 'Lee']);
      await cli(['people', 'add', 'Hester']);
      await json(['tasks', 'add', 'Water plants', '--for', 'Lee']);
      await json(['tasks', 'add', 'Call vet', '--for', 'Hester']);
      final listed = await json(['tasks', 'list']);
      final (code, text) = await cli(['tasks', 'list']);
      expect(code, 0);
      final tasks = (listed['tasks'] as List).cast<Map>();
      expect(tasks.map((t) => t['assigneeName']).toSet(), {'Lee', 'Hester'});
      for (final t in tasks) {
        final line = text
            .split('\n')
            .singleWhere((l) => l.contains(t['title'] as String));
        expect(line, contains('@${t['assigneeName']}'));
        expect(line, contains('rev ${t['rev']}'));
      }
      final forLee = await json(['tasks', 'list', '--for', 'Lee']);
      expect(forLee['view'], 'Open tasks for Lee');
      expect(forLee['total'], 1);
    },
  );

  test('food move-some splits a row as one action with one Undo', () async {
    await setUpAgent();
    final added = await json([
      'food',
      'add',
      '--name',
      'Soup',
      '--expiry',
      '2027-03-01',
      '--location',
      'Pantry',
      '--count',
      '3',
    ]);
    final row = [
      for (final a in added['affected'] as List) (a as Map)['id'] as String,
    ]..sort();
    expect(row, hasLength(3));
    Future<Map> show(String id) => json(['food', 'show', id]);
    final named = await show(row.last);
    final args = [
      'food',
      'move-some',
      row.last,
      '--if-rev',
      named['rev'] as String,
      '--count',
      '2',
      '--location',
      'Freezer',
    ];
    // Plan required: the command chooses the containers.
    final bare = await json(args);
    expect(bare['error']['kind'], 'validation');
    for (final bad in [
      ['--count', '0'],
      ['--count', '4'],
      ['--location', 'Pantry'],
    ]) {
      final argv = [...args];
      argv[argv.indexOf(bad[0]) + 1] = bad[1];
      final refused = await json([...argv, '--dry-run']);
      expect(refused['error']['kind'], 'validation', reason: '$bad');
    }
    // A planned commit whose own dry run fails opens and closes the real
    // workspace cleanly: the refusal is reported and the next call proceeds.
    final zero = [...args];
    zero[zero.indexOf('--count') + 1] = '0';
    final failed = await json([...zero, '--expect-plan', 'x']);
    expect(failed['error']['kind'], 'validation', reason: '$failed');
    final before = await bytes();
    final dry = await json([...args, '--dry-run']);
    expect(await bytes(), before);
    // The row's first two current containers, as the page sends them.
    expect(
      [for (final e in dry['effects'] as List) (e as Map)['id']]..sort(),
      row.take(2).toList(),
    );

    // Any change between plan and commit refuses the commit.
    final other = await show(row.first);
    await json([
      'food',
      'edit',
      row.first,
      '--rev=${row.first}=${other['rev']}',
      '--expiry',
      '2026-12-01',
    ]);
    final canonical = await bytes(canonicalOnly: true);
    final changed = await json([
      ...args,
      '--expect-plan',
      dry['planHash'] as String,
    ]);
    expect(changed['error']['kind'], 'plan_changed');
    expect(changed['exit'], 6);
    expect(await bytes(canonicalOnly: true), canonical);

    // The edited container left the row; re-plan moves the next two.
    final replanned = await json([...args, '--dry-run']);
    expect(replanned['error'], isNull, reason: '$replanned');
    final moved = await json([
      ...args,
      '--expect-plan',
      replanned['planHash'] as String,
    ]);
    expect(moved['actions'], hasLength(1));
    final movedIds = [
      for (final a in moved['affected'] as List) (a as Map)['id'] as String,
    ]..sort();
    expect(movedIds, row.skip(1).toList());
    for (final id in movedIds) {
      expect((await show(id))['details']['location'], 'Freezer');
    }
    expect((await show(row.first))['details']['location'], 'Pantry');

    // One Undo restores both.
    final undone = await json(undoArgv(moved));
    expect(undone['actions'], hasLength(1), reason: '$undone');
    for (final id in movedIds) {
      expect((await show(id))['details']['location'], 'Pantry');
    }
    expect((await json(['verify']))['error'], isNull);
  });
}
