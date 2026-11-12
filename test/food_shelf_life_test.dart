import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/shelf_life.dart';

void main() {
  test('Keeps for reads the durations people type', () {
    expect(FoodKeepsFor.parse('5 days'), const FoodKeepsFor(5, 'day'));
    expect(FoodKeepsFor.parse(' 1 Day '), const FoodKeepsFor(1, 'day'));
    expect(FoodKeepsFor.parse('2 weeks'), const FoodKeepsFor(2, 'week'));
    expect(FoodKeepsFor.parse('2wk'), const FoodKeepsFor(2, 'week'));
    expect(FoodKeepsFor.parse('3 months'), const FoodKeepsFor(3, 'month'));
    expect(FoodKeepsFor.parse('3 mo.'), const FoodKeepsFor(3, 'month'));
    expect(FoodKeepsFor.parse('10'), const FoodKeepsFor(10, 'day'));
    for (final bad in [
      '',
      '0 days',
      'two weeks',
      '1000 days',
      '121 months',
      '2 years',
      '-3 days',
      '1.5 weeks',
      '2 weeks 3 days',
    ]) {
      expect(FoodKeepsFor.parse(bad), isNull, reason: bad);
    }
    expect(FoodKeepsFor.parse('999 days'), isNotNull);
    expect(FoodKeepsFor.parse('120 months'), isNotNull);
  });

  test('Keeps for displays the unit it was given', () {
    expect(const FoodKeepsFor(1, 'day').label, '1 day');
    expect(const FoodKeepsFor(5, 'day').label, '5 days');
    expect(const FoodKeepsFor(1, 'week').label, '1 week');
    expect(const FoodKeepsFor(3, 'month').label, '3 months');
    expect(const FoodKeepsFor(14, 'day').label, '14 days');
  });

  test('Keeps for JSON accepts only a valid count and unit', () {
    expect(
      FoodKeepsFor.fromJson(const FoodKeepsFor(2, 'week').toJson()),
      const FoodKeepsFor(2, 'week'),
    );
    for (final bad in <Object?>[
      null,
      '2 weeks',
      {'count': 2},
      {'count': '2', 'unit': 'week'},
      {'count': 2, 'unit': 'weeks'},
      {'count': 0, 'unit': 'day'},
      {'count': 121, 'unit': 'month'},
      {'count': 2, 'unit': 'week', 'from': 'opening'},
    ]) {
      expect(FoodKeepsFor.fromJson(bad), isNull, reason: '$bad');
    }
  });

  test('dates are civil: days, weeks, month ends and leap years', () {
    expect(const FoodKeepsFor(5, 'day').addTo('2026-11-07'), '2026-11-12');
    expect(const FoodKeepsFor(3, 'week').addTo('2026-11-07'), '2026-11-28');
    expect(const FoodKeepsFor(30, 'day').addTo('2026-12-15'), '2027-01-14');
    expect(const FoodKeepsFor(1, 'month').addTo('2026-01-31'), '2026-02-28');
    expect(const FoodKeepsFor(1, 'month').addTo('2028-01-31'), '2028-02-29');
    expect(const FoodKeepsFor(1, 'month').addTo('2026-12-15'), '2027-01-15');
    expect(const FoodKeepsFor(3, 'month').addTo('2026-11-30'), '2027-02-28');
    expect(const FoodKeepsFor(12, 'month').addTo('2028-02-29'), '2029-02-28');
    expect(const FoodKeepsFor(2, 'month').addTo('2026-08-31'), '2026-10-31');
    // Daylight saving changes never move a civil date.
    expect(const FoodKeepsFor(1, 'day').addTo('2026-03-07'), '2026-03-08');
    expect(const FoodKeepsFor(1, 'day').addTo('2026-03-08'), '2026-03-09');
    expect(const FoodKeepsFor(1, 'week').addTo('2026-10-29'), '2026-11-05');
  });

  test('a remembered duration is days, or weeks when it divides by 7', () {
    expect(
      FoodKeepsFor.between('2026-11-07', '2026-11-19'),
      const FoodKeepsFor(12, 'day'),
    );
    expect(
      FoodKeepsFor.between('2026-11-07', '2026-11-28'),
      const FoodKeepsFor(3, 'week'),
    );
    expect(
      FoodKeepsFor.between('2026-01-31', '2026-02-28'),
      const FoodKeepsFor(4, 'week'),
    );
    expect(FoodKeepsFor.between('2026-11-07', '2026-11-07'), isNull);
    expect(FoodKeepsFor.between('2026-11-07', '2026-11-01'), isNull);
    expect(FoodKeepsFor.between('2026-01-01', '2029-01-01'), isNull);
    expect(
      FoodKeepsFor.between('2026-01-01', '2029-01-04'),
      const FoodKeepsFor(157, 'week'),
    );
  });
}
