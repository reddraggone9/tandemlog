import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_clock.dart';

void main() {
  test('Chicago completion day follows local midnight across DST', () {
    const zone = 'America/Chicago';
    expect(
      civilDayAt(DateTime.parse('2026-03-08T05:59:59Z'), zone),
      DateTime.utc(2026, 3, 7),
    );
    expect(
      civilDayAt(DateTime.parse('2026-03-08T06:00:00Z'), zone),
      DateTime.utc(2026, 3, 8),
    );
    expect(
      civilDayAt(DateTime.parse('2026-03-09T05:00:00Z'), zone),
      DateTime.utc(2026, 3, 9),
    );
    expect(
      civilDayAt(DateTime.parse('2026-11-01T05:00:00Z'), zone),
      DateTime.utc(2026, 11, 1),
    );
    expect(
      civilDayAt(DateTime.parse('2026-11-02T05:59:59Z'), zone),
      DateTime.utc(2026, 11, 1),
    );
    expect(
      civilDayAt(DateTime.parse('2026-11-02T06:00:00Z'), zone),
      DateTime.utc(2026, 11, 2),
    );
  });
  test('unknown timezone never silently falls back', () {
    expect(
      () => civilDayAt(DateTime.utc(2026), 'Invalid/Zone'),
      throwsA(isA<Exception>()),
    );
  });
}
