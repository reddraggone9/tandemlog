import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import '../domain/text_actor.dart';
import '../domain/text_context.dart';
import '../domain/text_inheritance.dart';
import 'native_text_engine.dart';
import 'shared_text_history.dart';
import 'text_history_operation.dart';
export 'text_history_operation.dart';

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

class ResolvedTextField {
  ResolvedTextField({
    required this.context,
    required this.seed,
    required Iterable<LineageTextOperation> operations,
    required NativeTextState state,
    required this.text,
  }) : _operations = List.unmodifiable(operations),
       _state = state,
       historyReference = null,
       _runtime = null;
  ResolvedTextField._shared({
    required this.context,
    required this.seed,
    required this.historyReference,
    required this.text,
    required _RecurringHistoryRuntime runtime,
  }) : _runtime = runtime,
       _operations = null,
       _state = null;
  final TextFieldContext context;
  final NativeTextUpdate seed;
  final SharedTextReference? historyReference;
  final _RecurringHistoryRuntime? _runtime;
  final List<LineageTextOperation>? _operations;
  final NativeTextState? _state;
  Iterable<LineageTextOperation> get operations =>
      _operations ?? _runtime!.graph.operations(historyReference!);
  NativeTextState get state =>
      _state ?? _runtime!.state(context.field, historyReference!);
  final String text;
  String get stateHash => historyReference == null
      ? sha256.convert(state.bytes).toString()
      : _runtime!.snapshot(context.field, historyReference!).stateHash;
}

/// Original packets and admission claims are shared authority, rather than a
/// separate inherited list for each occurrence. Only disposable live native
/// documents/checkpoints are in the bounded replay pool. No editor owner enters
/// this runtime. Original context grants remain the resolver's responsibility.
class _RecurringHistoryRuntime {
  _RecurringHistoryRuntime(this.engine, this.deriveActor)
    : registry = TextActorRegistry(deriveActor: deriveActor);
  final NativeTextEngine engine;
  final TextActorDeriver? deriveActor;
  final graph = SharedTextHistoryGraph();
  final TextActorRegistry registry;
  final _admitted = <String>{};
  final _rootActors = <String, TextActorClaim>{};
  final _pools = <String, SharedTextMaterializer>{};
  bool _closed = false;
  int get packetApplications =>
      _pools.values.fold(0, (n, pool) => n + pool.packetApplications);
  SharedTextMaterializer _pool(String field) => _pools.putIfAbsent(
    field,
    () => SharedTextMaterializer(
      engine,
      limits: NativeTextLimits(visibleUtf16: field == 'title' ? 500 : 10000),
    ),
  );
  SharedTextReference append(
    SharedTextReference parent,
    LineageTextOperation packet,
  ) {
    final key =
        '${parent.rootContext}:${packet.event.space}:${packet.event.hash}:${packet.field}';
    final ownerKey = '${parent.rootContext}:${packet.claim.actor}';
    if (!_admitted.contains(key)) {
      registry.bindAll([packet.claim]);
      registry.validateStructActors(
        packet.claim,
        engine.inspect(packet.update),
      );
      final owner = _rootActors[ownerKey];
      if (owner != null && !owner.sameOwner(packet.claim)) {
        throw FormatFailure('Inherited native text actor collision.');
      }
    }
    final reference = graph.append(parent, packet);
    _rootActors[ownerKey] = packet.claim;
    _admitted.add(key);
    return reference;
  }

  SharedTextSnapshot snapshot(String field, SharedTextReference reference) {
    if (!_closed) return _pool(field).snapshot(reference);
    final temporary = SharedTextMaterializer(
      engine,
      limits: NativeTextLimits(visibleUtf16: field == 'title' ? 500 : 10000),
    );
    try {
      final snapshot = temporary.snapshot(reference);
      return SharedTextSnapshot(
        snapshot.text,
        snapshot.pending,
        snapshot.stateHash,
      );
    } finally {
      temporary.close();
    }
  }

  NativeTextState state(String field, SharedTextReference reference) {
    if (!_closed) return _pool(field).state(reference);
    final temporary = SharedTextMaterializer(
      engine,
      limits: NativeTextLimits(visibleUtf16: field == 'title' ? 500 : 10000),
    );
    try {
      return temporary.state(reference);
    } finally {
      temporary.close();
    }
  }

  void close() {
    for (final pool in _pools.values) {
      pool.close();
    }
    _pools.clear();
    _closed = true;
  }
}

