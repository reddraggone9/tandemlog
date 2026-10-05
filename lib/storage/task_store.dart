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
import '../text/native_text_engine.dart';
import '../text/recurring_text.dart';
import 'text_cache.dart';
import '../domain/text_context.dart';
import '../domain/text_actor.dart';
export 'writer_guard.dart';

Map<String, dynamic>? calculateTaskTagChanges(
  List<String> tags,
  Map<String, String> observedTagRefs,
) {
  final wanted = tags.toSet();
  final removed = observedTagRefs.entries
      .where((entry) => !wanted.contains(entry.value))
      .map((entry) => entry.key)
      .toList();
  final added = wanted.difference(observedTagRefs.values.toSet()).toList()
    ..sort();
  return added.isEmpty && removed.isEmpty
      ? null
      : {'add': added, 'remove': removed};
}

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

class TaskTextFieldCapture {
  const TaskTextFieldCapture({
    required this.field,
    required this.context,
    required this.allocation,
    required this.actor,
    required this.document,
    required this.undoAllocation,
    required this.undoActor,
  });
  final String field, context, allocation, undoAllocation;
  final int actor, undoActor;
  final NativeTextDocument document;
}

class TaskTextCapture {
  const TaskTextCapture(this.entity, this.fields, {required this.writer});
  final String entity, writer;
  final Map<String, TaskTextFieldCapture> fields;
}

class _NativeTextOperation {
  _NativeTextOperation(this.receipt, this.capture, this.fields, this.owners);
  final OperationReceipt receipt;
  final TaskTextCapture capture;
  final List<String> fields;
  final Map<String, _NativeUndoField> owners;
  Map<String, NativeTextPreparedUndo>? prepared;
  OperationReceipt? compensation;
}

class _NativeUndoField {
  _NativeUndoField(
    this.entity,
    this.field,
    this.context,
    this.allocation,
    this.actor,
    this.document,
  );
  final String entity, field;
  final Set<String> applied = {};
  final String context, allocation;
  final int actor;
  final NativeTextDocument document;
}

