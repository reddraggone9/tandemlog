import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

void main() {
  test('new wall time wins despite many older borrowed nanoseconds', () {
    final old = EventClock(BigInt.from(1000000) + BigInt.from(100000));
    final recent = EventClock(BigInt.from(2000000));
    expect(recent > old, isTrue);
    expect(EventClock.next(recent.value, old), recent);
  });
  test('equal and backward wall time borrow exactly one nanosecond', () {
    final wall = BigInt.parse('1770000000123456000');
    var clock = EventClock(wall);
    for (var i = 0; i < 100000; i++) {
      clock = EventClock.next(wall, clock);
    }
    expect(clock.value, wall + BigInt.from(100000));
    expect(
      EventClock.next(wall - BigInt.one, clock).value,
      clock.value + BigInt.one,
    );
  });
  test(
    'canonical decimal clock round trips values beyond JSON number precision',
    () {
      final exact = EventClock(BigInt.parse('1770000000123456789'));
      expect(exact.toJson(), '1770000000123456789');
      expect(EventClock.fromJson(exact.toJson()), exact);
      expect(
        EventClock.fromJson(EventClock.maximum.toString()).value,
        EventClock.maximum,
      );
      expect(
        () => EventClock.next(BigInt.zero, EventClock(EventClock.maximum)),
        throwsFormatException,
      );
      for (final value in [
        1,
        {'wallMs': 1, 'logical': 0},
        '-1',
        '01',
        '1.0',
        '1e9',
        '+1',
        '',
        (EventClock.maximum + BigInt.one).toString(),
      ]) {
        expect(() => EventClock.fromJson(value), throwsFormatException);
      }
    },
  );
  test(
    'numeric legacy and tuple draft event clocks are rejected explicitly',
    () {
      const id = '12345678-1234-4234-8234-123456789abc';
      for (final clock in [
        5,
        {'wallMs': 5, 'logical': 0},
      ]) {
        final record = LogEvent(
          id,
          id,
          1,
          EventClock(BigInt.one),
          id,
          'user.created',
          {'name': 'Example'},
        ).toJson()..['clock'] = clock;
        record['hash'] = eventRecordHash(record);
        final raw = canonicalEventJson(record);
        expect(
          () => LogEvent.decode(raw),
          throwsA(
            isA<FormatFailure>().having(
              (e) => e.message,
              'message',
              contains('decimal string'),
            ),
          ),
        );
      }
    },
  );
}
