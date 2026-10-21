import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';

const space = '11111111-1111-4111-8111-111111111111';
const writer = '22222222-2222-4222-8222-222222222222';
const entity = '33333333-3333-4333-8333-333333333333';
const fixture = 'test/fixtures/current-operation-v1/persons.operations';
List<String> lines() => File(fixture).readAsLinesSync();
Map<String, dynamic> body() =>
    jsonDecode(lines().first) as Map<String, dynamic>;
String seal(Map<String, dynamic> record) {
  record.remove('contentHash');
  record.remove('referenceHash');
  final hash = sha256
      .convert(
        utf8.encode('tandemlog:operation:v1\n${canonicalDataJson(record)}'),
      )
      .toString();
  return canonicalDataJson({
    ...record,
    'contentHash': hash,
    'referenceHash': hash,
  });
}

void main() {
  test(
    'Python SHA256 current fixture is byte-exact including UTF-8 and predecessor chaining',
    () {
      expect(
        sha256.convert(File(fixture).readAsBytesSync()).toString(),
        '4c8c32877d15e520e510a8d96d4b38fb9cd16787f9a15c1875e010f3e52b741d',
      );
      final raw = lines(),
          first = LogEvent.decode(lines().first),
          second = LogEvent.decode(lines().last);
      expect(
        first.hash,
        '25a67b512527e909844484da57c0bdda5b3f4f03374aa88556b700b8a9a8ef5b',
      );
      expect(
        second.hash,
        'bcb71086bd14d5d96d5682657b928d388326361b9bdf236eedb962d483664e08',
      );
      expect(first.previousHash, '0' * 64);
      expect(second.previousHash, first.hash);
      expect(first.encode(), raw.first);
      expect(second.encode(), raw.last);
      expect(second.data['name'], 'Second ${String.fromCharCode(0x20ac)}');
      expect(
        LogEvent(
          space,
          writer,
          1,
          EventClock(BigInt.one),
          entity,
          'user.created',
          {'name': 'Example'},
        ).encode(previousHash: '0' * 64),
        raw.first,
      );
    },
  );
  test('recursive object keys sort while array order remains meaningful', () {
    expect(
      canonicalDataJson({
        'z': {'b': 2, 'a': 1},
        'a': [2, 1],
      }),
      '{"a":[2,1],"z":{"a":1,"b":2}}',
    );
    expect(
      canonicalDataJson({
        'a': [1, 2],
      }),
      isNot(
        canonicalDataJson({
          'a': [2, 1],
        }),
      ),
    );
  });
  test(
    'alternate spelling whitespace and duplicate fields cannot masquerade as canonical bytes',
    () {
      final raw = lines().first;
      for (final changed in [
        ' $raw',
        '$raw ',
        raw.replaceFirst('"name":"Example"', '"name": "Example"'),
        raw.replaceFirst('"clock":"1"', '"clock":"1","clock":"1"'),
        raw.replaceFirst('Example', '${String.fromCharCode(92)}u0045xample'),
      ]) {
        expect(
          () => LogEvent.decode(changed),
          throwsA(isA<FormatFailure>()),
          reason: changed,
        );
      }
    },
  );
  test('altering any current envelope field invalidates its retained hash', () {
    for (final key in [
      'space',
      'author',
      'subject',
      'predecessor',
      'clock',
      'value',
      'identity',
      'operation',
      'referenceHash',
      'contentHash',
    ]) {
      final record = body();
      switch (key) {
        case 'value':
          record[key] = {'name': 'Changed'};
        case 'identity':
          record[key] = {'writer': writer, 'sequence': 2};
        case 'operation':
          record[key] = {'family': 'person.create', 'revision': 2};
        case 'clock':
          record[key] = '2';
        case 'referenceHash':
          record[key] = 'invalid-hash';
        case 'contentHash':
          record[key] = 'f' * 64;
        case 'predecessor':
          record[key] = 'f' * 64;
        default:
          record[key] = '99999999-9999-4999-8999-999999999999';
      }
      expect(
        () => LogEvent.decode(canonicalDataJson(record)),
        throwsA(isA<FormatFailure>()),
        reason: key,
      );
    }
  });
  test(
    'unknown required family and revision fail closed even with independently recomputed hashes',
    () {
      for (final operation in [
        {'family': 'person.create', 'revision': 99},
        {'family': 'future.person', 'revision': 1},
      ]) {
        final record = body()..['operation'] = operation;
        expect(
          () => LogEvent.decode(seal(record)),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
  test(
    'closed required field sets reject extras and missing keys at every envelope level',
    () {
      for (final change in [0, 1, 2, 3]) {
        final record = body();
        if (change == 0) record['future'] = true;
        if (change == 1) record.remove('author');
        if (change == 2) (record['identity'] as Map)['future'] = true;
        if (change == 3) (record['operation'] as Map)['future'] = true;
        expect(
          () => LogEvent.decode(canonicalDataJson(record)),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
  test(
    'canonical numeric grammar accepts safe plain integers and rejects floats and unsafe integers',
    () {
      expect(
        canonicalDataJson([0, -1, 9007199254740991]),
        '[0,-1,9007199254740991]',
      );
      for (final value in [
        1.0,
        0.5,
        double.nan,
        double.infinity,
        9007199254740992,
      ]) {
        expect(() => canonicalDataJson(value), throwsFormatException);
      }
    },
  );
  test(
    'native and Task action input cannot add ignored fields or shadow current identity',
    () {
      for (final data in [
        {'name': 'Example', 'future': true},
        {
          'name': 'Example',
          'identity': {'writer': entity, 'sequence': 1},
        },
      ]) {
        expect(
          () => LogEvent(
            space,
            writer,
            1,
            EventClock(BigInt.one),
            entity,
            'user.created',
            data,
          ).encode(),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );
  test(
    'old v1 v2 and v3 fixture bytes remain explicit preserved failures in the app',
    () {
      final frozen = File(
        'test/fixtures/event_chain_v3.jsonl',
      ).readAsBytesSync();
      for (final raw in const LineSplitter().convert(utf8.decode(frozen))) {
        expect(() => LogEvent.decode(raw), throwsA(isA<FormatFailure>()));
        final j = jsonDecode(raw) as Map;
        for (final version in [1, 2]) {
          expect(
            () => LogEvent.decode(jsonEncode({...j, 'v': version})),
            throwsA(isA<FormatFailure>()),
          );
        }
      }
      expect(
        File('test/fixtures/event_chain_v3.jsonl').readAsBytesSync(),
        frozen,
      );
    },
  );
  test('UTF-8 byte budget rejects oversized input before interpretation', () {
    final raw = lines().first;
    final padding = String.fromCharCode(0x20ac) * (1024 * 1024 ~/ 3 + 1);
    expect(utf8.encode(padding + raw).length, greaterThan(1024 * 1024));
    expect(
      () => LogEvent.decode(padding + raw),
      throwsA(
        isA<FormatFailure>().having(
          (e) => e.message,
          'budget',
          contains('Oversized'),
        ),
      ),
    );
  });
}
