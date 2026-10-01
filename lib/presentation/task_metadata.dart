import 'package:timezone/timezone.dart' as tz;

import '../domain/wall_time.dart';

/// Day-group rows show times; full calendar dates belong in the editor.
String scheduleMetadata(
  Map<String, dynamic> schedule, {
  required String? groupDate,
  required String localZoneId,
}) {
  String detail(String role, String dateKey, String timeKey) {
    var date = schedule[dateKey] as String?;
    var time = schedule[timeKey] as String?;
    final zone = time == null ? null : schedule['timeZone'] as String?;
    if (date == null && time == null) return '';
    if (date != null && time != null && zone != null) {
      final instant = resolveZonedWallTime(date, time, zone).instant;
      final local = tz.TZDateTime.from(instant, timeZoneLocation(localZoneId));
      date =
          '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      time =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    final parts = [if (groupDate == null && date != null) date, ?time];
    return parts.isEmpty ? '' : '$role ${parts.join(' ')}';
  }

  return [
    if (schedule['scheduledDate'] == null) detail('Due', 'dueDate', 'dueTime'),
    detail('Scheduled', 'scheduledDate', 'scheduledTime'),
    detail('Start', 'startDate', 'startTime'),
    if (schedule['recurrence'] != null) '↻ ${schedule['recurrence']}',
  ].where((part) => part.isNotEmpty).join(' · ');
}
