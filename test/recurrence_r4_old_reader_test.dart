import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';
import '../integration_test/native_text_fixtures.dart';
import 'support/frozen_recurrence_r3/current_operation.dart' as frozen;

// Real bytes from the current writer against the real RC109 reader. The frozen
// operation decoder alone cannot show what an old device does with a whole
// workspace, so lib/ from the published RC109 commit runs in its own process
// and owns its own profile, exactly as an un-updated device does.
const _rc109 = '2409743be75f7acd4d0d1259e800308cc47681c6';
const _rc109Decoder =
    '9a889789b38d881f2b3aa1b6839587e483f39c6c4d3c33e13794d789e0646d28';
const _update = 'Update the app; history was preserved';
const _rule = 'every 2 months on the 2nd Tuesday';
final _library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];

class _Reader {
  _Reader(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _waiting.removeAt(0).complete(jsonDecode(line)));
    process.stderr.transform(utf8.decoder).listen(_errors.write);
  }
  final Process process;
  final _waiting = <Completer<Object?>>[];
  final _errors = StringBuffer();

  Future<Map<String, dynamic>> call(String cmd, [Map<String, Object?>? args]) {
    final reply = Completer<Object?>();
    _waiting.add(reply);
    process.stdin.writeln(jsonEncode({'cmd': cmd, ...?args}));
    return reply.future
        .timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw StateError('RC109 hung on $cmd: $_errors'),
        )
        .then((value) => value! as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> ok(String cmd, [Map<String, Object?>? args]) =>
      call(cmd, args).then((reply) {
        expect(reply['ok'], isTrue, reason: '$cmd: $reply');
        return reply['value'] as Map<String, dynamic>;
      });

  Future<void> refused(String cmd, [Map<String, Object?>? args]) async {
    final reply = await call(cmd, args);
    expect(reply['ok'], isFalse, reason: '$cmd was accepted: $reply');
    expect(reply['error'], contains(_update), reason: cmd);
  }
}

Future<void> _copy(String from, String to) async {
  final target = Directory(to);
  if (await target.exists()) await target.delete(recursive: true);
  await target.create(recursive: true);
  await for (final entity in Directory(from).list()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is File) {
      await entity.copy('$to/$name');
    } else if (entity is Directory) {
      await _copy(entity.path, '$to/$name');
    }
  }
}

Future<Map<String, String>> _bytes(String folder) async => {
  await for (final entity in Directory(folder).list())
    if (entity is File)
      entity.uri.pathSegments.last: base64Encode(await entity.readAsBytes()),
};

Future<_Reader> _startReader(String root) async {
  Future<ProcessResult> git(List<String> args) =>
      Process.run('git', args, stdoutEncoding: null);
  final archive = await git(['archive', _rc109, 'lib']);
  expect(
    archive.exitCode,
    0,
    reason:
        'CI needs fetch-depth 0 so the published reader remains available: ${archive.stderr}',
  );
  final tree = '$root/rc109';
  await Directory('$tree/.dart_tool').create(recursive: true);
  final tar = await Process.start('tar', ['-x', '-C', tree]);
  tar.stdin.add(archive.stdout as List<int>);
  await tar.stdin.close();
  expect(await tar.exitCode, 0);
  expect(
    sha256
        .convert(
          await File('$tree/lib/domain/current_operation.dart').readAsBytes(),
        )
        .toString(),
    _rc109Decoder,
  );
  // Same pinned packages (the lockfile did not change), other tandemlog root.
  // Running the driver in place first materializes the sqlite native asset.
  final probe = await Process.run(_dart(), [
    'run',
    '--verbosity=error',
    'test/support/rc109_reader/driver.dart',
    '--probe',
  ]);
  expect(probe.exitCode, 0, reason: '${probe.stdout}${probe.stderr}');
  final config =
      jsonDecode(await File('.dart_tool/package_config.json').readAsString())
          as Map<String, dynamic>;
  final base = Directory('.dart_tool').absolute.uri;
  for (final package in (config['packages'] as List).cast<Map>()) {
    package['rootUri'] = package['name'] == 'tandemlog'
        ? Directory(tree).absolute.uri.toString()
        : base.resolve('${package['rootUri']}/').toString();
  }
  await File(
    '$tree/.dart_tool/package_config.json',
  ).writeAsString(jsonEncode(config));
  await File(
    '.dart_tool/native_assets.yaml',
  ).copy('$tree/.dart_tool/native_assets.yaml');
  await File('test/support/rc109_reader/driver.dart').copy('$tree/driver.dart');
  return _Reader(
    await Process.start(_dart(), [
      '--packages=$tree/.dart_tool/package_config.json',
      '$tree/driver.dart',
      _library!,
    ]),
  );
}

