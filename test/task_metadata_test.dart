import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_metadata.dart';

void main() {
  String render(
    Map<String, dynamic> schedule, {
    String? day = '2030-04-23',
    String zone = 'UTC',
  }) => scheduleMetadata(schedule, groupDate: day, localZoneId: zone);
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
      }),
      'Due 17:30 · Scheduled 14:00',
    );
  });
  test('different dates including bounded start remain explicit', () {
    expect(
      render({
        'dueDate': '2030-04-22',
        'scheduledDate': '2030-04-24',
        'startDate': '2030-04-23',
      }, day: '2030-04-24'),
      'Due 2030-04-22 · Start 2030-04-23',
    );
    expect(render({'dueDate': '2030-04-23'}, day: null), 'Due 2030-04-23');
  });
  test('pinned wall dates must also agree with local heading', () {
    final schedule = {
      'dueDate': '2030-04-23',
      'dueTime': '23:30',
      'timeZone': 'America/Argentina/Buenos_Aires',
    };
    expect(
      render(schedule),
      'Due 2030-04-23 23:30 America/Argentina/Buenos_Aires',
    );
    expect(
      render(schedule, day: '2030-04-24'),
      'Due 2030-04-23 23:30 America/Argentina/Buenos_Aires',
    );
    expect(
      render({...schedule, 'dueTime': '17:30'}),
      'Due 17:30 America/Argentina/Buenos_Aires',
    );
  });
  test('recurrence survives omission without orphan separators', () {
    expect(render({'dueDate': '2030-04-23', 'recurrence': 'daily'}), '↻ daily');
  });
}