/// Process-local reuse of fully verified immutable completion references.
/// The entry budget covers visible summaries and root/reference metadata.
/// Original authority is shared once in a graph; bounded native history pools
/// carry sparse disposable state separately, never editor/Undo ownership.
class RecurringTextMemo {
  RecurringTextMemo({
    this.maxEntries = 128,
    this.maxPayloadBytes = 16 * 1024 * 1024,
    this.maxRecords = 2048,
    this.maxRecordPayloadBytes = 16 * 1024 * 1024,
    this.maxActorDerivations = 2048,
  }) {
    if (maxEntries < 1 ||
        maxPayloadBytes < 1 ||
        maxRecords < 1 ||
        maxRecordPayloadBytes < 1 ||
        maxActorDerivations < 1) {
      throw ArgumentError('Invalid text memo budget.');
    }
  }
  final int maxEntries, maxPayloadBytes, maxRecords, maxRecordPayloadBytes;
  final int maxActorDerivations;
  final _entries = <String, _RememberedText>{};
  final _records = <String, LogEvent>{};
  final _actors = <(String, String, String), int>{};
  final _sharedPackets = <String, LineageTextOperation>{};
  final _packetUses = Map<LineageTextOperation, int>.identity();
  final _eventUses = Map<LogEvent, int>.identity();
  final _histories = <String, _RecurringHistoryRuntime>{};
  _RecurringHistoryRuntime _history(NativeTextEngine engine) =>
      _histories.putIfAbsent(
        engine.ownerId,
        () => _RecurringHistoryRuntime(engine, deriveActor),
      );
  int get sharedPacketCount =>
      _sharedPackets.length +
      _histories.values.fold(0, (n, history) => n + history.graph.packetCount);
  int get historyPacketApplications =>
      _histories.values.fold(0, (n, history) => n + history.packetApplications);

  String _packetKey(LineageTextOperation packet) =>
      '${packet.event.hash}:${packet.field}';

  LineageTextOperation _operation(
    LogEvent event,
    String field,
    TextActorClaim claim,
    Object? update,
  ) =>
      _sharedPackets['${event.hash}:$field'] ??
      LineageTextOperation(event, field, claim, NativeTextUpdate.parse(update));

  int _packetBytes(LineageTextOperation packet) =>
      packet.update.bytes.length +
      2 *
          (packet.claim.context.length +
              packet.claim.writer.length +
              packet.claim.allocation.length);
  int _eventBytes(LogEvent event) => event.canonicalRaw!.length * 4;

  int retainedPayloadBytes = 0, hits = 0, misses = 0;
  int retainedRecordPayloadBytes = 0, recordHits = 0, recordDecodes = 0;
  int get entryCount => _entries.length;
  int get recordCount => _records.length;
  int get actorDerivationCount => _actors.length;

  /// Reuse only the pure allocation hash. Registries still check contextual
  /// ownership/collisions on every admission. Valid identities have fixed
  /// lengths, so the entry cap also bounds retained key payload.
  int deriveActor(String context, String writer, String allocation) {
    final key = (context, writer, allocation);
    final remembered = _actors.remove(key);
    if (remembered != null) {
      _actors[key] = remembered;
      return remembered;
    }
    final actor = deriveTextActor(context, writer, allocation);
    if (_actors.length >= maxActorDerivations) {
      _actors.remove(_actors.keys.first);
    }
    _actors[key] = actor;
    return actor;
  }

  /// An exact canonical string is decoded and deeply frozen once. Changed raw
  /// bytes always undergo full validation; callers cannot mutate a cached event.
  LogEvent decodeCanonical(String raw) {
    final remembered = _records.remove(raw);
    if (remembered != null) {
      recordHits++;
      _records[raw] = remembered;
      return remembered;
    }
    final event = _freezeEvent(LogEvent.decode(raw));
    recordDecodes++;
    final bytes = raw.length * 4;
    if (bytes <= maxRecordPayloadBytes) {
      while (_records.isNotEmpty &&
          (_records.length >= maxRecords ||
              retainedRecordPayloadBytes + bytes > maxRecordPayloadBytes)) {
        final oldest = _records.keys.first;
        _records.remove(oldest);
        retainedRecordPayloadBytes -= oldest.length * 4;
      }
      _records[raw] = event;
      retainedRecordPayloadBytes += bytes;
    }
    return event;
  }

  void clear() {
    for (final runtime in _histories.values) {
      runtime.close();
    }
    _histories.clear();
    _entries.clear();
    _records.clear();
    _actors.clear();
    _sharedPackets.clear();
    _packetUses.clear();
    _eventUses.clear();
    retainedPayloadBytes = 0;
    retainedRecordPayloadBytes = 0;
  }

