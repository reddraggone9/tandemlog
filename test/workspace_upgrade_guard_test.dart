import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/storage/workspace_upgrade_guard.dart';

import 'unified_conversion_test.dart' as fixture;

class _ObservedFolder extends LocalLogFolder {
  _ObservedFolder(super.location);
  int writes = 0, _listsUntilPause = 0;
  Completer<void>? entered, release;
  void pauseSecondList() {
    _listsUntilPause = 2;
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<List<LogFileInfo>> list() async {
    if (_listsUntilPause > 0 && --_listsUntilPause == 0) {
      entered!.complete();
      await release!.future;
    }
    return super.list();
  }

  @override
  Future<void> append(String name, Uint8List bytes) {
    writes++;
    return super.append(name, bytes);
  }

  @override
  Future<void> create(String name, Uint8List bytes) {
    writes++;
    return super.create(name, bytes);
  }
}

class _Client {
  _Client(this.profile, this.tasks, this.food);
  final LocalProfileDatabase profile;
  final TaskStore tasks;
  final FoodStore food;
  int prepared = 0;
  Future<void> taskCommand() async {
    await tasks.command(fixture.container, 'task.edited', {
      'schedule': {'dueDate': '2030-05-02'},
    }, onPrepared: (_) => prepared++);
  }

