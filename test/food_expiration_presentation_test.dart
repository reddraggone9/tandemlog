import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/expiration_presentation.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  test('local calendar boundaries are inclusive and undated stays neutral', () {
    final today = DateTime(2026, 10, 11, 23, 59);
    expect(foodExpiryUrgency(null, today), FoodExpiryUrgency.normal);
    expect(foodExpiryUrgency('2026-10-10', today), FoodExpiryUrgency.expired);
    for (final day in [11, 12, 13]) {
      expect(foodExpiryUrgency('2026-10-$day', today), FoodExpiryUrgency.soon);
    }
    for (final day in [14, 15, 17]) {
      expect(
        foodExpiryUrgency('2026-10-$day', today),
        FoodExpiryUrgency.approaching,
      );
    }
    expect(foodExpiryUrgency('2026-10-18', today), FoodExpiryUrgency.normal);
  });

  test('calendar thresholds cross DST, month, year and leap-day boundaries', () {
    final zone = tz.getLocation('America/Chicago');
    for (final sample in [
      (
        tz.TZDateTime(zone, 2027, 3, 14),
        '2027-03-16',
        '2027-03-17',
        '2027-03-20',
        '2027-03-21',
      ),
      (
        tz.TZDateTime(zone, 2027, 11, 7),
        '2027-11-09',
        '2027-11-10',
        '2027-11-13',
        '2027-11-14',
      ),
      (
        DateTime(2026, 12, 30),
        '2027-01-01',
        '2027-01-02',
        '2027-01-05',
        '2027-01-06',
      ),
      (
        DateTime(2028, 2, 27),
        '2028-02-29',
        '2028-03-01',
        '2028-03-04',
        '2028-03-05',
      ),
    ]) {
      expect(foodExpiryUrgency(sample.$2, sample.$1), FoodExpiryUrgency.soon);
      expect(
        foodExpiryUrgency(sample.$3, sample.$1),
        FoodExpiryUrgency.approaching,
      );
      expect(
        foodExpiryUrgency(sample.$4, sample.$1),
        FoodExpiryUrgency.approaching,
      );
      expect(foodExpiryUrgency(sample.$5, sample.$1), FoodExpiryUrgency.normal);
    }
    // These elapsed days are not all 24 hours; date classification must not use them.
    expect(
      tz.TZDateTime(
        zone,
        2027,
        3,
        15,
      ).difference(tz.TZDateTime(zone, 2027, 3, 14)).inHours,
      23,
    );
    expect(
      tz.TZDateTime(
        zone,
        2027,
        11,
        8,
      ).difference(tz.TZDateTime(zone, 2027, 11, 7)).inHours,
      25,
    );
  });

  test(
    'date colors retain readable contrast in the actual light and dark palettes',
    () {
      final today = DateTime(2026, 10, 11);
      for (final brightness in Brightness.values) {
        final colors = ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        );
        final expired = foodExpiryColor('2026-10-10', today, colors);
        final orange = foodExpiryColor('2026-10-13', today, colors);
        final yellow = foodExpiryColor('2026-10-17', today, colors);
        final normal = foodExpiryColor('2026-10-18', today, colors);
        expect({expired, orange, yellow, normal}.length, 4);
        expect(normal, colors.onSurface);
        expect(foodExpiryColor(null, today, colors), colors.onSurface);
        for (final foreground in [expired, orange, yellow, normal]) {
          for (final background in [
            colors.surface,
            colors.surfaceContainerLow,
          ]) {
            final a = foreground.computeLuminance(),
                b = background.computeLuminance();
            final contrast = a > b
                ? (a + .05) / (b + .05)
                : (b + .05) / (a + .05);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason: '$brightness date text on $background',
            );
          }
        }
      }
    },
  );

  test('midnight clock refreshes display without mutating records', () {
    fakeAsync((fake) {
      final start = DateTime(2026, 10, 11, 23, 59, 59);
      const details = FoodDetails(
        name: 'Synthetic food',
        expiry: '2026-10-14',
        estimated: true,
      );
      final before = details.toJson();
      final clock = FoodExpirationClock(now: () => start.add(fake.elapsed));
      var notifications = 0;
      clock.addListener(() => notifications++);
      expect(
        foodExpiryUrgency(details.expiry, clock.today),
        FoodExpiryUrgency.approaching,
      );
      expect(fake.nonPeriodicTimerCount, 1);
      fake.elapse(const Duration(seconds: 1));
      expect(clock.today, DateTime(2026, 10, 12));
      expect(
        foodExpiryUrgency(details.expiry, clock.today),
        FoodExpiryUrgency.soon,
      );
      expect(notifications, 1);
      expect(details.toJson(), before);
      expect(fake.nonPeriodicTimerCount, 1);
      clock.dispose();
      expect(fake.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'pause and resume sample current local day; disposed callbacks stay inert',
    () {
      var now = DateTime(2026, 10, 11, 18);
      final timers = <_ManualTimer>[];
      final clock = FoodExpirationClock(
        now: () => now,
        schedule: (_, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      var notifications = 0;
      clock.addListener(() => notifications++);
      clock.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(timers.last.isActive, isFalse);
      now = DateTime(2026, 10, 15, 10);
      timers.first.callback();
      expect(clock.today, DateTime(2026, 10, 11));
      clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(clock.today, DateTime(2026, 10, 15));
      expect(notifications, 1);
      expect(timers.last.isActive, isTrue);
      clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(notifications, 1);
      final last = timers.last;
      clock.dispose();
      expect(last.isActive, isFalse);
      now = DateTime(2026, 10, 16);
      last.callback();
      clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(notifications, 1);
    },
  );

  test(
    'next local midnight uses calendar construction and supports short/long days',
    () {
      for (final day in [DateTime(2027, 3, 14), DateTime(2027, 11, 7)]) {
        final next = DateTime(day.year, day.month, day.day + 1);
        expect(delayUntilNextLocalMidnight(day), next.difference(day));
        expect(day.add(delayUntilNextLocalMidnight(day)).day, day.day + 1);
      }
      expect(
        delayUntilNextLocalMidnight(DateTime(2026, 12, 31, 23, 59, 59)),
        const Duration(seconds: 1),
      );
    },
  );

  test(
    'every background lifecycle stops timers and resume keeps one wakeup',
    () {
      fakeAsync((fake) {
        final clock = FoodExpirationClock(now: () => DateTime(2026, 10, 11));
        var notifications = 0;
        clock.addListener(() => notifications++);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ]) {
          clock.didChangeAppLifecycleState(state);
          expect(fake.nonPeriodicTimerCount, 0);
          clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
          expect(fake.nonPeriodicTimerCount, 1);
        }
        expect(notifications, 0);
        clock.dispose();
        expect(fake.nonPeriodicTimerCount, 0);
      });
    },
  );
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