/// Owns durable log ingestion and one disposable SQLite materialization.
class TaskStore {
  final LogFolder folder;
  final Database db;
  final String writer;
  final ProfileLock lock;
  final WriterGuard writerGuard;
  final NativeTextEngine? textEngine;
  final String privatePath;
  String? textWriteBlocked;
  LogEvent? _textBaseline;
  final List<TaskTextCapture> _textCaptures = [];
  final Map<NativeTextDocument, Set<int>> _capturedLocalActors = {};
  final Map<NativeTextDocument, Set<String>> _capturedApplied = {};
  final Map<String, _NativeTextOperation> _nativeOperations = {};
  final Map<String, Map<String, Map<String, dynamic>>> _preparedTextBases = {};
  final Map<NativeTextDocument, List<String>> _nativeUndoStacks = {};
  final Map<String, _NativeUndoField> _nativeUndoFields = {};
  static const _textTypes = {
    'task.createdWithText',
    'task.completedWithText',
    'task.textEdited',
    'task.textEditUndone',
    'text.baselineInitialized',
  };
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
    this.textEngine,
    this.privatePath,
  );
  static Future<TaskStore> open(
    LogFolder folder,
    String privatePath, {
    void Function(String, int)? onTiming,
    DateTime Function()? now,
    String? writerIdentity,
    WriterGuard? writerGuard,
    NativeTextEngine? textEngine,
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
      if (version < 0 || version > 14) {
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
        db.execute(
          'CREATE TABLE IF NOT EXISTS text_fields (entity TEXT NOT NULL, field TEXT NOT NULL, context TEXT NOT NULL, codec TEXT NOT NULL, adapter INTEGER NOT NULL, seed_hash TEXT NOT NULL, state BLOB NOT NULL, state_hash TEXT NOT NULL, frontier TEXT NOT NULL, PRIMARY KEY(entity,field))',
        );
        db.execute(
          'CREATE TABLE IF NOT EXISTS text_actors (context TEXT NOT NULL, actor INTEGER NOT NULL, writer TEXT NOT NULL, allocation TEXT NOT NULL, PRIMARY KEY(context,actor))',
        );
        db.execute(
          'CREATE TABLE IF NOT EXISTS text_outbox (id TEXT PRIMARY KEY, raw TEXT NOT NULL, entity TEXT NOT NULL)',
        );
        db.execute(
          'PRAGMA user_version=${textEngine != null || version == 14 ? 14 : 13}',
        );
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
        textEngine,
        privatePath,
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
      await store._restoreTextIntents();
      await store.refresh();
      if (textEngine == null &&
          db
              .select(
                "SELECT 1 FROM events WHERE json_extract(raw,'\$.type') IN ('task.createdWithText','task.completedWithText','task.textEdited','task.textEditUndone','text.baselineInitialized') LIMIT 1",
              )
              .isNotEmpty) {
        throw FormatFailure(
          'Native text support is required. Update the app; history was preserved.',
        );
      }
      if (textEngine != null) store._validateTextBaseline();
      final orderVersion = db.select(
        "SELECT value FROM metadata WHERE key='order_projection'",
      );
      if (orderVersion.isEmpty ||
          orderVersion.single['value'] != '3' ||
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
      await _retireConfirmedTextIntents();
      return false;
    }
    final originalBaseline = _textBaseline;
    final originalTextBlocked = textWriteBlocked;
    var committed = false;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final (index, e) in newEvents.indexed) {
        if (_textTypes.contains(e.type) && textEngine == null) {
          throw FormatFailure(
            'Native text support is required. Update the app; history was preserved.',
          );
        }
        db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
          e.id,
          e.entity,
          e.writer,
          e.sequence,
          e.clock.value.toInt(),
          newEventRaws[index],
        ]);
        db.execute('DELETE FROM text_outbox WHERE id=? AND raw=?', [
          e.id,
          newEventRaws[index],
        ]);
      }
      final oldBaseline = _textBaseline?.id;
      if (newEvents.isNotEmpty) {
        if (textEngine != null) {
          TextCache(db, textEngine!).validatePackets(newEvents);
        }
        _validateTextBaseline();
        _validateUndoReferences();
        _validateMoves();
        _validateTagReferences();
      }
      if (verify) _validateAuditedSemantics(auditedEntities, eventLocations);
      final affected = newEvents.map((e) => e.entity).toSet();
      if (newEvents.any((event) => event.type == 'text.baselineInitialized') ||
          oldBaseline != _textBaseline?.id) {
        affected.addAll(
          db.select('SELECT id FROM views').map((row) => row['id'] as String),
        );
      }
      for (final e in newEvents) {
        if (isTaskCompletion(e.type) && e.data['successor'] != null) {
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
      affected.addAll(
        db
            .select(
              "SELECT id FROM views WHERE json_extract(raw,'\$.textInheritancePending')=1",
            )
            .map((row) => row['id'] as String),
      );
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
                  'task.createdWithText',
                  'user.created',
                  'task.completed',
                  'task.completedWithText',
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
      committed = true;
      cacheTransactions++;
      _updateCapturedTextDocuments(newEvents, affected);
      _updateNativeUndoOwners(newEvents, affected);
      // Cleanup is dispensable: exact canonical receipts are already committed.
      // A failed deletion leaves the immutable intent available next startup.
      try {
        await _retireConfirmedTextIntents();
      } on FileSystemException {
        // Preserve the file; it cannot authorize a different prepared event.
      }
      _updateClockWarning(_maximumClock(), _nowNs());
      if (verify) _lastHistoryVerification = verificationReport;
      return newEvents.isNotEmpty;
    } catch (failure) {
      if (committed) rethrow;
      db.execute('ROLLBACK');
      _textBaseline = originalBaseline;
      textWriteBlocked = originalTextBlocked;
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

  Future<TaskTextCapture> captureTaskText(
    String entity,
  ) => _serialize(() async {
    await _refresh();
    if (textEngine == null) {
      throw FormatFailure('Native text support is unavailable.');
    }
    final history = _entityEvents(entity);
    final task = project(history);
    if (task == null || task['kind'] != 'task' || task['deleted'] == true) {
      throw FormatFailure('Unknown or deleted task.');
    }
    final native = _hasNativeTextRoot(entity, history);
    if (!native && (_textBaseline == null || textWriteBlocked != null)) {
      throw FormatFailure(
        textWriteBlocked ??
            'Initialize shared text before editing this existing task.',
      );
    }
    if (!native &&
        history.any(
          (event) => event.type == 'task.created' && event.canonicalRaw == null,
        ) &&
        project(_baselineEntityHistory(entity, _textBaseline!)) == null) {
      throw FormatFailure(
        'This recurring occurrence is waiting for a verified native text creation context.',
      );
    }
    // Verify the lazily opened field checkpoints against their canonical
    // context and operation frontier; corrupt disposable state rebuilds.
    db.execute('BEGIN IMMEDIATE');
    try {
      _materializeText(task, history);
      if (task['textUnavailable'] != null) {
        throw TextInheritancePending(task['textUnavailable'] as String);
      }
      db.execute('INSERT OR REPLACE INTO views VALUES (?,?)', [
        entity,
        jsonEncode(task),
      ]);
      db.execute('COMMIT');
      cacheTransactions++;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    final fields = <String, TaskTextFieldCapture>{};
    try {
      for (final field in ['title', 'description']) {
        final rows = db.select(
          'SELECT * FROM text_fields WHERE entity=? AND field=?',
          [entity, field],
        );
        if (rows.isEmpty) {
          throw FormatFailure(
            'Native text is waiting for its initialization history.',
          );
        }
        final row = rows.single;
        final state = row['state'] as Uint8List;
        if (row['codec'] != 'yrs-v1' ||
            row['adapter'] != 1 ||
            sha256.convert(state).toString() != row['state_hash']) {
          throw FormatFailure(
            'Native text checkpoint needs a verified cache rebuild.',
          );
        }
        final context = row['context'] as String;
        final allocation = const Uuid().v4();
        final actor = deriveTextActor(context, writer, allocation);
        final undoAllocation = const Uuid().v4();
        final undoActor = deriveTextActor(context, writer, undoAllocation);
        final document = textEngine!.restoreDocument(
          actorClientId: undoActor,
          limits: NativeTextLimits(
            visibleUtf16: field == 'title' ? 500 : 10000,
          ),
          checkpoint: NativeTextCheckpoint(
            NativeTextState.parse(base64Encode(state)),
          ),
        );
        if (document.read().pending) {
          document.dispose();
          throw FormatFailure(
            'Native text is waiting for a missing update dependency.',
          );
        }
        fields[field] = TaskTextFieldCapture(
          field: field,
          context: context,
          allocation: allocation,
          actor: actor,
          document: document,
          undoActor: undoActor,
          undoAllocation: undoAllocation,
        );
        _capturedLocalActors[document] = {actor, undoActor};
        _capturedApplied[document] =
            (jsonDecode(row['frontier'] as String) as List)
                .cast<String>()
                .toSet();
      }
      final result = TaskTextCapture(
        entity,
        Map.unmodifiable(fields),
        writer: writer,
      );
      _textCaptures.add(result);
      return result;
    } catch (_) {
      for (final field in fields.values) {
        field.document.dispose();
      }
      rethrow;
    }
  });

  Future<LogEvent> editNativeTask(
    String entity,
    Map<String, dynamic> changes, {
    Map<String, dynamic>? nonText,
    String? expectedSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    final bases = <String, Map<String, dynamic>>{};
    for (final name in changes.keys) {
      final row = db.select(
        'SELECT * FROM text_fields WHERE entity=? AND field=?',
        [entity, name],
      );
      if (row.isEmpty) {
        throw FormatFailure(
          'Native text is waiting for its initialized field.',
        );
      }
      final cached = Map<String, dynamic>.from(row.single);
      cached['state'] = Uint8List.fromList(
        cached['state'] as Uint8List,
      ).asUnmodifiableView();
      bases[name] = Map.unmodifiable(cached);
    }
    return _command(
      entity,
      'task.textEdited',
      {...?nonText, 'changes': changes},
      expectedTaskSnapshot: expectedSnapshot,
      ignoreSnapshotText: true,
      canCommit: canCommit,
      onPrepared: (receipt) {
        _preparedTextBases[receipt.id] = Map.unmodifiable(bases);
        onPrepared?.call(receipt);
      },
    );
  });

  void registerTextOperation(
    OperationReceipt receipt,
    TaskTextCapture capture,
  ) {
    _requireConfirmed([receipt]);
    final event = LogEvent.decode(receipt.raw);
    if (!_textCaptures.contains(capture) ||
        event.type != 'task.textEdited' ||
        event.writer != writer ||
        event.entity != capture.entity ||
        capture.writer != writer) {
      throw FormatFailure(
        'Native Undo requires this session’s exact saved text receipt.',
      );
    }
    if (_nativeOperations.containsKey(event.id)) return;
    final fields = (event.data['changes'] as Map).keys.cast<String>().toList();
    for (final name in fields) {
      final field = capture.fields[name];
      final change = (event.data['changes'] as Map)[name] as Map;
      if (field == null ||
          field.document.isClosed ||
          change['context'] != field.context ||
          !_capturedLocalActors[field.document]!.contains(change['actor'])) {
        throw FormatFailure(
          'Saved native text receipt does not belong to its retained owner.',
        );
      }
    }
    final bases = _preparedTextBases[event.id];
    if (bases == null) {
      throw FormatFailure(
        'Native Undo requires its captured immutable pre-Save state.',
      );
    }
    final owners = <String, _NativeUndoField>{};
    for (final name in fields) {
      final base = bases[name]!;
      final context = base['context'] as String;
      var owner = _nativeUndoFields[context];
      if (owner == null) {
        final allocation = const Uuid().v4();
        final actor = deriveTextActor(context, writer, allocation);
        final document = textEngine!.restoreDocument(
          actorClientId: actor,
          limits: NativeTextLimits(visibleUtf16: name == 'title' ? 500 : 10000),
          checkpoint: NativeTextCheckpoint(
            NativeTextState.parse(base64Encode(base['state'] as Uint8List)),
          ),
        );
        owner = _NativeUndoField(
          event.entity,
          name,
          context,
          allocation,
          actor,
          document,
        );
        owner.applied.addAll(
          (jsonDecode(base['frontier'] as String) as List).cast<String>(),
        );
        _nativeUndoFields[context] = owner;
      }
      owners[name] = owner;
      _syncNativeUndoField(
        owner,
        _entityEvents(event.entity),
        exclude: event.id,
      );
      if (!owner.applied.contains(event.id)) {
        owner.document.applyOwnedReceipt(
          NativeTextUpdate.parse(
            (event.data['changes'] as Map)[name]['update'],
          ),
          operationId: event.id,
        );
        owner.applied.add(event.id);
      }
    }
    _nativeOperations[event.id] = _NativeTextOperation(
      receipt,
      capture,
      fields,
      owners,
    );
    _preparedTextBases.remove(event.id);
    for (final name in fields) {
      _nativeUndoStacks
          .putIfAbsent(owners[name]!.document, () => [])
          .add(event.id);
    }
  }

  /// Release process-local Undo owners without pruning canonical events or
  /// unresolved immutable intents.
  void releaseTextOperations(Iterable<String> operations) {
    for (final id in operations) {
      final owner = _nativeOperations[id];
      if (owner?.compensation != null &&
          confirmedOperations([owner!.compensation!]).isEmpty) {
        continue;
      }
      if (owner != null) {
        for (final prepared
            in owner.prepared?.values ?? <NativeTextPreparedUndo>[]) {
          prepared.cancel();
        }
        for (final name in owner.fields) {
          final field = owner.owners[name]!;
          final document = field.document;
          final stack = _nativeUndoStacks[document];
          stack?.remove(id);
          if (stack?.isEmpty == true) _nativeUndoStacks.remove(document);
          final retained = _nativeOperations.entries.any(
            (entry) =>
                entry.key != id && entry.value.owners.values.contains(field),
          );
          if (!retained) {
            _nativeUndoFields.remove(field.context);
            document.dispose();
          }
        }
        _nativeOperations.remove(id);
      }
      if (db.select('SELECT 1 FROM text_outbox WHERE id=?', [id]).isEmpty) {
        _preparedTextBases.remove(id);
      }
    }
  }

  /// Closed editors release source handles. Saved operations retain separate
  /// shared session Undo owners until history eviction.
  void releaseTextCapture(TaskTextCapture capture) {
    if (!_textCaptures.contains(capture)) return;
    for (final receipt in pendingTextOperations) {
      final event = LogEvent.decode(receipt.raw);
      if (event.entity != capture.entity) continue;
      final changes = event.data['changes'] as Map?;
      if (changes != null &&
          changes.entries.any((entry) {
            final field = capture.fields[entry.key];
            return field != null &&
                _capturedLocalActors[field.document]!.contains(
                  (entry.value as Map)['actor'],
                );
          })) {
        throw StateError(
          'The captured editor still owns an unconfirmed exact text intent.',
        );
      }
    }
    for (final field in capture.fields.values) {
      field.document.dispose();
      _capturedLocalActors.remove(field.document);
      _capturedApplied.remove(field.document);
      if (_nativeUndoStacks[field.document]?.isEmpty == true) {
        _nativeUndoStacks.remove(field.document);
      }
    }
    _textCaptures.remove(capture);
  }

  void registerTextDraftActor(
    TaskTextCapture capture,
    String field,
    String allocation,
    int actor,
  ) {
    if (_closed ||
        !_textCaptures.contains(capture) ||
        capture.writer != writer) {
      throw StateError('Captured native text owner is unavailable.');
    }
    final source = capture.fields[field];
    if (source == null ||
        source.document.isClosed ||
        deriveTextActor(source.context, writer, allocation) != actor) {
      throw FormatFailure('Invalid private native draft allocation.');
    }
    _capturedLocalActors[source.document]!.add(actor);
  }

  void _updateCapturedTextDocuments(
    List<LogEvent> events,
    Set<String> affected,
  ) {
    for (final capture in _textCaptures) {
      if (_hasInheritedText(capture.entity)) {
        if (!affected.contains(capture.entity)) continue;
        Map<String, ResolvedTextField> resolved;
        try {
          resolved = _resolvedText(capture.entity);
        } on TextInheritancePending {
          continue;
        }
        for (final field in capture.fields.values) {
          if (field.document.isClosed) continue;
          final lineage = resolved[field.field]!;
          if (lineage.context.hash != field.context) {
            throw FormatFailure('Captured successor text context changed.');
          }
          final applied = _capturedApplied[field.document]!;
          for (final packet in lineage.operations) {
            if (applied.contains(packet.event.id) ||
                _capturedLocalActors[field.document]!.contains(
                  packet.claim.actor,
                )) {
              continue;
            }
            field.document.applyRemote(packet.update);
            applied.add(packet.event.id);
          }
        }
        continue;
      }
      for (final event in events) {
        if (event.entity != capture.entity ||
            (event.type != 'task.textEdited' &&
                event.type != 'task.textEditUndone')) {
          continue;
        }
        for (final entry in (event.data['changes'] as Map).entries) {
          final field = capture.fields[entry.key];
          final change = entry.value as Map;
          if (field == null ||
              field.document.isClosed ||
              change['context'] != field.context ||
              _capturedLocalActors[field.document]!.contains(change['actor'])) {
            continue;
          }
          field.document.applyRemote(NativeTextUpdate.parse(change['update']));
        }
      }
    }
  }

  void _syncNativeUndoField(
    _NativeUndoField owner,
    List<LogEvent> events, {
    String? exclude,
  }) {
    if (_hasInheritedText(owner.entity)) {
      Map<String, ResolvedTextField> fields;
      try {
        fields = _resolvedText(owner.entity);
      } on TextInheritancePending {
        // Missing foreign proof is ordinary transport delay. Preserve the
        // session owner and its scoped Undo until the dependency arrives.
        return;
      }
      final lineage = fields[owner.field]!;
      if (lineage.context.hash != owner.context) {
        throw FormatFailure('Retained successor text context changed.');
      }
      for (final packet in lineage.operations) {
        if (packet.event.id == exclude ||
            owner.applied.contains(packet.event.id) ||
            _preparedTextBases.containsKey(packet.event.id) ||
            packet.claim.actor == owner.actor) {
          continue;
        }
        owner.document.applyRemote(packet.update);
        owner.applied.add(packet.event.id);
      }
      return;
    }
    for (final event in events) {
      if (event.entity != owner.entity ||
          event.id == exclude ||
          owner.applied.contains(event.id) ||
          _preparedTextBases.containsKey(event.id) ||
          (event.type != 'task.textEdited' &&
              event.type != 'task.textEditUndone')) {
        continue;
      }
      final change = (event.data['changes'] as Map)[owner.field] as Map?;
      if (change == null ||
          change['context'] != owner.context ||
          change['actor'] == owner.actor) {
        continue;
      }
      owner.document.applyRemote(NativeTextUpdate.parse(change['update']));
      owner.applied.add(event.id);
    }
  }

  void _updateNativeUndoOwners(List<LogEvent> events, Set<String> affected) {
    for (final owner in _nativeUndoFields.values) {
      if (!affected.contains(owner.entity)) continue;
      _syncNativeUndoField(owner, events);
    }
  }

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
          "SELECT id,entity,json_extract(raw,'\$.type') AS type,json_extract(raw,'\$.data.before') AS before_id,json_extract(raw,'\$.data.successor.id') AS successor FROM events WHERE json_extract(raw,'\$.type') IN ('user.created','task.created','task.createdWithText','task.completed','task.completedWithText','task.moved') ORDER BY clock,writer,seq",
        )
        .where((row) {
          if (row['type'] == 'task.moved') {
            return !retracted.contains(row['id']);
          }
          final successor = row['successor'] as String?;
          if (isTaskCompletion(row['type'] as String) && successor != null) {
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
      "INSERT OR REPLACE INTO metadata VALUES ('order_projection','3')",
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
              isTaskCompletion(e.type) &&
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
    bool ignoreSnapshotText = false,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    await _refresh();
    _requireWriterAppendReady();
    if (expectedTaskSnapshot != null &&
        (ignoreSnapshotText
            ? _nonTextSnapshot(expectedTaskSnapshot) !=
                  _nonTextSnapshot(taskSnapshot)
            : expectedTaskSnapshot != taskSnapshot)) {
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
    await _stageTextReceipt(e, receipt);
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
    if (_writerHasPendingAppend ||
        db.select('SELECT 1 FROM text_outbox LIMIT 1').isNotEmpty) {
      throw WriterGuardFailure.unresolvedAppend();
    }
  }

  bool _baselineIncludes(LogEvent event, LogEvent baseline) {
    final head = (baseline.data['frontiers'] as Map)[event.writer] as Map?;
    return head != null && event.sequence <= (head['seq'] as int);
  }

  void _validateTextBaseline() {
    final roots = db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='text.baselineInitialized'",
    );
    _textBaseline = null;
    textWriteBlocked = null;
    if (roots.isEmpty) return;
    if (roots.length != 1) {
      textWriteBlocked =
          'Competing text initialization records were retained. Text saving is blocked.';
      return;
    }
    final root = LogEvent.decode(roots.single['raw'] as String);
    if (root.entity != space) {
      throw FormatFailure(
        'Text initialization must reference its workspace in ${root.id}.',
      );
    }
    for (final entry in (root.data['frontiers'] as Map).entries) {
      final head = entry.value as Map;
      final seq = head['seq'] as int;
      if (seq == 0) {
        if (head['hash'] != eventGenesisHash(space, entry.key as String)) {
          throw FormatFailure(
            'Invalid text baseline genesis frontier in ${root.id}.',
          );
        }
        continue;
      }
      final record = db.select(
        'SELECT raw FROM events WHERE writer=? AND seq=?',
        [entry.key, seq],
      );
      if (record.isEmpty) {
        textWriteBlocked =
            'Text initialization is waiting for its declared history.';
        return;
      }
      final event = LogEvent.decode(record.single['raw'] as String);
      if (event.hash != head['hash'] ||
          event.clock.value >= root.clock.value ||
          (event.writer == root.writer && seq >= root.sequence)) {
        throw FormatFailure('Invalid text baseline frontier in ${root.id}.');
      }
    }
    final verified = db.select(
      "SELECT value FROM metadata WHERE key='text_baseline_verified'",
    );
    if (verified.isEmpty || verified.single['value'] != root.id) {
      final fields = _baselineSeedFields(root);
      if (textBaselineSeedDigest(fields) != root.data['seedDigest']) {
        throw FormatFailure('Text baseline seed digest differs in ${root.id}.');
      }
      db.execute(
        "INSERT OR REPLACE INTO metadata VALUES ('text_baseline_verified',?)",
        [root.id],
      );
    }
    _textBaseline = root;
  }

  Map<String, Map<String, String>> _baselineSeedFields(LogEvent root) {
    final prefix = db
        .select('SELECT raw FROM events')
        .map((row) => LogEvent.decode(row['raw'] as String))
        .where((event) => _baselineIncludes(event, root))
        .toList();
    final grouped = <String, List<LogEvent>>{};
    final successors = <String, List<LogEvent>>{};
    for (final event in prefix) {
      grouped.putIfAbsent(event.entity, () => []).add(event);
      if (isTaskCompletion(event.type) && event.data['successor'] != null) {
        final entity = (event.data['successor'] as Map)['id'] as String;
        successors.putIfAbsent(entity, () => []).add(event);
      }
    }
    for (final entry in successors.entries) {
      final own = grouped[entry.key] ?? [];
      final parent = entry.value.first.entity;
      final anchored = prefix.any(
        (event) =>
            event.type == 'task.moved' && event.data['before'] == entry.key,
      );
      final selected = selectSuccessor(
        entry.value,
        grouped[parent] ?? [],
        protected: own.isNotEmpty || anchored,
      );
      grouped
          .putIfAbsent(entry.key, () => [])
          .add(successorCreation(selected.seed));
    }
    final fields = <String, Map<String, String>>{};
    for (final entry in grouped.entries) {
      if (entry.value.any((event) => event.type == 'task.createdWithText') ||
          successors[entry.key]?.any(
                (event) => event.type == 'task.completedWithText',
              ) ==
              true) {
        continue;
      }
      final state = project(entry.value);
      if (state == null || state['kind'] != 'task') continue;
      fields[entry.key] = {
        for (final field in ['title', 'description'])
          field: sha256
              .convert(
                textEngine!.seedText(state[field] as String? ?? '').bytes,
              )
              .toString(),
      };
    }
    return fields;
  }

  bool get sharedTextInitialized =>
      _textBaseline != null && textWriteBlocked == null;

  Future<LogEvent> initializeSharedText({
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    if (textEngine == null) {
      throw FormatFailure('Native text support is unavailable.');
    }
    if (db
        .select(
          "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='text.baselineInitialized' LIMIT 1",
        )
        .isNotEmpty) {
      throw FormatFailure(
        'A text initialization record already exists. Wait for its history or resolve competing records.',
      );
    }
    final frontiers = <String, dynamic>{};
    for (final row in db.select(
      'SELECT name,last_seq,chain_head FROM streams',
    )) {
      final name = row['name'] as String;
      frontiers[name.substring(0, name.length - 6)] = {
        'seq': row['last_seq'],
        'hash': row['chain_head'],
      };
    }
    final reference = LogEvent(
      space,
      writer,
      1,
      EventClock.next(_nowNs(), _maximumClock()),
      space,
      'text.baselineInitialized',
      {'frontiers': frontiers},
    );
    final digest = textBaselineSeedDigest(_baselineSeedFields(reference));
    return _command(space, 'text.baselineInitialized', {
      'codec': 'yrs-v1',
      'adapter': 1,
      'frontiers': frontiers,
      'seedDigest': digest,
    }, onPrepared: onPrepared);
  });

  File _textIntentFile(LogEvent event) =>
      File('$privatePath/text-intents/${event.writer}-${event.sequence}.json');

  Future<void> _stageTextReceipt(
    LogEvent event,
    OperationReceipt receipt,
  ) async {
    if (!_textTypes.contains(event.type)) return;
    if (textEngine == null) {
      throw FormatFailure('Native text support is required before saving.');
    }
    final intent = _textIntentFile(event);
    if (await intent.exists()) {
      if (await intent.readAsString() != receipt.raw) {
        throw FormatFailure(
          'Prepared text intent differs from its immutable event bytes.',
        );
      }
    } else {
      await createFileDurable(intent, utf8.encode(receipt.raw));
    }
    db.execute('INSERT OR IGNORE INTO text_outbox VALUES (?,?,?)', [
      receipt.id,
      receipt.raw,
      receipt.entity,
    ]);
  }

  Future<void> _restoreTextIntents() async {
    final directory = Directory('$privatePath/text-intents');
    if (!await directory.exists()) return;
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final raw = await file.readAsString();
      final event = LogEvent.decode(raw);
      if (!_textTypes.contains(event.type) ||
          event.writer != writer ||
          event.space != space ||
          file.absolute.uri.normalizePath() !=
              _textIntentFile(event).absolute.uri.normalizePath()) {
        throw FormatFailure(
          'Invalid private prepared text intent; evidence was retained.',
        );
      }
      db.execute('INSERT OR IGNORE INTO text_outbox VALUES (?,?,?)', [
        event.id,
        raw,
        event.entity,
      ]);
    }
  }

  Future<void> _retireConfirmedTextIntents() async {
    final directory = Directory('$privatePath/text-intents');
    if (!await directory.exists()) return;
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final raw = await file.readAsString();
      final event = LogEvent.decode(raw);
      final present = db.select('SELECT raw FROM events WHERE id=?', [
        event.id,
      ]);
      if (present.isNotEmpty && present.single['raw'] == raw) {
        db.execute('DELETE FROM text_outbox WHERE id=? AND raw=?', [
          event.id,
          raw,
        ]);
        await file.delete();
        await syncParentAfterCreate(file);
      }
    }
  }

  /// Exact prepared bytes survive an unknown append outcome and process restart.
  List<OperationReceipt> get pendingTextOperations => db
      .select('SELECT id,raw,entity FROM text_outbox ORDER BY rowid')
      .map(
        (row) => OperationReceipt(
          row['id'] as String,
          row['raw'] as String,
          row['entity'] as String,
        ),
      )
      .toList(growable: false);

  Future<LogEvent> retryTextOperation(OperationReceipt receipt) =>
      _serialize(() => _retryTextOperation(receipt));

  Future<LogEvent> _retryTextOperation(OperationReceipt receipt) async {
    await _refresh();
    final event = LogEvent.decode(receipt.raw);
    if (!_textTypes.contains(event.type) ||
        event.writer != writer ||
        event.space != space ||
        event.id != receipt.id ||
        event.entity != receipt.entity ||
        textEngine == null) {
      throw FormatFailure('Invalid prepared native text receipt.');
    }
    final present = db.select('SELECT raw FROM events WHERE id=?', [event.id]);
    if (present.isNotEmpty) {
      _requireConfirmed([receipt]);
      return event;
    }
    final staged = db.select('SELECT raw FROM text_outbox WHERE id=?', [
      event.id,
    ]);
    if (staged.isEmpty ||
        staged.single['raw'] != receipt.raw ||
        event.sequence != _acknowledgedOwnedSequence + 1 ||
        event.previousHash != _writerChainHead) {
      throw FormatFailure(
        'Prepared native text bytes do not match the owned canonical prefix.',
      );
    }
    final guarded = await writerGuard.load(space, writer);
    if (guarded == null || guarded.pending.isEmpty) {
      await _prepareWriterAppend([receipt]);
    } else if (guarded.pending.first.sequence != event.sequence ||
        guarded.pending.first.hash != event.hash) {
      throw FormatFailure(
        'Prepared text receipt differs from the reserved writer append.',
      );
    }
    await folder.append(
      '$writer.jsonl',
      Uint8List.fromList(utf8.encode('${receipt.raw}\n')),
    );
    await _refresh();
    _requireConfirmed([receipt]);
    return event;
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
    final legacyTextChange =
        type == 'task.edited' &&
        (data.containsKey('title') || data.containsKey('description'));
    final textSnapshotRequired =
        type == 'task.completed' && data['successor'] != null;
    if (textSnapshotRequired &&
        textEngine != null &&
        db.select('SELECT 1 FROM text_fields WHERE entity=? LIMIT 1', [
          entity,
        ]).isNotEmpty) {
      throw FormatFailure(
        'Collaborative recurring completion is not available yet; existing history is retained.',
      );
    }
    if ((legacyTextChange || textSnapshotRequired) &&
        textWriteBlocked != null &&
        !_hasNativeTextRoot(entity, _entityEvents(entity))) {
      throw FormatFailure(textWriteBlocked!);
    }
    if (_textTypes.contains(type) &&
        type != 'task.createdWithText' &&
        textWriteBlocked != null &&
        !_hasNativeTextRoot(entity, _entityEvents(entity))) {
      throw FormatFailure(textWriteBlocked!);
    }
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
    if (type == 'task.textEdited' || type == 'task.textEditUndone') {
      if (_hasInheritedText(entity)) _resolvedText(entity, pending: [e]);
      final nativeCreation = _hasNativeTextRoot(entity, prior);
      if (!nativeCreation && _textBaseline == null) {
        throw FormatFailure(
          textWriteBlocked ??
              'Initialize shared text before saving this existing task.',
        );
      }
      if (!nativeCreation &&
          prior.any(
            (event) =>
                event.type == 'task.created' && event.canonicalRaw == null,
          ) &&
          project(_baselineEntityHistory(entity, _textBaseline!)) == null) {
        throw FormatFailure(
          'This recurring occurrence is waiting for a verified native text creation context.',
        );
      }
    }
    final projected = type == 'text.baselineInitialized'
        ? <String, dynamic>{'id': space}
        : project([...prior, e]);
    if (projected == null) {
      throw FormatFailure('Local command requires an existing entity.');
    }
    if (_textTypes.contains(type)) {
      if (textEngine == null) {
        throw FormatFailure('Native text support is required before saving.');
      }
      db.execute('SAVEPOINT validate_text_command');
      final oldBaseline = _textBaseline;
      final oldBlocked = textWriteBlocked;
      try {
        TextCache(db, textEngine!).validatePackets([e]);
        if (type == 'text.baselineInitialized') {
          db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
            e.id,
            e.entity,
            e.writer,
            e.sequence,
            e.clock.value.toInt(),
            e.canonicalRaw,
          ]);
          _validateTextBaseline();
          if (textWriteBlocked != null) throw FormatFailure(textWriteBlocked!);
        } else if (type == 'task.completedWithText') {
          _resolvedText(
            (data['successor'] as Map)['id'] as String,
            pending: [e],
          );
        } else {
          _materializeText(projected, [...prior, e]);
        }
      } finally {
        _textBaseline = oldBaseline;
        textWriteBlocked = oldBlocked;
        db.execute('ROLLBACK TO validate_text_command');
        db.execute('RELEASE validate_text_command');
      }
    }
    if (type.startsWith('task.') &&
        type != 'task.created' &&
        type != 'task.createdWithText' &&
        type != 'task.operationUndone' &&
        type != 'task.textEditUndone' &&
        type != 'task.recurringCompletionUndone' &&
        project(prior)?['deleted'] == true) {
      throw FormatFailure('This task was deleted.');
    }
    if ((type == 'task.created' ||
            type == 'task.createdWithText' ||
            ((type == 'task.edited' || type == 'task.textEdited') &&
                data.containsKey('assignee'))) &&
        db.select(
          "SELECT id FROM views WHERE id=? AND json_extract(raw,'\$.kind')='user'",
          [data['assignee']],
        ).isEmpty) {
      throw FormatFailure('Choose an existing user before creating a task.');
    }
    if (type == 'task.textEditUndone' ||
        type == 'task.completionUndone' ||
        type == 'task.operationUndone' ||
        type == 'task.recurringCompletionUndone') {
      final field =
          type == 'task.operationUndone' || type == 'task.textEditUndone'
          ? 'operation'
          : 'completion';
      if (!prior.any((target) => target.id == data[field])) {
        throw FormatFailure('Undo requires an earlier operation of this task.');
      }
    }
    _validateUndoReferences(e);
    _validateMoves(e);
    _validateTagReferences(e);
    if (isTaskCompletion(type) &&
        data['successor'] == null &&
        TaskSchedule.fromJson(
              Map<String, dynamic>.from(project(prior)!['schedule'] as Map),
            ).recurrence !=
            null) {
      throw FormatFailure('Repeating completion requires a next occurrence.');
    }
    if (isTaskCompletion(type) && data['successor'] != null) {
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
        "SELECT id FROM events WHERE entity=? AND json_extract(raw,'\$.type') IN ('task.created','task.createdWithText','user.created')",
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
    for (final receipt in receipts) {
      await _stageTextReceipt(LogEvent.decode(receipt.raw), receipt);
    }
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
          {
            'title': entry.value,
            'description': '',
            'assignee': assignee,
            if (textEngine != null)
              'text': {
                'codec': 'yrs-v1',
                'adapter': 1,
                'seeds': {
                  'title': sha256
                      .convert(textEngine!.seedText(entry.value).bytes)
                      .toString(),
                  'description': sha256
                      .convert(textEngine!.seedText('').bytes)
                      .toString(),
                },
              },
          },
        ));
      }
    }
    final prepared = <OperationReceipt>[];
    Object? error;
    try {
      await _appendCommandBatch(
        textEngine == null ? 'task.created' : 'task.createdWithText',
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
    final invalidText = db.select(
      "SELECT u.id FROM events u JOIN events t ON t.id=json_extract(u.raw,'\$.data.operation') WHERE json_extract(u.raw,'\$.type')='task.textEditUndone' AND (u.entity<>t.entity OR t.clock>=u.clock OR json_extract(t.raw,'\$.type')<>'task.textEdited') LIMIT 1",
    );
    if (invalidText.isNotEmpty) {
      throw FormatFailure(
        'Invalid text Undo reference in ${invalidText.single['id']}.',
      );
    }
    // A join revalidates resolved references, including newly imported targets.
    final invalid = db.select(
      "SELECT u.id FROM events u JOIN events t ON t.id=CASE WHEN json_extract(u.raw,'\$.type')='task.operationUndone' THEN json_extract(u.raw,'\$.data.operation') ELSE json_extract(u.raw,'\$.data.completion') END WHERE json_extract(u.raw,'\$.type') IN ('task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND (u.entity<>t.entity OR t.clock>=u.clock OR (json_extract(u.raw,'\$.type')='task.completionUndone' AND json_extract(t.raw,'\$.type') NOT IN ('task.completed','task.completedWithText')) OR (json_extract(u.raw,'\$.type')='task.recurringCompletionUndone' AND (json_extract(t.raw,'\$.type') NOT IN ('task.completed','task.completedWithText') OR json_extract(t.raw,'\$.data.successor.id') IS NULL)) OR (json_extract(u.raw,'\$.type')='task.operationUndone' AND (json_extract(t.raw,'\$.type') NOT IN ('task.edited','task.moved','task.deleted','task.completed','task.completedWithText','task.completionUndone') OR (json_extract(t.raw,'\$.type') IN ('task.completed','task.completedWithText') AND json_extract(t.raw,'\$.data.successor') IS NOT NULL)))) LIMIT 1",
    );
    if (invalid.isNotEmpty) {
      throw FormatFailure('Invalid undo reference in ${invalid.single['id']}.');
    }
    if (pending == null) return;
    void validate(LogEvent undo, LogEvent target) {
      if (undo.type == 'task.textEditUndone') {
        if (target.entity != undo.entity ||
            target.clock >= undo.clock ||
            target.type != 'task.textEdited') {
          throw FormatFailure('Invalid text Undo reference in ${undo.id}.');
        }
        return;
      }
      final operation = undo.type == 'task.operationUndone';
      if (target.entity != undo.entity ||
          target.clock >= undo.clock ||
          (operation
              ? (!reversibleTaskEvents.contains(target.type) ||
                    (isTaskCompletion(target.type) &&
                        target.data['successor'] != null))
              : !isTaskCompletion(target.type)) ||
          (undo.type == 'task.recurringCompletionUndone' &&
              target.data['successor'] == null)) {
        throw FormatFailure('Invalid undo reference in ${undo.id}.');
      }
    }

    if (pending.type == 'task.textEditUndone' ||
        pending.type == 'task.operationUndone' ||
        pending.type == 'task.completionUndone' ||
        pending.type == 'task.recurringCompletionUndone') {
      final ref =
          pending.data[pending.type == 'task.operationUndone' ||
                  pending.type == 'task.textEditUndone'
              ? 'operation'
              : 'completion'];
      final targets = db.select('SELECT raw FROM events WHERE id=?', [ref]);
      if (targets.isNotEmpty) {
        validate(pending, LogEvent.decode(targets.single['raw'] as String));
      }
    }
    for (final row in db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.type') IN ('task.textEditUndone','task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND COALESCE(json_extract(raw,'\$.data.operation'),json_extract(raw,'\$.data.completion'))=?",
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
        pending != null &&
            isTaskCompletion(pending.type) &&
            pending.data['successor'] is Map
        ? (pending.data['successor'] as Map)['id']
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
          if (pending != null &&
              isTaskCompletion(pending.type) &&
              pending.data['successor'] != null) {
            final successor = pending.data['successor'] as Map;
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
        if (target.type == 'task.created' ||
            target.type == 'task.createdWithText') {
          additions = target.data['tags'] as List? ?? [];
        }
        if ((target.type == 'task.edited' ||
                target.type == 'task.textEdited') &&
            target.data['tagChanges'] != null) {
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
        (e) =>
            e.type == 'task.created' ||
            e.type == 'task.createdWithText' ||
            e.type == 'user.created',
      )) {
        final creations = own
            .where(
              (event) =>
                  event.type == 'task.created' ||
                  event.type == 'task.createdWithText' ||
                  event.type == 'user.created',
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
                      event.type == 'task.createdWithText' ||
                      event.type == 'user.created',
                )
                .skip(1)
          : ordered.where((event) => event.type.startsWith('task.'));
      if (candidates.isEmpty) rethrow;
      throw FormatFailure('${failure.message} In ${candidates.first.id}.');
    }
    if (state == null) return null;
    _materializeText(state, history);
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

  void _materializeText(Map<String, dynamic> state, List<LogEvent> history) {
    if (textEngine == null) return;
    final entity = state['id'] as String;
    if (_hasInheritedText(entity)) {
      try {
        TextCache(db, textEngine!).materializeResolved(
          state,
          _resolvedText(
            entity,
            pending: history
                .where((event) => event.canonicalRaw != null)
                .toList(),
          ),
        );
      } on TextInheritancePending catch (pending) {
        // Retain the verified display if any; do not establish a guessed seed.
        final cached = db.select('SELECT raw FROM views WHERE id=?', [entity]);
        if (cached.isNotEmpty) {
          final prior = jsonDecode(cached.single['raw'] as String) as Map;
          for (final field in ['title', 'description']) {
            state[field] = prior[field];
          }
        }
        state['textUnavailable'] = pending.message;
        state['textInheritancePending'] = true;
      }
      return;
    }
    var basis = _textBaseline;
    var kind = 'legacy-baseline';
    Map<String, String>? seedText;
    final nativeCreation = history.any(
      (event) => event.type == 'task.createdWithText',
    );
    if (!nativeCreation &&
        textWriteBlocked?.startsWith('Competing') == true &&
        history.any((event) => event.type == 'task.created') &&
        db.select('SELECT 1 FROM text_fields WHERE entity=? LIMIT 1', [
          state['id'],
        ]).isEmpty) {
      state['textUnavailable'] = textWriteBlocked;
      return;
    }
    if (basis != null &&
        !history.any((event) => event.type == 'task.createdWithText')) {
      final prefix = project(
        _baselineEntityHistory(state['id'] as String, basis),
      );
      Map<String, dynamic>? initial = prefix;
      if (initial == null) {
        final creations = history
            .where((event) => event.type == 'task.created')
            .toList();
        if (creations.isNotEmpty) {
          basis = creations.single;
          kind = 'legacy-creation';
          initial = project([basis]);
        }
      }
      if (initial?['kind'] == 'task') {
        seedText = {
          for (final field in ['title', 'description'])
            field: initial![field] as String? ?? '',
        };
      }
    }
    if (history.any((event) => _textTypes.contains(event.type)) ||
        seedText != null ||
        db.select('SELECT 1 FROM text_fields WHERE entity=? LIMIT 1', [
          state['id'],
        ]).isNotEmpty) {
      TextCache(db, textEngine!).materialize(
        state,
        history,
        basis: basis,
        legacySeedText: seedText,
        basisKind: kind,
      );
    }
  }

  bool _hasInheritedText(String entity) => db.select(
    "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='task.completedWithText' AND json_extract(raw,'\$.data.successor.id')=? LIMIT 1",
    [entity],
  ).isNotEmpty;

  bool _hasNativeTextRoot(String entity, List<LogEvent> history) =>
      history.any((event) => event.type == 'task.createdWithText') ||
      _hasInheritedText(entity);

  Map<String, ResolvedTextField> _resolvedText(
    String entity, {
    List<LogEvent> pending = const [],
  }) => RecurringTextResolver(textEngine!, [
    ...db
        .select('SELECT raw FROM events')
        .map((row) => LogEvent.decode(row['raw'] as String)),
    ...pending,
  ], legacyRoots: _legacyTextRoots).resolve(entity);

  Map<String, TextFieldSeed>? _legacyTextRoots(
    String entity,
    List<LogEvent> observed,
  ) {
    final baseline = _textBaseline;
    if (baseline == null || !observed.any((event) => event.id == baseline.id)) {
      return null;
    }
    List<LogEvent> entityHistory(List<LogEvent> prefix) {
      final own = prefix.where((event) => event.entity == entity).toList();
      final seeds = prefix
          .where(
            (event) =>
                isTaskCompletion(event.type) &&
                (event.data['successor'] as Map?)?['id'] == entity,
          )
          .toList();
      if (seeds.isNotEmpty) {
        own.add(
          successorCreation(
            selectSuccessor(
              seeds,
              prefix.where((event) => event.entity == seeds.first.entity),
              protected:
                  own.isNotEmpty ||
                  prefix.any(
                    (event) =>
                        event.type == 'task.moved' &&
                        event.data['before'] == entity,
                  ),
            ).seed,
          ),
        );
      }
      return own;
    }

    var basis = baseline;
    var kind = 'legacy-baseline';
    var initial = project(
      entityHistory(
        observed.where((event) => _baselineIncludes(event, baseline)).toList(),
      ),
    );
    if (initial == null) {
      final creations = observed
          .where(
            (event) => event.entity == entity && event.type == 'task.created',
          )
          .toList();
      if (creations.length != 1) return null;
      basis = creations.single;
      kind = 'legacy-creation';
      initial = project([basis]);
    }
    if (initial?['kind'] != 'task') return null;
    return {
      for (final field in ['title', 'description'])
        field: (() {
          final seed = textEngine!.seedText(initial![field] as String? ?? '');
          return TextFieldSeed(
            TextFieldContext(
              space: space,
              entity: entity,
              field: field,
              basis: basis.id,
              basisKind: kind,
              seedHash: sha256.convert(seed.bytes).toString(),
            ),
            seed,
          );
        })(),
    };
  }

  List<LogEvent> _baselineEntityHistory(String entity, LogEvent baseline) {
    final own = db
        .select('SELECT raw FROM events WHERE entity=?', [entity])
        .map((row) => LogEvent.decode(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    final seeds = db
        .select(
          "SELECT raw FROM events WHERE json_extract(raw,'\$.data.successor.id')=?",
          [entity],
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    if (seeds.isNotEmpty) {
      final parent = db
          .select('SELECT raw FROM events WHERE entity=?', [seeds.first.entity])
          .map((row) => LogEvent.decode(row['raw'] as String))
          .where((event) => _baselineIncludes(event, baseline));
      final anchors = db
          .select(
            "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.moved' AND json_extract(raw,'\$.data.before')=?",
            [entity],
          )
          .map((row) => LogEvent.decode(row['raw'] as String))
          .any((event) => _baselineIncludes(event, baseline));
      own.add(
        successorCreation(
          selectSuccessor(
            seeds,
            parent,
            protected: own.isNotEmpty || anchors,
          ).seed,
        ),
      );
    }
    return own;
  }

  Future<LogEvent> complete(
    String entity, {
    DateTime? completionDay,
    DateTime? completionInstant,
    String? localZoneId,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    final state = _projectEntity(entity);
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
    var type = 'task.completed';
    if (data['successor'] != null &&
        textEngine != null &&
        db.select('SELECT 1 FROM text_fields WHERE entity=? LIMIT 1', [
          entity,
        ]).isNotEmpty) {
      final fields = _resolvedText(entity);
      data['inheritance'] = {
        'codec': 'yrs-v1',
        'adapter': 1,
        'frontiers': {
          for (final row in db.select(
            'SELECT name,last_seq,chain_head FROM streams',
          ))
            (row['name'] as String).replaceFirst(RegExp(r'\.jsonl$'), ''): {
              'seq': row['last_seq'],
              'hash': row['chain_head'],
            },
        },
        'fields': {
          for (final entry in fields.entries)
            entry.key: {
              'parentContext': entry.value.context.hash,
              'seedHash': entry.value.context.seedHash,
              'stateHash': entry.value.stateHash,
            },
        },
      };
      type = 'task.completedWithText';
    }
    return _command(
      entity,
      type,
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

  String _nonTextSnapshot(String snapshot) {
    final rows = (jsonDecode(snapshot) as List)
        .map(
          (row) => Map<String, dynamic>.from(row as Map)
            ..remove('title')
            ..remove('description')
            ..remove('inbox'),
        )
        .toList();
    return canonicalTextJson(rows);
  }

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
    bool ignoreSnapshotText = false,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    final tagChanges = calculateTaskTagChanges(tags, observedTagRefs);
    return _command(
      entity,
      'task.edited',
      {...fields, 'tagChanges': ?tagChanges},
      expectedTaskSnapshot: expectedTaskSnapshot,
      ignoreSnapshotText: ignoreSnapshotText,
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
    "SELECT 1 FROM events WHERE (json_extract(raw,'\$.type') IN ('task.operationUndone','task.textEditUndone') AND json_extract(raw,'\$.data.operation')=?) OR (json_extract(raw,'\$.type')='task.recurringCompletionUndone' AND json_extract(raw,'\$.data.completion')=?)",
    [id, id],
  ).isNotEmpty;

  Future<TaskUndoResult> _undoMixedTextOperations(
    List<String> operations,
    Map<String, LogEvent> targets,
  ) async {
    final undone = <String>[], remaining = <String>[];
    Object? failure;
    var newer = false, retained = 0, removed = 0;
    for (final id in operations) {
      if (targets[id]!.type != 'task.textEdited') {
        final result = await _undoOperations([id]);
        undone.addAll(result.undone);
        remaining.addAll(result.remaining);
        failure ??= result.error;
        newer |= result.keptNewerChanges;
        retained += result.retainedSuccessorCount;
        removed += result.removedSuccessorCount;
        continue;
      }
      final owner = _nativeOperations[id];
      try {
        if (_operationUndone(id) && owner?.prepared == null) {
          undone.add(id);
          continue;
        }
        if (owner == null) {
          throw FormatFailure(
            'Native Undo is available only in its retained editing session.',
          );
        }
        final history = _entityEvents(owner.capture.entity);
        if (history.any(
          (event) =>
              _preparedTextBases.containsKey(event.id) &&
              !_nativeOperations.containsKey(event.id) &&
              event.type == 'task.textEdited' &&
              owner.fields.any(
                (name) =>
                    (event.data['changes'] as Map)[name]?['context'] ==
                    owner.owners[name]!.context,
              ),
        )) {
          throw FormatFailure(
            'A newer saved edit has unfinished Undo registration. Restart Tandemlog to clear session Undo; the saved tasks remain in the folder.',
          );
        }
        final inactive = retractedOperationIds(history);
        newer |= history.any(
          (event) =>
              (reversibleTaskEvents.contains(event.type) ||
                  event.type == 'task.textEdited') &&
              compareEvents(event, targets[id]!) > 0 &&
              !inactive.contains(event.id),
        );
        if (owner.prepared == null) {
          for (final name in owner.fields) {
            final field = owner.owners[name]!;
            _syncNativeUndoField(field, _entityEvents(owner.capture.entity));
            if (field.document.isClosed ||
                _nativeUndoStacks[field.document]?.last != id) {
              throw FormatFailure(
                'Undo the newer text save before this operation.',
              );
            }
          }
          final prepared = <String, NativeTextPreparedUndo>{};
          try {
            for (final name in owner.fields) {
              prepared[name] = owner.owners[name]!.document
                  .prepareOperationUndo(operationId: id);
            }
          } catch (_) {
            for (final value in prepared.values) {
              value.cancel();
            }
            rethrow;
          }
          owner.prepared = prepared;
        }
        if (owner.compensation != null) {
          await _retryTextOperation(owner.compensation!);
        } else {
          final changes = <String, dynamic>{};
          for (final entry in owner.prepared!.entries) {
            final field = owner.owners[entry.key]!;
            changes[entry.key] = {
              'context': field.context,
              'allocation': field.allocation,
              'actor': field.actor,
              'update': entry.value.update.encoded,
            };
          }
          await _command(owner.capture.entity, 'task.textEditUndone', {
            'operation': id,
            'changes': changes,
          }, onPrepared: (receipt) => owner.compensation = receipt);
        }
        _commitNativeCompensation(owner, id);
        undone.add(id);
      } catch (error) {
        try {
          await _refresh();
        } catch (_) {
          /* Keep exact intent and private preparation. */
        }
        if (owner?.compensation != null &&
            confirmedOperations([owner!.compensation!]).isNotEmpty) {
          try {
            _commitNativeCompensation(owner, id);
            undone.add(id);
            continue;
          } catch (_) {
            /* Preserve for retry. */
          }
        }
        failure ??= error;
        remaining.add(id);
      }
    }
    return TaskUndoResult(
      undone,
      remaining,
      newer,
      error: failure,
      retainedSuccessorCount: retained,
      removedSuccessorCount: removed,
    );
  }

  void _commitNativeCompensation(_NativeTextOperation owner, String id) {
    _requireConfirmed([owner.compensation!]);
    for (final value in owner.prepared!.values) {
      value.commit(receiptUpdate: value.update);
    }
    for (final name in owner.fields) {
      final field = owner.owners[name]!;
      field.applied.add(owner.compensation!.id);
      final stack = _nativeUndoStacks[field.document]!;
      if (stack.isNotEmpty && stack.last == id) stack.removeLast();
    }
    owner.prepared = null;
  }

  Future<TaskUndoResult> undoOperations(List<String> operations) =>
      _serialize(() => _undoOperations(operations));

  Future<TaskUndoResult> _undoOperations(List<String> operations) async {
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
      if (!reversibleTaskEvents.contains(event.type) &&
          event.type != 'task.textEdited') {
        throw FormatFailure('This operation cannot be undone.');
      }
      targets[id] = event;
    }
    if (targets.values.any((event) => event.type == 'task.textEdited')) {
      return _undoMixedTextOperations(operations, targets);
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
          isTaskCompletion(targets[id]!.type) &&
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
        if (isTaskCompletion(targets[id]!.type) &&
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
  }

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
        for (final capture in _textCaptures) {
          for (final field in capture.fields.values) {
            field.document.dispose();
          }
        }
        for (final field in _nativeUndoFields.values) {
          field.document.dispose();
        }
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
