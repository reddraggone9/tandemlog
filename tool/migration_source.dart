import 'dart:convert';

/// Lossless source map. Literals hold formatting/non-task text; semantic slots
/// are regenerated from parsed fields, rather than returning an archived file.
class MarkdownSource {
  final bool bom;
  final List<Map<String, dynamic>> lines;
  MarkdownSource(this.bom, this.lines);

  static final date = RegExp(r'^(\d{4}-\d{2}-\d{2})(?=\s|$)');
  static final tag = RegExp(r'^#[^\s#]+');
  static final markerFields = {
    '🛫': 'start',
    '⏳': 'scheduled',
    '📅': 'due',
    '✅': 'done',
  };
  static final rules = <String>{
    for (final unit in ['day', 'week', 'month', 'year']) 'every $unit',
    for (final n in [2, 5, 9, 20, 25, 36]) 'every $n days',
    for (final n in [2, 3, 4, 6, 7, 8, 13, 26]) 'every $n weeks',
    for (final n in [3, 4, 6]) 'every $n months',
    'every 5 years',
    'every weekday',
    for (final days in [
      'Monday',
      'Friday',
      'Saturday',
      'Wednesday, Sunday',
      'Monday, Tuesday, Wednesday, Thursday, Friday, Saturday',
    ])
      'every week on $days',
    'every month on the last',
    'every 3 months on the 1st Friday',
    'every 3 months on the last',
    'every January, April, July and October on the 1st',
  };

  factory MarkdownSource.parse(List<int> bytes) {
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 239 &&
        bytes[1] == 187 &&
        bytes[2] == 191;
    final text = utf8.decode(
      bom ? bytes.sublist(3) : bytes,
      allowMalformed: false,
    );
    final lines = <Map<String, dynamic>>[];
    for (final match in RegExp(r'([^\r\n]*)(\r\n|\n|\r|$)').allMatches(text)) {
      if (match.start == text.length) break;
      final content = match[1]!;
      final ending = match[2]!;
      final task = RegExp(
        r'^(\s*[-*+] \[)([^\]])(\]\s+)(.*)$',
      ).firstMatch(content);
      if (task == null) {
        if (RegExp(r'^\s*[-*+]\s*\[').hasMatch(content)) {
          throw FormatException(
            'Unsupported task syntax on line ${lines.length + 1}.',
          );
        }
        lines.add({'literal': content, 'ending': ending});
        continue;
      }
      if (RegExp(r'^\s').hasMatch(task[1]!)) {
        throw FormatException(
          'Nested/indented task syntax on line ${lines.length + 1} is unsupported.',
        );
      }
      if (![' ', 'x', 'X'].contains(task[2])) {
        throw FormatException(
          'Unsupported task status on line ${lines.length + 1}.',
        );
      }
      final fields = <String, dynamic>{
        'completed': task[2] != ' ',
        'tags': <String>[],
      };
      final parts = <Map<String, dynamic>>[
        {'literal': task[1]},
        {'field': 'completed', 'checked': task[2] == 'X' ? 'X' : 'x'},
        {'literal': task[3]},
      ];
      final body = task[4]!;
      var i = 0;
      var literal = '';
      final titlePieces = <String>[];
      void flush() {
        if (literal.isEmpty) return;
        // Whitespace belongs to formatting; title text belongs to semantics.
        final m = RegExp(
          r'^(\s*)(.*?)(\s*)$',
          dotAll: true,
        ).firstMatch(literal)!;
        if (m[1]!.isNotEmpty) parts.add({'literal': m[1]});
        if (m[2]!.isNotEmpty) {
          parts.add({'field': 'title', 'piece': titlePieces.length});
          titlePieces.add(m[2]!);
        }
        if (m[3]!.isNotEmpty) parts.add({'literal': m[3]});
        literal = '';
      }

      while (i < body.length) {
        // Links are opaque title content, including embedded hashes/markers.
        if (body.startsWith('[[', i)) {
          final end = body.indexOf(']]', i + 2);
          if (end < 0) {
            throw FormatException(
              'Unclosed wikilink on line ${lines.length + 1}.',
            );
          }
          literal += body.substring(i, end + 2);
          i = end + 2;
          continue;
        }
        final markdownLink = RegExp(
          r'^\[[^\]]*\]\([^\r\n]*?\)',
        ).firstMatch(body.substring(i));
        if (markdownLink != null) {
          literal += markdownLink[0]!;
          i += markdownLink[0]!.length;
          continue;
        }
        final boundary = i == 0 || RegExp(r'\s').hasMatch(body[i - 1]);
        if (boundary && body.startsWith('#', i)) {
          final m = tag.firstMatch(body.substring(i));
          if (m != null) {
            flush();
            final value = m[0]!;
            (fields['tags'] as List<String>).add(value);
            parts.add({'field': 'tag', 'value': value});
            if (value.startsWith('#start-time-')) {
              if (!RegExp(
                r'^#start-time-(?:[01]\d|2[0-3])[0-5]\d$',
              ).hasMatch(value)) {
                throw FormatException(
                  'Invalid reserved time tag on line ${lines.length + 1}.',
                );
              }
              if (fields.containsKey('startTime')) {
                throw FormatException('Multiple start times.');
              }
              final digits = value.substring(12);
              fields['startTime'] =
                  '${digits.substring(0, 2)}:${digits.substring(2)}';
            }
            i += value.length;
            continue;
          }
        }
        String? matchedMarker;
        for (final marker in [...markerFields.keys, '🔁', '🏁']) {
          if (boundary && body.startsWith(marker, i)) {
            matchedMarker = marker;
            break;
          }
        }
        if (matchedMarker != null) {
          flush();
          final field = matchedMarker == '🔁'
              ? 'recurrence'
              : matchedMarker == '🏁'
              ? 'completionAction'
              : markerFields[matchedMarker]!;
          if (fields.containsKey(field)) {
            throw FormatException(
              'Duplicate $field on line ${lines.length + 1}.',
            );
          }
          final start = i + matchedMarker.length;
          final ws = RegExp(r'^\s*').firstMatch(body.substring(start))![0]!;
          final valueStart = start + ws.length;
          String value;
          if (field == 'recurrence') {
            final choices = [
              for (final rule in rules) ...[rule, '$rule when done'],
            ]..sort((a, b) => b.length.compareTo(a.length));
            final found = choices.where(
              (s) =>
                  body.startsWith(s, valueStart) &&
                  (valueStart + s.length == body.length ||
                      RegExp(r'\s').hasMatch(body[valueStart + s.length])),
            );
            if (found.isEmpty) {
              throw FormatException(
                'Unsupported recurrence on line ${lines.length + 1}.',
              );
            }
            value = found.first;
            final remainder = body
                .substring(valueStart + value.length)
                .trimLeft();
            if (remainder.isNotEmpty &&
                !RegExp(r'^(#|🛫|⏳|📅|✅|🏁)').hasMatch(remainder)) {
              throw FormatException(
                'Unparsed recurrence suffix on line ${lines.length + 1}.',
              );
            }
          } else if (field == 'completionAction') {
            final found = RegExp(
              r'^[A-Za-z]+(?=\s|$)',
            ).firstMatch(body.substring(valueStart));
            if (found == null ||
                !['keep', 'delete'].contains(found[0]!.toLowerCase())) {
              throw FormatException(
                'Unsupported completion action on line ${lines.length + 1}; expected keep or delete.',
              );
            }
            value = found[0]!;
            final remainder = body
                .substring(valueStart + value.length)
                .trimLeft();
            if (remainder.isNotEmpty &&
                !RegExp(r'^(#|🛫|⏳|📅|✅|🔁|🏁)').hasMatch(remainder)) {
              throw FormatException(
                'Unparsed completion-action suffix on line ${lines.length + 1}.',
              );
            }
          } else {
            final found = date.firstMatch(body.substring(valueStart));
            if (found == null) throw FormatException('Invalid $field date.');
            value = found[1]!;
            final parsed = DateTime.tryParse(value);
            if (parsed == null ||
                parsed.toIso8601String().substring(0, 10) != value) {
              throw FormatException('Invalid calendar date.');
            }
          }
          fields[field] = value;
          parts.add({'literal': '$matchedMarker$ws'});
          parts.add({'field': field});
          i = valueStart + value.length;
          continue;
        }
        if (boundary &&
            [
              '➕',
              '🆔',
              '⛔',
              '⏫',
              '🔼',
              '🔽',
              '⏬',
              '❌',
            ].any((s) => body.startsWith(s, i))) {
          throw FormatException(
            'Unsupported Tasks metadata on line ${lines.length + 1}.',
          );
        }
        literal += body[i++];
      }
      flush();
      fields['titlePieces'] = titlePieces;
      fields['title'] = titlePieces.join(' ');
      if ((fields['title'] as String).isEmpty) {
        throw FormatException('Empty task title.');
      }
      lines.add({'fields': fields, 'parts': parts, 'ending': ending});
    }
    return MarkdownSource(bom, lines);
  }

