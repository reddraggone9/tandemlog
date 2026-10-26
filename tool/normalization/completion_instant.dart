// Offline conversion adapter only. No application startup/arrival inference.
// The external frozen reader must first verify source records and provide the
// ORIGINAL semantic clock and schedule zone immediately before this operation.
import 'package:tandemlog/domain/completion_instant.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/domain/wall_time.dart';
import 'package:tandemlog/application/task_clock.dart';

class NormalizedCompletionTime {
  const NormalizedCompletionTime(this.instant, this.method);
  final String instant;
  // Conversion-report evidence, never a canonical operation field or UI marker.
  final String method;
}

NormalizedCompletionTime normalizeCompletionTime({
  required String? completedAt,
  required BigInt originalClock,
  String? historicalZone,
}) {
  // Event clocks are canonical positive scalar nanoseconds, not tuple HLCs.
  if (originalClock < BigInt.zero ||
      originalClock > BigInt.parse('9223372036854775807')) {
    throw const FormatException('Invalid original semantic clock.');
  }
  final zone = historicalZone ?? 'UTC';
  timeZoneLocation(zone); // Unknown claimed evidence is a conversion error.
  final micros = originalClock ~/ BigInt.from(1000);
  DateTime? clockInstant;
  if (micros <= BigInt.from(253402300799999999)) {
    clockInstant = DateTime.fromMicrosecondsSinceEpoch(
      micros.toInt(),
      isUtc: true,
    );
  }
  if (completedAt == null) {
    if (clockInstant == null) {
      throw const FormatException('Unrepresentable completion clock.');
    }
    return NormalizedCompletionTime(
      encodeCompletionInstant(clockInstant),
      'clock-no-date',
    );
  }
  if (completedAt.length < 10) {
    throw const FormatException('Invalid legacy completion date.');
  }
  final recorded = completedAt.substring(0, 10);
  final day = parseCivilDate(recorded);
  final offsetMatch = RegExp(
    r'(Z|[+-][0-9]{2}:?[0-9]{2})$',
  ).firstMatch(completedAt);
  Duration? offset;
  if (completedAt.length > 10 && offsetMatch != null) {
    final raw = offsetMatch.group(0)!;
    if (raw == 'Z') {
      offset = Duration.zero;
    } else {
      final digits = raw.substring(1).replaceAll(':', '');
      final hours = int.parse(digits.substring(0, 2));
      final minutes = int.parse(digits.substring(2));
      if (hours > 23 || minutes > 59) {
        throw const FormatException('Invalid legacy offset.');
      }
      offset = Duration(
        minutes: (hours * 60 + minutes) * (raw.startsWith('-') ? -1 : 1),
      );
    }
  }
  String dateAt(DateTime instant) => formatCivilDate(
    offset == null ? civilDayAt(instant, zone) : instant.toUtc().add(offset),
  );
  NormalizedCompletionTime? accept(DateTime? instant, String method) {
    if (instant == null || dateAt(instant) != recorded) return null;
    return NormalizedCompletionTime(encodeCompletionInstant(instant), method);
  }

  if (completedAt.length > 10) {
    final explicit = DateTime.tryParse(completedAt);
    if (explicit == null) {
      throw const FormatException('Invalid legacy completion time.');
    }
    // Validate all wall components before using Dart's permissive ISO parser.
    final wall = DateTime.tryParse(
      '${completedAt.substring(0, completedAt.length - (offsetMatch?.group(0)?.length ?? 0))}Z',
    );
    if (wall == null || formatCivilDate(wall) != recorded) {
      throw const FormatException('Overflowed legacy completion time.');
    }
    final candidate = offset != null
        ? explicit.toUtc()
        : resolveCivilWallTime(wall, zone).instant.add(
            Duration(
              seconds: wall.second,
              milliseconds: wall.millisecond,
              microseconds: wall.microsecond,
            ),
          );
    final exact = accept(candidate, 'explicit');
    if (exact != null) return exact;
  }
  final fromClock = accept(clockInstant, 'clock');
  if (fromClock != null) return fromClock;
  final noon = offset == null
      ? resolveCivilWallTime(
          DateTime.utc(day.year, day.month, day.day, 12),
          zone,
        ).instant
      : DateTime.utc(day.year, day.month, day.day, 12).subtract(offset);
  return accept(noon, 'noon') ??
      NormalizedCompletionTime(
        encodeCompletionInstant(DateTime.utc(day.year, day.month, day.day, 12)),
        'skipped-date-utc-noon',
      );
}
