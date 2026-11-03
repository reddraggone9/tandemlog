import '../agent/render.dart' show taskScheduleText;
import '../domain/event.dart';
import '../food/inventory.dart';
import '../storage/unified_history.dart';
import '../storage/unified_record.dart';
import 'activity_log.dart';

/// Text fields of [entity] after exactly [history], a causal prefix of admitted
/// task events. Null when unavailable; never a guess.
typedef ActivityTextAt =
    Map<String, String>? Function(String entity, List<LogEvent> history);

/// One changed field. [before] is null when no single prior value is known.
class ActivityChange {
  const ActivityChange(this.label, this.after, [this.before]);
  final String label, after;
  final String? before;
  String get line =>
      before == null ? '$label: $after' : '$label: $before → $after';
}

class ActivityDescription {
  const ActivityDescription(
    this.subject,
    this.changes, {
    this.needsText = false,
  });

  /// Title or notes values are shown only after a shared-text replay.
  final bool needsText;

  /// The changed item as recorded by this action, for example `Milk (Kroger)`.
  final String? subject;
  final List<ActivityChange> changes;
}

const _unknown = Object();

class _Write {
  const _Write(this.record, this.position, this.value);
  final UnifiedRecord record;
  final int position;

  /// A String, or [_unknown] when the action changed the field without a
  /// readable value (Undo, text update, recurring completion).
  final Object value;
}

const _taskLabels = {
  'title': 'Title',
  'description': 'Notes',
  'assignee': 'Assignee',
  'schedule': 'Schedule',
};
const _foodLabels = {
  'name': 'Name',
  'brand': 'Brand',
  'size': 'Container size',
  'location': 'Location',
  'expiry': 'Expiration',
  'retention': 'Retention reason',
  'contents': 'Amount',
};
const _productLabels = {
  'name': 'Product name',
  'brand': 'Brand',
  'size': 'Size',
  'links': 'Store links',
  'minimum': 'Keep at least',
};
const _undoTypes = {
  'task.undo',
  'task.operationUndone',
  'task.textEditUndone',
  'task.completionUndone',
  'task.recurringCompletionUndone',
  'task.deletionUndone',
  'text.compensate',
};

/// Plain values for Activity rows, derived on demand from one admitted
/// snapshot. Old values come from the causal past of the action: the writes
/// it observed. If those disagree, an unreadable change intervened, or another
/// device wrote the same field concurrently, only the new value is shown.
class ActivityValues {
  ActivityValues(this.snapshot, {this.textAt});
  final UnifiedSnapshot snapshot;
  final ActivityTextAt? textAt;

  late final Map<String, UnifiedRecord> _records = {
    for (final r in snapshot.records)
      if (r.sequence <= (snapshot.published[r.writer] ?? 0)) r.recordId: r,
  };
  final _writes = <String, List<_Write>>{};
  final _people = <String, String>{};
  final _tags = <String, String>{};
  final _described = <String, ActivityDescription>{};
  bool _indexed = false;

  /// Imported historical records carry no observed frontier; the app that
  /// wrote them replayed in clock order, so that order is their history.
  static bool _before(UnifiedRecord a, UnifiedRecord b) {
    if (a.writer == b.writer) return a.sequence < b.sequence;
    if (b.historical) {
      return a.historical && a.effect.clock.compareTo(b.effect.clock) < 0;
    }
    return (b.observed[a.writer]?.sequence ?? 0) >= a.sequence;
  }

  bool _precedes(_Write a, _Write b) => identical(a.record, b.record)
      ? a.position < b.position
      : _before(a.record, b.record);

