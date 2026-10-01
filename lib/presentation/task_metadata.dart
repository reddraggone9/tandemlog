/// Day-group rows show times; full calendar dates belong in the editor.
String scheduleMetadata(
  Map<String, dynamic> schedule, {
  required String? groupDate,
}) {
  String detail(String role, String dateKey, String timeKey) {
    final date = schedule[dateKey] as String?;
    final time = schedule[timeKey] as String?;
    final zone = time == null ? null : schedule['timeZone'] as String?;
    if (date == null && time == null) return '';
    final parts = [if (groupDate == null && date != null) date, ?time, ?zone];
    return parts.isEmpty ? '' : '$role ${parts.join(' ')}';
  }

  return [
    detail('Due', 'dueDate', 'dueTime'),
    detail('Scheduled', 'scheduledDate', 'scheduledTime'),
    detail('Start', 'startDate', 'startTime'),
    if (schedule['recurrence'] != null) '↻ ${schedule['recurrence']}',
  ].where((part) => part.isNotEmpty).join(' · ');
}
