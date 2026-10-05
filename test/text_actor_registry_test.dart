// Canonical actor ownership cases frozen before implementation.
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_actor.dart';

const writerA = '22222222-2222-4222-8222-222222222222';
const writerB = '33333333-3333-4333-8333-333333333333';
const allocationA = '44444444-4444-4444-8444-444444444444';
const allocationB = '55555555-5555-4555-8555-555555555555';
final context = 'a' * 64;

TextActorClaim claim(
  String allocation, {
  String writer = writerA,
  int? actor,
}) => TextActorClaim(
  context: context,
  writer: writer,
  allocation: allocation,
  actor: actor ?? deriveTextActor(context, writer, allocation),
);

void main() {
  test('TA01 durable actor derivation is exact, stable and context scoped', () {
    final actor = deriveTextActor(context, writerA, allocationA);
    expect(actor, inInclusiveRange(2, 9007199254740991));
    expect(deriveTextActor(context, writerA, allocationA), actor);
    expect(deriveTextActor('b' * 64, writerA, allocationA), isNot(actor));
    expect(deriveTextActor(context, writerB, allocationA), isNot(actor));
    expect(deriveTextActor(context, writerA, allocationB), isNot(actor));
    expect(
      TextActorClaim.fromJson(claim(allocationA).toJson()).toJson(),
      claim(allocationA).toJson(),
    );
  });

  test('TA02 reserved, unsafe, malformed and mismatched owners reject', () {
    for (final value in [1, 9007199254740992, -1]) {
      expect(
        () => TextActorRegistry().bindAll([claim(allocationA, actor: value)]),
        throwsA(isA<FormatFailure>()),
      );
    }
    expect(
      () => TextActorRegistry().bindAll([claim(allocationA, actor: 42)]),
      throwsA(isA<FormatFailure>()),
    );
    for (final data in [
      {...claim(allocationA).toJson(), 'writer': 'not-a-uuid'},
      {...claim(allocationA).toJson(), 'allocation': 'not-a-uuid'},
      {...claim(allocationA).toJson(), 'context': 'not-a-hash'},
      {...claim(allocationA).toJson(), 'actor': 2.0},
    ]) {
      expect(
        () => TextActorClaim.fromJson(data),
        throwsA(isA<FormatFailure>()),
      );
    }
  });

  test(
    'TA03 actual allocator collision retains first owner and rejects second',
    () {
      final registry = TextActorRegistry(deriveActor: (_, _, _) => 42);
      final first = claim(allocationA, actor: 42);
      final second = claim(allocationB, writer: writerB, actor: 42);
      registry.bindAll([first]);
      expect(
        () => registry.bindAll([second]),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('actor ownership collision'),
          ),
        ),
      );
      expect(registry.claims.map((c) => c.toJson()), [first.toJson()]);
      registry.bindAll([first]);
      expect(registry.claims, hasLength(1));
    },
  );

  test('TA04 multi-field admission is atomic when a later owner conflicts', () {
    final registry = TextActorRegistry(deriveActor: (_, _, _) => 42);
    expect(
      () => registry.bindAll([
        claim(allocationA, actor: 42),
        claim(allocationB, actor: 42),
      ]),
      throwsA(isA<FormatFailure>()),
    );
    expect(registry.claims, isEmpty);
  });

  test(
    'TA05 canonical-only ownership replay is duplicate/order independent',
    () {
      final a = claim(allocationA);
      final b = claim(allocationB);
      final first = TextActorRegistry()..bindAll([a, b, a]);
      final replay = TextActorRegistry()
        ..bindAll([
          TextActorClaim.fromJson(b.toJson()),
          TextActorClaim.fromJson(a.toJson()),
          TextActorClaim.fromJson(b.toJson()),
        ]);
      expect(
        replay.claims.map((c) => c.toJson()),
        first.claims.map((c) => c.toJson()),
      );
    },
  );

  test('TA06 operation struct authors must be the declared owner', () {
    final a = claim(allocationA);
    final b = claim(allocationB);
    final registry = TextActorRegistry()..bindAll([a, b]);
    registry.validateStructActors(a, [a.actor]);
    registry.validateStructActors(a, const []); // Delete-only operation.
    for (final actual in [
      [1],
      [b.actor],
      [a.actor, b.actor],
    ]) {
      expect(
        () => registry.validateStructActors(a, actual),
        throwsA(isA<FormatFailure>()),
      );
    }
    expect(registry.claims, hasLength(2));
  });

  test('TA07 separate documents do not conflate equal actor numbers', () {
    final registry = TextActorRegistry(deriveActor: (_, _, _) => 42);
    registry.bindAll([
      claim(allocationA, actor: 42),
      TextActorClaim(
        context: 'b' * 64,
        writer: writerA,
        allocation: allocationA,
        actor: 42,
      ),
    ]);
    expect(registry.claims, hasLength(2));
  });

  test('TA08 unknown ownership metadata fails explicitly', () {
    expect(
      () => TextActorClaim.fromJson({
        ...claim(allocationA).toJson(),
        'optionalOwnerOverride': writerB,
      }),
      throwsA(isA<FormatFailure>()),
    );
  });

  test('a failed delta preserves every previously bound owner', () {
    final registry = TextActorRegistry(deriveActor: (_, _, _) => 42);
    final first = claim(allocationA, actor: 42);
    registry.bindAll([first]);
    expect(
      () => registry.bindAll([
        TextActorClaim(
          context: 'b' * 64,
          writer: writerA,
          allocation: allocationA,
          actor: 42,
        ),
        claim(allocationB, actor: 42),
      ]),
      throwsA(isA<FormatFailure>()),
    );
    expect(registry.claims.map((entry) => entry.toJson()), [first.toJson()]);
  });
}
