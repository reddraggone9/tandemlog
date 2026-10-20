import 'package:timezone/timezone.dart' as tz;

import 'timezone_data/iana_2025c.dart' as database;
import 'timezone_data/iana_2026e_additional.dart' as additional_database;

const timeZoneUpgradeRequiredMessage =
    'Update every device to build 98 or later, then enable additional time zones '
    'in workspace Settings before using this time zone.';

const additionalTimeZoneNames = ['CST6CDT', 'EST5EDT', 'MST7MDT', 'PST8PDT'];
const legacyTimeZoneDataSha256 =
    'e67e57be5d320b54e96381b59fdc2e7b0ec803b7e1be98621e445312cf5f295e';
const additionalTimeZoneDataSha256 =
    'a49273d40c8560e4559e79178dd7384d3fb427933929ebe6d22ccfa336bf5a17';
const additionalTimeZoneFeature = 'timezone-four-names-2026e-v1';
const additionalTimeZoneMinimumBuild = 98;
const additionalTimeZoneCapabilityDescriptor = {
  'reader': 1,
  'minimumBuild': additionalTimeZoneMinimumBuild,
  'legacyData': legacyTimeZoneDataSha256,
  'additionalData': additionalTimeZoneDataSha256,
  'names': additionalTimeZoneNames,
};

class TimeZoneUpgradeRequired extends FormatException {
  const TimeZoneUpgradeRequired() : super(timeZoneUpgradeRequiredMessage);
}

// Location's constructor only reads these lists. TimeZone values themselves
// contain final Duration/bool/String fields, so only the three lists need copies.
tz.Location _immutableLocation(tz.Location location) => tz.Location(
  location.name,
  List<int>.unmodifiable(location.transitionAt),
  List<int>.unmodifiable(location.transitionZone),
  List<tz.TimeZone>.unmodifiable(location.zones),
);

final _utcLocation = tz.Location(
  'Etc/UTC',
  const [tz.minTime],
  const [0],
  const [tz.TimeZone.UTC],
);

Map<String, tz.Location>? _locations;
tz.Location timeZoneLocation(String name) {
  if (name == 'UTC') return _utcLocation;
  var locations = _locations;
  if (locations == null) {
    // Capture the four explicitly pinned new names before loading legacy data.
    // Workspace admission policy is separate from this pure format resolver.
    additional_database.initializeTimeZones();
    final additional = {
      for (final name in additionalTimeZoneNames)
        name: _immutableLocation(tz.getLocation(name)),
    };
    database.initializeTimeZones();
    locations = Map<String, tz.Location>.unmodifiable({
      ...additional,
      for (final entry in tz.timeZoneDatabase.locations.entries)
        entry.key: _immutableLocation(entry.value),
    });
    _locations = locations;
  }
  final location = locations[name];
  if (location == null) {
    throw tz.LocationNotFoundException(
      'Location with the name "$name" does not exist',
    );
  }
  return location;
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
  return resolveCivilWallTime(civil, zone);
}

/// Resolve already validated civil components, including internal exclusive
/// end-of-day boundaries beyond the public four-digit date range. This value
/// carries calendar components, not an instant or a device-local zone.
ResolvedWallTime resolveCivilWallTime(DateTime civil, String zone) {
  civil = DateTime.utc(
    civil.year,
    civil.month,
    civil.day,
    civil.hour,
    civil.minute,
  );
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
