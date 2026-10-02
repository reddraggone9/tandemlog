import 'event.dart';
import 'schedule.dart' hide validateSchedule;

/// Only explicitly supplied schedule fields change; null clears a field.
class BulkTaskEdit {
  final Map<String, dynamic> schedulePatch;
  final String? assignee;
  final List<String> addTags, removeTags;
  BulkTaskEdit({
    Map<String, dynamic> schedulePatch = const {},
    this.assignee,
    List<String> addTags = const [],
    List<String> removeTags = const [],
  }) : schedulePatch = Map.unmodifiable(schedulePatch),
       addTags = List.unmodifiable(addTags),
       removeTags = List.unmodifiable(removeTags);

  Map<String, dynamic> fieldsFor(Map<String, dynamic> task) {
    if (schedulePatch.keys.any((key) => !TaskSchedule.keys.contains(key))) {
      throw FormatFailure('Unknown schedule field.');
    }
    validateTags(addTags);
    validateTags(removeTags);
    if (addTags.toSet().intersection(removeTags.toSet()).isNotEmpty) {
      throw FormatFailure('A tag cannot be added and removed together.');
    }
    final fields = <String, dynamic>{};
    if (assignee != null && assignee != task['assignee']) {
      fields['assignee'] = assignee;
    }
    if (schedulePatch.isNotEmpty) {
      final schedule = <String, dynamic>{
        ...Map<String, dynamic>.from(task['schedule'] as Map),
        ...schedulePatch,
      };
      validateSchedule(schedule);
      final normalized = TaskSchedule.fromJson(schedule).toJson();
      final original = TaskSchedule.fromJson(
        Map<String, dynamic>.from(task['schedule'] as Map),
      ).toJson();
      if (normalized.entries.any((e) => e.value != original[e.key])) {
        fields['schedule'] = normalized;
      }
    }
    final refs = Map<String, String>.from(task['tagRefs'] as Map);
    final added = addTags.toSet().difference(refs.values.toSet()).toList()
      ..sort();
    final removed =
        refs.entries
            .where((e) => removeTags.contains(e.value))
            .map((e) => e.key)
            .toList()
          ..sort();
    if (added.isNotEmpty || removed.isNotEmpty) {
      fields['tagChanges'] = {'add': added, 'remove': removed};
    }
    return fields;
  }
}

/// Each successful task is durably committed independently. On an I/O failure,
/// the first remaining task may have appended; refresh and reconcile it against
/// canonical history before retrying the uncommitted tail. Blindly retrying all
/// remaining IDs can change block order or include already deleted tasks.
class BulkTaskResult {
  final List<String> committedIds, remainingIds;
  final Object? error;
  BulkTaskResult(
    Iterable<String> committed,
    Iterable<String> remaining, [
    this.error,
  ]) : committedIds = List.unmodifiable(committed),
       remainingIds = List.unmodifiable(remaining);
  bool get succeeded => error == null && remainingIds.isEmpty;
}
