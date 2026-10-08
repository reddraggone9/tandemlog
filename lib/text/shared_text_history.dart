import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/event.dart';
import 'native_text_engine.dart';
import 'recurring_text.dart';

/// An immutable reference to original operations. Recurrence copies references,
/// never a growing inherited packet list. Context/actor grants are verified by
/// the caller; this graph verifies that referenced packets retain exact authorship.
class SharedTextReference {
  SharedTextReference._(
    this.hash,
    this.rootContext,
    this.seed,
    this.parents,
    this.operation,
    this.depth,
  );
  final String hash, rootContext;
  final NativeTextUpdate seed;
  final List<SharedTextReference> parents;
  final LineageTextOperation? operation;
  final int depth;

  bool contains(SharedTextReference ancestor) {
    if (rootContext != ancestor.rootContext ||
        seed.encoded != ancestor.seed.encoded) {
      return false;
    }
    final seen = <String>{}, pending = <SharedTextReference>[this];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current.hash == ancestor.hash) return true;
      if (current.depth < ancestor.depth || !seen.add(current.hash)) continue;
      pending.addAll(current.parents);
    }
    return false;
  }
}

String _packetKey(LineageTextOperation packet) =>
    '${packet.event.space}:${packet.event.id}:${packet.field}';

Iterable<LineageTextOperation> _operations(
  SharedTextReference reference,
  Set<String> visited,
) sync* {
  final stack = <(SharedTextReference, bool)>[(reference, false)];
  final packets = <String>{};
  while (stack.isNotEmpty) {
    final (current, expanded) = stack.removeLast();
    if (expanded) {
      final packet = current.operation;
      if (packet != null && packets.add(_packetKey(packet))) yield packet;
      continue;
    }
    if (!visited.add(current.hash)) continue;
    stack.add((current, true));
    for (final parent in current.parents.reversed) {
      stack.add((parent, false));
    }
  }
}

class SharedTextHistoryGraph {
  final _nodes = <String, SharedTextReference>{};
  final _packets = <String, LineageTextOperation>{};
  int get nodeCount => _nodes.length;
  int get packetCount => _packets.length;

  SharedTextReference _node(
    String context,
    NativeTextUpdate seed,
    List<SharedTextReference> parents,
    LineageTextOperation? packet,
  ) {
    final hash = sha256
        .convert(
          utf8.encode(
            canonicalDataJson({
              'domain': 'tandemlog.text.history.reference.v1',
              'rootContext': context,
              'seedHash': sha256.convert(seed.bytes).toString(),
              'parents': parents.map((parent) => parent.hash).toList(),
              if (packet != null)
                'operation': {
                  'id': packet.event.id,
                  'space': packet.event.space,
                  'hash': packet.event.hash,
                  'field': packet.field,
                },
            }),
          ),
        )
        .toString();
    var depth = 0;
    for (final parent in parents) {
      if (parent.depth > depth) depth = parent.depth;
    }
    if (packet != null) depth++;
    return _nodes.putIfAbsent(
      hash,
      () => SharedTextReference._(
        hash,
        context,
        seed,
        List.unmodifiable(parents),
        packet,
        depth,
      ),
    );
  }

  SharedTextReference root(String context, NativeTextUpdate seed) {
    if (!isEventHash(context)) {
      throw FormatFailure('Invalid shared history context.');
    }
    return _node(context, seed, const [], null);
  }

