import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/task_tables.dart';
import 'package:tandemlog/storage/unified_manifest.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

/// Pauses at every step, running [onPause] inside each pause.
class _EveryStep extends TaskValidationFrames {
  _EveryStep([this.onPause]) : super(slice: Duration.zero);
  final Future<void> Function(int pause)? onPause;
  int pauses = 0;

  @override
  Future<void> pause() async {
    final pause = pauses++;
    await onPause?.call(pause);
    await super.pause();
  }
}

void main() {
  late Directory root;
  late NativeTextEngine engine;
  late List<LogEvent> events;
  late String space, writer, locationKey, manifestDigest, witnessKey;
  late Object? witness;
  late LocalProfileDatabase profile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('validator-slices-');
    engine = NativeTextEngine(
      libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
    );
    // Scalar legacy tasks before the text baseline, as in the startup seed,
    // then native creations, an edit and a completion through the store.
    final seeded =
        await Process.run(Platform.isWindows ? 'python' : 'python3', [
          'tool/measure_startup.py',
          '--workspace',
          root.path,
          '--tasks',
          '6',
          '--runs',
          '1',
          '--binary',
          '${root.path}/absent-synthetic-executable',
          '--native-library',
          Platform.environment['TANDEMLOG_TEXT_LIBRARY']!,
        ]);
    final receipt =
        jsonDecode(
              await File(
                '${root.path}/synthetic-text-fixture.json',
              ).readAsString(),
            )
            as Map;
    expect(receipt['initialized'], isTrue, reason: '${seeded.stderr}');
    final folder = LocalLogFolder('${root.path}/shared');
    final store = await TaskStore.open(
      folder,
      '${root.path}/profile',
      textEngine: engine,
      writerIdentity: receipt['writer'] as String,
    );
    final user = store.rows.firstWhere((r) => r['kind'] == 'user')['id'];
    final created = {
      for (var i = 0; i < 4; i++) const Uuid().v4(): 'Native task $i',
    };
    expect((await store.createTasks(created, user)).succeeded, isTrue);
    await store.command(created.keys.first, 'task.edited', {
      'schedule': {'dueDate': '2030-05-10'},
    });
    await store.complete(
      created.keys.last,
      localZoneId: 'UTC',
      completionInstant: DateTime.utc(2030, 5, 10),
    );
    final history = store.unified!;
    events = List.unmodifiable(history.snapshot.tasks);
    expect(events.any((e) => e.type == 'text.baselineInitialized'), isTrue);
    space = store.space;
    writer = store.writer;
    manifestDigest = history.manifest.digest;
    locationKey = bytesDigest(
      utf8.encode('${folder.location}#app5:${history.manifest.epoch}'),
    );
    witnessKey = 'app5.task.cache.$locationKey';
    await store.close();
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    witness = profile.database.select(
      'SELECT value FROM profile_metadata WHERE key=?',
      [witnessKey],
    ).single['value'];
  });

  tearDownAll(() async {
    await profile.close();
    await root.delete(recursive: true);
  });

  void setWitness(Object? value) {
    profile.database.execute('DELETE FROM profile_metadata WHERE key=?', [
      witnessKey,
    ]);
    if (value != null) {
      profile.database.execute('INSERT INTO profile_metadata VALUES (?,?)', [
        witnessKey,
        value,
      ]);
    }
  }

  Object? currentWitness() => profile.database.select(
    'SELECT value FROM profile_metadata WHERE key=?',
    [witnessKey],
  ).firstOrNull?['value'];

  TaskSemanticValidator validator({bool bound = true}) => TaskSemanticValidator(
    space: space,
    writer: writer,
    textEngine: engine,
    profile: bound ? profile : null,
    locationKey: bound ? locationKey : null,
    manifestDigest: bound ? manifestDigest : null,
  );

  Set<String> strictReady() {
    final v = validator(bound: false);
    try {
      return v.validate(events);
    } finally {
      v.close();
    }
  }

  test('strict sliced validation equals synchronous validation', () async {
    final expected = strictReady();
    setWitness(null);
    final v = validator();
    try {
      final frames = _EveryStep();
      final ready = await v.validateBetweenFrames(events, frames: frames);
      expect(ready, expected);
      expect(v.reusedProjectionRevision, isNull);
      expect(v.fullRebuilds, 1);
      expect(frames.pauses, v.validationPauses);
      expect(v.validationPauses, greaterThan(events.length));
      // Sealing succeeds only when the scratch rows equal the rows the store
      // projected and sealed at close: the sliced replay built the same rows.
      v.sealCleanCache(
        profile.database,
        TaskTables.forLocation(locationKey),
        events,
      );
      expect(currentWitness(), isNotNull);
      // The validator is idle again: the synchronous API accepts the input.
      expect(v.validate(events), expected);
    } finally {
      v.close();
      setWitness(witness);
    }
  });

  test('warm sliced restore equals synchronous restore', () async {
    final sync = validator();
    final expected = sync.validate(events);
    final reused = sync.reusedProjectionRevision;
    expect(reused, isNotNull);
    sync.close();
    expect(currentWitness(), isNull, reason: 'restore consumes the witness');
    setWitness(witness);
    final v = validator();
    try {
      final ready = await v.validateBetweenFrames(events, frames: _EveryStep());
      expect(ready, expected);
      expect(v.reusedProjectionRevision, reused);
      expect(v.fullRebuilds, 0);
      expect(v.validationPauses, greaterThan(0));
      expect(currentWitness(), isNull);
    } finally {
      v.close();
      setWitness(witness);
    }
  });

  test(
    'a sealed row change during a sliced restore replays strictly',
    () async {
      final expected = strictReady();
      final v = validator();
      final events0 = 'tasks_${locationKey}_events';
      final raw = profile.database
          .select('SELECT id,raw FROM $events0 LIMIT 1')
          .single;
      try {
        final ready = await v.validateBetweenFrames(
          events,
          frames: _EveryStep((pause) async {
            // After the first table is read; a same-value write still fires
            // the witness trigger.
            if (pause == 1) {
              expect(currentWitness(), witness);
              profile.database.execute('UPDATE $events0 SET raw=? WHERE id=?', [
                raw['raw'],
                raw['id'],
              ]);
              expect(currentWitness(), isNull);
            }
          }),
        );
        expect(ready, expected);
        expect(v.reusedProjectionRevision, isNull);
        expect(v.fullRebuilds, 1);
        expect(currentWitness(), isNull);
      } finally {
        v.close();
        setWitness(witness);
      }
    },
  );

  test('a sliced validation owns the validator until it ends', () async {
    final expected = strictReady();
    final v = validator(bound: false);
    try {
      final refused = <Object>[];
      void refuse(void Function() call) {
        try {
          call();
        } on StateError catch (error) {
          refused.add(error);
        }
      }

      final ready = await v.validateBetweenFrames(
        events,
        frames: _EveryStep((pause) async {
          if (pause != events.length) return;
          refuse(() => v.validate(events));
          refuse(
            () => v.validateMonotonicDelta(
              events.take(1).toList(),
              expectedBaseKey: 'base',
              inputKey: 'next',
              orderedEvents: () => events,
            ),
          );
          refuse(
            () => v.validateAppend(
              events.take(1).toList(),
              expectedBaseKey: 'base',
              inputKey: 'next',
            ),
          );
          await expectLater(
            v.validateBetweenFrames(events),
            throwsA(isA<StateError>()),
          );
          expect(v.selectText('any', const []), isNull);
          expect(v.selectCopySeedRaws('any', 'entity'), isNull);
        }),
      );
      expect(refused, hasLength(3));
      expect(ready, expected);
      expect(v.validate(events), expected);
    } finally {
      v.close();
    }
  });

  test('a failed pause discards the partial scratch replay', () async {
    final expected = strictReady();
    final v = validator(bound: false);
    try {
      final running = v.validateBetweenFrames(
        events,
        frames: _EveryStep((pause) async {
          if (pause == events.length) throw StateError('frame failed');
        }),
      );
      await expectLater(running, throwsA(isA<StateError>()));
      expect(v.validate(events), expected);
      expect(v.fullRebuilds, 1);
    } finally {
      v.close();
    }
  });

  test('close during a pause fails the sliced validation cleanly', () async {
    final expected = strictReady();
    final v = validator(bound: false);
    try {
      final running = v.validateBetweenFrames(
        events,
        frames: _EveryStep((pause) async {
          if (pause == events.length) v.close();
        }),
      );
      await expectLater(running, throwsA(isA<StateError>()));
      // A closed validator rebuilds from the canonical input on next use.
      expect(v.validate(events), expected);
      expect(
        await v.validateBetweenFrames(events, frames: _EveryStep()),
        expected,
      );
    } finally {
      v.close();
    }
  });
}
