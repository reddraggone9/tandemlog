/// Hybrid logical timestamp. Physical time approximates concurrent recency;
/// logical increments preserve causality without borrowing future milliseconds.
class HlcClock implements Comparable<HlcClock> {
  static const maxInteger = 9007199254740991;
  final int wallMs;
  final int logical;
  const HlcClock(this.wallMs, this.logical);

  factory HlcClock.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        !value.containsKey('wallMs') ||
        !value.containsKey('logical') ||
        value.values.any((x) => x is! int || x < 0 || x > maxInteger)) {
      throw const FormatException('Unsupported or invalid hybrid event clock.');
    }
    return HlcClock(value['wallMs'] as int, value['logical'] as int);
  }

  static HlcClock next(int nowMs, HlcClock? maximumSeen) {
    if (nowMs < 0 || nowMs > maxInteger) {
      throw const FormatException(
        'System clock is outside the supported range.',
      );
    }
    if (maximumSeen == null || nowMs > maximumSeen.wallMs) {
      return HlcClock(nowMs, 0);
    }
    if (maximumSeen.logical == maxInteger) {
      throw const FormatException('Hybrid logical counter exhausted.');
    }
    return HlcClock(maximumSeen.wallMs, maximumSeen.logical + 1);
  }

  Map<String, int> toJson() => {'wallMs': wallMs, 'logical': logical};
  String get sortKey =>
      '${wallMs.toString().padLeft(16, '0')}:${logical.toString().padLeft(16, '0')}';
  @override
  int compareTo(HlcClock other) {
    final physical = wallMs.compareTo(other.wallMs);
    return physical == 0 ? logical.compareTo(other.logical) : physical;
  }

  bool operator <(HlcClock other) => compareTo(other) < 0;
  bool operator <=(HlcClock other) => compareTo(other) <= 0;
  bool operator >(HlcClock other) => compareTo(other) > 0;
  bool operator >=(HlcClock other) => compareTo(other) >= 0;
  @override
  bool operator ==(Object other) =>
      other is HlcClock && wallMs == other.wallMs && logical == other.logical;
  @override
  int get hashCode => Object.hash(wallMs, logical);
  @override
  String toString() => '$wallMs:$logical';
}
