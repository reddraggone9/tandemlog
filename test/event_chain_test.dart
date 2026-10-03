import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

const space = '11111111-1111-4111-8111-111111111111';
const writer = '22222222-2222-4222-8222-222222222222';
const entity = '33333333-3333-4333-8333-333333333333';
const genesis =
    '45f93a5918726c4021803b86223e37965d486fd10c851c9499e615b55b5ef453';

LogEvent example({int sequence = 1, Map<String, dynamic>? data}) => LogEvent(
  space,
  writer,
  sequence,
  EventClock(BigInt.from(sequence)),
  entity,
  'user.created',
  data ?? {'name': 'Example'},
);

String sealed(Map<String, dynamic> record) {
  record['hash'] = eventRecordHash(record);
  return canonicalEventJson(record);
}

void main() {
  test('independent Python SHA256 golden JSONL is byte-exact on re-encode', () {
    // Fixture generated with Python hashlib.sha256 and compact json.dumps,
    // recursively sorted data keys, ensure_ascii=False; never the Dart codec.
    final lines = File('test/fixtures/event_chain_v3.jsonl').readAsLinesSync();
    expect(lines, hasLength(2));
    expect(eventGenesisHash(space, writer), genesis);
    final first = LogEvent.decode(lines[0]);
    final second = LogEvent.decode(lines[1]);
    expect(first.previousHash, genesis);
    expect(
      first.hash,
      'b57729257a72d096db9a8d026bb898bc23300de70e8d7a4c1174b2a8f591256e',
    );
    expect(second.previousHash, first.hash);
    expect(
      second.hash,
      'a3faa7052ed9607b32bba52a69b419e314eaee69b2cc3910b69e179f6d65031b',
    );
    for (final (event, raw) in [(first, lines[0]), (second, lines[1])]) {
      expect(event.encode(), raw);
      expect(event.canonicalRaw, raw);
      expect(event.toJson()['hash'], event.hash);
    }
    expect(first.data['name'], 'Zoë 🧭\n"\\\t');
    expect(second.data['title'], 'Café é');
    expect(() => first.data['name'] = 'Edited', throwsUnsupportedError);
    expect(
      () => (second.data['schedule'] as Map)['dueDate'] = '2040-01-01',
      throwsUnsupportedError,
    );
    expect(
      () => (second.data['tags'] as List).add('tag'),
      throwsUnsupportedError,
    );
  });

  test('new records require an explicit predecessor beyond genesis', () {
    final first = LogEvent.decode(example().encode());
    expect(first.previousHash, genesis);
    expect(() => example(sequence: 2).encode(), throwsA(isA<FormatFailure>()));
    expect(() => example(sequence: 2).toJson(), throwsA(isA<FormatFailure>()));
    final second = LogEvent.decode(
      example(sequence: 2).encode(previousHash: first.hash),
    );
    expect(second.previousHash, first.hash);
    expect(second.hash, isNot(first.hash));
    expect(second.encode(), second.canonicalRaw);
    expect(eventGenesisHash(writer, space), isNot(genesis));
    expect(eventGenesisHash(space, entity), isNot(genesis));
  });

  test('canonical bytes reject alternate spellings and duplicate fields', () {
    final raw = example().encode();
    final record = example().toJson();
    final reordered = <String, dynamic>{
      'hash': record['hash'],
      ...record..remove('hash'),
    };
    for (final changed in [
      ' $raw',
      '$raw ',
      '$raw\n',
      '$raw\r',
      raw.replaceFirst(':3,', ': 3,'),
      raw.replaceFirst('"v":3', '"v":3,"v":3'),
      raw.replaceFirst('"Example"', r'"\u0045xample"'),
      raw.replaceFirst('"seq":1', '"seq":1.0'),
      jsonEncode(reordered),
    ]) {
      expect(() => LogEvent.decode(changed), throwsA(isA<FormatFailure>()));
    }
  });

  test('data key order is recursive and array order remains significant', () {
    final record = example().toJson();
    record['data'] = {
      'z': [3, 2, 1],
      'a': {'z': true, 'a': null},
      '\u{10000}': 'supplementary',
      '\ue000': 'BMP',
    };
    final canonical = canonicalEventJson(record);
    expect(
      canonical,
      contains(
        '"data":{"a":{"a":null,"z":true},"z":[3,2,1],"\ue000":"BMP","\u{10000}":"supplementary"}',
      ),
    );
    final hash = eventRecordHash(record);
    record['data'] = {
      '\ue000': 'BMP',
      'a': {'a': null, 'z': true},
      '\u{10000}': 'supplementary',
      'z': [3, 2, 1],
    };
    expect(eventRecordHash(record), hash);
    record['data']['z'] = [1, 2, 3];
    expect(eventRecordHash(record), isNot(hash));
  });

  test('altering any envelope field or content breaks the retained hash', () {
    final record = example().toJson();
    for (final (key, value) in [
      ('space', writer),
      ('writer', space),
      ('seq', 2),
      ('clock', '2'),
      ('entity', writer),
      ('type', 'task.deleted'),
      ('data', {'name': 'Altered'}),
      ('previousHash', '0' * 64),
      ('hash', '0' * 64),
    ]) {
      final changed = {...record, key: value};
      expect(
        () => LogEvent.decode(canonicalEventJson(changed)),
        throwsA(isA<FormatFailure>()),
      );
    }
    // Codec checks a self hash; stream admission checks the expected predecessor.
    final rebound = {...record, 'previousHash': '0' * 64};
    expect(LogEvent.decode(sealed(rebound)).previousHash, '0' * 64);
  });

  test('hash fields must be full lowercase hex and are mandatory', () {
    final record = example().toJson();
    for (final key in ['hash', 'previousHash']) {
      for (final bad in [
        null,
        3,
        '',
        'f' * 63,
        'G' * 64,
        genesis.toUpperCase(),
      ]) {
        expect(
          () => LogEvent.decode(jsonEncode({...record, key: bad})),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(
        () => LogEvent.decode(jsonEncode({...record}..remove(key))),
        throwsA(isA<FormatFailure>()),
      );
    }
  });

  test(
    'literal Unicode survives, malformed surrogates never become replacements',
    () {
      final text = 'é é 🧭 / \u2028\u2029\u0000\u001f\b\f\n\r\t"\\';
      final raw = example(data: {'name': text}).encode();
      expect(LogEvent.decode(raw).data['name'], text);
      expect(raw, contains('é é 🧭 / \u2028\u2029'));
      expect(raw, contains(r'\u0000\u001f\b\f\n\r\t\"\\'));
      for (final surrogate in [0xd800, 0xdbff, 0xdc00, 0xdfff]) {
        final bad = String.fromCharCode(surrogate);
        expect(
          () => example(data: {'name': 'bad$bad'}).encode(),
          throwsA(isA<FormatFailure>()),
        );
        final escaped = surrogate.toRadixString(16);
        expect(
          () => LogEvent.decode(raw.replaceFirst('é é 🧭', '\\u$escaped')),
          throwsA(isA<FormatFailure>()),
        );
      }
      expect(
        () => LogEvent.decode(raw.replaceFirst('🧭', r'\ud83e\udded')),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test('canonical numeric grammar is plain safe integers, never floats', () {
    final record = example().toJson();
    record['data'] = {
      'number': 9007199254740991,
      'negative': -9007199254740991,
    };
    expect(canonicalEventJson(record), contains('9007199254740991'));
    for (final unsupported in [
      9007199254740992,
      -9007199254740992,
      1.0,
      double.nan,
      double.infinity,
    ]) {
      record['data'] = {'number': unsupported};
      expect(() => canonicalEventJson(record), throwsFormatException);
    }
  });

  test('v1 and v2 prerelease histories remain explicit preserved failures', () {
    for (final version in [1, 2]) {
      expect(
        () => LogEvent.decode('{"v":$version}'),
        throwsA(
          isA<FormatFailure>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('older prerelease format (v$version)'),
              contains('Preserve'),
            ),
          ),
        ),
      );
    }
    for (final line in File(
      'test/fixtures/recurring_operation_undone_v2.jsonl',
    ).readAsLinesSync()) {
      expect(
        () => LogEvent.decode(line),
        throwsA(
          isA<FormatFailure>().having(
            (error) => error.message,
            'message',
            contains('(v2)'),
          ),
        ),
      );
    }
    expect(
      () => LogEvent.decode('{"v":99}'),
      throwsA(
        isA<FormatFailure>().having(
          (error) => error.message,
          'message',
          contains('Unsupported event version 99'),
        ),
      ),
    );
  });
}
