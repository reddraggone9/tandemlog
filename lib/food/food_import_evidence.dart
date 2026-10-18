import 'dart:convert';
import '../domain/event.dart';
import '../storage/local_profile_database.dart';
import 'food_record.dart';

/// Existing bounded private import witness validation, shared by v3 and v4.
List<Map<String, dynamic>> readFoodImportEvidence(
  LocalProfileDatabase profile,
  String space,
) {
  final importPrefix = 'food.import.v1.$space.';
  // Bound corrupt/local inputs before SQLite materializes ledger strings.
  final totals = profile.database.select(
    "SELECT COUNT(*) AS n,COALESCE(SUM(length(CAST(value AS BLOB))),0) AS bytes,COALESCE(MAX(length(CAST(value AS BLOB))),0) AS largest,COALESCE(MAX(length(CAST(key AS BLOB))),0) AS keyBytes,COALESCE(SUM(CASE WHEN typeof(value)='text' THEN 0 ELSE 1 END),0) AS invalid FROM profile_metadata WHERE key LIKE ?",
    ['$importPrefix%'],
  ).single;
  if ((totals['n'] as int) > 101 ||
      (totals['bytes'] as int) > 26 * 1024 * 1024 ||
      (totals['largest'] as int) > 256 * 1024 ||
      (totals['keyBytes'] as int) > 256 ||
      totals['invalid'] != 0) {
    throw const FormatException('Import evidence exceeds safe read limits.');
  }
  final rows = profile.database.select(
    'SELECT key,value FROM profile_metadata WHERE key LIKE ?',
    ['$importPrefix%'],
  );
  final witness = profile.database.select(
    'SELECT version FROM protected_food_import_witnesses WHERE space=?',
    [space],
  );
  if ((witness.isEmpty != rows.isEmpty) ||
      (witness.isNotEmpty && witness.single['version'] != 1)) {
    throw const FormatException(
      'Import initialization evidence is missing or differs.',
    );
  }
  if (rows.isEmpty) return [];
  if (rows.length > 101) {
    throw const FormatException('Too many import attempts.');
  }
  final byKey = {
    for (final row in rows) row['key'] as String: row['value'] as String,
  };
  final rawIndex = byKey.remove('${importPrefix}index');
  if (rawIndex == null || utf8.encode(rawIndex).length > 64 * 1024) {
    throw const FormatException('Import source witness is missing or invalid.');
  }
  final index = jsonDecode(rawIndex);
  if (index is! List || index.isEmpty || index.length > 100) {
    throw const FormatException('Invalid import source witness.');
  }
  final result = <Map<String, dynamic>>[];
  final namespaces = <String>{}, sources = <String>{};
  for (final entry in index) {
    if (entry is! Map<String, dynamic> ||
        entry.length != 4 ||
        !{
          'importId',
          'sourceSha256',
          'planHash',
          'writer',
        }.every(entry.containsKey) ||
        !isCanonicalId(entry['importId']) ||
        !isCanonicalId(entry['writer']) ||
        !_validHash(entry['sourceSha256']) ||
        !_validHash(entry['planHash']) ||
        !namespaces.add(entry['importId']) ||
        !sources.add(entry['sourceSha256'])) {
      throw const FormatException('Invalid import source witness.');
    }
    final raw = byKey.remove('${importPrefix}attempt.${entry['importId']}');
    if (raw == null || utf8.encode(raw).length > 256 * 1024) {
      throw const FormatException(
        'Import attempt evidence is missing or invalid.',
      );
    }
    final attempt = jsonDecode(raw);
    if (attempt is! Map<String, dynamic> ||
        attempt.length != 7 ||
        !{
          'v',
          'space',
          'importId',
          'sourceSha256',
          'planHash',
          'writer',
          'records',
        }.every(attempt.containsKey) ||
        attempt['v'] is! int ||
        attempt['v'] != 1 ||
        attempt['space'] != space ||
        entry.keys.any((key) => attempt[key] != entry[key]) ||
        attempt['records'] is! List ||
        (attempt['records'] as List).isEmpty ||
        (attempt['records'] as List).length > 1000) {
      throw const FormatException('Invalid import attempt evidence.');
    }
    final recordIds = <String>{};
    int? priorSequence;
    for (final record in attempt['records'] as List) {
      if (record is! Map<String, dynamic> ||
          record.length != 2 ||
          !record.containsKey('id') ||
          !record.containsKey('hash') ||
          record['id'] is! String ||
          !_validHash(record['hash'])) {
        throw const FormatException('Invalid import record evidence.');
      }
      validateFoodReference(record['id']);
      final parts = (record['id'] as String).split(':');
      final sequence = int.parse(parts.last);
      if (parts.first != attempt['writer'] ||
          !recordIds.add(record['id']) ||
          (priorSequence != null && sequence != priorSequence + 1)) {
        throw const FormatException('Invalid import record evidence.');
      }
      priorSequence = sequence;
    }
    result.add(attempt);
  }
  if (byKey.isNotEmpty) {
    throw const FormatException('Import witness omits retained attempts.');
  }
  return result;
}

bool _validHash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
