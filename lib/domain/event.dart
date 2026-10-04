import 'dart:convert';
import 'event_chain.dart';
export 'event_chain.dart';
import 'event_clock.dart';
export 'event_clock.dart';
import 'package:uuid/uuid.dart';
import 'schedule.dart' hide validateSchedule;
import 'wall_time.dart';

const protocolVersion = 3;
final _idShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Same UUID namespace admission as the installed UUID implementation, with
/// canonical lowercase spelling so identities cannot alias by case.
bool isCanonicalId(Object? value) =>
    value is String &&
    _idShape.hasMatch(value) &&
    Uuid.isValidUUID(fromString: value);

bool _validReference(Object? value, {bool tag = false}) {
  if (value is! String) return false;
  final parts = value.split(':');
  return parts.length == (tag ? 3 : 2) &&
      isCanonicalId(parts[0]) &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(parts[1]) &&
      (!tag || RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(parts[2]));
}

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
  final EventClock clock;
  final Map<String, dynamic> data;
  final String? previousHash, hash;
  final String? canonicalRaw;
  LogEvent(
    this.space,
    this.writer,
    this.sequence,
    this.clock,
    this.entity,
    this.type,
    this.data, {
    this.previousHash,
    this.hash,
    this.canonicalRaw,
  });
  String get id => '$writer:$sequence';
  Map<String, dynamic> toJson({String? previousHash}) {
    final predecessor =
        previousHash ??
        this.previousHash ??
        (sequence == 1 ? eventGenesisHash(space, writer) : null);
    if (!isEventHash(predecessor)) {
      throw FormatFailure('A valid previous hash is required for this event.');
    }
    final record = <String, dynamic>{
      'v': protocolVersion,
      'space': space,
      'writer': writer,
      'seq': sequence,
      'clock': clock.toJson(),
      'entity': entity,
      'type': type,
      'data': data,
      'previousHash': predecessor,
    };
    try {
      record['hash'] = eventRecordHash(record);
      return record;
    } on FormatException catch (error) {
      throw FormatFailure(error.message);
    }
  }

  String encode({String? previousHash}) =>
      canonicalEventJson(toJson(previousHash: previousHash));
  factory LogEvent.decode(String raw) {
    try {
      if (raw.length > 1024 * 1024 || utf8.encode(raw).length > 1024 * 1024) {
        throw FormatFailure('Oversized event.');
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['v'] == 1 || j['v'] == 2) {
        throw FormatFailure(
          'This history uses an older prerelease format (v${j['v']}). Preserve it and choose a new data folder for this prerelease.',
        );
      }
      if (j['v'] != protocolVersion) {
        throw FormatFailure(
          'Unsupported event version ${j['v']}. Update the app; history was preserved.',
        );
      }
      for (final key in ['space', 'writer', 'entity']) {
        if (j[key] is! String || !isCanonicalId(j[key])) {
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
        case 'user.created':
          text('name', 100);
        case 'task.created':
        case 'task.createdWithText':
          text('title', 500);
          text('description', 10000, empty: true);
          if (d['assignee'] is! String || !isCanonicalId(d['assignee'])) {
            throw FormatFailure('Invalid assignee.');
          }
        case 'task.edited':
          if (!d.containsKey('title') &&
              !d.containsKey('description') &&
              !d.containsKey('schedule') &&
              !d.containsKey('tagChanges') &&
              !d.containsKey('assignee')) {
            throw FormatFailure('Empty edit.');
          }
          if (d.containsKey('assignee') && !isCanonicalId(d['assignee'])) {
            throw FormatFailure('Invalid assignee.');
          }
          if (d.containsKey('title')) text('title', 500);
          if (d.containsKey('description')) {
            text('description', 10000, empty: true);
          }
        case 'task.textEdited':
          validateTextChanges(d['changes']);
          if (d.containsKey('intent') && d['intent'] != 'undo') {
            throw FormatFailure('Unsupported native text intent.');
          }
          if (d.containsKey('assignee') && !isCanonicalId(d['assignee'])) {
            throw FormatFailure('Invalid assignee.');
          }
        case 'task.textEditUndone':
          if (!_validReference(d['operation'])) {
            throw FormatFailure('Invalid native text operation reference.');
          }
          validateTextChanges(d['changes'], empty: true);
        case 'text.baselineInitialized':
          if (j['entity'] != j['space']) {
            throw FormatFailure(
              'Text initialization must reference its workspace.',
            );
          }
          validateTextBaseline(d);
        case 'task.deleted':
          break;
        case 'task.moved':
          if (d['before'] != null &&
              (d['before'] is! String ||
                  !isCanonicalId(d['before']) ||
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
                !isCanonicalId(next['id'])) {
              throw FormatFailure('Invalid successor.');
            }
            validateTask(next, successor: true);
            if (next['id'] != const Uuid().v5(j['entity'], 'successor')) {
              throw FormatFailure('Invalid derived successor identity.');
            }
          }
          break;
        case 'task.completionUndone':
        case 'task.recurringCompletionUndone':
          text('completion', 80);
          if (!_validReference(d['completion'])) {
            throw FormatFailure('Invalid completion reference.');
          }
        case 'task.operationUndone':
          text('operation', 80);
          if (!_validReference(d['operation'])) {
            throw FormatFailure('Invalid operation reference.');
          }
        default:
          throw FormatFailure(
            'Unknown event ${j['type']}. Update the app; history was preserved.',
          );
      }
      if (j['type'] == 'task.created' || j['type'] == 'task.createdWithText') {
        validateTask(d);
      }
      if (j['type'] == 'task.createdWithText') {
        validateTextSeedDescriptor(d['text']);
      }
      if ((j['type'] == 'task.edited' || j['type'] == 'task.textEdited') &&
          d.containsKey('schedule')) {
        validateSchedule(d['schedule']);
      }
      if (d.containsKey('tagChanges')) validateTagChanges(d['tagChanges']);
      final allowed = switch (j['type']) {
        'user.created' => {'name'},
        'task.created' => {
          'title',
          'description',
          'assignee',
          'schedule',
          'tags',
        },
        'task.createdWithText' => {
          'title',
          'description',
          'assignee',
          'schedule',
          'tags',
          'text',
        },
        'task.edited' => {
          'title',
          'description',
          'schedule',
          'tagChanges',
          'assignee',
        },
        'task.textEdited' => {
          'changes',
          'intent',
          'schedule',
          'tagChanges',
          'assignee',
        },
        'task.textEditUndone' => {'operation', 'changes'},
        'text.baselineInitialized' => {
          'codec',
          'adapter',
          'frontiers',
          'seedDigest',
        },
        'task.deleted' => <String>{},
        'task.moved' => {'before'},
        'task.completed' => {'completedAt', 'successor'},
        'task.operationUndone' => {'operation'},
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
              'previousHash',
              'hash',
            }.contains(k),
          )) {
        throw FormatFailure('Unknown fields require a newer format version.');
      }
      if (!isEventHash(j['previousHash']) || !isEventHash(j['hash'])) {
        throw FormatFailure('Invalid event chain hash.');
      }
      if (canonicalEventJson(j) != raw) {
        throw FormatFailure('Noncanonical event JSON. History was preserved.');
      }
      if (eventRecordHash(j) != j['hash']) {
        throw FormatFailure('Event hash mismatch. History was preserved.');
      }
      return LogEvent(
        j['space'],
        j['writer'],
        j['seq'],
        EventClock.fromJson(j['clock']),
        j['entity'],
        j['type'],
        _freezeJson(d) as Map<String, dynamic>,
        previousHash: j['previousHash'],
        hash: j['hash'],
        canonicalRaw: raw,
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

int compareEvents(LogEvent a, LogEvent b) {
  final c = a.clock.compareTo(b.clock);
  return c != 0
      ? c
      : (a.writer != b.writer
            ? a.writer.compareTo(b.writer)
            : a.sequence.compareTo(b.sequence));
}

/// Replay is a pure function of an event set; never emits authoritative events.
Map<String, dynamic>? project(List<LogEvent> events) {
  events.sort(compareEvents);
  Map<String, dynamic>? state;
  final completions = <String>{};
  final undone = <String>{};
  final tagAdds = <String, String>{};
  final tagRemoves = <String>{};
  final retracted = retractedOperationIds(events);
  for (final e in events) {
    if (e.type == 'user.created' ||
        e.type == 'task.created' ||
        e.type == 'task.createdWithText') {
      if (state != null) {
        throw FormatFailure('Duplicate entity creation: ${e.entity}');
      }
      state = {
        'id': e.entity,
        'kind': e.type == 'user.created' ? 'user' : 'task',
        ...e.data,
        'order': '${e.clock.sortKey}:${e.writer}',
        // Raw captures need triage. Populated creations and derived recurring
        // occurrences have already been organized, even before their first edit.
        'inbox':
            (e.type == 'task.created' || e.type == 'task.createdWithText') &&
            e.data['tagOrigin'] == null &&
            (e.data['description'] as String? ?? '').trim().isEmpty &&
            (e.data['tags'] as List? ?? []).isEmpty &&
            (e.data['schedule'] as Map? ?? {}).values.every((v) => v == null),
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
    if (retracted.contains(e.id)) continue;
    if (e.type == 'task.edited' || e.type == 'task.textEdited') {
      state.addAll(
        Map<String, dynamic>.from(e.data)
          ..remove('tagChanges')
          ..remove('changes')
          ..remove('intent'),
      );
      state['inbox'] = false;
    }
    if (e.data.containsKey('tagChanges')) {
      state['inbox'] = false;
      final changes = e.data['tagChanges'] as Map;
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
  state['deleted'] = events.any(
    (e) => e.type == 'task.deleted' && !retracted.contains(e.id),
  );
  state.remove('tagOrigin');
  state.remove(
    'text',
  ); // Native initialization metadata belongs to canonical context.
  state['tagRefs'] = Map.fromEntries(
    tagAdds.entries.where((e) => !tagRemoves.contains(e.key)),
  );
  state['tags'] = (state['tagRefs'] as Map).values.toSet().toList()..sort();
  final active = completions.difference(undone);
  state['completed'] = active.isNotEmpty;
  final activeEvents = events.where(
    (event) => event.type == 'task.completed' && active.contains(event.id),
  );
  state['completedAt'] = activeEvents.isEmpty
      ? null
      : activeEvents.last.data['completedAt'];
  return state;
}

/// Retractions are idempotent, name earlier original operations, and are never
/// themselves Undo targets. Known reference validity is checked by ingestion.
Set<String> retractedOperationIds(Iterable<LogEvent> events) => events
    .where(
      (e) =>
          e.type == 'task.operationUndone' ||
          e.type == 'task.textEditUndone' ||
          e.type == 'task.recurringCompletionUndone',
    )
    .map(
      (e) =>
          (e.type == 'task.operationUndone' || e.type == 'task.textEditUndone'
                  ? e.data['operation']
                  : e.data['completion'])
              as String,
    )
    .toSet();

void validateTags(dynamic value) {
  if (value is! List ||
      value.length > 100 ||
      value.any((x) => x is! String || x.trim().isEmpty || x.length > 200)) {
    throw FormatFailure('Invalid tags.');
  }
  final reserved = RegExp(
    r'^#?(?:due-(?:min|max)-[0-9]+-days?|start-time-[0-9]{4})$',
  );
  if (value.any((tag) => reserved.hasMatch(tag as String))) {
    throw FormatFailure(
      'Reserved scheduling tag. Use task schedule fields; existing history was preserved and requires a compatible fresh import.',
    );
  }
}

/// Additive required creation meaning. Old task.created records remain unchanged.
/// Native seed/content agreement is checked by the text adapter before admission.
void validateTextSeedDescriptor(dynamic value) {
  if (value is! Map<String, dynamic> ||
      value.keys.toSet().difference({'codec', 'adapter', 'seeds'}).isNotEmpty ||
      value['codec'] != 'yrs-v1' ||
      value['adapter'] != 1 ||
      value['seeds'] is! Map<String, dynamic>) {
    throw FormatFailure('Unsupported native text seed descriptor.');
  }
  final seeds = value['seeds'] as Map<String, dynamic>;
  if (seeds.length != 2 ||
      !seeds.containsKey('title') ||
      !seeds.containsKey('description') ||
      seeds.values.any((seed) => !isEventHash(seed))) {
    throw FormatFailure('Invalid native text seed hashes.');
  }
}

/// Wire admission is separate from native codec and ownership validation.
/// Exact decoded bytes are retained; permissive base64 aliases are rejected.
void validateTextChanges(dynamic value, {bool empty = false}) {
  if (value is! Map<String, dynamic> ||
      (!empty && value.isEmpty) ||
      value.keys.any((key) => key != 'title' && key != 'description')) {
    throw FormatFailure('Invalid native text changes.');
  }
  for (final change in value.values) {
    if (change is! Map<String, dynamic> ||
        change.length != 4 ||
        !isEventHash(change['context']) ||
        !isCanonicalId(change['allocation']) ||
        change['actor'] is! int ||
        change['actor'] < 2 ||
        change['actor'] > 9007199254740991 ||
        change['update'] is! String) {
      throw FormatFailure('Invalid native text change descriptor.');
    }
    final encoded = change['update'] as String;
    // Limit before decoding, independently of the whole canonical event cap.
    if (encoded.isEmpty || encoded.length > 1398104) {
      throw FormatFailure('Oversized or empty native text update.');
    }
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty ||
          bytes.length > 1024 * 1024 ||
          base64Encode(bytes) != encoded) {
        throw FormatFailure('Noncanonical native text update.');
      }
    } on FormatException {
      throw FormatFailure('Malformed native text update.');
    }
  }
}

void validateTextBaseline(Map<String, dynamic> data) {
  if (data['codec'] != 'yrs-v1' ||
      data['adapter'] != 1 ||
      data['frontiers'] is! Map<String, dynamic> ||
      !isEventHash(data['seedDigest'])) {
    throw FormatFailure('Unsupported text initialization descriptor.');
  }
  for (final entry in (data['frontiers'] as Map<String, dynamic>).entries) {
    final head = entry.value;
    if (!isCanonicalId(entry.key) ||
        head is! Map<String, dynamic> ||
        head.length != 2 ||
        head['seq'] is! int ||
        head['seq'] < 0 ||
        head['seq'] > 9007199254740991 ||
        !isEventHash(head['hash'])) {
      throw FormatFailure('Invalid text initialization frontier.');
    }
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
      !isCanonicalId(d['assignee'])) {
    throw FormatFailure('Invalid task snapshot.');
  }
  if (d.containsKey('schedule')) validateSchedule(d['schedule']);
  if (d.containsKey('tags')) validateTags(d['tags']);
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
        (x) => x is! String || !_validReference(x, tag: true),
      )) {
    throw FormatFailure('Invalid tag removal references.');
  }
}

// Keep a decoded record's retained hash consistent with its admitted payload.
dynamic _freezeJson(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freezeJson(item))),
    );
  }
  if (value is List) return List<dynamic>.unmodifiable(value.map(_freezeJson));
  return value;
}
