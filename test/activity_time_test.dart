import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/activity_log.dart';

void main() {
  test('day headings: Today, Yesterday, then the Tasks heading format', () {
    final now = DateTime(2026, 11, 3, 0, 30);
    expect(activityDay(DateTime(2026, 11, 3, 0, 0, 1).toUtc(), now), 'Today');
    expect(
      activityDay(DateTime(2026, 11, 2, 23, 59, 59).toUtc(), now),
      'Yesterday',
    );
    expect(
      activityDay(DateTime(2026, 10, 26, 12).toUtc(), now),
      'Monday · 2026-10-26',
    );
    // Clock skew can put an entry ahead of the device; it gets a dated heading.
    expect(
      activityDay(DateTime(2026, 11, 4, 9).toUtc(), now),
      'Wednesday · 2026-11-04',
    );
  });

  test('times to the second; offset only when it differs from now', () {
    final instant = DateTime(2026, 11, 2, 23, 9, 27, 123, 456);
    final local = instant.timeZoneOffset;
    expect(activityClock(instant.toUtc(), currentOffset: local), '23:09:27');
    expect(
      activityTime(instant.toUtc(), currentOffset: local),
      '2026-11-02 23:09:27',
    );
    final other = local + const Duration(hours: 1);
    final minutes = local.inMinutes;
    String two(int v) => v.toString().padLeft(2, '0');
    final zone =
        'UTC${minutes < 0 ? '-' : '+'}${two(minutes.abs() ~/ 60)}:${two(minutes.abs() % 60)}';
    expect(
      activityClock(instant.toUtc(), currentOffset: other),
      '23:09:27 $zone',
    );
  });
}