  Map<String, dynamic> toJson() => {
    'formatVersion': 1,
    'encoding': 'utf-8',
    'bom': bom,
    'lines': lines,
  };
  factory MarkdownSource.fromJson(Map<String, dynamic> json) {
    if (json['formatVersion'] != 1 || json['encoding'] != 'utf-8') {
      throw FormatException('Unsupported source map.');
    }
    return MarkdownSource(
      json['bom'] as bool,
      (json['lines'] as List).cast<Map<String, dynamic>>(),
    );
  }
  List<int> render() {
    final output = StringBuffer();
    for (final line in lines) {
      if (line.containsKey('literal')) {
        output.write(line['literal']);
      } else {
        final fields = line['fields'] as Map<String, dynamic>;
        for (final part
            in (line['parts'] as List).cast<Map<String, dynamic>>()) {
          if (part.containsKey('literal')) {
            output.write(part['literal']);
            continue;
          }
          final field = part['field'];
          switch (field) {
            case 'completed':
              output.write(fields['completed'] == true ? part['checked'] : ' ');
            case 'title':
              output.write(
                (fields['titlePieces'] as List)[part['piece'] as int],
              );
            case 'tag':
              if ((part['value'] as String).startsWith('#start-time-')) {
                final time = fields['startTime'] as String?;
                if (time == null) {
                  throw const FormatException(
                    'Start time removed; edited-source exporter required.',
                  );
                }
                output.write('#start-time-${time.replaceAll(':', '')}');
                break;
              }
              if (!(fields['tags'] as List).contains(part['value'])) {
                throw FormatException(
                  'Removed tag requires an edited-document exporter.',
                );
              }
              output.write(part['value']);
            default:
              output.write(fields[field]);
          }
        }
      }
      output.write(line['ending']);
    }
    return [
      ...(bom ? [239, 187, 191] : <int>[]),
      ...utf8.encode(output.toString()),
    ];
  }
}
