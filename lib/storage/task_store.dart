import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../domain/undo.dart';
export '../domain/undo.dart';
import '../domain/projection.dart';
import '../domain/bulk_task_edit.dart';
export '../domain/bulk_task_edit.dart';
import '../application/task_clock.dart';
import '../domain/schedule.dart' hide validateSchedule;
import 'log_folder.dart';
import 'profile_lock.dart';
import 'writer_guard.dart';
import 'local_durability.dart';
export 'writer_guard.dart';

/// The task state observed by a caller changed before a guarded command.
class StaleTaskSnapshot implements Exception {
  @override
  String toString() => 'Tasks changed. Review the selection and try again.';
}

/// A canonical history failure, with the first offending record location.
class HistoryVerificationFailure extends FormatFailure {
  final String fileName, reason;
  final int recordNumber, byteOffset;
  HistoryVerificationFailure(
    this.fileName,
    this.recordNumber,
    this.byteOffset,
    this.reason,
  ) : super(
        '$fileName: record $recordNumber, byte offset $byteOffset: $reason',
      );
}

class HistoryVerificationReport {
  final int checkedLogCount, checkedRecordCount, checkedByteCount;
  final int importedEventCount;
  const HistoryVerificationReport({
    required this.checkedLogCount,
    required this.checkedRecordCount,
    required this.checkedByteCount,
    required this.importedEventCount,
  });
}

