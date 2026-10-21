import 'dart:convert';
import 'dart:io';
import 'local_durability.dart';
import 'local_settings.dart';
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
import '../domain/occurrence_due_migration.dart';
import 'log_folder.dart';
import 'profile_lock.dart';
import 'writer_guard.dart';
import 'local_profile_database.dart';
import 'task_tables.dart';
import '../text/native_text_engine.dart';
import '../text/recurring_text.dart';
import 'text_cache.dart';
import 'unified_history.dart';
import 'unified_manifest.dart' show assertWorkspaceTaskTimeZonePolicy;
import 'workspace_view.dart';
import '../domain/time_zone_policy.dart';
import 'unified_record.dart';
import 'unified_manifest.dart' show bytesDigest;
import '../domain/text_context.dart';
import '../domain/text_actor.dart';
import '../domain/historical_completion.dart';
import '../domain/checklist.dart';
import '../domain/text_inheritance.dart' show verifyTextInheritance;
export 'writer_guard.dart';

part 'checklist_store.dart';

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

/// Results of append-only compatibility edits. Conflicts remain ordinary tasks.
class OccurrenceDueMigrationResult {
  const OccurrenceDueMigrationResult(
    this.migrated,
    this.conflicts,
    this.error, {
    required this.changed,
  });
  final int migrated;

  /// Refresh or guarded append may have changed the rows, even with zero conversions.
  final bool changed;
  final Map<String, String> conflicts;
  final Object? error;
}

/// Owns durable log ingestion and one disposable SQLite materialization.
class TaskStore {
  final LogFolder folder;
  final Database _database;
  Database get db => profileDatabase?.database ?? _database;
  final String writer;
  final ProfileLock? lock;
  final LocalProfileDatabase? profileDatabase;
  final TaskTables tables;
  final String? _locationKey;
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
  final _recurringTextMemo = RecurringTextMemo();
  static const _textTypes = nativeTextIntentTypes;
  bool _writerHasPendingAppend = false;
  final DateTime Function() now;
  static const materialClockSkew = Duration(minutes: 5);
  String? clockWarning;
  late final String space;
  int get readFiles => unified?.readFiles ?? 0;
  int cacheTransactions = 0;
  Map<String, int>? lastBatchTiming;
  HistoryVerificationReport? _lastHistoryVerification;
  HistoryVerificationReport? get lastHistoryVerification =>
      _lastHistoryVerification;
  TaskViewSnapshot _currentView = TaskViewSnapshot.empty();
  TaskViewSnapshot get currentView => _currentView;
  final _viewChanges = WorkspaceChanges();
  Object? viewFailure;
  Object? viewSharedFailure;
  final bool _viewHasPendingSave = false;
  bool get viewHasPendingSave => _viewHasPendingSave;
  void Function() listenView(void Function() listener) =>
      _viewChanges.listen(listener);

  Future<T> _runWorkspaceOperation<T>(Future<T> Function() work) async {
    try {
      return await work();
    } finally {
      if (unified == null) _viewChanges.notify();
    }
  }

