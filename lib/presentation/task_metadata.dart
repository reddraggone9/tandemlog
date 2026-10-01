import 'package:timezone/timezone.dart' as tz;

import '../domain/wall_time.dart';

/// Schedule details relative to the day actually displayed above the row.
String scheduleMetadata(
  Map<String, dynamic> schedule, {
  required String? groupDate,
  required String localZoneId,
}) {
  String detail(String role, String dateKey, String timeKey) {
    final date = schedule[dateKey] as String?;
    final time = schedule[timeKey] as String?;
    final zone = time == null ? null : schedule['timeZone'] as String?;
    if (date == null && time == null) return '';
    var sameDay = date != null && date == groupDate;
    if (sameDay && time != null && zone != null) {
      final instant = resolveZonedWallTime(date, time, zone).instant;
      final local = tz.TZDateTime.from(instant, timeZoneLocation(localZoneId));
      final localDate =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      sameDay = localDate == groupDate;
    }
    final parts = [if (!sameDay && date != null) date, ?time, ?zone];
    return parts.isEmpty ? '' : '$role ${parts.join(' ')}';
  }

  return [
    detail('Due', 'dueDate', 'dueTime'),
    detail('Scheduled', 'scheduledDate', 'scheduledTime'),
    detail('Start', 'startDate', 'startTime'),
    if (schedule['recurrence'] != null) '↻ ${schedule['recurrence']}',
  ].where((part) => part.isNotEmpty).join(' · ');
}
