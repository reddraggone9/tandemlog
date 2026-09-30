import 'wall_time.dart';

/// Civil task dates. These values are not device-local DateTime instants.
///
/// Recurrence semantics match the observed Obsidian Tasks 7.20.0 subset:
/// due > scheduled > start reference, preserved day offsets, and configured
/// scheduled-date removal. Implementation is independent of the upstream code.
class TaskSchedule {
  final String? startDate;
  final String? scheduledDate;
  final String? dueDate;
  final String? startTime;
  final String? scheduledTime;
  final String? dueTime;
  final String? timeZone;
  final String? recurrence;
  final int? dueMinDays;
  final int? dueMaxDays;

  static const keys = {
    'startDate',
    'scheduledDate',
    'dueDate',
    'startTime',
    'scheduledTime',
    'dueTime',
    'timeZone',
    'recurrence',
    'dueMinDays',
    'dueMaxDays',
  };

  factory TaskSchedule({
    String? startDate,
    String? scheduledDate,
    String? dueDate,
    String? startTime,
    String? scheduledTime,
    String? dueTime,
    String? timeZone,
    String? recurrence,
    int? dueMinDays,
    int? dueMaxDays,
  }) {
    if ((dueMinDays != null && dueMinDays < 0) ||
        (dueMaxDays != null && dueMaxDays < 0) ||
        (dueMinDays != null && dueMaxDays != null && dueMinDays > dueMaxDays)) {
      throw const FormatException(
        'Due bounds must be nonnegative days, with minimum no greater than maximum.',
      );
    }
    for (final date in [startDate, scheduledDate, dueDate]) {
      if (date != null) parseCivilDate(date);
    }
    for (final (label, date, time) in [
      ('Start', startDate, startTime),
      ('Scheduled', scheduledDate, scheduledTime),
      ('Due', dueDate, dueTime),
    ]) {
      if (time != null &&
          !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
        throw FormatException('$label time must be HH:mm.');
      }
      if (time != null && date == null) {
        throw FormatException(
          'Choose a ${label.toLowerCase()} date before adding a time.',
        );
      }
    }
    if (timeZone != null) {
      try {
        timeZoneLocation(timeZone);
      } catch (_) {
        throw const FormatException('Unknown time zone identifier.');
      }
    }
    if (startDate != null && dueDate != null) {
      // Date-only start means beginning of day. Date-only due includes that
      // whole day; an exact due time is inclusive. Never use elapsed 24 hours
      // to find the end of a named-zone day across DST.
      DateTime resolve(DateTime day, String time) {
        final parts = time.split(':').map(int.parse).toList();
        final civil = DateTime.utc(
          day.year,
          day.month,
          day.day,
          parts[0],
          parts[1],
        );
        return timeZone == null
            ? civil
            : resolveCivilWallTime(civil, timeZone).instant;
      }

      final start = resolve(parseCivilDate(startDate), startTime ?? '00:00');
      final due = dueTime != null
          ? resolve(parseCivilDate(dueDate), dueTime)
          : resolve(
              parseCivilDate(dueDate).add(const Duration(days: 1)),
              '00:00',
            );
      if (dueTime == null ? !start.isBefore(due) : start.isAfter(due)) {
        throw const FormatException(
          'Start must be on or before the due date and time.',
        );
      }
    }
    if (recurrence != null) {
      _Rule.parse(recurrence);
      if (dueDate == null && scheduledDate == null && startDate == null) {
        throw const FormatException('Repeating tasks need a reference date.');
      }
    }
    return TaskSchedule._(
      startDate,
      scheduledDate,
      dueDate,
      startTime,
      scheduledTime,
      dueTime,
      timeZone,
      recurrence,
      dueMinDays,
      dueMaxDays,
    );
  }

  const TaskSchedule._(
    this.startDate,
    this.scheduledDate,
    this.dueDate,
    this.startTime,
    this.scheduledTime,
    this.dueTime,
    this.timeZone,
    this.recurrence,
    this.dueMinDays,
    this.dueMaxDays,
  );

