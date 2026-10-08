import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'event.dart';

/// Canonical field identity. Seed, workspace, entity and activation basis are
/// all scoped explicitly; an update for another field cannot alias this one.
class TextFieldContext {
  TextFieldContext({
    required this.space,
    required this.entity,
    required this.field,
    required this.basis,
    required this.basisKind,
    required this.seedHash,
  }) {
    final reference = basis.split(':');
    final sequence = reference.length == 2 ? int.tryParse(reference[1]) : null;
    final recurring = basisKind == 'recurring-successor';
    if (!isCanonicalId(space) ||
        !isCanonicalId(entity) ||
        !const {'title', 'description'}.contains(field) ||
        (recurring
            ? !isEventHash(basis)
            : reference.length != 2 ||
                  !isCanonicalId(reference[0]) ||
                  sequence == null ||
                  sequence < 1 ||
                  sequence > 9007199254740991 ||
                  reference[1] != sequence.toString()) ||
        !const {
          'native-creation',
          'legacy-baseline',
          'legacy-creation',
          'recurring-successor',
        }.contains(basisKind) ||
        !isEventHash(seedHash)) {
      throw FormatFailure('Invalid native text field context.');
    }
  }

  factory TextFieldContext.successor(TextFieldContext parent, String child) =>
      TextFieldContext(
        space: parent.space,
        entity: child,
        field: parent.field,
        basis: parent.hash,
        basisKind: 'recurring-successor',
        seedHash: parent.seedHash,
      );

  factory TextFieldContext.fromCreation(LogEvent event, String field) {
    if (!isNativeTextCreation(event.type)) {
      throw FormatFailure('Native field context requires its creation record.');
    }
    validateTextSeedDescriptor(event.data['text']);
    final seeds = (event.data['text'] as Map)['seeds'] as Map;
    if (!seeds.containsKey(field)) {
      throw FormatFailure('Invalid native text field.');
    }
    return TextFieldContext(
      space: event.space,
      entity: event.entity,
      field: field,
      basis: event.id,
      basisKind: 'native-creation',
      seedHash: seeds[field] as String,
    );
  }

  final String space, entity, field, basis, basisKind, seedHash;
  String get hash => sha256
      .convert(
        utf8.encode(
          canonicalTextJson({
            'domain': 'tandemlog.text.context.v1',
            'space': space,
            'entity': entity,
            'field': field,
            'basis': basis,
            'basisKind': basisKind,
            'codec': 'yrs-v1',
            'adapter': 1,
            'seedHash': seedHash,
          }),
        ),
      )
      .toString();
}

String canonicalTextJson(Object? value) => canonicalDataJson(value);

/// A baseline agrees on the exact seeded text for every legacy task field.
/// No original text or source-format metadata is stored in this descriptor.
String textBaselineSeedDigest(Map<String, Map<String, String>> fields) {
  for (final entry in fields.entries) {
    final values = entry.value;
    if (!isCanonicalId(entry.key) ||
        values.length != 2 ||
        !values.containsKey('title') ||
        !values.containsKey('description') ||
        values.values.any((value) => !isEventHash(value))) {
      throw FormatFailure('Invalid text baseline seed fields.');
    }
  }
  return sha256
      .convert(
        utf8.encode(
          canonicalTextJson({
            'domain': 'tandemlog.text.baseline.v1',
            'fields': fields,
          }),
        ),
      )
      .toString();
}
