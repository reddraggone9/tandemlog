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

/// The task state observed by a caller changed before a guarded command.
class StaleTaskSnapshot implements Exception {
  @override
  String toString() => 'Tasks changed. Review the selection and try again.';
}

/// Owns durable log ingestion and one disposable SQLite materialization.
class TaskStore {
  final LogFolder folder;
  final Database db;
  final String writer;
  final RandomAccessFile lock;
  final DateTime Function() now;
  static const materialClockSkew = Duration(minutes: 5);
  String? clockWarning;
  late final String space;
  int readFiles = 0, cacheTransactions = 0;
  Map<String, int>? lastBatchTiming;
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
        manifest['v'] == 1 &&
        manifest['id'] is String &&
        isCanonicalId(manifest['id']) &&
        manifest.keys.every((key) => {'v', 'id'}.contains(key))) {
      throw FormatFailure(
        'This folder uses an older prerelease format (v1). Preserve this folder and choose a new data folder for this prerelease.',
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

  TaskStore._(this.folder, this.db, this.writer, this.lock, this.now);
  static Future<TaskStore> open(
    LogFolder folder,
    String privatePath, {
    void Function(String, int)? onTiming,
    DateTime Function()? now,
  }) async {
    final phase = Stopwatch()..start();
    void mark(String name) {
      onTiming?.call(name, phase.elapsedMilliseconds);
      phase.reset();
    }

    await Directory(privatePath).create(recursive: true);
    final lock = await File(
      '$privatePath/session.lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw StateError(
        'This workspace is already open in another app instance.',
      );
    }
    Database? db;
    try {
      final identity = File('$privatePath/writer-id');
      if (!await identity.exists()) {
        await identity.writeAsString(const Uuid().v4(), flush: true);
      }
      final writer = (await identity.readAsString()).trim();
      if (!isCanonicalId(writer)) {
        throw FormatFailure('Invalid local writer identity.');
      }
      mark('identity_lock');
      db = sqlite3.open('$privatePath/cache.sqlite');
      final version =
          db.select('PRAGMA user_version').first.values.first as int;
      if (version < 0 || version > 8) {
        throw FormatFailure(
          'This cache was created by a newer app. Use a compatible app; the cache and canonical logs were retained.',
        );
      }
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      if (version > 0 && version < 8) {
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
      db.execute(
        'CREATE TABLE IF NOT EXISTS positions (id TEXT PRIMARY KEY, rank INTEGER NOT NULL)',
      );
      db.execute('PRAGMA user_version=8');
      mark('sqlite_open_schema');
      final store = TaskStore._(folder, db, writer, lock, now ?? DateTime.now);
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
      db?.close();
      await lock.close();
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
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final table in ['events', 'views', 'positions']) {
        db.execute('DROP TABLE IF EXISTS $table');
      }
      db.execute("DELETE FROM metadata WHERE key='order_projection'");
      db.execute(
        "INSERT OR REPLACE INTO metadata VALUES ('replay_pending','1')",
      );
      db.execute('PRAGMA user_version=8');
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
  Future<bool> _refresh() async {
    if (await _readSpace(folder) != space) {
      throw FormatFailure('Workspace identity changed at this location.');
    }
    _updateClockWarning(_maximumClock(), _nowNs());
    final files = await folder.list();
    if (files.any((f) => f.name.contains('sync-conflict'))) {
      throw FormatFailure(
        'A folder-sync conflict copy needs recovery. No history was discarded.',
      );
    }
    final logs = files.where((f) => f.name.endsWith('.jsonl')).toList();
    final names = logs.map((f) => f.name).toSet();
    for (final row in db.select('SELECT name FROM streams')) {
      if (!names.contains(row['name'])) {
        throw FormatFailure(
          'Previously imported log ${row['name']} is missing. Restore it; do not rebuild away this warning.',
        );
      }
    }
    final replay = db
        .select("SELECT value FROM metadata WHERE key='replay_pending'")
        .isNotEmpty;
    final newEvents = <LogEvent>[];
    final checkpoints = <List<Object?>>[];
    for (final info in logs) {
      final writerName = info.name.substring(0, info.name.length - 6);
      if (!isCanonicalId(writerName)) {
        throw FormatFailure('Unrecognized log filename ${info.name}.');
      }
      final saved = db.select('SELECT * FROM streams WHERE name=?', [
        info.name,
      ]);
      final row = saved.isEmpty ? null : saved.first;
      if (!replay &&
          row != null &&
          info.stamp.isNotEmpty &&
          row['stamp'] == info.stamp) {
        continue;
      }
      final bytes = await folder.read(info.name);
      readFiles++;
      final offset = row == null ? 0 : row['offset'] as int;
      if (bytes.length < offset ||
          (row != null &&
              sha256.convert(bytes.sublist(0, offset)).toString() !=
                  row['hash'])) {
        throw FormatFailure(
          'Previously imported history changed in ${info.name}. Restore the original log before writing.',
        );
      }
      var end = bytes.lastIndexOf(10) + 1;
      if (end < offset) end = offset;
      if (bytes.length - end > 1024 * 1024) {
        throw FormatFailure('Oversized incomplete record in ${info.name}.');
      }
      if (info.name == '$writer.jsonl' && end != bytes.length) {
        throw FormatFailure(
          'Interrupted local append detected. Preserve the file and recover its incomplete tail before writing.',
        );
      }
      var lastSeq =
          db.select(
                'SELECT COALESCE(MAX(seq),0) AS n FROM events WHERE writer=?',
                [writerName],
              ).first['n']
              as int;
      var lastClock = _maximumClock(writerName);
      final appended = utf8.decode(bytes.sublist(replay ? 0 : offset, end));
      final lines = appended.isEmpty
          ? <String>[]
          : (appended.split('\n')..removeLast());
      for (final raw in lines) {
        if (raw.isEmpty) {
          throw FormatFailure('Blank canonical record in ${info.name}.');
        }
        if (raw.length > 1024 * 1024) throw FormatFailure('Oversized event.');
        final e = LogEvent.decode(raw);
        if (e.space != space ||
            e.writer != writerName ||
            e.sequence != lastSeq + 1 ||
            (lastClock != null && e.clock <= lastClock)) {
          throw FormatFailure(
            'Invalid space, writer, sequence or clock in ${info.name}.',
          );
        }
        lastSeq = e.sequence;
        lastClock = e.clock;
        newEvents.add(e);
      }
      checkpoints.add([
        info.name,
        end,
        sha256.convert(bytes.sublist(0, end)).toString(),
        end == bytes.length ? info.stamp : '',
      ]);
    }
    if (checkpoints.isEmpty) {
      if (replay) db.execute("DELETE FROM metadata WHERE key='replay_pending'");
      return false;
    }
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final e in newEvents) {
        db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
          e.id,
          e.entity,
          e.writer,
          e.sequence,
          e.clock.value.toInt(),
          e.encode(),
        ]);
      }
      _validateUndoReferences();
      _validateMoves();
      _validateTagReferences();
      final affected = newEvents.map((e) => e.entity).toSet();
      for (final e in newEvents) {
        if (e.type == 'task.completed' && e.data['successor'] != null) {
          affected.add((e.data['successor'] as Map)['id'] as String);
        }
      }
      for (final entity in affected) {
        final state = project(_entityEvents(entity));
        if (state != null) {
          db.execute('INSERT OR REPLACE INTO views VALUES (?,?)', [
            entity,
            jsonEncode(state),
          ]);
        }
      }
      if (newEvents.any(
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
        db.execute('INSERT OR REPLACE INTO streams VALUES (?,?,?,?)', c);
      }
      db.execute("DELETE FROM metadata WHERE key='replay_pending'");
      db.execute('COMMIT');
      cacheTransactions++;
      _updateClockWarning(_maximumClock(), _nowNs());
      return newEvents.isNotEmpty;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  bool hasEntity(String id) =>
      db.select('SELECT 1 FROM views WHERE id=?', [id]).isNotEmpty;

  final Map<String, int> lastReadTimings = {};
  List<Map<String, dynamic>> get rows {
    final watch = Stopwatch()..start();
    final records = db.select(
      "SELECT views.raw FROM views JOIN positions ON positions.id=views.id WHERE COALESCE(json_extract(views.raw,'\$.deleted'),0)=0 ORDER BY positions.rank",
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
    final actions = db
        .select(
          "SELECT id,entity,json_extract(raw,'\$.type') AS type,json_extract(raw,'\$.data.before') AS before_id,json_extract(raw,'\$.data.successor.id') AS successor FROM events WHERE json_extract(raw,'\$.type') IN ('user.created','task.created','task.completed','task.moved') ORDER BY clock,writer,seq",
        )
        .where(
          (row) =>
              row['type'] != 'task.moved' || !retracted.contains(row['id']),
        )
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
    final raw = e.encode();
    onPrepared?.call(OperationReceipt(e.id, raw, e.entity));
    await folder.append(
      '$writer.jsonl',
      Uint8List.fromList(utf8.encode('$raw\n')),
    );
    // Durable log append is the commit point. A cache failure is recoverable.
    await _refresh();
    return e;
  }

  LogEvent _prepareCommand(
    String entity,
    String type,
    Map<String, dynamic> data,
    int seq,
    EventClock clock,
  ) {
    final e = LogEvent.decode(
      LogEvent(space, writer, seq, clock, entity, type, data).encode(),
    );
    final prior = _entityEvents(entity);
    final projected = project([...prior, e]);
    if (projected == null) {
      throw FormatFailure('Local command requires an existing entity.');
    }
    if (type.startsWith('task.') &&
        type != 'task.created' &&
        type != 'task.operationUndone' &&
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
    if (type == 'task.completionUndone' || type == 'task.operationUndone') {
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
  }) async {
    if (commands.isEmpty) return [];
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
    for (final (entity, data) in commands) {
      final wall = _nowNs();
      _updateClockWarning(maximum, wall);
      final clock = EventClock.next(wall, maximum);
      final event = _prepareCommand(entity, type, data, seq++, clock);
      final raw = event.encode();
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
      "SELECT u.id FROM events u JOIN events t ON t.id=CASE WHEN json_extract(u.raw,'\$.type')='task.operationUndone' THEN json_extract(u.raw,'\$.data.operation') ELSE json_extract(u.raw,'\$.data.completion') END WHERE json_extract(u.raw,'\$.type') IN ('task.completionUndone','task.operationUndone') AND (u.entity<>t.entity OR t.clock>=u.clock OR (json_extract(u.raw,'\$.type')='task.completionUndone' AND json_extract(t.raw,'\$.type')<>'task.completed') OR (json_extract(u.raw,'\$.type')='task.operationUndone' AND json_extract(t.raw,'\$.type') NOT IN ('task.edited','task.moved','task.deleted','task.completed','task.completionUndone'))) LIMIT 1",
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
              ? !reversibleTaskEvents.contains(target.type)
              : target.type != 'task.completed')) {
        throw FormatFailure('Invalid undo reference in ${undo.id}.');
      }
    }

    if (pending.type == 'task.operationUndone' ||
        pending.type == 'task.completionUndone') {
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
      "SELECT raw FROM events WHERE json_extract(raw,'\$.type') IN ('task.completionUndone','task.operationUndone') AND COALESCE(json_extract(raw,'\$.data.operation'),json_extract(raw,'\$.data.completion'))=?",
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
        throw FormatFailure('Task order anchor is not a task.');
      }
      if (move == pending && target == null) {
        throw FormatFailure('Task order anchor is missing.');
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
              ? "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.tagsChanged' OR json_extract(raw,'\$.data.tagChanges') IS NOT NULL"
              : "SELECT raw FROM events e WHERE EXISTS (SELECT 1 FROM json_each(CASE WHEN json_extract(e.raw,'\$.type')='task.tagsChanged' THEN json_extract(e.raw,'\$.data.remove') ELSE json_extract(e.raw,'\$.data.tagChanges.remove') END) r WHERE r.value LIKE ?) OR e.entity=?",
          pending == null ? [] : ['${pending.id}:%', successor],
        )
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    if (pending != null) mutations.add(pending);
    for (final mutation in mutations) {
      final changes = mutation.type == 'task.tagsChanged'
          ? mutation.data
          : mutation.data['tagChanges'];
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
            throw FormatFailure('Invalid future derived tag reference.');
          }
          continue; // delayed dependency or stable derived seed tag
        }
        List? additions;
        final owner = target.entity;
        if (target.type == 'task.created') {
          additions = target.data['tags'] as List? ?? [];
        }
        if (target.type == 'task.tagsChanged') {
          additions = target.data['add'] as List;
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
        throw FormatFailure(
          'Successor identifier collides with existing entity.',
        );
      }
      final seed = LogEvent.decode(seeds.first['raw'] as String);
      own.add(successorCreation(seed));
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

  Future<void> setTags(
    String entity,
    List<String> desired, {
    Map<String, String>? observedTagRefs,
  }) => _serialize(() async {
    await _refresh();
    final state = project(_entityEvents(entity));
    if (state == null || state['kind'] != 'task' || state['deleted'] == true) {
      throw FormatFailure('Unknown task.');
    }
    final refs =
        observedTagRefs ?? Map<String, String>.from(state['tagRefs'] as Map);
    final wanted = desired.toSet();
    final removed = refs.entries
        .where((e) => !wanted.contains(e.value))
        .map((e) => e.key)
        .toList();
    final added = wanted.difference(refs.values.toSet()).toList()..sort();
    if (removed.isNotEmpty || added.isNotEmpty) {
      await _command(entity, 'task.tagsChanged', {
        'add': added,
        'remove': removed,
      });
    }
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

  /// An ID alone cannot confirm an uncertain append: the next command can
  /// reuse its sequence after a failed write. Match its complete canonical raw.
  Set<String> confirmedOperations(Iterable<OperationReceipt> receipts) => {
    for (final r in receipts)
      if (db.select('SELECT 1 FROM events WHERE id=? AND raw=?', [
        r.id,
        r.raw,
      ]).isNotEmpty)
        r.id,
  };

  bool _operationUndone(String id) => db.select(
    "SELECT 1 FROM events WHERE json_extract(raw,'\$.type')='task.operationUndone' AND json_extract(raw,'\$.data.operation')=?",
    [id],
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
      await _appendCommandBatch('task.operationUndone', [
        for (final id in operations.where((id) => !alreadyUndone.contains(id)))
          (targets[id]!.entity, {'operation': id}),
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
        LogEvent.decode(receipt.raw).data['operation'] as String,
    };
    return TaskUndoResult(
      operations.where(undone.contains),
      operations.where((id) => !undone.contains(id)),
      newer,
      error,
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
      db.close();
      await lock.close();
    });
  }
}