  factory TaskSchedule.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => !keys.contains(key)) ||
        json.entries.any(
          (entry) =>
              entry.value != null &&
              ({'dueMinDays', 'dueMaxDays'}.contains(entry.key)
                  ? entry.value is! int
                  : entry.value is! String),
        )) {
      throw const FormatException('Unknown or invalid schedule field.');
    }
    return TaskSchedule(
      startDate: json['startDate'] as String?,
      scheduledDate: json['scheduledDate'] as String?,
      dueDate: json['dueDate'] as String?,
      startTime: json['startTime'] as String?,
      scheduledTime: json['scheduledTime'] as String?,
      dueTime: json['dueTime'] as String?,
      timeZone: json['timeZone'] as String?,
      recurrence: json['recurrence'] as String?,
      dueMinDays: json['dueMinDays'] as int?,
      dueMaxDays: json['dueMaxDays'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'startDate': startDate,
    'scheduledDate': scheduledDate,
    'dueDate': dueDate,
    'startTime': startTime,
    'scheduledTime': scheduledTime,
    'dueTime': dueTime,
    'timeZone': timeZone,
    'recurrence': recurrence,
    'dueMinDays': dueMinDays,
    'dueMaxDays': dueMaxDays,
  };

  String? get referenceDate => dueDate ?? scheduledDate ?? startDate;

  TaskSchedule next(DateTime completionDay) {
    if (recurrence == null || referenceDate == null) {
      throw StateError('A recurrence and reference date are required.');
    }
    final rule = _Rule.parse(recurrence!);
    final reference = parseCivilDate(referenceDate!);
    final anchor = rule.whenDone
        ? DateTime.utc(
            completionDay.year,
            completionDay.month,
            completionDay.day,
          )
        : reference;
    final nextReference = rule.next(anchor);
    String? shift(String? date) => date == null
        ? null
        : formatCivilDate(
            nextReference.add(
              Duration(days: parseCivilDate(date).difference(reference).inDays),
            ),
          );
    return TaskSchedule(
      startDate: shift(startDate),
      scheduledDate: startDate != null || dueDate != null
          ? null
          : shift(scheduledDate),
      dueDate: shift(dueDate),
      startTime: startTime,
      scheduledTime: startDate != null || dueDate != null
          ? null
          : scheduledTime,
      dueTime: dueTime,
      timeZone: timeZone,
      recurrence: recurrence,
      dueMinDays: dueMinDays,
      dueMaxDays: dueMaxDays,
    );
  }
}

DateTime parseCivilDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Date must be YYYY-MM-DD.');
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8));
  final result = DateTime.utc(year, month, day);
  if (year < 1 ||
      result.year != year ||
      result.month != month ||
      result.day != day) {
    throw const FormatException('Invalid calendar date.');
  }
  return result;
}