  Future<void> foodCommand() => food.add(
    const FoodDetails(name: 'Synthetic guard beans', expiry: '2030-05-02'),
    1,
  );
  Future<void> close() async {
    await food.close();
    await tasks.close();
    await profile.close();
  }
}

void main() {
  late Directory root;
  late _ObservedFolder folder;
  late _Client owner;
  final extras = <_Client>[];
  Future<_Client> client(String writer) async {
    final profile = await LocalProfileDatabase.open(
      '${root.path}/profile-$writer',
    );
    profile.transaction(
      () => profile.database.execute(
        'INSERT INTO protected_settings VALUES (1,?,?)',
        [
          writer,
          utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
        ],
      ),
    );
    final tasks = await TaskStore.open(
      folder,
      profile.root,
      profileDatabase: profile,
      writerIdentity: writer,
    );
    final food = await FoodStore.open(
      folder,
      profile: profile,
      installationWriter: writer,
      space: fixture.space,
    );
    return _Client(profile, tasks, food);
  }

  Future<WorkspaceUpgrade> start() => WorkspaceUpgrade.start(
    folder: folder,
    profile: owner.profile,
    writer: fixture.owner,
    participants: {fixture.owner, fixture.peer},
  );
  Map<String, dynamic> journal(LocalProfileDatabase profile) =>
      jsonDecode(
            utf8.decode(
              profile.database.select(
                    'SELECT plan FROM protected_app_migrations WHERE space=?',
                    [fixture.space],
                  ).single['plan']
                  as List<int>,
            ),
          )
          as Map<String, dynamic>;
  void replaceJournal(
    LocalProfileDatabase profile,
    Map<String, dynamic> plan,
    String state,
  ) {
    profile.transaction(
      () => profile.database.execute(
        'UPDATE protected_app_migrations SET plan=?,state=? WHERE space=?',
        [utf8.encode(canonicalDataJson(plan)), state, fixture.space],
      ),
    );
  }

  Map<String, dynamic> authorities(_Client client) {
    Object? value(Object? v) => v is Uint8List ? base64Encode(v) : v;
    return {
      for (final table in [
        'protected_writer_guards',
        'protected_text_intents',
        'protected_food_intents',
        'protected_food_heads',
        'protected_app_heads',
        'protected_app_outbox',
      ])
        table: client.profile.database
            .select('SELECT * FROM $table')
            .map((row) => {for (final key in row.keys) key: value(row[key])})
            .toList(),
    };
  }

  Future<Map<String, String>> canonical() async {
    final result = <String, String>{};
    for (final file in await Directory(folder.location).list().toList()) {
      if (file is File) {
        result[file.uri.pathSegments.last] = base64Encode(
          await file.readAsBytes(),
        );
      }
    }
    return result;
  }

  Future<void> denyBoth(_Client client) async {
    final before = authorities(client), files = await canonical();
    final writes = folder.writes, prepared = client.prepared;
    final foodPrepared = client.food.lastPreparedRecords
        .map((r) => r.encode())
        .toList();
    await expectLater(client.taskCommand(), throwsA(isA<FormatFailure>()));
    await expectLater(client.foodCommand(), throwsA(isA<FormatFailure>()));
    expect(client.prepared, prepared, reason: 'No Task reservation callback.');
    expect(
      client.food.lastPreparedRecords.map((r) => r.encode()).toList(),
      foodPrepared,
    );
    expect(client.food.hasPreparedAppend, isFalse);
    expect(
      authorities(client),
      before,
      reason: 'No writer or intent reservation.',
    );
    expect(folder.writes, writes, reason: 'No canonical create or append.');
    expect(
      await canonical(),
      files,
      reason: 'Every shared file remains exact.',
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('upgrade-command-guard-');
    folder = _ObservedFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 3, 'id': fixture.space})),
      ),
    );
    for (final entry in fixture.sources().entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    owner = await client(fixture.owner);
  });
  tearDown(() async {
    for (final client in extras) {
      await client.close();
    }
    extras.clear();
    await owner.close();
    await root.delete(recursive: true);
  });

  for (final terminal in ['complete', 'aborted']) {
    for (final mutation in [
      'phase',
      'session',
      'space',
      'missing location',
      'empty location',
      'nonstring location',
      'missing consent',
      'nonbool consent',
    ]) {
      test(
        'malformed $terminal journal $mutation blocks Task and Food before reservation',
        () async {
          await start();
          final plan = journal(owner.profile);
          plan['phase'] = terminal;
          switch (mutation) {
            case 'phase':
              plan['phase'] = 'frozen';
            case 'session':
              (plan['session'] as Map)['session'] = fixture.peer;
            case 'space':
              (plan['session'] as Map)['space'] = fixture.peer;
            case 'missing location':
              plan.remove('location');
            case 'empty location':
              plan['location'] = '';
            case 'nonstring location':
              plan['location'] = 12;
            case 'missing consent':
              plan.remove('consented');
            case 'nonbool consent':
              plan['consented'] = 'true';
          }
          replaceJournal(owner.profile, plan, terminal);
          // Only the corrupted local authority can block after shared control removal.
          await folder.file(workspaceUpgradeSessionName).delete();
          expect(
            () => WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
            throwsA(isA<FormatFailure>()),
          );
          await denyBoth(owner);
        },
      );
    }
  }
  for (final mutation in [
    'missing key',
    'empty participants',
    'coordinator outside roster',
    'manifest digest',
    'source owner',
    'source kind',
  ]) {
    test(
      'malformed shared session $mutation cannot be bypassed with matching abort digest',
      () async {
        final upgrade = await start();
        await upgrade.abort();
        final session =
            jsonDecode(
                  utf8.decode(await folder.read(workspaceUpgradeSessionName)),
                )
                as Map<String, dynamic>;
        switch (mutation) {
          case 'missing key':
            session.remove('outputDigest');
          case 'empty participants':
            session['participants'] = <String>[];
          case 'coordinator outside roster':
            session['coordinator'] = fixture.container;
          case 'manifest digest':
            session['manifestDigest'] = List.filled(64, '0').join();
          case 'source owner':
            ((session['sources'] as List).first as Map)['owner'] =
                fixture.container;
          case 'source kind':
            ((session['sources'] as List).first as Map)['kind'] =
                'legacy.unknown';
        }
        final raw = utf8.encode(canonicalDataJson(session));
        await folder
            .file(workspaceUpgradeSessionName)
            .writeAsBytes(raw, flush: true);
        await folder
            .file('upgrade-${upgrade.sessionId}-aborted.json')
            .writeAsBytes(
              utf8.encode(
                canonicalDataJson({
                  'v': 1,
                  'session': upgrade.sessionId,
                  'sessionDigest': bytesDigest(raw),
                  'coordinator': session['coordinator'],
                }),
              ),
              flush: true,
            );
        expect(
          WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
          isFalse,
        );
        expect(
          () => WorkspaceUpgradeGuard.decodeSession(raw, space: fixture.space),
          throwsA(isA<FormatFailure>()),
        );
        await denyBoth(owner);
      },
    );
  }
  for (final artifact in [
    'upgrade-${fixture.space}-staging.json',
    'upgrade-malformed-staging.json',
    '${fixture.owner}.applog',
    '${fixture.owner}.applog.tmp',
  ]) {
    test('orphan $artifact blocks both ordinary v3 command adapters', () async {
      await folder.create(artifact, Uint8List.fromList(utf8.encode('{}')));
      await denyBoth(owner);
    });
  }
  test(
    'prestage cancellation releases each client only after its own journal observes abort',
    () async {
      final peer = await client(fixture.peer);
      extras.add(peer);
      final upgrade = await start();
      await WorkspaceUpgrade.open(
        folder: folder,
        profile: peer.profile,
        writer: fixture.peer,
      );
      await denyBoth(peer);
      await upgrade.abort();
      expect(
        WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
        isFalse,
      );
      expect(
        WorkspaceUpgradeGuard.isFrozen(peer.profile, fixture.space),
        isTrue,
      );
      await denyBoth(peer);
      await owner.taskCommand();
      await owner.foodCommand();
      expect(
        await WorkspaceUpgrade.open(
          folder: folder,
          profile: peer.profile,
          writer: fixture.peer,
        ),
        isNull,
      );
      expect(journal(peer.profile)['phase'], 'aborted');
      expect(
        WorkspaceUpgradeGuard.isFrozen(peer.profile, fixture.space),
        isFalse,
      );
      final before = folder.writes;
      await peer.taskCommand();
      await peer.foodCommand();
      expect(folder.writes, greaterThan(before));
    },
  );
  for (final food in [false, true]) {
    test(
      'actual command food=$food provider refresh drains before durable upgrade freeze',
      () async {
        folder.pauseSecondList();
        final command = food ? owner.foodCommand() : owner.taskCommand();
        await folder.entered!.future;
        final starting = start();
        await Future<void>.delayed(Duration.zero);
        expect(
          WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
          isFalse,
        );
        folder.release!.complete();
        await command;
        final upgrade = await starting;
        expect(
          WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
          isTrue,
        );
        final raw = food
            ? owner.food.lastPreparedRecords.single.encode()
            : owner.tasks.db.select(
                    'SELECT raw FROM ${owner.tasks.tables.events} WHERE writer=? ORDER BY seq DESC LIMIT 1',
                    [fixture.owner],
                  ).single['raw']
                  as String;
        expect(
          upgrade.conversion.originalEffects.any((effect) => effect.raw == raw),
          isTrue,
        );
        await denyBoth(owner);
      },
    );
    test(
      'actual command food=$food delayed refresh cannot reserve after durable local freeze',
      () async {
        final prior = await start();
        final frozen = journal(owner.profile);
        await prior.abort();
        for (final file in await Directory(folder.location).list().toList()) {
          if (file is File &&
              (file.uri.pathSegments.last.startsWith('upgrade-') ||
                  file.uri.pathSegments.last == workspaceUpgradeSessionName)) {
            await file.delete();
          }
        }
        final before = authorities(owner), files = await canonical();
        final writes = folder.writes, prepared = owner.prepared;
        folder.pauseSecondList();
        final command = food ? owner.foodCommand() : owner.taskCommand();
        final rejected = expectLater(command, throwsA(isA<FormatFailure>()));
        await folder.entered!.future;
        // Adversarial durable-state delivery while provider I/O awaits. Normal
        // start() uses the profile queue and is covered by the real drain case.
        replaceJournal(owner.profile, frozen, 'frozen');
        expect(
          WorkspaceUpgradeGuard.isFrozen(owner.profile, fixture.space),
          isTrue,
        );
        folder.release!.complete();
        await rejected;
        expect(owner.prepared, prepared);
        expect(owner.food.lastPreparedRecords, isEmpty);
        expect(authorities(owner), before);
        expect(folder.writes, writes);
        expect(await canonical(), files);
      },
    );
  }
}
