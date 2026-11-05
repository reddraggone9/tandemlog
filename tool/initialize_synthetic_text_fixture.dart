// QA-only: build a new current-format workload in an empty synthetic folder.
// Never invoked by the application or used to adopt retained user history.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/application/workspace_session.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_purchase_import.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Supply empty synthetic folder, NEW seed cache, native library.',
    );
  }
  final folder = LocalLogFolder(Directory(arguments[0]).absolute.path);
  final private = Directory(arguments[1]).absolute;
  final workspace = private.parent;
  final library = File(arguments[2]).absolute;
  if (await private.exists()) throw StateError('Seed cache already exists.');
  if (!await library.exists() || (await folder.list()).isNotEmpty) {
    throw StateError('Pinned library and empty synthetic folder are required.');
  }
  final spec =
      jsonDecode(
            await File(
              '${workspace.path}/synthetic-workload.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  if (spec['synthetic'] != true || ![1, 2].contains(spec['version'])) {
    throw StateError('Expected explicit synthetic workload.');
  }
  final writer = spec['writer'] as String, user = spec['user'] as String;
  final tasks = (spec['tasks'] as List).cast<Map<String, dynamic>>();
  if (!isCanonicalId(writer) || !isCanonicalId(user) || tasks.length > 10000) {
    throw StateError('Invalid synthetic identities/budget.');
  }
  final profilePath = Directory(spec['profile'] as String).absolute;
  final relative = profilePath.uri.path.substring(workspace.uri.path.length);
  if (!profilePath.uri.path.startsWith(workspace.uri.path) ||
      relative.isEmpty ||
      relative.split('/').contains('..')) {
    throw StateError(
      'Measured profile must be inside its synthetic workspace.',
    );
  }
  if (await profilePath.exists() && !(await profilePath.list().isEmpty)) {
    throw StateError('Measured profile is not empty.');
  }
  final engine = NativeTextEngine(libraryPath: library.path);
  if (spec['version'] == 2) {
    try {
      final receipt = await _seedMixed(
        folder,
        private,
        spec,
        writer,
        user,
        tasks,
        engine,
      );
      await _writeSettings(profilePath, writer, folder, user);
      stdout.writeln(
        jsonEncode({
          ...receipt,
          'settings_sha256': sha256
              .convert(_settings(writer, folder, user))
              .toString(),
          'native_sha256': sha256
              .convert(await library.readAsBytes())
              .toString(),
        }),
      );
    } finally {
      engine.dispose();
    }
    return;
  }
  TaskStore? store;
  try {
    store = await TaskStore.open(
      folder,
      private.path,
      writerIdentity: writer,
      textEngine: engine,
    );
    await store.command(user, 'user.created', {
      'name': spec['userName'] as String,
    });
    // Preserve the scalar workload, then construct its native baseline through
    // current production APIs. Chunking bounds seed-generation memory only.
    for (var offset = 0; offset < tasks.length; offset += 500) {
      final chunk = tasks.skip(offset).take(500);
      await store.unified!.appendAtomic([
        for (final task in chunk)
          (sequence, clock, head) => UnifiedEffect(
            'task',
            LogEvent(
              store!.space,
              writer,
              sequence,
              clock,
              task['id'] as String,
              'task.created',
              {
                'title': task['title'],
                'description': task['description'],
                'assignee': user,
              },
            ).encode(previousHash: head),
          ),
      ]);
    }
    final baseline = await store.initializeSharedText();
    await store.verifyHistory();
    final count = store.rows.length;
    if (!store.sharedTextInitialized || count != tasks.length + 1) {
      throw StateError('Synthetic workload admission failed.');
    }
    await store.close();
    store = null;
    // Preferences only: deliberately leave all projections/observations cold.
    final profile = await LocalProfileDatabase.open(profilePath.path);
    final settings = utf8.encode(
      jsonEncode({
        'writer': writer,
        'folder': folder.location,
        'user': user,
        'appearance': 'system',
      }),
    );
    try {
      profile.transaction(
        () => profile.database.execute(
          'INSERT INTO protected_settings VALUES(1,?,?)',
          [writer, settings],
        ),
      );
    } finally {
      await profile.close();
    }
    stdout.writeln(
      jsonEncode({
        'synthetic': true,
        'initialized': true,
        'format': 'app-action-v5',
        'baseline': baseline.id,
        'writer': writer,
        'user': user,
        'rows': count,
        'settings_sha256': sha256.convert(settings).toString(),
        'native_sha256': sha256.convert(await library.readAsBytes()).toString(),
      }),
    );
  } finally {
    await store?.close();
    engine.dispose();
  }
}

List<int> _settings(String writer, LocalLogFolder folder, String user) =>
    utf8.encode(
      jsonEncode({
        'writer': writer,
        'folder': folder.location,
        'user': user,
        'appearance': 'system',
      }),
    );

// Preferences only: deliberately leave all projections/observations cold.
Future<void> _writeSettings(
  Directory profilePath,
  String writer,
  LocalLogFolder folder,
  String user,
) async {
  final profile = await LocalProfileDatabase.open(profilePath.path);
  try {
    profile.transaction(
      () => profile.database.execute(
        'INSERT INTO protected_settings VALUES(1,?,?)',
        [writer, _settings(writer, folder, user)],
      ),
    );
  } finally {
    await profile.close();
  }
}

