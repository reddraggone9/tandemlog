import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_metadata.dart';

void main() {
  String render(Map<String, dynamic> schedule, {String? day = '2030-04-23'}) =>
      scheduleMetadata(schedule, groupDate: day);
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
      'Due 17:30 · Scheduled 14:00 · Start 09:00',
    );
  });
  test('day groups hide differing dates including bounded start', () {
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
    expect(render(schedule), 'Due 23:30 America/Argentina/Buenos_Aires');
    expect(
      render(schedule, day: '2030-04-24'),
      'Due 23:30 America/Argentina/Buenos_Aires',
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
