import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/activity_log.dart';
import 'package:tandemlog/food/food_admission.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/domain/event.dart';
import 'unified_conversion_test.dart' as fixture;

UnifiedSnapshot snapshot(List<UnifiedRecord> records) => UnifiedSnapshot(
  'revision',
  records,
  records.expand((r) => r.effects).toList(),
  <String, Uint8List>{},
  {
    for (final r in records)
      r.writer: records
          .where((p) => p.writer == r.writer)
          .map((p) => p.sequence)
          .reduce((a, b) => a > b ? a : b),
  },
  false,
  admitFoodRecords([
    for (final r in records)
      for (final e in r.effects)
        if (e.food != null) e.food!,
  ]),
  false,
);

void main() {
  test('supported task retractions keep explicit Undo labels', () {
    for (final type in [
      'task.operationUndone',
      'task.completionUndone',
      'task.recurringCompletionUndone',
      'task.deletionUndone',
      'task.textEditUndone',
    ]) {
      expect(activityLabel(type), 'Task change undone');
    }
  });

  test(
    'historical original clocks and authors, not physical migration order',
    () {
      final p = fixture.plan();
      final converted = p.convert(fixture.ack(p));
      final records = [
        for (final bytes in converted.files.values)
          for (final line in utf8.decode(bytes).split('\n'))
            if (line.isNotEmpty) UnifiedRecord.decode(line),
      ];
      final before = records.map((r) => r.encode()).toList();
      final rows = activityEntries(snapshot(records));
      expect(rows, hasLength(records.length));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i - 1].clock >= rows[i].clock, isTrue);
      }
      for (final record in records) {
        final row = rows.singleWhere((a) => a.id == record.recordId);
        expect(row.clock, record.effect.clock);
        expect(row.writer, record.effect.author);
        expect(row.historical, isTrue);
      }
      expect(records.map((r) => r.encode()), before);
      final reverse = activityEntries(snapshot(records.reversed.toList()));
      expect(reverse.map((r) => r.id), rows.map((r) => r.id));
    },
  );

  test(
    'unpublished actions and device labels wait for dependency publication',
    () {
      final p = fixture.plan();
      final records = [
        for (final bytes in p.convert(fixture.ack(p)).files.values)
          for (final line in utf8.decode(bytes).split('\n'))
            if (line.isNotEmpty) UnifiedRecord.decode(line),
      ];
      final full = snapshot(records);
      final blocked = UnifiedSnapshot(
        'blocked',
        records,
        full.effects,
        full.physical,
        {for (final r in records) r.writer: 0},
        false,
        full.foodAdmission,
        true,
      );
      expect(activityEntries(blocked), isEmpty);
      expect(activityEntries(full), hasLength(records.length));
    },
  );

  test(
    'future skew retained, tied clocks deterministic, duplicate names safe',
    () {
      const epoch = '55555555-5555-4555-8555-555555555555';
      UnifiedRecord named(String writer, int time) {
        final head = unifiedGenesis(fixture.space, epoch, writer);
        return UnifiedRecord(
          space: fixture.space,
          epoch: epoch,
          writer: writer,
          sequence: 1,
          clock: EventClock(BigInt.from(time)),
          previousHash: head,
          effect: UnifiedEffect.named('Same device name'),
          observed: {writer: UnifiedFrontier(0, head)},
        );
      }

      final a = named(fixture.owner, 2000000000);
      final b = named(fixture.peer, 2000000000);
      final rows = activityEntries(snapshot([b, a]));
      expect(rows.map((r) => r.writer), [fixture.owner, fixture.peer]);
      expect(rows.map((r) => r.device).toSet(), {'Same device name'});
      expect(rows.map((r) => r.id).toSet(), hasLength(2));
      final future = named(fixture.peer, 9223372036000000000);
      expect(activityEntries(snapshot([a, future])).first.id, future.recordId);
      expect(activityEntries(snapshot([future])).single.recordedAt.year, 2262);
    },
  );
}
