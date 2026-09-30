import 'dart:convert';
import 'hlc.dart';
export 'hlc.dart';
import 'package:uuid/uuid.dart';
import 'schedule.dart' hide validateSchedule;
import 'wall_time.dart';
import 'import_provenance.dart';

const protocolVersion = 2;
final idPattern = RegExp(r'^[a-f0-9-]{36}$');

class FormatFailure implements Exception {
  final String message;
  FormatFailure(this.message);
  @override
  String toString() => message;
}

/// Wire validation is deliberately independent of Flutter and persistence.
class LogEvent {
  final String space, writer, entity, type;
  final int sequence;
  final HlcClock clock;
  final Map<String, dynamic> data;
  LogEvent(
    this.space,
    this.writer,
    this.sequence,
    this.clock,
    this.entity,
    this.type,
    this.data,
  );
  String get id => '$writer:$sequence';
  Map<String, dynamic> toJson() => {
    'v': protocolVersion,
    'space': space,
    'writer': writer,
    'seq': sequence,
    'clock': clock.toJson(),
    'entity': entity,
    'type': type,
    'data': data,
  };
  String encode() => jsonEncode(toJson());
  factory LogEvent.decode(String raw) {
    try {
      if (raw.length > 1024 * 1024) throw FormatFailure('Oversized event.');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['v'] == 1) {
        throw FormatFailure(
          'This history uses an older prerelease format (v1). Preserve it and choose a new data folder for this prerelease.',
        );
      }
      if (j['v'] != protocolVersion) {
        throw FormatFailure(
          'Unsupported event version ${j['v']}. Update the app; history was preserved.',
        );
      }
      for (final key in ['space', 'writer', 'entity']) {
        if (j[key] is! String || !idPattern.hasMatch(j[key])) {
          throw FormatFailure('Invalid $key identifier.');
        }
      }
      for (final key in ['seq']) {
        if (j[key] is! int || j[key] < 1 || j[key] > 9007199254740991) {
          throw FormatFailure('Invalid $key counter.');
        }
      }
      final d = j['data'] as Map<String, dynamic>;
      void text(String key, int max, {bool empty = false}) {
        if (d[key] is! String ||
            (d[key] as String).length > max ||
            (!empty && (d[key] as String).trim().isEmpty)) {
          throw FormatFailure('Invalid $key.');
        }
      }

      switch (j['type']) {
        case 'import.document':
          validateImportDocument(d);
          if (d['documentId'] != j['entity']) {
            throw FormatFailure('Import document identity mismatch.');
          }
        case 'user.created':
          text('name', 100);
        case 'task.created':
          text('title', 500);
          text('description', 10000, empty: true);
          if (d['assignee'] is! String || !idPattern.hasMatch(d['assignee'])) {
            throw FormatFailure('Invalid assignee.');
          }
        case 'task.edited':
          if (!d.containsKey('title') &&
              !d.containsKey('description') &&
              !d.containsKey('schedule') &&
              !d.containsKey('tagChanges')) {
            throw FormatFailure('Empty edit.');
          }
          if (d.containsKey('title')) text('title', 500);
          if (d.containsKey('description')) {
            text('description', 10000, empty: true);
          }
        case 'task.tagsChanged':
          validateTagChanges(d);
        case 'task.moved':
          if (d['before'] != null &&
              (d['before'] is! String ||
                  !idPattern.hasMatch(d['before']) ||
                  d['before'] == j['entity'])) {
            throw FormatFailure('Invalid order anchor.');
          }
          if (!d.containsKey('before')) {
            throw FormatFailure('Missing order anchor.');
          }
        case 'task.completed':
          if (d.containsKey('completedAt')) {
            if (d['completedAt'] is! String ||
                DateTime.tryParse(d['completedAt']) == null) {
              throw FormatFailure('Invalid completion date.');
            }
          }
          if (d.containsKey('completedAt')) {
            parseCivilDate((d['completedAt'] as String).substring(0, 10));
          }
          if (d.containsKey('successor')) {
            final next = d['successor'];
            if (next is! Map<String, dynamic> ||
                next['id'] is! String ||
                !idPattern.hasMatch(next['id'])) {
              throw FormatFailure('Invalid successor.');
            }
            validateTask(next, successor: true);
            if (next['id'] != const Uuid().v5(j['entity'], 'successor')) {
              throw FormatFailure('Invalid derived successor identity.');
            }
          }
          break;
        case 'task.completionUndone':
          text('completion', 80);
          if (!RegExp(
            r'^[a-f0-9-]{36}:[1-9][0-9]*$',
          ).hasMatch(d['completion'])) {
            throw FormatFailure('Invalid completion reference.');
          }
        default:
          throw FormatFailure(
            'Unknown event ${j['type']}. Update the app; history was preserved.',
          );
      }
      if (j['type'] == 'task.created') validateTask(d);
      if (j['type'] == 'task.edited' && d.containsKey('schedule')) {
        validateSchedule(d['schedule']);
      }
      if (d.containsKey('tagChanges')) validateTagChanges(d['tagChanges']);
      final allowed = switch (j['type']) {
        'import.document' => {
          'documentId',
          'formatVersion',
          'encoding',
          'bom',
          'lines',
        },
        'user.created' => {'name'},
        'task.created' => {
          'title',
          'description',
          'assignee',
          'schedule',
          'tags',
          'import',
        },
        'task.edited' => {'title', 'description', 'schedule', 'tagChanges'},
        'task.tagsChanged' => {'add', 'remove'},
        'task.moved' => {'before'},
        'task.completed' => {'completedAt', 'successor'},
        _ => {'completion'},
      };
      if (d.keys.any((k) => !allowed.contains(k)) ||
          j.keys.any(
            (k) => !{
              'v',
              'space',
              'writer',
              'seq',
              'clock',
              'entity',
              'type',
              'data',
            }.contains(k),
          )) {
        throw FormatFailure('Unknown fields require a newer format version.');
      }
      return LogEvent(
        j['space'],
        j['writer'],
        j['seq'],
        HlcClock.fromJson(j['clock']),
        j['entity'],
        j['type'],
        d,
      );
    } on FormatFailure {
      rethrow;
    } on FormatException catch (error) {
      throw FormatFailure(error.message);
    } catch (_) {
      throw FormatFailure('Malformed event. History was preserved.');
    }
  }
}

