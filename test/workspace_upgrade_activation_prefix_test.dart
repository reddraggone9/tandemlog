import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';

import 'unified_conversion_test.dart' as fixture;

class _InterruptedActivationFolder extends LocalLogFolder {
  _InterruptedActivationFolder(super.location);
  bool interruptManifest = false;
  int interruptedPrefixLength = 29;
  int replacementCalls = 0;
  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    replacementCalls++;
    if (interruptManifest && name == 'tandemlog-space.json') {
      interruptManifest = false;
      await file(
        name,
      ).writeAsBytes(bytes.take(interruptedPrefixLength).toList(), flush: true);
      throw OwnedReplacementFailure(
        'Synthetic activation prefix interruption',
        phase: 'write_or_verify',
        mayHaveChanged: true,
      );
    }
    await super.replaceOwned(name, expected, bytes);
  }
}

void main() {
  late Directory root;
  late _InterruptedActivationFolder folder;
  late LocalProfileDatabase ownerProfile, peerProfile;
  late List<int> originalManifest;
  Future<LocalProfileDatabase> profile(String writer) async {
    final p = await LocalProfileDatabase.open('${root.path}/profile-$writer');
    p.transaction(
      () =>
          p.database.execute('INSERT INTO protected_settings VALUES (1,?,?)', [
            writer,
            utf8.encode(jsonEncode({'writer': writer, 'appearance': 'system'})),
          ]),
    );
    return p;
  }

  Future<WorkspaceUpgrade> start() => WorkspaceUpgrade.start(
    folder: folder,
    profile: ownerProfile,
    writer: fixture.owner,
    participants: {fixture.owner, fixture.peer},
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
    root = await Directory.systemTemp.createTemp('upgrade-activation-prefix-');
    folder = _InterruptedActivationFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    originalManifest = utf8.encode(jsonEncode({'v': 3, 'id': fixture.space}));
    await folder.create(
      'tandemlog-space.json',
      Uint8List.fromList(originalManifest),
    );
    for (final entry in fixture.sources().entries) {
      await folder.create(entry.key, Uint8List.fromList(entry.value));
    }
    ownerProfile = await profile(fixture.owner);
    peerProfile = await profile(fixture.peer);
  });
  tearDown(() async {
    await ownerProfile.close();
    await peerProfile.close();
    await root.delete(recursive: true);
  });

  for (final prefixLength in [0, 1, 29, -1]) {
    test(
      'cold activating recovery preflights exact journal prefix $prefixLength before repair',
      () async {
        var a = await start();
        final b = await peer();
        await allInput(a, b);
        await a.stage();
        await allOutput(a, b);
        final desired = utf8.encode(a.conversion.manifest.encode());
        folder.interruptedPrefixLength = prefixLength < 0
            ? desired.length - 1
            : prefixLength;
        folder.interruptManifest = true;
        await expectLater(
          a.activate(),
          throwsA(isA<OwnedReplacementFailure>()),
        );
        final retained = await folder.read('tandemlog-space.json');
        expect(retained, desired.take(folder.interruptedPrefixLength).toList());
        final profileRoot = ownerProfile.root;
        await ownerProfile.close();
        ownerProfile = await LocalProfileDatabase.open(profileRoot);
        a = (await WorkspaceUpgrade.open(
          folder: folder,
          profile: ownerProfile,
          writer: fixture.owner,
        ))!;
        expect(a.canResumeActivation, isTrue);
        await a.activate();
        await a.complete();
        await b.complete();
        expect(await folder.read('tandemlog-space.json'), desired);
        expect(a.phase, 'complete');
        for (final entry in fixture.sources().entries) {
          expect(await folder.read(entry.key), entry.value);
        }
        for (final entry in a.conversion.files.entries) {
          expect(await folder.read(entry.key), entry.value);
        }
      },
    );
  }

  for (final corruption in [
    'missing row',
    'missing intent',
    'wrong expected',
    'wrong desired',
    'extra intent key',
    'wrong phase',
    'wrong session',
    'wrong location',
    'no consent',
    'foreign bytes',
    'capability prefix',
  ]) {
    test(
      'activating preview refuses $corruption without provider or authority changes',
      () async {
        final a = await start(), b = await peer();
        await allInput(a, b);
        await a.stage();
        await allOutput(a, b);
        folder.interruptManifest = true;
        await expectLater(
          a.activate(),
          throwsA(isA<OwnedReplacementFailure>()),
        );
        final row = ownerProfile.database.select(
          'SELECT plan,state FROM protected_app_migrations WHERE space=? AND epoch=?',
          [fixture.space, a.sessionId],
        ).single;
        final saved =
            jsonDecode(utf8.decode(row['plan'] as List<int>))
                as Map<String, dynamic>;
        var phase = row['state'] as String;
        switch (corruption) {
          case 'missing row':
            ownerProfile.database.execute(
              'DELETE FROM protected_app_migrations WHERE space=? AND epoch=?',
              [fixture.space, a.sessionId],
            );
          case 'missing intent':
            saved.remove('replacement');
          case 'wrong expected':
            (saved['replacement'] as Map)['expected'] = base64Encode(
              originalManifest,
            );
          case 'wrong desired':
            (saved['replacement'] as Map)['desired'] = base64Encode(
              utf8.encode(a.conversion.manifest.staged().encode()),
            );
          case 'extra intent key':
            (saved['replacement'] as Map)['extra'] = true;
          case 'wrong phase':
            saved['phase'] = phase = 'output';
          case 'wrong session':
            (saved['session'] as Map)['coordinator'] = fixture.peer;
          case 'wrong location':
            saved['location'] = '${folder.location}-different';
          case 'no consent':
            saved['consented'] = false;
          case 'foreign bytes':
            await folder
                .file('tandemlog-space.json')
                .writeAsBytes(
                  utf8.encode('foreign incomplete bytes'),
                  flush: true,
                );
          case 'capability prefix':
            final extended = utf8.encode(
              a.conversion.manifest.withAdditionalTimeZones().encode(),
            );
            await folder
                .file('tandemlog-space.json')
                .writeAsBytes(
                  extended.take(extended.length - 1).toList(),
                  flush: true,
                );
        }
        if (corruption != 'missing row') {
          ownerProfile.database.execute(
            'UPDATE protected_app_migrations SET plan=?,state=? WHERE space=? AND epoch=?',
            [
              utf8.encode(canonicalDataJson(saved)),
              phase,
              fixture.space,
              a.sessionId,
            ],
          );
        }
        final canonical = <String, List<int>>{};
        for (final info in await folder.list()) {
          canonical[info.name] = await folder.read(info.name);
        }
        final durable = ownerProfile.database
            .select('SELECT * FROM protected_app_migrations')
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final replacements = folder.replacementCalls;
        await expectLater(a.activate(), throwsA(isA<FormatFailure>()));
        expect(folder.replacementCalls, replacements);
        expect(
          ownerProfile.database
              .select('SELECT * FROM protected_app_migrations')
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
          durable,
        );
        expect(
          ownerProfile.database.select(
            'SELECT * FROM protected_app_workspaces',
          ),
          isEmpty,
        );
        expect(
          ownerProfile.database.select('SELECT * FROM protected_app_outbox'),
          isEmpty,
        );
        expect(
          (await folder.list()).map((f) => f.name).toSet(),
          canonical.keys.toSet(),
        );
        for (final entry in canonical.entries) {
          expect(await folder.read(entry.key), entry.value);
        }
      },
    );
  }
}
