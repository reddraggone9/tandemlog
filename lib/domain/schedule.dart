import 'wall_time.dart';

const supportedRecurrenceGrammar =
    'Use every N days/weeks/months/years; every weekday; every N weeks on '
    'Monday, Friday; every N months on the last, the 15th, or the '
    '1st/2nd/3rd/4th/last weekday (e.g. the 2nd Tuesday); or every '
    'January, May and September on the 15th. N is 1–999; month days are '
    '1st–31st. Add when done to calculate from completion.';

/// A required wire revision, not a migration or a normalization of saved text.
/// The previous reader accepted all ordinary intervals, weekly day lists,
/// monthly last-day/1st-Friday rules and the exact quarterly month literal.
bool recurrenceRequiresRevision4(String text) => _Rule.parse(text).extended;

const unchangedRecurrenceMessage =
    'The next occurrence would have the same dates. Complete this task later or edit its schedule.';

class ScheduleValidationException extends FormatException {
  const ScheduleValidationException(super.message, this.fields);
  final List<String> fields;
}

/// Civil task dates. These values are not device-local DateTime instants.
///
/// Recurrence semantics match the observed Obsidian Tasks 7.20.0 subset:
/// due > scheduled > start reference, preserved day offsets, and configured
/// scheduled-date removal. Implementation is independent of the upstream code.
class TaskSchedule {
  /// A finite 1000-year relative horizon, far beyond practical task planning.
  /// Reject at admission before untrusted integers reach duration arithmetic.
  static const maxRelativeDays = 365000;

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
    if ((dueMinDays != null &&
            (dueMinDays < 0 || dueMinDays > maxRelativeDays)) ||
        (dueMaxDays != null &&
            (dueMaxDays < 0 || dueMaxDays > maxRelativeDays)) ||
        (dueMinDays != null && dueMaxDays != null && dueMinDays > dueMaxDays)) {
      throw const ScheduleValidationException(
        'Sort-date bounds must be 0–365000 days, with minimum no greater than maximum.',
        ['dueMinDays', 'dueMaxDays'],
      );
    }
    for (final (field, date) in [
      ('startDate', startDate),
      ('scheduledDate', scheduledDate),
      ('dueDate', dueDate),
    ]) {
      if (date != null) {
        try {
          parseCivilDate(date);
        } on FormatException catch (error) {
          throw ScheduleValidationException(error.message, [field]);
        }
      }
    }
    for (final (field, label, date, time) in [
      ('start', 'Start', startDate, startTime),
      ('scheduled', 'This occurrence', scheduledDate, scheduledTime),
      ('due', 'Due', dueDate, dueTime),
    ]) {
      if (time != null &&
          !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
        throw ScheduleValidationException('$label time must be HH:mm.', [
          '${field}Time',
        ]);
      }
      if (time != null && date == null) {
        throw ScheduleValidationException(
          'Choose a ${label.toLowerCase()} date before adding a time.',
          ['${field}Time', '${field}Date'],
        );
      }
    }
    if (timeZone != null) {
      try {
        timeZoneLocation(timeZone);
      } on TimeZoneUpgradeRequired catch (error) {
        throw ScheduleValidationException(error.message, ['timeZone']);
      } catch (_) {
        throw const ScheduleValidationException(
          'Unknown time zone identifier.',
          ['timeZone'],
        );
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
        throw const ScheduleValidationException(
          'Start must be on or before the due date and time.',
          ['startDate', 'startTime', 'dueDate', 'dueTime'],
        );
      }
    }
    if (recurrence != null) {
      try {
        _Rule.parse(recurrence);
      } on FormatException catch (error) {
        throw ScheduleValidationException(error.message, ['recurrence']);
      }
      if (dueDate == null && scheduledDate == null && startDate == null) {
        throw const ScheduleValidationException(
          'Choose a Start, Due or This occurrence date for Repeat.',
          ['recurrence', 'startDate', 'dueDate', 'scheduledDate'],
        );
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

  /// Compare persisted occurrence dates, independently of sort bounds or
  /// display precision. Clearing an occurrence override counts as a change.
  bool hasSameOccurrenceDates(TaskSchedule other) =>
      startDate == other.startDate &&
      scheduledDate == other.scheduledDate &&
      dueDate == other.dueDate;

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
  final List<int>? months;
  final int? monthDay, ordinal, weekday;
  final bool extended;
  const _Rule(
    this.unit,
    this.interval,
    this.whenDone, [
    this.weekdays,
    this.constraint,
    this.months,
    this.monthDay,
    this.ordinal,
    this.weekday,
    this.extended = false,
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
    final monthList = RegExp(
      r'^every (.+) on the (\d+(?:st|nd|rd|th))$',
    ).firstMatch(rule);
    if (monthList != null) {
      const names = [
        'january',
        'february',
        'march',
        'april',
        'may',
        'june',
        'july',
        'august',
        'september',
        'october',
        'november',
        'december',
      ];
      final tokens = monthList[1]!.split(RegExp(r', | and '));
      final day = parseOrdinal(monthList[2]!);
      if (tokens.isNotEmpty && tokens.every(names.contains) && day != null) {
        return _Rule(
          'months',
          1,
          done,
          null,
          null,
          tokens.map((name) => names.indexOf(name) + 1).toSet().toList(),
          day,
          null,
          null,
          rule != 'every january, april, july and october on the 1st',
        );
      }
    }
    if (rule == 'every weekday') {
      return _Rule('weekdays', 1, done, [1, 2, 3, 4, 5]);
    }
    final match = RegExp(
      r'^every (?:(\d+) )?(day|week|month|year)s?(?: on (.+))?$',
    ).firstMatch(rule);
    if (match == null) throw unsupported(text);
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
        throw unsupported(text);
      }
      return _Rule(
        unit,
        interval,
        done,
        names.map((name) => weekdayNames.indexOf(name) + 1).toSet().toList(),
      );
    }
    if (unit == 'month') {
      if (suffix == 'the last') {
        return _Rule(unit, interval, done, null, suffix);
      }
      final nth = RegExp(
        r'^the (1st|2nd|3rd|4th|last) (\w+)$',
      ).firstMatch(suffix);
      if (nth != null && weekdayNames.contains(nth[2])) {
        final ordinal = nth[1] == 'last' ? -1 : int.parse(nth[1]![0]);
        final weekday = weekdayNames.indexOf(nth[2]!) + 1;
        return _Rule(
          unit,
          interval,
          done,
          null,
          suffix,
          null,
          null,
          ordinal,
          weekday,
          ordinal != 1 || weekday != DateTime.friday,
        );
      }
      final day = suffix.startsWith('the ')
          ? parseOrdinal(suffix.substring(4))
          : null;
      if (day != null) {
        return _Rule(
          unit,
          interval,
          done,
          null,
          suffix,
          null,
          day,
          null,
          null,
          true,
        );
      }
    }
    throw unsupported(text);
  }

  static FormatException unsupported(String text) => FormatException(
    'Unsupported recurrence: $text. $supportedRecurrenceGrammar',
  );

  static int? parseOrdinal(String text) {
    final match = RegExp(r'^(\d{1,2})(st|nd|rd|th)$').firstMatch(text);
    if (match == null) return null;
    final day = int.parse(match[1]!);
    if (day < 1 || day > 31) return null;
    final suffix = day >= 11 && day <= 13
        ? 'th'
        : switch (day % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return match[2] == suffix ? day : null;
  }

  DateTime inMonth(DateTime month) {
    final last = DateTime.utc(month.year, month.month + 1, 0);
    if (monthDay != null) {
      return DateTime.utc(
        month.year,
        month.month,
        monthDay! > last.day ? last.day : monthDay!,
      );
    }
    if (constraint == 'the last') return last;
    if (ordinal == -1) {
      return last.subtract(Duration(days: (last.weekday - weekday! + 7) % 7));
    }
    return DateTime.utc(
      month.year,
      month.month,
      1 + (weekday! - month.weekday + 7) % 7 + (ordinal! - 1) * 7,
    );
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
        final candidate = inMonth(month);
        if (candidate.isAfter(anchor)) return candidate;
      }
    }
    if (unit == 'months') {
      for (var offset = 0; offset <= 12; offset++) {
        final month = DateTime.utc(anchor.year, anchor.month + offset, 1);
        if (!months!.contains(month.month)) continue;
        final day = inMonth(month);
        if (day.isAfter(anchor)) return day;
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

/// Additive examples, separate from the frozen observed37 parity inventory.
const recurrenceExamples = <String>[
  ...observedRecurrences,
  'every 2 months on the 2nd Tuesday',
  'every 3 months on the last Friday when done',
  'every month on the 15th',
  'every February, June and November on the 20th when done',
];