  void _index() {
    if (_indexed) return;
    _indexed = true;
    for (final r in _records.values) {
      for (final e in r.effects) {
        final task = e.task;
        if (task?.type == 'user.created' && task!.data['name'] is String) {
          _people[task.entity] = task.data['name'] as String;
        }
      }
    }
    for (final r in _records.values) {
      var position = 0;
      for (final e in r.effects) {
        position++;
        void put(String key, Object value) =>
            (_writes[key] ??= []).add(_Write(r, position, value));
        final task = e.task;
        if (task != null) {
          final d = task.data;
          final added = d['tags'] ?? (d['tagChanges'] as Map?)?['add'];
          if (added is List) {
            for (var i = 0; i < added.length; i++) {
              _tags['${task.id}:$i'] = '${added[i]}';
            }
          }
          for (final (field, value) in _taskWrites(task)) {
            put('${task.entity}|$field', value);
          }
          continue;
        }
        final food = e.food;
        if (food == null) continue;
        for (final (target, field, value) in _foodWrites(food.operation)) {
          put('$target|$field', value);
        }
      }
    }
  }

  List<(String, Object)> _taskWrites(LogEvent e) {
    final d = e.data;
    if (_undoTypes.contains(e.type)) {
      return [for (final field in _taskLabels.keys) (field, _unknown)];
    }
    if (isTaskCompletion(e.type)) return [('schedule', _unknown)];
    final text = d['changes'] is Map ? (d['changes'] as Map).keys : const [];
    return [
      for (final field in _taskLabels.keys)
        if (text.contains(field))
          (field, _unknown)
        else if (d.containsKey(field) &&
            (e.type.startsWith('task.created') ||
                e.type == 'task.edited' ||
                e.type == 'task.textEdited'))
          (field, _taskValue(field, d[field])),
    ];
  }

  String _taskValue(String field, Object? value) => switch (field) {
    'assignee' => _people[value] ?? 'Unknown person',
    'schedule' when value is Map<String, dynamic> => _schedule(value),
    _ => _text(value),
  };

  static String _schedule(Map<String, dynamic> schedule) {
    final text = taskScheduleText(schedule, DateTime.now().year);
    return text.isEmpty ? 'none' : text;
  }

  static String _text(Object? value) {
    final text = value is String ? value.trim() : '${value ?? ''}';
    if (text.isEmpty) return 'none';
    final line = text.split('\n').first;
    return line.length > 80 || line != text
        ? '${line.substring(0, line.length.clamp(0, 80))}…'
        : line;
  }

  List<(String, String, Object)> _foodWrites(FoodOperation op) {
    final details = op.details?.toJson();
    switch (op.action) {
      case FoodAction.add:
      case FoodAction.edit:
        final fields = op.action == FoodAction.add
            ? [
                if (details != null) ...details.keys,
                if (op.contents != null) 'contents',
              ]
            : [...op.fields, if (op.contents != null) 'contents'];
        return [
          for (final target in op.targets)
            for (final field in fields)
              if (_foodLabels.containsKey(field))
                (
                  target,
                  field,
                  field == 'contents'
                      ? op.contents!.label
                      : _foodValue(field, details?[field]),
                ),
        ];
      case FoodAction.undo:
        return [
          for (final target in op.targets)
            for (final field in _foodLabels.keys) (target, field, _unknown),
        ];
      case FoodAction.product:
        return [
          for (final target in op.targets)
            for (final entry in (op.product ?? const {}).entries)
              if (_productLabels.containsKey(entry.key))
                (target, 'product.${entry.key}', _productValue(entry.value)),
        ];
      default:
        return const [];
    }
  }

  static String _foodValue(String field, Object? value) {
    if (field == 'expiry' && value == null) return 'none';
    return _text(value);
  }

  static String _productValue(Object? value) => value is List
      ? (value.isEmpty ? 'none' : value.map(_text).join(', '))
      : _text(value);

  /// Resolves one field write of [record]: old value only when certain.
  /// Null [change] is a change without a readable value; [same] means the
  /// write kept the value the action observed, which is not shown.
  ({bool same, ActivityChange? change}) _change(
    String key,
    String label,
    UnifiedRecord record,
    _Write own,
  ) {
    final writes = _writes[key] ?? const <_Write>[];
    final past = <_Write>[];
    for (final w in writes) {
      if (identical(w, own)) continue;
      if (_precedes(w, own)) {
        past.add(w);
      } else if (!_precedes(own, w)) {
        // A concurrent write to the same field: the prior value is a guess.
        return (
          same: false,
          change: own.value is String
              ? ActivityChange(label, own.value as String)
              : null,
        );
      }
    }
    if (own.value is! String) return (same: false, change: null);
    final latest = past
        .where((w) => !past.any((o) => !identical(o, w) && _precedes(w, o)))
        .map((w) => w.value)
        .toSet();
    final before = latest.length == 1 && latest.single is String
        ? latest.single as String
        : null;
    if (before == own.value) return (same: true, change: null);
    return (
      same: false,
      change: ActivityChange(label, own.value as String, before),
    );
  }

