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

List<TaskViewGroup> _groups(List<TaskViewEntry> entries) {
  final groups = <TaskViewGroup>[];
  for (final entry in entries) {
    final date = entry.effectiveDate == null
        ? null
        : formatCivilDate(entry.effectiveDate!);
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

/// Derive visible tasks, effective-date groups, and the next clock boundary.
/// Input order is the shared manual order. This function never changes tasks,
/// schedules, deadlines, recurrence anchors or canonical logs.
TimedView<TaskView> projectTaskView(
  List<Map<String, dynamic>> rows,
  ViewTime time, {
  String? assignee,
}) {
  final localZone = timeZoneLocation(time.localZoneId);
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

  final nowCivil = localCivil(time.instant);
  final today = DateTime.utc(nowCivil.year, nowCivil.month, nowCivil.day);
  DateTime boundDay(int days) {
    // Validate before constructing Duration: multiplying attacker-controlled
    // integer days by microseconds can overflow before DateTime sees it.
    final remaining = DateTime.utc(9999, 12, 31).difference(today).inDays;
    if (days > remaining) {
      throw const FormatException(
        'Due bound exceeds the supported calendar range.',
      );
    }
    return today.add(Duration(days: days));
  }

  DateTime? nextChange;
  void boundary(DateTime value) {
    if (value.isAfter(time.instant) &&
        (nextChange == null || value.isBefore(nextChange!))) {
      nextChange = value.toUtc();
    }
  }

  DateTime civil(String date, String? time) {
    final day = parseCivilDate(date);
    final parts = (time ?? '00:00').split(':').map(int.parse).toList();
    return DateTime.utc(day.year, day.month, day.day, parts[0], parts[1]);
  }

  final open = <(int, TaskViewEntry)>[];
  final completed = <(int, TaskViewEntry)>[];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row['kind'] != 'task' ||
        (assignee != null && row['assignee'] != assignee)) {
      continue;
    }
    final schedule = TaskSchedule.fromJson(
      Map<String, dynamic>.from(row['schedule'] as Map? ?? {}),
    );
    final done = row['completed'] == true;
    if (schedule.dueMinDays != null || schedule.dueMaxDays != null) {
      boundary(
        resolveCivilWallTime(
          DateTime.utc(today.year, today.month, today.day + 1),
          time.localZoneId,
        ).instant,
      );
    }
    if (!done && schedule.startDate != null) {
      final start = resolveCivilWallTime(
        civil(schedule.startDate!, schedule.startTime),
        schedule.startTime == null
            ? time.localZoneId
            : schedule.timeZone ?? time.localZoneId,
      ).instant;
      if (start.isAfter(time.instant)) {
        boundary(start);
        continue;
      }
    }
    final date = schedule.scheduledDate ?? schedule.dueDate;
    final preciseTime = schedule.scheduledDate != null
        ? schedule.scheduledTime
        : schedule.dueTime;
    DateTime? effective;
    if (date != null) {
      effective = civil(date, preciseTime);
      // Date-only values retain their civil day. Pinned exact times denote an
      // instant, so their displayed group follows the viewer's local calendar.
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
    if (schedule.dueMinDays != null || schedule.dueMaxDays != null) {
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
    (done ? completed : open).add((index, TaskViewEntry(row, effective)));
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
