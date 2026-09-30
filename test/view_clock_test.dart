import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/timed_view.dart';
import 'package:tandemlog/domain/wall_time.dart';
import 'package:tandemlog/presentation/view_clock.dart';

void main() {
  test('exact boundary updates without edits; watchdog avoids projection', () {
    fakeAsync((fake) {
      final epoch = DateTime.utc(2026, 10, 1);
      final boundary = epoch.add(const Duration(minutes: 2));
      final values = <bool>[];
      final clock = ViewClock<bool>(
        readTime: () => ViewTime(
          instant: epoch.add(fake.elapsed),
          localZoneId: 'UTC',
          localOffset: Duration.zero,
        ),
        monotonicNow: () => fake.elapsed,
        project: (time) => TimedView(
          !time.instant.isBefore(boundary),
          nextChange: time.instant.isBefore(boundary) ? boundary : null,
        ),
        onView: (view) => values.add(view.value),
      )..start();
      fake.elapse(const Duration(minutes: 1));
      expect(values, [false]);
      fake.elapse(const Duration(seconds: 59));
      expect(values, [false]);
      fake.elapse(const Duration(seconds: 1));
      expect(values, [false, true]);
      fake.elapse(const Duration(hours: 2));
      expect(values, [false, true]);
      expect(fake.nonPeriodicTimerCount, 1);
      clock.dispose();
      expect(fake.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'resume samples current time after skipped boundaries without replay',
    () {
      fakeAsync((fake) {
        final epoch = DateTime.utc(2026, 10, 1);
        var views = 0;
        final clock = ViewClock<int>(
          readTime: () => ViewTime(
            instant: epoch.add(fake.elapsed),
            localZoneId: 'UTC',
            localOffset: Duration.zero,
          ),
          monotonicNow: () => fake.elapsed,
          project: (time) => TimedView(time.instant.day),
          onView: (_) => views++,
        )..start();
        clock.stop();
        fake.elapse(const Duration(days: 3));
        expect(views, 1);
        clock.start();
        expect(views, 2);
        clock.dispose();
        clock.start();
        clock.invalidate();
        fake.elapse(const Duration(days: 1));
        expect(views, 2);
        expect(fake.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'native invalidation immediate; fallback detects clock and zone changes',
    () {
      fakeAsync((fake) {
        final epoch = DateTime.utc(2026, 10, 1);
        var shift = Duration.zero;
        var zone = 'UTC';
        var offset = Duration.zero;
        var views = 0;
        final clock = ViewClock<DateTime>(
          readTime: () => ViewTime(
            instant: epoch.add(fake.elapsed + shift),
            localZoneId: zone,
            localOffset: offset,
          ),
          monotonicNow: () => fake.elapsed,
          project: (time) => TimedView(time.instant),
          onView: (_) => views++,
        )..start();
        shift = const Duration(days: 1);
        clock.invalidate(); // Native clock-change signal.
        expect(views, 2);
        shift = const Duration(days: -1);
        fake.elapse(const Duration(minutes: 1));
        expect(views, 3);
        zone =
            'Europe/London'; // Same current offset is not same zone identity.
        fake.elapse(const Duration(minutes: 1));
        expect(views, 4);
        offset = const Duration(hours: 1);
        clock.invalidate();
        expect(views, 5);
        fake.elapse(const Duration(minutes: 2));
        expect(views, 5);
        clock.dispose();
      });
    },
  );

  test('delayed wake uses current instant and input invalidation rearms', () {
    final timers = <_ManualTimer>[];
    var now = DateTime.utc(2026, 10, 1);
    final boundary = now.add(const Duration(seconds: 10));
    var input = 'draft remains owned by editor';
    final values = <String>[];
    final clock = ViewClock<String>(
      readTime: () => ViewTime(
        instant: now,
        localZoneId: 'UTC',
        localOffset: Duration.zero,
      ),
      monotonicNow: () => Duration.zero,
      schedule: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
      project: (time) => TimedView(
        '$input:${!time.instant.isBefore(boundary)}',
        nextChange: time.instant.isBefore(boundary) ? boundary : null,
      ),
      onView: (view) => values.add(view.value),
    )..start();
    input = 'updated input';
    clock.invalidate();
    expect(timers.first.isActive, false);
    now = boundary.add(const Duration(days: 2));
    timers.last.callback();
    expect(values.last, 'updated input:true');
    expect(input, 'updated input');
    clock.dispose();
  });

  test('cancelled workspace timer cannot publish and callback can dispose', () {
    final timers = <_ManualTimer>[];
    var calls = 0;
    final clock = ViewClock<int>(
      readTime: () => ViewTime(
        instant: DateTime.utc(2026),
        localZoneId: 'UTC',
        localOffset: Duration.zero,
      ),
      monotonicNow: () => Duration.zero,
      schedule: (_, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
      project: (_) => const TimedView(1),
      onView: (_) => calls++,
    )..start();
    clock.invalidate();
    timers.first.callback(); // Deliberately deliver cancelled callback.
    expect(calls, 2);
    clock.dispose();
    timers.last.callback();
    expect(calls, 2);
  });

  test('callback disposal and invalid boundary cannot produce timer loops', () {
    fakeAsync((fake) {
      final now = ViewTime(
        instant: DateTime.utc(2026),
        localZoneId: 'UTC',
        localOffset: Duration.zero,
      );
      late ViewClock<int> clock;
      clock = ViewClock<int>(
        readTime: () => now,
        monotonicNow: () => fake.elapsed,
        project: (_) => const TimedView(1),
        onView: (_) => clock.dispose(),
      );
      clock.start();
      expect(fake.nonPeriodicTimerCount, 0);
      final invalid = ViewClock<int>(
        readTime: () => now,
        monotonicNow: () => fake.elapsed,
        project: (_) => TimedView(1, nextChange: now.instant),
        onView: (_) => fail('Invalid result must not publish'),
      );
      expect(invalid.start, throwsStateError);
      expect(fake.nonPeriodicTimerCount, 0);
      invalid.dispose();
    });
  });

  for (final day in ['2027-03-14', '2027-11-07']) {
    test('injected calendar boundary crosses DST day $day', () {
      fakeAsync((fake) {
        final start = resolveZonedWallTime(
          day,
          '00:00',
          'America/Chicago',
        ).instant;
        final nextDay = day == '2027-03-14' ? '2027-03-15' : '2027-11-08';
        final end = resolveZonedWallTime(
          nextDay,
          '00:00',
          'America/Chicago',
        ).instant;
        expect(end.difference(start).inHours, day == '2027-03-14' ? 23 : 25);
        var calls = 0;
        final clock = ViewClock<bool>(
          readTime: () => ViewTime(
            instant: start.add(fake.elapsed),
            localZoneId: 'America/Chicago',
            localOffset: Duration.zero,
          ),
          monotonicNow: () => fake.elapsed,
          project: (time) => TimedView(
            !time.instant.isBefore(end),
            nextChange: time.instant.isBefore(end) ? end : null,
          ),
          onView: (_) => calls++,
        )..start();
        fake.elapse(end.difference(start) - const Duration(microseconds: 1));
        expect(calls, 1);
        fake.elapse(const Duration(microseconds: 1));
        expect(calls, 2);
        clock.dispose();
      });
    });
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}
