import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Protocol v3 uses domain-separated SHA-256 over canonical UTF-8 JSON.
/// This detects accidental edits; without a trusted head it does not authenticate
/// writers or prove that the final records of a history have not been removed.
const eventHashDomain = 'tandemlog:event:v3\n';
const eventGenesisDomain = 'tandemlog:genesis:v3\n';
const eventEnvelopeKeys = [
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
];

bool isEventHash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String eventGenesisHash(String space, String writer) => sha256
    .convert(utf8.encode('$eventGenesisDomain$space\n$writer\n'))
    .toString();

String eventRecordHash(Map<String, dynamic> record) => sha256
    .convert(
      utf8.encode(
        '$eventHashDomain${canonicalEventJson(record, includeHash: false)}',
      ),
    )
    .toString();

/// Envelope keys have the fixed order above; all nested object keys are sorted
/// by Unicode scalar value. Arrays keep their order. There is no whitespace or
/// Unicode normalization. Integers use plain decimal in the JSON-safe range;
/// floating-point numbers are outside the v3 data model.
String canonicalEventJson(
  Map<String, dynamic> record, {
  bool includeHash = true,
}) {
  final keys = includeHash
      ? eventEnvelopeKeys
      : eventEnvelopeKeys.take(eventEnvelopeKeys.length - 1);
  return '{${keys.map((key) {
    if (!record.containsKey(key)) {
      throw FormatException('Missing event field $key.');
    }
    return '${_string(key)}:${_value(record[key])}';
  }).join(',')}}';
}

String _value(Object? value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) {
    if (value < -9007199254740991 || value > 9007199254740991) {
      throw const FormatException('JSON integer exceeds the exact safe range.');
    }
    return value.toString();
  }
  if (value is String) return _string(value);
  if (value is List) return '[${value.map(_value).join(',')}]';
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const FormatException('JSON object keys must be strings.');
    }
    final keys = value.keys.cast<String>().toList()..sort(_compareScalars);
    return '{${keys.map((key) => '${_string(key)}:${_value(value[key])}').join(',')}}';
  }
  throw const FormatException('Unsupported JSON value in event.');
}

int _compareScalars(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;
  while (true) {
    final hasLeft = left.moveNext();
    final hasRight = right.moveNext();
    if (!hasLeft || !hasRight) {
      return hasLeft ? 1 : (hasRight ? -1 : 0);
    }
    final result = left.current.compareTo(right.current);
    if (result != 0) return result;
  }
}

/// Quote/backslash and controls are escaped. Controls use b/f/n/r/t where
/// available and lowercase u00xx otherwise. All other scalar values are literal.
/// Unpaired UTF-16 surrogates are rejected instead of being replaced by UTF-8.
String _string(String value) {
  final result = StringBuffer('"');
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 1 >= value.length ||
          value.codeUnitAt(i + 1) < 0xdc00 ||
          value.codeUnitAt(i + 1) > 0xdfff) {
        throw const FormatException('Unpaired Unicode surrogate in event.');
      }
      result.write(value.substring(i, i + 2));
      i++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Unpaired Unicode surrogate in event.');
    } else {
      switch (unit) {
        case 0x22:
          result.write(r'\"');
        case 0x5c:
          result.write(r'\\');
        case 0x08:
          result.write(r'\b');
        case 0x0c:
          result.write(r'\f');
        case 0x0a:
          result.write(r'\n');
        case 0x0d:
          result.write(r'\r');
        case 0x09:
          result.write(r'\t');
        default:
          if (unit < 0x20) {
            result.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
          } else {
            result.writeCharCode(unit);
          }
      }
    }
  }
  result.write('"');
  return result.toString();
}
