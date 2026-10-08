import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_inheritance.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000002';
const other = '00000000-0000-4000-8000-000000000003';
LogEvent event(String author, int seq, int clock) => LogEvent.decode(
  LogEvent(
    space,
    author,
    seq,
    EventClock(BigInt.from(clock)),
    other,
    'user.created',
    {'name': 'Synthetic'},
  ).encode(previousHash: eventGenesisHash(space, author)),
);
Map<String, dynamic> proof(LogEvent head) => {
  'codec': 'yrs-v1',
  'adapter': 1,
  'frontiers': {
    head.writer: {'seq': head.sequence, 'hash': head.hash},
  },
  'fields': {
    for (final field in ['title', 'description'])
      field: <String, dynamic>{
        'parentContext': 'a' * 64,
        'seedHash': 'b' * 64,
        'stateHash': 'c' * 64,
      },
  },
};
void main() {
  final head = event(other, 1, 1), completion = event(writer, 2, 3);
  test(
    'strict descriptor rejects unknown keys, versions, fields and hashes',
    () {
      validateTextInheritance(proof(head));
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (p) => p['extra'] = true,
        (p) => p['adapter'] = 2,
        (p) => p['codec'] = 'unknown',
        (p) => (p['fields'] as Map).remove('description'),
        (p) => p['fields']['title']['extra'] = true,
        (p) => p['fields']['title']['parentContext'] = 'A' * 64,
        (p) => p['fields']['title']['seedHash'] = 'bad',
        (p) => p['fields']['title']['stateHash'] = null,
        (p) => p['frontiers'] = {},
        (p) => p['frontiers'][other]['seq'] = -1,
        (p) => p['frontiers'][other]['seq'] = 9007199254740992,
        (p) => p['frontiers'][other]['seq'] = 1.0,
        (p) => p['frontiers'][other]['extra'] = 1,
        (p) => p['frontiers'] = {
          'invalid': {'seq': 0, 'hash': 'a' * 64},
        },
      ]) {
        final p = proof(head);
        mutate(p);
        expect(() => validateTextInheritance(p), throwsA(isA<FormatFailure>()));
      }
    },
  );
  test('missing proof is pending while a known wrong hash is invalid', () {
    final p = proof(head);
    final pending = verifyTextInheritance(
      p,
      completion: completion,
      available: [],
    );
    expect(pending.isPending, isTrue);
    expect(pending.missingFrontiers, {'$other:1'});
    p['frontiers'][other]['hash'] = 'd' * 64;
    expect(
      () => verifyTextInheritance(p, completion: completion, available: [head]),
      throwsA(isA<FormatFailure>()),
    );
  });
  test('genesis is verified and does not require a record', () {
    final p = proof(head);
    p['frontiers'][other] = {'seq': 0, 'hash': eventGenesisHash(space, other)};
    expect(
      verifyTextInheritance(
        p,
        completion: completion,
        available: [head],
      ).observedPrefix,
      isEmpty,
    );
    p['frontiers'][other]['hash'] = 'd' * 64;
    expect(
      () => verifyTextInheritance(p, completion: completion, available: []),
      throwsA(isA<FormatFailure>()),
    );
  });
  test(
    'forward clock and same writer references are rejected even missing',
    () {
      final future = event(other, 1, 3);
      expect(
        () => verifyTextInheritance(
          proof(future),
          completion: completion,
          available: [future],
        ),
        throwsA(isA<FormatFailure>()),
      );
      final own = event(writer, 2, 1);
      expect(
        () => verifyTextInheritance(
          proof(own),
          completion: completion,
          available: [],
        ),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test('duplicate reordered arrival filters immutable observed prefix', () {
    final p = proof(head), before = jsonEncode(proof(head));
    final later = event(other, 2, 2), unrelated = event(writer, 1, 1);
    final input = [later, head, unrelated, head];
    final result = verifyTextInheritance(
      p,
      completion: completion,
      available: input,
    );
    expect(result.isPending, isFalse);
    expect(result.observedPrefix.map((e) => e.id), [head.id]);
    expect(jsonEncode(p), before);
    expect(input, [later, head, unrelated, head]);
    expect(() => result.observedPrefix.clear(), throwsUnsupportedError);
  });
}
