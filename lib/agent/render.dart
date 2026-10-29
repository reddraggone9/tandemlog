import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../food/inventory.dart';
import 'agent_profile.dart';

/// Output contract version; additive within v1, renames/removals bump it.
const agentOutputVersion = 1;
const outputCapBytes = 32 * 1024;
const defaultLimit = 50;

String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

String revOf(Object? canonical) => sha256
    .convert(utf8.encode(jsonEncode(canonical)))
    .toString()
    .substring(0, 8);

/// Unique prefix of 8+ characters, or the full ID. Ambiguity is an error,
/// never a guess.
String resolveId(String input, Iterable<String> ids, String noun) {
  final needle = input.toLowerCase();
  if (needle.length < 8) {
    throw AgentFailure(
      'validation',
      'Use at least 8 characters of the $noun ID.',
      details: {'field': 'id', 'error': 'too_short'},
    );
  }
  final matches = ids.where((id) => id.startsWith(needle)).toSet().toList();
  if (matches.isEmpty) {
    throw AgentFailure('not_found', 'No $noun matches "$input".');
  }
  if (matches.length > 1) {
    throw AgentFailure(
      'ambiguous_id',
      '"$input" matches ${matches.length} ${noun}s.',
      details: {'candidates': matches.take(10).toList()},
    );
  }
  return matches.single;
}

/// A page of rows with an opaque cursor bound to the query that produced it.
class Page<T> {
  Page(this.rows, this.total, this._key, this._offset, [this.memberOffset = 0]);
  final List<T> rows;
  final int total;
  final String _key;
  final int _offset;

  /// Members of the first row already returned by earlier pages (a cursor
  /// that resumes inside an oversized row); later rows start at zero.
  final int memberOffset;

  String? get next => after(rows.length);

  /// Cursor of the first row after the first [shown] rows of this page.
  String? after(int shown) {
    final end = _offset + shown;
    return end < total
        ? base64Url.encode(utf8.encode(jsonEncode({'q': _key, 'o': end})))
        : null;
  }

  /// Cursor resuming inside this page's first row after [members] more of
  /// its members; always advances, so an oversized row still pages.
  String within(int members) => base64Url.encode(
    utf8.encode(
      jsonEncode({'q': _key, 'o': _offset, 'm': memberOffset + members}),
    ),
  );

  static Page<T> of<T>(
    List<T> all, {
    required int? limit,
    required String? cursor,
    required String query,
  }) {
    final bound = limit ?? defaultLimit;
    if (bound < 1) {
      throw const AgentFailure(
        'validation',
        'limit must be at least 1.',
        details: {'field': 'limit', 'error': 'range'},
      );
    }
    final key = revOf(query);
    var offset = 0;
    var members = 0;
    if (cursor != null) {
      try {
        final j =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
                )
                as Map;
        if (j['q'] != key) throw const FormatException();
        offset = j['o'] as int;
        members = (j['m'] as int?) ?? 0;
        if (offset < 0 || members < 0) throw const FormatException();
      } catch (_) {
        throw const AgentFailure(
          'validation',
          'This cursor belongs to a different query.',
          details: {'field': 'cursor', 'error': 'invalid'},
        );
      }
    }
    final end = (offset + bound).clamp(0, all.length);
    final rows = offset >= all.length ? <T>[] : all.sublist(offset, end);
    return Page(
      rows,
      all.length,
      key,
      offset.clamp(0, all.length),
      rows.isEmpty ? 0 : members,
    );
  }
}

