import 'schedule.dart';

/// A proposed ordinary schedule edit, not a replay or history migration.
///
/// The caller must refresh and revalidate its captured task snapshot before
/// writing. A plan cannot guard against unseen offline edits or update an
/// already-created recurring successor.
class OccurrenceDuePlan {
  final Map<String, dynamic> beforeSchedule;
  final TaskSchedule? afterSchedule;
  final String? conflict;

  const OccurrenceDuePlan._(
    this.beforeSchedule,
    this.afterSchedule,
    this.conflict,
  );
}

/// Moves an existing occurrence date/time into an absent Due field.
///
/// Start-backed repeats are deliberately eligible: retaining Due can change
/// later recurrence anchors after the old occurrence override would be cleared.
/// Completed rows are also eligible, but their historical completion payloads
/// and independently existing successors are outside this plan.
OccurrenceDuePlan? planOccurrenceDueMigration(Map<String, dynamic> task) {
  if (task['kind'] != 'task' || task['deleted'] == true) return null;
  final raw = task['schedule'];
  if (raw is! Map || raw['dueDate'] != null || raw['scheduledDate'] == null) {
    return null;
  }
  final before = Map<String, dynamic>.unmodifiable(
    Map<String, dynamic>.from(raw),
  );
  try {
    // Validate the original too, rather than repairing malformed legacy fields
    // by overwriting an orphan Due time or discarding an unknown field.
    TaskSchedule.fromJson(before);
    final after = TaskSchedule.fromJson({
      ...before,
      'dueDate': before['scheduledDate'],
      'dueTime': before['scheduledTime'],
      'scheduledDate': null,
      'scheduledTime': null,
    });
    return OccurrenceDuePlan._(before, after, null);
  } on FormatException catch (error) {
    return OccurrenceDuePlan._(before, null, error.message.toString());
  }
}
