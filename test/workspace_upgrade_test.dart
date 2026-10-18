import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/storage/writer_guard.dart';
import 'unified_conversion_test.dart' as fixture;

const newcomer = '55555555-5555-4555-8555-555555555555';

class InterruptedFolder extends LocalLogFolder {
  InterruptedFolder(super.location);
  bool interruptManifest = false;
  final reads = <String, int>{};
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    reads[name] = (reads[name] ?? 0) + 1;
    return super.readBounded(name, maximumBytes);
  }

  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    if (interruptManifest && name == 'tandemlog-space.json') {
      interruptManifest = false;
      await file(name).writeAsBytes(bytes.take(29).toList(), flush: true);
      throw OwnedReplacementFailure(
        'Synthetic partial provider write',
        phase: 'write_or_verify',
        mayHaveChanged: true,
      );
    }
    await super.replaceOwned(name, expected, bytes);
  }
}

class BudgetFolder extends InterruptedFolder {
  BudgetFolder(
    super.location, {
    this.overFile = false,
    this.syntheticFiles = 0,
  });
  final bool overFile;
  final int syntheticFiles;
  @override
  Future<List<LogFileInfo>> list() async => [
    ...(await super.list()).map(
      (f) => f.name.endsWith('.jsonl') && overFile
          ? LogFileInfo(f.name, f.stamp, size: maximumUnifiedFileBytes + 1)
          : f,
    ),
    for (var i = 0; i < syntheticFiles; i++)
      LogFileInfo(
        '99999999-9999-4999-8999-${i.toString().padLeft(12, '0')}.jsonl',
        'synthetic-budget',
        size: maximumUnifiedFileBytes,
      ),
  ];
}

