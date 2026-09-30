import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/schedule.dart';

void main() {
  test('all 37 observed expressions match pinned upstream oracle', () {
    expect(observedRecurrences.length, 37);
    for (final row in oracleCases) {
      final reference = parseCivilDate(row[1]);
      final schedule = TaskSchedule(
        startDate: formatCivilDate(reference.subtract(const Duration(days: 2))),
        scheduledDate: formatCivilDate(
          reference.subtract(const Duration(days: 1)),
        ),
        dueDate: row[1],
        recurrence: row[0],
        startTime: '09:30',
        timeZone: 'America/Chicago',
      );
      final next = schedule.next(parseCivilDate(row[2]));
      expect(next.startDate, row[3], reason: row.toString());
      expect(next.dueDate, row[4], reason: row.toString());
      expect(next.scheduledDate, isNull);
      expect(next.startTime, '09:30');
      expect(next.timeZone, 'America/Chicago');
      expect(schedule.dueDate, row[1]);
    }
  });
  test('civil dates and schedule reject normalization and unknown fields', () {
    for (final value in [
      '2026-02-29',
      '2026-13-01',
      '2026-01-00',
      '0000-01-01',
      '26-1-1',
      '2026-01-01T00:00:00Z',
    ]) {
      expect(() => parseCivilDate(value), throwsFormatException);
    }
    for (final value in ['24:00', '9:30', '12:60', '09:30:00']) {
      expect(() => TaskSchedule(startTime: value), throwsFormatException);
    }
    expect(
      () => TaskSchedule.fromJson({'unknown': null}),
      throwsFormatException,
    );
    expect(
      () => TaskSchedule.fromJson({'dueDate': 123}),
      throwsFormatException,
    );
    expect(() => TaskSchedule(recurrence: 'every day'), throwsFormatException);
    expect(
      () => TaskSchedule(dueDate: '2026-01-01', recurrence: 'every 0 days'),
      throwsFormatException,
    );
    expect(
      () => TaskSchedule(dueDate: '2026-01-01', recurrence: 'every nonsense'),
      throwsFormatException,
    );
    expect(() => TaskSchedule(startTime: '09:30'), throwsFormatException);
    expect(
      () => TaskSchedule.fromJson({
        'dueDate': '2026-10-02',
        'startTime': '09:30',
      }),
      throwsFormatException,
    );
    final empty = TaskSchedule();
    expect(TaskSchedule.fromJson(empty.toJson()).toJson(), empty.toJson());
    expect(() => empty.next(DateTime.utc(2026, 1, 1)), throwsStateError);
  });
  test(
    'reference precedence, missing dates and configured scheduled removal',
    () {
      final completion = DateTime.utc(2026, 10, 20);
      final a = TaskSchedule(
        startDate: '2026-10-01',
        scheduledDate: '2026-10-02',
        dueDate: '2026-10-03',
        recurrence: 'every week',
      ).next(completion);
      expect(a.startDate, '2026-10-08');
      expect(a.scheduledDate, isNull);
      expect(a.dueDate, '2026-10-10');
      final b = TaskSchedule(
        startDate: '2026-10-01',
        scheduledDate: '2026-10-02',
        dueDate: '2026-10-03',
        recurrence: 'every week when done',
      ).next(completion);
      expect(b.startDate, '2026-10-25');
      expect(b.dueDate, '2026-10-27');
      final scheduledOnly = TaskSchedule(
        scheduledDate: '2026-10-02',
        recurrence: 'every week',
      ).next(completion);
      expect(scheduledOnly.scheduledDate, '2026-10-09');
      expect(scheduledOnly.startDate, isNull);
      expect(scheduledOnly.dueDate, isNull);
      final startOnly = TaskSchedule(
        startDate: '2026-10-02',
        recurrence: 'every week',
      ).next(completion);
      expect(startOnly.startDate, '2026-10-09');
      expect(startOnly.scheduledDate, isNull);
    },
  );
  test('start bounds reject invalid edits without inventing dates', () {
    for (final zone in <String?>[null, 'UTC', 'America/Chicago']) {
      expect(
        () => TaskSchedule(
          startDate: '2026-10-03',
          dueDate: '2026-10-02',
          timeZone: zone,
        ),
        throwsFormatException,
      );
      expect(
        () => TaskSchedule.fromJson({
          'startDate': '2026-10-03',
          'dueDate': '2026-10-02',
          'timeZone': zone,
        }),
        throwsFormatException,
      );
      final sameDay = TaskSchedule(
        startDate: '2026-10-02',
        dueDate: '2026-10-02',
        startTime: '23:59',
        timeZone: zone,
        recurrence: 'every day',
      );
      expect(sameDay.next(DateTime.utc(2026, 10, 20)).startDate, '2026-10-03');
      expect(sameDay.next(DateTime.utc(2026, 10, 20)).dueDate, '2026-10-03');
    }
    final startOnly = TaskSchedule(startDate: '2026-10-02', startTime: '09:30');
    expect(startOnly.dueDate, isNull);
    final dueOnly = TaskSchedule(dueDate: '2026-10-02');
    expect(dueOnly.startDate, isNull);
  });
  test('named-zone gap and fold obey end-of-due-day bounds', () {
    for (final (date, time) in [
      ('2026-03-08', '02:30'),
      ('2026-11-01', '01:30'),
    ]) {
      final valid = TaskSchedule(
        startDate: date,
        dueDate: date,
        startTime: time,
        timeZone: 'America/Chicago',
      );
      expect(valid.startTime, time);
    }
    expect(
      () => TaskSchedule(
        startDate: '2011-12-30',
        dueDate: '2011-12-30',
        startTime: '12:00',
        timeZone: 'Pacific/Apia',
      ),
      throwsFormatException,
    );
    final beforeSkippedDate = TaskSchedule(
      startDate: '2011-12-29',
      dueDate: '2011-12-29',
      startTime: '12:00',
      timeZone: 'Pacific/Apia',
      recurrence: 'every day',
    );
    expect(
      () => beforeSkippedDate.next(DateTime.utc(2011, 12, 29)),
      throwsFormatException,
    );
    // The same civil values remain valid floating values: no device zone is
    // inferred during validation or replay.
    expect(
      TaskSchedule(
        startDate: '2011-12-30',
        dueDate: '2011-12-30',
        startTime: '12:00',
      ).timeZone,
      isNull,
    );
  });
  test('exact due bounds are inclusive; date-only due covers whole day', () {
    for (final zone in <String?>[null, 'UTC', 'America/Chicago']) {
      TaskSchedule make(String start, String? due) => TaskSchedule(
        startDate: '2026-10-02',
        dueDate: '2026-10-02',
        startTime: start,
        dueTime: due,
        timeZone: zone,
      );
      expect(make('09:30', '09:30').dueTime, '09:30');
      expect(make('09:29', '09:30').startTime, '09:29');
      expect(() => make('09:31', '09:30'), throwsFormatException);
      expect(make('23:59', null).dueTime, isNull);
      expect(
        () => TaskSchedule(
          startDate: '2026-10-03',
          startTime: '00:00',
          dueDate: '2026-10-02',
          timeZone: zone,
        ),
        throwsFormatException,
      );
      expect(
        TaskSchedule(
          startDate: '2026-10-02',
          dueDate: '2026-10-02',
          dueTime: '00:00',
          timeZone: zone,
        ).startTime,
        isNull,
      );
    }
    expect(() => TaskSchedule(dueTime: '09:00'), throwsFormatException);
    expect(() => TaskSchedule(scheduledTime: '09:00'), throwsFormatException);
    expect(
      () => TaskSchedule(dueDate: '2026-10-02', dueTime: '24:00'),
      throwsFormatException,
    );
    expect(
      () => TaskSchedule(scheduledDate: '2026-10-02', scheduledTime: '12:99'),
      throwsFormatException,
    );
  });
  test('precise named-zone bounds compare resolved gap and fold instants', () {
    // Spring gap moves 02:30 to 03:30, after the entered 03:00 due time.
    expect(
      () => TaskSchedule(
        startDate: '2026-03-08',
        startTime: '02:30',
        dueDate: '2026-03-08',
        dueTime: '03:00',
        timeZone: 'America/Chicago',
      ),
      throwsFormatException,
    );
    final equal = TaskSchedule(
      startDate: '2026-03-08',
      startTime: '02:30',
      dueDate: '2026-03-08',
      dueTime: '03:30',
      timeZone: 'America/Chicago',
    );
    expect(equal.dueTime, '03:30');
    final fold = TaskSchedule(
      startDate: '2026-11-01',
      startTime: '01:30',
      dueDate: '2026-11-01',
      dueTime: '01:30',
      timeZone: 'America/Chicago',
    );
    expect(fold.startTime, fold.dueTime);
    expect(
      TaskSchedule(
        startDate: '2026-03-08',
        startTime: '02:30',
        dueDate: '2026-03-08',
        dueTime: '03:00',
      ).timeZone,
      isNull,
    );
  });
  test(
    'recurrence preserves exact times and removes scheduled time with its date',
    () {
      final value = TaskSchedule(
        startDate: '2026-10-01',
        startTime: '08:30',
        scheduledDate: '2026-10-02',
        scheduledTime: '10:00',
        dueDate: '2026-10-03',
        dueTime: '17:00',
        timeZone: 'UTC',
        recurrence: 'every week',
      );
      expect(TaskSchedule.fromJson(value.toJson()).toJson(), value.toJson());
      final next = value.next(DateTime.utc(2026, 10, 5));
      expect(next.startTime, '08:30');
      expect(next.dueTime, '17:00');
      expect(next.timeZone, 'UTC');
      expect(next.scheduledDate, isNull);
      expect(next.scheduledTime, isNull);
      final scheduledOnly = TaskSchedule(
        scheduledDate: '2026-10-02',
        scheduledTime: '10:00',
        recurrence: 'every week',
      ).next(DateTime.utc(2026, 10, 5));
      expect(scheduledOnly.scheduledDate, '2026-10-09');
      expect(scheduledOnly.scheduledTime, '10:00');
    },
  );
  test('last supported due day accepts its internal next-year boundary', () {
    for (final zone in <String?>[null, 'UTC', 'America/Chicago']) {
      final schedule = TaskSchedule(
        startDate: '9999-12-31',
        startTime: '23:59',
        dueDate: '9999-12-31',
        timeZone: zone,
      );
      expect(schedule.dueDate, '9999-12-31');
    }
    expect(() => parseCivilDate('10000-01-01'), throwsFormatException);
  });
  test('clamping evolves while explicit last remains month end', () {
    final day = DateTime.utc(2026, 1, 31);
    final plain = TaskSchedule(
      dueDate: '2026-01-31',
      recurrence: 'every month',
    );
    expect(plain.next(day).dueDate, '2026-02-28');
    expect(plain.next(day).next(day).dueDate, '2026-03-28');
    final last = TaskSchedule(
      dueDate: '2026-01-31',
      recurrence: 'every month on the last',
    );
    expect(last.next(day).next(day).dueDate, '2026-03-31');
    expect(
      TaskSchedule(
        dueDate: '2024-02-29',
        recurrence: 'every year',
      ).next(day).dueDate,
      '2025-02-28',
    );
  });
}

