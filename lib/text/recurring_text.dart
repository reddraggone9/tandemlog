import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import '../domain/text_actor.dart';
import '../domain/text_context.dart';
import '../domain/checklist.dart';
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

final class ResolvedTextField {
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
    if (_closed) return;
    final pools = _pools.values.toList();
    _pools.clear();
    _closed = true;
    Object? failure;
    StackTrace? failureStack;
    for (final pool in pools) {
      try {
        pool.close();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
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
    this.maxRecords = 4096,
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
    _rememberRecord(raw, event);
    return event;
  }

  void _rememberRecord(String raw, LogEvent event) {
    final bytes = raw.length * 4;
    if (_records.remove(raw) != null) retainedRecordPayloadBytes -= bytes;
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
  }

  // An eager scan retains the bounded starting entries until this one batch
  // finishes. Early misses cannot evict later hits in the SAME immutable input.
  // This avoids the all-miss LRU cliff when history slightly exceeds the cap.
  // Only frozen exact-raw decodes are reused; new bytes always decode below.
  List<LogEvent> _decodeCanonicalBatch(Iterable<String> raws) {
    final previous = Map<String, LogEvent>.of(_records);
    final decoded = <LogEvent>[];
    for (final raw in raws) {
      final remembered = previous[raw];
      if (remembered != null) {
        recordHits++;
        _rememberRecord(raw, remembered);
        decoded.add(remembered);
      } else {
        decoded.add(decodeCanonical(raw));
      }
    }
    return decoded;
  }

  void clear() {
    final histories = _histories.values.toList();
    _histories.clear();
    _entries.clear();
    _records.clear();
    _actors.clear();
    _sharedPackets.clear();
    _packetUses.clear();
    _eventUses.clear();
    retainedPayloadBytes = 0;
    retainedRecordPayloadBytes = 0;
    Object? failure;
    StackTrace? failureStack;
    for (final runtime in histories) {
      try {
        runtime.close();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  String _checklistCutKey(
    NativeTextEngine engine,
    String baselineScope,
    LogEvent completion,
  ) {
    if (completion.hash == null || completion.integrityHash == null) {
      throw StateError('Checklist memo evidence must be strictly canonical.');
    }
    return 'checklist-cut-v1:${jsonEncode([engine.ownerId, baselineScope, completion.hash, completion.integrityHash])}';
  }

  // The strict input owns the verification identity; callers cannot supply an
  // arbitrary receipt to bypass the public list API's complete pair comparison.
  bool hasVerifiedChecklistInputCut(
    NativeTextEngine engine,
    String baselineScope,
    LogEvent completion,
    RecurringTextInput input,
    Map<String, dynamic> descriptor,
  ) {
    final verified = input.verifyInheritance(
      descriptor,
      completion: completion,
    );
    return !verified.isPending &&
        _get(
              _checklistCutKey(engine, baselineScope, completion),
              verified.recordsForResolution,
              verification: verified,
            ) !=
            null;
  }

  void rememberVerifiedChecklistInputCut(
    NativeTextEngine engine,
    String baselineScope,
    LogEvent completion,
    RecurringTextInput input,
    Map<String, dynamic> descriptor,
  ) {
    final verified = input.verifyInheritance(
      descriptor,
      completion: completion,
    );
    if (verified.isPending) throw StateError('Cannot remember a pending cut.');
    _put(
      _checklistCutKey(engine, baselineScope, completion),
      const {},
      verified.recordsForResolution,
      verification: verified,
    );
  }

  /// Cache only caller-verified membership/order/native-parent predicates.
  /// TaskStore owns its memo privately; this does not validate a completion.
  bool hasVerifiedChecklistCut(
    NativeTextEngine engine,
    String baselineScope,
    LogEvent completion,
    List<LogEvent> verifiedPrefix,
  ) =>
      _get(
        _checklistCutKey(engine, baselineScope, completion),
        verifiedPrefix,
      ) !=
      null;

  void rememberVerifiedChecklistCut(
    NativeTextEngine engine,
    String baselineScope,
    LogEvent completion,
    List<LogEvent> verifiedPrefix,
  ) => _put(
    _checklistCutKey(engine, baselineScope, completion),
    const {},
    verifiedPrefix,
  );

  Map<String, ResolvedTextField>? _get(
    String key,
    List<LogEvent> observedPrefix, {
    TextResolutionCut? verification,
  }) {
    final value = _entries[key];
    if (value == null || value.prefix.length != observedPrefix.length) {
      misses++;
      return null;
    }
    // Strict canonical decoding binds every body field with integrityHash and
    // its independent retained anchor with hash. Compare the ENTIRE freshly
    // verified ordered prefix, including unrelated and sparse interior records.
    final identicalVerifiedCut =
        verification != null &&
        identical(verification.recordsForResolution, observedPrefix) &&
        identical(value.verification?.target, verification);
    // A selected dependency set is not a complete generic prefix. Its memo
    // evidence can only be reused within the exact verified immutable cut.
    if (!identicalVerifiedCut &&
        (verification is SelectedTextInheritanceCut || value.selectedCut)) {
      misses++;
      return null;
    }
    for (var i = 0; !identicalVerifiedCut && i < observedPrefix.length; i++) {
      final event = observedPrefix[i];
      final reference = event.hash, content = event.integrityHash;
      if (reference == null || content == null) {
        throw StateError('Observed memo evidence must be strictly canonical.');
      }
      if (value.prefix[i].$1 != reference || value.prefix[i].$2 != content) {
        misses++;
        return null;
      }
    }
    hits++;
    _entries.remove(key);
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

  void _put(
    String key,
    Map<String, ResolvedTextField> fields,
    List<LogEvent> observedPrefix, {
    TextResolutionCut? verification,
  }) {
    if (verification != null &&
        (!identical(verification.recordsForResolution, observedPrefix) ||
            verification.isPending)) {
      throw StateError('Memo receipt must be the exact successful cut.');
    }
    // Reject malformed evidence before eviction or accounting mutation.
    for (final event in observedPrefix) {
      if (event.hash == null || event.integrityHash == null) {
        throw StateError('Observed memo evidence must be strictly canonical.');
      }
    }
    final frozen = Map<String, ResolvedTextField>.unmodifiable(fields);
    // Charge both 64-character hash strings, tuple/list references and
    // conservative metadata per record. No full input event/raw is retained.
    var bytes = key.length * 2 + observedPrefix.length * 320 + 64;
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
    final prefix = List<(String, String)>.unmodifiable([
      for (final event in observedPrefix)
        (
          event.hash ??
              (throw StateError('Observed reference hash is required.')),
          event.integrityHash ??
              (throw StateError('Observed content hash is required.')),
        ),
    ]);
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
    _entries[key] = _RememberedText(
      frozen,
      bytes,
      packets,
      events,
      prefix,
      verification == null ? null : WeakReference(verification),
      verification is SelectedTextInheritanceCut,
    );
  }
}

class _RememberedText {
  _RememberedText(
    this.fields,
    this.bytes,
    this.packets,
    this.events,
    this.prefix,
    this.verification,
    this.selectedCut,
  );
  final WeakReference<TextResolutionCut>? verification;
  // Mode outlives the weak receipt: GC can never turn a selected dependency
  // result into evidence for a generic complete-prefix caller.
  final bool selectedCut;
  final Map<String, ResolvedTextField> fields;
  final int bytes;
  final Set<LineageTextOperation> packets;
  final Set<LogEvent> events;
  final List<(String, String)> prefix;
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
  attributedWriter: event.attributedWriter,
  integrityHash: event.integrityHash,
  operationRevision: event.operationRevision,
);

/// Resolver-local references into one strictly decoded immutable input. This
/// avoids scanning every unrelated record for each entity. Observed-prefix
/// subresolvers build their own lookup; no candidate or proof crosses a prefix.
/// The extra references scale with input records and declared copied items.
class _RecurringHistoryLookup {
  _RecurringHistoryLookup(List<LogEvent> history) {
    for (final event in history) {
      (own[event.entity] ??= []).add(event);
      if (event.type == 'checklist.itemCreated') {
        (checklistParents[event.data['parent'] as String] ??= []).add(event);
      } else if (event.type == 'task.completedWithChecklist') {
        final parent = (event.data['successor'] as Map)['id'] as String;
        (checklistParents[parent] ??= []).add(event);
      }
      if (event.type == 'task.operationUndone' ||
          event.type == 'task.textEditUndone' ||
          event.type == 'task.recurringCompletionUndone') {
        final target =
            event.data[event.type == 'task.recurringCompletionUndone'
                    ? 'completion'
                    : 'operation']
                as String;
        (retractions[target] ??= []).add(event);
      }
      final children = <String>{};
      if (hasNativeTaskSuccessor(event)) {
        children.add((event.data['successor'] as Map)['id'] as String);
      }
      // Scalar parents can still copy native checklist fields.
      if (event.type == 'task.completedWithChecklist') {
        for (final item in (event.data['checklist'] as Map)['items'] as List) {
          children.add((item as Map)['id'] as String);
        }
      }
      for (final child in children) {
        (contributionCandidates[child] ??= []).add(event);
      }
      if (isScalarSuccessorInitialization(event)) {
        final child = (event.data['successor'] as Map?)?['id'];
        if (child is String) scalarSuccessors.add(child);
      }
    }
  }

  _RecurringHistoryLookup.appended(
    _RecurringHistoryLookup prior,
    List<LogEvent> added,
  ) {
    own.addAll(prior.own);
    contributionCandidates.addAll(prior.contributionCandidates);
    scalarSuccessors.addAll(prior.scalarSuccessors);
    checklistParents.addAll(prior.checklistParents);
    retractions.addAll(prior.retractions);
    final delta = _RecurringHistoryLookup(added);
    for (final entry in delta.own.entries) {
      own[entry.key] = List.unmodifiable([...?own[entry.key], ...entry.value]);
    }
    for (final entry in delta.contributionCandidates.entries) {
      contributionCandidates[entry.key] = List.unmodifiable([
        ...?contributionCandidates[entry.key],
        ...entry.value,
      ]);
    }
    scalarSuccessors.addAll(delta.scalarSuccessors);
    for (final entry in delta.checklistParents.entries) {
      checklistParents[entry.key] = List.unmodifiable([
        ...?checklistParents[entry.key],
        ...entry.value,
      ]);
    }
    for (final entry in delta.retractions.entries) {
      retractions[entry.key] = List.unmodifiable([
        ...?retractions[entry.key],
        ...entry.value,
      ]);
    }
  }

  // Membership uses the same pure domain projector, with every relevant own
  // record, copy seed and retraction (including malformed cross-entity Undo).
  // Unrelated Tasks and their Notes cannot affect this parent's checklist.
  List<LogEvent> checklistHistory(String parent) {
    final selected = <String, LogEvent>{};
    final ids = <String>{};
    for (final event in checklistParents[parent] ?? const <LogEvent>[]) {
      selected[event.id] = event;
      if (event.type == 'checklist.itemCreated') {
        ids.add(event.entity);
      } else {
        for (final item in (event.data['checklist'] as Map)['items'] as List) {
          ids.add((item as Map)['id'] as String);
        }
      }
    }
    for (final id in ids) {
      for (final event in own[id] ?? const <LogEvent>[]) {
        selected[event.id] = event;
      }
    }
    for (final id in selected.keys.toList()) {
      for (final event in retractions[id] ?? const <LogEvent>[]) {
        selected[event.id] = event;
      }
    }
    return selected.values.toList();
  }

  final checklistParents = <String, List<LogEvent>>{};
  final retractions = <String, List<LogEvent>>{};
  final own = <String, List<LogEvent>>{};
  final contributionCandidates = <String, List<LogEvent>>{};
  final scalarSuccessors = <String>{};
}

/// Pure immutable canonical input, shared by resolvers without sharing native
/// handles, actor admission or resolved fields. Store retention is bounded.
final class RecurringTextInput {
  RecurringTextInput._(
    this.history,
    this._records,
    this._heads,
    this._inheritanceIndex,
    this.rawCost, [
    this._lookupCache,
    this._previous,
    this._selectedIndex,
  ]);
  factory RecurringTextInput.fromCanonical(
    Iterable<String> history, {
    RecurringTextMemo? memo,
  }) {
    final records = <String, LogEvent>{};
    final decoded =
        memo?._decodeCanonicalBatch(history) ??
        history.map((raw) => _freezeEvent(LogEvent.decode(raw)));
    for (final event in decoded) {
      final previous = records[event.id];
      if (previous != null && previous.canonicalRaw != event.canonicalRaw) {
        throw FormatFailure('Conflicting text lineage records.');
      }
      records[event.id] = event;
    }
    final ordered = records.values.toList()..sort(compareEvents);
    return RecurringTextInput._fromEvents(List.unmodifiable(ordered));
  }
  factory RecurringTextInput._fromEvents(List<LogEvent> events) {
    final records = <String, LogEvent>{}, heads = <String, int>{};
    var cost = 0;
    for (final event in events) {
      records[event.id] = event;
      final writer = '${event.space}:${event.writer}';
      if (event.sequence > (heads[writer] ?? 0)) heads[writer] = event.sequence;
      cost += event.canonicalRaw!.length * 4;
    }
    return RecurringTextInput._(
      events,
      Map.unmodifiable(records),
      Map.unmodifiable(heads),
      TextInheritanceIndex(events),
      cost,
    );
  }
  final List<LogEvent> history;
  final Map<String, LogEvent> _records;
  final Map<String, int> _heads;
  final TextInheritanceIndex _inheritanceIndex;
  final SelectedTextInheritanceIndex? _selectedIndex;

  /// A dependency selection has distinct cut semantics. This never supplies a
  /// complete-prefix receipt to the generic list oracle or its cross-call memo.
  factory RecurringTextInput.fromSelectedCanonical(
    Iterable<String> records,
    Map<String, String> heads,
    Map<String, int> availableSequences,
  ) => RecurringTextInput._fromSelectedIndex(
    SelectedTextInheritanceIndex.fromCanonical(
      records,
      heads,
      availableSequences,
    ),
  );

  factory RecurringTextInput._fromSelectedIndex(
    SelectedTextInheritanceIndex index,
  ) {
    final input = RecurringTextInput._fromEvents(index.records);
    return RecurringTextInput._(
      input.history,
      input._records,
      input._heads,
      input._inheritanceIndex,
      input.rawCost,
      null,
      null,
      index,
    );
  }
  bool get isSelected => _selectedIndex != null;
  int get selectedDecodedRecordCount => _selectedIndex?.decodedRecordCount ?? 0;

  RecurringTextInput _forVerifiedCut(TextResolutionCut cut) => switch (cut) {
    TextInheritanceVerification() => _forPrefix(cut.observedPrefix),
    SelectedTextInheritanceCut() => RecurringTextInput._fromSelectedIndex(
      _selectedIndex!.forCut(cut),
    ),
  };
  final int rawCost;
  final RecurringTextInput? _previous;
  _RecurringHistoryLookup? _lookupCache;
  _RecurringHistoryLookup get _lookup =>
      _lookupCache ??= _RecurringHistoryLookup(history);
  bool get cacheable =>
      !isSelected && history.length <= 4096 && rawCost <= 16 * 1024 * 1024;

  RecurringTextInput? appendedCanonical(
    Iterable<String> raw, {
    RecurringTextMemo? memo,
  }) {
    // A preparation overlay does not advance this owning committed cut's
    // available heads. Only actual inserted candidate SQL may do that.
    if (_selectedIndex != null) {
      final values = raw.toList();
      final records = {..._records};
      for (final value in values) {
        final event = _freezeEvent(LogEvent.decode(value));
        final old = records[event.id];
        if (old != null && old.canonicalRaw != event.canonicalRaw) return null;
        records[event.id] = event;
      }
      return RecurringTextInput.fromSelectedCanonical(
        records.values.map((e) => e.canonicalRaw!),
        _selectedIndex.headRaws,
        _selectedIndex.availableSequences,
      );
    }
    final added =
        (memo?._decodeCanonicalBatch(raw) ??
                raw.map((raw) => _freezeEvent(LogEvent.decode(raw))))
            .toList()
          ..sort(compareEvents);
    if (added.isEmpty) return this;
    final heads = Map<String, int>.of(_heads);
    var cost = rawCost;
    final newIds = <String>{};
    for (final event in added) {
      final writer = '${event.space}:${event.writer}';
      if (_records.containsKey(event.id) ||
          !newIds.add(event.id) ||
          event.sequence <= (heads[writer] ?? 0) ||
          history.isNotEmpty && compareEvents(history.last, event) >= 0) {
        return null;
      }
      heads[writer] = event.sequence;
      cost += event.canonicalRaw!.length * 4;
    }
    // Keep only one detached previous input for newly observed complete cuts.
    // It has no backlink; old generations cannot form a retained chain.
    final previous = RecurringTextInput._(
      history,
      _records,
      _heads,
      _inheritanceIndex,
      rawCost,
      _lookupCache,
    );
    return RecurringTextInput._(
      List.unmodifiable([...history, ...added]),
      Map.unmodifiable({..._records, for (final e in added) e.id: e}),
      Map.unmodifiable(heads),
      TextInheritanceIndex.appended(_inheritanceIndex, added),
      cost,
      _lookupCache == null
          ? null
          : _RecurringHistoryLookup.appended(_lookupCache!, added),
      previous,
    );
  }

  /// Exact old records in a preparation overlay do not change this input.
  /// Compare actual canonical bytes as well as ID; conflicting duplicates still
  /// take the strict generic reconstruction path and fail there.
  bool containsCanonical(LogEvent event) =>
      event.canonicalRaw != null &&
      _records[event.id]?.canonicalRaw == event.canonicalRaw;

  TextResolutionCut verifyInheritance(
    Map<String, dynamic> descriptor, {
    required LogEvent completion,
  }) =>
      _selectedIndex?.verify(descriptor, completion: completion) ??
      _inheritanceIndex.verify(descriptor, completion: completion);

  /// A declared cut is verified against this exact strictly decoded input
  /// before selecting parent-local membership records. Pending cuts stay pending.
  List<Map<String, dynamic>> observedChecklist(
    String parent,
    Map<String, dynamic> descriptor, {
    required LogEvent completion,
  }) {
    final verified = verifyInheritance(descriptor, completion: completion);
    if (verified.isPending) {
      throw TextInheritancePending(
        'Checklist is waiting for observed history.',
      );
    }
    return _forVerifiedCut(verified).checklist(parent);
  }

  List<Map<String, dynamic>> checklist(String parent) =>
      projectChecklist(_lookup.checklistHistory(parent), parent);

  RecurringTextInput _forPrefix(List<LogEvent> prefix) {
    bool same(List<LogEvent> available) =>
        prefix.length == available.length &&
        Iterable<int>.generate(
          prefix.length,
        ).every((i) => identical(prefix[i], available[i]));
    if (same(history)) return this;
    if (_previous != null && same(_previous.history)) return _previous;
    return RecurringTextInput._fromEvents(prefix);
  }
}

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
    return RecurringTextResolver.fromInput(
      engine,
      RecurringTextInput.fromCanonical(history, memo: memo),
      legacyRoots: legacyRoots,
      memo: memo,
      legacyScope: legacyScope,
    );
  }

  factory RecurringTextResolver.fromInput(
    NativeTextEngine engine,
    RecurringTextInput input, {
    LegacyTextRoots? legacyRoots,
    RecurringTextMemo? memo,
    String? legacyScope,
  }) {
    if (memo != null && legacyRoots != null && legacyScope == null) {
      throw ArgumentError(
        'Memoized legacy roots require an immutable baseline scope.',
      );
    }
    return RecurringTextResolver._(
      engine,
      input,
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
    this.input,
    this.legacyRoots,
    this.ancestors,
    this.observedFields,
    this.memo,
    this.legacyScope,
    this._runtime,
    this._closeRuntime,
  );
  final NativeTextEngine engine;
  final RecurringTextInput input;
  List<LogEvent> get history => input.history;
  _RecurringHistoryLookup get _lookup => input._lookup;
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
    if (_runtime._closed) {
      // A pending/failed entity may be followed by another entity in the same
      // ingestion transaction. Rejoin the memo's live admission runtime before
      // publishing observed fields; detached fields cannot authorize new owners.
      return RecurringTextResolver.fromInput(
        engine,
        input,
        legacyRoots: legacyRoots,
        memo: memo,
        legacyScope: legacyScope,
      ).resolve(entity);
    }
    try {
      return _resolve(entity);
    } catch (_) {
      // Failed admission cannot publish a lasting packet/claim authority graph.
      // Existing immutable fields can replay their originals after pool closure.
      try {
        memo?.clear();
      } catch (_) {
        /* Authority was discarded; preserve the original admission failure. */
      }
      try {
        _runtime.close();
      } catch (_) {
        /* Disposal cannot replace the original admission failure. */
      }
      _resolved.clear();
      observedFields.clear();
      rethrow;
    } finally {
      if (_closeRuntime) _runtime.close();
    }
  }

  Map<String, ResolvedTextField> _resolve(String entity) {
    if (_resolved.containsKey(entity)) return _resolved[entity]!;
    if (ancestors.contains(entity)) {
      throw FormatFailure('Cyclic recurring text lineage.');
    }
    final own = _lookup.own[entity] ?? const <LogEvent>[];
    final creations = own
        .where((event) => isNativeTextCreation(event.type))
        .toList();
    final contributions = textContributions(
      _lookup.contributionCandidates[entity] ?? const <LogEvent>[],
      entity,
    ).toList();
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
            event.type == 'checklist.itemCreated' ||
            event.type == 'user.created',
      )) {
        throw FormatFailure(
          'Recurring text identity collides with a creation.',
        );
      }
      if (_lookup.scalarSuccessors.contains(entity)) {
        throw FormatFailure(
          'Mixed successor text initialization; history retained.',
        );
      }
      for (final contribution in contributions) {
        final completion = contribution.event;
        final expected = contribution.checklist
            ? copiedChecklistId(
                (completion.data['successor'] as Map)['id'] as String,
                contribution.parent,
              )
            : const Uuid().v5(completion.entity, 'successor');
        if (expected != entity) {
          throw FormatFailure('Invalid recurring text identity.');
        }
        final proof = contribution.proof;
        final verified = input.verifyInheritance(proof, completion: completion);
        if (verified.isPending) {
          throw TextInheritancePending(
            'Recurring text is waiting for its declared canonical history.',
          );
        }
        Map<String, ResolvedTextField> observed;
        try {
          observed = observedFields.putIfAbsent(contribution.key, () {
            // The exact record set matters even when a declared head is
            // present: a sparse closed prefix must not reuse a fuller proof.
            final content = completion.integrityHash;
            if (content == null) {
              throw StateError('Completion memo evidence must be canonical.');
            }
            var key =
                '${engine.ownerId}|${legacyScope ?? ''}|${completion.hash}|$content';
            if (contribution.checklist) key += '|${contribution.parent}';
            final remembered = memo?._get(
              key,
              verified.recordsForResolution,
              verification: verified,
            );
            if (remembered != null) return remembered;
            final result = RecurringTextResolver._(
              engine,
              input._forVerifiedCut(verified),
              legacyRoots,
              {...ancestors, entity},
              observedFields,
              memo,
              legacyScope,
              _runtime,
              false,
            ).resolve(contribution.parent);
            memo?._put(
              key,
              result,
              verified.recordsForResolution,
              verification: verified,
            );
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
              contribution.snapshot[field] != parent.text) {
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
