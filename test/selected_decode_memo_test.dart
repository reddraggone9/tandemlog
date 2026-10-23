import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_inheritance.dart';
import 'package:tandemlog/text/recurring_text.dart';

const space = '00000000-0000-4000-8000-000000000001';
const writer = '00000000-0000-4000-8000-000000000002';
const other = '00000000-0000-4000-8000-000000000003';
LogEvent event(
  String author,
  int sequence,
  int clock, {
  String name = 'Seed',
  String inSpace = space,
}) => LogEvent.decode(
  LogEvent(
    inSpace,
    author,
    sequence,
    EventClock(BigInt.from(clock)),
    other,
    'user.created',
    {'name': name},
  ).encode(previousHash: eventGenesisHash(inSpace, author)),
);
Map<String, dynamic> proof(LogEvent head) => {
  'codec': 'yrs-v1',
  'adapter': 1,
  'frontiers': {
    head.writer: {'seq': head.sequence, 'hash': head.hash},
  },
  'fields': {
    for (final field in ['title', 'description'])
      field: {
        'parentContext': 'a' * 64,
        'seedHash': 'b' * 64,
        'stateHash': 'c' * 64,
      },
  },
};
SelectedTextInheritanceIndex index(
  CanonicalTextRecordMemo memo,
  Iterable<LogEvent> records, {
  Map<String, String> heads = const {},
  Map<String, int> bounds = const {},
}) => SelectedTextInheritanceIndex.fromCanonical(
  records.map((e) => e.canonicalRaw!),
  heads,
  bounds,
  decodeMemo: memo,
);
void main() {
  final head = event(other, 1, 1), completion = event(writer, 2, 3);
  test(
    'exact frozen records are reused without reusing selected cut authority',
    () {
      final memo = CanonicalTextRecordMemo();
      final first = index(
        memo,
        [head],
        heads: {head.id: head.canonicalRaw!},
        bounds: {other: 1},
      );
      expect(
        first.verify(proof(head), completion: completion).isPending,
        isFalse,
      );
      final second = index(
        memo,
        [head],
        heads: {head.id: head.canonicalRaw!},
        bounds: {other: 1},
      );
      expect(
        second.verify(proof(head), completion: completion).isPending,
        isFalse,
      );
      expect(identical(first, second), isFalse);
      expect(identical(first.records.single, second.records.single), isTrue);
      expect(memo.decodes, 1);
      expect(second.decodedRecordCount, 0);
      expect(
        () => second.records.single.data['name'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            second
                    .verify(proof(head), completion: completion)
                    .frontiers[other] =
                8,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'cached head bytes cannot supply missing or decreased scope evidence',
    () {
      final memo = CanonicalTextRecordMemo();
      index(
        memo,
        [head],
        heads: {head.id: head.canonicalRaw!},
        bounds: {other: 1},
      ).verify(proof(head), completion: completion);
      expect(
        index(
          memo,
          [head],
          bounds: {other: 1},
        ).verify(proof(head), completion: completion).isPending,
        isTrue,
      );
      expect(
        index(
          memo,
          [head],
          heads: {head.id: head.canonicalRaw!},
          bounds: {other: 0},
        ).verify(proof(head), completion: completion).isPending,
        isTrue,
      );
    },
  );
  test(
    'changed valid raw decodes again and unchanged wrong head still rejects',
    () {
      final memo = CanonicalTextRecordMemo();
      final changed = event(other, 1, 1, name: 'Different');
      index(memo, [head]);
      final current = index(
        memo,
        [changed],
        heads: {head.id: head.canonicalRaw!},
        bounds: {other: 1},
      );
      expect(memo.decodes, 2);
      expect(
        () => current.verify(proof(changed), completion: completion),
        throwsA(isA<FormatFailure>()),
      );
      final broken = changed.canonicalRaw!.replaceFirst('Different', 'Broken');
      expect(
        () => SelectedTextInheritanceIndex.fromCanonical(
          [broken],
          {},
          {},
          decodeMemo: memo,
        ),
        throwsA(isA<FormatFailure>()),
      );
      expect(memo.entryCount, 2);
    },
  );
  test('cached foreign-space and forward-clock heads remain invalid', () {
    final memo = CanonicalTextRecordMemo();
    for (final invalid in [
      event(other, 1, 9),
      event(other, 1, 1, inSpace: '00000000-0000-4000-8000-000000000009'),
    ]) {
      index(memo, [invalid]);
      final current = index(
        memo,
        [],
        heads: {invalid.id: invalid.canonicalRaw!},
        bounds: {other: 1},
      );
      expect(
        () => current.verify(proof(invalid), completion: completion),
        throwsA(isA<FormatFailure>()),
      );
    }
  });
  test(
    'one shared raw payload and entry budget includes lazily decoded heads',
    () {
      final memo = CanonicalTextRecordMemo(maximumEntries: 2);
      final second = event(other, 2, 2), third = event(writer, 1, 1);
      index(memo, [head, second]);
      index(
        memo,
        [],
        heads: {third.id: third.canonicalRaw!},
        bounds: {writer: 1},
      ).verify(proof(third), completion: event(other, 3, 4));
      expect(memo.entryCount, 2);
      expect(
        memo.retainedRawPayloadBytes,
        lessThanOrEqualTo(memo.maximumRawPayloadBytes),
      );
      final before = memo.decodes;
      index(memo, [head]);
      expect(memo.decodes, before + 1);
    },
  );
  test('oversized payloads remain strict and uncached', () {
    final memo = CanonicalTextRecordMemo(
      maximumRawPayloadBytes: head.canonicalRaw!.length * 4 - 1,
    );
    index(memo, [head]);
    index(memo, [head]);
    expect(memo.entryCount, 0);
    expect(memo.retainedRawPayloadBytes, 0);
    expect(memo.decodes, 2);
  });
  test(
    'owning text memo clears decoded payload independently of live inputs',
    () {
      final memo = RecurringTextMemo();
      final input = RecurringTextInput.fromSelectedCanonical(
        [head.canonicalRaw!],
        {},
        {},
        memo: memo,
      );
      expect(memo.recordDecodeMemo.entryCount, 1);
      memo.clear();
      expect(memo.recordDecodeMemo.entryCount, 0);
      expect(input.history.single.data['name'], 'Seed');
    },
  );
}
