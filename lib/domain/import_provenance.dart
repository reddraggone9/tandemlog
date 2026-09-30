import 'schedule.dart';

/// Closed schema for the one-time Markdown source map. Literal spans represent
/// formatting/non-task lines, while semantic slots reference task fields.
void validateImportDocument(Map<String, dynamic> data) {
  const keys = {'documentId', 'formatVersion', 'encoding', 'bom', 'lines'};
  if (!_keys(data, keys) ||
      !_id(data['documentId']) ||
      data['formatVersion'] != 1 ||
      data['encoding'] != 'utf-8' ||
      data['bom'] is! bool ||
      data['lines'] is! List) {
    throw const FormatException('Invalid import document.');
  }
  final lines = data['lines'] as List;
  if (lines.length > 10000) {
    throw const FormatException('Too many source lines.');
  }
  final taskIds = <String>{};
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final item = lines[lineIndex];
    if (item is! Map<String, dynamic> ||
        !['', '\r', '\n', '\r\n'].contains(item['ending'])) {
      throw const FormatException('Invalid source line.');
    }
    if (item['ending'] == '' && lineIndex != lines.length - 1) {
      throw const FormatException(
        'Missing line ending before final source line.',
      );
    }
    if (item.containsKey('literal')) {
      if (!_keys(item, {'literal', 'ending'}) ||
          !_text(item['literal'], 10000) ||
          ((item['literal'] as String).contains(RegExp(r'[\r\n]')) ||
              RegExp(r'^\s*[-*+]\s*\[').hasMatch(item['literal'] as String))) {
        throw const FormatException('Invalid literal source line.');
      }
      continue;
    }
    if (!_keys(item, {'taskId', 'fields', 'parts', 'ending'}) ||
        !_id(item['taskId']) ||
        !taskIds.add(item['taskId'] as String) ||
        item['fields'] is! Map<String, dynamic> ||
        item['parts'] is! List) {
      throw const FormatException('Invalid task source line.');
    }
    final fields = item['fields'] as Map<String, dynamic>;
    const allowed = {
      'title',
      'titlePieces',
      'completed',
      'tags',
      'start',
      'scheduled',
      'due',
      'done',
      'startTime',
      'recurrence',
    };
    if (fields.keys.any((k) => !allowed.contains(k)) ||
        !_text(fields['title'], 500) ||
        (fields['title'] as String).trim().isEmpty ||
        fields['titlePieces'] is! List ||
        fields['completed'] is! bool ||
        fields['tags'] is! List) {
      throw const FormatException('Invalid source task fields.');
    }
    final pieces = fields['titlePieces'] as List;
    final tags = fields['tags'] as List;
    if (pieces.isEmpty ||
        pieces.length > 101 ||
        pieces.any((p) => !_text(p, 500)) ||
        pieces.join(' ') != fields['title'] ||
        tags.length > 100 ||
        tags.any(
          (t) => !_text(t, 201) || !RegExp(r'^#[^\s#]+$').hasMatch(t as String),
        )) {
      throw const FormatException('Invalid source title or tags.');
    }
    for (final name in ['start', 'scheduled', 'due', 'done']) {
      if (fields.containsKey(name)) {
        if (fields[name] is! String) {
          throw const FormatException('Invalid source date.');
        }
        parseCivilDate(fields[name] as String);
      }
    }
    if (fields.containsKey('done') && fields['completed'] != true) {
      throw const FormatException(
        'Completion date on an open source task is unsupported.',
      );
    }
    TaskSchedule(
      startDate: fields['start'] as String?,
      scheduledDate: fields['scheduled'] as String?,
      dueDate: fields['due'] as String?,
      startTime: fields['startTime'] as String?,
      recurrence: fields['recurrence'] as String?,
    );
    final timeTags = tags
        .cast<String>()
        .where((t) => t.startsWith('#start-time-'))
        .toList();
    if (fields.containsKey('startTime')) {
      if (timeTags.length != 1 ||
          timeTags.single !=
              '#start-time-${(fields['startTime'] as String).replaceAll(':', '')}') {
        throw const FormatException('Start time provenance mismatch.');
      }
    } else if (timeTags.isNotEmpty) {
      throw const FormatException('Missing start time semantic field.');
    }
    final parts = item['parts'] as List;
    if (parts.length > 1000) {
      throw const FormatException('Too many source slots.');
    }
    final seenPieces = <int>[];
    final seenTags = <String>[];
    final seenFields = <String>[];
    for (final part in parts) {
      if (part is! Map<String, dynamic>) {
        throw const FormatException('Invalid source slot.');
      }
      if (part.containsKey('literal')) {
        if (!_keys(part, {'literal'}) ||
            !_text(part['literal'], 10000) ||
            (part['literal'] as String).contains(RegExp(r'[\r\n]'))) {
          throw const FormatException('Invalid literal slot.');
        }
        continue;
      }
      switch (part['field']) {
        case 'title':
          if (!_keys(part, {'field', 'piece'}) ||
              part['piece'] is! int ||
              part['piece'] < 0 ||
              part['piece'] >= pieces.length) {
            throw const FormatException('Invalid title slot.');
          }
          seenPieces.add(part['piece'] as int);
        case 'tag':
          if (!_keys(part, {'field', 'value'}) || part['value'] is! String) {
            throw const FormatException('Invalid tag slot.');
          }
          seenTags.add(part['value'] as String);
        case 'completed':
          if (!_keys(part, {'field', 'checked'}) ||
              !['x', 'X'].contains(part['checked'])) {
            throw const FormatException('Invalid check slot.');
          }
          seenFields.add('completed');
        case 'start':
        case 'scheduled':
        case 'due':
        case 'done':
        case 'recurrence':
          if (!_keys(part, {'field'}) || !fields.containsKey(part['field'])) {
            throw const FormatException('Missing source field for slot.');
          }
          seenFields.add(part['field'] as String);
        default:
          throw const FormatException('Unknown source slot.');
      }
    }
    if (seenPieces.length != pieces.length ||
        seenPieces.asMap().entries.any((e) => e.key != e.value) ||
        seenTags.join('\u0000') != tags.join('\u0000') ||
        seenFields.where((f) => f == 'completed').length != 1) {
      throw const FormatException('Inconsistent source slots.');
    }
    for (final field in ['start', 'scheduled', 'due', 'done', 'recurrence']) {
      if (seenFields.where((f) => f == field).length !=
          (fields.containsKey(field) ? 1 : 0)) {
        throw const FormatException('Missing or duplicate semantic slot.');
      }
    }
  }
}

void validateTaskImport(Map<String, dynamic> data) {
  if (!_keys(data, {'documentId', 'line'}) ||
      !_id(data['documentId']) ||
      data['line'] is! int ||
      data['line'] < 1 ||
      data['line'] > 10000) {
    throw const FormatException('Invalid task import reference.');
  }
}

bool _id(dynamic value) =>
    value is String && RegExp(r'^[a-f0-9-]{36}$').hasMatch(value);
bool _text(dynamic value, int max) => value is String && value.length <= max;
bool _keys(Map<String, dynamic> data, Set<String> keys) =>
    data.length == keys.length && data.keys.every(keys.contains);
