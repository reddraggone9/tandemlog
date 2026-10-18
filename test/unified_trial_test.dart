import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_trial.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'unified_conversion_test.dart' as fixture;

void main() {
  UnifiedTrial? trial;
  Future<UnifiedTrial> create() async =>
      trial = await UnifiedTrial.createSynthetic(
        space: fixture.space,
        owners: {fixture.owner, fixture.peer},
        participants: {fixture.owner, fixture.peer},
        sources: fixture.sources(),
      );
  Future<void> inputs(UnifiedTrial t) async {
    for (final w in t.plan.participants) {
      await t.acknowledgeInput(w);
    }
  }

  Future<void> outputs(UnifiedTrial t) async {
    for (final w in t.plan.participants) {
      await t.acknowledgeOutput(w);
    }
  }

  Future<UnifiedTrial> reopen(UnifiedTrial t) async {
    final path = t.root.path;
    await t.close();
    return trial = await UnifiedTrial.resume(path);
  }

  tearDown(() async {
    final t = trial;
    if (t != null) {
      await t.close();
      await t.root.delete(recursive: true);
    }
    trial = null;
  });

  test(
    'all participant barriers, exact backups and complete old-file retirement in an owned trial',
    () async {
      final t = await create(), originals = fixture.sources();
      await expectLater(t.stage(), throwsA(isA<FormatFailure>()));
      await t.acknowledgeInput(fixture.owner);
      await expectLater(t.stage(), throwsA(isA<FormatFailure>()));
      await t.acknowledgeInput(fixture.peer);
      await t.stage();
      final p = await t.openParticipant(fixture.owner);
      await expectLater(
        UnifiedHistory.open(t.folder, profile: p, writer: fixture.owner),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        p.database.select('SELECT * FROM protected_app_workspaces'),
        isEmpty,
      );
      await p.close();
      await t.acknowledgeOutput(fixture.owner);
      await expectLater(t.activate(), throwsA(isA<FormatFailure>()));
      await t.acknowledgeOutput(fixture.peer);
      await t.activate();
      await t.retireSyntheticSources();
      expect(t.phase, 'complete');
      for (final name in originals.keys) {
        expect(await t.folder.file(name).exists(), isFalse);
      }
      final backup =
          jsonDecode(
                utf8.decode(
                  t.journal.database
                          .select('SELECT plan FROM protected_app_migrations')
                          .single['plan']
                      as List<int>,
                ),
              )
              as Map;
      for (final entry in originals.entries) {
        expect(
          base64Decode((backup['sources'] as Map)[entry.key] as String),
          entry.value,
        );
      }
      final profile = await t.openParticipant(fixture.owner);
      final h = await UnifiedHistory.open(
        t.folder,
        profile: profile,
        writer: fixture.owner,
      );
      final before = await t.folder.read(unifiedLogName(fixture.owner));
      await h.rebuildOwned();
      expect(await t.folder.read(unifiedLogName(fixture.owner)), before);
      expect(
        h.snapshot.effects.where((e) => e.isData).map((e) => e.raw).toSet(),
        t.conversion.originalEffects.map((e) => e.raw).toSet(),
      );
      await h.close();
      await profile.close();
    },
  );

  for (final stop in [
    'after-manifest',
    'after-output:${unifiedLogName(fixture.owner)}',
    'before-activation',
    'after-activation',
    'before-delete:${fixture.owner}.jsonl',
    'after-delete:${fixture.owner}.jsonl',
  ]) {
    test('journal resumes exact conversion after $stop', () async {
      var t = await create();
      await inputs(t);
      var interrupted = false;
      Future<void> checkpoint(String at) async {
        if (at == stop && !interrupted) {
          interrupted = true;
          throw StateError('Synthetic crash');
        }
      }

      try {
        await t.stage(checkpoint: checkpoint);
        await outputs(t);
        await t.activate(checkpoint: checkpoint);
        await t.retireSyntheticSources(checkpoint: checkpoint);
      } on StateError {
        /* Process dies after durable intent, before next phase. */
      }
      expect(interrupted, isTrue);
      t = await reopen(t);
      if ({'input', 'staging', 'staged'}.contains(t.phase)) {
        await t.stage();
        await outputs(t);
      }
      if ({'staged', 'activating', 'active'}.contains(t.phase)) {
        await t.activate();
      }
      await t.retireSyntheticSources();
      expect(t.phase, 'complete');
      for (final entry in t.conversion.files.entries) {
        expect(await t.folder.read(entry.key), entry.value);
      }
    });
  }

  test(
    'late old writes block staging, activation and deletion without losing bytes',
    () async {
      final t = await create();
      await inputs(t);
      final name = fixture.sources().keys.first, file = t.folder.file(name);
      final bytes = await file.readAsBytes();
      await file.writeAsBytes([...bytes, 10], flush: true);
      await expectLater(t.stage(), throwsA(isA<FormatFailure>()));
      await file.writeAsBytes(bytes, flush: true);
      await t.stage();
      await outputs(t);
      await file.writeAsBytes([...bytes, 10], flush: true);
      await expectLater(t.activate(), throwsA(isA<FormatFailure>()));
      await file.writeAsBytes(bytes, flush: true);
      await t.activate();
      await file.writeAsBytes([...bytes, 10], flush: true);
      await expectLater(
        t.retireSyntheticSources(),
        throwsA(isA<FormatFailure>()),
      );
      expect(await file.readAsBytes(), [...bytes, 10]);
    },
  );

  test(
    'changed converted bytes invalidate output acknowledgement and activation',
    () async {
      final t = await create();
      await inputs(t);
      await t.stage();
      final entry = t.conversion.files.entries.first,
          file = t.folder.file(entry.key);
      await file.writeAsBytes([...entry.value, 10], flush: true);
      await expectLater(
        t.acknowledgeOutput(fixture.owner),
        throwsA(isA<FormatFailure>()),
      );
      await file.writeAsBytes(entry.value, flush: true);
      await outputs(t);
      await file.writeAsBytes([...entry.value, 10], flush: true);
      await expectLater(t.activate(), throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'output changed immediately before activation leaves ready false',
    () async {
      final t = await create();
      await inputs(t);
      await t.stage();
      await outputs(t);
      final entry = t.conversion.files.entries.first;
      await expectLater(
        t.activate(
          checkpoint: (at) async {
            if (at == 'before-activation') {
              await t.folder.file(entry.key).writeAsBytes([
                ...entry.value,
                10,
              ], flush: true);
            }
          },
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(
        await t.folder.file('tandemlog-space.json').readAsString(),
        t.conversion.manifest.staged().encode(),
      );
    },
  );

  test(
    'trial resume rejects arbitrary paths and linked trial content',
    () async {
      await expectLater(
        UnifiedTrial.resume(Directory.current.path),
        throwsA(isA<FormatFailure>()),
      );
      final t = await create();
      final nested = await Directory('${t.root.path}/nested').create();
      await expectLater(
        UnifiedTrial.resume(nested.path),
        throwsA(isA<FormatFailure>()),
      );
      if (!Platform.isWindows) {
        final rootLink = Link('${t.root.path}-root-link');
        await rootLink.create(t.root.path);
        try {
          await expectLater(
            UnifiedTrial.resume(rootLink.path),
            throwsA(isA<FormatFailure>()),
          );
        } finally {
          await rootLink.delete();
        }
        final link = Link('${t.root.path}/escape');
        await link.create(Directory.systemTemp.path);
        await expectLater(
          t.acknowledgeInput(fixture.owner),
          throwsA(isA<FormatFailure>()),
        );
        await link.delete();
      }
    },
  );

  test(
    'created and resumed roots use canonical system-temp identity',
    () async {
      final t = await create();
      expect(t.root.path, await t.root.resolveSymbolicLinks());
      expect(
        t.root.parent.path,
        await Directory.systemTemp.resolveSymbolicLinks(),
      );
      final p = await t.openParticipant(fixture.owner);
      await p.close();
      final spelling = t.root.path.replaceAll(r'\', '/');
      await t.close();
      trial = await UnifiedTrial.resume(spelling);
      await trial!.acknowledgeInput(fixture.owner);
    },
  );

  test(
    'a system-temp parent alias preserves direct-root ownership and resume',
    () async {
      final temp = Directory(await Directory.systemTemp.resolveSymbolicLinks());
      final holder = await temp.createTemp('tandemlog-temp-alias-');
      final alias = Link('${holder.path}/temp');
      await alias.create(temp.path);
      try {
        await IOOverrides.runZoned(() async {
          final t = await create();
          final p = await t.openParticipant(fixture.owner);
          await p.close();
          expect(t.root.path, await t.root.resolveSymbolicLinks());
          expect(t.root.parent.path, temp.path);
          final basename = t.root.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          await t.close();
          trial = await UnifiedTrial.resume('${alias.path}/$basename');
          await trial!.acknowledgeInput(fixture.owner);
        }, getSystemTempDirectory: () => Directory(alias.path));
      } finally {
        final t = trial;
        if (t != null) {
          await t.close();
          final physical = Directory(await t.root.resolveSymbolicLinks());
          expect(physical.parent.path, temp.path);
          await physical.delete(recursive: true);
          trial = null;
        }
        await alias.delete();
        await holder.delete();
      }
    },
    skip:
        Platform.isWindows, // Creating a link requires host-specific privilege.
  );

  test('open participant profile cannot attest quiescence', () async {
    final t = await create(), p = await t.openParticipant(fixture.owner);
    await expectLater(t.acknowledgeInput(fixture.owner), throwsA(anything));
    await p.close();
    await t.acknowledgeInput(fixture.owner);
  });
}
