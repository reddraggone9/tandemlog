import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_context.dart';

const space = '00000000-0000-4000-8000-000000000001';
const entity = '00000000-0000-4000-8000-000000000002';
const writer = '00000000-0000-4000-8000-000000000003';
final seed = 'a' * 64;

TextFieldContext context({String field = 'title', String? entityId}) =>
    TextFieldContext(
      space: space,
      entity: entityId ?? entity,
      field: field,
      basis: '$writer:7',
      basisKind: 'native-creation',
      seedHash: seed,
    );

void main() {
  test('context hashes the precise canonical domain descriptor', () {
    final encoded = canonicalTextJson({
      'domain': 'tandemlog.text.context.v1',
      'space': space,
      'entity': entity,
      'field': 'title',
      'basis': '$writer:7',
      'basisKind': 'native-creation',
      'codec': 'yrs-v1',
      'adapter': 1,
      'seedHash': seed,
    });
    expect(context().hash, sha256.convert(utf8.encode(encoded)).toString());
    expect(context().hash, context().hash);
    expect(context(field: 'description').hash, isNot(context().hash));
    expect(context(entityId: writer).hash, isNot(context().hash));
  });
  test('canonical nested values reuse scalar ordering and exact escaping', () {
    expect(
      canonicalTextJson({'\u{10000}': 2, '\ue000': 1, 'x': '\n'}),
      '{"x":"\\n","\ue000":1,"\u{10000}":2}',
    );
    expect(
      () => canonicalTextJson({'x': 9007199254740992}),
      throwsFormatException,
    );
    expect(
      () => canonicalTextJson({'x': String.fromCharCode(0xd800)}),
      throwsFormatException,
    );
  });
  test('invalid identity, basis, field, kind and digest fail closed', () {
    TextFieldContext make({
      String s = space,
      String e = entity,
      String f = 'title',
      String b = '$writer:7',
      String k = 'native-creation',
      String? h,
    }) => TextFieldContext(
      space: s,
      entity: e,
      field: f,
      basis: b,
      basisKind: k,
      seedHash: h ?? seed,
    );
    for (final build in [
      () => make(s: 'bad'),
      () => make(e: 'bad'),
      () => make(f: 'name'),
      () => make(b: '$writer:0'),
      () => make(b: '$writer:9007199254740992'),
      () => make(k: 'future'),
      () => make(h: 'A' * 64),
    ]) {
      expect(build, throwsA(isA<FormatFailure>()));
    }
  });
  test(
    'native creation context uses its canonical creation and seed hashes',
    () {
      final event = LogEvent(
        space,
        writer,
        7,
        EventClock(BigInt.from(8)),
        entity,
        'task.createdWithText',
        {
          'title': 'Task',
          'description': '',
          'assignee': writer,
          'text': {
            'codec': 'yrs-v1',
            'adapter': 1,
            'seeds': {'title': seed, 'description': 'b' * 64},
          },
        },
      );
      expect(
        TextFieldContext.fromCreation(event, 'title').hash,
        context().hash,
      );
      expect(
        () => TextFieldContext.fromCreation(
          LogEvent(
            space,
            writer,
            7,
            EventClock(BigInt.from(8)),
            entity,
            'task.created',
            {},
          ),
          'title',
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test('baseline digest is independent of object insertion order', () {
    final a = textBaselineSeedDigest({
      entity: {'title': seed, 'description': 'b' * 64},
      writer: {'title': 'c' * 64, 'description': 'd' * 64},
    });
    final b = textBaselineSeedDigest({
      writer: {'description': 'd' * 64, 'title': 'c' * 64},
      entity: {'description': 'b' * 64, 'title': seed},
    });
    expect(a, b);
    expect(
      a,
      isNot(
        textBaselineSeedDigest({
          entity: {'title': seed, 'description': 'b' * 64},
        }),
      ),
    );
    expect(textBaselineSeedDigest({}), matches(RegExp(r'^[0-9a-f]{64}$')));
  });
  test('baseline digest rejects incomplete or arbitrary fields', () {
    for (final fields in <Map<String, Map<String, String>>>[
      {
        'bad': {'title': seed, 'description': seed},
      },
      {
        entity: {'title': seed},
      },
      {
        entity: {'title': seed, 'description': seed, 'rawSource': seed},
      },
      {
        entity: {'title': seed, 'description': 'bad'},
      },
    ]) {
      expect(
        () => textBaselineSeedDigest(fields),
        throwsA(isA<FormatFailure>()),
      );
    }
  });
}