  Future<void> _queue = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;
  Future<void> Function()? _closeOwnedResources;
  Future<T> _serialize<T>(Future<T> Function() work) {
    if (_closed) return Future.error(StateError('Workspace is closed.'));
    var entered = false;
    Future<T> run() {
      entered = true;
      return _runWorkspaceOperation(work);
    }

    final result = profileDatabase == null
        ? _queue.then((_) => run())
        : profileDatabase!.serialize(run);
    final observed = result.then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        if (!entered) {
          if (unified != null) {
            unified!.reportQueueFailure(error);
          } else {
            viewFailure = error;
            viewSharedFailure = error;
            _viewChanges.notify();
          }
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _queue = observed.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return observed;
  }

  static void _rollback(
    Database db,
    LocalProfileDatabase? profile,
    Object error,
  ) {
    if (profile != null) {
      profile.rollbackAfterFailure(error);
    } else if (!db.autocommit) {
      db.execute('ROLLBACK');
    }
  }

  final UnifiedHistory? unified;
  TimeZoneNamePolicy get timeZonePolicy =>
      unified?.timeZonePolicy ?? TimeZoneNamePolicy.additional2026eV1;

  TaskStore._(
    this.folder,
    this._database,
    this.writer,
    this.lock,
    this.now,
    this.textEngine,
    this.privatePath,
    this.profileDatabase,
    this.tables,
    this._locationKey, {
    this.unified,
  });

  /// Preflight uses the existing semantic/native validators on a scratch DB,
  /// never durable files or a second writer. Original raw IDs/hashes are intact.
  static List<Map<String, dynamic>> validateSemanticHistory(
    Iterable<LogEvent> input, {
    required String space,
    required String writer,
    NativeTextEngine? textEngine,
    void Function(Set<String>)? onReady,
  }) {
    final events = input.toList(), db = sqlite3.openInMemory();
    const tables = TaskTables.legacy();
    TaskStore? store;
    try {
      for (final sql in _latestProjectionSchema(tables)) {
        db.execute(sql);
      }
      store = TaskStore._(
        _SemanticValidationFolder(),
        db,
        writer,
        null,
        DateTime.now,
        textEngine,
        '',
        null,
        tables,
        null,
      );
      store.space = space;
      db.execute('BEGIN IMMEDIATE');
      store._replaySemanticEvents(events);
      onReady?.call(store._semanticReadyIds(events));
      return store.rows
          .map((row) => Map<String, dynamic>.unmodifiable(row))
          .toList();
    } finally {
      store?._recurringTextMemo.clear();
      if (!db.autocommit) db.execute('ROLLBACK');
      db.close();
    }
  }

  static List<String> _latestProjectionSchema(TaskTables tables) => [
    'CREATE TABLE IF NOT EXISTS ${tables.events} (id TEXT PRIMARY KEY, entity TEXT NOT NULL, writer TEXT NOT NULL, seq INTEGER NOT NULL, clock INTEGER NOT NULL, raw TEXT NOT NULL, semantic TEXT NOT NULL, UNIQUE(writer,seq))',
    'CREATE TABLE IF NOT EXISTS ${tables.views} (id TEXT PRIMARY KEY, raw TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS ${tables.streams} (name TEXT PRIMARY KEY, offset INTEGER NOT NULL, hash TEXT NOT NULL, stamp TEXT NOT NULL, hash_offset INTEGER NOT NULL DEFAULT 0, range_capable INTEGER NOT NULL DEFAULT 0, chain_head TEXT, last_seq INTEGER NOT NULL DEFAULT 0, last_clock INTEGER)',
    'CREATE TABLE IF NOT EXISTS ${tables.streamRanges} (name TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, hash TEXT NOT NULL, PRIMARY KEY(name,start_offset))',
    'CREATE TABLE IF NOT EXISTS ${tables.textFields} (entity TEXT NOT NULL, field TEXT NOT NULL, context TEXT NOT NULL, codec TEXT NOT NULL, adapter INTEGER NOT NULL, seed_hash TEXT NOT NULL, state BLOB NOT NULL, state_hash TEXT NOT NULL, frontier TEXT NOT NULL, PRIMARY KEY(entity,field))',
    'CREATE TABLE IF NOT EXISTS ${tables.textActors} (context TEXT NOT NULL, actor INTEGER NOT NULL, writer TEXT NOT NULL, allocation TEXT NOT NULL, PRIMARY KEY(context,actor))',
    'CREATE TABLE IF NOT EXISTS ${tables.textOutbox} (id TEXT PRIMARY KEY, raw TEXT NOT NULL, entity TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS ${tables.positions} (id TEXT PRIMARY KEY, rank INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS ${tables.metadata} (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ];

  void _replaySemanticEvents(List<LogEvent> events) {
    TextCache? cache;
    try {
      for (final e in events) {
        if (e.space != space || e.canonicalRaw == null) {
          throw FormatFailure('Task snapshot has invalid canonical evidence.');
        }
        if (_textTypes.contains(e.type) && textEngine == null) {
          throw FormatFailure(
            'Native text support is required before app admission.',
          );
        }
        db.execute('INSERT INTO ${tables.events} VALUES (?,?,?,?,?,?,?)', [
          e.id,
          e.entity,
          e.writer,
          e.sequence,
          e.clock.value.toInt(),
          e.canonicalRaw,
          jsonEncode({'type': e.type, 'data': e.data}),
        ]);
      }
      final writers = events.map((e) => e.writer).toSet();
      for (final author in writers) {
        final ordered = events.where((e) => e.writer == author).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
        final last = ordered.last;
        db.execute('INSERT INTO ${tables.streams} VALUES (?,?,?,?,?,?,?,?,?)', [
          '$author.jsonl',
          0,
          '',
          '',
          0,
          0,
          last.hash,
          last.sequence,
          last.clock.value.toInt(),
        ]);
      }
      if (textEngine != null) {
        cache = TextCache.forTransaction(
          db,
          textEngine!,
          memo: _recurringTextMemo,
          tables: tables,
        );
        cache.validatePackets(events);
      }
      _validateTextBaseline();
      _validateUndoReferences();
      _validateMoves();
      _validateTagReferences();
      _validateHistoricalCompletions();
      _validateChecklistReferences();
      _validateChecklistCompletions();
      final entities = events.map((e) => e.entity).toSet();
      for (final e in events) {
        if (isTaskCompletion(e.type) && e.data['successor'] is Map) {
          entities.add((e.data['successor'] as Map)['id'] as String);
        }
        if (e.type == 'task.completedWithChecklist') {
          for (final item in (e.data['checklist'] as Map)['items'] as List) {
            entities.add((item as Map)['id'] as String);
          }
        }
      }
      final resolution = textEngine == null ? null : _textResolution();
      for (final entity in entities) {
        final state = _projectEntity(
          entity,
          resolution: resolution,
          textCache: cache,
        );
        if (state != null) {
          db.execute('INSERT OR REPLACE INTO ${tables.views} VALUES (?,?)', [
            entity,
            jsonEncode(state),
          ]);
        }
      }
      _rebuildOrder();
    } finally {
      cache?.close();
    }
  }

  Set<String> _semanticReadyIds(List<LogEvent> events) {
    final states = {
      for (final r in db.select('SELECT id,raw FROM ${tables.views}'))
        r['id'] as String: jsonDecode(r['raw'] as String) as Map,
    };
    final births = <String, String>{};
    for (final e in events) {
      if (const {
        'user.created',
        'task.created',
        'task.createdWithText',
        'checklist.itemCreated',
      }.contains(e.type)) {
        births[e.entity] = e.id;
      }
      if (isTaskCompletion(e.type) && e.data['successor'] is Map) {
        births[(e.data['successor'] as Map)['id'] as String] = e.id;
      }
      if (e.type == 'task.completedWithChecklist') {
        for (final item in (e.data['checklist'] as Map)['items'] as List) {
          births[(item as Map)['id'] as String] = e.id;
        }
      }
    }
    // Resolve derived births with the exact same seed selection used by rows.
    for (final child in births.keys.toList()) {
      final seeds = db.select(
        "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
        [child],
      );
      if (seeds.isNotEmpty) {
        final own = events.where((e) => e.entity == child).toList();
        births[child] = _successorSelection(child, seeds, own).seed.id;
      } else {
        final copies = _itemCopySeeds(child);
        if (copies.isNotEmpty) births[child] = copies.first.$1.id;
      }
    }
    final nativePending = <String>{};
    if (textEngine != null) {
      for (final r in db.select('SELECT * FROM ${tables.textFields}')) {
        if (r['adapter'] == 2) {
          continue; // resolver already checks shared history
        }
        final doc = textEngine!.restoreDocument(
          actorClientId: 2,
          checkpoint: NativeTextCheckpoint(
            NativeTextState.parse(base64Encode(r['state'] as Uint8List)),
          ),
          limits: NativeTextLimits(
            visibleUtf16: r['field'] == 'title' ? 500 : 10000,
          ),
        );
        try {
          if (doc.read().pending) nativePending.add(r['entity'] as String);
        } finally {
          doc.dispose();
        }
      }
    }
    final competingRoots =
        db
            .select(
              "SELECT id FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='text.baselineInitialized' LIMIT 2",
            )
            .length ==
        2;
    bool availableState(Map? state) =>
        state != null &&
        (state['textUnavailable'] == null ||
            competingRoots && state['textUnavailable'] == textWriteBlocked);
    final dependencies = <String, Set<String>>{};
    final candidates = <String>{};
    for (final e in events) {
      final refs = <String>{};
      void entity(Object? value) {
        if (value is! String) return;
        refs.add(births[value] ?? 'missing-entity:$value');
      }

      void reference(Object? value) {
        if (value is! String) return;
        final parts = value.split(':');
        refs.add(parts.take(2).join(':'));
      }

      if (e.type == 'text.baselineInitialized') {
        if (_textBaseline?.id == e.id || competingRoots) candidates.add(e.id);
      } else {
        entity(e.entity);
        final state = states[e.entity];
        var ready = availableState(state) && !nativePending.contains(e.entity);
        if (e.type == 'task.textEdited' || e.type == 'task.textEditUndone') {
          final hasSeed = events.any(
            (other) =>
                other.entity == e.entity && isNativeTextCreation(other.type),
          );
          if (!hasSeed && !_hasInheritedText(e.entity)) {
            if (_textBaseline == null) {
              ready = false;
            } else {
              refs.add(_textBaseline!.id);
            }
          }
        }
        if (births.entries
            .where((entry) => entry.value == e.id)
            .any(
              (entry) =>
                  !availableState(states[entry.key]) ||
                  nativePending.contains(entry.key),
            )) {
          ready = false;
        }
        if (ready) candidates.add(e.id);
      }
      if (e.type == 'task.moved' || e.type.startsWith('checklist.')) {
        entity(e.data['before']);
      }
      if (e.type.startsWith('checklist.')) entity(e.data['parent']);
      reference(e.data['operation']);
      reference(e.data['completion']);
      if (e.data['retainedSuccessor'] is Map) {
        final retained = e.data['retainedSuccessor'] as Map;
        reference(retained['completion']);
        entity(retained['id']);
      }
      if (e.data['tagChanges'] is Map) {
        for (final ref in (e.data['tagChanges'] as Map)['remove'] as List) {
          final birthId = births[e.entity];
          final matches = events.where(
            (seed) =>
                seed.id == birthId &&
                seed.data['successor'] is Map &&
                (((seed.data['successor'] as Map)['tags'] as List?) ?? []).any(
                  (tag) =>
                      '${const Uuid().v5(e.entity, 'tag:$tag')}:1:0' == ref,
                ),
          );
          if (matches.isNotEmpty) {
            refs.add(matches.single.id);
          } else {
            reference(ref);
          }
        }
      }
      for (final descriptor in [
        e.type == 'text.baselineInitialized' ? e.data : null,
        e.data['inheritance'],
        e.data['checklist'],
      ]) {
        if (descriptor is! Map || descriptor['frontiers'] is! Map) continue;
        for (final entry in (descriptor['frontiers'] as Map).entries) {
          final seq = (entry.value as Map)['seq'] as int;
          if (seq > 0) refs.add('${entry.key}:$seq');
        }
      }
      refs.remove(e.id);
      dependencies[e.id] = refs;
    }
    while (true) {
      final blocked = candidates
          .where((id) => !dependencies[id]!.every(candidates.contains))
          .toList();
      if (blocked.isEmpty) return Set.unmodifiable(candidates);
      candidates.removeAll(blocked);
    }
  }

  /// Open a standalone handle over the same normalized common authority used
  /// by the application. This convenience owns its history and, when omitted,
  /// its local profile. It never reads or converts a legacy workspace.
  static Future<TaskStore> open(
    LogFolder folder,
    String privatePath, {
    void Function(String, int)? onTiming,
    DateTime Function()? now,
    String? writerIdentity,
    NativeTextEngine? textEngine,
    LocalProfileDatabase? profileDatabase,
    bool initializeNewWorkspaceText = false,
  }) async {
    if (initializeNewWorkspaceText && textEngine == null) {
      throw ArgumentError(
        'Native text support is required before creating a text workspace.',
      );
    }
    final started = Stopwatch()..start();
    final profile =
        profileDatabase ?? await LocalProfileDatabase.open(privatePath);
    final openingLease = 'opening:${const Uuid().v4()}';
    profile.acquireWorkspace(openingLease);
    UnifiedHistory? history;
    TaskStore? store;
    try {
      final rows = profile.database.select('SELECT * FROM protected_settings');
      if (rows.isEmpty) {
        if (await File('${profile.root}/settings.json').exists()) {
          throw FormatFailure(
            'This profile needs the coordinated offline handoff. Preserve its original files.',
          );
        }
        final id = writerIdentity ?? const Uuid().v4();
        if (!isCanonicalId(id)) {
          throw FormatFailure('Invalid installation identity.');
        }
        profile.transaction(
          () => profile.database.execute(
            'INSERT INTO protected_settings VALUES (1,?,?)',
            [
              id,
              utf8.encode(jsonEncode({'writer': id, 'appearance': 'system'})),
            ],
          ),
        );
      }
      final writer = LocalSettings.protectedValues(profile)['writer'] as String;
      if (writerIdentity != null && writerIdentity != writer) {
        throw FormatFailure(
          'Installation identity differs from protected settings.',
        );
      }
      if (folder is LocalLogFolder) {
        await ensureDirectoryDurable(Directory(folder.location));
      }
      final files = await folder.list();
      final genuinelyNew = files.isEmpty;
      if (!genuinelyNew &&
          !files.any((f) => f.name == 'tandemlog-space.json')) {
        throw FormatFailure(
          'Workspace manifest is missing. Preserve the existing history.',
        );
      }
      history = genuinelyNew
          ? await UnifiedHistory.create(
              folder,
              profile: profile,
              writer: writer,
              now: now,
              textEngine: textEngine,
            )
          : await UnifiedHistory.open(
              folder,
              profile: profile,
              writer: writer,
              now: now,
              textEngine: textEngine,
            );
      store = await openUnified(history);
      if (initializeNewWorkspaceText && !store.sharedTextInitialized) {
        if (history.snapshot.tasks.isNotEmpty) {
          throw FormatFailure(
            'Existing Task history has no shared-text root. Preserve it for offline conversion.',
          );
        }
        // An empty current canonical history needs no private bootstrap intent.
        // A prior unacknowledged suffix is discarded by its owner before Save.
        await store.initializeSharedText();
      }
      final ownedHistory = history;
      store._closeOwnedResources = () async {
        try {
          await ownedHistory.close();
        } finally {
          if (profileDatabase == null) await profile.close();
        }
      };
      onTiming?.call('unified-open', started.elapsedMilliseconds);
      return store;
    } catch (_) {
      await store?.close();
      await history?.close();
      profile.releaseWorkspace(openingLease);
      if (profileDatabase == null) await profile.close();
      rethrow;
    } finally {
      profile.releaseWorkspace(openingLease);
    }
  }

  static Future<TaskStore> openUnified(UnifiedHistory history) async {
    final key = sha256
        .convert(
          utf8.encode(
            '${history.folder.location}#app5:${history.manifest.epoch}',
          ),
        )
        .toString();
    history.profile.acquireWorkspace(key);
    TaskStore? store;
    try {
      return await history.profile.serialize(() async {
        final tables = TaskTables.forLocation(key);
        history.profile.transaction(() {
          for (final sql in _latestProjectionSchema(tables)) {
            history.profile.database.execute(sql);
          }
        });
        store = TaskStore._(
          history.folder,
          history.profile.database,
          history.writer,
          null,
          history.now,
          history.textEngine,
          history.profile.root,
          history.profile,
          tables,
          key,
          unified: history,
        );
        store!.space = history.manifest.space;
        history.attachProjectionInProfileQueue(
          store!,
          store!._stageUnifiedProjection,
        );
        return store!;
      });
    } catch (_) {
      if (store != null) history.detachProjectionInProfileQueue(store!);
      history.profile.releaseWorkspace(key);
      rethrow;
    }
  }

  String? _unifiedTaskRevision;
  void Function() _stageUnifiedProjection(UnifiedSnapshot snapshot) {
    final events = snapshot.tasks.toList();
    final oldIds = db
        .select('SELECT id FROM ${tables.events}')
        .map((r) => r['id'])
        .toSet();
    final added = events.where((e) => !oldIds.contains(e.id)).toList();
    final affected = {
      ...added.map((e) => e.entity),
      if (added.isNotEmpty) ..._textCaptures.map((c) => c.entity),
      if (added.isNotEmpty) ..._nativeUndoFields.values.map((f) => f.entity),
    };
    final revision = bytesDigest(
      utf8.encode(events.map((e) => '${e.canonicalRaw!}\n').join()),
    );
    final projectionChanged = revision != _unifiedTaskRevision;
    final oldBaseline = _textBaseline, oldBlocked = textWriteBlocked;
    LogEvent? newBaseline = oldBaseline;
    String? newBlocked = oldBlocked;
    if (revision != _unifiedTaskRevision) {
      try {
        _textBaseline = null;
        textWriteBlocked = null;
        _recurringTextMemo.clear();
        for (final table in [
          tables.events,
          tables.views,
          tables.streams,
          tables.streamRanges,
          tables.textFields,
          tables.textActors,
          tables.textOutbox,
          tables.positions,
        ]) {
          db.execute('DELETE FROM $table');
        }
        _replaySemanticEvents(events);
        newBaseline = _textBaseline;
        newBlocked = textWriteBlocked;
      } finally {
        _textBaseline = oldBaseline;
        textWriteBlocked = oldBlocked;
      }
    }
    final pending =
        unified!.hasPendingAfter(snapshot) || snapshot.pendingEffects;
    final candidateView = revision == _unifiedTaskRevision
        ? _currentView
        : TaskViewSnapshot.next(rows, _currentView);
    final oldWarning = clockWarning;
    final maximum = snapshot.records.isEmpty
        ? null
        : snapshot.records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);
    _updateClockWarning(maximum, _nowNs());
    final warning = clockWarning;
    clockWarning = oldWarning;
    return () {
      _textBaseline = newBaseline;
      textWriteBlocked = newBlocked;
      if (projectionChanged) cacheTransactions++;
      _unifiedTaskRevision = revision;
      _writerHasPendingAppend = pending;
      clockWarning = warning;
      _currentView = candidateView;
      _updateCapturedTextDocuments(added, affected);
      _updateNativeUndoOwners(added, affected);
    };
  }

  Future<List<OperationReceipt>> _appendUnifiedCommands(
    List<(String, String, Map<String, dynamic>)> commands, {
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    _requireWriterAppendReady();
    if (commands.isEmpty) return [];
    if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    final creations = <String, LogEvent>{};
    final expected = unified!.snapshot.revision;
    final reservation = await unified!.prepareInProfileQueue(
      [
        for (final (entity, type, data) in commands)
          (seq, clock, head) {
            final event = _prepareCommand(
              entity,
              type,
              data,
              seq,
              clock,
              previousHash: head,
              pendingCreation: creations[entity],
            );
            if (type == 'task.created' || type == 'task.createdWithText') {
              creations[entity] = event;
            }
            return UnifiedEffect('task', event.canonicalRaw!);
          },
      ],
      expectedRevision: expected,
      onReserved: (_) {
        if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
      },
    );
    final receipts = reservation.records
        .expand((r) => r.effects)
        .map((effect) {
          final e = effect.task!;
          return OperationReceipt(e.id, e.canonicalRaw!, e.entity);
        })
        .toList(growable: false);
    // The committed common receipt is the acceptance point. Native sessions
    // bind it irreversibly; callback failure must retain exact recovery bytes.
    for (final receipt in receipts) {
      onPrepared?.call(receipt);
    }
    await unified!.commitInProfileQueue();
    _requireConfirmed(receipts);
    return receipts;
  }

  EventClock? _maximumClock([String? writerId]) {
    if (unified != null && writerId == null) return unified!.maximumClock;
    final result = db.select(
      'SELECT clock FROM ${tables.events} ${writerId == null ? '' : 'WHERE writer=?'} ORDER BY clock DESC LIMIT 1',
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

  /// Rebuild only this namespace's disposable projections. Durable location
  /// binding, trusted stream observations, UI state, guards and exact intents
  /// remain in place; replay is forced even for unchanged-size canonical logs.
  Future<void> rebuildCache() => _serialize(() async {
    _unifiedTaskRevision = null;
    await _refresh();
  });

  Future<bool> _refresh({bool verify = false}) async {
    final before = _unifiedTaskRevision;
    final previousTaskIds = verify
        ? unified!.snapshot.tasks.map((event) => event.id).toSet()
        : const <String>{};
    final snapshot = await unified!.refreshInProfileQueue();
    if (verify) {
      _lastHistoryVerification = HistoryVerificationReport(
        checkedLogCount: snapshot.physical.length,
        checkedRecordCount: snapshot.records.length,
        checkedByteCount: snapshot.physical.values.fold(
          0,
          (n, b) => n + b.length,
        ),
        importedEventCount: snapshot.tasks
            .where((event) => !previousTaskIds.contains(event.id))
            .length,
      );
    }
    return before != _unifiedTaskRevision;
  }

  bool hasEntity(String id) =>
      db.select('SELECT 1 FROM ${tables.views} WHERE id=?', [id]).isNotEmpty;

  Future<TaskTextCapture> captureTaskText(
    String entity,
  ) => _serialize(() async {
    await _refresh();
    if (textEngine == null) {
      throw FormatFailure('Native text support is unavailable.');
    }
    final common = unified;
    if (common != null &&
        common.snapshot.records.any((r) {
          if (r.sequence <= (common.snapshot.published[r.writer] ?? 0)) {
            return false;
          }
          return r.effects.any((effect) {
            final e = effect.task;
            return e != null &&
                e.entity == entity &&
                (e.type == 'task.textEdited' ||
                    e.type == 'task.textEditUndone');
          });
        })) {
      throw FormatFailure(
        'This task is waiting for its complete text history before editing.',
      );
    }
    final history = _entityEvents(entity);
    final task = project(history);
    if (task == null ||
        !{'task', 'checklistItem'}.contains(task['kind']) ||
        task['deleted'] == true) {
      throw FormatFailure('Unknown or deleted task.');
    }
    _attachSuccessorSuppression(task);
    if (task['successorSuppressed'] == true) {
      throw FormatFailure('This untouched next occurrence was canceled.');
    }
    if (task['kind'] == 'checklistItem' &&
        !_checklistParentAvailable(task['parent'] as String)) {
      throw FormatFailure('This checklist item’s task is unavailable.');
    }
    final native = _hasNativeTextRoot(entity, history);
    if (!native && (_textBaseline == null || textWriteBlocked != null)) {
      throw FormatFailure(
        textWriteBlocked ??
            'Restore verified shared-text initialization before editing this existing task.',
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
      _attachChecklist(task);
      if (task['textUnavailable'] != null) {
        throw TextInheritancePending(task['textUnavailable'] as String);
      }
      db.execute('INSERT OR REPLACE INTO ${tables.views} VALUES (?,?)', [
        entity,
        jsonEncode(task),
      ]);
      db.execute('COMMIT');
      cacheTransactions++;
    } catch (error) {
      _rollback(db, profileDatabase, error);
      rethrow;
    }
    final resolvedFields = _hasInheritedText(entity)
        ? _resolvedText(entity)
        : null;
    final fields = <String, TaskTextFieldCapture>{};
    try {
      for (final field in ['title', 'description']) {
        final row = _nativeTextFieldRow(
          entity,
          field,
          resolved: resolvedFields,
        );
        if (row == null) {
          throw FormatFailure(
            'Native text is waiting for its initialization history.',
          );
        }
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

  /// Editor/receipt capture needs exact native state, while historical cache
  /// rows retain only references. Reconstruct from admitted originals on demand;
  /// never reinterpret a reference hash or compact frontier as a native BLOB.
  Map<String, dynamic>? _nativeTextFieldRow(
    String entity,
    String field, {
    Map<String, ResolvedTextField>? resolved,
  }) {
    final rows = db.select(
      'SELECT * FROM ${tables.textFields} WHERE entity=? AND field=?',
      [entity, field],
    );
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.single);
    if (row['adapter'] != 2) return row;
    final lineage = (resolved ?? _resolvedText(entity))[field]!;
    final reference = lineage.historyReference!;
    final frontier = jsonDecode(row['frontier'] as String);
    if (row['codec'] != 'yrs-v1' ||
        row['context'] != lineage.context.hash ||
        row['seed_hash'] != lineage.context.seedHash ||
        row['state_hash'] != reference.hash ||
        (row['state'] as Uint8List).isNotEmpty ||
        frontier is! Map ||
        frontier.length != 1 ||
        frontier['history'] != reference.hash) {
      throw FormatFailure(
        'Shared text reference needs a verified cache rebuild.',
      );
    }
    final state = lineage.state.bytes;
    final operationIds =
        lineage.operations.map((packet) => packet.event.id).toList()..sort();
    return {
      ...row,
      'adapter': 1,
      'state': state,
      'state_hash': sha256.convert(state).toString(),
      'frontier': jsonEncode(operationIds),
    };
  }

  Future<LogEvent> editNativeTask(
    String entity,
    Map<String, dynamic> changes, {
    Map<String, dynamic>? nonText,
    String? expectedSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    final resolvedFields = _hasInheritedText(entity)
        ? _resolvedText(entity)
        : null;
    final bases = <String, Map<String, dynamic>>{};
    for (final name in changes.keys) {
      final row = _nativeTextFieldRow(entity, name, resolved: resolvedFields);
      if (row == null) {
        throw FormatFailure(
          'Native text is waiting for its initialized field.',
        );
      }
      final cached = Map<String, dynamic>.from(row);
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
      if (db.select('SELECT 1 FROM ${tables.textOutbox} WHERE id=?', [
        id,
      ]).isEmpty) {
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
      "SELECT ${tables.views}.raw FROM ${tables.views} JOIN ${tables.positions} ON ${tables.positions}.id=${tables.views}.id WHERE json_extract(${tables.views}.raw,'\$.kind')<>'checklistItem' AND COALESCE(json_extract(${tables.views}.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(${tables.views}.raw,'\$.successorSuppressed'),0)=0 ORDER BY ${tables.positions}.rank",
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
        .select(
          "SELECT id FROM ${tables.views} ORDER BY json_extract(raw,'\$.order'),id",
        )
        .map((row) => row['id'] as String);
    final retracted = retractedOperationIds(
      db
          .select(
            "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.operationUndone'",
          )
          .map((r) => LogEvent.decode(r['raw'] as String)),
    );
    // Views already contain the selected derived creation's exact clock/writer
    // stamp. Strict per-writer clocks identify that completion uniquely. Reuse
    // this projection after affected views update, instead of replaying every
    // successor's history again while rebuilding global manual order.
    final selectedSeedIds = <String, String>{
      for (final row in db.select(
        "SELECT e.id,json_extract(e.semantic,'\$.data.successor.id') AS successor FROM ${tables.events} e JOIN ${tables.views} v ON v.id=json_extract(e.semantic,'\$.data.successor.id') AND json_extract(v.raw,'\$.order')=printf('%019d:%s',e.clock,e.writer) WHERE json_extract(e.semantic,'\$.type') IN ('task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist')",
      ))
        row['successor'] as String: row['id'] as String,
    };
    final actions = db
        .select(
          "SELECT id,entity,json_extract(semantic,'\$.type') AS type,json_extract(semantic,'\$.data.before') AS before_id,json_extract(semantic,'\$.data.successor.id') AS successor FROM ${tables.events} WHERE json_extract(semantic,'\$.type') IN ('user.created','task.created','task.createdWithText','task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist','task.moved') ORDER BY clock,writer,seq",
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
    db.execute('DELETE FROM ${tables.positions}');
    for (var i = 0; i < ordered.length; i++) {
      db.execute('INSERT INTO ${tables.positions} VALUES (?,?)', [
        ordered[i],
        i,
      ]);
    }
    db.execute(
      "INSERT OR REPLACE INTO ${tables.metadata} VALUES ('order_projection','3')",
    );
  }

  /// Snapshot the completions represented by the currently displayed cache.
  /// Reopening must not cancel a completion that arrives after this observation.
  List<String> activeCompletionIds(String entity) {
    final events = db
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
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
    final receipts = await _appendUnifiedCommands(
      [(entity, type, data)],
      canCommit: canCommit,
      onPrepared: onPrepared,
    );
    return LogEvent.decode(receipts.single.raw);
  }

  void _requireWriterAppendReady() {
    if (_writerHasPendingAppend || pendingTextOperations.isNotEmpty) {
      throw WriterGuardFailure.unresolvedAppend();
    }
  }

  bool _baselineIncludes(LogEvent event, LogEvent baseline) {
    final head = (baseline.data['frontiers'] as Map)[event.writer] as Map?;
    return head != null && event.sequence <= (head['seq'] as int);
  }

  void _validateTextBaseline() {
    final roots = db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='text.baselineInitialized'",
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
        'SELECT raw FROM ${tables.events} WHERE writer=? AND seq=?',
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
      "SELECT value FROM ${tables.metadata} WHERE key='text_baseline_verified'",
    );
    if (verified.isEmpty || verified.single['value'] != root.id) {
      final fields = _baselineSeedFields(root);
      if (textBaselineSeedDigest(fields) != root.data['seedDigest']) {
        throw FormatFailure('Text baseline seed digest differs in ${root.id}.');
      }
      db.execute(
        "INSERT OR REPLACE INTO ${tables.metadata} VALUES ('text_baseline_verified',?)",
        [root.id],
      );
    }
    _textBaseline = root;
  }

  Map<String, Map<String, String>> _baselineSeedFields(LogEvent root) {
    final prefix = db
        .select('SELECT raw FROM ${tables.events}')
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
        protected:
            own.isNotEmpty ||
            anchored ||
            hasDurableChecklistActivity(prefix, entry.key),
      );
      grouped
          .putIfAbsent(entry.key, () => [])
          .add(successorCreation(selected.seed));
    }
    final fields = <String, Map<String, String>>{};
    for (final entry in grouped.entries) {
      if (entry.value.any((event) => event.type == 'task.createdWithText') ||
          successors[entry.key]?.any(
                (event) => hasNativeTaskSuccessor(event),
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

  /// Historical fixture construction only. The application initializes empty
  /// workspaces through [open], and never adopts an existing legacy workspace.
  Future<LogEvent> initializeSharedText({
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() => _initializeSharedText(onPrepared: onPrepared));

  Future<LogEvent> _initializeSharedText({
    void Function(OperationReceipt)? onPrepared,
    bool requireEmptyHistory = false,
  }) async {
    await _refresh();
    if (requireEmptyHistory &&
        db.select('SELECT 1 FROM ${tables.events} LIMIT 1').isNotEmpty) {
      throw FormatFailure(
        'New workspace history changed before text initialization. Restore its initialized history before opening.',
      );
    }
    if (textEngine == null) {
      throw FormatFailure('Native text support is unavailable.');
    }
    if (db
        .select(
          "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='text.baselineInitialized' LIMIT 1",
        )
        .isNotEmpty) {
      throw FormatFailure(
        'A text initialization record already exists. Wait for its history or resolve competing records.',
      );
    }
    final frontiers = <String, dynamic>{};
    for (final row in db.select(
      'SELECT name,last_seq,chain_head FROM ${tables.streams}',
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
    return _command(
      space,
      'text.baselineInitialized',
      {
        'codec': 'yrs-v1',
        'adapter': 1,
        'frontiers': frontiers,
        'seedDigest': digest,
      },
      onPrepared: onPrepared,
      canCommit: requireEmptyHistory
          ? () => db.select('SELECT 1 FROM ${tables.events} LIMIT 1').isEmpty
          : null,
    );
  }

  /// Same-session bytes reconcile an uncertain append; nothing retries on restart.
  List<OperationReceipt> get pendingTextOperations =>
      (unified?.pendingRecords ?? const <UnifiedRecord>[])
          .expand((r) => r.effects)
          .where((r) => r.task != null && _textTypes.contains(r.task!.type))
          .map((r) {
            final e = r.task!;
            return OperationReceipt(e.id, e.canonicalRaw!, e.entity);
          })
          .toList(growable: false);

  Future<LogEvent> retryTextOperation(OperationReceipt receipt) =>
      _serialize(() => _retryTextOperation(receipt));

  Future<LogEvent> _retryTextOperation(OperationReceipt receipt) async {
    await _refresh();
    final event = LogEvent.decode(receipt.raw);
    assertWorkspaceTaskTimeZonePolicy(event, timeZonePolicy);
    if (!_textTypes.contains(event.type) ||
        event.writer != writer ||
        event.space != space ||
        event.id != receipt.id ||
        event.entity != receipt.entity ||
        textEngine == null) {
      throw FormatFailure('Invalid prepared native text receipt.');
    }
    final present = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
      event.id,
    ]);
    if (present.isNotEmpty) {
      _requireConfirmed([receipt]);
      return event;
    }
    if (!unified!.pendingRecords
        .expand((r) => r.effects)
        .any((r) => r.task?.canonicalRaw == receipt.raw)) {
      throw FormatFailure(
        'Prepared native text receipt differs from the common reservation.',
      );
    }
    await unified!.recoverPreparedInProfileQueue();
    _requireConfirmed([receipt]);
    return event;
  }

  LogEvent _prepareCommand(
    String entity,
    String type,
    Map<String, dynamic> data,
    int seq,
    EventClock clock, {
    String? previousHash,
    LogEvent? pendingCreation,
  }) {
    final legacyTextChange =
        type == 'task.edited' &&
        (data.containsKey('title') || data.containsKey('description'));
    final textSnapshotRequired =
        type == 'task.completed' && data['successor'] != null;
    if (textSnapshotRequired &&
        textEngine != null &&
        db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=? LIMIT 1', [
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
        !isNativeTextCreation(type) &&
        textWriteBlocked != null &&
        !_hasNativeTextRoot(entity, _entityEvents(entity))) {
      throw FormatFailure(textWriteBlocked!);
    }
    final e = LogEvent.decode(
      LogEvent(space, writer, seq, clock, entity, type, data).encode(
        previousHash:
            previousHash ??
            (throw StateError('A common reservation is required.')),
      ),
    );
    assertWorkspaceTaskTimeZonePolicy(e, timeZonePolicy);
    final prior = [
      ..._entityEvents(entity),
      if (type == 'task.moved' && pendingCreation?.entity == entity)
        pendingCreation!,
    ];
    if (type == 'task.textEdited' || type == 'task.textEditUndone') {
      if (_hasInheritedText(entity)) _resolvedText(entity, pending: [e]);
      final nativeCreation = _hasNativeTextRoot(entity, prior);
      if (!nativeCreation && _textBaseline == null) {
        throw FormatFailure(
          textWriteBlocked ??
              'Restore verified shared-text initialization before saving this existing task.',
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
      final oldBaseline = _textBaseline;
      final oldBlocked = textWriteBlocked;
      void validate() {
        TextCache(
          db,
          textEngine!,
          memo: _recurringTextMemo,
          tables: tables,
        ).validatePackets([e]);
        if (type == 'text.baselineInitialized') {
          db.execute('INSERT INTO ${tables.events} VALUES (?,?,?,?,?,?,?)', [
            e.id,
            e.entity,
            e.writer,
            e.sequence,
            e.clock.value.toInt(),
            e.canonicalRaw,
            jsonEncode({'type': e.type, 'data': e.data}),
          ]);
          _validateTextBaseline();
          if (textWriteBlocked != null) throw FormatFailure(textWriteBlocked!);
        } else if (type == 'task.completedWithText' ||
            type == 'task.completedWithChecklist') {
          if (type == 'task.completedWithChecklist') {
            _validateChecklistCompletions(e);
          }
          if (hasNativeTaskSuccessor(e)) {
            _resolvedText(
              (data['successor'] as Map)['id'] as String,
              pending: [e],
            );
          }
        } else {
          _materializeText(projected, [...prior, e]);
        }
      }

      try {
        if (profileDatabase != null) {
          try {
            profileDatabase!.transaction<Never>(() {
              validate();
              throw const _DiscardTextValidation();
            });
          } on _DiscardTextValidation {
            // A successful validation is deliberately rolled back.
          }
        } else {
          db.execute('SAVEPOINT validate_text_command');
          try {
            validate();
          } finally {
            db.execute('ROLLBACK TO validate_text_command');
            db.execute('RELEASE validate_text_command');
          }
        }
      } finally {
        _textBaseline = oldBaseline;
        textWriteBlocked = oldBlocked;
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
          "SELECT id FROM ${tables.views} WHERE id=? AND json_extract(raw,'\$.kind')='user'",
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
    _validateHistoricalCompletions(e);
    _validateChecklistReferences(e);
    _validateChecklistCompletions(e);
    if (isTaskCompletion(type) &&
        data['successor'] == null &&
        type != 'task.completedKeepingSuccessor' &&
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
        "SELECT id FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN ('task.created','task.createdWithText','user.created')",
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
    bool reserveBeforeTextStaging = false,
  }) async {
    return _appendUnifiedCommands(
      commands,
      canCommit: canCommit,
      onPrepared: onPrepared,
    );
  }

  bool isCaptureConfirmed(String entity) =>
      !_writerHasPendingAppend && hasEntity(entity);

  /// Retry identities belong to the same capture; already present tasks are
  /// acknowledged without recreating them. UI updates happen after this batch.
  Future<TaskCaptureResult> createTasks(
    Map<String, String> titles,
    String assignee,
  ) => _serialize(() async {
    await _refresh();
    final anchor = rows
        .where((row) => row['kind'] == 'task')
        .map((row) => row['id'] as String)
        .firstOrNull;
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
      // Even an all-present retry must wait for its reserved exact suffix.
      _requireWriterAppendReady();
      await _appendCommands(
        [
          for (final (id, data) in commands)
            (
              id,
              textEngine == null ? 'task.created' : 'task.createdWithText',
              data,
            ),
          if (anchor != null)
            for (final (id, _) in commands)
              (id, 'task.moved', {'before': anchor}),
        ],
        onPrepared: prepared.add,
        reserveBeforeTextStaging: true,
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
    final byEntity = <String, List<OperationReceipt>>{};
    for (final receipt in prepared) {
      (byEntity[receipt.entity] ??= []).add(receipt);
    }
    final created = {
      ...present,
      for (final receipt in prepared.where(
        (r) =>
            confirmed.contains(r.id) &&
            LogEvent.decode(r.raw).type != 'task.moved',
      ))
        receipt.entity,
    };
    final committed = {
      ...present.where(isCaptureConfirmed),
      for (final entry in byEntity.entries)
        if (entry.value.every((r) => confirmed.contains(r.id))) entry.key,
    };
    return TaskCaptureResult(
      titles.keys.where(committed.contains),
      titles.keys.where((id) => !committed.contains(id)),
      titles.keys.where(created.contains),
      error,
    );
  });

  void _validateUndoReferences([LogEvent? pending]) {
    final invalidText = db.select(
      "SELECT u.id FROM ${tables.events} u JOIN ${tables.events} t ON t.id=json_extract(u.semantic,'\$.data.operation') WHERE json_extract(u.semantic,'\$.type')='task.textEditUndone' AND (u.entity<>t.entity OR t.clock>=u.clock OR json_extract(t.semantic,'\$.type')<>'task.textEdited') LIMIT 1",
    );
    if (invalidText.isNotEmpty) {
      throw FormatFailure(
        'Invalid text Undo reference in ${invalidText.single['id']}.',
      );
    }
    // A join revalidates resolved references, including newly imported targets.
    final invalid = db.select(
      "SELECT u.id FROM ${tables.events} u JOIN ${tables.events} t ON t.id=CASE WHEN json_extract(u.semantic,'\$.type')='task.operationUndone' THEN json_extract(u.semantic,'\$.data.operation') ELSE json_extract(u.semantic,'\$.data.completion') END WHERE json_extract(u.semantic,'\$.type') IN ('task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND (u.entity<>t.entity OR t.clock>=u.clock OR (json_extract(u.semantic,'\$.type')='task.completionUndone' AND json_extract(t.semantic,'\$.type') NOT IN ('task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist')) OR (json_extract(u.semantic,'\$.type')='task.recurringCompletionUndone' AND (json_extract(t.semantic,'\$.type') NOT IN ('task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist') OR json_extract(t.semantic,'\$.data.successor.id') IS NULL)) OR (json_extract(u.semantic,'\$.type')='task.operationUndone' AND (json_extract(t.semantic,'\$.type') NOT IN ('checklist.itemEdited','checklist.itemMoved','checklist.itemDeleted','task.edited','task.moved','task.deleted','task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist','task.completionUndone') OR (json_extract(t.semantic,'\$.type') IN ('task.completed','task.completedWithText','task.completedKeepingSuccessor','task.completedWithChecklist') AND json_extract(t.semantic,'\$.data.successor') IS NOT NULL)))) LIMIT 1",
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
      final targets = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
        ref,
      ]);
      if (targets.isNotEmpty) {
        validate(pending, LogEvent.decode(targets.single['raw'] as String));
      }
    }
    for (final row in db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type') IN ('task.textEditUndone','task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND COALESCE(json_extract(semantic,'\$.data.operation'),json_extract(semantic,'\$.data.completion'))=?",
      [pending.id],
    )) {
      validate(LogEvent.decode(row['raw'] as String), pending);
    }
  }

  void _validateMoves([LogEvent? pending]) {
    final moves = db
        .select(
          pending == null
              ? "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved'"
              : "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved' AND json_extract(semantic,'\$.data.before')=?",
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
              ? "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.tagChanges') IS NOT NULL"
              : "SELECT raw FROM ${tables.events} e WHERE EXISTS (SELECT 1 FROM json_each(json_extract(e.semantic,'\$.data.tagChanges.remove')) r WHERE r.value LIKE ?) OR e.entity=?",
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
        final rows = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
          eventId,
        ]);
        final target = pending?.id == eventId
            ? pending
            : rows.isEmpty
            ? null
            : LogEvent.decode(rows.first['raw'] as String);
        if (target == null) {
          final seeds = db.select(
            "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=?",
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
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
        .map((r) => LogEvent.decode(r['raw'] as String))
        .toList();
    final seeds = db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
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
    final copies = _itemCopySeeds(entity);
    if (copies.isNotEmpty) {
      own.add(checklistCopyCreation(copies.first.$1, copies.first.$2));
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
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [parent])
        .map((r) => LogEvent.decode(r['raw'] as String));
    final anchored = db.select(
      "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved' AND json_extract(semantic,'\$.data.before')=? LIMIT 1",
      [entity],
    ).isNotEmpty;
    return selectSuccessor(
      decoded,
      parentHistory,
      protected: own.isNotEmpty || anchored || _hasChecklistActivity(entity),
    );
  }

  Map<String, dynamic>? _projectEntity(
    String entity, {
    RecurringTextResolver? resolution,
    TextCache? textCache,
  }) {
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
    _materializeText(
      state,
      history,
      resolution: resolution,
      textCache: textCache,
    );
    _attachSuccessorSuppression(state);
    _attachChecklist(state, resolution: resolution, textCache: textCache);
    return state;
  }

  void _attachSuccessorSuppression(Map<String, dynamic> state) {
    final entity = state['id'] as String;
    final seeds = db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
      [entity],
    );
    if (seeds.isNotEmpty) {
      final own = db
          .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
          .map((r) => LogEvent.decode(r['raw'] as String))
          .toList();
      state['successorSuppressed'] = _successorSelection(
        entity,
        seeds,
        own,
      ).suppressed;
    }
  }

  void _materializeText(
    Map<String, dynamic> state,
    List<LogEvent> history, {
    RecurringTextResolver? resolution,
    TextCache? textCache,
  }) {
    if (textEngine == null) return;
    final entity = state['id'] as String;
    if (_hasInheritedText(entity)) {
      try {
        (textCache ??
                TextCache(
                  db,
                  textEngine!,
                  memo: _recurringTextMemo,
                  tables: tables,
                ))
            .materializeResolved(
              state,
              resolution?.resolve(entity) ??
                  _resolvedText(
                    entity,
                    pending: history
                        .where((event) => event.canonicalRaw != null)
                        .toList(),
                  ),
            );
      } on TextInheritancePending catch (pending) {
        // Retain the verified display if any; do not establish a guessed seed.
        final cached = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
          entity,
        ]);
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
      (event) => isNativeTextCreation(event.type),
    );
    if (!nativeCreation &&
        textWriteBlocked?.startsWith('Competing') == true &&
        history.any((event) => event.type == 'task.created') &&
        db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=? LIMIT 1', [
          state['id'],
        ]).isEmpty) {
      state['textUnavailable'] = textWriteBlocked;
      return;
    }
    if (basis != null &&
        !history.any((event) => isNativeTextCreation(event.type))) {
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
        db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=? LIMIT 1', [
          state['id'],
        ]).isNotEmpty) {
      (textCache ??
              TextCache(
                db,
                textEngine!,
                memo: _recurringTextMemo,
                tables: tables,
              ))
          .materialize(
            state,
            history,
            basis: basis,
            legacySeedText: seedText,
            basisKind: kind,
          );
    }
  }

  bool _hasInheritedText(String entity) =>
      db.select(
        "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.type') IN ('task.completedWithText','task.completedWithChecklist') AND json_extract(semantic,'\$.data.inheritance') IS NOT NULL AND json_extract(semantic,'\$.data.successor.id')=? LIMIT 1",
        [entity],
      ).isNotEmpty ||
      _itemCopySeeds(entity).isNotEmpty;

  bool _hasNativeTextRoot(String entity, List<LogEvent> history) =>
      history.any((event) => isNativeTextCreation(event.type)) ||
      _hasInheritedText(entity);

  Map<String, ResolvedTextField> _resolvedText(
    String entity, {
    List<LogEvent> pending = const [],
  }) => _textResolution(pending: pending).resolve(entity);

  RecurringTextResolver _textResolution({List<LogEvent> pending = const []}) =>
      RecurringTextResolver.fromCanonical(
        textEngine!,
        [
          ...db
              .select('SELECT raw FROM ${tables.events}')
              .map((row) => row['raw'] as String),
          ...pending.map((event) => event.canonicalRaw!),
        ],
        legacyRoots: _legacyTextRoots,
        memo: _recurringTextMemo,
        legacyScope: '${_textBaseline?.hash ?? ''}|${textWriteBlocked ?? ''}',
      );

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
                  ) ||
                  hasDurableChecklistActivity(prefix, entity),
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
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
        .map((row) => LogEvent.decode(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    final seeds = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=?",
          [entity],
        )
        .map((row) => LogEvent.decode(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    if (seeds.isNotEmpty) {
      final parent = db
          .select('SELECT raw FROM ${tables.events} WHERE entity=?', [
            seeds.first.entity,
          ])
          .map((row) => LogEvent.decode(row['raw'] as String))
          .where((event) => _baselineIncludes(event, baseline));
      final anchors = db
          .select(
            "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved' AND json_extract(semantic,'\$.data.before')=?",
            [entity],
          )
          .map((row) => LogEvent.decode(row['raw'] as String))
          .any((event) => _baselineIncludes(event, baseline));
      own.add(
        successorCreation(
          selectSuccessor(
            seeds,
            parent,
            protected:
                own.isNotEmpty ||
                anchors ||
                hasDurableChecklistActivity(
                  db
                      .select('SELECT raw FROM ${tables.events}')
                      .map((row) => LogEvent.decode(row['raw'] as String))
                      .where((event) => _baselineIncludes(event, baseline))
                      .toList(),
                  entity,
                ),
          ).seed,
        ),
      );
    }
    return own;
  }

  LogEvent? _historicalSuccessorInitialization(String entity) {
    if (textEngine == null) return null;
    final child = const Uuid().v5(entity, 'successor');
    final creations = _entityEvents(child).where(
      (event) => event.type == 'task.created' && event.canonicalRaw == null,
    );
    if (creations.length != 1) return null;
    final source = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
      creations.single.id,
    ]);
    if (source.isEmpty) return null;
    final event = LogEvent.decode(source.single['raw'] as String);
    if (!isHistoricalSuccessorInitialization(event) || event.entity != entity) {
      return null;
    }
    if (event.type == 'task.completedWithChecklist' ||
        hasNativeTaskSuccessor(event)) {
      // Checklist copies own item histories; native children also own their
      // saved task edits. Durable activity protects either initialized child,
      // including undone/deleted work, from later historical inheritance.
      final independent =
          db.select('SELECT 1 FROM ${tables.events} WHERE entity=? LIMIT 1', [
            child,
          ]).isNotEmpty ||
          db.select(
            "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved' AND json_extract(semantic,'\$.data.before')=? LIMIT 1",
            [child],
          ).isNotEmpty ||
          _hasChecklistActivity(child);
      if (independent) return event;
      // An unadopted native successor keeps the existing forward/concurrent
      // inheritance policy. The checks below belong to released scalar history.
      if (hasNativeTaskSuccessor(event)) return null;
    }
    // Preserve released scalar completion policy: its historical marker still
    // requires an independently initialized pair of parent/child documents.
    if (db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=? LIMIT 1', [
          entity,
        ]).isEmpty ||
        _hasInheritedText(child) ||
        db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=?', [
              child,
            ]).length !=
            2) {
      return null;
    }
    return event;
  }

  void _validateHistoricalCompletions([LogEvent? pending]) {
    final markers = <LogEvent>[
      for (final row in db.select(
        "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedKeepingSuccessor'",
      ))
        LogEvent.decode(row['raw'] as String),
      if (pending?.type == 'task.completedKeepingSuccessor') pending!,
    ];
    for (final marker in markers) {
      final retained = marker.data['retainedSuccessor'] as Map;
      final rows = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
        retained['completion'],
      ]);
      final known = verifyHistoricalCompletion(
        marker,
        rows.isEmpty ? null : LogEvent.decode(rows.single['raw'] as String),
      );
      if (!known && identical(marker, pending)) {
        throw FormatFailure(
          'Historical completion requires its earlier initialization history.',
        );
      }
    }
  }

  Future<LogEvent> complete(
    String entity, {
    DateTime? completionDay,
    DateTime? completionInstant,
    String? localZoneId,
    String? expectedChecklistSnapshot,
    bool requireIncomplete = false,
    void Function(OperationReceipt)? onPrepared,
  }) => _serialize(() async {
    await _refresh();
    final state = _projectEntity(entity);
    if (state == null || state['kind'] != 'task' || state['deleted'] == true) {
      throw FormatFailure('Unknown task.');
    }
    if (expectedChecklistSnapshot != null &&
        expectedChecklistSnapshot != jsonEncode(state['checklist'] ?? [])) {
      throw StaleTaskSnapshot();
    }
    if (requireIncomplete && state['completed'] == true) {
      throw StaleTaskSnapshot();
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
    final historical = schedule.recurrence == null
        ? null
        : _historicalSuccessorInitialization(entity);
    if (historical != null) {
      data['retainedSuccessor'] = {
        'id': const Uuid().v5(entity, 'successor'),
        'completion': historical.id,
        'hash': historical.hash,
      };
      return _command(
        entity,
        'task.completedKeepingSuccessor',
        data,
        expectedTaskSnapshot: taskSnapshot,
        onPrepared: onPrepared,
      );
    }
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
        db.select('SELECT 1 FROM ${tables.textFields} WHERE entity=? LIMIT 1', [
          entity,
        ]).isNotEmpty) {
      final fields = _resolvedText(entity);
      data['inheritance'] = {
        'codec': 'yrs-v1',
        'adapter': 2,
        'frontiers': {
          for (final row in db.select(
            'SELECT name,last_seq,chain_head FROM ${tables.streams}',
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
              'historyHash': entry.value.historyReference!.hash,
            },
        },
      };
      type = 'task.completedWithText';
    }
    if (data['successor'] != null && state.containsKey('checklist')) {
      final frontiers = <String, dynamic>{
        for (final row in db.select(
          'SELECT name,last_seq,chain_head FROM ${tables.streams}',
        ))
          (row['name'] as String).replaceFirst('.jsonl', ''): {
            'seq': row['last_seq'],
            'hash': row['chain_head'],
          },
      };
      data['checklist'] = _checklistCopy(
        entity,
        (data['successor'] as Map)['id'] as String,
        (state['checklist'] as List).cast<Map<String, dynamic>>(),
        frontiers,
      );
      type = 'task.completedWithChecklist';
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
    for (final row in rows) {
      if (row['checklist'] is List) {
        row['checklist'] = [
          for (final item in row['checklist'] as List)
            Map<String, dynamic>.from(item as Map)
              ..remove('title')
              ..remove('description'),
        ];
      }
    }
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

  /// A presentation upgrade, explicitly invoked by the application after open
  /// and external refresh. Replay itself is read-only. Each edit refreshes and
  /// checks the observed task snapshot through the normal v3 writer gate.
  /// Existing-Due rows are never changed. Concurrent older offline edits retain
  /// the protocol's existing last-writer ordering, not a new conditional merge.
  Future<OccurrenceDueMigrationResult> migrateOccurrenceDates({
    bool Function()? canCommit,
  }) => _serialize(
    () => _migrateOccurrenceDatesInProfileQueue(canCommit: canCommit),
  );

  Future<OccurrenceDueMigrationResult> refreshForWorkspace({
    bool migrateOccurrenceDates = false,
    bool Function()? canCommit,
  }) => _serialize(() async {
    final changed = await _refresh();
    if (!migrateOccurrenceDates || canCommit?.call() == false) {
      return OccurrenceDueMigrationResult(0, const {}, null, changed: changed);
    }
    return _migrateOccurrenceDatesInProfileQueue(
      canCommit: canCommit,
      initialChanged: changed,
    );
  });

  Future<OccurrenceDueMigrationResult> _migrateOccurrenceDatesInProfileQueue({
    bool Function()? canCommit,
    bool? initialChanged,
  }) async {
    var changed = initialChanged ?? await _refresh();
    final conflicts = <String, String>{};
    var migrated = 0;
    Object? failure;
    final ids = [
      for (final task in rows)
        if (planOccurrenceDueMigration(task) != null) task['id'] as String,
    ];
    for (final id in ids) {
      if (canCommit?.call() == false) break;
      // A preceding append may have admitted a newly synced task edit.
      changed = await _refresh() || changed;
      final current = rows.where((row) => row['id'] == id).firstOrNull;
      if (current == null) continue;
      final plan = planOccurrenceDueMigration(current);
      if (plan == null) continue;
      if (plan.conflict != null) {
        conflicts[id] = plan.conflict!;
        continue;
      }
      try {
        await _command(
          id,
          'task.edited',
          {'schedule': plan.afterSchedule!.toJson()},
          expectedTaskSnapshot: taskSnapshot,
          canCommit: canCommit,
        );
        migrated++;
        changed = true;
      } on StaleTaskSnapshot {
        changed = true;
        // Do not append a stale plan. A later external refresh can replan it.
        continue;
      } catch (error) {
        changed = true;
        // Stop after a provider/writer failure; normal recovery must acknowledge
        // any prepared append before a new operation can be admitted.
        failure = error;
        break;
      }
    }
    return OccurrenceDueMigrationResult(
      migrated,
      Map.unmodifiable(conflicts),
      failure,
      changed: changed,
    );
  }

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

  /// Exact admitted effect bytes acknowledge a save. Logical effect IDs
  /// are independent of physical action positions.
  Set<String> confirmedOperations(Iterable<OperationReceipt> receipts) => {
    for (final r in receipts)
      if (r.id.startsWith('$writer:') &&
          db.select('SELECT 1 FROM ${tables.events} WHERE id=? AND raw=?', [
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
    "SELECT 1 FROM ${tables.events} WHERE (json_extract(semantic,'\$.type') IN ('task.operationUndone','task.textEditUndone') AND json_extract(semantic,'\$.data.operation')=?) OR (json_extract(semantic,'\$.type')='task.recurringCompletionUndone' AND json_extract(semantic,'\$.data.completion')=?)",
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
      final found = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
        id,
      ]);
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
    final retainedHistorical = {
      for (final id in operations.where(undone.contains))
        if (targets[id]!.type == 'task.completedKeepingSuccessor')
          (targets[id]!.data['retainedSuccessor'] as Map)['id'] as String,
    };
    final suppressed = successors
        .where((id) => _projectEntity(id)?['successorSuppressed'] == true)
        .length;
    return TaskUndoResult(
      operations.where(undone.contains),
      operations.where((id) => !undone.contains(id)),
      newer,
      error: error,
      retainedSuccessorCount:
          {...successors, ...retainedHistorical}.length - suppressed,
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
        if (profileDatabase == null) db.close();
      } finally {
        _recurringTextMemo.clear();
        _viewChanges.clear();
        unified?.detachProjectionInProfileQueue(this);
        await lock?.close();
        if (_locationKey != null) {
          profileDatabase!.releaseWorkspace(_locationKey);
        }
        await _closeOwnedResources?.call();
      }
    });
  }
}

class _DiscardTextValidation implements Exception {
  const _DiscardTextValidation();
}

class _SemanticValidationFolder implements LogFolder {
  @override
  String get location => 'semantic-preflight';
  @override
  Future<List<LogFileInfo>> list() async =>
      throw StateError('Preflight cannot read transport.');
  @override
  Future<Uint8List> read(String name) async =>
      throw StateError('Preflight cannot read transport.');
  @override
  Future<void> append(String name, Uint8List bytes) async =>
      throw StateError('Preflight cannot write.');
  @override
  Future<void> create(String name, Uint8List bytes) async =>
      throw StateError('Preflight cannot write.');
}
