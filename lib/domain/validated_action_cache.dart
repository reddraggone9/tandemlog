import 'dart:collection';
import 'dart:convert';

/// One effect in a verified clean batch. Position, kind, raw evidence and typed
/// values cannot be substituted by callers.
final class ValidatedActionEffect {
  const ValidatedActionEffect._(
    this.recordIndex,
    this.effectIndex,
    this.kind,
    this.raw,
    this.fields,
  );
  final int recordIndex, effectIndex;
  final String kind, raw;
  final List<Object?>? fields;
  int get layout => 3;
}

final class ValidatedCachedAction {
  const ValidatedCachedAction._(this.raw, this.value, this.effects);
  final String raw;
  final Map<String, dynamic> value;
  final List<ValidatedActionEffect> effects;
}

/// Rows of the local history store (design/history-store.md) restored into
/// typed effects. Trust comes from the store's seal and the open's fast check
/// (Lee 11-05), so rows are not re-hashed; this only decodes and checks shape.
final class ValidatedActionCache {
  const ValidatedActionCache._(this.records);
  static const layout = 3;
  // Process-local decode memo bound (UnifiedHistory); the persistent store
  // itself has no cap beyond the log safety limits.
  static const maximumBytes = 64 * 1024 * 1024;
  static const maximumRecords = 16384;
  final List<ValidatedCachedAction> records;

  /// [rows] are (canonical record text, typed effect fields JSON) pairs.
  static ValidatedActionCache fromStoredRows(List<(String, String)> rows) {
    final result = <ValidatedCachedAction>[];
    for (var index = 0; index < rows.length; index++) {
      final (raw, typedJson) = rows[index];
      final value = _freeze(jsonDecode(raw)) as Map<String, dynamic>;
      final wire = value['effects'] as List;
      final typed = _freeze(jsonDecode(typedJson)) as List;
      if (wire.isEmpty || wire.length > 10000 || typed.length != wire.length) {
        throw const FormatException('Invalid stored effect mapping.');
      }
      final effects = <ValidatedActionEffect>[];
      for (var effectIndex = 0; effectIndex < wire.length; effectIndex++) {
        final item = wire[effectIndex] as Map;
        if (item.length != 2 || !item.keys.every({'kind', 'raw'}.contains)) {
          throw const FormatException('Invalid stored raw effect.');
        }
        final kind = item['kind'] as String, effectRaw = item['raw'] as String;
        if (!const {
          'task',
          'history.task',
          'food',
          'history.food',
          'writer.named',
          'writer.joined',
        }.contains(kind)) {
          throw const FormatException('Unknown stored effect kind.');
        }
        final data = typed[effectIndex];
        List<Object?>? fields;
        if (data != null) {
          final pair = data as List;
          if (pair.length != 2 || pair[0] != kind) {
            throw const FormatException('Stored effect kind differs.');
          }
          fields = (pair[1] as List).cast<Object?>();
        } else if (kind == 'task' ||
            kind == 'history.task' ||
            kind == 'food' ||
            kind == 'history.food') {
          throw const FormatException('Missing stored module payload.');
        }
        effects.add(
          ValidatedActionEffect._(index, effectIndex, kind, effectRaw, fields),
        );
      }
      result.add(
        ValidatedCachedAction._(raw, value, List.unmodifiable(effects)),
      );
    }
    return ValidatedActionCache._(List.unmodifiable(result));
  }
}

Object? _freeze(Object? value) {
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    for (final key in map.keys) {
      map[key] = _freeze(map[key]);
    }
    return UnmodifiableMapView<String, dynamic>(map);
  }
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      value[index] = _freeze(value[index]);
    }
    return UnmodifiableListView<Object?>(value.cast<Object?>());
  }
  return value;
}