String _dart() {
  final executable = Platform.resolvedExecutable;
  final cache = executable.indexOf('/bin/cache/');
  return cache < 0
      ? 'dart'
      : '${executable.substring(0, cache)}/bin/cache/dart-sdk/bin/dart';
}

typedef _Fixture = ({
  String root,
  String shared,
  String main,
  String peer,
  String user,
  String legacy,
  NativeTextEngine? engine,
});

/// What each mode's sole delivered record must be. Retained completions carry
/// no schedule at all: their revision comes from the parent rule.
Map<String, Future<LogEvent> Function(_Fixture, TaskStore)> _actions() {
  Future<String> authored(
    _Fixture f,
    Future<void> Function(TaskStore other, String id) build,
  ) async {
    // A third updated device authors the prerequisite and is not delivered.
    // A completion can only be r4's first arrival through reordered delivery.
    final other = await TaskStore.open(
      LocalLogFolder(f.shared),
      '${f.root}/author',
      textEngine: f.engine,
    );
    final id = const Uuid().v4();
    try {
      await build(other, id);
    } finally {
      await other.close();
    }
    return id;
  }

  Map<String, dynamic> schedule() => {
    'dueDate': '2030-05-14',
    'recurrence': _rule,
  };
  Future<LogEvent> finish(TaskStore w, String id) async {
    await w.refresh();
    return w.complete(
      id,
      completionInstant: DateTime.utc(2030, 5, 14, 12),
      localZoneId: 'UTC',
    );
  }

  return {
    'create': (f, w) => w.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Expanded',
      'description': '',
      'assignee': f.user,
      'schedule': schedule(),
    }),
    'update': (f, w) =>
        w.command(f.legacy, 'task.edited', {'schedule': schedule()}),
    'complete snapshot': (f, w) async {
      final id = await authored(
        f,
        (a, id) => a.command(id, 'task.created', {
          'title': 'Expanded',
          'description': '',
          'assignee': f.user,
          'schedule': schedule(),
        }),
      );
      return finish(w, id);
    },
    'complete text': (f, w) async {
      final id = await authored(
        f,
        (a, id) => a.createNativeFixtureTask(id, {
          'title': 'Expanded',
          'description': '',
          'assignee': f.user,
          'schedule': schedule(),
        }),
      );
      return finish(w, id);
    },
    'complete checklist': (f, w) async {
      final id = await authored(f, (a, id) async {
        await a.createNativeFixtureTask(id, {
          'title': 'Expanded',
          'description': '',
          'assignee': f.user,
          'schedule': schedule(),
        });
        await a.addChecklistItem(id, 'Synthetic item');
      });
      return finish(w, id);
    },
    'complete retained': (f, w) async {
      final id = await authored(f, (a, id) async {
        await a.createNativeFixtureTask(id, {
          'title': 'Expanded',
          'description': '',
          'assignee': f.user,
          'schedule': schedule(),
        });
        final first = await a.complete(
          id,
          completionInstant: DateTime.utc(2030, 5, 14, 12),
          localZoneId: 'UTC',
        );
        await a.command(const Uuid().v5(id, 'successor'), 'task.edited', {
          'schedule': {'dueDate': '2030-08-20', 'recurrence': _rule},
        });
        await a.reopen(id, [first.id]);
      });
      return finish(w, id);
    },
  };
}

const _modes = {
  'create': 'task.createdWithText',
  'update': 'task.edited',
  'complete snapshot': 'task.completed',
  'complete text': 'task.completedWithText',
  'complete checklist': 'task.completedWithChecklist',
  'complete retained': 'task.completedKeepingSuccessor',
};

