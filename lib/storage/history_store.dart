import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/validated_action_cache.dart';
import 'unified_record.dart';

/// One writer's sealed state: [sequence] stored records ending at byte [end]
/// (just after the last record's LF). The last record starts at [lastStart]
/// and has chain hash [hash]. Sequence 0 is an empty stream at the genesis.
final class HistorySeal {
  const HistorySeal(this.sequence, this.end, this.hash, this.lastStart);
  final int sequence, end, lastStart;
  final String hash;
}

/// A complete, chain-validated record and its byte range in the writer file
/// ([length] excludes the LF).
typedef StoredRecord = ({UnifiedRecord record, int start, int length});

/// A record's stored row, serialized.
typedef EncodedRow = ({
  int sequence,
  int start,
  int length,
  String hash,
  String raw,
  String typed,
});

/// A stored row before decoding.
typedef StoredRow = ({int start, int length, String raw, String typed});

/// Lee 11-05: the profile database holds the whole decoded history as rows,
/// appended in the same transaction that advances `protected_app_heads`, so a
/// warm start never re-parses the logs. Not a size-capped cache: only the log
/// safety limits apply. See design/history-store.md.
///
/// Per-location tables follow the `tasks_<key>_*` projection precedent; the
/// profile schema version is unchanged. A changed [binding] (including
/// [generation]) drops and rebuilds them from a strict open.
final class HistoryStore {
  HistoryStore(this.db, this.key) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw ArgumentError('A history store needs a canonical location key.');
    }
  }

  /// Bump when record decoding, the typed field layout or admission rules
  /// change so that stored rows are no longer equivalent to a strict decode.
  static const generation = 1;

  final Database db;
  final String key;
  String get _records => 'history_${key}_records';
  String get _seals => 'history_${key}_seals';
  String get _bindingKey => 'app5.store.$key';

  static String binding({
    required String space,
    required String epoch,
    required String manifestDigest,
    required String writer,
    required bool nativeText,
  }) => jsonEncode([
    generation,
    ValidatedActionCache.layout,
    space,
    epoch,
    manifestDigest,
    writer,
    nativeText,
  ]);

  /// The stored binding, or null when there is no complete store.
  String? readBinding() {
    final rows = db.select('SELECT value FROM profile_metadata WHERE key=?', [
      _bindingKey,
    ]);
    if (rows.isEmpty || !_tablesExist()) return null;
    return rows.single['value'] as String;
  }

  String get _recordsSql =>
      'CREATE TABLE $_records (writer TEXT NOT NULL, seq INTEGER NOT NULL, start_offset INTEGER NOT NULL, length INTEGER NOT NULL, hash TEXT NOT NULL, raw TEXT NOT NULL, typed TEXT NOT NULL, PRIMARY KEY(writer,seq))';
  String get _sealsSql =>
      'CREATE TABLE $_seals (writer TEXT PRIMARY KEY, sequence INTEGER NOT NULL, end_offset INTEGER NOT NULL, hash TEXT NOT NULL, last_start INTEGER NOT NULL)';

  // Both tables exist with exactly their frozen definitions.
  bool _tablesExist() {
    final rows = db.select(
      "SELECT name,sql FROM sqlite_schema WHERE type='table' AND name IN (?,?)",
      [_records, _seals],
    );
    final sql = {for (final r in rows) r['name']: r['sql']};
    return sql.length == 2 &&
        sql[_records] == _recordsSql &&
        sql[_seals] == _sealsSql;
  }

  Map<String, HistorySeal> readSeals() => {
    for (final row in db.select(
      'SELECT writer,sequence,end_offset,hash,last_start FROM $_seals',
    ))
      row['writer'] as String: HistorySeal(
        row['sequence'] as int,
        row['end_offset'] as int,
        row['hash'] as String,
        row['last_start'] as int,
      ),
  };

  String? rawAt(String writer, int sequence) {
    final rows = db.select(
      'SELECT raw FROM $_records WHERE writer=? AND seq=?',
      [writer, sequence],
    );
    return rows.isEmpty ? null : rows.single['raw'] as String;
  }

  /// Every stored row of [writer] in sequence order, or null if they are not
  /// exactly sequences 1..[seal].sequence ending in the sealed hash.
  List<StoredRow>? readWriter(String writer, HistorySeal seal) {
    final rows = db.select(
      'SELECT seq,start_offset,length,hash,raw,typed FROM $_records WHERE writer=? ORDER BY seq',
      [writer],
    );
    if (rows.length != seal.sequence) return null;
    final result = <StoredRow>[];
    for (final row in rows) {
      if (row['seq'] != result.length + 1) return null;
      result.add((
        start: row['start_offset'] as int,
        length: row['length'] as int,
        raw: row['raw'] as String,
        typed: row['typed'] as String,
      ));
    }
    if (rows.isNotEmpty && rows.last['hash'] != seal.hash) return null;
    return result;
  }

  /// Read in bounded pages; queue ownership keeps the seals stable while
  /// the loading animation gets event-loop turns between SQLite calls.
  Future<List<StoredRow>?> readWriterBetweenFrames(
    String writer,
    HistorySeal seal,
    Future<void> Function() pause,
  ) async {
    final result = <StoredRow>[];
    String? lastHash;
    for (var after = 0; after < seal.sequence;) {
      final rows = db.select(
        'SELECT seq,start_offset,length,hash,raw,typed FROM $_records WHERE writer=? AND seq>? ORDER BY seq LIMIT 128',
        [writer, after],
      );
      if (rows.isEmpty) return null;
      for (final row in rows) {
        if (row['seq'] != result.length + 1) return null;
        result.add((
          start: row['start_offset'] as int,
          length: row['length'] as int,
          raw: row['raw'] as String,
          typed: row['typed'] as String,
        ));
        lastHash = row['hash'] as String;
      }
      after = result.length;
      await pause();
    }
    if (db.select(
      'SELECT seq FROM $_records WHERE writer=? AND seq>? LIMIT 1',
      [writer, result.length],
    ).isNotEmpty) {
      return null;
    }
    if (result.length != seal.sequence ||
        result.isNotEmpty && lastHash != seal.hash) {
      return null;
    }
    return result;
  }

  /// Restores [rows] without re-hashing: trust comes from the seal and the
  /// open's fast check (Lee 11-05). Pure, so it may run in another isolate.
  static List<UnifiedRecord> decode(List<StoredRow> rows) =>
      UnifiedDecodedCache.restoreStored([
        for (final row in rows) (row.raw, row.typed),
      ]);

  /// Drops any previous store and starts an empty one for [newBinding].
  /// Call inside the profile transaction that inserts the rebuilt rows.
  void reset(String newBinding) {
    db.execute('DROP TABLE IF EXISTS $_records');
    db.execute('DROP TABLE IF EXISTS $_seals');
    db.execute(_recordsSql);
    db.execute(_sealsSql);
    // The whole-blob decoded cache this store replaces (any location).
    db.execute("DELETE FROM profile_metadata WHERE key LIKE 'app5.decoded.%'");
    db.execute('INSERT OR REPLACE INTO profile_metadata VALUES (?,?)', [
      _bindingKey,
      newBinding,
    ]);
  }

  void deleteWriter(String writer) {
    db.execute('DELETE FROM $_records WHERE writer=?', [writer]);
    db.execute('DELETE FROM $_seals WHERE writer=?', [writer]);
  }

  /// Removes the store; the next open is strict and rebuilds it.
  void drop() {
    db.execute('DELETE FROM profile_metadata WHERE key=?', [_bindingKey]);
    db.execute('DROP TABLE IF EXISTS $_records');
    db.execute('DROP TABLE IF EXISTS $_seals');
  }

  /// Appends [records] (consecutive, after the writer's current seal) and
  /// moves the seal. Call inside the transaction that advances the writer's
  /// `protected_app_heads` row to the same sequence, hash and end.
  void append(
    String writer,
    List<StoredRecord> records,
    HistorySeal seal, {
    Map<UnifiedRecord, (String, String)>? encoded,
  }) {
    appendRows(writer, [
      for (final r in records)
        (
          sequence: r.record.sequence,
          start: r.start,
          length: r.length,
          hash: r.record.hash,
          raw: encoded?[r.record]?.$1 ?? r.record.encode(),
          typed:
              encoded?[r.record]?.$2 ??
              UnifiedDecodedCache.typedFields(r.record),
        ),
    ], seal);
  }

  /// [append] with each record's serialization already made.
  void appendRows(String writer, List<EncodedRow> rows, HistorySeal seal) {
    if (rows.isNotEmpty) {
      final insert = db.prepare('INSERT INTO $_records VALUES (?,?,?,?,?,?,?)');
      try {
        for (final r in rows) {
          insert.execute([
            writer,
            r.sequence,
            r.start,
            r.length,
            r.hash,
            r.raw,
            r.typed,
          ]);
        }
      } finally {
        insert.close();
      }
    }
    db.execute('INSERT OR REPLACE INTO $_seals VALUES (?,?,?,?,?)', [
      writer,
      seal.sequence,
      seal.end,
      seal.hash,
      seal.lastStart,
    ]);
  }
}
