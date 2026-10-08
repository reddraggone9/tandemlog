import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import '../domain/event.dart';
import '../domain/text_actor.dart';
import '../domain/text_context.dart';
import '../text/native_text_engine.dart';
import '../text/recurring_text.dart';

/// Disposable full native state. Every candidate is private until SQLite commits;
/// editor documents and their captured drafts are never used for materialization.
class TextCache {
  TextCache(this.db, this.engine, {this.memo});
  TextCache._transaction(this.db, this.engine, this.memo) {
    if (db.autocommit) {
      throw StateError('Shared text actors require an active transaction.');
    }
    _transactionActors = _loadActors();
  }

  /// Share validated ownership only inside the caller's active transaction.
  /// The caller must close this index in a finally block after commit/rollback,
  /// before the connection can start another transaction.
  factory TextCache.forTransaction(
    Database db,
    NativeTextEngine engine, {
    RecurringTextMemo? memo,
  }) => TextCache._transaction(db, engine, memo);
  final Database db;
  final NativeTextEngine engine;
  final RecurringTextMemo? memo;
  TextActorRegistry? _transactionActors;
  bool _closed = false;

  /// The scoped index must never outlive its owning SQLite transaction.
  void close() {
    _closed = true;
    _transactionActors = null;
  }

  TextActorRegistry _loadActors() =>
      TextActorRegistry(deriveActor: memo?.deriveActor)..bindAll(
        db
            .select('SELECT context,writer,allocation,actor FROM text_actors')
            .map(
              (row) => TextActorClaim.fromJson(Map<String, dynamic>.from(row)),
            ),
      );

  TextActorRegistry _actors() {
    _ensureUsable();
    return _transactionActors ?? _loadActors();
  }

  void _ensureUsable() {
    if (_closed || (_transactionActors != null && db.autocommit)) {
      throw StateError('Text actor index used outside its transaction.');
    }
  }

  void validatePackets(Iterable<LogEvent> incoming) {
    final registry = _actors();
    for (final event in incoming) {
      if (event.type != 'task.textEdited' &&
          event.type != 'task.textEditUndone') {
        continue;
      }
      for (final change in (event.data['changes'] as Map).values) {
        final claim = TextActorClaim(
          context: change['context'] as String,
          writer: event.writer,
          allocation: change['allocation'] as String,
          actor: change['actor'] as int,
        );
        final present = registry.hasOwner(claim);
        registry.bindAll([claim]);
        registry.validateStructActors(
          claim,
          engine.inspect(NativeTextUpdate.parse(change['update'])),
        );
        if (!present) {
          db.execute('INSERT OR IGNORE INTO text_actors VALUES (?,?,?,?)', [
            claim.context,
            claim.actor,
            claim.writer,
            claim.allocation,
          ]);
        }
      }
    }
  }

