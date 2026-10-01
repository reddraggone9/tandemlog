import 'package:timezone/timezone.dart' as tz;

import 'schedule.dart';
import 'timed_view.dart';
import 'wall_time.dart';

/// An unchanged persisted task plus its derived local civil sorting value.
/// Null is Someday, not a fabricated distant deadline. Dates at midnight may
/// be date-only; original precision remains in [task]'s schedule.
class TaskViewEntry {
  const TaskViewEntry(this.task, this.effectiveDate);
  final Map<String, dynamic> task;
  final DateTime? effectiveDate;
}

class TaskViewGroup {
  const TaskViewGroup(this.date, this.weekday, this.entries);
  final String? date;
  final int? weekday;
  final List<TaskViewEntry> entries;
}

class TaskView {
  TaskView(this.open, this.completed)
    : openGroups = _groups(open),
      completedGroups = _groups(completed);
  final List<TaskViewEntry> open;
  final List<TaskViewEntry> completed;
  final List<TaskViewGroup> openGroups;
  final List<TaskViewGroup> completedGroups;
}

// Group dates are derived values, so a supported relative horizon may extend
// beyond the four-digit range permitted for persisted user-entered dates.
String _groupDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

List<TaskViewGroup> _groups(List<TaskViewEntry> entries) {
  final groups = <TaskViewGroup>[];
  for (final entry in entries) {
    final date = entry.effectiveDate == null
        ? null
        : _groupDate(entry.effectiveDate!);
    if (groups.isEmpty || groups.last.date != date) {
      groups.add(TaskViewGroup(date, entry.effectiveDate?.weekday, [entry]));
    } else {
      groups.last.entries.add(entry);
    }
  }
  return List.unmodifiable(
    groups.map(
      (group) => TaskViewGroup(
        group.date,
        group.weekday,
        List.unmodifiable(group.entries),
      ),
    ),
  );
}

/// Clock-derived timing for any task, including hidden or completed tasks.
/// [availabilityStart] defaults to today's local midnight when no start exists;
/// that compatibility value does not invent a persisted start date.
class TaskTiming {
  const TaskTiming({
    required this.availabilityStart,
    required this.available,
    required this.effectiveDate,
    required this.nextChange,
    DateTime? nextSortChange,
  }) : _nextSortChange = nextSortChange;
  final DateTime availabilityStart;
  final bool available;
  final DateTime? effectiveDate;
  final DateTime? nextChange;
  final DateTime? _nextSortChange;
}

TaskTiming evaluateTaskTiming(TaskSchedule schedule, ViewTime time) =>
    _TaskTimingContext(time).evaluate(schedule);

// Shared by standalone evaluation and the complete projection. A projection
// reuses the local-day/zone context and lazily resolves midnight only once.
class _TaskTimingContext {
  _TaskTimingContext(this.time)
    : localZone = timeZoneLocation(time.localZoneId) {
    final local = localCivil(time.instant);
    today = DateTime.utc(local.year, local.month, local.day);
  }
  final ViewTime time;
  final tz.Location localZone;
  late final DateTime today;
  DateTime? _nextMidnight;
  DateTime? _todayMidnight;

  DateTime localCivil(DateTime instant) {
    final local = tz.TZDateTime.from(instant, localZone);
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }

  DateTime civil(String date, String? time) {
    final day = parseCivilDate(date);
    final parts = (time ?? '00:00').split(':').map(int.parse).toList();
    return DateTime.utc(day.year, day.month, day.day, parts[0], parts[1]);
  }

  DateTime boundDay(int days) {
    try {
      return today.add(Duration(days: days));
    } on ArgumentError {
      throw const FormatException(
        'Current clock and sort-date bound exceed the supported calendar range.',
      );
    }
  }