void main() {
  _Reader? reader;
  Directory? root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('r4-old-reader-');
    reader = await _startReader(root!.path);
    expect(
      (await reader!.ok('whoami'))['library'],
      startsWith(File('${root!.path}/rc109').absolute.path),
    );
  });
  tearDownAll(() async {
    reader?.process.kill();
    await root?.delete(recursive: true);
  });

  final skip = Platform.isWindows
      ? 'Linux CI proves the wire behavior; the harness uses POSIX tooling.'
      : _library == null
      ? 'Requires the production text engine.'
      : false;

  for (final action in _modes.keys) {
    test(
      '$action: real r4 record refused whole by real RC109, own and peer, running and reopen',
      () async {
        final engine = NativeTextEngine(libraryPath: _library);
        final base = await Directory(
          '${root!.path}/${action.replaceAll(' ', '-')}',
        ).create();
        final shared = '${base.path}/shared',
            main = '${base.path}/main',
            peer = '${base.path}/peer';
        await Directory(shared).create();
        final seed = await reader!.ok('seed', {
          'folder': shared,
          'main': main,
          'peer': peer,
          // Only an engine-less workspace writes snapshot mode with a successor.
          'useEngine': action != 'complete snapshot',
        });
        final textEngine = action == 'complete snapshot' ? null : engine;
        final fixture = (
          root: base.path,
          shared: shared,
          main: main,
          peer: peer,
          user: seed['user'] as String,
          legacy: seed['legacy'] as String,
          engine: textEngine,
        );
        await _copy(shared, '${base.path}/saved-shared');
        await _copy(main, '${base.path}/saved-main');
        await _copy(peer, '${base.path}/saved-peer');
        final prefix = await _bytes(shared);

        // The peer device updates and acts. Its profile moves forward with it.
        final writer = await TaskStore.open(
          LocalLogFolder(shared),
          peer,
          textEngine: textEngine,
        );
        final LogEvent event;
        try {
          event = await _actions()[action]!(fixture, writer);
        } finally {
          await writer.close();
        }
        expect(event.type, _modes[action]);
        expect(event.operationRevision, 4);
        // No schedule is carried by retained: the parent rule requires r4.
        if (action == 'complete retained') {
          expect(event.data, isNot(contains('successor')));
        }
        expect(
          () => frozen.CurrentOperation.decode(
            event.canonicalRaw!,
            module: 'tasks',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(_update),
            ),
          ),
        );

        final peerName = '${seed['peerWriter']}.applog';
        final prior = base64Decode(prefix[peerName]!);
        final after = await File('$shared/$peerName').readAsBytes();
        final delivered = Uint8List.sublistView(after, prior.length);
        // Exactly one complete outer action carrying exactly this operation.
        final lines = LineSplitter.split(utf8.decode(delivered)).toList();
        expect(lines, hasLength(1));
        final record = UnifiedRecord.decode(lines.single);
        expect(record.effects.single.task!.encode(), event.canonicalRaw);

        Future<void> restore() async {
          await _copy('${base.path}/saved-shared', shared);
          await _copy('${base.path}/saved-main', main);
          await _copy('${base.path}/saved-peer', peer);
          await File('$shared/$peerName').writeAsBytes(prior, flush: true);
        }

        for (final own in [false, true]) {
          final profile = own ? peer : main;
          final who = own ? 'own' : 'peer';

          // Running: warm prefix first, proven by the reader's own counter.
          await restore();
          final warm = await reader!.ok('open', {
            'folder': shared,
            'profile': profile,
          });
          expect(warm['safety'], isNull);
          expect(warm['records'], greaterThan(0));
          expect(
            warm['decodedCacheReuses'],
            warm['records'],
            reason: '$who warm prefix came from the sealed cache',
          );
          // A partial tail is not yet a recognizable record.
          final half = delivered.length ~/ 2;
          final sink = File(
            '$shared/$peerName',
          ).openSync(mode: FileMode.append);
          sink.writeFromSync(delivered.sublist(0, half));
          sink.flushSync();
          final partial = await reader!.ok('refresh');
          expect(partial['safety'], isNull);
          expect(partial['rows'], warm['rows']);
          expect(partial['food'], warm['food']);
          sink.writeFromSync(delivered.sublist(half));
          sink.flushSync();
          sink.closeSync();
          final canonical = await _bytes(shared);
          await reader!.refused('refresh');
          final held = await reader!.ok('state');
          expect(held['safety'], contains(_update));
          expect(held['rows'], warm['rows'], reason: 'Task projection');
          expect(held['food'], warm['food'], reason: 'Food projection');
          expect(held['revision'], warm['revision']);
          expect(held['commonHead'], warm['commonHead']);
          expect(held['dump'], warm['dump'], reason: 'protected heads');
          await reader!.refused('taskWrite');
          await reader!.refused('foodWrite');
          expect(await _bytes(shared), canonical);
          expect(
            await reader!.ok('state').then((s) => s['dump']),
            warm['dump'],
          );
          await reader!.ok('close');

          // Clean reopen with the complete record already delivered. The same
          // sealed state was just shown to hit; the consumed proof shows this
          // attempt reached that path before the suffix refused the open.
          await restore();
          final sealed = await reader!.ok('dump', {'profile': profile});
          expect(sealed['proofs'], 1);
          await File(
            '$shared/$peerName',
          ).writeAsBytes(delivered, mode: FileMode.append, flush: true);
          final preserved = await _bytes(shared);
          await reader!.refused('open', {'folder': shared, 'profile': profile});
          final consumed = await reader!.ok('dump', {'profile': profile});
          expect(consumed['proofs'], 0);
          expect(consumed['dump'], sealed['dump'], reason: 'protected heads');
          expect(await _bytes(shared), preserved);
          // Refusal stays stable and does not depend on the optional proof.
          await reader!.refused('open', {'folder': shared, 'profile': profile});
          expect(await _bytes(shared), preserved);
        }
        engine.dispose();
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
