import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

void main() {
  test(
    'wall time orders unrelated writes despite large stale logical counts',
    () {
      const old = HlcClock(1000, 1000000);
      const recent = HlcClock(1001, 0);
      expect(recent > old, isTrue);
      expect(HlcClock.next(1001, old), recent);
    },
  );
  test(
    'equal-wall bursts and backward time retain causality without future drift',
    () {
      var clock = const HlcClock(1000, 0);
      for (var i = 0; i < 100000; i++) {
        clock = HlcClock.next(1000, clock);
      }
      expect(clock, const HlcClock(1000, 100000));
      expect(HlcClock.next(900, clock), const HlcClock(1000, 100001));
      expect(HlcClock.next(1001, clock), const HlcClock(1001, 0));
    },
  );
  test(
    'clock wire schema rejects scalar legacy, fractions, unknowns and overflow',
    () {
      for (final value in [
        1,
        {'wallMs': 1.1, 'logical': 0},
        {'wallMs': 1, 'logical': -1},
        {'wallMs': 1, 'logical': 0, 'future': true},
        {'wallMs': HlcClock.maxInteger + 1, 'logical': 0},
      ]) {
        expect(() => HlcClock.fromJson(value), throwsFormatException);
      }
      expect(
        () => HlcClock.next(1, const HlcClock(1, HlcClock.maxInteger)),
        throwsFormatException,
      );
      expect(
        HlcClock.fromJson(const HlcClock(20, 4).toJson()),
        const HlcClock(20, 4),
      );
    },
  );
  test('scalar v2 event is rejected explicitly, never reinterpreted', () {
    const id = '12345678-1234-1234-1234-123456789abc';
    final raw =
        '{"v":2,"space":"$id","writer":"$id","seq":1,"clock":5,"entity":"$id","type":"user.created","data":{"name":"Example"}}';
    expect(
      () => LogEvent.decode(raw),
      throwsA(
        isA<FormatFailure>().having(
          (e) => e.message,
          'message',
          contains('hybrid'),
        ),
      ),
    );
  });
}