  Map<String, ResolvedTextField>? _get(String key) {
    final value = _entries.remove(key);
    if (value == null) {
      misses++;
      return null;
    }
    hits++;
    _entries[key] = value;
    return value.fields;
  }

  void _forget(String key) {
    final entry = _entries.remove(key)!;
    retainedPayloadBytes -= entry.bytes;
    for (final packet in entry.packets) {
      final uses = _packetUses[packet]! - 1;
      if (uses == 0) {
        _packetUses.remove(packet);
        _sharedPackets.remove(_packetKey(packet));
        retainedPayloadBytes -= _packetBytes(packet);
      } else {
        _packetUses[packet] = uses;
      }
    }
    for (final event in entry.events) {
      final uses = _eventUses[event]! - 1;
      if (uses == 0) {
        _eventUses.remove(event);
        retainedPayloadBytes -= _eventBytes(event);
      } else {
        _eventUses[event] = uses;
      }
    }
  }

  void _put(String key, Map<String, ResolvedTextField> fields) {
    final frozen = Map<String, ResolvedTextField>.unmodifiable(fields);
    var bytes = key.length * 2;
    final packets = Set<LineageTextOperation>.identity();
    final events = Set<LogEvent>.identity();
    for (final field in frozen.values) {
      if (field.historyReference != null) {
        // Keep one immutable reference and its visible summary. The authority
        // graph shares original packets; this entry retains no full-state BLOB,
        // flattened operation list or per-entry packet/event membership set.
        bytes +=
            field.seed.bytes.length +
            2 *
                (field.seed.encoded.length +
                    field.text.length +
                    field.historyReference!.hash.length);
        continue;
      }
      bytes +=
          field.seed.bytes.length +
          field.state.bytes.length +
          2 *
              (field.seed.encoded.length +
                  field.state.encoded.length +
                  field.text.length) +
          8 * field.operations.length;
      packets.addAll(field.operations);
      events.addAll(field.operations.map((packet) => packet.event));
    }
    // Inherited lists share immutable originals. Charge each retained packet
    // and canonical record once, rather than multiplying their payload by the
    // number of occurrences that reference them. Entry lists/state remain billed.
    int additional() =>
        bytes +
        packets
            .where((packet) => !_packetUses.containsKey(packet))
            .fold<int>(0, (n, packet) => n + _packetBytes(packet)) +
        events
            .where((event) => !_eventUses.containsKey(event))
            .fold<int>(0, (n, event) => n + _eventBytes(event));
    final alone =
        bytes +
        packets.fold(0, (n, packet) => n + _packetBytes(packet)) +
        events.fold(0, (n, event) => n + _eventBytes(event));
    if (alone > maxPayloadBytes) return;
    if (_entries.containsKey(key)) _forget(key);
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries ||
            retainedPayloadBytes + additional() > maxPayloadBytes)) {
      _forget(_entries.keys.first);
    }
    retainedPayloadBytes += additional();
    for (final packet in packets) {
      _packetUses[packet] = (_packetUses[packet] ?? 0) + 1;
      _sharedPackets[_packetKey(packet)] = packet;
    }
    for (final event in events) {
      _eventUses[event] = (_eventUses[event] ?? 0) + 1;
    }
    _entries[key] = _RememberedText(frozen, bytes, packets, events);
  }
}

class _RememberedText {
  _RememberedText(this.fields, this.bytes, this.packets, this.events);
  final Map<String, ResolvedTextField> fields;
  final int bytes;
  final Set<LineageTextOperation> packets;
  final Set<LogEvent> events;
}

Object? _freezeJson(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, item) => MapEntry(key, _freezeJson(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freezeJson)),
  _ => value,
};

LogEvent _freezeEvent(LogEvent event) => LogEvent(
  event.space,
  event.writer,
  event.sequence,
  event.clock,
  event.entity,
  event.type,
  _freezeJson(event.data) as Map<String, dynamic>,
  previousHash: event.previousHash,
  hash: event.hash,
  canonicalRaw: event.canonicalRaw,
);

/// Resolves only immutable, admitted history. No receipt creation, writes,
/// timestamp rewriting, Undo execution or SQLite state is involved.
class RecurringTextResolver {
  factory RecurringTextResolver(
    NativeTextEngine engine,
    Iterable<LogEvent> history, {
    LegacyTextRoots? legacyRoots,
    RecurringTextMemo? memo,
    String? legacyScope,
  }) {
    return RecurringTextResolver.fromCanonical(
      engine,
      history.map((supplied) {
        final raw = supplied.canonicalRaw;
        if (raw == null) {
          throw FormatFailure(
            'Text lineage requires admitted canonical records.',
          );
        }
        return raw;
      }),
      legacyRoots: legacyRoots,
      memo: memo,
      legacyScope: legacyScope,
    );
  }

