import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/text/recurring_text.dart';

const space = '00000000-0000-4000-8000-000000000001';
const author = '00000000-0000-4000-8000-000000000002';
const peer = '00000000-0000-4000-8000-000000000003';
String raw(String writer, int seq, int clock, [String name = 'Synthetic']) =>
    LogEvent(
      space,
      writer,
      seq,
      EventClock(BigInt.from(clock)),
      peer,
      'user.created',
      {'name': name},
    ).encode(previousHash: eventGenesisHash(space, writer));

void main() {
  test(
    'strict frozen input preserves canonical order and duplicate semantics',
    () {
      final first = raw(author, 1, 1), last = raw(author, 2, 2);
      final input = RecurringTextInput.fromCanonical([last, first, first]);
      expect(input.history.map((event) => event.sequence), [1, 2]);
      expect(input.history.map((event) => event.canonicalRaw), [first, last]);
      expect(() => input.history.clear(), throwsUnsupportedError);
      expect(
        () => input.history.first.data['name'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => RecurringTextInput.fromCanonical([
          first,
          raw(author, 1, 1, 'Different'),
        ]),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test('append decodes only delta and never mutates the original input', () {
    final memo = RecurringTextMemo();
    final input = RecurringTextInput.fromCanonical([
      raw(author, 1, 1),
    ], memo: memo);
    final decoded = memo.recordDecodes;
    final next = input.appendedCanonical([raw(author, 2, 2)], memo: memo)!;
    expect(memo.recordDecodes, decoded + 1);
    expect(input.history.map((event) => event.sequence), [1]);
    expect(next.history.map((event) => event.sequence), [1, 2]);
    expect(identical(input.history.first, next.history.first), isTrue);
    expect(input.containsCanonical(input.history.first), isTrue);
    expect(next.containsCanonical(input.history.first), isTrue);
    expect(input.containsCanonical(next.history.last), isFalse);
    final conflicting = LogEvent.decode(raw(author, 1, 1, 'Different'));
    expect(input.containsCanonical(conflicting), isFalse);
    // A public DTO can lie about its ID. It cannot hide a different raw record.
    final forged = LogEvent(
      space,
      author,
      1,
      EventClock(BigInt.one),
      peer,
      'user.created',
      {'name': 'Synthetic'},
      canonicalRaw: raw(author, 2, 2),
    );
    expect(input.containsCanonical(forged), isFalse);
    expect(next.cacheable, isTrue);
    memo.clear();
  });

  test(
    'interior, reordered, duplicate and conflicting inputs require rebuild',
    () {
      final input = RecurringTextInput.fromCanonical([
        raw(author, 1, 1),
        raw(author, 3, 3),
      ]);
      expect(input.appendedCanonical([raw(author, 2, 2)]), isNull);
      expect(input.appendedCanonical([raw(peer, 1, 2)]), isNull);
      expect(input.appendedCanonical([raw(author, 3, 3)]), isNull);
      expect(input.appendedCanonical([raw(author, 3, 3, 'Different')]), isNull);
      expect(
        () => input.appendedCanonical(['{}']),
        throwsA(isA<FormatFailure>()),
      );
      final rebuilt = RecurringTextInput.fromCanonical([
        ...input.history.map((event) => event.canonicalRaw!),
        raw(author, 2, 2),
      ]);
      expect(rebuilt.history.map((event) => event.sequence), [1, 2, 3]);
    },
  );

  test(
    'large inputs remain usable but are excluded from retained store cache',
    () {
      final input = RecurringTextInput.fromCanonical([
        for (var seq = 1; seq <= 4097; seq++) raw(author, seq, seq),
      ]);
      expect(input.history.length, 4097);
      expect(input.cacheable, isFalse);
    },
  );
}
