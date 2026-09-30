/// One consistent observation for a pure time-dependent view calculation.
/// Zone identity is supplied by the platform, not inferred from its UTC offset:
/// two zones can share today's offset and have different future transitions.
class ViewTime {
  ViewTime({
    required DateTime instant,
    required this.localZoneId,
    required this.localOffset,
  }) : instant = instant.toUtc();

  final DateTime instant;
  final String localZoneId;
  final Duration localOffset;

  bool sameZone(ViewTime other) =>
      localZoneId == other.localZoneId && localOffset == other.localOffset;
}

/// A policy supplies both its value and the earliest future change boundary.
/// A null boundary means time alone cannot change this result. This contract
/// deliberately defines no task visibility, due-bound or sorting policy.
class TimedView<T> {
  const TimedView(this.value, {this.nextChange});
  final T value;
  final DateTime? nextChange;
}

typedef ViewProjection<T> = TimedView<T> Function(ViewTime time);
