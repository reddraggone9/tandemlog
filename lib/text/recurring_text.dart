import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import '../domain/text_actor.dart';
import '../domain/text_context.dart';
import '../domain/text_inheritance.dart';
import 'native_text_engine.dart';

/// A declared canonical dependency has not arrived. This is distinct from a
/// known invalid proof, and must never cause a guessed replacement seed.
class TextInheritancePending implements Exception {
  const TextInheritancePending(this.message);
  final String message;
  @override
  String toString() => message;
}

class TextFieldSeed {
  const TextFieldSeed(this.context, this.update);
  final TextFieldContext context;
  final NativeTextUpdate update;
}

typedef LegacyTextRoots =
    Map<String, TextFieldSeed>? Function(
      String entity,
      List<LogEvent> observed,
    );

/// An original packet and its original authorship. Inheritance grants permission
/// to reuse the packet; it does not make its completing writer the author.
class LineageTextOperation {
  const LineageTextOperation(this.event, this.field, this.claim, this.update);
  final LogEvent event;
  final String field;
  final TextActorClaim claim;
  final NativeTextUpdate update;
}

class ResolvedTextField {
  ResolvedTextField({
    required this.context,
    required this.seed,
    required Iterable<LineageTextOperation> operations,
    required this.state,
    required this.text,
  }) : operations = List.unmodifiable(operations);
  final TextFieldContext context;
  final NativeTextUpdate seed;
  final List<LineageTextOperation> operations;
  final NativeTextState state;
  final String text;
  String get stateHash => sha256.convert(state.bytes).toString();
}

/// Resolves only immutable, admitted history. No receipt creation, writes,
/// timestamp rewriting, Undo execution or SQLite state is involved.
class RecurringTextResolver {
  factory RecurringTextResolver(
    NativeTextEngine engine,
    Iterable<LogEvent> history, {
    LegacyTextRoots? legacyRoots,
  }) {
    final records = <String, LogEvent>{};
    for (final supplied in history) {
      final raw = supplied.canonicalRaw;
      if (raw == null) {
        throw FormatFailure(
          'Text lineage requires admitted canonical records.',
        );
      }
      final event = LogEvent.decode(raw);
      final previous = records[event.id];
      if (previous != null && previous.canonicalRaw != raw) {
        throw FormatFailure('Conflicting text lineage records.');
      }
      records[event.id] = event;
    }
    final ordered = records.values.toList()..sort(compareEvents);
    return RecurringTextResolver._(
      engine,
      List.unmodifiable(ordered),
      legacyRoots,
      const {},
      {},
    );
  }

  RecurringTextResolver._(
    this.engine,
    this.history,
    this.legacyRoots,
    this.ancestors,
    this.observedFields,
  );
  final NativeTextEngine engine;
  final List<LogEvent> history;
  final LegacyTextRoots? legacyRoots;
  final Set<String> ancestors;
  // One immutable completion proof has one parent snapshot. Share it across
  // recursive prefixes so concurrent ancestors do not multiply replay work.
  final Map<String, Map<String, ResolvedTextField>> observedFields;
  final Map<String, Map<String, ResolvedTextField>> _resolved = {};

