import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_purchase_import.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';

// Real bytes from this build against the real stable 2026.11.1 reader
// (design/food-shelf-life.md): lib/ from the published commit runs in its own
// process with its own profile, exactly as an un-updated device does, and
// meets a Keeps for edit (product.edit revision 2) or a prefilled receipt
// birth (container.add revision 3).
const _stable = 'ef71b8806fb93da3a9d2ce82f3610e86d044f05e';
const _stableDecoder =
    'bd2e749ce1cc5d02322148b0758166785fd15af2f015d792bcd72a513b74044f';
const _update = 'Update the app; history was preserved';
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
          onTimeout: () =>
              throw StateError('Stable 2026.11.1 hung on $cmd: $_errors'),
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
  final archive = await git(['archive', _stable, 'lib']);
  expect(
    archive.exitCode,
    0,
    reason:
        'CI needs fetch-depth 0 so the published reader remains available: ${archive.stderr}',
  );
  final tree = '$root/stable116';
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
    _stableDecoder,
  );
  // Same pinned packages (the lockfile did not change), other tandemlog root.
  // Running the driver in place first materializes the sqlite native asset.
  final probe = await Process.run(_dart(), [
    'run',
    '--verbosity=error',
    'test/support/stable116_reader/driver.dart',
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
  await File(
    'test/support/stable116_reader/driver.dart',
  ).copy('$tree/driver.dart');
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

/// The one action the updated device writes, and the revision that an older
/// install must refuse.
final _modes = <String, (String, int, Future<void> Function(FoodStore) action)>{
  'Keeps for edit': (
    'product.edit',
    2,
    (food) async {
      final soup = food.state.containers.single;
      await food.changeDetails(
        [soup.id],
        soup.details,
        const [],
        products: FoodProductChange(
          roots: [soup.product],
          changes: const {
            'keepsFor': {'count': 2, 'unit': 'week'},
          },
        ),
      );
    },
  ),
  'receipt import with the usual location': (
    'container.add',
    3,
    (food) async {
      await food.commitPurchaseImport(
        FoodPurchaseImportPlan(
          space: food.space,
          importId: '11111111-1111-4111-8111-111111111111',
          sourceSha256: 'a' * 64,
          lines: [
            FoodPurchaseLine(
              sourceKind: 'test',
              sourceKey: 'old-reader#1',
              date: '2031-03-01',
              store: 'Synthetic store',
              amount: 250,
              quantity: 1,
              name: 'Synthetic soup',
            ),
          ],
        ),
      );
    },
  ),
};

void main() {
  final skip = Platform.isWindows
      ? 'Linux CI proves the wire behavior; the harness uses POSIX tooling.'
      : _library == null
      ? 'Requires the production text engine.'
      : false;
  _Reader? reader;
  Directory? root;
  // setUpAll still runs when every test in the file is skipped.
  setUpAll(() async {
    if (skip != false) return;
    root = await Directory.systemTemp.createTemp('shelf-life-old-reader-');
    reader = await _startReader(root!.path);
    expect(
      (await reader!.ok('whoami'))['library'],
      startsWith(File('${root!.path}/stable116').absolute.path),
    );
  });
  tearDownAll(() async {
    reader?.process.kill();
    await root?.delete(recursive: true);
  });

  for (final MapEntry(key: mode, value: (family, revision, action))
      in _modes.entries) {
    test(
      '$mode: refused whole by real stable 2026.11.1, own and peer, running and reopen',
      () async {
        final engine = NativeTextEngine(libraryPath: _library);
        final base = await Directory(
          '${root!.path}/${mode.replaceAll(' ', '-')}',
        ).create();
        final shared = '${base.path}/shared',
            main = '${base.path}/main',
            peer = '${base.path}/peer';
        await Directory(shared).create();
        final seed = await reader!.ok('seed', {
          'folder': shared,
          'main': main,
          'peer': peer,
          'useEngine': true,
        });
        await _copy(shared, '${base.path}/saved-shared');
        await _copy(main, '${base.path}/saved-main');
        await _copy(peer, '${base.path}/saved-peer');
        final prefix = await _bytes(shared);

        // The peer device updates and acts. Its profile moves forward with it.
        final writer = await TaskStore.open(
          LocalLogFolder(shared),
          peer,
          textEngine: engine,
        );
        final food = await FoodStore.openUnified(writer.unified!);
        try {
          await action(food);
        } finally {
          await food.close();
          await writer.close();
        }

        final peerName = '${seed['peerWriter']}.applog';
        final prior = base64Decode(prefix[peerName]!);
        final after = await File('$shared/$peerName').readAsBytes();
        final delivered = Uint8List.sublistView(after, prior.length);
        // Exactly one complete outer action, holding the new revision.
        final lines = LineSplitter.split(utf8.decode(delivered)).toList();
        expect(lines, hasLength(1));
        final effects = UnifiedRecord.decode(lines.single).effects;
        final newer = [
          for (final effect in effects)
            if (effect.food != null &&
                effect.food!.currentOperation.family == family &&
                effect.food!.currentOperation.revision == revision)
              effect.food!,
        ];
        expect(newer, isNotEmpty, reason: '$family r$revision');
        // Nothing else in the action is beyond the old install.
        for (final effect in effects) {
          final FoodRecord record = effect.food!;
          final op = record.currentOperation;
          expect(
            newer.contains(record) ||
                op.revision <= (op.family == 'container.add' ? 2 : 1),
            isTrue,
            reason: '${op.family} r${op.revision}',
          );
        }

        Future<void> restore() async {
          await _copy('${base.path}/saved-shared', shared);
          await _copy('${base.path}/saved-main', main);
          await _copy('${base.path}/saved-peer', peer);
          await File('$shared/$peerName').writeAsBytes(prior, flush: true);
        }

        for (final own in [false, true]) {
          final profile = own ? peer : main;
          final who = own ? 'own' : 'peer';

          // Running: the old install is open when the record arrives.
          await restore();
          final warm = await reader!.ok('open', {
            'folder': shared,
            'profile': profile,
          });
          expect(warm['safety'], isNull, reason: who);
          expect(warm['records'], greaterThan(0));
          expect(warm['food'], contains('Synthetic soup'));
          await File(
            '$shared/$peerName',
          ).writeAsBytes(delivered, mode: FileMode.append, flush: true);
          final canonical = await _bytes(shared);
          await reader!.refused('refresh');
          final held = await reader!.ok('state');
          expect(held['safety'], contains(_update), reason: who);
          expect(held['rows'], warm['rows'], reason: 'Task projection');
          expect(held['food'], warm['food'], reason: 'Food projection');
          expect(held['revision'], warm['revision']);
          expect(held['commonHead'], warm['commonHead']);
          expect(held['dump'], warm['dump'], reason: 'protected heads');
          await reader!.refused('taskWrite');
          await reader!.refused('foodWrite');
          expect(await _bytes(shared), canonical, reason: '$who wrote nothing');
          expect(
            await reader!.ok('state').then((s) => s['dump']),
            warm['dump'],
          );
          await reader!.ok('close');

          // Reopen with the record already delivered: refused, stably, and
          // the shared folder keeps every byte.
          await restore();
          await File(
            '$shared/$peerName',
          ).writeAsBytes(delivered, mode: FileMode.append, flush: true);
          final preserved = await _bytes(shared);
          await reader!.refused('open', {'folder': shared, 'profile': profile});
          expect(await _bytes(shared), preserved);
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