  /// Cache a resolver-verified lineage. Original packet claims remain scoped to
  /// their original context; the resolver supplies the inheritance grants.
  /// The caller owns the SQLite transaction, as for ordinary materialization.
  void materializeResolved(
    Map<String, dynamic> view,
    Map<String, ResolvedTextField> fields,
  ) {
    if (fields.length != 2 ||
        !fields.containsKey('title') ||
        !fields.containsKey('description')) {
      throw FormatFailure('Resolved text requires both fields.');
    }
    if (fields.values.every((field) => field.historyReference != null)) {
      _ensureUsable();
      final rows = <List<Object?>>[];
      final texts = <String, String>{};
      for (final entry in fields.entries) {
        final field = entry.value, context = field.context;
        final reference = field.historyReference!;
        if (context.entity != view['id'] ||
            context.field != entry.key ||
            sha256.convert(field.seed.bytes).toString() != context.seedHash ||
            reference.seed.encoded != field.seed.encoded) {
          throw FormatFailure('Resolved shared reference or seed mismatch.');
        }
        // Only the resolver can construct a field with a history reference.
        // It already verified context grants, original claims and native text.
        // No native checkpoint from SQLite is trusted or replayed on this path.
        // Ingestion persists actor claims through validatePackets beforehand.
        rows.add([
          view['id'],
          entry.key,
          context.hash,
          'yrs-v1',
          2,
          context.seedHash,
          Uint8List(0),
          reference.hash,
          jsonEncode({'history': reference.hash}),
        ]);
        texts[entry.key] = field.text;
      }
      for (final row in rows) {
        db.execute(
          'INSERT OR REPLACE INTO text_fields VALUES (?,?,?,?,?,?,?,?,?)',
          row,
        );
      }
      view.addAll(texts);
      return;
    }
    final registry = _actors();
    final claims = <TextActorClaim>[];
    final rows = <List<Object?>>[];
    final texts = <String, String>{};
    for (final entry in fields.entries) {
      final field = entry.key,
          resolved = entry.value,
          context = resolved.context;
      if (context.entity != view['id'] ||
          context.field != field ||
          sha256.convert(resolved.seed.bytes).toString() != context.seedHash) {
        throw FormatFailure('Resolved native context or seed mismatch.');
      }
      final ordered = resolved.operations.toList()
        ..sort((a, b) => compareEvents(a.event, b.event));
      final originals = <String, String>{};
      for (final operation in ordered) {
        final event = operation.event;
        if (event.canonicalRaw == null ||
            event.space != context.space ||
            operation.field != field ||
            (event.type != 'task.textEdited' &&
                event.type != 'task.textEditUndone')) {
          throw FormatFailure('Invalid original inherited text packet.');
        }
        final canonical =
            memo?.decodeCanonical(event.canonicalRaw!) ??
            LogEvent.decode(event.canonicalRaw!);
        final change = (canonical.data['changes'] as Map)[field] as Map?;
        final claim = operation.claim;
        if (canonical.id != event.id ||
            canonical.space != context.space ||
            canonical.type != event.type ||
            change == null ||
            claim.writer != canonical.writer ||
            change['context'] != claim.context ||
            change['actor'] != claim.actor ||
            change['allocation'] != claim.allocation ||
            change['update'] != operation.update.encoded) {
          throw FormatFailure(
            'Inherited packet differs from original canonical authorship.',
          );
        }
        final previous = originals[event.id];
        if (previous != null && previous != operation.update.encoded) {
          throw FormatFailure('Conflicting inherited packet identity.');
        }
        originals[event.id] = operation.update.encoded;
      }
      final newClaims = ordered
          .map((operation) => operation.claim)
          .where((claim) => !registry.hasOwner(claim))
          .toList();
      registry.bindAll(newClaims);
      for (final operation in ordered) {
        registry.validateStructActors(
          operation.claim,
          engine.inspect(operation.update),
        );
      }
      claims.addAll(newClaims);
      final limits = NativeTextLimits(
        visibleUtf16: field == 'title' ? 500 : 10000,
      );
      var checkpoint = _resolvedCheckpoint(
        resolved,
        originals.keys.toSet(),
        limits,
      );
      while (true) {
        final applied = checkpoint?.applied ?? <String>{};
        final candidate =
            checkpoint?.document ??
            engine.createDocument(
              actorClientId: 2,
              limits: limits,
              seed: resolved.seed,
            );
        try {
          for (final operation in ordered) {
            if (applied.add(operation.event.id)) {
              candidate.applyRemote(operation.update);
            }
          }
          final state = candidate.fullState.bytes;
          final stateHash = sha256.convert(state).toString();
          final text = candidate.read().text;
          if (stateHash != resolved.stateHash || text != resolved.text) {
            // A self-consistent cache is insufficient proof. Compare against the
            // independently resolved original history, then retry from the seed.
            if (checkpoint != null) {
              checkpoint = null;
              continue;
            }
            throw FormatFailure(
              'Resolved native state differs from its original packets.',
            );
          }
          final frontier = originals.keys.toList()..sort();
          rows.add([
            view['id'],
            field,
            context.hash,
            'yrs-v1',
            1,
            context.seedHash,
            state,
            stateHash,
            jsonEncode(frontier),
          ]);
          texts[field] = text;
          break;
        } on NativeTextException {
          if (checkpoint == null) rethrow;
          checkpoint = null;
        } on FormatException {
          if (checkpoint == null) rethrow;
          checkpoint = null;
        } finally {
          candidate.dispose();
        }
      }
    }
    for (final claim in claims) {
      db.execute('INSERT OR IGNORE INTO text_actors VALUES (?,?,?,?)', [
        claim.context,
        claim.actor,
        claim.writer,
        claim.allocation,
      ]);
    }
    for (final row in rows) {
      db.execute(
        'INSERT OR REPLACE INTO text_fields VALUES (?,?,?,?,?,?,?,?,?)',
        row,
      );
    }
    view.addAll(texts);
  }