String formatCivilDate(DateTime value) {
  if (value.year < 1 || value.year > 9999) {
    throw const FormatException('Date outside supported years 0001–9999.');
  }
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

void validateSchedule(Map<String, dynamic> value) =>
    TaskSchedule.fromJson(value);
Map<String, dynamic> nextSchedule(
  Map<String, dynamic> value,
  DateTime completionDay,
) => TaskSchedule.fromJson(value).next(completionDay).toJson();

class _Rule {
  final String unit;
  final int interval;
  final bool whenDone;
  final List<int>? weekdays;
  final String? constraint;
  const _Rule(
    this.unit,
    this.interval,
    this.whenDone, [
    this.weekdays,
    this.constraint,
  ]);

  static const weekdayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static _Rule parse(String text) {
    final normalized = text.toLowerCase();
    final done = normalized.endsWith(' when done');
    final rule = done
        ? normalized.substring(0, normalized.length - 10)
        : normalized;
    if (rule == 'every january, april, july and october on the 1st') {
      return _Rule('quarterMonths', 1, done);
    }
    if (rule == 'every weekday') {
      return _Rule('weekdays', 1, done, [1, 2, 3, 4, 5]);
    }
    final match = RegExp(
      r'^every (?:(\d+) )?(day|week|month|year)s?(?: on (.+))?$',
    ).firstMatch(rule);
    if (match == null) throw FormatException('Unsupported recurrence: $text');
    final interval = int.parse(match[1] ?? '1');
    if (interval < 1 || interval > 999) {
      throw const FormatException('Recurrence interval must be 1–999.');
    }
    final unit = match[2]!;
    final suffix = match[3];
    if (suffix == null) return _Rule(unit, interval, done);
    if (unit == 'week') {
      final names = suffix.split(', ');
      if (names.any((name) => !weekdayNames.contains(name))) {
        throw FormatException('Unsupported weekdays: $suffix');
      }
      return _Rule(
        unit,
        interval,
        done,
        names.map((name) => weekdayNames.indexOf(name) + 1).toSet().toList(),
      );
    }
    if (unit == 'month' &&
        (suffix == 'the last' || suffix == 'the 1st friday')) {
      return _Rule(unit, interval, done, null, suffix);
    }
    throw FormatException('Unsupported recurrence constraint: $text');
  }

  DateTime next(DateTime anchor) {
    if (unit == 'day') return anchor.add(Duration(days: interval));
    if (unit == 'week' && weekdays == null) {
      return anchor.add(Duration(days: 7 * interval));
    }
    if (unit == 'year' || (unit == 'month' && constraint == null)) {
      final target = DateTime.utc(
        anchor.year,
        anchor.month + interval * (unit == 'year' ? 12 : 1),
        1,
      );
      final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
      return DateTime.utc(
        target.year,
        target.month,
        anchor.day > lastDay ? lastDay : anchor.day,
      );
    }
    if (unit == 'month') {
      // A constrained rule may still match later in its anchor month.
      for (var offset = 0; offset <= interval; offset += interval) {
        final month = DateTime.utc(anchor.year, anchor.month + offset, 1);
        final candidate = constraint == 'the last'
            ? DateTime.utc(month.year, month.month + 1, 0)
            : DateTime.utc(
                month.year,
                month.month,
                1 + (DateTime.friday - month.weekday + 7) % 7,
              );
        if (candidate.isAfter(anchor)) return candidate;
      }
    }
    if (unit == 'quarterMonths') {
      for (var offset = 0; offset <= 12; offset++) {
        final day = DateTime.utc(anchor.year, anchor.month + offset, 1);
        if ((day.month - 1) % 3 == 0 && day.isAfter(anchor)) return day;
      }
    }
    if (weekdays != null) {
      final weekStart = anchor.subtract(Duration(days: anchor.weekday - 1));
      for (var offset = 1; offset <= interval * 7 + 7; offset++) {
        final day = anchor.add(Duration(days: offset));
        final week = day.difference(weekStart).inDays ~/ 7;
        if (week % interval == 0 && weekdays!.contains(day.weekday)) return day;
      }
    }
    throw StateError('Unable to advance recurrence.');
  }
}

/// Sanitized rule inventory used for parity fixtures and editor suggestions.
const observedRecurrences = <String>[
  'every day when done',
  'every 2 days when done',
  'every 5 days when done',
  'every 9 days when done',
  'every 20 days when done',
  'every 25 days when done',
  'every week when done',
  'every 2 weeks when done',
  'every 3 weeks when done',
  'every 4 weeks when done',
  'every 6 weeks when done',
  'every 7 weeks when done',
  'every 8 weeks when done',
  'every 13 weeks when done',
  'every 26 weeks when done',
  'every month when done',
  'every 3 months when done',
  'every 4 months when done',
  'every 6 months when done',
  'every year when done',
  'every 5 years when done',
  'every weekday when done',
  'every week on Monday when done',
  'every week on Friday when done',
  'every week on Saturday when done',
  'every week on Wednesday, Sunday when done',
  'every week on Monday, Tuesday, Wednesday, Thursday, Friday, Saturday when done',
  'every month on the last when done',
  'every day',
  'every 36 days',
  'every week',
  'every week on Monday',
  'every month on the last',
  'every 3 months on the 1st Friday',
  'every 3 months on the last',
  'every January, April, July and October on the 1st',
  'every year',
];