  SharedTextReference append(
    SharedTextReference parent,
    LineageTextOperation packet,
  ) {
    final raw = packet.event.canonicalRaw;
    if (raw == null || !const {'title', 'description'}.contains(packet.field)) {
      throw FormatFailure(
        'Shared history requires original canonical packets.',
      );
    }
    final canonical = LogEvent.decode(raw);
    final change = (canonical.data['changes'] as Map?)?[packet.field] as Map?;
    if (!const {
          'task.textEdited',
          'task.textEditUndone',
        }.contains(canonical.type) ||
        canonical.id != packet.event.id ||
        canonical.hash != packet.event.hash ||
        canonical.space != packet.event.space ||
        canonical.entity != packet.event.entity ||
        canonical.type != packet.event.type ||
        canonical.clock != packet.event.clock ||
        canonical.previousHash != packet.event.previousHash ||
        canonicalDataJson(canonical.data) !=
            canonicalDataJson(packet.event.data) ||
        change == null ||
        canonical.writer != packet.claim.writer ||
        change['context'] != packet.claim.context ||
        change['allocation'] != packet.claim.allocation ||
        change['actor'] != packet.claim.actor ||
        change['update'] != packet.update.encoded) {
      throw FormatFailure(
        'Shared history packet differs from original authorship.',
      );
    }
    final key = _packetKey(packet), prior = _packets[key];
    if (prior != null) {
      if (prior.event.canonicalRaw != raw ||
          !prior.claim.sameOwner(packet.claim) ||
          prior.update.encoded != packet.update.encoded) {
        throw FormatFailure('Conflicting original shared history packet.');
      }
      if (operations(parent).any((operation) => _packetKey(operation) == key)) {
        return parent;
      }
    }
    // Decode owns deeply frozen data. Never retain a caller's mutable envelope,
    // even when its fields matched the original canonical bytes at admission.
    final retained =
        prior ??
        LineageTextOperation(
          canonical,
          packet.field,
          packet.claim,
          packet.update,
        );
    _packets[key] = retained;
    return _node(parent.rootContext, parent.seed, [parent], retained);
  }

  SharedTextReference merge(Iterable<SharedTextReference> incoming) {
    final unique = {
      for (final reference in incoming) reference.hash: reference,
    };
    if (unique.isEmpty) {
      throw ArgumentError('Shared history union requires a root.');
    }
    final parents = unique.values.toList()
      ..sort((a, b) => a.hash.compareTo(b.hash));
    final first = parents.first;
    if (parents.any(
      (parent) =>
          parent.rootContext != first.rootContext ||
          parent.seed.encoded != first.seed.encoded,
    )) {
      throw FormatFailure('Independent shared histories cannot be merged.');
    }
    if (parents.length == 1) return first;
    return _node(first.rootContext, first.seed, parents, null);
  }

  Iterable<LineageTextOperation> operations(SharedTextReference reference) =>
      _operations(reference, <String>{});
}

class SharedTextSnapshot {
  const SharedTextSnapshot(this.text, this.pending, this.stateHash);
  final String text, stateHash;
  final bool pending;
}

class _ActiveHistory {
  _ActiveHistory(this.reference, this.native, this.visited);
  SharedTextReference reference;
  final NativeTextMaterializer native;
  final Set<String> visited;
}

class _HistoricalCheckpoint {
  _HistoricalCheckpoint(this.reference, this.state);
  final SharedTextReference reference;
  final NativeTextState state;
  int get bytes => state.bytes.length + state.encoded.length * 2;
}

/// Incremental, unowned native documents plus bounded sparse historical state.
/// Checkpoint eviction changes replay cost only. Immutable packet references
/// remain authoritative; session editor/Undo owners never enter this cache.
class SharedTextMaterializer {
  SharedTextMaterializer(
    this.engine, {
    this.checkpointInterval = 32,
    this.checkpointByteLimit = 16 * 1024 * 1024,
    this.maxActiveRoots = 8,
    this.maxSnapshots = 2048,
    this.limits = const NativeTextLimits(visibleUtf16: 10000),
  }) {
    if (checkpointInterval < 1 ||
        checkpointByteLimit < 1 ||
        maxActiveRoots < 1 ||
        maxSnapshots < 1) {
      throw ArgumentError('Invalid history cache budget');
    }
  }
  final NativeTextEngine engine;
  final NativeTextLimits limits;
  final int checkpointInterval,
      checkpointByteLimit,
      maxActiveRoots,
      maxSnapshots;
  final _active = <String, _ActiveHistory>{};
  final _checkpoints = <String, _HistoricalCheckpoint>{};
  final _snapshots = <String, SharedTextSnapshot>{};
  bool _closed = false;
  int packetApplications = 0;
  int checkpointBytes = 0;
  int get checkpointCount => _checkpoints.length;