/// Owns durable log ingestion and one disposable SQLite materialization.
class TaskStore {
  final LogFolder folder;
  final Database db;
  final String writer;
  final ProfileLock lock;
  final WriterGuard writerGuard;
  int _acknowledgedOwnedSequence = 0;
  bool _writerHasPendingAppend = false;
  final DateTime Function() now;
  static const materialClockSkew = Duration(minutes: 5);
  String? clockWarning;
  late final String space;
  int readFiles = 0, cacheTransactions = 0;
  Map<String, int>? lastBatchTiming;
  HistoryVerificationReport? _lastHistoryVerification;
  HistoryVerificationReport? get lastHistoryVerification =>
      _lastHistoryVerification;
  Future<void> _queue = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;
  Future<T> _serialize<T>(Future<T> Function() work) {
    if (_closed) return Future.error(StateError('Workspace is closed.'));
    final result = _queue.then((_) {
      return work();
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Future<String> _readSpace(LogFolder folder) async {
    final raw = await folder.read('tandemlog-space.json');
    if (raw.length > 4096) throw FormatFailure('Oversized workspace manifest.');
    final manifest = jsonDecode(utf8.decode(raw));
    if (manifest is Map<String, dynamic> &&
        (manifest['v'] == 1 || manifest['v'] == 2) &&
        manifest['id'] is String &&
        isCanonicalId(manifest['id']) &&
        manifest.keys.every((key) => {'v', 'id'}.contains(key))) {
      throw FormatFailure(
        'This folder uses an older prerelease format (v${manifest['v']}). Preserve this folder and choose a new data folder for this prerelease.',
      );
    }
    if (manifest is! Map<String, dynamic> ||
        manifest['v'] != protocolVersion ||
        manifest['id'] is! String ||
        !isCanonicalId(manifest['id']) ||
        manifest.keys.any((key) => !{'v', 'id'}.contains(key))) {
      throw FormatFailure('Unsupported or invalid workspace manifest.');
    }
    return manifest['id'] as String;
  }

  TaskStore._(
    this.folder,
    this.db,
    this.writer,
    this.lock,
    this.now,
    this.writerGuard,
  );
  static Future<TaskStore> open(
    LogFolder folder,
    String privatePath, {
    void Function(String, int)? onTiming,
    DateTime Function()? now,
    String? writerIdentity,
    WriterGuard? writerGuard,
  }) async {
    final phase = Stopwatch()..start();
    void mark(String name) {
      onTiming?.call(name, phase.elapsedMilliseconds);
      phase.reset();
    }

    await ensureDirectoryDurable(Directory(privatePath));
    final lock = await ProfileLock.acquire(
      privatePath,
      fileName: 'session.lock',
      message: 'This workspace is already open in another app instance.',
    );
    Database? db;
    try {
      // The application supplies its settings-owned installation identity.
      // Omitted identity retains compatibility for standalone store clients.
      var writer = writerIdentity;
      if (writer == null) {
        final identity = File('$privatePath/writer-id');
        if (!await identity.exists()) {
          await createFileDurable(identity, utf8.encode(const Uuid().v4()));
        }
        await syncParentAfterCreate(identity);
        writer = (await identity.readAsString()).trim();
      }
      if (!isCanonicalId(writer)) {
        throw FormatFailure('Invalid local writer identity.');
      }
      mark('identity_lock');
      // Reject old canonical protocols before opening or migrating their cache.
      if ((await folder.list()).any((f) => f.name == 'tandemlog-space.json')) {
        await _readSpace(folder);
      }
      db = sqlite3.open('$privatePath/cache.sqlite');
      final version =
          db.select('PRAGMA user_version').first.values.first as int;
      if (version < 0 || version > 13) {
        throw FormatFailure(
          'This cache was created by a newer app. Use a compatible app; the cache and canonical logs were retained.',
        );
      }
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      if (version > 0 && version < 13) {
        await _prepareCacheReplay(db, folder, privatePath, version);
      }
      db.execute(
        'CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, entity TEXT NOT NULL, writer TEXT NOT NULL, seq INTEGER NOT NULL, clock INTEGER NOT NULL, raw TEXT NOT NULL, UNIQUE(writer,seq))',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS events_entity ON events(entity,clock,writer)',
      );
      db.execute(
        "CREATE INDEX IF NOT EXISTS events_type ON events(json_extract(raw,'\$.type'))",
      );
      db.execute('CREATE INDEX IF NOT EXISTS events_clock ON events(clock)');
      db.execute(
        "CREATE INDEX IF NOT EXISTS events_successor ON events(json_extract(raw,'\$.data.successor.id'))",
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS views (id TEXT PRIMARY KEY, raw TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS streams (name TEXT PRIMARY KEY, offset INTEGER NOT NULL, hash TEXT NOT NULL, stamp TEXT NOT NULL)',
      );
      // Retain older whole-prefix baselines as integrity evidence at their
      // original offsets; they are never resumable SHA state.
      db.execute('BEGIN IMMEDIATE');
      try {
        final columns = db.select('PRAGMA table_info(streams)');
        if (!columns.any((r) => r['name'] == 'hash_offset')) {
          db.execute(
            'ALTER TABLE streams ADD COLUMN hash_offset INTEGER NOT NULL DEFAULT 0',
          );
          db.execute('UPDATE streams SET hash_offset=offset');
        }
        if (!columns.any((r) => r['name'] == 'range_capable')) {
          db.execute(
            'ALTER TABLE streams ADD COLUMN range_capable INTEGER NOT NULL DEFAULT 0',
          );
        }
        db.execute(
          'CREATE TABLE IF NOT EXISTS stream_ranges (name TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(name,start_offset))',
        );
        for (final definition in [
          'chain_head TEXT',
          'last_seq INTEGER NOT NULL DEFAULT 0',
          'last_clock INTEGER',
        ]) {
          final name = definition.split(' ').first;
          if (!columns.any((r) => r['name'] == name)) {
            db.execute('ALTER TABLE streams ADD COLUMN $definition');
          }
        }
        db.execute(
          "UPDATE streams SET chain_head=(SELECT json_extract(raw,'\$.hash') FROM events WHERE writer=substr(streams.name,1,length(streams.name)-6) ORDER BY seq DESC LIMIT 1), last_seq=(SELECT COALESCE(MAX(seq),0) FROM events WHERE writer=substr(streams.name,1,length(streams.name)-6)), last_clock=(SELECT MAX(clock) FROM events WHERE writer=substr(streams.name,1,length(streams.name)-6)) WHERE chain_head IS NULL",
        );
        db.execute('PRAGMA user_version=13');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      db.execute(
        'CREATE TABLE IF NOT EXISTS positions (id TEXT PRIMARY KEY, rank INTEGER NOT NULL)',
      );
      mark('sqlite_open_schema');
      final store = TaskStore._(
        folder,
        db,
        writer,
        lock,
        now ?? DateTime.now,
        writerGuard ?? FileWriterGuard(privatePath),
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      final old = db.select("SELECT value FROM metadata WHERE key='space'");
      final files = await folder.list();
      if (!files.any((f) => f.name == 'tandemlog-space.json')) {
        if (old.isNotEmpty) {
          throw FormatFailure(
            'Previously opened workspace manifest is missing. Restore it before writing.',
          );
        }
        if (files.any((f) => f.name.endsWith('.jsonl'))) {
          throw FormatFailure(
            'Logs exist without a workspace manifest. Restore the manifest before opening.',
          );
        }
        await folder.create(
          'tandemlog-space.json',
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({'v': protocolVersion, 'id': const Uuid().v4()}),
            ),
          ),
        );
      }
      store.space = await _readSpace(folder);
      // A selected location must never silently change to another data space.
      if (old.isNotEmpty && old.first['value'] != store.space) {
        throw FormatFailure('Workspace identity changed at this location.');
      }
      db.execute("INSERT OR IGNORE INTO metadata VALUES ('space',?)", [
        store.space,
      ]);
      mark('manifest');
      await store.refresh();
      final orderVersion = db.select(
        "SELECT value FROM metadata WHERE key='order_projection'",
      );
      if (orderVersion.isEmpty ||
          orderVersion.single['value'] != '2' ||
          db.select('SELECT COUNT(*) AS n FROM positions').first['n'] !=
              db.select('SELECT COUNT(*) AS n FROM views').first['n']) {
        db.execute('BEGIN IMMEDIATE');
        try {
          store._rebuildOrder();
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      }
      mark('ingest');
      return store;
    } catch (_) {
      try {
        db?.close();
      } finally {
        await lock.close();
      }
      rethrow;
    }
  }

  /// Keep prior integrity checkpoints and space binding while discarding only
  /// obsolete materializations. A failed/restarted replay keeps these guards.
  static Future<void> _prepareCacheReplay(
    Database db,
    LogFolder folder,
    String privatePath,
    int version,
  ) async {
    final savedSpace = db.select(
      "SELECT value FROM metadata WHERE key='space'",
    );
    if (savedSpace.length != 1 || !isCanonicalId(savedSpace.single['value'])) {
      throw FormatFailure(
        'Old cache has no valid workspace identity. It was retained; recover the workspace before rebuilding.',
      );
    }
    if (!(await folder.list()).any(
      (file) => file.name == 'tandemlog-space.json',
    )) {
      throw FormatFailure(
        'Previously opened workspace manifest is missing. Restore it before rebuilding.',
      );
    }
    if (await _readSpace(folder) != savedSpace.single['value']) {
      throw FormatFailure('Workspace identity changed at this location.');
    }
    // A complete SQLite snapshot includes committed WAL data. It is retained
    // even if replay later finds invalid or unsupported canonical records.
    final backup = '$privatePath/cache-v$version-${const Uuid().v4()}.sqlite';
    db.execute('VACUUM INTO ?', [backup]);
    await syncParentAfterCreate(File(backup));
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final table in ['events', 'views', 'positions']) {
        db.execute('DROP TABLE IF EXISTS $table');
      }
      db.execute("DELETE FROM metadata WHERE key='order_projection'");
      db.execute(
        "INSERT OR REPLACE INTO metadata VALUES ('replay_pending','1')",
      );
      db.execute('PRAGMA user_version=10');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  EventClock? _maximumClock([String? writerId]) {
    final result = db.select(
      'SELECT clock FROM events ${writerId == null ? '' : 'WHERE writer=?'} ORDER BY clock DESC LIMIT 1',
      writerId == null ? [] : [writerId],
    );
    return result.isEmpty
        ? null
        : EventClock(BigInt.from(result.first['clock'] as int));
  }

  BigInt _nowNs() =>
      BigInt.from(now().microsecondsSinceEpoch) * BigInt.from(1000);

  void _updateClockWarning(EventClock? maximum, BigInt nowNs) {
    final threshold =
        BigInt.from(materialClockSkew.inMicroseconds) * BigInt.from(1000);
    clockWarning = maximum != null && maximum.value - nowNs > threshold
        ? 'A saved change is ahead of this device’s clock. You can keep editing; check device dates and times.'
        : null;
  }

  Future<bool> refresh() => _serialize(_refresh);

  /// Explicitly check all previously observed canonical bytes against their
  /// cached baseline/range hashes, then admit any valid new complete records.
  /// Ordinary startup, polling, resume and commands do not run this audit.
  Future<bool> verifyHistory() => _serialize(() async {
    _lastHistoryVerification = null;
    return _refresh(verify: true);
  });

  HistoryVerificationFailure _historyFailure(
    String name,
    Uint8List bytes,
    int byteOffset,
    String reason,
  ) {
    var record = 1;
    for (var i = 0; i < byteOffset && i < bytes.length; i++) {
      if (bytes[i] == 10) record++;
    }
    return HistoryVerificationFailure(name, record, byteOffset, reason);
  }

  HistoryVerificationFailure _baselineFailure(String name, Uint8List bytes) {
    final writerId = name.substring(0, name.length - 6);
    var offset = 0;
    for (final row in db.select(
      'SELECT seq,raw FROM events WHERE writer=? ORDER BY seq',
      [writerId],
    )) {
      final expected = utf8.encode('${row['raw']}\n');
      var matches = offset + expected.length <= bytes.length;
      if (matches) {
        for (var i = 0; i < expected.length; i++) {
          if (bytes[offset + i] != expected[i]) {
            matches = false;
            break;
          }
        }
      }
      if (!matches) {
        return HistoryVerificationFailure(
          name,
          row['seq'] as int,
          offset,
          'Previously imported history changed. Restore the original log before writing.',
        );
      }
      offset += expected.length;
    }
    return _historyFailure(
      name,
      bytes,
      offset,
      'Previously imported history checkpoints changed. Preserve the cache and log before recovery.',
    );
  }

  void _verifyHistoryBytes(String name, Uint8List bytes, Row row) {
    final offset = row['offset'] as int;
    final baseline = row['hash_offset'] as int;
    if (bytes.length < offset ||
        baseline < 0 ||
        baseline > offset ||
        sha256.convert(Uint8List.sublistView(bytes, 0, baseline)).toString() !=
            row['hash']) {
      throw _baselineFailure(name, bytes);
    }
    var covered = baseline;
    for (final range in db.select(
      'SELECT * FROM stream_ranges WHERE name=? ORDER BY start_offset',
      [name],
    )) {
      final start = range['start_offset'] as int;
      final end = range['end_offset'] as int;
      if (start != covered ||
          end > offset ||
          end <= start ||
          sha256.convert(Uint8List.sublistView(bytes, start, end)).toString() !=
              range['hash']) {
        throw _baselineFailure(name, bytes);
      }
      covered = end;
    }
    if (covered != offset) {
      throw _historyFailure(
        name,
        bytes,
        covered,
        'Cached history checkpoints are incomplete. Preserve the cache and log before recovery.',
      );
    }
  }

  _VerifiedWriterRecords _decodeWriterRecords(
    String name,
    Uint8List bytes,
    int completeLength,
    int start,
    int lastSeq,
    EventClock? lastClock,
    String chainHead,
    Row? checkpoint,
  ) {
    final writerName = name.substring(0, name.length - 6);
    final checkpointOffset = checkpoint?['offset'] as int?;
    final records = <_LocatedWriterRecord>[];
    var lineStart = 0;
    for (var i = 0; i < completeLength; i++) {
      if (bytes[i] != 10) continue;
      final recordOffset = start + lineStart;
      final recordNumber = lastSeq + 1;
      LogEvent event;
      String raw;
      try {
        if (i == lineStart) throw FormatFailure('Blank canonical record.');
        if (i - lineStart > 1024 * 1024) {
          throw FormatFailure('Oversized event.');
        }
        raw = utf8.decode(Uint8List.sublistView(bytes, lineStart, i));
        event = LogEvent.decode(raw);
        if (event.space != space ||
            event.writer != writerName ||
            event.sequence != lastSeq + 1 ||
            (lastClock != null && event.clock <= lastClock)) {
          throw FormatFailure('Invalid space, writer, sequence or clock.');
        }
        if (event.previousHash != chainHead) {
          throw FormatFailure(
            'Previous record hash does not match the writer chain.',
          );
        }
      } catch (failure) {
        throw HistoryVerificationFailure(
          name,
          recordNumber,
          recordOffset,
          failure is FormatFailure
              ? failure.message
              : 'Malformed canonical record.',
        );
      }
      lastSeq = event.sequence;
      lastClock = event.clock;
      chainHead = event.hash!;
      if (checkpoint != null &&
          i + 1 == checkpointOffset &&
          (chainHead != checkpoint['chain_head'] ||
              lastSeq != checkpoint['last_seq'] ||
              lastClock.value.toInt() != checkpoint['last_clock'])) {
        throw HistoryVerificationFailure(
          name,
          recordNumber,
          recordOffset,
          'Cached chain checkpoint is inconsistent with canonical history. Preserve the cache and log before recovery.',
        );
      }
      records.add(_LocatedWriterRecord(event, raw, recordOffset));
      lineStart = i + 1;
    }
    if (checkpointOffset == 0 &&
        (checkpoint!['chain_head'] != eventGenesisHash(space, writerName) ||
            checkpoint['last_seq'] != 0 ||
            checkpoint['last_clock'] != null)) {
      throw HistoryVerificationFailure(
        name,
        1,
        0,
        'Cached chain checkpoint is inconsistent with canonical history. Preserve the cache and log before recovery.',
      );
    }
    return _VerifiedWriterRecords(lastSeq, lastClock, chainHead, records);
  }

  String? _ownedRecordHash(int sequence, List<LogEvent> importedEvents) {
    if (sequence == 0) return eventGenesisHash(space, writer);
    for (final event in importedEvents) {
      if (event.writer == writer && event.sequence == sequence) {
        return event.hash;
      }
    }
    final cached = db.select(
      'SELECT raw FROM events WHERE writer=? AND seq=?',
      [writer, sequence],
    );
    return cached.isEmpty
        ? null
        : LogEvent.decode(cached.single['raw'] as String).hash;
  }

  void _validateOwnedWriterGuard(
    WriterGuardState? guardState,
    int ownedSequence,
    List<LogEvent> importedEvents,
  ) {
    if (guardState == null) return;
    if (ownedSequence < guardState.sequence ||
        _ownedRecordHash(guardState.sequence, importedEvents) !=
            guardState.hash) {
      throw WriterGuardFailure(
        'The owned writer history is behind or differs from its acknowledged safety checkpoint. Restore the acknowledged history before writing.',
      );
    }
    if (guardState.pending.isEmpty) return;
    if (ownedSequence > guardState.pending.last.sequence) {
      throw WriterGuardFailure(
        'The owned writer history differs from its unresolved prepared append. Preserve the profile and workspace before recovery.',
      );
    }
    for (final record in guardState.pending) {
      if (record.sequence <= ownedSequence &&
          _ownedRecordHash(record.sequence, importedEvents) != record.hash) {
        throw WriterGuardFailure(
          'The owned writer history differs from its unresolved prepared append. Preserve the profile and workspace before recovery.',
        );
      }
    }
  }

  Future<void> _acknowledgeWriterHead(
    WriterGuardState? guardState,
    int ownedSequence,
    String ownedHash,
  ) async {
    await writerGuard.acknowledge(space, writer, ownedSequence, ownedHash);
    _acknowledgedOwnedSequence = ownedSequence;
    _writerHasPendingAppend =
        guardState != null &&
        guardState.pending.isNotEmpty &&
        guardState.pending.last.sequence > ownedSequence;
  }

  HistoryVerificationFailure _locatedHistoryFailure(
    FormatFailure failure,
    Map<String, HistoryVerificationFailure> eventLocations,
    HistoryVerificationFailure fallback,
  ) {
    var location = fallback;
    for (final entry in eventLocations.entries) {
      if (failure.message.contains(entry.key)) {
        location = entry.value;
        break;
      }
    }
    return HistoryVerificationFailure(
      location.fileName,
      location.recordNumber,
      location.byteOffset,
      failure.message,
    );
  }

  void _validateAuditedSemantics(
    Set<String> auditedEntities,
    Map<String, HistoryVerificationFailure> eventLocations,
  ) {
    try {
      _validateUndoReferences();
      _validateMoves();
      _validateTagReferences();
      for (final entity in auditedEntities) {
        _projectEntity(entity);
      }
    } on FormatFailure catch (failure) {
      throw _locatedHistoryFailure(
        failure,
        eventLocations,
        eventLocations.values.last,
      );
    }
  }

  Future<bool> _refresh({bool verify = false}) async {
    if (await _readSpace(folder) != space) {
      throw FormatFailure('Workspace identity changed at this location.');
    }
    _updateClockWarning(_maximumClock(), _nowNs());
    final guardState = await writerGuard.load(space, writer);
    _acknowledgedOwnedSequence = guardState?.sequence ?? 0;
    _writerHasPendingAppend = guardState?.pending.isNotEmpty ?? false;
    final files = await folder.list();
    if (guardState != null &&
        guardState.sequence > 0 &&
        !files.any((file) => file.name == '$writer.jsonl')) {
      throw WriterGuardFailure(
        'Previously imported log for the acknowledged owned writer is missing. Restore the workspace history before writing.',
      );
    }
    if (files.any((f) => f.name.contains('sync-conflict'))) {
      throw FormatFailure(
        'A folder-sync conflict copy needs recovery. No history was discarded.',
      );
    }
    final logs = files.where((f) => f.name.endsWith('.jsonl')).toList();
    final names = logs.map((f) => f.name).toSet();
    for (final row in db.select('SELECT name FROM streams')) {
      if (!names.contains(row['name'])) {
        throw HistoryVerificationFailure(
          row['name'] as String,
          1,
          0,
          'Previously imported log is missing. Restore it; do not rebuild away this warning.',
        );
      }
    }
    final replay = db
        .select("SELECT value FROM metadata WHERE key='replay_pending'")
        .isNotEmpty;
    var checkedRecords = 0, checkedBytes = 0;
    final eventLocations = <String, HistoryVerificationFailure>{};
    final auditedEntities = <String>{};
    final newEvents = <LogEvent>[];
    final newEventRaws = <String>[];
    final checkpoints = <List<Object?>>[];
    final rangeCheckpoints = <List<Object?>>[];
    final fullCheckpoints = <String>[];
    for (final info in logs) {
      final writerName = info.name.substring(0, info.name.length - 6);
      if (!isCanonicalId(writerName)) {
        throw HistoryVerificationFailure(
          info.name,
          1,
          0,
          'Unrecognized log filename.',
        );
      }
      final saved = db.select('SELECT * FROM streams WHERE name=?', [
        info.name,
      ]);
      final row = saved.isEmpty ? null : saved.first;
      final offset = row == null ? 0 : row['offset'] as int;
      final observedSize = info.size != null && info.size! >= 0
          ? info.size
          : null;
      if (!verify && observedSize != null && observedSize < offset) {
        throw HistoryVerificationFailure(
          info.name,
          (row?['last_seq'] as int? ?? 0) + 1,
          offset,
          'Previously imported history was truncated. Restore the original log before writing.',
        );
      }
      final hasHead = row != null && row['chain_head'] != null;
      final reconcileOwned =
          info.name == '$writer.jsonl' &&
          (guardState == null || guardState.pending.isNotEmpty);
      if (!verify &&
          !replay &&
          !reconcileOwned &&
          hasHead &&
          folder is RangeLogFolder &&
          row['range_capable'] == 1 &&
          observedSize != null &&
          observedSize == offset) {
        continue;
      }
      Uint8List? suffix;
      final forceOwnedFull =
          info.name == '$writer.jsonl' &&
          row != null &&
          (guardState == null ||
              (guardState.pending.isNotEmpty && observedSize == offset));
      if (!verify &&
          !replay &&
          !forceOwnedFull &&
          (hasHead || row == null) &&
          observedSize != null &&
          folder is RangeLogFolder) {
        suffix = await (folder as RangeLogFolder).readFrom(info.name, offset);
      }
      var rangeCapable = suffix != null;
      final full = suffix == null || row == null;
      final bytes = suffix ?? await folder.read(info.name);
      readFiles++;
      final start = full ? 0 : offset;
      if (full && row != null) _verifyHistoryBytes(info.name, bytes, row);
      if (bytes.length + start < offset ||
          (observedSize != null && bytes.length + start < observedSize)) {
        throw HistoryVerificationFailure(
          info.name,
          (row?['last_seq'] as int? ?? 0) + 1,
          offset,
          'Previously imported history was truncated. Restore the original log before writing.',
        );
      }
      final completeLength = bytes.lastIndexOf(10) + 1;
      final end = start + completeLength;
      if (end < offset) {
        throw _historyFailure(
          info.name,
          bytes,
          completeLength,
          'Previously imported history was truncated. Restore the original log before writing.',
        );
      }
      final completeRecords = bytes
          .take(completeLength)
          .where((byte) => byte == 10)
          .length;
      if (bytes.length - completeLength > 1024 * 1024) {
        throw HistoryVerificationFailure(
          info.name,
          (full ? 0 : row['last_seq'] as int) + completeRecords + 1,
          end,
          'Oversized incomplete record.',
        );
      }
      if (info.name == '$writer.jsonl' && completeLength != bytes.length) {
        throw HistoryVerificationFailure(
          info.name,
          (full ? 0 : row['last_seq'] as int) + completeRecords + 1,
          end,
          'Interrupted local append detected. Preserve the file and recover its incomplete tail before writing.',
        );
      }
      final verified = _decodeWriterRecords(
        info.name,
        bytes,
        completeLength,
        start,
        full ? 0 : row['last_seq'] as int,
        full || row['last_clock'] == null
            ? null
            : EventClock(BigInt.from(row['last_clock'] as int)),
        full
            ? eventGenesisHash(space, writerName)
            : row['chain_head'] as String,
        full && hasHead ? row : null,
      );
      final lastSeq = verified.sequence;
      final lastClock = verified.clock;
      final chainHead = verified.hash;
      checkedRecords += verified.records.length;
      for (final record in verified.records) {
        final event = record.event;
        eventLocations[event.id] = HistoryVerificationFailure(
          info.name,
          event.sequence,
          record.byteOffset,
          'Invalid semantic history.',
        );
        auditedEntities.add(event.entity);
        if (replay || record.byteOffset >= offset) {
          newEvents.add(event);
          newEventRaws.add(record.raw);
        }
      }
      if (!rangeCapable &&
          (replay || verify || forceOwnedFull) &&
          observedSize != null &&
          bytes.length == observedSize &&
          folder is RangeLogFolder) {
        final probe = await (folder as RangeLogFolder).readFrom(
          info.name,
          bytes.length,
        );
        if (probe != null && probe.isEmpty) rangeCapable = true;
      }
      checkedBytes += bytes.length;
      final checkpoint = <Object?>[
        info.name,
        end,
        full
            ? sha256
                  .convert(Uint8List.sublistView(bytes, 0, completeLength))
                  .toString()
            : row['hash'],
        completeLength == bytes.length ? info.stamp : '',
        full ? end : row['hash_offset'],
        rangeCapable
            ? 1
            : ((verify || replay || forceOwnedFull) && row != null
                  ? row['range_capable']
                  : 0),
        chainHead,
        lastSeq,
        lastClock?.value.toInt(),
      ];
      if (!replay &&
          row != null &&
          row['offset'] == checkpoint[1] &&
          row['hash'] == checkpoint[2] &&
          row['stamp'] == checkpoint[3] &&
          row['hash_offset'] == checkpoint[4] &&
          row['range_capable'] == checkpoint[5] &&
          row['chain_head'] == checkpoint[6] &&
          row['last_seq'] == checkpoint[7] &&
          row['last_clock'] == checkpoint[8]) {
        continue;
      }
      checkpoints.add(checkpoint);
      if (full) {
        fullCheckpoints.add(info.name);
      } else if (end > offset) {
        rangeCheckpoints.add([
          info.name,
          offset,
          end,
          sha256
              .convert(Uint8List.sublistView(bytes, 0, completeLength))
              .toString(),
        ]);
      }
    }
    // The private checkpoint survives data-folder aliases and cache replacement.
    // Pending attempts read actual canonical suffixes (or the full unchanged log).
    final ownedCheckpoint = checkpoints.where(
      (checkpoint) => checkpoint[0] == '$writer.jsonl',
    );
    final savedOwned = db.select(
      'SELECT last_seq,chain_head FROM streams WHERE name=?',
      ['$writer.jsonl'],
    );
    final ownedSequence = ownedCheckpoint.isNotEmpty
        ? ownedCheckpoint.single[7] as int
        : savedOwned.isEmpty
        ? 0
        : savedOwned.single['last_seq'] as int;
    final ownedHash = ownedCheckpoint.isNotEmpty
        ? ownedCheckpoint.single[6] as String
        : savedOwned.isEmpty
        ? eventGenesisHash(space, writer)
        : savedOwned.single['chain_head'] as String;
    _validateOwnedWriterGuard(guardState, ownedSequence, newEvents);

    HistoryVerificationReport? verificationReport;
    if (verify) {
      verificationReport = HistoryVerificationReport(
        checkedLogCount: logs.length,
        checkedRecordCount: checkedRecords,
        checkedByteCount: checkedBytes,
        importedEventCount: newEvents.length,
      );
    }
    if (checkpoints.isEmpty) {
      if (verify) _validateAuditedSemantics(auditedEntities, eventLocations);
      await _acknowledgeWriterHead(guardState, ownedSequence, ownedHash);
      if (replay) db.execute("DELETE FROM metadata WHERE key='replay_pending'");
      if (verify) _lastHistoryVerification = verificationReport;
      return false;
    }
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final (index, e) in newEvents.indexed) {
        db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
          e.id,
          e.entity,
          e.writer,
          e.sequence,
          e.clock.value.toInt(),
          newEventRaws[index],
        ]);
      }
      if (newEvents.isNotEmpty) {
        _validateUndoReferences();
        _validateMoves();
        _validateTagReferences();
      }
      if (verify) _validateAuditedSemantics(auditedEntities, eventLocations);
      final affected = newEvents.map((e) => e.entity).toSet();
      for (final e in newEvents) {
        if (e.type == 'task.completed' && e.data['successor'] != null) {
          affected.add((e.data['successor'] as Map)['id'] as String);
        }
      }
      for (final e in newEvents) {
        if (e.type == 'task.recurringCompletionUndone') {
          affected.add(const Uuid().v5(e.entity, 'successor'));
        }
        if (e.type == 'task.moved' && e.data['before'] is String) {
          affected.add(e.data['before'] as String);
        }
      }
      for (final entity in affected) {
        final state = _projectEntity(entity);
        if (state != null) {
          db.execute('INSERT OR REPLACE INTO views VALUES (?,?)', [
            entity,
            jsonEncode(state),
          ]);
        }
      }
      if (affected.any(
            (entity) => db.select(
              "SELECT 1 FROM events WHERE json_extract(raw,'\$.data.successor.id')=? LIMIT 1",
              [entity],
            ).isNotEmpty,
          ) ||
          newEvents.any(
            (e) =>
                {
                  'task.created',
                  'user.created',
                  'task.completed',
                  'task.moved',
                }.contains(e.type) ||
                (e.type == 'task.operationUndone' &&
                    db.select(
                      "SELECT 1 FROM events WHERE id=? AND json_extract(raw,'\$.type')='task.moved'",
                      [e.data['operation']],
                    ).isNotEmpty),
          )) {
        _rebuildOrder();
      }
      for (final c in checkpoints) {
        db.execute(
          'INSERT OR REPLACE INTO streams (name,offset,hash,stamp,hash_offset,range_capable,chain_head,last_seq,last_clock) VALUES (?,?,?,?,?,?,?,?,?)',
          c,
        );
      }
      for (final name in fullCheckpoints) {
        db.execute('DELETE FROM stream_ranges WHERE name=?', [name]);
      }
      for (final range in rangeCheckpoints) {
        db.execute('INSERT INTO stream_ranges VALUES (?,?,?,?)', range);
      }
      db.execute("DELETE FROM metadata WHERE key='replay_pending'");
      await _acknowledgeWriterHead(guardState, ownedSequence, ownedHash);
      db.execute('COMMIT');
      cacheTransactions++;
      _updateClockWarning(_maximumClock(), _nowNs());
      if (verify) _lastHistoryVerification = verificationReport;
      return newEvents.isNotEmpty;
    } catch (failure) {
      db.execute('ROLLBACK');
      if (verify) _lastHistoryVerification = null;
      if (failure is FormatFailure &&
          failure is! HistoryVerificationFailure &&
          newEvents.isNotEmpty) {
        throw _locatedHistoryFailure(
          failure,
          eventLocations,
          eventLocations[newEvents.last.id]!,
        );
      }
      rethrow;
    }
  }

  bool hasEntity(String id) =>
      db.select('SELECT 1 FROM views WHERE id=?', [id]).isNotEmpty;

  final Map<String, int> lastReadTimings = {};
  List<Map<String, dynamic>> get rows {
    final watch = Stopwatch()..start();
    final records = db.select(
      "SELECT views.raw FROM views JOIN positions ON positions.id=views.id WHERE COALESCE(json_extract(views.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(views.raw,'\$.successorSuppressed'),0)=0 ORDER BY positions.rank",
    );
    lastReadTimings['query_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    final result = records
        .map((r) => jsonDecode(r['raw'] as String) as Map<String, dynamic>)
        .toList();
    lastReadTimings['decode_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    lastReadTimings['sort_ms'] = 0;
    return result;
  }

  /// Persist disposable sequence positions only when order-affecting history changes.
  void _rebuildOrder() {
    final ids = db
        .select("SELECT id FROM views ORDER BY json_extract(raw,'\$.order'),id")
        .map((row) => row['id'] as String);
    final retracted = retractedOperationIds(
      db
          .select(
            "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.operationUndone'",
          )
          .map((r) => LogEvent.decode(r['raw'] as String)),
    );
    final selectedSeedIds = <String, String>{};
    final actions = db
        .select(
          "SELECT id,entity,json_extract(raw,'\$.type') AS type,json_extract(raw,'\$.data.before') AS before_id,json_extract(raw,'\$.data.successor.id') AS successor FROM events WHERE json_extract(raw,'\$.type') IN ('user.created','task.created','task.completed','task.moved') ORDER BY clock,writer,seq",
        )
        .where((row) {
          if (row['type'] == 'task.moved') {
            return !retracted.contains(row['id']);
          }
          final successor = row['successor'] as String?;
          if (row['type'] == 'task.completed' && successor != null) {
            final selected = selectedSeedIds.putIfAbsent(
              successor,
              () => _entityEvents(
                successor,
              ).where((event) => event.type == 'task.created').single.id,
            );
            return selected == row['id'];
          }
          return true;
        })
        .map(
          (row) => OrderAction(
            row['entity'] as String,
            row['type'] as String,
            before: row['before_id'] as String?,
            successor: row['successor'] as String?,
          ),
        );
    final ordered = projectOrder(ids, actions);
    db.execute('DELETE FROM positions');
    for (var i = 0; i < ordered.length; i++) {
      db.execute('INSERT INTO positions VALUES (?,?)', [ordered[i], i]);
    }
    db.execute(
      "INSERT OR REPLACE INTO metadata VALUES ('order_projection','2')",
    );
  }

  /// Snapshot the completions represented by the currently displayed cache.
  /// Reopening must not cancel a completion that arrives after this observation.
  List<String> activeCompletionIds(String entity) {
    final events = db
        .select('SELECT raw FROM events WHERE entity=?', [entity])
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    final retracted = retractedOperationIds(events);
    final undone = events
        .where(
          (e) => e.type == 'task.completionUndone' && !retracted.contains(e.id),
        )
        .map((e) => e.data['completion'])
        .toSet();
    return events
        .where(
          (e) =>
              e.type == 'task.completed' &&
              !undone.contains(e.id) &&
              !retracted.contains(e.id),
        )
        .map((e) => e.id)
        .toList();
  }

  Future<void> reopen(
    String entity,
    List<String> observedCompletions, {
    void Function(OperationReceipt)? onPrepared,
  }) {
    final targets = observedCompletions.toSet();
    return _serialize(() async {
      await _refresh();
      final active = activeCompletionIds(entity).toSet();
      await _appendCommandBatch('task.completionUndone', [
        for (final target in targets.where(active.contains))
          (entity, {'completion': target}),
      ], onPrepared: onPrepared);
    });
  }

  Future<LogEvent> command(
    String entity,
    String type,
    Map<String, dynamic> data, {
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() => _command(entity, type, data, onPrepared: onPrepared));

  Future<LogEvent> _command(
    String entity,
    String type,
    Map<String, dynamic> data, {
    String? expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    await _refresh();
    _requireWriterAppendReady();
    if (expectedTaskSnapshot != null && expectedTaskSnapshot != taskSnapshot) {
      throw StaleTaskSnapshot();
    }
    final seq =
        (db.select(
              'SELECT COALESCE(MAX(seq),0) AS n FROM events WHERE writer=?',
              [writer],
            ).first['n']
            as int) +
        1;
    final writeTime = _nowNs();
    final maximum = _maximumClock();
    _updateClockWarning(maximum, writeTime);
    final clock = EventClock.next(writeTime, maximum);
    final e = _prepareCommand(entity, type, data, seq, clock);
    if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    final raw = e.canonicalRaw!;
    final receipt = OperationReceipt(e.id, raw, e.entity);
    onPrepared?.call(receipt);
    await _prepareWriterAppend([receipt]);
    await folder.append(
      '$writer.jsonl',
      Uint8List.fromList(utf8.encode('$raw\n')),
    );
    // Append alone cannot acknowledge a save: a provider replacement can keep
    // the old committed prefix while dropping this new suffix before ingestion.
    await _refresh();
    _requireConfirmed([receipt]);
    return e;
  }

  void _requireWriterAppendReady() {
    if (_writerHasPendingAppend) {
      throw WriterGuardFailure.unresolvedAppend();
    }
  }

  Future<void> _prepareWriterAppend(List<OperationReceipt> receipts) async {
    final records = receipts
        .map((receipt) => LogEvent.decode(receipt.raw))
        .toList();
    final base = records.first.sequence - 1;
    await writerGuard.prepare(
      space,
      writer,
      base,
      records.first.previousHash!,
      [
        for (final event in records)
          PreparedWriterRecord(event.sequence, event.hash!),
      ],
    );
  }

  String get _writerChainHead {
    final rows = db.select('SELECT chain_head FROM streams WHERE name=?', [
      '$writer.jsonl',
    ]);
    return rows.isEmpty
        ? eventGenesisHash(space, writer)
        : rows.single['chain_head'] as String;
  }

  LogEvent _prepareCommand(
    String entity,
    String type,
    Map<String, dynamic> data,
    int seq,
    EventClock clock, {
    String? previousHash,
  }) {
    final e = LogEvent.decode(
      LogEvent(
        space,
        writer,
        seq,
        clock,
        entity,
        type,
        data,
      ).encode(previousHash: previousHash ?? _writerChainHead),
    );
    final prior = _entityEvents(entity);
    final projected = project([...prior, e]);
    if (projected == null) {
      throw FormatFailure('Local command requires an existing entity.');
    }
    if (type.startsWith('task.') &&
        type != 'task.created' &&
        type != 'task.operationUndone' &&
        type != 'task.recurringCompletionUndone' &&
        project(prior)?['deleted'] == true) {
      throw FormatFailure('This task was deleted.');
    }
    if ((type == 'task.created' ||
            (type == 'task.edited' && data.containsKey('assignee'))) &&
        db.select(
          "SELECT id FROM views WHERE id=? AND json_extract(raw,'\$.kind')='user'",
          [data['assignee']],
        ).isEmpty) {
      throw FormatFailure('Choose an existing user before creating a task.');
    }
    if (type == 'task.completionUndone' ||
        type == 'task.operationUndone' ||
        type == 'task.recurringCompletionUndone') {
      final field = type == 'task.operationUndone' ? 'operation' : 'completion';
      if (!prior.any((target) => target.id == data[field])) {
        throw FormatFailure('Undo requires an earlier operation of this task.');
      }
    }
    _validateUndoReferences(e);
    _validateMoves(e);
    _validateTagReferences(e);
    if (type == 'task.completed' &&
        data['successor'] == null &&
        TaskSchedule.fromJson(
              Map<String, dynamic>.from(project(prior)!['schedule'] as Map),
            ).recurrence !=
            null) {
      throw FormatFailure('Repeating completion requires a next occurrence.');
    }
    if (type == 'task.completed' && data['successor'] != null) {
      final current = TaskSchedule.fromJson(
        Map<String, dynamic>.from(project(prior)!['schedule'] as Map),
      );
      final successor = TaskSchedule.fromJson(
        Map<String, dynamic>.from(
          (data['successor'] as Map)['schedule'] as Map,
        ),
      );
      if (current.recurrence != null &&
          current.hasSameOccurrenceDates(successor)) {
        throw FormatFailure(unchangedRecurrenceMessage);
      }
      final successorId = (data['successor'] as Map)['id'];
      if (db.select(
        "SELECT id FROM events WHERE entity=? AND json_extract(raw,'\$.type') IN ('task.created','user.created')",
        [successorId],
      ).isNotEmpty) {
        throw FormatFailure(
          'Successor identity collides with existing entity.',
        );
      }
    }
    return e;
  }

  /// Unchanged per-event JSONL protocol, one flushed append and cache commit.
  /// This is not a crash-atomic multi-event transaction. On failure exact raw
  /// receipts establish acknowledged progress; an incomplete owned tail blocks
  /// writes and is retained by the existing integrity/recovery policy.
  Future<List<OperationReceipt>> _appendCommandBatch(
    String type,
    List<(String, Map<String, dynamic>)> commands, {
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _appendCommands(
    [for (final (entity, data) in commands) (entity, type, data)],
    canCommit: canCommit,
    onPrepared: onPrepared,
  );

  Future<List<OperationReceipt>> _appendCommands(
    List<(String, String, Map<String, dynamic>)> commands, {
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    if (commands.isEmpty) return [];
    _requireWriterAppendReady();
    final phase = Stopwatch()..start();
    final transactions = cacheTransactions;
    var seq =
        (db.select(
              'SELECT COALESCE(MAX(seq),0) AS n FROM events WHERE writer=?',
              [writer],
            ).first['n']
            as int) +
        1;
    var maximum = _maximumClock();
    final receipts = <OperationReceipt>[];
    final bytes = BytesBuilder(copy: false);
    var chainHead = _writerChainHead;
    for (final (entity, type, data) in commands) {
      final wall = _nowNs();
      _updateClockWarning(maximum, wall);
      final clock = EventClock.next(wall, maximum);
      final event = _prepareCommand(
        entity,
        type,
        data,
        seq++,
        clock,
        previousHash: chainHead,
      );
      final raw = event.canonicalRaw!;
      chainHead = event.hash!;
      receipts.add(OperationReceipt(event.id, raw, entity));
      bytes.add(utf8.encode('$raw\n'));
      maximum = clock;
    }
    final preparedUs = phase.elapsedMicroseconds;
    if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    for (final receipt in receipts) {
      onPrepared?.call(receipt);
    }
    if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    await _prepareWriterAppend(receipts);
    phase.reset();
    try {
      await folder.append('$writer.jsonl', bytes.takeBytes());
    } finally {
      lastBatchTiming = {
        'tasks': commands.length,
        'prepare_us': preparedUs,
        'append_us': phase.elapsedMicroseconds,
        'cache_transactions': 0,
      };
    }
    phase.reset();
    try {
      await _refresh();
    } finally {
      lastBatchTiming!['reconcile_us'] = phase.elapsedMicroseconds;
      lastBatchTiming!['cache_transactions'] = cacheTransactions - transactions;
    }
    _requireConfirmed(receipts);
    return receipts;
  }

  /// Retry identities belong to the same capture; already present tasks are
  /// acknowledged without recreating them. UI updates happen after this batch.
  Future<BulkTaskResult> createTasks(
    Map<String, String> titles,
    String assignee,
  ) => _serialize(() async {
    await _refresh();
    final present = <String>[];
    final commands = <(String, Map<String, dynamic>)>[];
    for (final entry in titles.entries) {
      if (hasEntity(entry.key)) {
        final current = project(_entityEvents(entry.key));
        if (current?['kind'] != 'task') {
          throw FormatFailure('Capture identity is not a task.');
        }
        present.add(entry.key);
      } else {
        commands.add((
          entry.key,
          {'title': entry.value, 'description': '', 'assignee': assignee},
        ));
      }
    }
    final prepared = <OperationReceipt>[];
    Object? error;
    try {
      await _appendCommandBatch(
        'task.created',
        commands,
        onPrepared: prepared.add,
      );
    } catch (failure) {
      error = failure;
      try {
        await _refresh();
      } catch (_) {
        /* Preserve uncertain draft and logs. */
      }
    }
    final confirmed = confirmedOperations(prepared);
    final committed = {
      ...present,
      for (final receipt in prepared.where((r) => confirmed.contains(r.id)))
        receipt.entity,
    };
    return BulkTaskResult(
      titles.keys.where(committed.contains),
      titles.keys.where((id) => !committed.contains(id)),
      error,
    );
  });

  void _validateUndoReferences([LogEvent? pending]) {
    // A join revalidates resolved references, including newly imported targets.
    final invalid = db.select(
      "SELECT u.id FROM events u JOIN events t ON t.id=CASE WHEN json_extract(u.raw,'\$.type')='task.operationUndone' THEN json_extract(u.raw,'\$.data.operation') ELSE json_extract(u.raw,'\$.data.completion') END WHERE json_extract(u.raw,'\$.type') IN ('task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND (u.entity<>t.entity OR t.clock>=u.clock OR (json_extract(u.raw,'\$.type')='task.completionUndone' AND json_extract(t.raw,'\$.type')<>'task.completed') OR (json_extract(u.raw,'\$.type')='task.recurringCompletionUndone' AND (json_extract(t.raw,'\$.type')<>'task.completed' OR json_extract(t.raw,'\$.data.successor.id') IS NULL)) OR (json_extract(u.raw,'\$.type')='task.operationUndone' AND (json_extract(t.raw,'\$.type') NOT IN ('task.edited','task.moved','task.deleted','task.completed','task.completionUndone') OR (json_extract(t.raw,'\$.type')='task.completed' AND json_extract(t.raw,'\$.data.successor') IS NOT NULL)))) LIMIT 1",
    );
    if (invalid.isNotEmpty) {
      throw FormatFailure('Invalid undo reference in ${invalid.single['id']}.');
    }
    if (pending == null) return;
    void validate(LogEvent undo, LogEvent target) {
      final operation = undo.type == 'task.operationUndone';
      if (target.entity != undo.entity ||
          target.clock >= undo.clock ||
          (operation
              ? (!reversibleTaskEvents.contains(target.type) ||
                    (target.type == 'task.completed' &&
                        target.data['successor'] != null))
              : target.type != 'task.completed') ||
          (undo.type == 'task.recurringCompletionUndone' &&
              target.data['successor'] == null)) {
        throw FormatFailure('Invalid undo reference in ${undo.id}.');
      }
    }

    if (pending.type == 'task.operationUndone' ||
        pending.type == 'task.completionUndone' ||
        pending.type == 'task.recurringCompletionUndone') {
      final ref =
          pending.data[pending.type == 'task.operationUndone'
              ? 'operation'
              : 'completion'];
      final targets = db.select('SELECT raw FROM events WHERE id=?', [ref]);
      if (targets.isNotEmpty) {
        validate(pending, LogEvent.decode(targets.single['raw'] as String));
      }
    }
    for (final row in db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.type') IN ('task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND COALESCE(json_extract(raw,'\$.data.operation'),json_extract(raw,'\$.data.completion'))=?",
      [pending.id],
    )) {
      validate(LogEvent.decode(row['raw'] as String), pending);
    }
  }

  void _validateMoves([LogEvent? pending]) {
    final moves = db
        .select(
          pending == null
              ? "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.moved'"
              : "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.moved' AND json_extract(raw,'\$.data.before')=?",
          pending == null ? [] : [pending.entity],
        )
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    if (pending?.type == 'task.moved') moves.add(pending!);
    for (final move in moves) {
      final anchor = move.data['before'];
      if (anchor == null) continue;
      final events = _entityEvents(anchor as String);
      if (pending?.entity == anchor) events.add(pending!);
      final target = project(events);
      if (target != null && target['kind'] != 'task') {
        throw FormatFailure('Task order anchor is not a task in ${move.id}.');
      }
      if (move == pending && target == null) {
        throw FormatFailure('Task order anchor is missing in ${move.id}.');
      }
    }
  }

  void _validateTagReferences([LogEvent? pending]) {
    // Full ingestion validates all newly joined references. Local preparation
    // only needs mutations referencing this new event (or its derived seed),
    // plus the new mutation itself. Do not repeatedly decode unrelated history.
    final successor =
        pending?.type == 'task.completed' && pending?.data['successor'] is Map
        ? (pending!.data['successor'] as Map)['id']
        : null;
    final mutations = db
        .select(
          pending == null
              ? "SELECT raw FROM events WHERE json_extract(raw,'\$.data.tagChanges') IS NOT NULL"
              : "SELECT raw FROM events e WHERE EXISTS (SELECT 1 FROM json_each(json_extract(e.raw,'\$.data.tagChanges.remove')) r WHERE r.value LIKE ?) OR e.entity=?",
          pending == null ? [] : ['${pending.id}:%', successor],
        )
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    if (pending != null) mutations.add(pending);
    for (final mutation in mutations) {
      final changes = mutation.data['tagChanges'];
      if (changes == null) continue;
      for (final token in (changes['remove'] as List).cast<String>()) {
        final pieces = token.split(':');
        final eventId = '${pieces[0]}:${pieces[1]}';
        final index = int.tryParse(pieces[2]);
        final rows = db.select('SELECT raw FROM events WHERE id=?', [eventId]);
        final target = pending?.id == eventId
            ? pending
            : rows.isEmpty
            ? null
            : LogEvent.decode(rows.first['raw'] as String);
        if (target == null) {
          final seeds = db.select(
            "SELECT raw FROM events WHERE json_extract(raw,'\$.data.successor.id')=?",
            [mutation.entity],
          );
          final matches = <LogEvent>[];
          for (final row in seeds) {
            final seed = LogEvent.decode(row['raw'] as String);
            final tags = (seed.data['successor'] as Map)['tags'] as List? ?? [];
            if (tags.any(
              (tag) =>
                  '${const Uuid().v5(mutation.entity, 'tag:$tag')}:1:0' ==
                  token,
            )) {
              matches.add(seed);
            }
          }
          if (pending?.type == 'task.completed' &&
              pending?.data['successor'] != null) {
            final successor = pending!.data['successor'] as Map;
            if (successor['id'] == mutation.entity &&
                (successor['tags'] as List? ?? []).any(
                  (tag) =>
                      '${const Uuid().v5(mutation.entity, 'tag:$tag')}:1:0' ==
                      token,
                )) {
              matches.add(pending);
            }
          }
          if (matches.isNotEmpty &&
              matches.every((seed) => seed.clock >= mutation.clock)) {
            throw FormatFailure(
              'Invalid future derived tag reference in ${mutation.id}.',
            );
          }
          continue; // delayed dependency or stable derived seed tag
        }
        List? additions;
        final owner = target.entity;
        if (target.type == 'task.created') {
          additions = target.data['tags'] as List? ?? [];
        }
        if (target.type == 'task.edited' && target.data['tagChanges'] != null) {
          additions = (target.data['tagChanges'] as Map)['add'] as List;
        }
        if (owner != mutation.entity ||
            target.clock >= mutation.clock ||
            additions == null ||
            index == null ||
            index < 0 ||
            index >= additions.length) {
          throw FormatFailure(
            'Invalid observed tag reference in ${mutation.id}.',
          );
        }
      }
    }
  }

  /// A successor is a deterministic materialized entity, never a replay append.
  List<LogEvent> _entityEvents(String entity) {
    final own = db
        .select('SELECT raw FROM events WHERE entity=?', [entity])
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    final seeds = db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
      [entity],
    );
    if (seeds.isNotEmpty) {
      if (own.any(
        (e) => e.type == 'task.created' || e.type == 'user.created',
      )) {
        final creations = own
            .where(
              (event) =>
                  event.type == 'task.created' || event.type == 'user.created',
            )
            .toList();
        creations.add(LogEvent.decode(seeds.first['raw'] as String));
        creations.sort(compareEvents);
        throw FormatFailure(
          'Successor identifier collides with existing entity in ${creations.last.id}.',
        );
      }
      own.add(successorCreation(_successorSelection(entity, seeds, own).seed));
    }
    return own;
  }

  SuccessorSelection _successorSelection(
    String entity,
    ResultSet seeds,
    List<LogEvent> own,
  ) {
    final decoded = seeds
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    final parent = decoded.first.entity;
    final parentHistory = db
        .select('SELECT raw FROM events WHERE entity=?', [parent])
        .map((r) => LogEvent.decode(r['raw'] as String));
    final anchored = db.select(
      "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='task.moved' AND json_extract(raw,'\$.data.before')=? LIMIT 1",
      [entity],
    ).isNotEmpty;
    return selectSuccessor(
      decoded,
      parentHistory,
      protected: own.isNotEmpty || anchored,
    );
  }

  Map<String, dynamic>? _projectEntity(String entity) {
    final history = _entityEvents(entity);
    Map<String, dynamic>? state;
    try {
      state = project(history);
    } on FormatFailure catch (failure) {
      final ordered = history.toList()..sort(compareEvents);
      final candidates = failure.message.startsWith('Duplicate entity creation')
          ? ordered
                .where(
                  (event) =>
                      event.type == 'task.created' ||
                      event.type == 'user.created',
                )
                .skip(1)
          : ordered.where((event) => event.type.startsWith('task.'));
      if (candidates.isEmpty) rethrow;
      throw FormatFailure('${failure.message} In ${candidates.first.id}.');
    }
    if (state == null) return null;
    final seeds = db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
      [entity],
    );
    if (seeds.isNotEmpty) {
      final own = db
          .select('SELECT raw FROM events WHERE entity=?', [entity])
          .map((r) => LogEvent.decode(r['raw'] as String))
          .toList();
      state['successorSuppressed'] = _successorSelection(
        entity,
        seeds,
        own,
      ).suppressed;
    }
    return state;
  }

  Future<LogEvent> complete(
    String entity, {
    DateTime? completionDay,
    DateTime? completionInstant,
    String? localZoneId,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    final state = project(_entityEvents(entity));
    if (state == null || state['kind'] != 'task' || state['deleted'] == true) {
      throw FormatFailure('Unknown task.');
    }
    final schedule = TaskSchedule.fromJson(
      Map<String, dynamic>.from(state['schedule'] as Map),
    );
    if ((completionDay == null) == (completionInstant == null)) {
      throw ArgumentError('Supply exactly one completion day or instant.');
    }
    final day =
        completionDay ??
        civilDayAt(completionInstant!, schedule.timeZone ?? localZoneId);
    final data = <String, dynamic>{
      'completedAt':
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    };
    if (schedule.recurrence != null) {
      final next = schedule.next(day);
      if (schedule.hasSameOccurrenceDates(next)) {
        throw FormatFailure(unchangedRecurrenceMessage);
      }
      data['successor'] = {
        'id': const Uuid().v5(entity, 'successor'),
        'title': state['title'],
        'description': state['description'],
        'assignee': state['assignee'],
        'tags': state['tags'],
        'schedule': next.toJson(),
      };
    }
    return _command(
      entity,
      'task.completed',
      data,
      expectedTaskSnapshot: taskSnapshot,
      onPrepared: onPrepared,
    );
  });

  /// Immutable comparison token for current task content and global order.
  /// User-only changes do not invalidate a task move. No display policy lives
  /// here: callers separately validate filters/time-dependent move eligibility.
  String get taskSnapshot =>
      jsonEncode(rows.where((row) => row['kind'] == 'task').toList());

  /// Optional synchronous guard checks caller-owned conditions after ingestion
  /// and immediately before append. It must not mutate this store.
  Future<LogEvent> moveBefore(
    String entity,
    String? before, {
    String? expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(
    () => _command(
      entity,
      'task.moved',
      {'before': before},
      expectedTaskSnapshot: expectedTaskSnapshot,
      canCommit: canCommit,
      onPrepared: onPrepared,
    ),
  );

  Future<LogEvent> edit(
    String entity,
    Map<String, dynamic> fields, {
    required List<String> tags,
    required Map<String, String> observedTagRefs,
    String? expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    final wanted = tags.toSet();
    final removed = observedTagRefs.entries
        .where((e) => !wanted.contains(e.value))
        .map((e) => e.key)
        .toList();
    final added = wanted.difference(observedTagRefs.values.toSet()).toList()
      ..sort();
    return _command(
      entity,
      'task.edited',
      {
        ...fields,
        if (added.isNotEmpty || removed.isNotEmpty)
          'tagChanges': {'add': added, 'remove': removed},
      },
      expectedTaskSnapshot: expectedTaskSnapshot,
      canCommit: canCommit,
      onPrepared: onPrepared,
    );
  });

  List<Map<String, dynamic>> _selection(List<String> ids) {
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw FormatFailure('Choose distinct tasks.');
    }
    final tasks = rows
        .where((r) => r['kind'] == 'task' && ids.contains(r['id']))
        .toList();
    if (tasks.length != ids.length) {
      throw FormatFailure('Selection contains a missing or deleted task.');
    }
    return tasks;
  }

  Future<BulkTaskResult> _bulk(
    List<String> ids,
    String type,
    Map<String, Map<String, dynamic>> Function(List<Map<String, dynamic>>)
    prepare, {
    required String expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    if (taskSnapshot != expectedTaskSnapshot ||
        (canCommit != null && !canCommit())) {
      throw StaleTaskSnapshot();
    }
    final selected = _selection(ids);
    final commands = prepare(selected);
    final prepared = <OperationReceipt>[];
    Object? error;
    try {
      await _appendCommandBatch(
        type,
        [for (final entry in commands.entries) (entry.key, entry.value)],
        canCommit: canCommit,
        onPrepared: (receipt) {
          prepared.add(receipt);
          onPrepared?.call(receipt);
        },
      );
    } catch (failure) {
      error = failure;
      try {
        await _refresh();
      } catch (_) {
        /* No false acknowledgement. */
      }
    }
    final confirmed = confirmedOperations(prepared);
    final committed = {
      for (final receipt in prepared.where((r) => confirmed.contains(r.id)))
        receipt.entity,
    };
    return BulkTaskResult(
      commands.keys.where(committed.contains),
      commands.keys.where((id) => !committed.contains(id)),
      error,
    );
  });

  Future<BulkTaskResult> bulkEdit(
    List<String> ids,
    BulkTaskEdit edit, {
    required String expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _bulk(
    ids,
    'task.edited',
    (tasks) => {
      for (final task in tasks)
        if (edit.fieldsFor(task).isNotEmpty)
          task['id'] as String: edit.fieldsFor(task),
    },
    expectedTaskSnapshot: expectedTaskSnapshot,
    canCommit: canCommit,
    onPrepared: onPrepared,
  );

  /// A receipt requires its exact canonical bytes and a durable private
  /// acknowledgment. Unobserved prepared records retain their reserved sequence.
  Set<String> confirmedOperations(Iterable<OperationReceipt> receipts) => {
    for (final r in receipts)
      if (r.id.startsWith('$writer:') &&
          (int.tryParse(r.id.substring(writer.length + 1)) ??
                  9007199254740991) <=
              _acknowledgedOwnedSequence &&
          db.select('SELECT 1 FROM events WHERE id=? AND raw=?', [
            r.id,
            r.raw,
          ]).isNotEmpty)
        r.id,
  };

  void _requireConfirmed(List<OperationReceipt> receipts) {
    if (confirmedOperations(receipts).length != receipts.length) {
      throw FolderAccessFailure(
        'The folder changed before the new records could be confirmed. Review the current tasks and retry.',
      );
    }
  }

  bool _operationUndone(String id) => db.select(
    "SELECT 1 FROM events WHERE (json_extract(raw,'\$.type')='task.operationUndone' AND json_extract(raw,'\$.data.operation')=?) OR (json_extract(raw,'\$.type')='task.recurringCompletionUndone' AND json_extract(raw,'\$.data.completion')=?)",
    [id, id],
  ).isNotEmpty;

  Future<TaskUndoResult> undoOperations(
    List<String> operations,
  ) => _serialize(() async {
    await _refresh();
    if (operations.isEmpty || operations.toSet().length != operations.length) {
      throw FormatFailure('Choose distinct saved operations.');
    }
    final targets = <String, LogEvent>{};
    for (final id in operations) {
      final found = db.select('SELECT raw FROM events WHERE id=?', [id]);
      if (found.isEmpty) {
        throw FormatFailure('The saved operation is unavailable.');
      }
      final event = LogEvent.decode(found.single['raw'] as String);
      if (!reversibleTaskEvents.contains(event.type)) {
        throw FormatFailure('This operation cannot be undone.');
      }
      targets[id] = event;
    }
    var newer = false;
    final alreadyUndone = <String>{};
    for (final id in operations) {
      final target = targets[id]!;
      final history = _entityEvents(target.entity);
      final inactive = retractedOperationIds(history);
      newer |= history.any(
        (e) =>
            reversibleTaskEvents.contains(e.type) &&
            compareEvents(e, target) > 0 &&
            !inactive.contains(e.id),
      );
      if (_operationUndone(id)) alreadyUndone.add(id);
    }
    final prepared = <OperationReceipt>[];
    Object? error;
    try {
      await _appendCommands([
        for (final id in operations.where((id) => !alreadyUndone.contains(id)))
          targets[id]!.type == 'task.completed' &&
                  targets[id]!.data['successor'] != null
              ? (
                  targets[id]!.entity,
                  'task.recurringCompletionUndone',
                  {'completion': id},
                )
              : (
                  targets[id]!.entity,
                  'task.operationUndone',
                  {'operation': id},
                ),
      ], onPrepared: prepared.add);
    } catch (failure) {
      error = failure;
      try {
        await _refresh();
      } catch (_) {
        /* Preserve uncertain history. */
      }
    }
    final confirmed = confirmedOperations(prepared);
    final undone = {
      ...alreadyUndone,
      for (final receipt in prepared.where((r) => confirmed.contains(r.id)))
        (LogEvent.decode(receipt.raw).data['operation'] ??
                LogEvent.decode(receipt.raw).data['completion'])
            as String,
    };
    final successors = {
      for (final id in operations.where(undone.contains))
        if (targets[id]!.type == 'task.completed' &&
            targets[id]!.data['successor'] != null)
          (targets[id]!.data['successor'] as Map)['id'] as String,
    };
    final suppressed = successors
        .where((id) => _projectEntity(id)?['successorSuppressed'] == true)
        .length;
    return TaskUndoResult(
      operations.where(undone.contains),
      operations.where((id) => !undone.contains(id)),
      newer,
      error: error,
      retainedSuccessorCount: successors.length - suppressed,
      removedSuccessorCount: suppressed,
    );
  });

  Future<BulkTaskResult> deleteTasks(
    List<String> ids, {
    required String expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _bulk(
    ids,
    'task.deleted',
    (tasks) => {
      for (final task in tasks) task['id'] as String: <String, dynamic>{},
    },
    expectedTaskSnapshot: expectedTaskSnapshot,
    canCommit: canCommit,
    onPrepared: onPrepared,
  );

  Future<LogEvent> deleteTask(
    String id, {
    required String expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(
    () => _command(
      id,
      'task.deleted',
      {},
      expectedTaskSnapshot: expectedTaskSnapshot,
      canCommit: canCommit,
      onPrepared: onPrepared,
    ),
  );

  /// Input order is ignored: preserve selected tasks' current global order.
  /// Caller guard checks the effective date/filter key immediately before commits.
  Future<BulkTaskResult> moveBlockBefore(
    List<String> ids,
    String? before, {
    required String expectedTaskSnapshot,
    required bool Function() canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _bulk(
    ids,
    'task.moved',
    (tasks) {
      if (ids.contains(before)) {
        throw FormatFailure('Order anchor is selected.');
      }
      if (before != null &&
          !rows.any((r) => r['id'] == before && r['kind'] == 'task')) {
        throw FormatFailure('Order anchor is missing.');
      }
      return {
        for (final task in tasks) task['id'] as String: {'before': before},
      };
    },
    expectedTaskSnapshot: expectedTaskSnapshot,
    canCommit: canCommit,
    onPrepared: onPrepared,
  );

  Future<void> close() {
    _closed = true;
    return _closing ??= _queue.then((_) async {
      try {
        db.close();
      } finally {
        await lock.close();
      }
    });
  }
}

class _LocatedWriterRecord {
  final LogEvent event;
  final String raw;
  final int byteOffset;
  const _LocatedWriterRecord(this.event, this.raw, this.byteOffset);
}

class _VerifiedWriterRecords {
  final int sequence;
  final EventClock? clock;
  final String hash;
  final List<_LocatedWriterRecord> records;
  const _VerifiedWriterRecords(
    this.sequence,
    this.clock,
    this.hash,
    this.records,
  );
}