/// Cap rendered text at [outputCapBytes] (UTF-8); the marker is explicit.
/// The first [leading] lines are not page rows. When rows are dropped and
/// [page] is given, the marker carries the cursor of the first dropped row.
String capText(
  List<String> lines, {
  String? header,
  Page<Object?>? page,
  int leading = 0,
}) {
  final out = StringBuffer();
  var size = 0;
  var truncated = false;
  var shown = 0;
  // Room for the marker and its cursor line.
  const reserve = 512;
  bool add(String line) {
    final n = utf8.encode(line).length + 1;
    if (size + n > outputCapBytes - reserve) {
      truncated = true;
      return false;
    }
    size += n;
    out.writeln(line);
    return true;
  }

  if (header != null) add(header);
  for (var i = 0; i < lines.length && !truncated; i++) {
    if (add(lines[i]) && i >= leading) shown++;
  }
  final next = truncated ? page?.after(shown) : page?.next;
  if (truncated) {
    out.writeln(
      '… truncated at 32 KB after $shown rows; '
      '${page == null ? 'use --format jsonl' : 'continue with --cursor or use --format jsonl'}',
    );
  }
  if (next != null) out.writeln('next: $next');
  return out.toString().trimRight();
}

String clip(String value, int max) {
  final single = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return single.length <= max ? single : '${single.substring(0, max - 1)}…';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2026-10-30` → `Oct 30`, adding the year when it differs from [thisYear].
String shortDate(String? civil, int thisYear) {
  if (civil == null) return '';
  final parts = civil.split('-');
  if (parts.length != 3) return civil;
  final y = int.parse(parts[0]),
      m = int.parse(parts[1]),
      d = int.parse(parts[2]);
  return '${_months[m - 1]} $d${y == thisYear ? '' : ', $y'}';
}

String taskScheduleText(Map<String, dynamic> schedule, int thisYear) {
  final parts = <String>[];
  String at(String? date, String? time) =>
      [shortDate(date, thisYear), ?time].where((s) => s.isNotEmpty).join(' ');
  if (schedule['startDate'] != null || schedule['startTime'] != null) {
    parts.add('Start ${at(schedule['startDate'], schedule['startTime'])}');
  }
  if (schedule['dueDate'] != null || schedule['dueTime'] != null) {
    parts.add('Due ${at(schedule['dueDate'], schedule['dueTime'])}');
  }
  if (schedule['scheduledDate'] != null) {
    parts.add(
      'This occurrence ${at(schedule['scheduledDate'], schedule['scheduledTime'])}',
    );
  }
  final recurrence = schedule['recurrence'];
  if (recurrence != null) parts.add('↻ ${recurrenceText(recurrence)}');
  return parts.join(' · ');
}

/// The stored rule (for example `FREQ=MONTHLY`) is already terse.
String recurrenceText(Object recurrence) =>
    recurrence is String ? recurrence : 'repeats';

/// [from] skips containers an earlier page already returned (a cursor that
/// resumes inside an oversized row); `count` stays the whole group's.
Map<String, Object?> foodGroupJson(FoodGroup g, {int from = 0}) {
  final d = g.details;
  final start = from.clamp(0, g.containers.length);
  return {
    'key': revOf(g.key),
    'product': g.product,
    'name': d.name,
    'brand': d.brand,
    'size': d.size,
    'expiry': d.expiry,
    'location': d.location,
    'retention': d.retention,
    'count': g.containers.length,
    'summary': g.summary,
    'deleted': g.containers.first.deleted,
    if (start > 0) 'containersFrom': start,
    'containers': [
      for (final c in g.containers.skip(start)) {'id': c.id, 'rev': foodRev(c)},
    ],
  };
}

String foodRev(FoodContainer c) => revOf(c.toJson());

String foodGroupLine(FoodGroup g, int thisYear) {
  final d = g.details;
  final parts = <String>[
    '${shortId(g.containers.first.id)} ${d.name}',
    if (d.brand.isNotEmpty) d.brand,
    [if (d.size.isNotEmpty) d.size, '×${g.containers.length}'].join(' '),
    if (d.expiry != null) 'exp ${shortDate(d.expiry, thisYear)}',
    if (d.location.isNotEmpty) d.location,
    if (d.retention.isNotEmpty) 'kept: ${d.retention}',
    if (g.containers.first.deleted) 'deleted',
  ];
  final ids = g.containers.length > 1
      ? ' · ids ${g.containers.map((c) => shortId(c.id)).join(',')}'
      : '';
  return '${parts.join(' · ')}$ids';
}
