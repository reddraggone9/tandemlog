import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'task_view_test.dart' show row, ids;
import 'package:tandemlog/domain/event.dart';

void main() {
  ViewTime at(String instant) => ViewTime(
    instant: DateTime.parse(instant),
    localZoneId: 'UTC',
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
      final first = e(2, 'task.completed', {'completedAt': '2026-10-25'});
      final last = e(3, 'task.completed', {'completedAt': '2026-10-26'});
      final both = project([last, created, first])!;
      expect(both['completedAt'], '2026-10-26');
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
      expect(undone['completedAt'], '2026-10-25');
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
          'completedAt': '2026-10-25',
          'completionOrder': '002',
        },
        {
          ...row('newer', completed: true),
          'completedAt': '2026-10-26',
          'completionOrder': '004',
        },
        {
          ...row('same-day', completed: true),
          'completedAt': '2026-10-26',
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
}