  TaskTiming evaluate(TaskSchedule schedule) {
    final start = schedule.startDate == null
        ? _todayMidnight ??= resolveCivilWallTime(
            today,
            time.localZoneId,
          ).instant
        : resolveCivilWallTime(
            civil(schedule.startDate!, schedule.startTime),
            schedule.timeZone ?? time.localZoneId,
          ).instant;
    final available =
        schedule.startDate == null || !start.isAfter(time.instant);
    final date = schedule.scheduledDate ?? schedule.dueDate;
    final preciseTime = schedule.scheduledDate != null
        ? schedule.scheduledTime
        : schedule.dueTime;
    DateTime? effective;
    if (date != null) {
      effective = civil(date, preciseTime);
      // Date-only effective dates keep their civil day. Pinned exact values
      // use the viewer's local calendar, preserving precise clock time.
      if (preciseTime != null && schedule.timeZone != null) {
        effective = localCivil(
          resolveCivilWallTime(effective, schedule.timeZone!).instant,
        );
      }
    }
    DateTime withDay(DateTime day) => DateTime.utc(
      day.year,
      day.month,
      day.day,
      effective?.hour ?? 0,
      effective?.minute ?? 0,
    );
    DateTime? sortChange;
    if (schedule.dueMinDays != null || schedule.dueMaxDays != null) {
      sortChange = _nextMidnight ??= resolveCivilWallTime(
        DateTime.utc(today.year, today.month, today.day + 1),
        time.localZoneId,
      ).instant;
      if (schedule.dueMinDays != null && effective != null) {
        final min = boundDay(schedule.dueMinDays!);
        final effectiveDay = DateTime.utc(
          effective.year,
          effective.month,
          effective.day,
        );
        if (effectiveDay.isBefore(min)) effective = withDay(min);
      }
      if (schedule.dueMaxDays != null) {
        final max = boundDay(schedule.dueMaxDays!);
        final effectiveDay = effective == null
            ? null
            : DateTime.utc(effective.year, effective.month, effective.day);
        if (effectiveDay == null || effectiveDay.isAfter(max)) {
          effective = withDay(max);
        }
      }
    }
    DateTime? next = sortChange;
    if (!available && (next == null || start.isBefore(next))) next = start;
    return TaskTiming(
      availabilityStart: start,
      available: available,
      effectiveDate: effective,
      nextChange: next,
      nextSortChange: sortChange,
    );
  }
}

/// Input order is shared manual order. Derived values never mutate persisted
/// tasks, deadlines or recurrence anchors. Completed history stays accessible.
TimedView<TaskView> projectTaskView(
  List<Map<String, dynamic>> rows,
  ViewTime time, {
  String? assignee,
  bool includeUpcoming = false,
  String? tag,
}) {
  final context = _TaskTimingContext(time);
  DateTime? nextChange;
  final open = <(int, TaskViewEntry)>[];
  final completed = <(int, TaskViewEntry)>[];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row['kind'] != 'task' ||
        (assignee != null && row['assignee'] != assignee) ||
        (tag != null && !(row['tags'] as List? ?? []).contains(tag))) {
      continue;
    }
    final schedule = TaskSchedule.fromJson(
      Map<String, dynamic>.from(row['schedule'] as Map? ?? {}),
    );
    final timing = context.evaluate(schedule);
    final done = row['completed'] == true;
    final next = done ? timing._nextSortChange : timing.nextChange;
    if (next != null && (nextChange == null || next.isBefore(nextChange))) {
      nextChange = next;
    }
    if (!done && !includeUpcoming && !timing.available) continue;
    (done ? completed : open).add((
      index,
      TaskViewEntry(row, timing.effectiveDate),
    ));
  }
  List<TaskViewEntry> sorted(List<(int, TaskViewEntry)> values) {
    values.sort((a, b) {
      final x = a.$2.effectiveDate, y = b.$2.effectiveDate;
      final order = x == null
          ? (y == null ? 0 : 1)
          : y == null
          ? -1
          : x.compareTo(y);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    return List.unmodifiable(values.map((value) => value.$2));
  }

  return TimedView(
    TaskView(sorted(open), sorted(completed)),
    nextChange: nextChange,
  );
}
