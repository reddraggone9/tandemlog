import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/timed_view.dart';

ViewTime at(String instant, [String zone = 'UTC', int offsetHours = 0]) =>
    ViewTime(
      instant: DateTime.parse(instant),
      localZoneId: zone,
      localOffset: Duration(hours: offsetHours),
    );
Map<String, dynamic> row(
  String id, {
  TaskSchedule? schedule,
  bool completed = false,
  String user = 'a',
}) => {
  'kind': 'task',
  'id': id,
  'assignee': user,
  'completed': completed,
  'schedule': (schedule ?? TaskSchedule()).toJson(),
};
List<String> ids(List<TaskViewEntry> rows) =>
    rows.map((row) => row.task['id'] as String).toList();

void main() {
  test('upcoming is opt-in and does not change stored rows', () {
    final rows = [
      row('future', schedule: TaskSchedule(startDate: '2026-11-01')),
      row('ready'),
    ];
    final before = jsonEncode(rows);
    final time = at('2026-10-01T12:00:00Z');
    expect(ids(projectTaskView(rows, time).value.open), ['ready']);
    expect(ids(projectTaskView(rows, time, includeUpcoming: true).value.open), [
      'future',
      'ready',
    ]);
    expect(jsonEncode(rows), before);
  });
  test(
    'standalone timing evaluates hidden and completed rows without changing state',
    () {
      final time = at('2026-10-02T12:00:00Z', 'America/Chicago', -5);
      final schedule = TaskSchedule(
        startDate: '2026-10-04',
        dueDate: '2026-10-05',
        dueMaxDays: 1,
      );
      final timing = evaluateTaskTiming(schedule, time);
      expect(timing.available, isFalse);
      expect(timing.availabilityStart, DateTime.parse('2026-10-04T05:00:00Z'));
      expect(timing.effectiveDate, DateTime.utc(2026, 10, 3));
      expect(timing.nextChange, DateTime.parse('2026-10-03T05:00:00Z'));
      final view = projectTaskView([
        row('hidden', schedule: schedule),
        row('done', schedule: schedule, completed: true),
      ], time);
      expect(view.value.open, isEmpty);
      expect(view.value.completed.single.effectiveDate, timing.effectiveDate);
      final absent = evaluateTaskTiming(TaskSchedule(), time);
      expect(absent.available, isTrue);
      expect(absent.availabilityStart, DateTime.parse('2026-10-02T05:00:00Z'));
      expect(absent.effectiveDate, isNull);
      expect(absent.nextChange, isNull);
    },
  );

  test(
    'bounds accept only nullable integers and preserve recurrence anchor',
    () {
      for (final value in [
        -1,
        365001,
        9223372036854775807,
        1.0,
        '1',
        true,
        <int>[],
      ]) {
        expect(
          () => TaskSchedule.fromJson({'dueMinDays': value}),
          throwsFormatException,
        );
        expect(
          () => TaskSchedule.fromJson({'dueMaxDays': value}),
          throwsFormatException,
        );
      }
      expect(
        () => TaskSchedule(dueMinDays: 2, dueMaxDays: 1),
        throwsFormatException,
      );
      final schedule = TaskSchedule(
        dueDate: '2026-10-02',
        recurrence: 'every day',
        dueMinDays: 0,
        dueMaxDays: 2,
      );
      expect(
        TaskSchedule.fromJson(schedule.toJson()).toJson(),
        schedule.toJson(),
      );
      final next = schedule.next(DateTime.utc(2026, 10, 9));
      expect(next.dueDate, '2026-10-03');
      expect(next.dueMinDays, 0);
      expect(next.dueMaxDays, 2);
    },
  );

  test(
    'availability includes exact boundary and completed history stays visible',
    () {
      final rows = [
        row(
          'future',
          schedule: TaskSchedule(startDate: '2026-10-02', startTime: '09:30'),
        ),
        row('free'),
        row(
          'history',
          schedule: TaskSchedule(startDate: '2026-12-01'),
          completed: true,
        ),
      ];
      final before = projectTaskView(rows, at('2026-10-02T09:29:59Z'));
      expect(ids(before.value.open), ['free']);
      expect(ids(before.value.completed), ['history']);
      expect(before.nextChange, DateTime.parse('2026-10-02T09:30:00Z'));
      final exact = projectTaskView(rows, at('2026-10-02T09:30:00Z'));
      expect(ids(exact.value.open), ['future', 'free']);
      expect(exact.nextChange, isNull);
    },
  );

  test('effective scheduled precedence, bounds, Someday and manual ties', () {
    final rows = [
      row('someday'),
      row('minOnlyUndated', schedule: TaskSchedule(dueMinDays: 2)),
      row(
        'scheduled',
        schedule: TaskSchedule(
          scheduledDate: '2026-10-03',
          dueDate: '2026-10-01',
        ),
      ),
      row('min', schedule: TaskSchedule(dueDate: '2026-09-01', dueMinDays: 1)),
      row('maxUndated', schedule: TaskSchedule(dueMaxDays: 1)),
      row(
        'maxFuture',
        schedule: TaskSchedule(dueDate: '2027-01-01', dueMaxDays: 1),
      ),
    ];
    final before = jsonEncode(rows);
    final view = projectTaskView(rows, at('2026-10-02T12:00:00Z'));
    expect(ids(view.value.open), [
      'scheduled',
      'min',
      'maxUndated',
      'maxFuture',
      'someday',
      'minOnlyUndated',
    ]);
    expect(view.value.openGroups.map((g) => g.date), ['2026-10-03', null]);
    expect(view.value.openGroups.first.weekday, DateTime.saturday);
    expect(view.value.openGroups.last.weekday, isNull);
    expect(view.nextChange, DateTime.parse('2026-10-03T00:00:00Z'));
    expect(jsonEncode(rows), before);
    final tomorrow = projectTaskView(rows, at('2026-10-03T00:00:00Z'));
    expect(tomorrow.value.open[1].effectiveDate, DateTime.utc(2026, 10, 4));
  });

  test(
    'bounds clamp civil day while retaining exact time and manual tie order',
    () {
      final rows = [
        row(
          'late',
          schedule: TaskSchedule(
            dueDate: '2027-01-01',
            dueTime: '17:00',
            dueMaxDays: 0,
          ),
        ),
        row(
          'early',
          schedule: TaskSchedule(
            dueDate: '2026-01-01',
            dueTime: '09:00',
            dueMinDays: 0,
          ),
        ),
        row(
          'same',
          schedule: TaskSchedule(dueDate: '2026-10-02', dueTime: '09:00'),
        ),
        row('dateOnly', schedule: TaskSchedule(dueDate: '2026-10-02')),
      ];
      final view = projectTaskView(rows, at('2026-10-02T12:00:00Z')).value;
      expect(ids(view.open), ['dateOnly', 'early', 'same', 'late']);
      expect(view.open.last.effectiveDate, DateTime.utc(2026, 10, 2, 17));
      expect(view.openGroups.length, 1);
    },
  );

  test(
    'pinned exact dates convert to viewer calendar but date-only remains civil',
    () {
      final rows = [
        row(
          'pinnedExact',
          schedule: TaskSchedule(
            dueDate: '2026-10-02',
            dueTime: '01:00',
            timeZone: 'UTC',
          ),
        ),
        row(
          'pinnedDate',
          schedule: TaskSchedule(dueDate: '2026-10-02', timeZone: 'UTC'),
        ),
        row(
          'floatingExact',
          schedule: TaskSchedule(dueDate: '2026-10-02', dueTime: '01:00'),
        ),
      ];
      final view = projectTaskView(
        rows,
        at('2026-10-02T12:00:00Z', 'America/Chicago', -5),
      ).value;
      expect(view.open[0].effectiveDate, DateTime.utc(2026, 10, 1, 20));
      expect(view.open[1].effectiveDate, DateTime.utc(2026, 10, 2));
      expect(view.open[2].effectiveDate, DateTime.utc(2026, 10, 2, 1));
    },
  );

  test('start midnight and DST gap/fold use calendar transitions', () {
    final gap = [
      row(
        'gap',
        schedule: TaskSchedule(
          startDate: '2026-03-08',
          startTime: '02:30',
          timeZone: 'America/Chicago',
        ),
      ),
    ];
    final before = projectTaskView(gap, at('2026-03-08T08:29:59Z'));
    expect(before.value.open, isEmpty);
    expect(before.nextChange, DateTime.parse('2026-03-08T08:30:00Z'));
    expect(
      projectTaskView(gap, at('2026-03-08T08:30:00Z')).value.open.length,
      1,
    );
    final fold = [
      row(
        'fold',
        schedule: TaskSchedule(
          startDate: '2026-11-01',
          startTime: '01:30',
          timeZone: 'America/Chicago',
        ),
      ),
    ];
    expect(
      projectTaskView(fold, at('2026-11-01T06:29:59Z')).nextChange,
      DateTime.parse('2026-11-01T06:30:00Z'),
    );
    final midnight = [
      row('day', schedule: TaskSchedule(startDate: '2026-03-09')),
    ];
    expect(
      projectTaskView(
        midnight,
        at('2026-03-08T06:00:00Z', 'America/Chicago', -6),
      ).nextChange,
      DateTime.parse('2026-03-09T05:00:00Z'),
    );
  });

  test('date-only start midnight uses the shared pinned task zone', () {
    final rows = [
      row(
        'localDay',
        schedule: TaskSchedule(
          startDate: '2026-10-02',
          dueDate: '2026-10-03',
          dueTime: '17:00',
          timeZone: 'UTC',
        ),
      ),
    ];
    final before = projectTaskView(
      rows,
      at('2026-10-01T23:59:59Z', 'America/Chicago', -5),
    );
    expect(before.value.open, isEmpty);
    expect(before.nextChange, DateTime.parse('2026-10-02T00:00:00Z'));
    expect(
      projectTaskView(
        rows,
        at('2026-10-02T00:00:00Z', 'America/Chicago', -5),
      ).value.open.length,
      1,
    );
  });
  test(
    'supported bound horizon is admitted and renderable, larger values rejected',
    () {
      expect(
        () => TaskSchedule(dueMaxDays: 9223372036854775807),
        throwsFormatException,
      );
      expect(
        () => TaskSchedule(dueMinDays: TaskSchedule.maxRelativeDays + 1),
        throwsFormatException,
      );
      final schedule = TaskSchedule(dueMaxDays: TaskSchedule.maxRelativeDays);
      final view = projectTaskView([
        row('far', schedule: schedule),
      ], at('2026-10-02T12:00:00Z'));
      expect(
        view.value.open.single.effectiveDate,
        DateTime.utc(2026, 10, 2).add(const Duration(days: 365000)),
      );
    },
  );
  test('derived bound groups may cross the persisted date year limit', () {
    final view = projectTaskView([
      row('futureGroup', schedule: TaskSchedule(dueMaxDays: 1)),
    ], at('9999-12-31T12:00:00Z'));
    expect(view.value.open.single.effectiveDate, DateTime.utc(10000, 1, 1));
    expect(view.value.openGroups.single.date, '10000-01-01');
  });
  test('bounds midnight boundary follows 23 and 25 hour local days', () {
    final rows = [row('bound', schedule: TaskSchedule(dueMaxDays: 0))];
    final spring = projectTaskView(
      rows,
      at('2026-03-08T06:00:00Z', 'America/Chicago', -6),
    );
    expect(
      spring.nextChange!.difference(DateTime.parse('2026-03-08T06:00:00Z')),
      const Duration(hours: 23),
    );
    final autumn = projectTaskView(
      rows,
      at('2026-11-01T05:00:00Z', 'America/Chicago', -5),
    );
    expect(
      autumn.nextChange!.difference(DateTime.parse('2026-11-01T05:00:00Z')),
      const Duration(hours: 25),
    );
  });

  test('filter and hidden bounds select earliest relevant clock boundary', () {
    final rows = [
      row(
        'other',
        user: 'b',
        schedule: TaskSchedule(startDate: '2026-10-02', startTime: '13:00'),
      ),
      row(
        'future',
        schedule: TaskSchedule(startDate: '2026-10-04', dueMaxDays: 0),
      ),
      {'kind': 'user', 'id': 'a'},
    ];
    final view = projectTaskView(
      rows,
      at('2026-10-02T12:00:00Z'),
      assignee: 'a',
    );
    expect(view.value.open, isEmpty);
    expect(view.nextChange, DateTime.parse('2026-10-03T00:00:00Z'));
    expect(
      projectTaskView(rows, at('2026-10-02T12:00:00Z')).nextChange,
      DateTime.parse('2026-10-02T13:00:00Z'),
    );
  });
}
