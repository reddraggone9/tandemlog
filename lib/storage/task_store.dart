import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../domain/projection.dart';
import '../application/task_clock.dart';
import '../domain/schedule.dart' hide validateSchedule;
import 'log_folder.dart';

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
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      final version = db.select('PRAGMA user_version').first.values.first;
      if (version != 0 && version != 7) {
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
      db.execute('PRAGMA user_version=7');
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
      var lastClock = _maximumClock(writerName);
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
    if (checkpoints.isEmpty) return false;
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
        (e) => {
          'task.created',
          'user.created',
          'task.completed',
          'task.moved',
        }.contains(e.type),
      )) {
        _rebuildOrder();
      }
      for (final c in checkpoints) {
        db.execute('INSERT OR REPLACE INTO streams VALUES (?,?,?,?)', c);
      }
      db.execute('COMMIT');
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
      'SELECT views.raw FROM views JOIN positions ON positions.id=views.id ORDER BY positions.rank',
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
    final actions = db
        .select(
          "SELECT entity,json_extract(raw,'\$.type') AS type,json_extract(raw,'\$.data.before') AS before_id,json_extract(raw,'\$.data.successor.id') AS successor FROM events WHERE json_extract(raw,'\$.type') IN ('user.created','task.created','task.completed','task.moved') ORDER BY clock,writer,seq",
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
    final undone = events
        .where((e) => e.type == 'task.completionUndone')
        .map((e) => e.data['completion'])
        .toSet();
    return events
        .where((e) => e.type == 'task.completed' && !undone.contains(e.id))
        .map((e) => e.id)
        .toList();
  }

  Future<void> reopen(String entity, List<String> observedCompletions) {
    final targets = observedCompletions.toSet();
    return _serialize(() async {
      for (final target in targets) {
        await _refresh();
        if (activeCompletionIds(entity).contains(target)) {
          await _command(entity, 'task.completionUndone', {
            'completion': target,
          });
        }
      }
    });
  }

  Future<LogEvent> command(
    String entity,
    String type,
    Map<String, dynamic> data,
  ) => _serialize(() => _command(entity, type, data));

  Future<LogEvent> _command(
    String entity,
    String type,
    Map<String, dynamic> data,
  ) async {
    await _refresh();
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
    final e = LogEvent.decode(
      LogEvent(space, writer, seq, clock, entity, type, data).encode(),
    );
    final prior = _entityEvents(entity);
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
    _validateMoves(e);
    _validateTagReferences(e);
    if (type == 'task.completed' && data['successor'] != null) {
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
    await folder.append(
      '$writer.jsonl',
      Uint8List.fromList(utf8.encode('${e.encode()}\n')),
    );
    // Durable log append is the commit point. A cache failure is recoverable.
    await _refresh();
    return e;
  }

  void _validateMoves([LogEvent? pending]) {
    final moves = db
        .select(
          "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.moved'",
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
    final mutations = db
        .select(
          "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.tagsChanged' OR json_extract(raw,'\$.data.tagChanges') IS NOT NULL",
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
  }) => _serialize(() async {
    await _refresh();
    final state = project(_entityEvents(entity));
    if (state == null || state['kind'] != 'task') {
      throw FormatFailure('Unknown task.');
    }
    final schedule = TaskSchedule.fromJson(
      Map<String, dynamic>.from(state['schedule'] as Map),
    );
    if ((completionDay == null) == (completionInstant == null)) {
      throw ArgumentError('Supply exactly one completion day or instant.');
    }
    final day =
        completionDay ?? civilDayAt(completionInstant!, schedule.timeZone);
    final data = <String, dynamic>{
      'completedAt':
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    };
    if (schedule.recurrence != null) {
      final next = schedule.next(day);
      data['successor'] = {
        'id': const Uuid().v5(entity, 'successor'),
        'title': state['title'],
        'description': state['description'],
        'assignee': state['assignee'],
        'tags': state['tags'],
        'schedule': next.toJson(),
      };
    }
    return _command(entity, 'task.completed', data);
  });

  Future<LogEvent> moveBefore(String entity, String? before) =>
      command(entity, 'task.moved', {'before': before});

  Future<LogEvent> edit(
    String entity,
    Map<String, dynamic> fields, {
    required List<String> tags,
    required Map<String, String> observedTagRefs,
  }) => _serialize(() async {
    final wanted = tags.toSet();
    final removed = observedTagRefs.entries
        .where((e) => !wanted.contains(e.value))
        .map((e) => e.key)
        .toList();
    final added = wanted.difference(observedTagRefs.values.toSet()).toList()
      ..sort();
    return _command(entity, 'task.edited', {
      ...fields,
      if (added.isNotEmpty || removed.isNotEmpty)
        'tagChanges': {'add': added, 'remove': removed},
    });
  });

  Future<void> setTags(
    String entity,
    List<String> desired, {
    Map<String, String>? observedTagRefs,
  }) => _serialize(() async {
    await _refresh();
    final state = project(_entityEvents(entity));
    if (state == null || state['kind'] != 'task') {
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

  Future<void> close() {
    _closed = true;
    return _closing ??= _queue.then((_) async {
      db.close();
      await lock.close();
    });
  }
}
