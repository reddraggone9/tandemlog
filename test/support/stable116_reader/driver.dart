import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

// Runs under the exact stable 2026.11.1 lib/ extracted from git, never the
// working tree's, so its answers are what an un-updated device really does.
// See food_shelf_life_old_reader_test.dart. One JSON command per stdin line.

TaskStore? store;
FoodStore? food;
NativeTextEngine? engine;
var useEngine = true;

Future<Map<String, Object?>> open(String folder, String profile) async {
  store = await TaskStore.open(
    LocalLogFolder(folder),
    profile,
    textEngine: useEngine ? engine : null,
  );
  food = await FoodStore.openUnified(store!.unified!);
  return state();
}

Future<void> close() async {
  await food?.close();
  food = null;
  await store?.close();
  store = null;
}

Map<String, Object?> state() {
  final s = store!;
  return {
    'writer': s.writer,
    'rows': jsonEncode(s.rows),
    'food': jsonEncode([
      for (final c in food!.state.active) [c.id, c.details.name],
    ]),
    'revision': s.unified!.snapshot.revision,
    'records': s.unified!.snapshot.records.length,
    'commonHead': s.unified!.commonHead,
    'decodedCacheReuses': s.unified!.decodedCacheReuses,
    'safety': s.unified!.safetyFailure?.toString(),
    'dump': dump(s.unified!.profile.database),
  };
}

/// Every profile table, including protected heads and both projections. The
/// private optional decode cache is the one thing a refused open may consume.
Map<String, Object?> dump(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    row['name'] as String: jsonEncode(
      db
          .select('SELECT * FROM "${row['name']}"')
          .where(
            (r) =>
                row['name'] != 'profile_metadata' ||
                !(r['key'] as String).startsWith('app5.decoded.'),
          )
          .map((r) => r.values.map((v) => v is List ? base64(v) : v).toList())
          .toList(),
    ),
};

String base64(List<Object?> value) => base64Encode(value.cast<int>());

Future<Map<String, Object?>> handle(Map<String, dynamic> c) async {
  switch (c['cmd']) {
    case 'seed':
      final folder = c['folder'] as String;
      useEngine = c['useEngine'] as bool;
      await open(folder, c['main'] as String);
      final user = const Uuid().v4();
      await store!.command(user, 'user.created', {'name': 'Synthetic'});
      // A dated, placed hand entry: the product has a usual location.
      await food!.add(
        const FoodDetails(
          name: 'Synthetic soup',
          expiry: '2030-01-01',
          location: 'Pantry',
        ),
        1,
      );
      final mainWriter = store!.writer;
      // Peer joins and sees everything, then both close clean: both profiles
      // hold a sealed decode cache, the state a real idle device leaves behind.
      final mainStore = store!, mainFood = food!;
      await open(folder, c['peer'] as String);
      final peerWriter = store!.writer;
      await close();
      store = mainStore;
      food = mainFood;
      await store!.refresh();
      await close();
      return {'user': user, 'mainWriter': mainWriter, 'peerWriter': peerWriter};
    case 'whoami':
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:tandemlog/storage/task_store.dart'),
      );
      return {'library': library!.toFilePath()};
    case 'open':
      return open(c['folder'] as String, c['profile'] as String);
    case 'refresh':
      await store!.refresh();
      return state();
    case 'state':
      return state();
    case 'taskWrite':
      await store!.command(const Uuid().v4(), 'user.created', {
        'name': 'Must be refused',
      });
      return {};
    case 'foodWrite':
      await food!.add(const FoodDetails(name: 'Must be refused'), 1);
      return {};
    case 'close':
      await close();
      return {};
    case 'dump':
      final db = sqlite3.open(
        '${c['profile']}/local.sqlite',
        mode: OpenMode.readOnly,
      );
      try {
        return {
          'dump': dump(db),
          'proofs': db
              .select(
                "SELECT COUNT(*) AS n FROM profile_metadata WHERE key LIKE 'app5.decoded.proof.%'",
              )
              .single['n'],
        };
      } finally {
        db.close();
      }
    default:
      throw ArgumentError('Unknown command ${c['cmd']}');
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--probe') return;
  engine = NativeTextEngine(libraryPath: args.single);
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    Map<String, Object?> reply;
    try {
      reply = {
        'ok': true,
        'value': await handle(jsonDecode(line) as Map<String, dynamic>),
      };
    } catch (e) {
      reply = {'ok': false, 'type': e.runtimeType.toString(), 'error': '$e'};
    }
    stdout.writeln(jsonEncode(reply));
  }
  await close();
  exit(0);
}
