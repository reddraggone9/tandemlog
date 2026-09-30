import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../platform/log_folder.dart';

/// Owns durable log ingestion and one disposable SQLite materialization.
class TaskStore {
  final LogFolder folder;
  final Database db;
  final String writer;
  final RandomAccessFile lock;
  late final String space;
  int readFiles = 0;
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
    if (manifest is! Map<String, dynamic> ||
        manifest['v'] != 1 ||
        manifest['id'] is! String ||
        !idPattern.hasMatch(manifest['id']) ||
        manifest.keys.any((key) => !{'v', 'id'}.contains(key))) {
      throw FormatFailure('Unsupported or invalid workspace manifest.');
    }
    return manifest['id'] as String;
  }

  TaskStore._(this.folder, this.db, this.writer, this.lock);
  static Future<TaskStore> open(
    LogFolder folder,
    String privatePath, {
    void Function(String, int)? onTiming,
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
      if (!idPattern.hasMatch(writer)) {
        throw FormatFailure('Invalid local writer identity.');
      }
      mark('identity_lock');
      db = sqlite3.open('$privatePath/cache.sqlite');
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      final version = db.select('PRAGMA user_version').first.values.first;
      if (version != 0 && version != 1) {
        throw FormatFailure(
          'Unsupported cache version. Preserve logs and rebuild cache with a compatible app.',
        );
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
        'CREATE TABLE IF NOT EXISTS views (id TEXT PRIMARY KEY, raw TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE IF NOT EXISTS streams (name TEXT PRIMARY KEY, offset INTEGER NOT NULL, hash TEXT NOT NULL, stamp TEXT NOT NULL)',
      );
      db.execute('PRAGMA user_version=1');
      mark('sqlite_open_schema');
      final store = TaskStore._(folder, db, writer, lock);
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
            utf8.encode(jsonEncode({'v': 1, 'id': const Uuid().v4()})),
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
      mark('ingest');
      return store;
    } catch (_) {
      db?.close();
      await lock.close();
      rethrow;
    }
  }

  Future<bool> refresh() => _serialize(_refresh);
  Future<bool> _refresh() async {
    if (await _readSpace(folder) != space) {
      throw FormatFailure('Workspace identity changed at this location.');
    }
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
    final newEvents = <LogEvent>[];
    final checkpoints = <List<Object?>>[];
    for (final info in logs) {
      final writerName = info.name.substring(0, info.name.length - 6);
      if (!idPattern.hasMatch(writerName)) {
        throw FormatFailure('Unrecognized log filename ${info.name}.');
      }
      final saved = db.select('SELECT * FROM streams WHERE name=?', [
        info.name,
      ]);
      final row = saved.isEmpty ? null : saved.first;
      if (row != null && info.stamp.isNotEmpty && row['stamp'] == info.stamp) {
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
      var lastClock =
          db.select(
                'SELECT COALESCE(MAX(clock),0) AS n FROM events WHERE writer=?',
                [writerName],
              ).first['n']
              as int;
      final appended = utf8.decode(bytes.sublist(offset, end));
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
            e.clock <= lastClock) {
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
    if (checkpoints.isEmpty) return false;
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final e in newEvents) {
        db.execute('INSERT INTO events VALUES (?,?,?,?,?,?)', [
          e.id,
          e.entity,
          e.writer,
          e.sequence,
          e.clock,
          e.encode(),
        ]);
      }
      // Revalidate all undo references when a missing target arrives, including
      // references whose target belongs to another entity.
      for (final row in db.select(
        "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.completionUndone'",
      )) {
        final undo = LogEvent.decode(row['raw'] as String);
        if (undo.type != 'task.completionUndone') continue;
        final target = db.select('SELECT raw FROM events WHERE id=?', [
          undo.data['completion'],
        ]);
        if (target.isNotEmpty) {
          final completed = LogEvent.decode(target.first['raw'] as String);
          if (completed.type != 'task.completed' ||
              completed.entity != undo.entity ||
              completed.clock >= undo.clock) {
            throw FormatFailure('Invalid completion reference in ${undo.id}.');
          }
        }
      }
      for (final entity in newEvents.map((e) => e.entity).toSet()) {
        final state = project(
          db
              .select('SELECT raw FROM events WHERE entity=?', [entity])
              .map((r) => LogEvent.decode(r['raw'] as String))
              .toList(),
        );
        if (state != null) {
          db.execute('INSERT OR REPLACE INTO views VALUES (?,?)', [
            entity,
            jsonEncode(state),
          ]);
        }
      }
      for (final c in checkpoints) {
        db.execute('INSERT OR REPLACE INTO streams VALUES (?,?,?,?)', c);
      }
      db.execute('COMMIT');
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
    final records = db.select('SELECT raw FROM views');
    lastReadTimings['query_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    final result = records
        .map((r) => jsonDecode(r['raw'] as String) as Map<String, dynamic>)
        .toList();
    lastReadTimings['decode_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    result.sort(
      (a, b) => (a['order'] as String).compareTo(b['order'] as String),
    );
    lastReadTimings['sort_ms'] = watch.elapsedMilliseconds;
    return result;
  }

  Future<LogEvent> command(
    String entity,
    String type,
    Map<String, dynamic> data,
  ) => _serialize(() async {
    await _refresh();
    final seq =
        (db.select(
              'SELECT COALESCE(MAX(seq),0) AS n FROM events WHERE writer=?',
              [writer],
            ).first['n']
            as int) +
        1;
    final clock =
        (db.select('SELECT COALESCE(MAX(clock),0) AS n FROM events').first['n']
            as int) +
        1;
    final e = LogEvent.decode(
      LogEvent(space, writer, seq, clock, entity, type, data).encode(),
    );
    final prior = db
        .select('SELECT raw FROM events WHERE entity=?', [entity])
        .map((row) => LogEvent.decode(row['raw'] as String))
        .toList();
    final projected = project([...prior, e]);
    if (projected == null) {
      throw FormatFailure('Local command requires an existing entity.');
    }
    if (type == 'task.created' &&
        db.select(
          "SELECT id FROM views WHERE id=? AND json_extract(raw,'\$.kind')='user'",
          [data['assignee']],
        ).isEmpty) {
      throw FormatFailure('Choose an existing user before creating a task.');
    }
    if (type == 'task.completionUndone') {
      final targets = prior.where((target) => target.id == data['completion']);
      if (targets.isEmpty ||
          targets.single.type != 'task.completed' ||
          targets.single.clock >= clock) {
        throw FormatFailure(
          'Undo requires an earlier completion of this task.',
        );
      }
    }
    for (final row in db.select(
      "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.completionUndone' AND json_extract(raw,'\$.data.completion')=?",
      [e.id],
    )) {
      final undo = LogEvent.decode(row['raw'] as String);
      if (e.type != 'task.completed' ||
          e.entity != undo.entity ||
          e.clock >= undo.clock) {
        throw FormatFailure(
          'Local event would resolve an invalid undo reference.',
        );
      }
    }
    await folder.append(
      '$writer.jsonl',
      Uint8List.fromList(utf8.encode('${e.encode()}\n')),
    );
    // Durable log append is the commit point. A cache failure is recoverable.
    await _refresh();
    return e;
  });

  Future<void> close() {
    _closed = true;
    return _closing ??= _queue.then((_) async {
      db.close();
      await lock.close();
    });
  }
}