  /// A cached ancestor can carry the same original identities into its child.
  /// Frontier inclusion and self-hash admit only a candidate; the caller must
  /// compare its final native state/text with the independent resolver result.
  /// A mismatch or malformed checkpoint always falls back to original replay.
  _ResolvedCheckpoint? _resolvedCheckpoint(
    ResolvedTextField resolved,
    Set<String> known,
    NativeTextLimits limits,
  ) {
    final context = resolved.context;
    // Sort lightweight identifiers first. Selecting every candidate BLOB and
    // full frontier copies the whole occurrence history on each materialization.
    // Fetch checkpoint bytes only until a usable candidate is found.
    for (final reference in db.select(
      "SELECT entity FROM text_fields WHERE field=? AND seed_hash=? AND codec='yrs-v1' AND adapter=1 ORDER BY (entity=?) DESC,length(frontier) DESC",
      [context.field, context.seedHash, context.entity],
    )) {
      final row = db.select(
        'SELECT * FROM text_fields WHERE entity=? AND field=?',
        [reference['entity'], context.field],
      ).single;
      final bytes = row['state'];
      if (bytes is! Uint8List ||
          (row['entity'] == context.entity && row['context'] != context.hash) ||
          sha256.convert(bytes).toString() != row['state_hash']) {
        continue;
      }
      Object? frontier;
      try {
        frontier = jsonDecode(row['frontier'] as String);
      } on FormatException {
        continue;
      }
      if (frontier is! List ||
          !frontier.every((id) => id is String && known.contains(id)) ||
          frontier.toSet().length != frontier.length) {
        continue;
      }
      try {
        final document = engine.restoreDocument(
          actorClientId: 2,
          limits: limits,
          checkpoint: NativeTextCheckpoint(
            NativeTextState.parse(base64Encode(bytes)),
          ),
        );
        return _ResolvedCheckpoint(document, frontier.cast<String>().toSet());
      } on NativeTextException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  void materialize(
    Map<String, dynamic> view,
    List<LogEvent> history, {
    LogEvent? basis,
    Map<String, String>? legacySeedText,
    String basisKind = 'legacy-baseline',
  }) {
    _ensureUsable();
    final creations = history.where(
      (event) => event.type == 'task.createdWithText',
    );
    final creation = creations.isEmpty ? null : creations.single;
    if (creation == null && basis == null) {
      // Competing roots cannot select a new initialization. Retain the last
      // verified native display while the canonical evidence remains pending.
      for (final row in db.select('SELECT * FROM text_fields WHERE entity=?', [
        view['id'],
      ])) {
        final bytes = row['state'] as Uint8List;
        if (sha256.convert(bytes).toString() != row['state_hash']) {
          throw FormatFailure(
            'Unverified text cache cannot resolve competing initialization records.',
          );
        }
        final field = row['field'] as String;
        final candidate = engine.restoreDocument(
          actorClientId: 2,
          limits: NativeTextLimits(
            visibleUtf16: field == 'title' ? 500 : 10000,
          ),
          checkpoint: NativeTextCheckpoint(
            NativeTextState.parse(base64Encode(bytes)),
          ),
        );
        try {
          view[field] = candidate.read().text;
        } finally {
          candidate.dispose();
        }
      }
      return;
    }
    for (final field in ['title', 'description']) {
      final initial =
          creation?.data[field] as String? ?? legacySeedText?[field];
      if (initial == null) continue;
      final seed = engine.seedText(initial);
      final seedHash = sha256.convert(seed.bytes).toString();
      final context = creation != null
          ? TextFieldContext.fromCreation(creation, field)
          : TextFieldContext(
              space: basis!.space,
              entity: view['id'] as String,
              field: field,
              basis: basis.id,
              basisKind: basisKind,
              seedHash: seedHash,
            );
      if (context.seedHash != seedHash) {
        throw FormatFailure(
          'Native text seed hash differs in ${creation?.id ?? basis!.id}.',
        );
      }
      _field(view, field, context, seed, history);
    }
  }

  void _field(
    Map<String, dynamic> view,
    String field,
    TextFieldContext context,
    NativeTextUpdate seed,
    List<LogEvent> history,
  ) {
    final entity = view['id'] as String;
    final cached = db.select(
      'SELECT * FROM text_fields WHERE entity=? AND field=?',
      [entity, field],
    );
    final limits = NativeTextLimits(
      visibleUtf16: field == 'title' ? 500 : 10000,
    );
    final applied = <String>{};
    NativeTextDocument candidate;
    if (cached.isEmpty) {
      candidate = engine.createDocument(
        actorClientId: 2,
        limits: limits,
        seed: seed,
      );
    } else {
      final row = cached.single;
      final bytes = row['state'];
      Object? frontier;
      try {
        frontier = jsonDecode(row['frontier'] as String);
      } on FormatException {
        /* Rebuild below. */
      }
      final known = history
          .where(
            (event) =>
                (event.type == 'task.textEdited' ||
                    event.type == 'task.textEditUndone') &&
                (event.data['changes'] as Map).containsKey(field),
          )
          .map((event) => event.id)
          .toSet();
      final validFrontier =
          frontier is List &&
          frontier.every((id) => id is String && known.contains(id)) &&
          frontier.toSet().length == frontier.length;
      if (row['context'] != context.hash ||
          row['codec'] != 'yrs-v1' ||
          row['adapter'] != 1 ||
          row['seed_hash'] != context.seedHash ||
          bytes is! Uint8List ||
          !validFrontier ||
          sha256.convert(bytes).toString() != row['state_hash']) {
        // Invalid disposable state is rebuilt from exact canonical operations.
        candidate = engine.createDocument(
          actorClientId: 2,
          limits: limits,
          seed: seed,
        );
      } else {
        applied.addAll(frontier.cast<String>());
        try {
          candidate = engine.restoreDocument(
            actorClientId: 2,
            limits: limits,
            checkpoint: NativeTextCheckpoint(
              NativeTextState.parse(base64Encode(bytes)),
            ),
          );
        } on NativeTextException {
          applied.clear();
          candidate = engine.createDocument(
            actorClientId: 2,
            limits: limits,
            seed: seed,
          );
        } on FormatException {
          applied.clear();
          candidate = engine.createDocument(
            actorClientId: 2,
            limits: limits,
            seed: seed,
          );
        }
      }
    }
    try {
      final registry = TextActorRegistry(deriveActor: memo?.deriveActor);
      registry.bindAll(
        db
            .select(
              'SELECT context,writer,allocation,actor FROM text_actors WHERE context=?',
              [context.hash],
            )
            .map(
              (row) => TextActorClaim.fromJson(Map<String, dynamic>.from(row)),
            ),
      );
      final ordered = history.toList()..sort(compareEvents);
      for (final event in ordered) {
        if (event.type != 'task.textEdited' &&
            event.type != 'task.textEditUndone') {
          continue;
        }
        final change = (event.data['changes'] as Map)[field];
        if (change == null) continue;
        final claim = TextActorClaim(
          context: change['context'] as String,
          writer: event.writer,
          allocation: change['allocation'] as String,
          actor: change['actor'] as int,
        );
        if (claim.context != context.hash) {
          throw FormatFailure('Native text context mismatch in ${event.id}.');
        }
        registry.bindAll([claim]);
        if (!applied.contains(event.id)) {
          final update = NativeTextUpdate.parse(change['update']);
          registry.validateStructActors(claim, engine.inspect(update));
          candidate.applyRemote(update);
          applied.add(event.id);
        }
        db.execute('INSERT OR IGNORE INTO text_actors VALUES (?,?,?,?)', [
          claim.context,
          claim.actor,
          claim.writer,
          claim.allocation,
        ]);
      }
      final snapshot = candidate.read();
      final state = candidate.fullState.bytes;
      final frontier = applied.toList()..sort();
      db.execute(
        'INSERT OR REPLACE INTO text_fields VALUES (?,?,?,?,?,?,?,?,?)',
        [
          entity,
          field,
          context.hash,
          'yrs-v1',
          1,
          context.seedHash,
          state,
          sha256.convert(state).toString(),
          jsonEncode(frontier),
        ],
      );
      view[field] = snapshot.text;
    } finally {
      candidate.dispose();
    }
  }
}

class _ResolvedCheckpoint {
  _ResolvedCheckpoint(this.document, this.applied);
  final NativeTextDocument document;
  final Set<String> applied;
}
