import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/occurrence_due_migration.dart';
import 'package:tandemlog/domain/schedule.dart';

Map<String, dynamic> taskWith(TaskSchedule schedule) => {
  'id': 'synthetic-task',
  'kind': 'task',
  'completed': false,
  'deleted': false,
  'schedule': schedule.toJson(),
};

void main() {
  test('only tasks with an occurrence and absent Due are eligible', () {
    final eligible = taskWith(TaskSchedule(scheduledDate: '2026-10-05'));
    for (final task in <Map<String, dynamic>>[
      {...eligible, 'kind': 'user'},
      {...eligible, 'deleted': true},
      {...eligible, 'schedule': null},
      taskWith(TaskSchedule()),
      taskWith(TaskSchedule(startDate: '2026-10-01', recurrence: 'every week')),
      taskWith(TaskSchedule(dueMaxDays: 5)),
    ]) {
      expect(planOccurrenceDueMigration(task), isNull);
    }
    expect(planOccurrenceDueMigration(eligible)?.afterSchedule, isNotNull);
  });

  test('existing Due is never overwritten or cleared', () {
    final task = taskWith(
      TaskSchedule(
        dueDate: '2026-10-08',
        dueTime: '17:00',
        scheduledDate: '2026-10-05',
        scheduledTime: '10:00',
      ),
    );
    final before = jsonEncode(task);
    expect(planOccurrenceDueMigration(task), isNull);
    expect(jsonEncode(task), before);
  });

  test(
    'nonrepeat plan preserves every other schedule field and task value',
    () {
      final original = TaskSchedule(
        startDate: '2026-10-01',
        startTime: '08:30',
        scheduledDate: '2026-10-05',
        scheduledTime: '10:00',
        timeZone: 'America/Chicago',
        dueMinDays: 2,
        dueMaxDays: 8,
      );
      final task = {
        ...taskWith(original),
        'title': 'Synthetic unchanged title',
      };
      final before = jsonEncode(task);
      final plan = planOccurrenceDueMigration(task)!;
      expect(plan.conflict, isNull);
      expect(plan.beforeSchedule, original.toJson());
      expect(plan.afterSchedule!.toJson(), {
        ...original.toJson(),
        'scheduledDate': null,
        'scheduledTime': null,
        'dueDate': '2026-10-05',
        'dueTime': '10:00',
      });
      expect(jsonEncode(task), before);
      expect(
        () => plan.beforeSchedule['startDate'] = '2026-10-02',
        throwsUnsupportedError,
      );
      (task['schedule'] as Map)['startDate'] = '2026-10-02';
      expect(plan.beforeSchedule['startDate'], '2026-10-01');
      expect(plan.afterSchedule!.startDate, '2026-10-01');
    },
  );

  test('date-only and explicit midnight retain distinct precision', () {
    for (final time in <String?>[null, '00:00', '23:59']) {
      final plan = planOccurrenceDueMigration(
        taskWith(
          TaskSchedule(scheduledDate: '2026-10-05', scheduledTime: time),
        ),
      )!;
      expect(plan.conflict, isNull);
      expect(plan.afterSchedule!.dueDate, '2026-10-05');
      expect(plan.afterSchedule!.dueTime, time);
      expect(plan.afterSchedule!.scheduledDate, isNull);
      expect(plan.afterSchedule!.scheduledTime, isNull);
    }
  });

  test('DST gap and fold keep civil date, clock precision and pinned zone', () {
    for (final (date, time) in [
      ('2026-03-08', '02:30'),
      ('2026-11-01', '01:30'),
    ]) {
      final original = TaskSchedule(
        startDate: date,
        startTime: '00:00',
        scheduledDate: date,
        scheduledTime: time,
        timeZone: 'America/Chicago',
        recurrence: 'every week',
        dueMinDays: 0,
        dueMaxDays: 4,
      );
      final plan = planOccurrenceDueMigration(taskWith(original))!;
      expect(plan.conflict, isNull);
      expect(plan.afterSchedule!.dueDate, date);
      expect(plan.afterSchedule!.dueTime, time);
      expect(plan.afterSchedule!.timeZone, 'America/Chicago');
      expect(plan.afterSchedule!.startDate, original.startDate);
      expect(plan.afterSchedule!.startTime, '00:00');
      expect(plan.afterSchedule!.recurrence, 'every week');
      expect(plan.afterSchedule!.dueMinDays, 0);
      expect(plan.afterSchedule!.dueMaxDays, 4);
    }
  });

  test(
    'invalid Start versus converted Due returns conflict without coercion',
    () {
      for (final original in [
        TaskSchedule(startDate: '2026-10-06', scheduledDate: '2026-10-05'),
        TaskSchedule(
          startDate: '2026-10-05',
          startTime: '18:00',
          scheduledDate: '2026-10-05',
          scheduledTime: '10:00',
          timeZone: 'America/Chicago',
          recurrence: 'every week',
        ),
      ]) {
        final task = taskWith(original);
        final before = jsonEncode(task);
        final plan = planOccurrenceDueMigration(task)!;
        expect(plan.afterSchedule, isNull);
        expect(
          plan.conflict,
          'Start must be on or before the due date and time.',
        );
        expect(plan.beforeSchedule, original.toJson());
        expect(jsonEncode(task), before);
      }
    },
  );

  test('whole source and candidate validation never silently repairs data', () {
    final base = taskWith(TaskSchedule(scheduledDate: '2026-10-05'));
    for (final change in <Map<String, dynamic>>[
      {'dueTime': '10:00'},
      {'scheduledTime': '24:00'},
      {'timeZone': 'Synthetic/Unknown'},
      {'dueMinDays': 7, 'dueMaxDays': 2},
      {'unknownField': 'preserve rather than silently discard'},
    ]) {
      final task = {
        ...base,
        'schedule': {...base['schedule'] as Map, ...change},
      };
      final before = jsonEncode(task);
      final plan = planOccurrenceDueMigration(task)!;
      expect(plan.afterSchedule, isNull);
      expect(plan.conflict, isNotEmpty);
      expect(jsonEncode(task), before);
    }
  });

  test('applying the planned schedule makes further planning a no-op', () {
    final task = taskWith(TaskSchedule(scheduledDate: '2026-10-05'));
    final plan = planOccurrenceDueMigration(task)!;
    expect(
      planOccurrenceDueMigration({
        ...task,
        'schedule': plan.afterSchedule!.toJson(),
      }),
      isNull,
    );
  });

  test('scheduled-only repeats advance as persistent Due after conversion', () {
    final original = TaskSchedule(
      scheduledDate: '2026-10-05',
      scheduledTime: '10:00',
      recurrence: 'every week',
    );
    final after = planOccurrenceDueMigration(
      taskWith(original),
    )!.afterSchedule!;
    final next = after.next(DateTime.utc(2026, 10, 20));
    expect(next.startDate, isNull);
    expect(next.dueDate, '2026-10-12');
    expect(next.dueTime, '10:00');
    expect(next.scheduledDate, isNull);
    expect(next.scheduledTime, isNull);
    expect(
      original.next(DateTime.utc(2026, 10, 20)).scheduledDate,
      next.dueDate,
    );
  });

  test(
    'approved Start-backed conversion changes second-generation cadence',
    () {
      final original = TaskSchedule(
        startDate: '2026-10-01',
        scheduledDate: '2026-10-05',
        scheduledTime: '10:00',
        recurrence: 'every week on monday',
      );
      final after = planOccurrenceDueMigration(
        taskWith(original),
      )!.afterSchedule!;
      final day = DateTime.utc(2026, 10, 20);
      final oldFirst = original.next(day);
      final newFirst = after.next(day);
      expect(oldFirst.startDate, '2026-10-08');
      expect(oldFirst.scheduledDate, isNull);
      expect(oldFirst.dueDate, isNull);
      expect(newFirst.startDate, '2026-10-08');
      expect(newFirst.dueDate, '2026-10-12');
      expect(oldFirst.next(day).startDate, '2026-10-12');
      expect(newFirst.next(day).startDate, '2026-10-15');
      expect(newFirst.next(day).dueDate, '2026-10-19');
      expect(newFirst.next(day).dueTime, '10:00');
    },
  );

  test('when-done conversion retains Start offset on later generations', () {
    final original = TaskSchedule(
      startDate: '2026-10-01',
      scheduledDate: '2026-10-05',
      recurrence: 'every week when done',
    );
    final after = planOccurrenceDueMigration(
      taskWith(original),
    )!.afterSchedule!;
    final oldFirst = original.next(DateTime.utc(2026, 10, 20));
    final newFirst = after.next(DateTime.utc(2026, 10, 20));
    expect(oldFirst.startDate, '2026-10-23');
    expect(newFirst.startDate, '2026-10-23');
    expect(oldFirst.next(DateTime.utc(2026, 10, 30)).startDate, '2026-11-06');
    expect(newFirst.next(DateTime.utc(2026, 10, 30)).startDate, '2026-11-02');
  });

  test('completed parent plan leaves existing child and history untouched', () {
    final original = TaskSchedule(
      startDate: '2026-10-01',
      scheduledDate: '2026-10-05',
      recurrence: 'every week',
    );
    final child = {
      ...taskWith(original.next(DateTime.utc(2026, 10, 6))),
      'id': 'synthetic-existing-child',
      'title': 'Synthetic independently edited child',
    };
    final historicalPayload = {
      'successor': {'id': child['id'], 'schedule': child['schedule']},
    };
    final parent = {...taskWith(original), 'completed': true};
    final historyBefore = jsonEncode(historicalPayload);
    final childBefore = jsonEncode(child);
    final parentBefore = jsonEncode(parent);
    final plan = planOccurrenceDueMigration(parent)!;
    expect(plan.afterSchedule!.dueDate, '2026-10-05');
    expect(plan.conflict, isNull);
    // Model the caller replacing only its own current row's schedule. Storage
    // admission and historical-successor retention need separate integration.
    final convertedParent = {
      ...parent,
      'schedule': plan.afterSchedule!.toJson(),
    };
    expect(convertedParent['completed'], isTrue);
    expect(jsonEncode(parent), parentBefore);
    expect(jsonEncode(child), childBefore);
    expect(jsonEncode(historicalPayload), historyBefore);
  });
}
