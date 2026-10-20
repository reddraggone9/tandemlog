import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/workspace_capabilities.dart';

const _writer = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
const _space = '11111111-1111-4111-8111-111111111111';
const _epoch = '44444444-4444-4444-8444-444444444444';
const _manifest = 'tandemlog-space.json';

/// Synthetic provider faults, not evidence of native SAF acceptance.
class _FaultFolder extends LocalLogFolder {
  _FaultFolder(super.location);
  int replaces = 0, recoveries = 0, reads = 0;
  int? prefix;
  bool unknownFull = false, corruptReadback = false;
  bool denyRead = false, denyPreflight = false, duplicate = false;
  String? Function()? journalPhase;
  final phasesAtWrite = <String?>[];

  @override
  Future<List<LogFileInfo>> list() async {
    final names = await super.list();
    if (duplicate) names.add(LogFileInfo(_manifest, 'duplicate'));
    return names;
  }

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    reads++;
    if (denyRead && name == _manifest) {
      throw FolderAccessFailure('Synthetic grant loss');
    }
    return super.readBounded(name, maximumBytes);
  }

  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) {
    if (denyPreflight) {
      throw OwnedReplacementFailure(
        'Synthetic unsupported provider',
        phase: 'check',
        mayHaveChanged: false,
      );
    }
    return super.checkReplacementSupport(name, maximumBytes);
  }

  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    replaces++;
    phasesAtWrite.add(journalPhase?.call());
    final cut = prefix;
    prefix = null;
    if (cut != null || unknownFull || corruptReadback) {
      final full = unknownFull, corrupt = corruptReadback;
      unknownFull = false;
      corruptReadback = false;
      await file(name).writeAsBytes(
        corrupt ? [42] : bytes.take(cut ?? bytes.length).toList(),
        flush: true,
      );
      if (corrupt) return;
      throw OwnedReplacementFailure(
        full
            ? 'Synthetic unconfirmed full write'
            : 'Synthetic interrupted write',
        phase: 'write',
        mayHaveChanged: true,
      );
    }
    await super.replaceOwned(name, expected, bytes);
  }

  @override
  Future<void> recoverOwned(String name, Uint8List expected, Uint8List bytes) {
    recoveries++;
    return super.recoverOwned(name, expected, bytes);
  }
}

/// Models a checked provider without desktop temporary-file recovery.
class _CheckedOnlyFolder
    implements LogFolder, BoundedLogFolder, CheckedReplaceLogFolder {
  _CheckedOnlyFolder(this.inner);
  final _FaultFolder inner;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) =>
      inner.checkReplacementSupport(name, maximumBytes);
  @override
  Future<void> replaceOwned(String name, Uint8List expected, Uint8List bytes) =>
      inner.replaceOwned(name, expected, bytes);
}