/// Version 2: mixed Task and Food history, one user action per record, from
/// several devices, in the proportions of a real household copy
/// (design/performance-gate.md, native cold start). Every action goes through
/// the production stores; each device has its own private seed cache. The
/// measured installation is `writer`; the others are its peers.
Future<Map<String, dynamic>> _seedMixed(
  LocalLogFolder folder,
  Directory private,
  Map<String, dynamic> spec,
  String writer,
  String user,
  List<Map<String, dynamic>> tasks,
  NativeTextEngine engine,
) async {
  final shape = (spec['history'] as Map).cast<String, dynamic>();
  int count(String key) {
    final value = shape[key];
    if (value is! int || value < 0 || value > 5000) {
      throw StateError('Invalid synthetic history count $key.');
    }
    return value;
  }

  final peers = (spec['peers'] as List).cast<String>();
  if (peers.isEmpty || peers.length > 6 || !peers.every(isCanonicalId)) {
    throw StateError('Invalid synthetic peers.');
  }
  final devices = [writer, ...peers];
  final taskEdits = count('taskEdits'),
      taskCompletions = count('taskCompletions'),
      foodAdds = count('foodAdds'),
      foodMultiAdds = count('foodMultiAdds'),
      foodRemovals = count('foodRemovals'),
      foodEdits = count('foodEdits'),
      productEdits = count('productEdits'),
      purchaseImports = count('purchaseImports'),
      purchaseLines = count('purchaseLines');
  if (taskCompletions > tasks.length ||
      foodRemovals + foodEdits > foodAdds ||
      productEdits > foodAdds ||
      foodMultiAdds > foodAdds ||
      (purchaseImports == 0) != (purchaseLines == 0) ||
      purchaseLines < purchaseImports) {
    throw StateError('Inconsistent synthetic history shape.');
  }
  // Rounds interleave the devices the way a syncing household does, so every
  // file holds both Task and Food actions.
  final steps = <(String, int)>[
    for (var i = 0; i < tasks.length; i++) ('task', i),
    for (var i = 0; i < foodAdds; i++) ('food.add', i),
    for (var i = 0; i < taskEdits; i++) ('task.edit', i),
    for (var i = 0; i < foodEdits; i++) ('food.edit', i),
    for (var i = 0; i < productEdits; i++) ('product.edit', i),
    for (var i = 0; i < purchaseImports; i++) ('purchase', i),
    for (var i = 0; i < taskCompletions; i++) ('task.complete', i),
    for (var i = 0; i < foodRemovals; i++) ('food.remove', i),
  ];
  const rounds = 4;
  final perRound = (steps.length / rounds).ceil();
  var done = 0, linesWritten = 0;
  for (var round = 0; round < rounds; round++) {
    final roundSteps = steps.skip(round * perRound).take(perRound).toList();
    for (var d = 0; d < devices.length; d++) {
      final mine = [
        for (var i = 0; i < roundSteps.length; i++)
          if (i % devices.length == d) roundSteps[i],
      ];
      if (mine.isEmpty) continue;
      final store = await TaskStore.open(
        folder,
        '${private.path}/${devices[d]}',
        writerIdentity: devices[d],
        textEngine: engine,
      );
      FoodStore? food;
      try {
        if (round == 0 && d == 0) {
          await store.command(user, 'user.created', {
            'name': spec['userName'] as String,
          });
          await store.initializeSharedText();
        }
        food = await FoodStore.openUnified(store.unified!);
        for (final (kind, i) in mine) {
          done++;
          final task = tasks[i % tasks.length];
          switch (kind) {
            case 'task':
              await store.command(task['id'] as String, 'task.created', {
                'title': task['title'],
                'description': task['description'],
                'assignee': user,
              });
            case 'task.edit':
              await store.command(task['id'] as String, 'task.edited', {
                'description': 'Synthetic startup notes, edit $i',
              });
            case 'task.complete':
              // Spread across the list so open and completed rows interleave.
              await store.command(
                tasks[(i * 7) % tasks.length]['id'] as String,
                'task.completed',
                {'completedInstant': '2026-10-${10 + i % 18}T12:00:00.000000Z'},
              );
            case 'food.add':
              await food.add(
                FoodDetails(
                  name: 'Synthetic food ${i % 430}',
                  brand: 'Synthetic brand ${i % 23}',
                  location: const ['Fridge', 'Freezer', 'Pantry', ''][i % 4],
                  expiry: i % 5 == 0
                      ? null
                      : '2026-${11 + i % 2}-${(i % 27 + 1).toString().padLeft(2, '0')}',
                  retention: i % 9 == 0 ? 'Keep frozen' : '',
                ),
                i < foodMultiAdds ? 2 + i % 3 : 1,
              );
            case 'food.edit':
              final c = _activeAt(food, i * 3);
              final own = c.ownDetails;
              await food.changeDetails(
                [c.id],
                FoodDetails(
                  name: own.name,
                  brand: own.brand,
                  expiry: own.expiry,
                  retention: own.retention,
                  size: own.size,
                  location: 'Synthetic shelf ${i % 6}',
                ),
                const ['location'],
              );
            case 'product.edit':
              final groups = food.state.groups;
              final row = groups[(i * 5) % groups.length];
              await food.changeDetails(
                row.containers.map((e) => e.id).toList(),
                row.details,
                const [],
                products: FoodProductChange(
                  roots: [row.product],
                  changes: {'brand': 'Synthetic brand edit $i'},
                ),
              );
            case 'purchase':
              final start = purchaseLines * i ~/ purchaseImports;
              final end = purchaseLines * (i + 1) ~/ purchaseImports;
              final lines = [
                for (var n = start; n < end; n++)
                  FoodPurchaseLine(
                    sourceKind: 'ynab',
                    sourceKey: 'synthetic-$i#$n',
                    date: '2026-10-${10 + i % 18}',
                    store: 'Walmart',
                    amount: 199 + n * 37 % 900,
                    quantity: 1 + n % 2,
                    name: 'Synthetic purchase ${n % 20}',
                    link: 'https://www.walmart.com/ip/${100000 + n}',
                  ),
              ];
              linesWritten += lines.length;
              await food.commitPurchaseImport(
                FoodPurchaseImportPlan(
                  space: food.space,
                  importId: _uuid('purchase:$i'),
                  sourceSha256: sha256.convert(utf8.encode('$i')).toString(),
                  lines: lines,
                ),
              );
            case 'food.remove':
              await food.remove([_activeAt(food, i * 11 + 1).id]);
          }
        }
      } finally {
        await food?.close();
        await store.close();
      }
    }
  }
  if (done != steps.length || linesWritten != purchaseLines) {
    throw StateError('Synthetic history plan was not completed.');
  }
  // Read back through the production read-only open on a fresh profile: the
  // receipt states what an installation admits, not what the writers believed
  // they wrote, and the check itself writes nothing to the folder.
  final verifyProfile = Directory('${private.path}/verify');
  await _writeSettings(verifyProfile, writer, folder, user);
  final profile = await LocalProfileDatabase.open(verifyProfile.path);
  WorkspaceSession? session;
  try {
    session = await WorkspaceSession.open(
      ReadOnlyLogFolder(folder),
      profile: profile,
      writer: writer,
      textEngine: engine,
      readOnly: true,
    );
    final check = session!.tasks, food = session.food;
    // A full audit; any damaged record or chain throws.
    await check.verifyHistory();
    {
      final families = <String, int>{};
      var records = 0;
      for (final action in session.history.snapshot.records) {
        records++;
        for (final effect in action.effects) {
          final family =
              effect.food?.currentOperation.family ??
              (effect.task == null ? effect.kind : effect.task!.type);
          families[family] = (families[family] ?? 0) + 1;
        }
      }
      final state = food.state;
      final bytes = <String, int>{};
      for (final info in await folder.list()) {
        if (info.name.endsWith('.applog')) bytes[info.name] = info.size ?? -1;
      }
      final rows = check.rows.length;
      final expectedAdded =
          foodAdds +
          List.generate(
            foodMultiAdds,
            (i) => 1 + i % 3,
          ).fold<int>(0, (a, b) => a + b) +
          List.generate(
            purchaseLines,
            (i) => 1 + i % 2,
          ).fold<int>(0, (a, b) => a + b);
      final expectedFamilies = <String, int>{
        'task.created': tasks.length,
        'task.edited': taskEdits,
        'task.completed': taskCompletions,
        'container.add': foodAdds + purchaseLines,
        'container.edit': foodEdits,
        'container.remove': foodRemovals,
        'purchase.record': purchaseLines,
      };
      if (rows != tasks.length + 1 ||
          state.active.length != expectedAdded - foodRemovals ||
          state.catalog.purchases.length != purchaseLines ||
          expectedFamilies.entries.any(
            (e) => (families[e.key] ?? 0) != e.value,
          ) ||
          (families['product.edit'] ?? 0) < productEdits ||
          bytes.length != devices.length) {
        throw StateError('Synthetic mixed workload admission failed.');
      }
      return {
        'synthetic': true,
        'initialized': true,
        'format': 'app-action-v5',
        'workload': 'mixed-v2',
        'writer': writer,
        'user': user,
        'rows': rows,
        'records': records,
        'effectFamilies': Map.fromEntries(
          families.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        ),
        'food': {
          'activeContainers': state.active.length,
          'groups': state.groups.length,
          'products': state.products.length,
          'purchases': state.catalog.purchases.length,
        },
        'files': bytes.length,
        'historyBytes': bytes.values.fold<int>(0, (a, b) => a + b),
      };
    }
  } finally {
    await session?.close(sealCache: false);
    await profile.close();
  }
}

FoodContainer _activeAt(FoodStore food, int i) {
  final active = food.state.active;
  return active[i % active.length];
}

String _uuid(String value) =>
    const Uuid().v5('8f6f2a3e-5d0e-4d8e-9a55-1b2c3d4e5f60', value);
