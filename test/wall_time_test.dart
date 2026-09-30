import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/wall_time.dart';

void main() {
  test(
    'Chicago spring gap moves forward by gap, fall fold uses earlier instant',
    () {
      final spring = resolveZonedWallTime(
        '2026-03-08',
        '02:30',
        'America/Chicago',
      );
      expect(spring.instant, DateTime.utc(2026, 3, 8, 8, 30));
      expect(spring.gapShift, const Duration(hours: 1));
      final fall = resolveZonedWallTime(
        '2026-11-01',
        '01:30',
        'America/Chicago',
      );
      expect(fall.instant, DateTime.utc(2026, 11, 1, 6, 30));
      expect(fall.ambiguous, isTrue);
    },
  );
  test('pinned wall time follows DST while UTC has no transition', () {
    expect(
      resolveZonedWallTime('2026-03-07', '09:00', 'America/Chicago').instant,
      DateTime.utc(2026, 3, 7, 15),
    );
    expect(
      resolveZonedWallTime('2026-03-08', '09:00', 'America/Chicago').instant,
      DateTime.utc(2026, 3, 8, 14),
    );
    expect(
      resolveZonedWallTime('2026-03-08', '09:00', 'UTC').instant,
      DateTime.utc(2026, 3, 8, 9),
    );
  });
  test('half-hour transitions are not hardcoded to an hour', () {
    final result = resolveZonedWallTime(
      '2026-10-04',
      '02:15',
      'Australia/Lord_Howe',
    );
    expect(result.gapShift, const Duration(minutes: 30));
  });
}