  _ActiveHistory _activate(SharedTextReference reference) {
    if (_closed) throw StateError('Shared history materializer is closed');
    final root =
        '${reference.rootContext}:${sha256.convert(reference.seed.bytes)}';
    var current = _active.remove(root);
    if (current != null && !reference.contains(current.reference)) {
      current.native.close();
      current = null;
    }
    if (current == null) {
      _HistoricalCheckpoint? checkpoint;
      for (final candidate in _checkpoints.values) {
        if (reference.contains(candidate.reference) &&
            (checkpoint == null ||
                candidate.reference.depth > checkpoint.reference.depth)) {
          checkpoint = candidate;
        }
      }
      while (_active.length >= maxActiveRoots) {
        _active.remove(_active.keys.first)!.native.close();
      }
      final native = engine.createMaterializer(
        seed:
            checkpoint?.state ?? NativeTextState.parse(reference.seed.encoded),
        limits: limits,
      );
      final visited = <String>{};
      if (checkpoint != null) {
        for (final _ in _operations(checkpoint.reference, visited)) {
          // Establish the visited reference frontier without retaining a list.
        }
      }
      current = _ActiveHistory(
        checkpoint?.reference ?? reference,
        native,
        visited,
      );
    }
    try {
      for (final operation in _operations(reference, current.visited)) {
        current.native.apply(operation.update);
        packetApplications++;
      }
      current.reference = reference;
      _active[root] = current;
      return current;
    } catch (_) {
      try {
        current.native.close();
      } catch (_) {
        /* Preserve the replay failure. */
      }
      rethrow;
    }
  }

  SharedTextSnapshot snapshot(SharedTextReference reference) {
    if (_closed) throw StateError('Shared history materializer is closed');
    final cached = _snapshots.remove(reference.hash);
    if (cached != null) {
      _snapshots[reference.hash] = cached;
      return cached;
    }
    final current = _activate(reference), read = current.native.read();
    final state = current.native.fullState;
    final snapshot = SharedTextSnapshot(
      read.text,
      read.pending,
      sha256.convert(state.bytes).toString(),
    );
    if (_snapshots.length >= maxSnapshots) {
      _snapshots.remove(_snapshots.keys.first);
    }
    _snapshots[reference.hash] = snapshot;
    if (!read.pending &&
        reference.depth > 0 &&
        reference.depth % checkpointInterval == 0 &&
        !_checkpoints.containsKey(reference.hash)) {
      final checkpoint = _HistoricalCheckpoint(reference, state);
      if (checkpoint.bytes <= checkpointByteLimit) {
        while (_checkpoints.isNotEmpty &&
            checkpointBytes + checkpoint.bytes > checkpointByteLimit) {
          checkpointBytes -= _checkpoints
              .remove(_checkpoints.keys.first)!
              .bytes;
        }
        _checkpoints[reference.hash] = checkpoint;
        checkpointBytes += checkpoint.bytes;
      }
    }
    return snapshot;
  }

  NativeTextState state(SharedTextReference reference) {
    final expected = snapshot(reference), current = _activate(reference);
    final result = current.native.fullState;
    if (sha256.convert(result.bytes).toString() != expected.stateHash) {
      throw FormatFailure(
        'Shared history replay differs from its verified state.',
      );
    }
    return result;
  }

  void close() {
    if (_closed) return;
    Object? failure;
    for (final active in _active.values) {
      try {
        active.native.close();
      } catch (error) {
        failure ??= error;
      }
    }
    _active.clear();
    _checkpoints.clear();
    _snapshots.clear();
    checkpointBytes = 0;
    _closed = true;
    if (failure != null) throw failure;
  }
}