  /// The text-resolved description, if already computed.
  ActivityDescription? withText(ActivityEntry entry) =>
      _described['${entry.id}|true'];

  /// [text] resolves native title/notes edits, which replays shared text and
  /// is meant for the details view, not for every visible row.
  ActivityDescription describe(ActivityEntry entry, {bool text = false}) {
    final cacheKey = '${entry.id}|$text';
    final cached = _described[cacheKey];
    if (cached != null) return cached;
    var needsText = false;
    _index();
    final record = _records[entry.id];
    if (record == null) return const ActivityDescription(null, []);
    final changes = <String, List<ActivityChange?>>{};
    final subjects = <String>[];
    var position = 0;
    for (final e in record.effects) {
      position++;
      final task = e.task;
      if (task != null) {
        if (task.type.startsWith('task.created') &&
            task.data['title'] is String) {
          subjects.add(_text(task.data['title']));
        }
        if (task.type == 'user.created' && task.data['name'] is String) {
          subjects.add(_text(task.data['name']));
        }
        final creating = task.type.startsWith('task.created');
        for (final (field, value) in _taskWrites(task)) {
          if (creating && field != 'assignee' && field != 'schedule') continue;
          if (creating && field == 'schedule' && value == 'none') continue;
          final label = _taskLabels[field]!;
          final key = '${task.entity}|$field';
          final own = _writes[key]!.firstWhere(
            (w) => identical(w.record, record) && w.position == position,
          );
          if (value == _unknown &&
              (task.data['changes'] as Map?)?.containsKey(field) == true) {
            if (!text) {
              needsText = textAt != null;
              (changes[label] ??= []).add(null);
            } else if (_textChange(task, field, label, record)
                case final change) {
              if (!change.same) (changes[label] ??= []).add(change.change);
            }
            continue;
          }
          // Undo and completion effects only make later old values unknown.
          if (value == _unknown) continue;
          final change = _change(key, label, record, own);
          if (!change.same) (changes[label] ??= []).add(change.change);
        }
        final tags = task.data['tagChanges'];
        if (tags is Map) {
          final added = (tags['add'] as List? ?? const []).map((t) => '$t');
          final removed = (tags['remove'] as List? ?? const []).map(
            (ref) => _tags[ref] ?? 'a tag',
          );
          final parts = [
            if (added.isNotEmpty) 'added ${added.join(', ')}',
            if (removed.isNotEmpty) 'removed ${removed.toSet().join(', ')}',
          ];
          if (parts.isNotEmpty) {
            (changes['Tags'] ??= []).add(
              ActivityChange('Tags', parts.join('; ')),
            );
          }
        }
        continue;
      }
      final food = e.food;
      if (food == null) continue;
      final op = food.operation;
      final details = op.details;
      if (op.action == FoodAction.add && details != null) {
        subjects.add(_foodName(details.name, details.brand));
        continue;
      }
      if (!op.action.productLevel) {
        for (final target in op.targets) {
          final name = _valueAt(record, position, '$target|name');
          if (name != null) {
            subjects.add(
              _foodName(name, _valueAt(record, position, '$target|brand')),
            );
          }
        }
      }
      if (op.action == FoodAction.undo) continue;
      for (final (target, field, _) in _foodWrites(op)) {
        final key = '$target|$field';
        final own = _writes[key]!.firstWhere(
          (w) => identical(w.record, record) && w.position == position,
        );
        final label = field.startsWith('product.')
            ? _productLabels[field.substring(8)]!
            : _foodLabels[field]!;
        final change = _change(key, label, record, own);
        // A new product's empty fields are not changes worth a line.
        if (field.startsWith('product.') &&
            change.change?.before == null &&
            change.change?.after == 'none') {
          continue;
        }
        if (!change.same) (changes[label] ??= []).add(change.change);
      }
    }
    final result = ActivityDescription(_summarize(subjects), [
      for (final entry in changes.entries) ?_merge(entry.key, entry.value),
    ], needsText: needsText);
    _described[cacheKey] = result;
    return result;
  }