  factory RecurringTextResolver.fromCanonical(
    NativeTextEngine engine,
    Iterable<String> history, {
    LegacyTextRoots? legacyRoots,
    RecurringTextMemo? memo,
    String? legacyScope,
  }) {
    if (memo != null && legacyRoots != null && legacyScope == null) {
      throw ArgumentError(
        'Memoized legacy roots require an immutable baseline scope.',
      );
    }
    final records = <String, LogEvent>{};
    for (final raw in history) {
      final event =
          memo?.decodeCanonical(raw) ?? _freezeEvent(LogEvent.decode(raw));
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
      memo,
      legacyScope,
      memo?._history(engine) ?? _RecurringHistoryRuntime(engine, null),
      memo == null,
    );
  }

  RecurringTextResolver._(
    this.engine,
    this.history,
    this.legacyRoots,
    this.ancestors,
    this.observedFields,
    this.memo,
    this.legacyScope,
    this._runtime,
    this._closeRuntime,
  );
  final NativeTextEngine engine;
  final List<LogEvent> history;
  final LegacyTextRoots? legacyRoots;
  final Set<String> ancestors;
  // One immutable completion proof has one parent snapshot. Share it across
  // recursive prefixes so concurrent ancestors do not multiply replay work.
  final Map<String, Map<String, ResolvedTextField>> observedFields;
  final RecurringTextMemo? memo;
  final String? legacyScope;
  final _RecurringHistoryRuntime _runtime;
  final bool _closeRuntime;
  final Map<String, Map<String, ResolvedTextField>> _resolved = {};

  Map<String, ResolvedTextField> resolve(String entity) {
    try {
      return _resolve(entity);
    } finally {
      if (_closeRuntime) _runtime.close();
    }
  }

  Map<String, ResolvedTextField> _resolve(String entity) {
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
    final inheritedReferences = <String, List<SharedTextReference>>{
      'title': [],
      'description': [],
    };
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
          observed = observedFields.putIfAbsent(completion.id, () {
            // The exact record set matters even when a declared head is
            // present: a sparse closed prefix must not reuse a fuller proof.
            final key =
                '${engine.ownerId}|${legacyScope ?? ''}|${completion.hash}|${sha256.convert(utf8.encode(verified.observedPrefix.map((event) => '${event.id}:${event.hash}\n').join()))}';
            final remembered = memo?._get(key);
            if (remembered != null) return remembered;
            final result = RecurringTextResolver._(
              engine,
              verified.observedPrefix,
              legacyRoots,
              {...ancestors, entity},
              observedFields,
              memo,
              legacyScope,
              _runtime,
              false,
            ).resolve(completion.entity);
            memo?._put(key, result);
            return result;
          });
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
              (proof['adapter'] == 1
                  ? declaration['stateHash'] != parent.stateHash
                  : declaration['historyHash'] !=
                        parent.historyReference!.hash) ||
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
          inheritedReferences[field]!.add(parent.historyReference!);
          // Contributions remain immutable even if completion is later undone.
          // Completion projection separately governs suppression of the child.
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
          (memo?._operation ?? _originalOperation)(
            event,
            field,
            TextActorClaim(
              context: change['context'] as String,
              writer: event.writer,
              allocation: change['allocation'] as String,
              actor: change['actor'] as int,
            ),
            change['update'],
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
      final parents = inheritedReferences[field]!;
      var reference = parents.isEmpty
          ? _runtime.graph.root(root.context.hash, root.update)
          : _runtime.graph.merge(parents);
      for (final packet in ordered) {
        reference = _runtime.append(reference, packet);
      }
      final snapshot = _runtime.snapshot(field, reference);
      if (snapshot.pending) {
        throw TextInheritancePending(
          'Recurring text is waiting for an inherited update dependency.',
        );
      }
      result[field] = ResolvedTextField._shared(
        context: root.context,
        seed: root.update,
        historyReference: reference,
        text: snapshot.text,
        runtime: _runtime,
      );
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

LineageTextOperation _originalOperation(
  LogEvent event,
  String field,
  TextActorClaim claim,
  Object? update,
) => LineageTextOperation(event, field, claim, NativeTextUpdate.parse(update));
