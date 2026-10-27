import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart' as current;
import 'package:tandemlog/domain/projection.dart' as projection;
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'support/frozen_stable_v3/event.dart' as old;
import 'support/frozen_stable_v3/projection.dart' as old_projection;
import '../tool/normalization/completion_instant.dart';

void main() {
  test(
    'unchanged stable inputs replay equally at every prefix, both writer arrival orders',
    () async {
      final root = Directory('test/fixtures/stable-v3-2026.10.0');
      final files =
          root
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jsonl'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final originals = {
        for (final file in files) file.path: file.readAsBytesSync(),
      };
      // Verify recovered decoders themselves remain the immutable source bytes.
      final provenance =
          jsonDecode(
                File(
                  'test/support/frozen_stable_v3/provenance.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final entry in (provenance['sha256'] as Map).entries) {
        expect(
          sha256
              .convert(
                File(
                  'test/support/frozen_stable_v3/${entry.key}',
                ).readAsBytesSync(),
              )
              .toString(),
          entry.value,
        );
      }
      final perWriter = <List<old.LogEvent>>[];
      for (final file in files) {
        final events = LineSplitter.split(
          utf8.decode(originals[file.path]!),
        ).map(old.LogEvent.decode).toList();
        var head = old.eventGenesisHash(
          events.first.space,
          events.first.writer,
        );
        for (final event in events) {
          expect(event.previousHash, head);
          head = event.hash!;
        }
        perWriter.add(events);
      }
      Map<String, dynamic>? oldRow(List<old.LogEvent> all, String id) =>
          old.project(all.where((e) => e.entity == id).toList());
      List<current.LogEvent> convert(List<old.LogEvent> source) {
        return [
          for (final e in source)
            (() {
              final data = Map<String, dynamic>.from(e.data);
              if (e.type == 'task.completed') {
                // Historical zone is replayed immediately BEFORE this operation,
                // never read from the task's eventual/final schedule.
                final before = oldRow(
                  source
                      .where((candidate) => old.compareEvents(candidate, e) < 0)
                      .toList(),
                  e.entity,
                );
                final eraZone =
                    (before?['schedule'] as Map?)?['timeZone'] as String?;
                final time = normalizeCompletionTime(
                  completedAt: data.remove('completedAt') as String?,
                  originalClock: e.clock.value,
                  historicalZone: eraZone,
                );
                data['completedInstant'] = time.instant;
              }
              final event = current.LogEvent.decode(
                current.LogEvent(
                  e.space,
                  e.writer,
                  e.sequence,
                  current.EventClock(e.clock.value),
                  e.entity,
                  e.type,
                  data,
                  previousHash: e.previousHash,
                  hash: e.hash,
                ).encode(),
              );
              return event;
            })(),
        ];
      }

      var prefixes = 0;
      for (final order in [perWriter, perWriter.reversed.toList()]) {
        final admitted = <old.LogEvent>[];
        for (final writer in order) {
          for (final event in writer) {
            admitted.add(event);
            final normalized = convert(admitted);
            for (final id in admitted.map((e) => e.entity).toSet()) {
              final expected = oldRow(admitted, id);
              final actual = current.project(
                normalized.where((e) => e.entity == id).toList(),
              );
              if (expected == null) {
                expect(actual, isNull);
                continue;
              }
              final strippedOld = Map<String, dynamic>.from(expected)
                ..remove('completedAt');
              final strippedNew = Map<String, dynamic>.from(actual!)
                ..remove('completedInstant')
                ..remove('completedMicros')
                ..remove('completionOrder');
              expect(strippedNew, strippedOld, reason: 'prefix $prefixes $id');
            }
            // Recurrence proposals and protection/retraction choose identical
            // child state and ID; normalization never recomputes their schedules.
            final byParent = admitted
                .where((e) => e.data['successor'] != null)
                .map((e) => e.entity)
                .toSet();
            for (final id in byParent) {
              final seeds = admitted
                  .where((e) => e.entity == id && e.data['successor'] != null)
                  .toList();
              final newSeeds = normalized
                  .where((e) => e.entity == id && e.data['successor'] != null)
                  .toList();
              for (final protected in [true, false]) {
                final oldChoice = old_projection.selectSuccessor(
                  [...seeds],
                  admitted.where((e) => e.entity == id),
                  protected: protected,
                );
                final newChoice = projection.selectSuccessor(
                  [...newSeeds],
                  normalized.where((e) => e.entity == id),
                  protected: protected,
                );
                expect(newChoice.suppressed, oldChoice.suppressed);
                expect(newChoice.seed.id, oldChoice.seed.id);
                expect(
                  newChoice.seed.data['successor'],
                  oldChoice.seed.data['successor'],
                );
              }
            }
            expect(
              normalized.map((e) => e.encode()).toList(),
              convert(admitted).map((e) => e.encode()).toList(),
            );
            prefixes++;
          }
        }
      }
      final goldenRoot = Directory(
        'test/fixtures/completion-instant-v3/converted-stable-v3',
      );
      final complete = convert(perWriter.expand((events) => events).toList());
      for (final file in goldenRoot.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.applog'),
      )) {
        final actions = LineSplitter.split(
          file.readAsStringSync(),
        ).map(UnifiedRecord.decode).toList();
        final expected = complete
            .where((e) => e.writer == actions.first.writer)
            .map((e) => e.encode())
            .toList();
        expect(
          actions.expand((a) => a.effects).map((e) => e.raw).toList(),
          expected,
        );
      }
      // The independently sealed output is an actual current workspace,
      // not merely accepted JSON or a final-state flattened snapshot.
      final trial = await Directory.systemTemp.createTemp(
        'converted-r3-golden-',
      );
      TaskStore? store;
      try {
        final shared = await Directory('${trial.path}/shared').create();
        for (final file in goldenRoot.listSync().whereType<File>()) {
          await file.copy('${shared.path}/${file.uri.pathSegments.last}');
        }
        store = await TaskStore.open(
          LocalLogFolder(shared.path),
          '${trial.path}/profile',
        );
        final expected = jsonDecode(
          File(
            'test/fixtures/stable-v3-2026.10.0/expected-rows.json',
          ).readAsStringSync(),
        );
        final actual = store.rows
            .map(
              (row) => Map<String, dynamic>.from(row)
                ..remove('completedInstant')
                ..remove('completedMicros')
                ..remove('completionOrder'),
            )
            .toList();
        final stripped = (expected as List)
            .map(
              (row) =>
                  Map<String, dynamic>.from(row as Map)..remove('completedAt'),
            )
            .toList();
        expect(actual, stripped);
      } finally {
        await store?.close();
        await trial.delete(recursive: true);
      }
      expect(prefixes, greaterThan(40));
      for (final file in files) {
        expect(file.readAsBytesSync(), originals[file.path]);
      }
    },
  );
}
