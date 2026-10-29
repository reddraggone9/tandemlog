import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

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

/// Pure verification of the concrete action decode-cache format. This is a
/// corruption/staleness checksum under the private profile trust model, not
/// authentication against replacement of both cache and its proof.
final class ValidatedActionCache {
  const ValidatedActionCache._(this.records);
  static const layout = 3;
  static const maximumBytes = 16 * 1024 * 1024;
  final List<ValidatedCachedAction> records;

  // At most one in-flight verification. Two independently opened profiles can
  // share only the exact same payload, digest AND scope, never a path/stat hint.
  // The opaque immutable receipt is safe to share; no SQL/native owner crosses
  // the isolate boundary. Drop all inputs as soon as verification settles.
  static ({
    String payload,
    String digest,
    String binding,
    Future<ValidatedActionCache> result,
  })?
  _flight;

  static Future<ValidatedActionCache> verifyOffThread(
    String payload,
    String digest,
    String binding,
  ) {
    final old = _flight;
    if (old != null &&
        old.payload == payload &&
        old.digest == digest &&
        old.binding == binding) {
      return old.result;
    }
    late final Future<ValidatedActionCache> result;
    result = _verifyInIsolate(payload, digest, binding).whenComplete(() {
      if (identical(_flight?.result, result)) _flight = null;
    });
    _flight = (
      payload: payload,
      digest: digest,
      binding: binding,
      result: result,
    );
    return result;
  }

  static ValidatedActionCache verify(
    String payload,
    String expectedDigest,
    String expectedBinding,
  ) {
    if (payload.length > maximumBytes) {
      throw const FormatException('Disposable action-cache exceeds bound.');
    }
    final bytes = utf8.encode(payload);
    if (bytes.length > maximumBytes ||
        sha256.convert(bytes).toString() != expectedDigest) {
      throw const FormatException('Disposable action-cache digest differs.');
    }
    final envelope = jsonDecode(payload) as Map<String, dynamic>;
    if (envelope.length != 3 ||
        !envelope.keys.every({'generation', 'binding', 'records'}.contains) ||
        envelope['generation'] != layout ||
        envelope['binding'] != expectedBinding) {
      throw const FormatException('Disposable action-cache scope differs.');
    }
    final rows = _freeze(envelope['records']) as List;
    if (rows.length > 4096) {
      throw const FormatException(
        'Disposable action-cache count exceeds bound.',
      );
    }
    final result = <ValidatedCachedAction>[], raws = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final tuple = rows[index] as List;
      if (tuple.length != 2) {
        throw const FormatException('Invalid action-cache row.');
      }
      final raw = tuple[0] as String;
      if (!raws.add(raw)) {
        throw const FormatException('Duplicate action-cache raw mapping.');
      }
      final value = _freeze(jsonDecode(raw)) as Map<String, dynamic>;
      final wire = value['effects'] as List, typed = tuple[1] as List;
      if (wire.isEmpty || wire.length > 10000 || typed.length != wire.length) {
        throw const FormatException('Invalid cached effect mapping.');
      }
      final effects = <ValidatedActionEffect>[];
      for (var effectIndex = 0; effectIndex < wire.length; effectIndex++) {
        final item = wire[effectIndex] as Map;
        if (item.length != 2 || !item.keys.every({'kind', 'raw'}.contains)) {
          throw const FormatException('Invalid cached raw effect.');
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
          throw const FormatException('Unknown cached effect kind.');
        }
        final data = typed[effectIndex];
        List<Object?>? fields;
        if (data != null) {
          final pair = data as List;
          if (pair.length != 2 || pair[0] != kind) {
            throw const FormatException('Cached effect kind differs.');
          }
          fields = (pair[1] as List).cast<Object?>();
        } else if (kind == 'task' ||
            kind == 'history.task' ||
            kind == 'food' ||
            kind == 'history.food') {
          throw const FormatException('Missing cached module payload.');
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

// Both callers hand over fresh, exclusively owned jsonDecode trees. Replace
// children before wrapping, so no mutable backing alias can escape; avoid
// allocating a second map/list and then copying it again for unmodifiable().
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

// Separate lexical scope: the worker must not capture the in-flight Future.
Future<ValidatedActionCache> _verifyInIsolate(
  String payload,
  String digest,
  String binding,
) => Isolate.run(
  () => ValidatedActionCache.verify(payload, digest, binding),
  debugName: 'tandemlog-cache-verify',
);