  Map<String, ResolvedTextField> resolve(String entity) {
    if (_resolved.containsKey(entity)) return _resolved[entity]!;
    if (ancestors.contains(entity)) {
      throw FormatFailure('Cyclic recurring text lineage.');
    }
    final own = history.where((event) => event.entity == entity).toList();
    final creations = own
        .where((event) => event.type == 'task.createdWithText')
        .toList();
    final contributions = history
        .where(
          (event) =>
              event.type == 'task.completedWithText' &&
              (event.data['successor'] as Map)['id'] == entity,
        )
        .toList();
    final roots = <String, TextFieldSeed>{};
    final packets = <String, Map<String, LineageTextOperation>>{
      'title': {},
      'description': {},
    };
    if (contributions.isNotEmpty) {
      if (own.any(
        (event) =>
            event.type == 'task.created' ||
            event.type == 'task.createdWithText' ||
            event.type == 'user.created',
      )) {
        throw FormatFailure(
          'Recurring text identity collides with a creation.',
        );
      }
      if (history.any(
        (event) =>
            event.type == 'task.completed' &&
            (event.data['successor'] as Map?)?['id'] == entity,
      )) {
        throw FormatFailure(
          'Mixed successor text initialization; history retained.',
        );
      }
      for (final completion in contributions) {
        if (const Uuid().v5(completion.entity, 'successor') != entity) {
          throw FormatFailure('Invalid recurring text identity.');
        }
        final proof = completion.data['inheritance'] as Map<String, dynamic>;
        final verified = verifyTextInheritance(
          proof,
          completion: completion,
          available: history,
        );
        if (verified.isPending) {
          throw TextInheritancePending(
            'Recurring text is waiting for its declared canonical history.',
          );
        }
        Map<String, ResolvedTextField> observed;
        try {
          observed = observedFields.putIfAbsent(
            completion.id,
            () => RecurringTextResolver._(
              engine,
              verified.observedPrefix,
              legacyRoots,
              {...ancestors, entity},
              observedFields,
            ).resolve(completion.entity),
          );
        } on TextInheritancePending {
          // Every declared head has arrived. This immutable observed prefix
          // cannot be repaired by events outside the completing writer's proof.
          throw FormatFailure(
            'Incomplete observed text proof in ${completion.id}.',
          );
        }
        final fields = proof['fields'] as Map;
        for (final field in ['title', 'description']) {
          final parent = observed[field]!;
          final declaration = fields[field] as Map;
          if (declaration['parentContext'] != parent.context.hash ||
              declaration['seedHash'] != parent.context.seedHash ||
              declaration['stateHash'] != parent.stateHash ||
              (completion.data['successor'] as Map)[field] != parent.text) {
            throw FormatFailure(
              'Observed parent text proof differs in ${completion.id}.',
            );
          }
          final context = TextFieldContext.successor(parent.context, entity);
          final prior = roots[field];
          if (prior != null &&
              (prior.context.hash != context.hash ||
                  prior.update.encoded != parent.seed.encoded)) {
            throw FormatFailure('Incompatible recurring text parent lineages.');
          }
          roots[field] = TextFieldSeed(context, parent.seed);
          // Contributions remain immutable even if completion is later undone.
          // Completion projection separately governs suppression of the child.
          for (final packet in parent.operations) {
            _include(packets[field]!, packet);
          }
        }
      }
    } else if (creations.isNotEmpty) {
      if (creations.length != 1) {
        throw FormatFailure('Duplicate native text creation.');
      }
      final creation = creations.single;
      for (final field in ['title', 'description']) {
        final seed = engine.seedText(creation.data[field] as String);
        final context = TextFieldContext.fromCreation(creation, field);
        if (sha256.convert(seed.bytes).toString() != context.seedHash) {
          throw FormatFailure('Native text creation seed differs.');
        }
        roots[field] = TextFieldSeed(context, seed);
      }
    } else {
      final legacy = legacyRoots?.call(entity, history);
      if (legacy == null ||
          legacy.keys.toSet().length != 2 ||
          !legacy.containsKey('title') ||
          !legacy.containsKey('description')) {
        throw FormatFailure('Observed history cannot establish its text root.');
      }
      roots.addAll(legacy);
    }
    for (final event in own) {
      if (event.type != 'task.textEdited' &&
          event.type != 'task.textEditUndone') {
        continue;
      }
      for (final entry in (event.data['changes'] as Map).entries) {
        final field = entry.key as String;
        final change = entry.value as Map;
        if (change['context'] != roots[field]!.context.hash) {
          throw FormatFailure('Native text context mismatch in ${event.id}.');
        }
        _include(
          packets[field]!,
          LineageTextOperation(
            event,
            field,
            TextActorClaim(
              context: change['context'] as String,
              writer: event.writer,
              allocation: change['allocation'] as String,
              actor: change['actor'] as int,
            ),
            NativeTextUpdate.parse(change['update']),
          ),
        );
      }
    }
    final result = <String, ResolvedTextField>{};
    for (final field in ['title', 'description']) {
      final root = roots[field]!;
      if (root.context.entity != entity ||
          root.context.field != field ||
          sha256.convert(root.update.bytes).toString() !=
              root.context.seedHash) {
        throw FormatFailure('Invalid verified text seed.');
      }
      final ordered = packets[field]!.values.toList()
        ..sort((a, b) => compareEvents(a.event, b.event));
      final registry = TextActorRegistry();
      final authors = <int, TextActorClaim>{};
      final document = engine.createDocument(
        actorClientId: 2,
        seed: root.update,
        limits: NativeTextLimits(visibleUtf16: field == 'title' ? 500 : 10000),
      );
      try {
        for (final packet in ordered) {
          registry.bindAll([packet.claim]);
          registry.validateStructActors(
            packet.claim,
            engine.inspect(packet.update),
          );
          final previous = authors[packet.claim.actor];
          if (previous != null && !previous.sameOwner(packet.claim)) {
            throw FormatFailure('Inherited native text actor collision.');
          }
          authors[packet.claim.actor] = packet.claim;
          document.applyRemote(packet.update);
        }
        final snapshot = document.read();
        if (snapshot.pending) {
          throw TextInheritancePending(
            'Recurring text is waiting for an inherited update dependency.',
          );
        }
        result[field] = ResolvedTextField(
          context: root.context,
          seed: root.update,
          operations: ordered,
          state: document.fullState,
          text: snapshot.text,
        );
      } finally {
        document.dispose();
      }
    }
    return _resolved[entity] = Map.unmodifiable(result);
  }
}

void _include(
  Map<String, LineageTextOperation> packets,
  LineageTextOperation incoming,
) {
  final previous = packets[incoming.event.id];
  if (previous != null &&
      (previous.update.encoded != incoming.update.encoded ||
          !previous.claim.sameOwner(incoming.claim))) {
    throw FormatFailure('Conflicting inherited text operation.');
  }
  packets[incoming.event.id] = incoming;
}
