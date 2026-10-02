import 'package:timezone/timezone.dart' as tz;

import '../domain/wall_time.dart';

/// Due/occurrence dates stay in their group/editor; only unavailable starts
/// explain when a visible future task becomes available.
String scheduleMetadata(
  Map<String, dynamic> schedule, {
  required String? groupDate,
  required String localZoneId,
  required DateTime viewInstant,
  DateTime? unavailableStart,
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
    if (unavailableStart != null && unavailableStart.isAfter(viewInstant))
      _startHint(schedule, unavailableStart, viewInstant, localZoneId),
  ].where((part) => part.isNotEmpty).join(' · ');
}

String _startHint(
  Map<String, dynamic> schedule,
  DateTime start,
  DateTime now,
  String localZoneId,
) {
  final zone = timeZoneLocation(localZoneId);
  final local = tz.TZDateTime.from(start, zone);
  final today = tz.TZDateTime.from(now, zone);
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  final precise = schedule['startTime'] != null;
  final time = precise
      ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
      : null;
  if (sameDay) return 'Starts ${time ?? 'today'}';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return [
    'Starts ${months[local.month - 1]} ${local.day}',
    if (local.year != today.year) '${local.year}',
    ?time,
  ].join(' ');
}
