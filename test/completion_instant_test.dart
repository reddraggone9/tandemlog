import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/completion_instant.dart';
import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'support/frozen_complete_r2/current_operation.dart' as frozen;
import '../tool/normalization/completion_instant.dart';

void main() {
  test(
    'canonical UTC microseconds roundtrip including zero and year limits',
    () {
      for (final value in [
        '0001-01-01T00:00:00.000000Z',
        '2026-10-26T15:24:05.123456Z',
        '9999-12-31T23:59:59.999999Z',
      ]) {
        expect(encodeCompletionInstant(decodeCompletionInstant(value)), value);
      }
      expect(
        encodeCompletionInstant(
          DateTime.parse('2026-10-26T10:24:05.123456-05:00'),
        ),
        '2026-10-26T15:24:05.123456Z',
      );
    },
  );
  test('strict instants reject missing noncanonical overflow and offsets', () {
    for (final invalid in [
      null,
      42,
      '',
      '2026-10-26',
      '2026-10-26T15:24:05Z',
      '2026-10-26T15:24:05.123Z',
      '2026-10-26T15:24:05.123456+00:00',
      '2026-02-30T15:24:05.000000Z',
      '2026-10-26T24:24:05.000000Z',
      '2026-10-26T15:60:05.000000Z',
      '2026-10-26T15:24:60.000000Z',
      '0000-01-01T00:00:00.000000Z',
      '+10000-01-01T00:00:00.000000Z',
    ]) {
      expect(
        () => decodeCompletionInstant(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });
  test(
    'independent fixed operation/action bytes and hashes, frozen reader refuses r3',
    () {
      final raw = File(
        'test/fixtures/completion-instant-v3/operation.json',
      ).readAsStringSync().trim();
      final actionRaw = File(
        'test/fixtures/completion-instant-v3/action.json',
      ).readAsStringSync().trim();
      final op = CurrentOperation.decode(raw, module: 'tasks');
      expect(op.revision, 3);
      expect(op.encode(), raw);
      expect(LogEvent.decode(raw).encode(), raw);
      expect(UnifiedRecord.decode(actionRaw).encode(), actionRaw);
      expect(
        () => frozen.CurrentOperation.decode(raw, module: 'tasks'),
        throwsFormatException,
      );
      for (final revision in [1, 2]) {
        final legacy = CurrentOperation(
          module: op.module,
          space: op.space,
          author: op.author,
          writer: op.writer,
          sequence: op.sequence,
          clock: op.clock,
          subject: op.subject,
          family: op.family,
          revision: revision,
          value: {
            'mode': 'snapshot',
            'values': {'completedAt': '2026-10-26'},
          },
          predecessor: op.predecessor,
        ).encode();
        expect(
          frozen.CurrentOperation.decode(legacy, module: 'tasks').encode(),
          legacy,
        );
        expect(LogEvent.decode(legacy).data, {'completedAt': '2026-10-26'});
      }
      for (final (revision, values) in <(int, Map<String, dynamic>)>[
        (3, {}),
        (
          3,
          {
            'completedInstant': op.value['values']['completedInstant'],
            'completedAt': '2026-10-26',
          },
        ),
        (
          3,
          {
            'completedInstant': op.value['values']['completedInstant'],
            'completionTimeZone': {'name': 'UTC'},
          },
        ),
        (1, {'completedInstant': op.value['values']['completedInstant']}),
        (4, {'completedInstant': op.value['values']['completedInstant']}),
      ]) {
        final invalid = CurrentOperation(
          module: op.module,
          space: op.space,
          author: op.author,
          writer: op.writer,
          sequence: op.sequence,
          clock: op.clock,
          subject: op.subject,
          family: op.family,
          revision: revision,
          value: {'mode': 'snapshot', 'values': values},
          predecessor: op.predecessor,
        ).encode();
        expect(() => LogEvent.decode(invalid), throwsA(isA<FormatFailure>()));
      }
    },
  );
  BigInt clock(String iso) =>
      BigInt.from(DateTime.parse(iso).microsecondsSinceEpoch) *
      BigInt.from(1000);
  for (final (legacy, causal, zone, expected, method)
      in <(String?, String, String?, String, String)>[
        (
          '2026-10-26T00:15:30.123456+14:00',
          '2026-10-26T23:00:00Z',
          null,
          '2026-10-25T10:15:30.123456Z',
          'explicit',
        ),
        (
          '2026-10-26T00:15:30.123456',
          '2026-10-26T23:00:00Z',
          'America/Chicago',
          '2026-10-26T05:15:30.123456Z',
          'explicit',
        ),
        (
          '2026-10-26',
          '2026-10-27T02:00:00Z',
          'America/Chicago',
          '2026-10-27T02:00:00.000000Z',
          'clock',
        ),
        (
          '2026-10-26',
          '2099-01-01T12:00:00Z',
          null,
          '2026-10-26T12:00:00.000000Z',
          'noon',
        ),
        (
          '2026-10-26',
          '2026-10-25T23:00:00Z',
          'America/Chicago',
          '2026-10-26T17:00:00.000000Z',
          'noon',
        ),
        (
          null,
          '2026-10-26T10:15:30.123456Z',
          null,
          '2026-10-26T10:15:30.123456Z',
          'clock-no-date',
        ),
        (
          '2026-11-01T01:30:00',
          '2026-01-01T00:00:00Z',
          'America/Chicago',
          '2026-11-01T06:30:00.000000Z',
          'explicit',
        ),
        (
          '2026-03-08T02:30:00',
          '2026-01-01T00:00:00Z',
          'America/Chicago',
          '2026-03-08T08:30:00.000000Z',
          'explicit',
        ),
        (
          '2011-12-30',
          '2011-12-01T00:00:00Z',
          'Pacific/Apia',
          '2011-12-30T12:00:00.000000Z',
          'skipped-date-utc-noon',
        ),
      ]) {
    test(
      'offline normalization $legacy $zone chooses $method deterministically',
      () {
        final a = normalizeCompletionTime(
          completedAt: legacy,
          originalClock: clock(causal),
          historicalZone: zone,
        );
        final b = normalizeCompletionTime(
          completedAt: legacy,
          originalClock: clock(causal),
          historicalZone: zone,
        );
        expect(a.instant, expected);
        expect(a.method, method);
        expect(b.instant, a.instant);
        expect(b.method, a.method);
      },
    );
  }
  test(
    'unchanged stable-v3 completions gain only instant, preserving successor and original bytes',
    () {
      final file = File(
        'test/fixtures/stable-v3-2026.10.0/22222222-2222-4222-8222-222222222222.jsonl',
      );
      final before = file.readAsBytesSync();
      final originals = LineSplitter.split(utf8.decode(before))
          .map((s) => jsonDecode(s) as Map)
          .where((e) => e['type'] == 'task.completed')
          .toList();
      expect(originals, hasLength(3));
      for (final original in originals) {
        final data = Map<String, dynamic>.from(original['data']);
        final result = normalizeCompletionTime(
          completedAt: data.remove('completedAt') as String?,
          originalClock: BigInt.parse(original['clock'] as String),
        );
        expect(
          result.instant.substring(0, 10),
          original['data']['completedAt'],
        );
        final normalized = {...data, 'completedInstant': result.instant};
        expect({...normalized}..remove('completedInstant'), data);
        expect(normalized.containsKey('approximate'), false);
      }
      expect(file.readAsBytesSync(), before);
    },
  );
}
