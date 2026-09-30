import 'package:timezone/timezone.dart' as tz;

import '../domain/wall_time.dart';

/// Convert an explicitly captured instant to a calendar day for a command.
/// Persist that day; replay must never consult the device clock or timezone.
DateTime civilDayAt(DateTime instant, String? timeZone) {
  final DateTime local;
  if (timeZone == null) {
    local = instant.toLocal();
  } else {
    local = tz.TZDateTime.from(instant, timeZoneLocation(timeZone));
  }
  return DateTime.utc(local.year, local.month, local.day);
}
