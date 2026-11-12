import 'inventory.dart';

/// Shelf life of fresh food with no printed date (design/food-shelf-life.md).
/// A product field: imports and hand entry date new containers from it.
/// All arithmetic is on civil dates.
class FoodKeepsFor {
  const FoodKeepsFor(this.count, this.unit);
  final int count;

  /// `day`, `week` or `month`, as the user wrote it.
  final String unit;

  static const units = {'day', 'week', 'month'};
  static const maximumCount = 999, maximumMonths = 120;
  static const hint = 'For example 5 days, 2 weeks or 3 months.';

  bool get valid =>
      units.contains(unit) &&
      count >= 1 &&
      count <= (unit == 'month' ? maximumMonths : maximumCount);

  Map<String, Object?> toJson() => {'count': count, 'unit': unit};

  /// Null for anything but a valid `{count, unit}` object.
  static FoodKeepsFor? fromJson(Object? value) {
    if (value is! Map ||
        value.length != 2 ||
        value['count'] is! int ||
        value['unit'] is! String) {
      return null;
    }
    final result = FoodKeepsFor(value['count'] as int, value['unit'] as String);
    return result.valid ? result : null;
  }

  /// Reads `5 days`, `2 weeks`, `1 month`, `10d`, `3 wk`, `2 mo`; a bare
  /// number means days. Null when the text is not a valid duration.
  static FoodKeepsFor? parse(String text) {
    final match = RegExp(
      r'^(\d{1,3})\s*([a-z]*)\.?$',
    ).firstMatch(text.trim().toLowerCase());
    if (match == null) return null;
    final unit = switch (match[2]!) {
      '' || 'd' || 'day' || 'days' => 'day',
      'w' || 'wk' || 'wks' || 'week' || 'weeks' => 'week',
      'mo' || 'mos' || 'month' || 'months' => 'month',
      _ => null,
    };
    if (unit == null) return null;
    final result = FoodKeepsFor(int.parse(match[1]!), unit);
    return result.valid ? result : null;
  }

  String get label => '$count $unit${count == 1 ? '' : 's'}';

  /// [date] (`YYYY-MM-DD`) plus this duration. A month lands on the same day
  /// of the month, or on that month's last day (Jan 31 + 1 month = Feb 28/29).
  String addTo(String date) {
    final from = _civil(date);
    if (unit != 'month') {
      return _text(from.add(Duration(days: count * (unit == 'week' ? 7 : 1))));
    }
    final months = from.year * 12 + from.month - 1 + count;
    final year = months ~/ 12, month = months % 12 + 1;
    final last = DateTime.utc(year, month + 1, 0).day;
    return _text(DateTime.utc(year, month, from.day > last ? last : from.day));
  }

  /// The duration from [from] to [to] as days, or weeks when it divides by 7.
  /// Months are never inferred. Null unless [to] is 1 to 999 days (or up to
  /// 999 whole weeks) after [from].
  static FoodKeepsFor? between(String from, String to) {
    final days = _civil(to).difference(_civil(from)).inDays;
    if (days < 1) return null;
    final result = days % 7 == 0
        ? FoodKeepsFor(days ~/ 7, 'week')
        : FoodKeepsFor(days, 'day');
    return result.valid ? result : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FoodKeepsFor && other.count == count && other.unit == unit;
  @override
  int get hashCode => Object.hash(count, unit);
}

DateTime _civil(String date) => DateTime.parse('${date}T00:00:00Z');
String _text(DateTime date) => date.toIso8601String().substring(0, 10);

/// The day a container was bought: the date of its linked, non-voided
/// purchase. Hand entries and unlinked containers have none.
String? foodPurchaseDay(FoodState state, FoodContainer container) {
  final purchase = state.catalog.purchases[container.purchase];
  return purchase == null || purchase.voided ? null : purchase.date;
}

/// Where a product's food usually goes: the location of its most recently
/// placed container. Removed containers count; nothing is stored.
String foodUsualLocation(FoodState state, String product) {
  FoodContainer? latest;
  for (final c in state.containersByProduct[product] ?? const []) {
    if (c.details.location.isEmpty) continue;
    if (latest == null ||
        c.placedOrder > latest.placedOrder ||
        (c.placedOrder == latest.placedOrder &&
            c.id.compareTo(latest.id) > 0)) {
      latest = c;
    }
  }
  return latest?.details.location ?? '';
}

/// A date for an undated container from how long the product's previous
/// purchase lasted: this purchase day plus the gap between the most recently
/// bought other container's purchase day and the date the user gave it.
/// Null without a purchase day or such an earlier container.
String? foodSuggestedExpiry(FoodState state, FoodContainer container) {
  final bought = foodPurchaseDay(state, container);
  if (bought == null) return null;
  (String, String, String)? latest;
  for (final c in state.containersByProduct[container.product] ?? const []) {
    final day = foodPurchaseDay(state, c), expiry = c.details.expiry;
    if (c.id == container.id ||
        day == null ||
        expiry == null ||
        c.estimate ||
        _civil(expiry).difference(_civil(day)).inDays < 1) {
      continue;
    }
    if (latest == null ||
        day.compareTo(latest.$1) > 0 ||
        (day == latest.$1 && c.id.compareTo(latest.$3) > 0)) {
      latest = (day, expiry, c.id);
    }
  }
  if (latest == null) return null;
  final gap = _civil(latest.$2).difference(_civil(latest.$1));
  return _text(_civil(bought).add(gap));
}
