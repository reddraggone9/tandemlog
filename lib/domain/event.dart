import 'dart:convert';

const protocolVersion = 1;
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
  final int sequence, clock;
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
    'clock': clock,
    'entity': entity,
    'type': type,
    'data': data,
  };
  String encode() => jsonEncode(toJson());
  factory LogEvent.decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
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
      for (final key in ['seq', 'clock']) {
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
        case 'user.created':
          text('name', 100);
        case 'task.created':
          text('title', 500);
          text('description', 10000, empty: true);
          if (d['assignee'] is! String || !idPattern.hasMatch(d['assignee'])) {
            throw FormatFailure('Invalid assignee.');
          }
        case 'task.edited':
          if (!d.containsKey('title') && !d.containsKey('description')) {
            throw FormatFailure('Empty edit.');
          }
          if (d.containsKey('title')) text('title', 500);
          if (d.containsKey('description')) {
            text('description', 10000, empty: true);
          }
        case 'task.completed':
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
      final allowed = switch (j['type']) {
        'user.created' => {'name'},
        'task.created' => {'title', 'description', 'assignee'},
        'task.edited' => {'title', 'description'},
        'task.completed' => <String>{},
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
        j['clock'],
        j['entity'],
        j['type'],
        d,
      );
    } on FormatFailure {
      rethrow;
    } catch (_) {
      throw FormatFailure('Malformed event. History was preserved.');
    }
  }
}

/// Replay is a pure function of an event set; never emits authoritative events.
Map<String, dynamic>? project(List<LogEvent> events) {
  events.sort((a, b) {
    final c = a.clock.compareTo(b.clock);
    return c != 0 ? c : a.writer.compareTo(b.writer);
  });
  Map<String, dynamic>? state;
  final completions = <String>{};
  final undone = <String>{};
  for (final e in events) {
    if (e.type == 'user.created' || e.type == 'task.created') {
      if (state != null) {
        throw FormatFailure('Duplicate entity creation: ${e.entity}');
      }
      state = {
        'id': e.entity,
        'kind': e.type == 'user.created' ? 'user' : 'task',
        ...e.data,
        'order': '${e.clock.toString().padLeft(16, '0')}:${e.writer}',
        'inbox': true,
      };
    }
  }
  if (state == null) return null; // dependencies may arrive later
  if (state['kind'] == 'user' &&
      events.any((e) => e.type.startsWith('task.'))) {
    throw FormatFailure('Task event references a user entity.');
  }
  for (final e in events) {
    if (e.type == 'task.edited') {
      state.addAll(e.data);
      state['inbox'] = false;
    }
    if (e.type == 'task.completed') completions.add(e.id);
    if (e.type == 'task.completionUndone') {
      undone.add(e.data['completion'] as String);
    }
  }
  state['completed'] = completions.difference(undone).isNotEmpty;
  return state;
}
