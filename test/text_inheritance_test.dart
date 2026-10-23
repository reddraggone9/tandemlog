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

  test(
    'shared index preserves sparse prefixes, ordering and last duplicate',
    () {
      final first = event(other, 1, 1), last = event(other, 2, 2);
      final end = event(writer, 3, 4);
      final same = LogEvent(
        first.space,
        first.writer,
        first.sequence,
        first.clock,
        first.entity,
        first.type,
        first.data,
        previousHash: first.previousHash,
        hash: first.hash,
        canonicalRaw: first.canonicalRaw,
      );
      final available = [last, first, same];
      final index = TextInheritanceIndex(available);
      available.clear();
      for (final declared in [proof(first), proof(last), proof(first)]) {
        final expected = verifyTextInheritance(
          declared,
          completion: end,
          available: [last, first, same],
        );
        final actual = index.verify(declared, completion: end);
        expect(actual.missingFrontiers, expected.missingFrontiers);
        expect(actual.observedPrefix, expected.observedPrefix);
        expect(identical(actual.observedPrefix.first, same), isTrue);
      }
      final sparse = TextInheritanceIndex([
        last,
      ]).verify(proof(last), completion: end);
      expect(sparse.isPending, isFalse);
      expect(sparse.observedPrefix.map((e) => e.id), [last.id]);
      expect(
        index
            .verify(proof(last), completion: end)
            .observedPrefix
            .map((e) => e.id),
        [first.id, last.id],
      );
      final wrong = proof(last)..['frontiers'][other]['hash'] = 'd' * 64;
      expect(
        () => index.verify(wrong, completion: end),
        throwsA(isA<FormatFailure>()),
      );
      final future = event(other, 2, 4);
      expect(
        () => TextInheritanceIndex([
          first,
          future,
        ]).verify(proof(future), completion: end),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'shared index defers foreign conflicts until that workspace is verified',
    () {
      const foreignSpace = '00000000-0000-4000-8000-000000000004';
      LogEvent foreign(String name, int seq, int clock) => LogEvent.decode(
        LogEvent(
          foreignSpace,
          other,
          seq,
          EventClock(BigInt.from(clock)),
          other,
          'user.created',
          {'name': name},
        ).encode(previousHash: eventGenesisHash(foreignSpace, other)),
      );
      final foreignA = foreign('A', 1, 1), foreignB = foreign('B', 1, 1);
      final index = TextInheritanceIndex([foreignA, head, foreignB]);
      expect(index.verify(proof(head), completion: completion).observedPrefix, [
        head,
      ]);
      expect(
        () => index.verify(
          proof(foreignA),
          completion: foreign('Completion', 2, 3),
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(index.verify(proof(head), completion: completion).observedPrefix, [
        head,
      ]);
      final invalid = proof(head)..['extra'] = true;
      expect(
        () => index.verify(invalid, completion: completion),
        throwsA(isA<FormatFailure>()),
      );
    },
  );
  test(
    'successful cut identity survives only append outside every declared cut',
    () {
      final first = event(other, 1, 1);
      final completion = event(writer, 4, 10);
      final descriptor = proof(first);
      final base = TextInheritanceIndex([first]);
      final verified = base.verify(descriptor, completion: completion);
      expect(base.verify(descriptor, completion: completion), same(verified));
      expect(base.verifiedCutHits, 1);
      final next = TextInheritanceIndex.appended(base, [event(other, 2, 11)]);
      expect(next.verify(descriptor, completion: completion), same(verified));
      expect(next.verifiedCutHits, 1);
      final changed =
          jsonDecode(jsonEncode(descriptor)) as Map<String, dynamic>;
      changed['frontiers'][other]['hash'] = 'd' * 64;
      expect(
        () => next.verify(changed, completion: completion),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'pending and sparse-cut delivery never inherit a stale verification',
    () {
      final first = event(other, 1, 1), head = event(other, 3, 3);
      final completion = event(writer, 4, 10), descriptor = proof(head);
      final missing = TextInheritanceIndex([first]);
      expect(
        missing.verify(descriptor, completion: completion).isPending,
        isTrue,
      );
      expect(missing.cachedCutCount, 0);
      final sparse = TextInheritanceIndex.appended(missing, [head]);
      final old = sparse.verify(descriptor, completion: completion);
      expect(old.observedPrefix.map((event) => event.sequence), [1, 3]);
      final filled = TextInheritanceIndex.appended(sparse, [
        event(other, 2, 2),
      ]);
      final current = filled.verify(descriptor, completion: completion);
      expect(identical(current, old), isFalse);
      expect(current.observedPrefix.map((event) => event.sequence), [1, 2, 3]);
      expect(old.observedPrefix.map((event) => event.sequence), [1, 3]);
    },
  );

  test(
    'cut reuse budgets total prefix references and eviction falls back safely',
    () {
      final available = [
        for (var seq = 1; seq <= 1100; seq++) event(other, seq, seq),
      ];
      final index = TextInheritanceIndex(available);
      final descriptor = proof(available.last);
      final firstCompletion = event(writer, 1, 2000);
      final first = index.verify(descriptor, completion: firstCompletion);
      for (var seq = 2; seq <= 140; seq++) {
        index.verify(descriptor, completion: event(writer, seq, 2000 + seq));
        expect(
          index.retainedCutBytes,
          lessThanOrEqualTo(TextInheritanceIndex.maximumCachedCutBytes),
        );
        expect(
          index.cachedCutCount,
          lessThanOrEqualTo(TextInheritanceIndex.maximumCachedCuts),
        );
      }
      expect(index.cachedCutCount, lessThan(128));
      final again = index.verify(descriptor, completion: firstCompletion);
      expect(identical(again, first), isFalse);
      expect(
        again.observedPrefix.map((event) => event.canonicalRaw),
        first.observedPrefix.map((event) => event.canonicalRaw),
      );
    },
  );
}
