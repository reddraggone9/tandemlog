import 'package:timezone/data/latest.dart' as database;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;
tz.Location timeZoneLocation(String name) {
  if (name == 'UTC') return tz.UTC;
  if (!_initialized) {
    database.initializeTimeZones();
    _initialized = true;
  }
  return tz.getLocation(name);
}

class ResolvedWallTime {
  const ResolvedWallTime(
    this.instant, {
    required this.gapShift,
    required this.ambiguous,
  });
  final DateTime instant;
  final Duration gapShift;
  final bool ambiguous;
}

/// A pinned wall time uses the earlier instant during a fold and moves forward
/// by the transition gap when nonexistent. Floating times have no global instant.
ResolvedWallTime resolveZonedWallTime(String date, String time, String zone) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) {
    throw const FormatException('Invalid date or time.');
  }
  final d = date.split('-').map(int.parse).toList();
  final t = time.split(':').map(int.parse).toList();
  final civil = DateTime.utc(d[0], d[1], d[2], t[0], t[1]);
  if (d.length != 3 ||
      t.length != 2 ||
      civil.year != d[0] ||
      civil.month != d[1] ||
      civil.day != d[2] ||
      civil.hour != t[0] ||
      civil.minute != t[1]) {
    throw FormatException('Invalid date or time.');
  }
  final location = timeZoneLocation(zone);
  // Only offsets near this date are candidates; historical offsets must not
  // manufacture a smaller apparent gap than the actual transition.
  final offsets = <int>{};
  for (var hours = -72; hours <= 72; hours += 6) {
    offsets.add(
      location
          .timeZone(civil.add(Duration(hours: hours)).millisecondsSinceEpoch)
          .offset
          .inMilliseconds,
    );
  }
  final matches = <DateTime>[];
  final forward = <(Duration, DateTime)>[];
  for (final offset in offsets) {
    final instant = DateTime.fromMillisecondsSinceEpoch(
      civil.millisecondsSinceEpoch - offset,
      isUtc: true,
    );
    final local = tz.TZDateTime.from(instant, location);
    final actualCivil = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
    final difference = actualCivil.difference(civil);
    if (difference == Duration.zero) matches.add(instant);
    if (difference > Duration.zero) forward.add((difference, instant));
  }
  if (matches.isNotEmpty) {
    matches.sort();
    return ResolvedWallTime(
      matches.first,
      gapShift: Duration.zero,
      ambiguous: matches.length > 1,
    );
  }
  forward.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c == 0 ? a.$2.compareTo(b.$2) : c;
  });
  if (forward.isEmpty) throw StateError('Cannot resolve wall time in $zone.');
  return ResolvedWallTime(
    forward.first.$2,
    gapShift: forward.first.$1,
    ambiguous: false,
  );
}
