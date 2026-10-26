import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'task_view_test.dart' show row, ids;
import 'package:tandemlog/domain/event.dart';

void main() {
  ViewTime at(String instant, [String zone = 'UTC']) => ViewTime(
    instant: DateTime.parse(instant),
    localZoneId: zone,
    localOffset: Duration.zero,
  );
  test(
    'completion order follows selected surviving operation, not last arrival',
    () {
      const space = '00000000-0000-4000-8000-000000000001';
      const writer = '00000000-0000-4000-8000-000000000002';
      const task = '00000000-0000-4000-8000-000000000003';
      LogEvent e(int seq, String type, Map<String, dynamic> data) => LogEvent(
        space,
        writer,
        seq,
        EventClock(BigInt.from(seq)),
        task,
        type,
        data,
      );
      final created = e(1, 'task.created', {
        'title': 'Completed',
        'assignee': writer,
      });
      final first = e(2, 'task.completed', {
        'completedInstant': '2026-10-25T00:00:00.000000Z',
      });
      final last = e(3, 'task.completed', {
        'completedInstant': '2026-10-26T00:00:00.000000Z',
      });
      final both = project([last, created, first])!;
      expect(both['completedInstant'], '2026-10-26T00:00:00.000000Z');
      final earlier = project([created, first])!;
      expect(
        (both['completionOrder'] as String).compareTo(
          earlier['completionOrder'] as String,
        ),
        greaterThan(0),
      );
      final undone = project([
        last,
        e(4, 'task.completionUndone', {'completion': last.id}),
        created,
        first,
      ])!;
      expect(undone['completedInstant'], '2026-10-25T00:00:00.000000Z');
      expect(undone['completionOrder'], earlier['completionOrder']);
    },
  );

  test('Today includes only tomorrow exact times inside rolling 24 hours', () {
    final rows = [
      row('today', schedule: TaskSchedule(dueDate: '2026-10-26')),
      row(
        'early',
        schedule: TaskSchedule(dueDate: '2026-10-27', dueTime: '08:00'),
      ),
      row(
        'late',
        schedule: TaskSchedule(dueDate: '2026-10-27', dueTime: '10:00'),
      ),
      row('untimed', schedule: TaskSchedule(dueDate: '2026-10-27')),
    ];
    final view = projectTaskView(rows, at('2026-10-26T08:00:00Z'));
    expect(ids(view.value.openGroups.first.entries), ['today', 'early']);
    expect(view.value.openGroups.first.today, isTrue);
    expect(view.value.openGroups.first.date, '2026-10-26');
    expect(ids(view.value.openGroups.last.entries), ['late', 'untimed']);
    expect(view.nextChange, DateTime.parse('2026-10-26T10:00:00Z'));
    expect(
      ids(
        projectTaskView(
          rows,
          at('2026-10-26T10:00:00Z'),
        ).value.openGroups.first.entries,
      ),
      ['today', 'early', 'late'],
    );
    expect(view.value.open[1].effectiveDate, DateTime.utc(2026, 10, 27, 8));
    expect(view.value.open[0].sharesOrderBucket(view.value.open[1]), isFalse);
  });
  test(
    'Completed view and search group by completion, never scheduled Due',
    () {
      final rows = [
        {
          ...row(
            'older',
            completed: true,
            schedule: TaskSchedule(dueDate: '2099-01-01'),
          ),
          'completedInstant': '2026-10-25T00:00:00.000000Z',
          'completionOrder': '002',
        },
        {
          ...row('newer', completed: true),
          'completedInstant': '2026-10-26T00:00:00.000000Z',
          'completionOrder': '004',
        },
        {
          ...row('same-day', completed: true),
          'completedInstant': '2026-10-26T00:00:00.000000Z',
          'completionOrder': '003',
        },
        row('unknown', completed: true),
      ];
      for (final search in [null, 'match']) {
        final named = rows.map((r) => {...r, 'title': 'match'}).toList();
        final view = projectTaskView(
          named,
          at('2026-10-26T08:00:00Z'),
          searchQuery: search,
        ).value;
        expect(ids(view.completed), ['newer', 'same-day', 'older', 'unknown']);
        expect(view.completedGroups.map((g) => g.date), [
          '2026-10-26',
          '2026-10-25',
          null,
        ]);
        expect(view.completed[0].hasEffectiveTime, isFalse);
        expect(view.completed[0].sharesOrderBucket(view.completed[1]), isFalse);
      }
    },
  );

  test(
    'viewer-local chronology crosses dates; exact instant wins over causal order and manual position',
    () {
      final rows = [
        {
          ...row('late', completed: true),
          'completedInstant': '2026-10-27T00:30:00.000000Z',
          'completionOrder': '001',
        },
        {
          ...row('early', completed: true),
          'completedInstant': '2026-10-26T23:30:00.000000Z',
          'completionOrder': '999',
        },
        {
          ...row('tie-b', completed: true),
          'completedInstant': '2026-10-26T23:30:00.000000Z',
          'completionOrder': '999',
        },
        {
          ...row('tie-a', completed: true),
          'completedInstant': '2026-10-26T23:30:00.000000Z',
          'completionOrder': '999',
        },
      ];
      for (final search in [null, 'match']) {
        final named = rows.map((r) => {...r, 'title': 'match'}).toList();
        final utc = projectTaskView(
          named,
          at('2026-10-27T02:00:00Z'),
          searchQuery: search,
        ).value;
        final chicago = projectTaskView(
          named.reversed.toList(),
          at('2026-10-27T02:00:00Z', 'America/Chicago'),
          searchQuery: search,
        ).value;
        expect(ids(utc.completed), ['late', 'early', 'tie-a', 'tie-b']);
        expect(ids(chicago.completed), ids(utc.completed));
        expect(utc.completedGroups.map((g) => g.date), [
          '2026-10-27',
          '2026-10-26',
        ]);
        expect(chicago.completedGroups.single.date, '2026-10-26');
        expect(chicago.completed.every((e) => e.effectiveDate == null), true);
        expect(rows.first['completedInstant'], '2026-10-27T00:30:00.000000Z');
      }
    },
  );

  test('rolling Today compares real instants across a DST fold', () {
    final rows = [
      row(
        'inside',
        schedule: TaskSchedule(
          dueDate: '2026-11-01',
          dueTime: '01:15',
          timeZone: 'America/Chicago',
        ),
      ),
      row(
        'outside',
        schedule: TaskSchedule(
          dueDate: '2026-11-01',
          dueTime: '01:45',
          timeZone: 'America/Chicago',
        ),
      ),
    ];
    final before = projectTaskView(
      rows,
      at('2026-10-31T06:30:00Z', 'America/Chicago'),
    );
    expect(before.value.open.first.today, isTrue);
    expect(before.value.open.last.today, isFalse);
    expect(before.nextChange, DateTime.parse('2026-10-31T06:45:00Z'));
    final boundary = projectTaskView(
      rows,
      at('2026-10-31T06:45:00Z', 'America/Chicago'),
    );
    expect(boundary.value.openGroups.single.today, isTrue);
  });

  test('Today uses the viewer date for a pinned due instant', () {
    final view = projectTaskView([
      row(
        'local-tomorrow',
        schedule: TaskSchedule(
          dueDate: '2026-10-28',
          dueTime: '00:30',
          timeZone: 'Asia/Tokyo',
        ),
      ),
    ], at('2026-10-26T15:30:00Z', 'America/Chicago'));
    expect(view.value.open.single.today, isTrue);
    expect(
      view.value.open.single.effectiveDate,
      DateTime.utc(2026, 10, 27, 10, 30),
    );
    expect(view.value.openGroups.single.date, '2026-10-26');
  });

  test(
    'a later future task renews grouping at midnight without other activity',
    () {
      final rows = [
        row(
          'later',
          schedule: TaskSchedule(dueDate: '2026-10-28', dueTime: '07:00'),
        ),
      ];
      final before = projectTaskView(rows, at('2026-10-26T08:00:00Z'));
      expect(before.value.open.single.today, isFalse);
      expect(before.nextChange, DateTime.parse('2026-10-27T00:00:00Z'));
      final midnight = projectTaskView(rows, at('2026-10-27T00:00:00Z'));
      expect(midnight.nextChange, DateTime.parse('2026-10-27T07:00:00Z'));
      expect(
        projectTaskView(
          rows,
          at('2026-10-27T07:00:00Z'),
        ).value.open.single.today,
        isTrue,
      );
    },
  );

  test('Today uses bound-adjusted local effective time without moving Due', () {
    final schedule = TaskSchedule(
      dueDate: '2027-01-01',
      dueTime: '07:00',
      dueMaxDays: 1,
    );
    final view = projectTaskView([
      row('bounded', schedule: schedule),
    ], at('2026-10-26T08:00:00Z'));
    expect(view.value.open.single.effectiveDate, DateTime.utc(2026, 10, 27, 7));
    expect(view.value.open.single.today, isTrue);
    expect(view.value.open.single.task['schedule'], schedule.toJson());
  });
}