  /// One line per field label across a bulk action's targets.
  static ActivityChange? _merge(String label, List<ActivityChange?> changes) {
    final known = changes.whereType<ActivityChange>().toList();
    if (known.isEmpty) {
      return changes.isEmpty ? null : ActivityChange(label, 'changed');
    }
    final after = known.map((c) => c.after).toSet();
    if (after.length != 1) return ActivityChange(label, 'changed');
    final before = known.map((c) => c.before).toSet();
    return ActivityChange(
      label,
      after.single,
      before.length == 1 && known.length == changes.length
          ? before.single
          : null,
    );
  }

  static String? _summarize(List<String> subjects) {
    if (subjects.isEmpty) return null;
    final distinct = subjects.toSet();
    if (distinct.length == 1) {
      return subjects.length == 1
          ? subjects.single
          : '${subjects.first} ×${subjects.length}';
    }
    return '${distinct.take(2).join(', ')}'
        '${distinct.length > 2 ? ' and ${distinct.length - 2} more' : ''}';
  }

  static String _foodName(String name, String? brand) {
    final n = _text(name);
    return brand == null || brand.trim().isEmpty || brand == 'none'
        ? n
        : '$n (${_text(brand)})';
  }

  /// The field's value right after this action, as its device saw it.
  /// Concurrent writes elsewhere do not change what the action observed.
  String? _valueAt(UnifiedRecord record, int position, String key) {
    final writes = _writes[key] ?? const <_Write>[];
    final at = _Write(record, position, '');
    final past = writes
        .where(
          (w) =>
              identical(w.record, record) && w.position == position ||
              _precedes(w, at),
        )
        .toList();
    final latest = past
        .where((w) => !past.any((o) => !identical(o, w) && _precedes(w, o)))
        .map((w) => w.value)
        .toSet();
    return latest.length == 1 && latest.single is String
        ? latest.single as String
        : null;
  }

  /// Long or multi-line text shows the part that changed, with context.
  static ActivityChange _textDifference(
    String label,
    String before,
    String after,
  ) {
    if (before.length <= 80 &&
        after.length <= 80 &&
        !before.contains('\n') &&
        !after.contains('\n')) {
      return ActivityChange(label, _text(after), _text(before));
    }
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }
    final start = (prefix - 20).clamp(0, prefix);
    String excerpt(String value) {
      var end = value.length - suffix;
      end = (end + 10).clamp(end, value.length);
      final more = end - start > 60;
      final body = value
          .substring(start, more ? start + 60 : end)
          .replaceAll('\n', ' ↵ ');
      if (body.trim().isEmpty) return 'none';
      return '${start > 0 ? '…' : ''}$body'
          '${more || end < value.length ? '…' : ''}';
    }

    return ActivityChange(label, excerpt(after), excerpt(before));
  }

  ({bool same, ActivityChange? change}) _textChange(
    LogEvent event,
    String field,
    String label,
    UnifiedRecord record,
  ) {
    const unknown = (same: false, change: null);
    final read = textAt;
    if (read == null) return unknown;
    final past = <LogEvent>[], through = <LogEvent>[];
    for (final r in _records.values) {
      final prior = _before(r, record);
      if (!prior && !identical(r, record)) continue;
      for (final e in r.effects) {
        final task = e.task;
        if (task == null) continue;
        through.add(task);
        if (prior) past.add(task);
      }
    }
    try {
      final after = read(event.entity, through)?[field];
      if (after == null) return unknown;
      final before = read(event.entity, past)?[field];
      if (before == after) return (same: true, change: null);
      return (
        same: false,
        change: before == null
            ? ActivityChange(label, _text(after))
            : _textDifference(label, before, after),
      );
    } catch (_) {
      // Unreadable text history shows the field as changed, without values.
      return unknown;
    }
  }
}
