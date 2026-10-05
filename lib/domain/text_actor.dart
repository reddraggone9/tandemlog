import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'event.dart';

typedef TextActorDeriver =
    int Function(String context, String writer, String allocation);

/// Exact JSON-safe ID. Ownership is checked separately: a digest can collide.
int deriveTextActor(String context, String writer, String allocation) {
  if (!isEventHash(context) ||
      !isCanonicalId(writer) ||
      !isCanonicalId(allocation)) {
    throw FormatFailure('Invalid text actor identity.');
  }
  final bytes = utf8.encode(
    jsonEncode(['tandemlog.text.actor.v1', context, writer, allocation]),
  );
  final hash = sha256.convert(bytes).toString();
  return int.parse(hash.substring(0, 13), radix: 16) + 2;
}

class TextActorClaim {
  const TextActorClaim({
    required this.context,
    required this.writer,
    required this.allocation,
    required this.actor,
  });
  final String context, writer, allocation;
  final int actor;

  void validate() {
    if (!isEventHash(context) ||
        !isCanonicalId(writer) ||
        !isCanonicalId(allocation) ||
        actor < 2 ||
        actor > 9007199254740991) {
      throw FormatFailure('Invalid text actor ownership.');
    }
  }

  Map<String, dynamic> toJson() => {
    'context': context,
    'writer': writer,
    'allocation': allocation,
    'actor': actor,
  };

  factory TextActorClaim.fromJson(Map<String, dynamic> value) {
    if (value.length != 4 ||
        value['context'] is! String ||
        value['writer'] is! String ||
        value['allocation'] is! String ||
        value['actor'] is! int) {
      throw FormatFailure('Unsupported text actor ownership metadata.');
    }
    final claim = TextActorClaim(
      context: value['context'] as String,
      writer: value['writer'] as String,
      allocation: value['allocation'] as String,
      actor: value['actor'] as int,
    );
    claim.validate();
    return claim;
  }

  bool sameOwner(TextActorClaim other) =>
      context == other.context &&
      writer == other.writer &&
      allocation == other.allocation &&
      actor == other.actor;
}

/// Reconstruct this disposable index from canonical claims, never local counters.
/// A field context binds workspace, entity, field, initialization and codec.
class TextActorRegistry {
  TextActorRegistry({TextActorDeriver? deriveActor})
    : _derive = deriveActor ?? deriveTextActor;
  final TextActorDeriver _derive;
  final Map<String, TextActorClaim> _claims = {};
  String _key(TextActorClaim claim) => '${claim.context}:${claim.actor}';

  List<TextActorClaim> get claims => _claims.values.toList()
    ..sort((a, b) {
      final context = a.context.compareTo(b.context);
      return context != 0 ? context : a.actor.compareTo(b.actor);
    });

  void bindAll(Iterable<TextActorClaim> incoming) {
    // Validate a private delta before publishing it. Copying every prior claim
    // for each packet makes long inherited lineages quadratic, while a failed
    // batch must still leave this index unchanged.
    final next = <String, TextActorClaim>{};
    for (final claim in incoming) {
      claim.validate();
      final key = _key(claim);
      final previous = next[key] ?? _claims[key];
      if (previous != null && !previous.sameOwner(claim)) {
        throw FormatFailure(
          'Text actor ownership collision; records were retained.',
        );
      }
      if (previous == null) {
        if (_derive(claim.context, claim.writer, claim.allocation) !=
            claim.actor) {
          throw FormatFailure(
            'Text actor does not match its durable allocation.',
          );
        }
        next[key] = claim;
      }
    }
    _claims.addAll(next);
  }

  /// Ordinary operations may introduce only their owned structs. Deletion-set
  /// references name existing identities and are deliberately not struct authors.
  void validateStructActors(TextActorClaim claim, Iterable<int> actors) {
    claim.validate();
    final bound = _claims[_key(claim)];
    if (bound == null ||
        !bound.sameOwner(claim) ||
        actors.any((actor) => actor != claim.actor)) {
      throw FormatFailure(
        'Unowned native text struct actor; records were retained.',
      );
    }
  }
}
