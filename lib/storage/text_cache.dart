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
  TextCache(this.db, this.engine);
  final Database db;
  final NativeTextEngine engine;

  void validatePackets(Iterable<LogEvent> incoming) {
    final registry = TextActorRegistry();
    registry.bindAll(
      db
          .select('SELECT context,writer,allocation,actor FROM text_actors')
          .map(
            (row) => TextActorClaim.fromJson(Map<String, dynamic>.from(row)),
          ),
    );
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
        registry.bindAll([claim]);
        registry.validateStructActors(
          claim,
          engine.inspect(NativeTextUpdate.parse(change['update'])),
        );
        db.execute('INSERT OR IGNORE INTO text_actors VALUES (?,?,?,?)', [
          claim.context,
          claim.actor,
          claim.writer,
          claim.allocation,
        ]);
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
    final registry = TextActorRegistry();
    registry.bindAll(
      db
          .select('SELECT context,writer,allocation,actor FROM text_actors')
          .map(
            (row) => TextActorClaim.fromJson(Map<String, dynamic>.from(row)),
          ),
    );
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
      final candidate = engine.createDocument(
        actorClientId: 2,
        limits: NativeTextLimits(visibleUtf16: field == 'title' ? 500 : 10000),
        seed: resolved.seed,
      );
      final applied = <String, String>{};
      try {
        final ordered = resolved.operations.toList()
          ..sort((a, b) => compareEvents(a.event, b.event));
        for (final operation in ordered) {
          final event = operation.event;
          if (event.canonicalRaw == null ||
              event.space != context.space ||
              operation.field != field ||
              (event.type != 'task.textEdited' &&
                  event.type != 'task.textEditUndone')) {
            throw FormatFailure('Invalid original inherited text packet.');
          }
          final canonical = LogEvent.decode(event.canonicalRaw!);
          final change = (canonical.data['changes'] as Map)[field] as Map?;
          final claim = operation.claim;
          if (change == null ||
              claim.writer != canonical.writer ||
              change['context'] != claim.context ||
              change['actor'] != claim.actor ||
              change['allocation'] != claim.allocation ||
              change['update'] != operation.update.encoded) {
            throw FormatFailure(
              'Inherited packet differs from original canonical authorship.',
            );
          }
          registry.bindAll([claim]);
          registry.validateStructActors(
            claim,
            engine.inspect(operation.update),
          );
          final previous = applied[event.id];
          if (previous != null && previous != operation.update.encoded) {
            throw FormatFailure('Conflicting inherited packet identity.');
          }
          if (previous == null) candidate.applyRemote(operation.update);
          applied[event.id] = operation.update.encoded;
          claims.add(claim);
        }
        final state = candidate.fullState.bytes;
        final stateHash = sha256.convert(state).toString();
        final text = candidate.read().text;
        if (stateHash != resolved.stateHash || text != resolved.text) {
          throw FormatFailure(
            'Resolved native state differs from its original packets.',
          );
        }
        final frontier = applied.keys.toList()..sort();
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
      } finally {
        candidate.dispose();
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

  void materialize(
    Map<String, dynamic> view,
    List<LogEvent> history, {
    LogEvent? basis,
    Map<String, String>? legacySeedText,
    String basisKind = 'legacy-baseline',
  }) {
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
      final registry = TextActorRegistry();
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