void main() {
  late Directory root;
  late InterruptedFolder folder;
  late LocalProfileDatabase ownerProfile, peerProfile, newProfile;
  late List<int> originalManifest;
  Future<LocalProfileDatabase> profile(String id) async {
    final p = await LocalProfileDatabase.open('${root.path}/profile-$id');
    p.transaction(
      () =>
          p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            id,
            utf8.encode(jsonEncode({'writer': id, 'appearance': 'system'})),
          ]),
    );
    return p;
  }

  Future<LocalProfileDatabase> profileCopyIdentityOnly(String id) async {
    final p = await LocalProfileDatabase.open(
      '${root.path}/fresh-validation-$id',
    );
    p.transaction(
      () =>
          p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            id,
            utf8.encode(jsonEncode({'writer': id, 'appearance': 'system'})),
          ]),
    );
    return p;
  }

  Future<WorkspaceUpgrade> start({Set<String>? participants}) =>
      WorkspaceUpgrade.start(
        folder: folder,
        profile: ownerProfile,
        writer: fixture.owner,
        participants: participants ?? {fixture.owner, fixture.peer},
      );
  Future<WorkspaceUpgrade> peer() async => (await WorkspaceUpgrade.open(
    folder: folder,
    profile: peerProfile,
    writer: fixture.peer,
  ))!;
  Future<void> allInput(WorkspaceUpgrade a, WorkspaceUpgrade b) async {
    await a.acknowledgeInput();
    await b.consentToUpgrade();
    await b.acknowledgeInput();
  }

  Future<void> allOutput(WorkspaceUpgrade a, WorkspaceUpgrade b) async {
    await a.acknowledgeOutput();
    await b.acknowledgeOutput();
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'workspace-upgrade-disposable-',
    );
    folder = InterruptedFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    originalManifest = utf8.encode(
      '{\n  "v": 3, "id": "${fixture.space}"\n}\n',
    );
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(originalManifest),
    );
    for (final e in fixture.sources().entries) {
      await folder.create(e.key, Uint8List.fromList(e.value));
    }
    ownerProfile = await profile(fixture.owner);
    peerProfile = await profile(fixture.peer);
    newProfile = await profile(newcomer);
  });
  tearDown(() async {
    await ownerProfile.close();
    await peerProfile.close();
    await newProfile.close();
    await root.delete(recursive: true);
  });

  test(
    'real independent profiles verify both barriers; originals and exact backup survive',
    () async {
      final a = await start(), b = await peer();
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isTrue);
      expect(WorkspaceUpgrade.isFrozen(peerProfile, fixture.space), isTrue);
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
      await a.acknowledgeInput();
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
      await b.consentToUpgrade();
      await b.acknowledgeInput();
      await a.stage();
      await a.acknowledgeOutput();
      await expectLater(a.activate(), throwsA(isA<FormatFailure>()));
      await b.acknowledgeOutput();
      await a.activate();
      await b.complete();
      await a.complete();
      expect(a.phase, 'complete');
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isFalse);
      for (final e in fixture.sources().entries) {
        expect(await folder.read(e.key), e.value);
      }
      final saved =
          jsonDecode(
                utf8.decode(
                  ownerProfile.database
                          .select('SELECT plan FROM protected_app_migrations')
                          .single['plan']
                      as List<int>,
                ),
              )
              as Map;
      expect(base64Decode(saved['manifest'] as String), originalManifest);
      for (final e in fixture.sources().entries) {
        expect(
          base64Decode((saved['sources'] as Map)[e.key] as String),
          e.value,
        );
      }
      expect(
        a.conversion.originalEffects.map((e) => e.raw).toSet(),
        fixture
            .plan()
            .prepareConversion()
            .originalEffects
            .map((e) => e.raw)
            .toSet(),
      );
    },
  );

  test('new participant has no historical ownership requirement', () async {
    final a = await start(participants: {fixture.owner, newcomer});
    expect(a.owners.contains(newcomer), isFalse);
    final b = (await WorkspaceUpgrade.open(
      folder: folder,
      profile: newProfile,
      writer: newcomer,
    ))!;
    await allInput(a, b);
    await a.stage();
    await allOutput(a, b);
    await a.activate();
    await b.complete();
    final history = await UnifiedHistory.open(
      folder,
      profile: newProfile,
      writer: newcomer,
    );
    try {
      expect(
        history.snapshot.records.any(
          (r) => r.writer == newcomer && r.effect.kind == 'writer.joined',
        ),
        isTrue,
      );
    } finally {
      await history.close();
    }
    await a.complete();
  });

  test(
    'cannot acknowledge another writer using a different protected profile',
    () async {
      await start();
      await expectLater(
        WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.peer,
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'old reader compatibility alone cannot supply an upgrade acknowledgement',
    () async {
      final a = await start();
      await a.acknowledgeInput();
      final info = (await folder.list()).singleWhere(
        (f) => f.name.endsWith('-input.json'),
      );
      final receipt =
          jsonDecode(utf8.decode(await folder.read(info.name)))
              as Map<String, dynamic>;
      receipt['writer'] = fixture.peer;
      receipt.remove('upgradeProtocol');
      final n = 'upgrade-${a.sessionId}-${fixture.peer}-input.json';
      await folder.create(
        n,
        Uint8List.fromList(utf8.encode(canonicalDataJson(receipt))),
      );
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'Food-only owner cannot be inferred by reversing deterministic UUID',
    () async {
      await folder.file('${fixture.owner}.jsonl').delete();
      final inv = await WorkspaceUpgrade.inspect(folder, writer: fixture.peer);
      expect(inv.unresolvedFoodNames, [foodLogName(foodWriter(fixture.owner))]);
      await expectLater(
        WorkspaceUpgrade.start(
          folder: folder,
          profile: peerProfile,
          writer: fixture.peer,
          participants: {fixture.peer},
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        ownerProfile.database.select('SELECT * FROM protected_app_migrations'),
        isEmpty,
      );
      final a = await WorkspaceUpgrade.start(
        folder: folder,
        profile: peerProfile,
        writer: fixture.peer,
        participants: {fixture.peer},
        knownOwners: {fixture.owner},
      );
      expect(a.owners, contains(fixture.owner));
    },
  );

  test(
    'late legacy writes invalidate existing input; safe cancellation enables fresh snapshot',
    () async {
      final a = await start(), b = await peer();
      await allInput(a, b);
      final n = '${fixture.owner}.jsonl';
      await folder.append(n, Uint8List.fromList([10]));
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
      await folder.file(n).writeAsBytes(fixture.sources()[n]!, flush: true);
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
      await a.abort();
      expect(
        await WorkspaceUpgrade.open(
          folder: folder,
          profile: peerProfile,
          writer: fixture.peer,
        ),
        isNull,
      );
      expect(WorkspaceUpgrade.isFrozen(peerProfile, fixture.space), isFalse);
      final newer = await start();
      expect(newer.sessionId, isNot(a.sessionId));
      expect(newer.inputAcknowledged, isEmpty);
    },
  );

  test(
    'safe cancel keeps exact manifest/history; cancellation forbidden after staging starts',
    () async {
      final a = await start(), b = await peer();
      await a.abort();
      expect(await folder.read('tandemlog-space.json'), originalManifest);
      expect(
        await WorkspaceUpgrade.open(
          folder: folder,
          profile: peerProfile,
          writer: fixture.peer,
        ),
        isNull,
      );
      final c = await start(), d = await peer();
      await allInput(c, d);
      await c.stage();
      await expectLater(c.abort(), throwsA(isA<FormatFailure>()));
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isTrue);
      expect(b.isParticipant, isTrue);
    },
  );

  test(
    'journal resumes exact authorized partial SAF manifest, without rewriting originals',
    () async {
      var a = await start();
      final b = await peer();
      await allInput(a, b);
      folder.interruptManifest = true;
      await expectLater(a.stage(), throwsA(isA<OwnedReplacementFailure>()));
      a = (await WorkspaceUpgrade.open(
        folder: folder,
        profile: ownerProfile,
        writer: fixture.owner,
      ))!;
      expect(a.canResumeStaging, isTrue);
      await a.stage();
      await allOutput(a, b);
      await a.activate();
      await a.complete();
      expect(a.phase, 'complete');
      expect(
        await folder.read('${fixture.owner}.jsonl'),
        fixture.sources()['${fixture.owner}.jsonl'],
      );
    },
  );

  test(
    'unrelated partial manifest cannot be repaired without matching prior write intent',
    () async {
      final a = await start(), b = await peer();
      await allInput(a, b);
      final desired = utf8.encode(a.conversion.manifest.staged().encode());
      await folder
          .file('tandemlog-space.json')
          .writeAsBytes(desired.take(20).toList(), flush: true);
      await expectLater(a.stage(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'ready publication survives peer join and append before coordinator recovery completes',
    () async {
      var a = await start();
      final b = await peer();
      await allInput(a, b);
      await a.stage();
      await allOutput(a, b);
      await expectLater(
        a.activate(
          checkpoint: (at) async {
            if (at == 'after-activation') {
              throw StateError('Synthetic process interruption');
            }
          },
        ),
        throwsStateError,
      );
      await b.complete();
      final history = await UnifiedHistory.open(
        folder,
        profile: peerProfile,
        writer: fixture.peer,
      );
      try {
        await history.renameDevice('Trial peer');
      } finally {
        await history.close();
      }
      a = (await WorkspaceUpgrade.open(
        folder: folder,
        profile: ownerProfile,
        writer: fixture.owner,
      ))!;
      expect(a.phase, 'ready');
      await a.activate(); // Must not restore an exact historical whole output.
      await a.complete();
      expect(a.phase, 'complete');
      final check = await UnifiedHistory.preflight(
        folder,
        profile: peerProfile,
        writer: fixture.peer,
      );
      expect(check.records.any((r) => r.effect.kind == 'writer.named'), isTrue);
    },
  );
  test(
    'snapshot and durable freeze drain already admitted profile work first',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final log = '${fixture.owner}.jsonl';
      final old = await folder.read(log);
      final last = LogEvent.decode(
        utf8.decode(old).trimRight().split('\n').last,
      );
      final next = LogEvent(
        fixture.space,
        fixture.owner,
        3,
        EventClock(BigInt.from(3000000000)),
        newcomer,
        'user.created',
        {'name': 'Accepted before freeze'},
        previousHash: last.hash,
      ).encode();
      final admitted = ownerProfile.serialize(() async {
        entered.complete();
        await release.future;
        await folder.append(log, Uint8List.fromList(utf8.encode('$next\n')));
      });
      await entered.future;
      final starting = start();
      await Future<void>.delayed(Duration.zero);
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isFalse);
      release.complete();
      await admitted;
      final upgrade = await starting;
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isTrue);
      expect(
        upgrade.conversion.originalEffects.any((effect) => effect.raw == next),
        isTrue,
      );
    },
  );

  test(
    'peer opening freezes safely but cannot attest before explicit local consent',
    () async {
      await start();
      final b = await peer();
      expect(b.hasLocalConsent, isFalse);
      await expectLater(b.acknowledgeInput(), throwsA(isA<FormatFailure>()));
      await b.consentToUpgrade();
      expect(b.hasLocalConsent, isTrue);
      await b.acknowledgeInput();
      final reopened = await peer();
      expect(reopened.hasLocalConsent, isTrue);
    },
  );

  test(
    'orphaned upgrade files never fall through to ordinary v3 startup',
    () async {
      await folder.create(
        'upgrade-${fixture.space}-staging.json',
        Uint8List.fromList([123, 125]),
      );
      await expectLater(
        WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'completed cold startup uses bounded activation receipt without replaying backup',
    () async {
      final a = await start(), b = await peer();
      await allInput(a, b);
      await a.stage();
      await allOutput(a, b);
      await a.activate();
      await a.complete();
      folder.reads.clear();
      expect(
        await WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ),
        isNull,
      );
      expect(
        folder.reads.keys.any(
          (name) =>
              name.endsWith('.jsonl') ||
              name.endsWith('.foodlog') ||
              name.endsWith('.applog'),
        ),
        isFalse,
      );
    },
  );
  test(
    'same locked profile cannot start a second same-UUID folder upgrade',
    () async {
      await start();
      final copy = LocalLogFolder(
        (await Directory('${root.path}/nested-copy').create()).path,
      );
      await copy.create(
        'tandemlog-space.json',
        Uint8List.fromList(originalManifest),
      );
      for (final e in fixture.sources().entries) {
        await copy.create(e.key, Uint8List.fromList(e.value));
      }
      await expectLater(
        WorkspaceUpgrade.start(
          folder: copy,
          profile: ownerProfile,
          writer: fixture.owner,
          participants: {fixture.owner},
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        (await copy.list()).any((f) => f.name == workspaceUpgradeSessionName),
        isFalse,
      );
      expect(
        ownerProfile.database.select('SELECT * FROM protected_app_migrations'),
        hasLength(1),
      );
    },
  );

  test(
    'copied own input and output receipts never replace this profile validation',
    () async {
      final a = await start(), originalPeer = await peer();
      await allInput(a, originalPeer);
      await a.stage();
      await allOutput(a, originalPeer);
      final fresh = await profileCopyIdentityOnly(fixture.peer);
      try {
        final copied = (await WorkspaceUpgrade.open(
          folder: folder,
          profile: fresh,
          writer: fixture.peer,
        ))!;
        expect(copied.hasLocalConsent, isFalse);
        expect(copied.inputAcknowledged, isNot(contains(fixture.peer)));
        expect(copied.outputAcknowledged, isNot(contains(fixture.peer)));
        await copied.consentToUpgrade();
        await copied.refresh();
        expect(copied.inputAcknowledged, isNot(contains(fixture.peer)));
        expect(copied.outputAcknowledged, isNot(contains(fixture.peer)));
        // Input is already staged. This fresh profile cannot inherit the earlier
        // validation; actual local input and output verification is required.
        await expectLater(
          copied.acknowledgeOutput(),
          throwsA(isA<FormatFailure>()),
        );
        await copied.acknowledgeInput();
        expect(copied.inputAcknowledged, contains(fixture.peer));
        expect(copied.outputAcknowledged, isNot(contains(fixture.peer)));
        await copied.acknowledgeOutput();
        expect(copied.outputAcknowledged, contains(fixture.peer));
      } finally {
        await fresh.close();
      }
    },
  );

  test(
    'copied own input can be accepted only after actual local consent and preflight',
    () async {
      final a = await start(), originalPeer = await peer();
      await allInput(a, originalPeer);
      final fresh = await profileCopyIdentityOnly(fixture.peer);
      try {
        final copy = (await WorkspaceUpgrade.open(
          folder: folder,
          profile: fresh,
          writer: fixture.peer,
        ))!;
        expect(copy.inputAcknowledged, isNot(contains(fixture.peer)));
        await copy.consentToUpgrade();
        expect(copy.inputAcknowledged, isNot(contains(fixture.peer)));
        await copy.acknowledgeInput();
        expect(copy.inputAcknowledged, contains(fixture.peer));
      } finally {
        await fresh.close();
      }
    },
  );

  test(
    'released ready v4 without new upgrade controls remains readable',
    () async {
      final conversion = fixture.plan().prepareConversion();
      await folder
          .file('tandemlog-space.json')
          .writeAsString(conversion.manifest.encode(), flush: true);
      for (final e in conversion.files.entries) {
        await folder.create(e.key, Uint8List.fromList(e.value));
      }
      expect(
        await WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ),
        isNull,
      );
      final history = await UnifiedHistory.open(
        folder,
        profile: ownerProfile,
        writer: fixture.owner,
      );
      try {
        expect(
          history.snapshot.effects
              .where((e) => e.isData)
              .map((e) => e.raw)
              .toSet(),
          conversion.originalEffects.map((e) => e.raw).toSet(),
        );
      } finally {
        await history.close();
      }
      for (final e in fixture.sources().entries) {
        expect(await folder.read(e.key), e.value);
      }
    },
  );

  test(
    'oversized source metadata is rejected before retaining any source bytes',
    () async {
      final oversized = BudgetFolder(folder.location, overFile: true);
      await expectLater(
        WorkspaceUpgrade.start(
          folder: oversized,
          profile: ownerProfile,
          writer: fixture.owner,
          participants: {fixture.owner},
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        oversized.reads.keys.any(
          (n) => n.endsWith('.jsonl') || n.endsWith('.foodlog'),
        ),
        isFalse,
      );
      expect(
        ownerProfile.database.select('SELECT * FROM protected_app_migrations'),
        isEmpty,
      );
    },
  );

  test(
    'aggregate source metadata and owner counts are bounded before source reads',
    () async {
      for (final count in [9, 257]) {
        final oversized = BudgetFolder(folder.location, syntheticFiles: count);
        await expectLater(
          WorkspaceUpgrade.start(
            folder: oversized,
            profile: ownerProfile,
            writer: fixture.owner,
            participants: {fixture.owner},
          ),
          throwsA(isA<FormatFailure>()),
        );
        expect(
          oversized.reads.keys.any(
            (n) => n.endsWith('.jsonl') || n.endsWith('.foodlog'),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'current installation empty Food genesis authority is not historical ownership',
    () async {
      final food = await FoodStore.open(
        folder,
        profile: newProfile,
        installationWriter: newcomer,
        space: fixture.space,
      );
      await food.close();
      final guards = newProfile.database.select(
        'SELECT writer,raw FROM protected_writer_guards WHERE space=?',
        [fixture.space],
      );
      expect(guards.map((r) => r['writer']), contains(foodWriter(newcomer)));
      final a = await WorkspaceUpgrade.start(
        folder: folder,
        profile: newProfile,
        writer: newcomer,
        participants: {newcomer},
      );
      expect(a.owners, isNot(contains(newcomer)));
      await a.acknowledgeInput();
      await a.stage();
      await a.acknowledgeOutput();
      await a.activate();
      await a.complete();
      expect(
        newProfile.database.select(
          'SELECT writer,raw FROM protected_writer_guards WHERE space=?',
          [fixture.space],
        ),
        guards,
      );
    },
  );

  test(
    'failed completion commit cannot make retry skip durable unfreeze',
    () async {
      final a = await start(), b = await peer();
      await allInput(a, b);
      await a.stage();
      await allOutput(a, b);
      await a.activate();
      ownerProfile.database.execute(
        "CREATE TEMP TRIGGER fail_upgrade_completion BEFORE INSERT ON protected_app_migrations WHEN NEW.state='complete' BEGIN SELECT RAISE(ABORT,'Synthetic completion commit failure'); END",
      );
      await expectLater(a.complete(), throwsException);
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isTrue);
      ownerProfile.database.execute('DROP TRIGGER fail_upgrade_completion');
      await a.complete();
      expect(WorkspaceUpgrade.isFrozen(ownerProfile, fixture.space), isFalse);
      expect(
        ownerProfile.database.select(
          'SELECT state FROM protected_app_migrations WHERE space=? AND epoch=?',
          [fixture.space, a.sessionId],
        ).single['state'],
        'complete',
      );
    },
  );

  test(
    'empty unknown foreign authority and missing positive current head still block',
    () async {
      const foreign = '66666666-6666-4666-8666-666666666666';
      await SqliteWriterGuard(newProfile).acknowledge(
        fixture.space,
        foreign,
        0,
        eventGenesisHash(fixture.space, foreign),
      );
      await expectLater(
        WorkspaceUpgrade.start(
          folder: folder,
          profile: newProfile,
          writer: newcomer,
          participants: {newcomer},
        ),
        throwsA(isA<FormatFailure>()),
      );
      newProfile.database.execute('DELETE FROM protected_writer_guards');
      await SqliteWriterGuard(
        newProfile,
      ).acknowledge(fixture.space, newcomer, 1, 'a' * 64);
      await expectLater(
        WorkspaceUpgrade.start(
          folder: folder,
          profile: newProfile,
          writer: newcomer,
          participants: {newcomer},
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        (await folder.list()).any((f) => f.name == workspaceUpgradeSessionName),
        isFalse,
      );
    },
  );

  test(
    'unknown original manifest fields reject before journal or shared mutation',
    () async {
      final raw = utf8.encode(
        jsonEncode({'v': 3, 'id': fixture.space, 'unknown': true}),
      );
      await folder.file('tandemlog-space.json').writeAsBytes(raw, flush: true);
      await expectLater(start(), throwsA(isA<FormatFailure>()));
      expect(
        ownerProfile.database.select('SELECT * FROM protected_app_migrations'),
        isEmpty,
      );
      expect(
        (await folder.list()).any((f) => f.name == workspaceUpgradeSessionName),
        isFalse,
      );
      expect(await folder.read('tandemlog-space.json'), raw);
    },
  );

  test(
    'malformed protected session cannot create a missing shared control file',
    () async {
      final a = await start();
      await folder.file(workspaceUpgradeSessionName).delete();
      final row = ownerProfile.database.select(
        'SELECT plan FROM protected_app_migrations WHERE space=? AND epoch=?',
        [fixture.space, a.sessionId],
      ).single;
      final state =
          jsonDecode(utf8.decode(row['plan'] as List<int>))
              as Map<String, dynamic>;
      (state['session'] as Map)['session'] = 'invalid-uuid';
      ownerProfile.database.execute(
        'UPDATE protected_app_migrations SET plan=? WHERE space=? AND epoch=?',
        [utf8.encode(canonicalDataJson(state)), fixture.space, a.sessionId],
      );
      final before = (await folder.list()).map((f) => f.name).toSet();
      await expectLater(
        WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect((await folder.list()).map((f) => f.name).toSet(), before);
    },
  );

  test(
    'unbound protected publication intent cannot repair partial shared bytes',
    () async {
      final a = await start();
      final original = await folder.read(workspaceUpgradeSessionName);
      final partial = original.take(23).toList();
      await folder
          .file(workspaceUpgradeSessionName)
          .writeAsBytes(partial, flush: true);
      final row = ownerProfile.database.select(
        'SELECT plan FROM protected_app_migrations WHERE space=? AND epoch=?',
        [fixture.space, a.sessionId],
      ).single;
      final state =
          jsonDecode(utf8.decode(row['plan'] as List<int>))
              as Map<String, dynamic>;
      final foreignSession = Map<String, dynamic>.from(state['session'] as Map);
      foreignSession['session'] = '77777777-7777-4777-8777-777777777777';
      (state['sessionPublication'] as Map)['desired'] = base64Encode(
        utf8.encode(canonicalDataJson(foreignSession)),
      );
      ownerProfile.database.execute(
        'UPDATE protected_app_migrations SET plan=? WHERE space=? AND epoch=?',
        [utf8.encode(canonicalDataJson(state)), fixture.space, a.sessionId],
      );
      await expectLater(
        WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(await folder.read(workspaceUpgradeSessionName), partial);
    },
  );
  for (final mode in ['missing', 'partial']) {
    test(
      'foreign actual manifest prevents $mode control repair without any writes',
      () async {
        await start();
        if (mode == 'missing') {
          await folder.file(workspaceUpgradeSessionName).delete();
        } else {
          final raw = await folder.read(workspaceUpgradeSessionName);
          await folder
              .file(workspaceUpgradeSessionName)
              .writeAsBytes(raw.take(23).toList(), flush: true);
        }
        await folder
            .file('tandemlog-space.json')
            .writeAsString(jsonEncode({'v': 3, 'id': newcomer}), flush: true);
        final before = <String, List<int>>{};
        for (final info in await folder.list()) {
          before[info.name] = await folder.read(info.name);
        }
        await expectLater(
          WorkspaceUpgrade.open(
            folder: folder,
            profile: ownerProfile,
            writer: fixture.owner,
          ),
          throwsA(isA<FormatFailure>()),
        );
        final after = <String, List<int>>{};
        for (final info in await folder.list()) {
          after[info.name] = await folder.read(info.name);
        }
        expect(after, before);
      },
    );
  }
}
