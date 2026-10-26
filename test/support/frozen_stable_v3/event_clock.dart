/// Wall-time-aware logical clock matching the original design. Canonical wire
/// values are decimal strings, never JSON numbers, so nanoseconds stay exact.
class EventClock implements Comparable<EventClock> {
  static final maximum = BigInt.parse('9223372036854775807');
  final BigInt value;
  EventClock(this.value);

  factory EventClock.fromJson(dynamic raw) {
    if (raw is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(raw)) {
      throw const FormatException(
        'Unsupported event clock: expected an exact decimal string.',
      );
    }
    final value = BigInt.parse(raw);
    if (value > maximum) {
      throw const FormatException(
        'Event clock exceeds the signed 64-bit range.',
      );
    }
    return EventClock(value);
  }

  static EventClock next(BigInt nowNs, EventClock? maximumSeen) {
    if (nowNs.isNegative || nowNs > maximum) {
      throw const FormatException(
        'System clock is outside the supported range.',
      );
    }
    final result = maximumSeen == null || nowNs > maximumSeen.value
        ? nowNs
        : maximumSeen.value + BigInt.one;
    if (result > maximum) {
      throw const FormatException(
        'Event clock exhausted its signed 64-bit range.',
      );
    }
    return EventClock(result);
  }

  String toJson() => value.toString();
  String get sortKey => value.toString().padLeft(19, '0');
  @override
  int compareTo(EventClock other) => value.compareTo(other.value);
  bool operator <(EventClock other) => compareTo(other) < 0;
  bool operator <=(EventClock other) => compareTo(other) <= 0;
  bool operator >(EventClock other) => compareTo(other) > 0;
  bool operator >=(EventClock other) => compareTo(other) >= 0;
  @override
  bool operator ==(Object other) => other is EventClock && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value.toString();
}
