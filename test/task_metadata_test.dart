import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/task_view.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/presentation/task_metadata.dart';

void main() {
  test(
    'future hints use projection availability and the observed local day',
    () {
      for (final (schedule, instant, zone, expected) in [
        (
          {'startDate': '2026-10-02', 'startTime': '17:00'},
          '2026-10-02T12:00:00Z',
          'UTC',
          'Starts 17:00',
        ),
        (
          {'startDate': '2026-10-05', 'startTime': '17:00'},
          '2026-10-02T12:00:00Z',
          'UTC',
          'Starts Oct 5 17:00',
        ),
        (
          {'startDate': '2026-10-05'},
          '2026-10-02T12:00:00Z',
          'UTC',
          'Starts Oct 5',
        ),
        (
          {'startDate': '2027-01-01'},
          '2026-10-02T12:00:00Z',
          'UTC',
          'Starts Jan 1 2027',
        ),
        (
          {'startDate': '2026-10-01', 'startTime': '17:00'},
          '2026-10-02T12:00:00Z',
          'UTC',
          '',
        ),
        (
          {'startDate': '2026-10-02', 'startTime': '17:00'},
          '2026-10-02T17:00:00Z',
          'UTC',
          '',
        ),
        (
          {'startDate': '2026-10-05', 'startTime': '00:30', 'timeZone': 'UTC'},
          '2026-10-04T12:00:00Z',
          'America/New_York',
          'Starts 20:30',
        ),
        (
          {'startDate': '2026-10-05', 'timeZone': 'UTC'},
          '2026-10-04T23:00:00Z',
          'America/New_York',
          'Starts today',
        ),
        (
          {
            'startDate': '2026-03-08',
            'startTime': '02:30',
            'timeZone': 'America/New_York',
          },
          '2026-03-08T06:59:00Z',
          'America/New_York',
          'Starts 03:30',
        ),
        (
          {
            'startDate': '2026-11-01',
            'startTime': '01:30',
            'timeZone': 'America/New_York',
          },
          '2026-11-01T04:30:00Z',
          'America/New_York',
          'Starts 01:30',
        ),
        (
          {
            'startDate': '2026-11-01',
            'startTime': '01:30',
            'timeZone': 'America/New_York',
          },
          '2026-11-01T05:30:00Z',
          'America/New_York',
          '',
        ),
        (
          {'startDate': '2026-10-05', 'startTime': '17:00'},
          '2026-10-04T12:00:00Z',
          'Asia/Tokyo',
          'Starts Oct 5 17:00',
        ),
      ]) {
        final time = ViewTime(
          instant: DateTime.parse(instant),
          localZoneId: zone,
          localOffset: Duration.zero,
        );
        final entry = projectTaskView(
          [
            {
              'kind': 'task',
              'id': 'example',
              'completed': false,
              'schedule': schedule,
            },
          ],
          time,
          includeUpcoming: true,
        ).value.open.single;
        expect(
          scheduleMetadata(
            schedule,
            groupDate: null,
            localZoneId: zone,
            viewInstant: time.instant,
            unavailableStart: entry.available ? null : entry.availabilityStart,
          ),
          expected,
          reason: '$schedule at $instant in $zone',
        );
      }
    },
  );
  test(
    'passed start and history hints stay absent even with a retained instant',
    () {
      final start = DateTime.utc(2026, 10, 2, 17);
      expect(
        scheduleMetadata(
          {'startDate': '2026-10-02', 'startTime': '17:00'},
          groupDate: null,
          localZoneId: 'UTC',
          viewInstant: start,
          unavailableStart: start,
        ),
        '',
      );
      expect(
        scheduleMetadata(
          {'startDate': '2026-10-05', 'startTime': '17:00'},
          groupDate: null,
          localZoneId: 'UTC',
          viewInstant: DateTime.utc(2026, 10, 2),
        ),
        '',
      );
    },
  );
  String render(
    Map<String, dynamic> schedule, {
    String? day = '2030-04-23',
    String zone = 'UTC',
  }) => scheduleMetadata(
    schedule,
    groupDate: day,
    localZoneId: zone,
    viewInstant: DateTime.utc(2030, 4, 23),
  );
  test('same heading removes date-only details and empty separators', () {
    expect(
      render({
        'dueDate': '2030-04-23',
        'scheduledDate': '2030-04-23',
        'startDate': '2030-04-23',
      }),
      '',
    );
    expect(render({}), '');
  });
  test('same heading retains role and time', () {
    expect(
      render({
        'dueDate': '2030-04-23',
        'dueTime': '17:30',
        'scheduledDate': '2030-04-23',
        'scheduledTime': '14:00',
        'startDate': '2020-01-01',
        'startTime': '09:00',
      }),
      'Scheduled 14:00',
    );
  });
  test('day groups hide due dates and available starts', () {
    expect(
      render({
        'dueDate': '2030-04-22',
        'scheduledDate': '2030-04-24',
        'startDate': '2030-04-23',
      }, day: '2030-04-24'),
      '',
    );
    expect(render({'dueDate': '2030-04-23'}, day: null), 'Due 2030-04-23');
  });
  test('day groups hide pinned dates even across local days', () {
    final schedule = {
      'dueDate': '2030-04-23',
      'dueTime': '23:30',
      'timeZone': 'America/Argentina/Buenos_Aires',
    };
    expect(render(schedule), 'Due 02:30');
    expect(render(schedule, day: '2030-04-24'), 'Due 02:30');
    expect(render({...schedule, 'dueTime': '17:30'}), 'Due 20:30');
  });
  test('repeat perimeter needs no redundant metadata line or verbose rule', () {
    expect(render({'dueDate': '2030-04-23', 'recurrence': 'daily'}), '');
  });
  test('local zone changes alter only pinned presentation', () {
    final schedule = {
      'dueDate': '2030-04-23',
      'dueTime': '23:30',
      'timeZone': 'UTC',
    };
    expect(render(schedule, zone: 'Asia/Tokyo'), 'Due 08:30');
    expect(render(schedule, zone: 'America/New_York'), 'Due 19:30');
    expect(
      render(schedule, day: null, zone: 'Asia/Tokyo'),
      'Due 2030-04-24 08:30',
    );
    expect(schedule['dueTime'], '23:30');
    expect(
      render({'dueDate': '2030-04-23', 'dueTime': '23:30'}, zone: 'Asia/Tokyo'),
      'Due 23:30',
    );
    expect(
      render(
        {'dueDate': '2030-04-23', 'timeZone': 'UTC'},
        day: null,
        zone: 'Asia/Tokyo',
      ),
      'Due 2030-04-23',
    );
  });
  test('pinned DST gaps and folds share projection resolution', () {
    expect(
      render({
        'dueDate': '2026-03-08',
        'dueTime': '02:30',
        'timeZone': 'America/New_York',
      }),
      'Due 07:30',
    );
    expect(
      render({
        'dueDate': '2026-11-01',
        'dueTime': '01:30',
        'timeZone': 'America/New_York',
      }),
      'Due 05:30',
    );
  });
  test('local day headings and bounded task times share the observed zone', () {
    final schedule = {
      'dueDate': '2030-04-23',
      'dueTime': '23:30',
      'startDate': '2020-01-01',
      'dueMinDays': 3,
      'startTime': '01:00',
      'timeZone': 'UTC',
    };
    final projection = projectTaskView(
      [
        {
          'kind': 'task',
          'id': 'example',
          'assignee': 'a',
          'completed': false,
          'schedule': schedule,
        },
      ],
      ViewTime(
        instant: DateTime.utc(2030, 4, 22),
        localZoneId: 'Asia/Tokyo',
        localOffset: const Duration(hours: 9),
      ),
      includeUpcoming: true,
    ).value;
    final group = projection.openGroups.single;
    expect(group.date, '2030-04-25');
    expect(render(schedule, day: group.date, zone: 'Asia/Tokyo'), 'Due 08:30');
  });
  test('date-only occurrence override suppresses timed base due', () {
    expect(
      render({
        'scheduledDate': '2030-04-24',
        'dueDate': '2030-04-23',
        'dueTime': '17:30',
      }),
      '',
    );
  });
}
