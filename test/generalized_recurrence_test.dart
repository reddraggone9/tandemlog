import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'support/frozen_stable_v3/schedule.dart' as old;

void main() {
  TaskSchedule schedule(String rule, String due) =>
      TaskSchedule(dueDate: due, recurrence: rule);
  String? next(String rule, String due, [String done = '2026-11-01']) =>
      schedule(rule, due).next(DateTime.parse(done)).dueDate;

  test('weekday-of-month first successor and N-month cadence', () {
    expect(
      next('every 3 months on the 1st Friday', '2026-11-01'),
      '2026-11-06',
    );
    expect(
      next('every 3 months on the 1st Friday', '2026-11-06'),
      '2027-02-05',
    );
    expect(
      next('every 2 months on the 2nd Tuesday', '2026-11-01'),
      '2026-11-10',
    );
    expect(
      next('every 2 months on the 2nd Tuesday', '2026-11-10'),
      '2027-01-12',
    );
    expect(
      next('every month on the 3rd Wednesday', '2026-11-01'),
      '2026-11-18',
    );
    expect(next('every month on the 4th Sunday', '2026-11-01'), '2026-11-22');
    expect(next('every month on the last Monday', '2026-11-01'), '2026-11-30');
    expect(next('every month on the last Monday', '2026-11-30'), '2026-12-28');
    expect(
      next(
        'every 2 months on the last Friday when done',
        '2026-01-01',
        '2026-11-28',
      ),
      '2027-01-29',
    );
  });

  test('all weekdays and ordinals remain within their target month', () {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    for (final (ordinal, label) in [
      (1, '1st'),
      (2, '2nd'),
      (3, '3rd'),
      (4, '4th'),
      (-1, 'last'),
    ]) {
      for (final (index, weekday) in weekdays.indexed) {
        final date = DateTime.parse(
          next('every month on the $label $weekday', '2026-01-31')!,
        );
        expect(date.month, 2);
        expect(date.weekday, index + 1);
        if (ordinal == -1) {
          expect(date.day + 7, greaterThan(28));
        } else {
          expect((date.day - 1) ~/ 7 + 1, ordinal);
        }
      }
    }
  });

  test(
    'general month list, day and when done, with deterministic clamping',
    () {
      expect(
        next('every May and November on the 15th', '2026-11-01'),
        '2026-11-15',
      );
      expect(
        next('every November, May and May on the 15th', '2026-11-15'),
        '2027-05-15',
      );
      expect(next('every February on the 31st', '2027-01-31'), '2027-02-28');
      expect(next('every February on the 31st', '2028-01-31'), '2028-02-29');
      expect(next('every 2 months on the 31st', '2026-11-30'), '2027-01-31');
      expect(
        next(
          'every May and November on the 15th when done',
          '2026-01-01',
          '2026-11-16',
        ),
        '2027-05-15',
      );
    },
  );

  test(
    'old inventory and exact legacy quarterly literal retain bytes and revision',
    () {
      expect(observedRecurrences.length, 37);
      for (final rule in observedRecurrences) {
        expect(schedule(rule, '2026-11-01').toJson()['recurrence'], rule);
        expect(recurrenceRequiresRevision4(rule), isFalse, reason: rule);
      }
      expect(
        recurrenceRequiresRevision4('every 19 months on the 1st Friday'),
        isFalse,
      );
      expect(
        recurrenceRequiresRevision4('every 19 months on the last'),
        isFalse,
      );
      const literal = 'every January, April, July and October on the 1st';
      expect(next(literal, '2026-10-01'), '2027-01-01');
      expect(
        next('$literal when done', '2026-01-01', '2026-11-01'),
        '2027-01-01',
      );
      expect(recurrenceRequiresRevision4('$literal when done'), isFalse);
      for (final rule in recurrenceExamples.skip(37)) {
        expect(recurrenceRequiresRevision4(rule), isTrue);
      }
    },
  );

  test('weekday and month lists share ", ", " and " and ", and "', () {
    // New spelling -> the comma form the previous reader already accepted.
    const spellings = {
      'every week on Monday and Friday': 'every week on Monday, Friday',
      'every week on Monday, Wednesday and Friday':
          'every week on Monday, Wednesday, Friday',
      'every week on Monday, Wednesday, and Friday':
          'every week on Monday, Wednesday, Friday',
      'every 2 weeks on Tuesday and Thursday when done':
          'every 2 weeks on Tuesday, Thursday when done',
      'every week on monday and friday': 'every week on monday, friday',
      'every January, April, July, and October on the 1st':
          'every January, April, July and October on the 1st',
      'every March, June, September, and December on the 15th when done':
          'every March, June, September, December on the 15th when done',
    };
    for (final MapEntry(key: rule, value: equivalent) in spellings.entries) {
      // Exact input text is what gets stored.
      expect(schedule(rule, '2026-11-01').toJson()['recurrence'], rule);
      for (final (due, done) in [
        ('2026-11-01', '2026-11-01'),
        ('2026-11-02', '2026-11-02'),
        ('2026-11-06', '2026-11-20'),
        ('2026-12-15', '2026-12-01'),
      ]) {
        expect(
          next(rule, due, done),
          next(equivalent, due, done),
          reason: '$rule from $due',
        );
      }
      // The previous reader refuses these bytes, so they need revision 4.
      expect(recurrenceRequiresRevision4(rule), isTrue, reason: rule);
      expect(
        () => old.TaskSchedule(
          dueDate: '2026-11-01',
          recurrence: rule,
        ).next(DateTime.parse('2026-11-01')),
        throwsFormatException,
        reason: rule,
      );
    }
    expect(next('every week on Monday and Friday', '2026-11-02'), '2026-11-06');
    expect(next('every week on Monday and Friday', '2026-11-06'), '2026-11-09');
    expect(
      next('every January, April, July, and October on the 1st', '2026-10-01'),
      '2027-01-01',
    );
    // Comma-only weekday lists keep their revision.
    expect(
      recurrenceRequiresRevision4('every week on Monday, Wednesday, Friday'),
      isFalse,
    );
  });

  test('invalid grammar explains supported forms', () {
    for (final rule in [
      'every 2 months on the 5th Tuesday',
      'every month on the 11st',
      'every month on the 32nd',
      'every Jany on the 1st',
      'every January, May on the 0th',
      'every week on Funday',
      'every week on Monday and',
      'every week on and Friday',
      'every week on Monday and and Friday',
      'every week on Monday, , Friday',
      'every January, and on the 1st',
    ]) {
      expect(
        () => schedule(rule, '2026-11-01'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'help',
            contains(supportedRecurrenceGrammar),
          ),
        ),
      );
    }
  });
}