void main() {
  late Directory root;
  late _FaultFolder folder;
  late LocalProfileDatabase profile;
  late String base, target, genesis;

  String protectedRaw() =>
      profile.database.select(
            'SELECT manifest FROM protected_app_workspaces WHERE space=?',
            [_space],
          ).single['manifest']
          as String;

  String? phase() {
    final rows = profile.database.select(
      'SELECT state FROM protected_workspace_capabilities',
    );
    return rows.isEmpty ? null : rows.single['state'] as String;
  }

  Map<String, dynamic> journal() => Map<String, dynamic>.from(
    jsonDecode(
          utf8.decode(
            profile.database
                    .select(
                      'SELECT journal FROM protected_workspace_capabilities',
                    )
                    .single['journal']
                as List<int>,
          ),
        )
        as Map,
  );

  String retainedAuthority() => canonicalDataJson({
    for (final entry in {
      'workspace': 'SELECT space,epoch,observed FROM protected_app_workspaces',
      'heads': 'SELECT * FROM protected_app_heads',
      'outbox': 'SELECT * FROM protected_app_outbox',
    }.entries)
      entry.key: [
        for (final row in profile.database.select(entry.value))
          Map<String, Object?>.from(row),
      ],
  });

  Future<void> enable({bool confirmed = true, LogFolder? provider}) =>
      profile.serialize(
        () => replaceOwnedTimeZoneCapabilityInProfileQueue(
          profile: profile,
          folder: provider ?? folder,
          writer: _writer,
          expectedRaw: base,
          targetRaw: target,
          confirmed: confirmed,
        ),
      );

  Future<void> adopt() => profile.serialize(
    () => prepareTimeZoneCapabilityAdoptionInProfileQueue(
      profile: profile,
      folder: folder,
      writer: _writer,
      expectedRaw: base,
      targetRaw: target,
    ),
  );

  void complete() => completeTimeZoneCapabilityTransitionInTransaction(
    profile: profile,
    space: _space,
    epoch: _epoch,
    writer: _writer,
    location: folder.location,
    expectedRaw: base,
    targetRaw: target,
  );

  WorkspaceCapabilityTransition? validate(String raw) =>
      validateCurrentWorkspaceCapabilitiesInProfileQueue(
        profile: profile,
        writer: _writer,
        location: folder.location,
        actualRaw: raw,
      );

  Future<void> resume({LogFolder? provider, String writer = _writer}) =>
      resumeOwnedWorkspaceCapabilitiesBeforeOpen(
        profile: profile,
        folder: provider ?? folder,
        writer: writer,
      );

  Future<bool> ownedPending() => hasOwnedPendingWorkspaceCapabilities(
    profile: profile,
    writer: _writer,
    location: folder.location,
  );

  void reserveCompatibleReceipt() {
    final record = UnifiedRecord(
      space: _space,
      epoch: _epoch,
      writer: _writer,
      sequence: 1,
      clock: EventClock(BigInt.one),
      previousHash: genesis,
      effect: UnifiedEffect.named('Compatible reserved name'),
      transactionStart: 1,
      transactionCount: 1,
      transactionIndex: 0,
      observed: {_writer: UnifiedFrontier(0, genesis)},
    );
    profile.transaction(
      () => profile.database.execute(
        'INSERT INTO protected_app_outbox VALUES (?,?,?,?,?,?,?,?)',
        [
          _space,
          _epoch,
          _writer,
          0,
          genesis,
          0,
          bytesDigest([]),
          utf8.encode('${record.encode()}\n'),
        ],
      ),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capability-journal-');
    folder = _FaultFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    genesis = unifiedGenesis(_space, _epoch, _writer);
    final manifest = UnifiedManifest(
      _space,
      _epoch,
      bytesDigest(utf8.encode('synthetic source')),
      {
        _writer: {'count': 0, 'head': genesis, 'digest': bytesDigest([])},
      },
      [],
    );
    base = manifest.encode();
    target = manifest.withAdditionalTimeZones().encode();
    await folder.create(_manifest, Uint8List.fromList(utf8.encode(base)));
    await folder.create(unifiedLogName(_writer), Uint8List(0));
    profile.transaction(() {
      profile.database.execute(
        'INSERT INTO protected_settings VALUES (1,?,?)',
        [
          _writer,
          utf8.encode(jsonEncode({'writer': _writer, 'appearance': 'system'})),
        ],
      );
      profile.database.execute(
        'INSERT INTO protected_app_workspaces VALUES (?,?,?,?)',
        [
          _space,
          _epoch,
          base,
          canonicalDataJson([_writer]),
        ],
      );
      profile.database.execute(
        'INSERT INTO protected_app_heads VALUES (?,?,?,?,?,?,?,?)',
        [_space, _epoch, _writer, 0, genesis, 0, bytesDigest([]), 0],
      );
    });
    folder.journalPhase = phase;
  });

  tearDown(() async {
    await profile.close();
    await root.delete(recursive: true);
  });

  test(
    'explicit consent is required before intent or provider mutation',
    () async {
      await expectLater(enable(confirmed: false), throwsArgumentError);
      expect(phase(), isNull);
      expect(folder.replaces, 0);
      expect(await folder.file(_manifest).readAsString(), base);
    },
  );

  test(
    'unsupported provider preflight leaves no intent or changed manifest',
    () async {
      folder.denyPreflight = true;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      expect(phase(), isNull);
      expect(folder.replaces, 0);
      expect(protectedRaw(), base);
    },
  );

  test(
    'intent precedes write; full admission alone promotes protected raw',
    () async {
      final before = retainedAuthority();
      await enable();
      expect(folder.phasesAtWrite, ['replacing']);
      expect(await folder.file(_manifest).readAsString(), target);
      expect(protectedRaw(), base);
      expect(phase(), 'replacing');
      expect(validate(target)!.role, WorkspaceCapabilityRole.initiator);
      expect(() => validate(base), throwsA(isA<FormatFailure>()));
      expect(retainedAuthority(), before);
      profile.transaction(complete);
      expect(protectedRaw(), target);
      expect(phase(), 'complete');
      expect(retainedAuthority(), before);
      await enable();
      profile.transaction(complete);
      expect(folder.replaces, 1);
    },
  );

  test('promotion outside SQL admission transaction is refused', () async {
    await enable();
    expect(complete, throwsStateError);
    expect(protectedRaw(), base);
    expect(phase(), 'replacing');
  });

  test(
    'failed projection transaction rolls back protected raw and completion',
    () async {
      await enable();
      final before = retainedAuthority();
      expect(
        () => profile.transaction(() {
          complete();
          throw StateError('Synthetic projection failure');
        }),
        throwsStateError,
      );
      expect(protectedRaw(), base);
      expect(phase(), 'replacing');
      expect(retainedAuthority(), before);
      profile.transaction(complete);
      expect(protectedRaw(), target);
    },
  );

  test(
    'journal completion SQL failure also rolls back protected promotion',
    () async {
      await enable();
      profile.database.execute(
        "CREATE TEMP TRIGGER fail_complete BEFORE UPDATE ON protected_workspace_capabilities "
        "WHEN NEW.state='complete' BEGIN SELECT RAISE(ABORT,'synthetic completion'); END",
      );
      expect(() => profile.transaction(complete), throwsA(anything));
      expect(protectedRaw(), base);
      expect(phase(), 'replacing');
      profile.database.execute('DROP TRIGGER fail_complete');
      profile.transaction(complete);
      expect(protectedRaw(), target);
    },
  );

  test(
    'adopter keeps old-compatible receipt and never repairs physical bytes',
    () async {
      reserveCompatibleReceipt();
      final before = retainedAuthority();
      await folder.file(_manifest).writeAsString(target, flush: true);
      await adopt();
      expect(journal()['consented'], false);
      expect(phase(), 'adopting');
      expect(await ownedPending(), false);
      expect(protectedRaw(), base);
      await folder
          .file(_manifest)
          .writeAsBytes(utf8.encode(target).take(19).toList(), flush: true);
      await resume();
      expect(folder.replaces, 0);
      expect(folder.recoveries, 0);
      expect(await folder.file(_manifest).length(), 19);
      expect(retainedAuthority(), before);
      expect(() => validate(base), throwsA(isA<FormatFailure>()));
      await folder.file(_manifest).writeAsString(target, flush: true);
      profile.transaction(complete);
      expect(protectedRaw(), target);
      expect(retainedAuthority(), before);
    },
  );

  test(
    'initiator with exact pending save cannot prepare capability intent',
    () async {
      reserveCompatibleReceipt();
      final before = retainedAuthority();
      await expectLater(enable(), throwsA(isA<FormatFailure>()));
      expect(phase(), isNull);
      expect(folder.replaces, 0);
      expect(retainedAuthority(), before);
    },
  );

  for (final prefix in [0, 17]) {
    test(
      'cold owned recovery repairs exact desired prefix $prefix only',
      () async {
        final before = retainedAuthority();
        folder.prefix = prefix;
        await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
        expect(phase(), 'replacing');
        expect(await folder.file(_manifest).length(), prefix);
        await profile.close();
        profile = await LocalProfileDatabase.open('${root.path}/profile');
        expect(await ownedPending(), true);
        await resume();
        expect(folder.recoveries, 1);
        expect(await folder.file(_manifest).readAsString(), target);
        expect(protectedRaw(), base);
        expect(phase(), 'replacing');
        expect(retainedAuthority(), before);
        profile.transaction(complete);
        expect(protectedRaw(), target);
      },
    );
  }

  test(
    'checked-only provider retains exact prefix bytes before partial repair',
    () async {
      final checked = _CheckedOnlyFolder(folder);
      folder.prefix = 13;
      await expectLater(
        enable(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      expect(journal()['interruptedPrefixLengths'], isEmpty);
      await resume(provider: checked);
      expect(folder.recoveries, 0);
      expect(folder.replaces, 2);
      expect(journal()['interruptedPrefixLengths'], [13]);
      expect(
        utf8.encode(journal()['targetRaw'] as String).take(13).toList(),
        utf8.encode(target).take(13).toList(),
      );
      expect(await folder.file(_manifest).readAsString(), target);
      expect(protectedRaw(), base);
      expect(phase(), 'replacing');
      profile.transaction(complete);
      expect(journal()['interruptedPrefixLengths'], [13]);
    },
  );

  test(
    'failed durable prefix evidence leaves provider and partial bytes untouched',
    () async {
      final checked = _CheckedOnlyFolder(folder);
      folder.prefix = 17;
      await expectLater(
        enable(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      profile.database.execute(
        "CREATE TEMP TRIGGER fail_prefix BEFORE UPDATE ON protected_workspace_capabilities "
        "BEGIN SELECT RAISE(ABORT,'synthetic evidence failure'); END",
      );
      await expectLater(resume(provider: checked), throwsA(anything));
      expect(folder.replaces, 1);
      expect(journal()['interruptedPrefixLengths'], isEmpty);
      expect(
        await folder.file(_manifest).readAsBytes(),
        utf8.encode(target).take(17).toList(),
      );
      profile.database.execute('DROP TRIGGER fail_prefix');
      await resume(provider: checked);
      expect(journal()['interruptedPrefixLengths'], [17]);
      expect(await folder.file(_manifest).readAsString(), target);
    },
  );

  test(
    'repeated checked-only interruptions retain every distinct exact prefix',
    () async {
      final checked = _CheckedOnlyFolder(folder);
      folder.prefix = 0;
      await expectLater(
        enable(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      folder.prefix = 17;
      await expectLater(
        resume(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      expect(journal()['interruptedPrefixLengths'], [0]);
      folder.prefix = 17;
      await expectLater(
        resume(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      expect(journal()['interruptedPrefixLengths'], [0, 17]);
      await resume(provider: checked);
      expect(journal()['interruptedPrefixLengths'], [0, 17]);
      profile.transaction(complete);
      expect(journal()['interruptedPrefixLengths'], [0, 17]);
    },
  );

  test(
    'bounded prefix evidence refuses unseen overflow but permits known prefix',
    () async {
      final manifest = UnifiedManifest.decode(base);
      final owners = Map<String, Map<String, dynamic>>.of(manifest.owners);
      for (var i = 0; i < 8; i++) {
        final owner =
            "00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}";
        owners[owner] = {
          'count': 0,
          'head': unifiedGenesis(_space, _epoch, owner),
          'digest': bytesDigest([]),
        };
      }
      final larger = UnifiedManifest(
        _space,
        _epoch,
        manifest.sourceDigest,
        owners,
        [],
      );
      base = larger.encode();
      target = larger.withAdditionalTimeZones().encode();
      expect(utf8.encode(target).length, greaterThan(1025));
      profile.database.execute(
        'UPDATE protected_app_workspaces SET manifest=?',
        [base],
      );
      await folder.file(_manifest).writeAsString(base, flush: true);
      final checked = _CheckedOnlyFolder(folder);
      folder.prefix = 0;
      await expectLater(
        enable(provider: checked),
        throwsA(isA<OwnedReplacementFailure>()),
      );
      final changed = journal();
      changed['interruptedPrefixLengths'] = List.generate(1024, (n) => n);
      profile.database.execute(
        'UPDATE protected_workspace_capabilities SET journal=?',
        [utf8.encode(canonicalDataJson(changed))],
      );
      await folder
          .file(_manifest)
          .writeAsBytes(utf8.encode(target).take(1024).toList(), flush: true);
      await expectLater(
        resume(provider: checked),
        throwsA(isA<FormatFailure>()),
      );
      expect(folder.replaces, 1);
      expect(await folder.file(_manifest).length(), 1024);
      expect((journal()['interruptedPrefixLengths'] as List).length, 1024);
      await folder
          .file(_manifest)
          .writeAsBytes(utf8.encode(target).take(1).toList(), flush: true);
      await resume(provider: checked);
      expect(await folder.file(_manifest).readAsString(), target);
      expect((journal()['interruptedPrefixLengths'] as List).length, 1024);
    },
  );

  test(
    'unconfirmed complete write is observed without a second replacement',
    () async {
      folder.unknownFull = true;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      await resume();
      expect(folder.replaces, 1);
      expect(folder.recoveries, 0);
      expect(protectedRaw(), base);
      expect(phase(), 'replacing');
    },
  );

  test(
    'local resume discovery survives grant loss and performs no provider reads',
    () async {
      folder.prefix = 0;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      folder.denyRead = true;
      final reads = folder.reads;
      expect(await ownedPending(), true);
      expect(folder.reads, reads);
      await expectLater(resume(), throwsA(isA<FolderAccessFailure>()));
      expect(phase(), 'replacing');
      expect(protectedRaw(), base);
      folder.denyRead = false;
      await resume();
      profile.transaction(complete);
      expect(await ownedPending(), false);
    },
  );

  test('unknown readback and later divergent bytes are preserved', () async {
    folder.corruptReadback = true;
    await expectLater(enable(), throwsA(isA<FormatFailure>()));
    await expectLater(resume(), throwsA(isA<FormatFailure>()));
    expect(await folder.file(_manifest).readAsBytes(), [42]);
    expect(folder.replaces, 1);
    expect(protectedRaw(), base);
    expect(phase(), 'replacing');
  });

  test('ambiguous duplicate target is rejected before any intent', () async {
    folder.duplicate = true;
    await expectLater(enable(), throwsA(isA<FormatFailure>()));
    expect(phase(), isNull);
    expect(folder.replaces, 0);
  });

  test('failed durable intent cannot precede a physical write', () async {
    profile.database.execute(
      "CREATE TEMP TRIGGER fail_intent BEFORE INSERT ON protected_workspace_capabilities "
      "BEGIN SELECT RAISE(ABORT,'synthetic intent'); END",
    );
    await expectLater(enable(), throwsA(anything));
    expect(phase(), isNull);
    expect(folder.replaces, 0);
    expect(await folder.file(_manifest).readAsString(), base);
  });

  test(
    'prepared phase cannot authorize partial bytes until replacing commits',
    () async {
      profile.database.execute(
        "CREATE TEMP TRIGGER fail_replacing BEFORE UPDATE ON protected_workspace_capabilities "
        "WHEN NEW.state='replacing' BEGIN SELECT RAISE(ABORT,'synthetic replacing'); END",
      );
      await expectLater(enable(), throwsA(anything));
      expect(phase(), 'prepared');
      expect(folder.replaces, 0);
      profile.database.execute('DROP TRIGGER fail_replacing');
      await folder
          .file(_manifest)
          .writeAsBytes(utf8.encode(target).take(7).toList(), flush: true);
      await expectLater(resume(), throwsA(isA<FormatFailure>()));
      expect(await folder.file(_manifest).length(), 7);
      await folder.file(_manifest).writeAsString(base, flush: true);
      await resume();
      expect(folder.phasesAtWrite, ['replacing']);
      expect(protectedRaw(), base);
    },
  );

  test(
    'owned desktop recovery archives exact interrupted temporary prefix',
    () async {
      folder.prefix = 11;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      final partial = utf8.encode(target).take(29).toList();
      await folder.file('$_manifest.tmp').writeAsBytes(partial, flush: true);
      await resume();
      final archives = (await folder.list())
          .where((entry) => entry.name.startsWith('$_manifest.recovery-'))
          .toList();
      expect(archives, hasLength(1));
      expect(await folder.read(archives.single.name), partial);
      expect(await folder.file('$_manifest.tmp').exists(), false);
      expect(await folder.file(_manifest).readAsString(), target);
      expect(protectedRaw(), base);
    },
  );

  test(
    'unknown desktop temporary bytes are preserved and block recovery',
    () async {
      folder.prefix = 0;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      await folder.file('$_manifest.tmp').writeAsBytes([255, 17], flush: true);
      await expectLater(resume(), throwsA(isA<OwnedReplacementFailure>()));
      expect(await folder.file('$_manifest.tmp').readAsBytes(), [255, 17]);
      expect(await folder.file(_manifest).length(), 0);
      expect(protectedRaw(), base);
    },
  );

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'version': (j) => j['v'] = 2,
    'kind': (j) => j['kind'] = 'unknown',
    'feature': (j) => j['feature'] = 'unknown',
    'writer': (j) => j['writer'] = _other,
    'consent': (j) => j['consented'] = false,
    'role': (j) => j['role'] = 'adopter',
    'phase': (j) => j['phase'] = 'prepared',
    'digest': (j) => j['targetDigest'] = List.filled(64, '0').join(),
    'base bytes': (j) => j['baseRaw'] = "${j['baseRaw']} ",
    'target bytes': (j) => j['targetRaw'] = "${j['targetRaw']} ",
    'unknown key': (j) => j['unknown'] = true,
    'non-list prefix evidence': (j) => j['interruptedPrefixLengths'] = '0',
    'duplicate prefix evidence': (j) => j['interruptedPrefixLengths'] = [0, 0],
    'negative prefix evidence': (j) => j['interruptedPrefixLengths'] = [-1],
    'float prefix evidence': (j) => j['interruptedPrefixLengths'] = [0.5],
    'full-length prefix evidence': (j) => j['interruptedPrefixLengths'] = [
      utf8.encode(j['targetRaw'] as String).length,
    ],
    'unbounded prefix evidence': (j) =>
        j['interruptedPrefixLengths'] = List.filled(1025, 0),
  };
  for (final entry in corruptions.entries) {
    test(
      'corrupt terminal journal ${entry.key} blocks read and resume discovery',
      () async {
        await enable();
        profile.transaction(complete);
        final changed = journal();
        entry.value(changed);
        profile.database
            .execute('UPDATE protected_workspace_capabilities SET journal=?', [
              utf8.encode(
                entry.key == 'float prefix evidence'
                    ? jsonEncode(changed)
                    : canonicalDataJson(changed),
              ),
            ]);
        expect(() => validate(target), throwsA(isA<FormatFailure>()));
        await expectLater(ownedPending(), throwsA(isA<FormatFailure>()));
        expect(protectedRaw(), target);
        expect(await folder.file(_manifest).readAsString(), target);
      },
    );
  }

  test(
    'prepared and adopter journals cannot manufacture repair byte evidence',
    () async {
      await folder.file(_manifest).writeAsString(target, flush: true);
      await adopt();
      final changed = journal();
      changed['interruptedPrefixLengths'] = [0];
      profile.database.execute(
        'UPDATE protected_workspace_capabilities SET journal=?',
        [utf8.encode(canonicalDataJson(changed))],
      );
      await expectLater(ownedPending(), throwsA(isA<FormatFailure>()));
      expect(folder.replaces, 0);
    },
  );

  test('prepared initiator cannot contain interrupted prefix evidence', () async {
    profile.database.execute(
      "CREATE TEMP TRIGGER fail_replacing BEFORE UPDATE ON protected_workspace_capabilities "
      "WHEN NEW.state='replacing' BEGIN SELECT RAISE(ABORT,'synthetic replacing'); END",
    );
    await expectLater(enable(), throwsA(anything));
    expect(phase(), 'prepared');
    profile.database.execute('DROP TRIGGER fail_replacing');
    final changed = journal();
    changed['interruptedPrefixLengths'] = [0];
    profile.database.execute(
      'UPDATE protected_workspace_capabilities SET journal=?',
      [utf8.encode(canonicalDataJson(changed))],
    );
    await expectLater(resume(), throwsA(isA<FormatFailure>()));
    expect(folder.replaces, 0);
    expect(await folder.file(_manifest).readAsString(), base);
  });

  test(
    'normal admission rejects another location even for completed journal',
    () async {
      await enable();
      profile.transaction(complete);
      expect(
        () => validateCurrentWorkspaceCapabilitiesInProfileQueue(
          profile: profile,
          writer: _writer,
          location: '${folder.location}-other',
          actualRaw: target,
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'activated profile rejects rollback and completed intent never repairs',
    () async {
      await enable();
      profile.transaction(complete);
      await folder.file(_manifest).writeAsString(base, flush: true);
      expect(() => validate(base), throwsA(isA<FormatFailure>()));
      await resume();
      expect(folder.replaces, 1);
      expect(await folder.file(_manifest).readAsString(), base);
      expect(protectedRaw(), target);
      expect(phase(), 'complete');
    },
  );

  test(
    'different installation cannot use retained initiating consent',
    () async {
      folder.prefix = 0;
      await expectLater(enable(), throwsA(isA<OwnedReplacementFailure>()));
      await expectLater(resume(writer: _other), throwsA(isA<FormatFailure>()));
      expect(folder.recoveries, 0);
      expect(await folder.file(_manifest).length(), 0);
      expect(protectedRaw(), base);
    },
  );
}
