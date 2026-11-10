// THROWAWAY mock-up prototype for design/food-shelf-life.md. Not the design's
// data model: values are keyed by product name so captures need no format
// change. Never merge this branch.

typedef KeepsFor = ({int count, String unit});

final prototypeToday = DateTime(2026, 11, 9);

/// Product name -> Keeps for.
final prototypeKeepsFor = <String, KeepsFor>{};

/// Product name -> purchase day of its imported containers.
final prototypePurchaseDay = <String, String>{};

/// Product name -> days from purchase to the last hand-set date.
final prototypeLastGapDays = <String, int>{};

/// Product name -> usual location.
final prototypeUsualLocation = <String, String>{};

String civil(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? parseCivil(String s) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ? DateTime.tryParse(s) : null;

String formatKeepsFor(KeepsFor k) =>
    '${k.count} ${k.unit}${k.count == 1 ? '' : 's'}';

KeepsFor? parseKeepsFor(String text) {
  final m = RegExp(
    r'^(\d+)\s*(day|week|month)?s?$',
  ).firstMatch(text.trim().toLowerCase());
  if (m == null) return null;
  return (count: int.parse(m[1]!), unit: m[2] ?? 'day');
}

DateTime addKeepsFor(DateTime start, KeepsFor k) => switch (k.unit) {
  'week' => DateTime(start.year, start.month, start.day + 7 * k.count),
  'month' => DateTime(
    start.year,
    start.month + k.count,
    start.day.clamp(1, DateTime(start.year, start.month + k.count + 1, 0).day),
  ),
  _ => DateTime(start.year, start.month, start.day + k.count),
};

/// Days or weeks between two civil dates; months are never inferred.
KeepsFor? impliedKeepsFor(String startDay, String expiry) {
  final a = parseCivil(startDay), b = parseCivil(expiry);
  if (a == null || b == null) return null;
  final days = DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  if (days < 1) return null;
  return days % 7 == 0
      ? (count: days ~/ 7, unit: 'week')
      : (count: days, unit: 'day');
}

bool sameDuration(String start, KeepsFor a, KeepsFor b) {
  final s = parseCivil(start)!;
  return civil(addKeepsFor(s, a)) == civil(addKeepsFor(s, b));
}