// Generated from official Tasks 7.20.0 (69d6bf8), using its locked rrule
// 2.7.2 and moment 2.29.4. TZ=America/Chicago, removeScheduledDate=true.
// Each row: expression, reference, completion, expected start, expected due.
// Only synthetic dates and public expressions; no private source content.
const oracleCases = <List<String>>[
  [
    'every day when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-19',
    '2026-10-21',
  ],
  [
    'every 2 days when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-20',
    '2026-10-22',
  ],
  [
    'every 5 days when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-23',
    '2026-10-25',
  ],
  [
    'every 9 days when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-27',
    '2026-10-29',
  ],
  [
    'every 20 days when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-07',
    '2026-11-09',
  ],
  [
    'every 25 days when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-12',
    '2026-11-14',
  ],
  [
    'every week when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-25',
    '2026-10-27',
  ],
  [
    'every 2 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-01',
    '2026-11-03',
  ],
  [
    'every 3 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-08',
    '2026-11-10',
  ],
  [
    'every 4 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-15',
    '2026-11-17',
  ],
  [
    'every 6 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-29',
    '2026-12-01',
  ],
  [
    'every 7 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-12-06',
    '2026-12-08',
  ],
  [
    'every 8 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2026-12-13',
    '2026-12-15',
  ],
  [
    'every 13 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2027-01-17',
    '2027-01-19',
  ],
  [
    'every 26 weeks when done',
    '2026-10-03',
    '2026-10-20',
    '2027-04-18',
    '2027-04-20',
  ],
  [
    'every month when done',
    '2026-10-03',
    '2026-10-20',
    '2026-11-18',
    '2026-11-20',
  ],
  [
    'every 3 months when done',
    '2026-10-03',
    '2026-10-20',
    '2027-01-18',
    '2027-01-20',
  ],
  [
    'every 4 months when done',
    '2026-10-03',
    '2026-10-20',
    '2027-02-18',
    '2027-02-20',
  ],
  [
    'every 6 months when done',
    '2026-10-03',
    '2026-10-20',
    '2027-04-18',
    '2027-04-20',
  ],
  [
    'every year when done',
    '2026-10-03',
    '2026-10-20',
    '2027-10-18',
    '2027-10-20',
  ],
  [
    'every 5 years when done',
    '2026-10-03',
    '2026-10-20',
    '2031-10-18',
    '2031-10-20',
  ],
  [
    'every weekday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-19',
    '2026-10-21',
  ],
  [
    'every week on Monday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-24',
    '2026-10-26',
  ],
  [
    'every week on Friday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-21',
    '2026-10-23',
  ],
  [
    'every week on Saturday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-22',
    '2026-10-24',
  ],
  [
    'every week on Wednesday, Sunday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-19',
    '2026-10-21',
  ],
  [
    'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-19',
    '2026-10-21',
  ],
  [
    'every month on the last when done',
    '2026-10-03',
    '2026-10-20',
    '2026-10-29',
    '2026-10-31',
  ],
  ['every day', '2026-10-03', '2026-10-20', '2026-10-02', '2026-10-04'],
  ['every 36 days', '2026-10-03', '2026-10-20', '2026-11-06', '2026-11-08'],
  ['every week', '2026-10-03', '2026-10-20', '2026-10-08', '2026-10-10'],
  [
    'every week on Monday',
    '2026-10-03',
    '2026-10-20',
    '2026-10-03',
    '2026-10-05',
  ],
  [
    'every month on the last',
    '2026-10-03',
    '2026-10-20',
    '2026-10-29',
    '2026-10-31',
  ],
  [
    'every 3 months on the 1st Friday',
    '2026-10-03',
    '2026-10-20',
    '2026-12-30',
    '2027-01-01',
  ],
  [
    'every 3 months on the last',
    '2026-10-03',
    '2026-10-20',
    '2026-10-29',
    '2026-10-31',
  ],
  [
    'every January, April, July and October on the 1st',
    '2026-10-03',
    '2026-10-20',
    '2026-12-30',
    '2027-01-01',
  ],
  ['every year', '2026-10-03', '2026-10-20', '2027-10-01', '2027-10-03'],
  [
    'every day when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-16',
    '2026-02-18',
  ],
  [
    'every 2 days when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-17',
    '2026-02-19',
  ],
  [
    'every 5 days when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-20',
    '2026-02-22',
  ],
  [
    'every 9 days when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-24',
    '2026-02-26',
  ],
  [
    'every 20 days when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-07',
    '2026-03-09',
  ],
  [
    'every 25 days when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-12',
    '2026-03-14',
  ],
  [
    'every week when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-22',
    '2026-02-24',
  ],
  [
    'every 2 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-01',
    '2026-03-03',
  ],
  [
    'every 3 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-08',
    '2026-03-10',
  ],
  [
    'every 4 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-15',
    '2026-03-17',
  ],
  [
    'every 6 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-29',
    '2026-03-31',
  ],
  [
    'every 7 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-04-05',
    '2026-04-07',
  ],
  [
    'every 8 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-04-12',
    '2026-04-14',
  ],
  [
    'every 13 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-05-17',
    '2026-05-19',
  ],
  [
    'every 26 weeks when done',
    '2026-01-31',
    '2026-02-17',
    '2026-08-16',
    '2026-08-18',
  ],
  [
    'every month when done',
    '2026-01-31',
    '2026-02-17',
    '2026-03-15',
    '2026-03-17',
  ],
  [
    'every 3 months when done',
    '2026-01-31',
    '2026-02-17',
    '2026-05-15',
    '2026-05-17',
  ],
  [
    'every 4 months when done',
    '2026-01-31',
    '2026-02-17',
    '2026-06-15',
    '2026-06-17',
  ],
  [
    'every 6 months when done',
    '2026-01-31',
    '2026-02-17',
    '2026-08-15',
    '2026-08-17',
  ],
  [
    'every year when done',
    '2026-01-31',
    '2026-02-17',
    '2027-02-15',
    '2027-02-17',
  ],
  [
    'every 5 years when done',
    '2026-01-31',
    '2026-02-17',
    '2031-02-15',
    '2031-02-17',
  ],
  [
    'every weekday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-16',
    '2026-02-18',
  ],
  [
    'every week on Monday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-21',
    '2026-02-23',
  ],
  [
    'every week on Friday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-18',
    '2026-02-20',
  ],
  [
    'every week on Saturday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-19',
    '2026-02-21',
  ],
  [
    'every week on Wednesday, Sunday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-16',
    '2026-02-18',
  ],
  [
    'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-16',
    '2026-02-18',
  ],
  [
    'every month on the last when done',
    '2026-01-31',
    '2026-02-17',
    '2026-02-26',
    '2026-02-28',
  ],
  ['every day', '2026-01-31', '2026-02-17', '2026-01-30', '2026-02-01'],
  ['every 36 days', '2026-01-31', '2026-02-17', '2026-03-06', '2026-03-08'],
  ['every week', '2026-01-31', '2026-02-17', '2026-02-05', '2026-02-07'],
  [
    'every week on Monday',
    '2026-01-31',
    '2026-02-17',
    '2026-01-31',
    '2026-02-02',
  ],
  [
    'every month on the last',
    '2026-01-31',
    '2026-02-17',
    '2026-02-26',
    '2026-02-28',
  ],
  [
    'every 3 months on the 1st Friday',
    '2026-01-31',
    '2026-02-17',
    '2026-04-01',
    '2026-04-03',
  ],
  [
    'every 3 months on the last',
    '2026-01-31',
    '2026-02-17',
    '2026-04-28',
    '2026-04-30',
  ],
  [
    'every January, April, July and October on the 1st',
    '2026-01-31',
    '2026-02-17',
    '2026-03-30',
    '2026-04-01',
  ],
  ['every year', '2026-01-31', '2026-02-17', '2027-01-29', '2027-01-31'],
  [
    'every day when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-16',
    '2024-03-18',
  ],
  [
    'every 2 days when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-17',
    '2024-03-19',
  ],
  [
    'every 5 days when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-20',
    '2024-03-22',
  ],
  [
    'every 9 days when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-24',
    '2024-03-26',
  ],
  [
    'every 20 days when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-04',
    '2024-04-06',
  ],
  [
    'every 25 days when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-09',
    '2024-04-11',
  ],
  [
    'every week when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-22',
    '2024-03-24',
  ],
  [
    'every 2 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-29',
    '2024-03-31',
  ],
  [
    'every 3 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-05',
    '2024-04-07',
  ],
  [
    'every 4 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-12',
    '2024-04-14',
  ],
  [
    'every 6 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-26',
    '2024-04-28',
  ],
  [
    'every 7 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-05-03',
    '2024-05-05',
  ],
  [
    'every 8 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-05-10',
    '2024-05-12',
  ],
  [
    'every 13 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-06-14',
    '2024-06-16',
  ],
  [
    'every 26 weeks when done',
    '2024-02-29',
    '2024-03-17',
    '2024-09-13',
    '2024-09-15',
  ],
  [
    'every month when done',
    '2024-02-29',
    '2024-03-17',
    '2024-04-15',
    '2024-04-17',
  ],
  [
    'every 3 months when done',
    '2024-02-29',
    '2024-03-17',
    '2024-06-15',
    '2024-06-17',
  ],
  [
    'every 4 months when done',
    '2024-02-29',
    '2024-03-17',
    '2024-07-15',
    '2024-07-17',
  ],
  [
    'every 6 months when done',
    '2024-02-29',
    '2024-03-17',
    '2024-09-15',
    '2024-09-17',
  ],
  [
    'every year when done',
    '2024-02-29',
    '2024-03-17',
    '2025-03-15',
    '2025-03-17',
  ],
  [
    'every 5 years when done',
    '2024-02-29',
    '2024-03-17',
    '2029-03-15',
    '2029-03-17',
  ],
  [
    'every weekday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-16',
    '2024-03-18',
  ],
  [
    'every week on Monday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-16',
    '2024-03-18',
  ],
  [
    'every week on Friday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-20',
    '2024-03-22',
  ],
  [
    'every week on Saturday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-21',
    '2024-03-23',
  ],
  [
    'every week on Wednesday, Sunday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-18',
    '2024-03-20',
  ],
  [
    'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-16',
    '2024-03-18',
  ],
  [
    'every month on the last when done',
    '2024-02-29',
    '2024-03-17',
    '2024-03-29',
    '2024-03-31',
  ],
  ['every day', '2024-02-29', '2024-03-17', '2024-02-28', '2024-03-01'],
  ['every 36 days', '2024-02-29', '2024-03-17', '2024-04-03', '2024-04-05'],
  ['every week', '2024-02-29', '2024-03-17', '2024-03-05', '2024-03-07'],
  [
    'every week on Monday',
    '2024-02-29',
    '2024-03-17',
    '2024-03-02',
    '2024-03-04',
  ],
  [
    'every month on the last',
    '2024-02-29',
    '2024-03-17',
    '2024-03-29',
    '2024-03-31',
  ],
  [
    'every 3 months on the 1st Friday',
    '2024-02-29',
    '2024-03-17',
    '2024-05-01',
    '2024-05-03',
  ],
  [
    'every 3 months on the last',
    '2024-02-29',
    '2024-03-17',
    '2024-05-29',
    '2024-05-31',
  ],
  [
    'every January, April, July and October on the 1st',
    '2024-02-29',
    '2024-03-17',
    '2024-03-30',
    '2024-04-01',
  ],
  ['every year', '2024-02-29', '2024-03-17', '2025-02-26', '2025-02-28'],
  [
    'every day when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-23',
    '2026-03-25',
  ],
  [
    'every 2 days when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-24',
    '2026-03-26',
  ],
  [
    'every 5 days when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-27',
    '2026-03-29',
  ],
  [
    'every 9 days when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-31',
    '2026-04-02',
  ],
  [
    'every 20 days when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-11',
    '2026-04-13',
  ],
  [
    'every 25 days when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-16',
    '2026-04-18',
  ],
  [
    'every week when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-29',
    '2026-03-31',
  ],
  [
    'every 2 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-05',
    '2026-04-07',
  ],
  [
    'every 3 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-12',
    '2026-04-14',
  ],
  [
    'every 4 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-19',
    '2026-04-21',
  ],
  [
    'every 6 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-05-03',
    '2026-05-05',
  ],
  [
    'every 7 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-05-10',
    '2026-05-12',
  ],
  [
    'every 8 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-05-17',
    '2026-05-19',
  ],
  [
    'every 13 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-06-21',
    '2026-06-23',
  ],
  [
    'every 26 weeks when done',
    '2026-03-07',
    '2026-03-24',
    '2026-09-20',
    '2026-09-22',
  ],
  [
    'every month when done',
    '2026-03-07',
    '2026-03-24',
    '2026-04-22',
    '2026-04-24',
  ],
  [
    'every 3 months when done',
    '2026-03-07',
    '2026-03-24',
    '2026-06-22',
    '2026-06-24',
  ],
  [
    'every 4 months when done',
    '2026-03-07',
    '2026-03-24',
    '2026-07-22',
    '2026-07-24',
  ],
  [
    'every 6 months when done',
    '2026-03-07',
    '2026-03-24',
    '2026-09-22',
    '2026-09-24',
  ],
  [
    'every year when done',
    '2026-03-07',
    '2026-03-24',
    '2027-03-22',
    '2027-03-24',
  ],
  [
    'every 5 years when done',
    '2026-03-07',
    '2026-03-24',
    '2031-03-22',
    '2031-03-24',
  ],
  [
    'every weekday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-23',
    '2026-03-25',
  ],
  [
    'every week on Monday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-28',
    '2026-03-30',
  ],
  [
    'every week on Friday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-25',
    '2026-03-27',
  ],
  [
    'every week on Saturday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-26',
    '2026-03-28',
  ],
  [
    'every week on Wednesday, Sunday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-23',
    '2026-03-25',
  ],
  [
    'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-23',
    '2026-03-25',
  ],
  [
    'every month on the last when done',
    '2026-03-07',
    '2026-03-24',
    '2026-03-29',
    '2026-03-31',
  ],
  ['every day', '2026-03-07', '2026-03-24', '2026-03-06', '2026-03-08'],
  ['every 36 days', '2026-03-07', '2026-03-24', '2026-04-10', '2026-04-12'],
  ['every week', '2026-03-07', '2026-03-24', '2026-03-12', '2026-03-14'],
  [
    'every week on Monday',
    '2026-03-07',
    '2026-03-24',
    '2026-03-07',
    '2026-03-09',
  ],
  [
    'every month on the last',
    '2026-03-07',
    '2026-03-24',
    '2026-03-29',
    '2026-03-31',
  ],
  [
    'every 3 months on the 1st Friday',
    '2026-03-07',
    '2026-03-24',
    '2026-06-03',
    '2026-06-05',
  ],
  [
    'every 3 months on the last',
    '2026-03-07',
    '2026-03-24',
    '2026-03-29',
    '2026-03-31',
  ],
  [
    'every January, April, July and October on the 1st',
    '2026-03-07',
    '2026-03-24',
    '2026-03-30',
    '2026-04-01',
  ],
  ['every year', '2026-03-07', '2026-03-24', '2027-03-05', '2027-03-07'],
  [
    'every day when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-16',
    '2026-11-18',
  ],
  [
    'every 2 days when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-17',
    '2026-11-19',
  ],
  [
    'every 5 days when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-20',
    '2026-11-22',
  ],
  [
    'every 9 days when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-24',
    '2026-11-26',
  ],
  [
    'every 20 days when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-05',
    '2026-12-07',
  ],
  [
    'every 25 days when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-10',
    '2026-12-12',
  ],
  [
    'every week when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-22',
    '2026-11-24',
  ],
  [
    'every 2 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-29',
    '2026-12-01',
  ],
  [
    'every 3 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-06',
    '2026-12-08',
  ],
  [
    'every 4 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-13',
    '2026-12-15',
  ],
  [
    'every 6 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-27',
    '2026-12-29',
  ],
  [
    'every 7 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2027-01-03',
    '2027-01-05',
  ],
  [
    'every 8 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2027-01-10',
    '2027-01-12',
  ],
  [
    'every 13 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2027-02-14',
    '2027-02-16',
  ],
  [
    'every 26 weeks when done',
    '2026-10-31',
    '2026-11-17',
    '2027-05-16',
    '2027-05-18',
  ],
  [
    'every month when done',
    '2026-10-31',
    '2026-11-17',
    '2026-12-15',
    '2026-12-17',
  ],
  [
    'every 3 months when done',
    '2026-10-31',
    '2026-11-17',
    '2027-02-15',
    '2027-02-17',
  ],
  [
    'every 4 months when done',
    '2026-10-31',
    '2026-11-17',
    '2027-03-15',
    '2027-03-17',
  ],
  [
    'every 6 months when done',
    '2026-10-31',
    '2026-11-17',
    '2027-05-15',
    '2027-05-17',
  ],
  [
    'every year when done',
    '2026-10-31',
    '2026-11-17',
    '2027-11-15',
    '2027-11-17',
  ],
  [
    'every 5 years when done',
    '2026-10-31',
    '2026-11-17',
    '2031-11-15',
    '2031-11-17',
  ],
  [
    'every weekday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-16',
    '2026-11-18',
  ],
  [
    'every week on Monday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-21',
    '2026-11-23',
  ],
  [
    'every week on Friday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-18',
    '2026-11-20',
  ],
  [
    'every week on Saturday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-19',
    '2026-11-21',
  ],
  [
    'every week on Wednesday, Sunday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-16',
    '2026-11-18',
  ],
  [
    'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-16',
    '2026-11-18',
  ],
  [
    'every month on the last when done',
    '2026-10-31',
    '2026-11-17',
    '2026-11-28',
    '2026-11-30',
  ],
  ['every day', '2026-10-31', '2026-11-17', '2026-10-30', '2026-11-01'],
  ['every 36 days', '2026-10-31', '2026-11-17', '2026-12-04', '2026-12-06'],
  ['every week', '2026-10-31', '2026-11-17', '2026-11-05', '2026-11-07'],
  [
    'every week on Monday',
    '2026-10-31',
    '2026-11-17',
    '2026-10-31',
    '2026-11-02',
  ],
  [
    'every month on the last',
    '2026-10-31',
    '2026-11-17',
    '2026-11-28',
    '2026-11-30',
  ],
  [
    'every 3 months on the 1st Friday',
    '2026-10-31',
    '2026-11-17',
    '2026-12-30',
    '2027-01-01',
  ],
  [
    'every 3 months on the last',
    '2026-10-31',
    '2026-11-17',
    '2027-01-29',
    '2027-01-31',
  ],
  [
    'every January, April, July and October on the 1st',
    '2026-10-31',
    '2026-11-17',
    '2026-12-30',
    '2027-01-01',
  ],
  ['every year', '2026-10-31', '2026-11-17', '2027-10-29', '2027-10-31'],
];