/// Replay is a pure function of an event set; never emits authoritative events.
Map<String, dynamic>? project(List<LogEvent> events) {
  events.sort((a, b) {
    final c = a.clock.compareTo(b.clock);
    return c != 0
        ? c
        : (a.writer != b.writer
              ? a.writer.compareTo(b.writer)
              : a.sequence.compareTo(b.sequence));
  });
  Map<String, dynamic>? state;
  final completions = <String>{};
  final undone = <String>{};
  final tagAdds = <String, String>{};
  final tagRemoves = <String>{};
  for (final e in events) {
    if (e.type == 'user.created' ||
        e.type == 'task.created' ||
        e.type == 'import.document') {
      if (state != null) {
        throw FormatFailure('Duplicate entity creation: ${e.entity}');
      }
      state = {
        'id': e.entity,
        'kind': e.type == 'user.created'
            ? 'user'
            : e.type == 'import.document'
            ? 'document'
            : 'task',
        ...e.data,
        'order': '${e.clock.sortKey}:${e.writer}',
        'inbox': true,
        'schedule': TaskSchedule().toJson(),
        'tags': <String>[],
        ...e.data,
      };
      final initialTags = e.data['tags'] as List? ?? [];
      for (var i = 0; i < initialTags.length; i++) {
        final tag = initialTags[i] as String;
        final token = e.data['tagOrigin'] is String
            ? '${const Uuid().v5(e.data['tagOrigin'] as String, 'tag:$tag')}:1:0'
            : '${e.id}:$i';
        tagAdds[token] = tag;
      }
    }
  }
  if (state == null) return null; // dependencies may arrive later
  if (state['kind'] != 'task' &&
      events.any((e) => e.type.startsWith('task.'))) {
    throw FormatFailure('Task event references a user entity.');
  }
  for (final e in events) {
    if (e.type == 'task.edited') {
      state.addAll(Map<String, dynamic>.from(e.data)..remove('tagChanges'));
      state['inbox'] = false;
    }
    if (e.type == 'task.tagsChanged' || e.data.containsKey('tagChanges')) {
      final changes = e.type == 'task.tagsChanged'
          ? e.data
          : e.data['tagChanges'] as Map;
      final added = changes['add'] as List;
      for (var i = 0; i < added.length; i++) {
        tagAdds['${e.id}:$i'] = added[i] as String;
      }
      tagRemoves.addAll((changes['remove'] as List).cast<String>());
    }
    if (e.type == 'task.completed') completions.add(e.id);
    if (e.type == 'task.completionUndone') {
      undone.add(e.data['completion'] as String);
    }
  }
  state.remove('tagOrigin');
  state['tagRefs'] = Map.fromEntries(
    tagAdds.entries.where((e) => !tagRemoves.contains(e.key)),
  );
  state['tags'] = (state['tagRefs'] as Map).values.toSet().toList()..sort();
  state['completed'] = completions.difference(undone).isNotEmpty;
  return state;
}

void validateTags(dynamic value) {
  if (value is! List ||
      value.length > 100 ||
      value.any((x) => x is! String || x.trim().isEmpty || x.length > 200)) {
    throw FormatFailure('Invalid tags.');
  }
}

void validateSchedule(dynamic value) {
  try {
    final schedule = TaskSchedule.fromJson(value as Map<String, dynamic>);
    if (schedule.timeZone != null) timeZoneLocation(schedule.timeZone!);
  } catch (_) {
    throw FormatFailure('Invalid task schedule.');
  }
}

void validateTask(Map<String, dynamic> d, {bool successor = false}) {
  if (d['title'] is! String ||
      (d['title'] as String).trim().isEmpty ||
      (d['title'] as String).length > 500 ||
      d['description'] is! String ||
      (d['description'] as String).length > 10000 ||
      d['assignee'] is! String ||
      !idPattern.hasMatch(d['assignee'])) {
    throw FormatFailure('Invalid task snapshot.');
  }
  if (d.containsKey('schedule')) validateSchedule(d['schedule']);
  if (d.containsKey('tags')) validateTags(d['tags']);
  if (d.containsKey('import')) {
    if (d['import'] is! Map<String, dynamic>) {
      throw FormatFailure('Invalid import provenance.');
    }
    validateTaskImport(d['import'] as Map<String, dynamic>);
  }
  if (successor &&
      d.keys.any(
        (k) => !{
          'id',
          'title',
          'description',
          'assignee',
          'schedule',
          'tags',
        }.contains(k),
      )) {
    throw FormatFailure('Unknown successor field.');
  }
}

void validateTagChanges(dynamic changes) {
  if (changes is! Map<String, dynamic> ||
      changes.keys.toSet().difference({'add', 'remove'}).isNotEmpty) {
    throw FormatFailure('Invalid tag changes.');
  }
  validateTags(changes['add']);
  if (changes['remove'] is! List ||
      (changes['remove'] as List).any(
        (x) =>
            x is! String ||
            !RegExp(r'^[a-f0-9-]{36}:[1-9][0-9]*:[0-9]+$').hasMatch(x),
      )) {
    throw FormatFailure('Invalid tag removal references.');
  }
}
