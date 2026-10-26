import '../domain/completion_instant.dart';
import '../domain/timed_view.dart';
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
import 'checklist_copy_index.dart';
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

// Private, action-local evidence; never persisted or accepted from a snapshot DTO.
typedef _FirstDerivedTextSeed = ({
  String kind,
  String? parent,
  String seed,
  String sourceParent,
  String? sourceItem,
  bool explicit,
});

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
  int _copySeedScopeDepth = 0;
  ChecklistCopyIndex? _copySeedIndex;
  bool _copySeedIndexUnavailable = false;
  void _invalidateCopySeedIndex() {
    _copySeedIndex = null;
    _copySeedIndexUnavailable = false;
  }

  T _withCopySeedIndex<T>(T Function() body) {
    final outer = _copySeedScopeDepth++ == 0;
    if (outer) _invalidateCopySeedIndex();
    try {
      return body();
    } finally {
      _copySeedScopeDepth--;
      if (outer) _invalidateCopySeedIndex();
    }
  }

  RecurringTextInput? _canonicalTextInput;
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

  static String canonicalTaskRevision(Iterable<LogEvent> events) =>
      _taskProjectionRevision(events);

  bool _projectionIndexesReady = false;

  void _ensureProjectionIndexes() {
    if (_projectionIndexesReady) return;
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS ${tables.events}_entity ON ${tables.events}(entity)',
      "CREATE INDEX IF NOT EXISTS ${tables.events}_successor ON ${tables.events}(json_extract(semantic,'\$.data.successor.id'))",
      "CREATE INDEX IF NOT EXISTS ${tables.events}_type_parent ON ${tables.events}(json_extract(semantic,'\$.type'),json_extract(semantic,'\$.data.parent'))",
      "CREATE INDEX IF NOT EXISTS ${tables.events}_type_before ON ${tables.events}(json_extract(semantic,'\$.type'),json_extract(semantic,'\$.data.before'))",
      "CREATE INDEX IF NOT EXISTS ${tables.views}_occurrence_due ON ${tables.views}(id) WHERE json_extract(raw,'\$.kind')='task' AND COALESCE(json_extract(raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(raw,'\$.successorSuppressed'),0)=0 AND json_extract(raw,'\$.schedule.dueDate') IS NULL AND json_extract(raw,'\$.schedule.scheduledDate') IS NOT NULL",
    ]) {
      db.execute(sql);
    }
    _projectionIndexesReady = true;
  }

  ({Set<String> projectedIds, bool orderRebuilt}) _replaySemanticEvents(
    List<LogEvent> events, {
    bool incremental = false,
    bool settledDelta = false,
    bool knownReadyDelta = false,
    bool auditCanonicalReferences = true,
  }) {
    TextCache? cache;
    try {
      _invalidateCopySeedIndex();
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
      _canonicalTextInput = incremental
          ? _canonicalTextInput?.appendedCanonical(
              events.map((event) => event.canonicalRaw!),
              memo: _recurringTextMemo,
            )
          : null;
      if (_canonicalTextInput?.cacheable == false) _canonicalTextInput = null;
      // Build expression indexes only after old disposable rows were cleared
      // and known canonical events inserted. An old malformed cache must reach
      // its normal canonical rebuild before JSON index expressions evaluate.
      _ensureProjectionIndexes();
      final writers = events.map((e) => e.writer).toSet();
      for (final author in writers) {
        final ordered = events.where((e) => e.writer == author).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
        final last = ordered.last;
        db.execute(
          'INSERT OR REPLACE INTO ${tables.streams} VALUES (?,?,?,?,?,?,?,?,?)',
          [
            '$author.jsonl',
            0,
            '',
            '',
            0,
            0,
            last.hash,
            last.sequence,
            last.clock.value.toInt(),
          ],
        );
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
      final previousBaseline = _textBaseline?.id;
      final previousTextBlocked = textWriteBlocked;
      _validateTextBaseline();
      RecurringTextResolver? resolution;
      if (auditCanonicalReferences) {
        if (settledDelta || knownReadyDelta) {
          for (final event in events) {
            if (event.type == 'task.completedWithChecklist') {
              resolution ??= _textResolution(
                entities: {
                  for (final changed in events) ...{
                    changed.entity,
                    if (changed.data['successor'] is Map)
                      (changed.data['successor'] as Map)['id'] as String,
                    if (changed.type == 'task.completedWithChecklist')
                      for (final item
                          in (changed.data['checklist'] as Map)['items']
                              as List)
                        (item as Map)['id'] as String,
                    if (changed.type == 'task.moved' &&
                        changed.data['before'] is String)
                      changed.data['before'] as String,
                  },
                },
              );
              _validateChecklistCompletions(event, false, resolution);
            }
            _validateUndoReferences(event);
            _validateTagReferences(event);
            _validateMoves(event);
            if (knownReadyDelta) _validateHistoricalCompletions(event, false);
            if (knownReadyDelta || event.type.startsWith('checklist.')) {
              _validateChecklistReferences(
                event,
                scoped: true,
                enforceLocalAvailability: false,
              );
            }
          }
        } else {
          if (textEngine != null &&
              db
                  .select(
                    "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedWithChecklist' LIMIT 1",
                  )
                  .isNotEmpty) {
            resolution = _textResolution();
          }
          _validateSemanticReferences(resolution);
        }
      }
      final entities = events.map((e) => e.entity).toSet();
      if (incremental) {
        // Baseline selection affects every text field. A normal edit/completion
        // changes only its entity, derived births and unresolved dependants.
        if (events.any((e) => e.type == 'text.baselineInitialized') ||
            previousBaseline != _textBaseline?.id ||
            previousTextBlocked != textWriteBlocked) {
          entities.addAll(
            db
                .select('SELECT id FROM ${tables.views}')
                .map((r) => r['id'] as String),
          );
          entities.addAll(
            db
                .select('SELECT DISTINCT entity FROM ${tables.events}')
                .map((r) => r['entity'] as String),
          );
        }
        entities.addAll(
          db
              .select(
                "SELECT id FROM ${tables.views} WHERE json_extract(raw,'\$.textInheritancePending')=1",
              )
              .map((r) => r['id'] as String),
        );
      }
      for (final e in events) {
        if (e.type == 'task.moved' && e.data['before'] is String) {
          entities.add(e.data['before'] as String);
        }
        entities.addAll(
          db
              .select(
                "SELECT json_extract(semantic,'\$.data.successor.id') AS child FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.data.successor.id') IS NOT NULL",
                [e.entity],
              )
              .map((r) => r['child'] as String),
        );
        if (e.type == 'task.recurringCompletionUndone') {
          entities.add(const Uuid().v5(e.entity, 'successor'));
        }
        if (isTaskCompletion(e.type) && e.data['successor'] is Map) {
          entities.add((e.data['successor'] as Map)['id'] as String);
        }
        if (e.type == 'task.completedWithChecklist') {
          for (final item in (e.data['checklist'] as Map)['items'] as List) {
            entities.add((item as Map)['id'] as String);
          }
        }
      }
      for (final entity in entities.toList()) {
        final parent = _checklistParent(entity);
        if (parent != null) entities.add(parent);
      }
      resolution ??=
          textEngine != null &&
              (!incremental || entities.any(_hasInheritedText))
          ? _textResolution(entities: entities)
          : null;
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
        } else if (incremental) {
          db.execute('DELETE FROM ${tables.views} WHERE id=?', [entity]);
        }
      }
      final orderRebuilt =
          !incremental ||
          events.any(
            (event) =>
                isTaskCompletion(event.type) && event.data['successor'] is Map,
          ) ||
          events.any(
            (e) =>
                e.type == 'task.createdWithText' ||
                e.type == 'checklist.itemCreated',
          ) ||
          (!settledDelta ||
                  events.any(
                    (e) =>
                        e.type == 'task.moved' ||
                        (e.type == 'task.operationUndone' &&
                            _undoMayChangeGlobalOrder(e)) ||
                        e.type == 'task.recurringCompletionUndone',
                  )) &&
              events.any(
                (e) => const {
                  'task.created',
                  'task.createdWithText',
                  'user.created',
                  'task.completed',
                  'task.completedWithText',
                  'task.completedWithChecklist',
                  'checklist.itemCreated',
                  'task.moved',
                  'task.operationUndone',
                  'task.recurringCompletionUndone',
                }.contains(e.type),
              );
      if (orderRebuilt) {
        _rebuildOrder();
      }
      return (
        projectedIds: Set.unmodifiable(entities),
        orderRebuilt: orderRebuilt,
      );
    } catch (_) {
      _canonicalTextInput = null;
      rethrow;
    } finally {
      cache?.close();
    }
  }

  void _validateSemanticReferences([RecurringTextResolver? resolution]) {
    _validateUndoReferences();
    _validateMoves();
    _validateTagReferences();
    _validateHistoricalCompletions();
    _validateChecklistReferences(null);
    _validateChecklistCompletions(null, true, resolution);
  }

  // A derived birth becomes a stable point target only AFTER independent
  // canonical activity has protected its selected seed. Merely materialized
  // children, private drafts and order anchors do not establish that boundary.
  // Callers additionally require the complete prior graph to be ready.
  bool _hasReadyDerivedIdentity(String entity, String kind, Set<String> ready) {
    if (kind != 'task' && kind != 'checklistItem') return false;
    final own = db
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
        .toList();
    if (!own.any((event) => ready.contains(event.id))) return false;
    if (kind == 'checklistItem') {
      final copies = _itemCopySeeds(entity);
      return copies.isNotEmpty && ready.contains(copies.first.$1.id);
    }
    final seeds = db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
      [entity],
    );
    return seeds.isNotEmpty &&
        ready.contains(_successorSelection(entity, seeds, own).seed.id);
  }

  // Capture selected prior seeds BEFORE insertion. Untouched re-completion
  // cannot rebind an old ready dependency; ambiguous/protected cases fall back.
  Map<String, String>? _recurringActionSeeds(
    List<LogEvent> delta,
    Set<String> ready,
  ) {
    if (delta.length != 1) return null;
    final event = delta.single;
    if (!const {
          'task.completedWithText',
          'task.completedWithChecklist',
        }.contains(event.type) ||
        event.data['successor'] is! Map) {
      return null;
    }
    final parentBirths = db.select(
      "SELECT id FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN ('task.created','task.createdWithText')",
      [event.entity],
    );
    if (!parentBirths.any((row) => ready.contains(row['id'])) &&
        !_hasReadyDerivedIdentity(event.entity, 'task', ready)) {
      return null;
    }
    final parent = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
      event.entity,
    ]);
    if (parent.length != 1 ||
        (jsonDecode(parent.single['raw'] as String) as Map)['kind'] != 'task') {
      return null;
    }
    final successor = (event.data['successor'] as Map)['id'] as String;
    final children = <String>[successor];
    final sources = <String, String>{};
    if (event.type == 'task.completedWithChecklist') {
      for (final item in (event.data['checklist'] as Map)['items'] as List) {
        children.add((item as Map)['id'] as String);
        sources[item['id'] as String] = item['source'] as String;
      }
    }
    if (children.toSet().length != children.length) return null;
    final prior = <String, String>{};
    for (final child in children) {
      if (db.select('SELECT 1 FROM ${tables.events} WHERE entity=? LIMIT 1', [
        child,
      ]).isNotEmpty) {
        return null;
      }
      final views = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
        child,
      ]);
      final seeds = db.select(
        "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
        [child],
      );
      final copies = _itemCopySeeds(child);
      if (views.isEmpty && seeds.isEmpty && copies.isEmpty) continue;
      if (views.length != 1) return null;
      final state = jsonDecode(views.single['raw'] as String) as Map;
      if (child == successor) {
        if (state['kind'] != 'task' ||
            seeds.isEmpty ||
            copies.isNotEmpty ||
            seeds.any(
              (row) =>
                  _recurringTextMemo
                      .decodeCanonical(row['raw'] as String)
                      .entity !=
                  event.entity,
            )) {
          return null;
        }
        // A retained marker is an old readiness dependency even without child
        // activity. Rebinding its birth could form marker -> new birth -> marker.
        if (db.select(
          "SELECT 1 FROM ${tables.events} WHERE json_extract(semantic,'\$.data.retainedSuccessor.id')=? LIMIT 1",
          [child],
        ).isNotEmpty) {
          return null;
        }
        final selected = _successorSelection(child, seeds, const []).seed.id;
        if (!ready.contains(selected)) return null;
        prior[child] = selected;
      } else {
        if (state['kind'] != 'checklistItem' ||
            state['parent'] != successor ||
            seeds.isNotEmpty ||
            copies.isEmpty ||
            copies.any(
              (copy) =>
                  copy.$1.entity != event.entity ||
                  copy.$2['source'] != sources[child],
            )) {
          return null;
        }
        final selected = copies.first.$1.id;
        if (!ready.contains(selected)) return null;
        prior[child] = selected;
      }
    }
    for (final descriptor in [
      event.data['inheritance'],
      event.data['checklist'],
    ]) {
      if (descriptor is! Map || descriptor['frontiers'] is! Map) continue;
      for (final entry in (descriptor['frontiers'] as Map).entries) {
        final seq = (entry.value as Map)['seq'] as int;
        if (seq > 0 && !ready.contains('${entry.key}:$seq')) return null;
      }
    }
    return Map.unmodifiable(prior);
  }

  _FirstDerivedTextSeed? _firstDerivedTextSeed(
    String entity,
    String kind,
    Set<String> ready, {
    bool allowExplicit = false,
  }) {
    final rows = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
      entity,
    ]);
    if (rows.length != 1) return null;
    final state = jsonDecode(rows.single['raw'] as String) as Map;
    final parent = state['parent'];
    if (state['kind'] != kind ||
        parent != null && parent is! String ||
        state['deleted'] == true ||
        state['successorSuppressed'] == true ||
        state['textUnavailable'] != null ||
        state['textInheritancePending'] == true) {
      return null;
    }
    final births = db.select(
      "SELECT raw FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN ('task.created','task.createdWithText','checklist.itemCreated')",
      [entity],
    );
    final seeds = db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
      [entity],
    );
    final copies = _itemCopySeeds(entity);
    if (births.isNotEmpty) {
      if (!allowExplicit ||
          kind != 'task' ||
          births.length != 1 ||
          seeds.isNotEmpty ||
          copies.isNotEmpty) {
        return null;
      }
      final birth = _recurringTextMemo.decodeCanonical(
        births.single['raw'] as String,
      );
      if (!ready.contains(birth.id)) return null;
      return (
        kind: kind,
        parent: parent as String?,
        seed: birth.id,
        sourceParent: entity,
        sourceItem: null,
        explicit: true,
      );
    }
    if (kind == 'task') {
      if (seeds.isEmpty || copies.isNotEmpty) return null;
      final first = _recurringTextMemo.decodeCanonical(
        seeds.first['raw'] as String,
      );
      if (!const {
            'task.completedWithText',
            'task.completedWithChecklist',
          }.contains(first.type) ||
          first.data['inheritance'] is! Map ||
          !ready.contains(first.id) ||
          seeds.any(
            (row) =>
                _recurringTextMemo
                    .decodeCanonical(row['raw'] as String)
                    .entity !=
                first.entity,
          )) {
        return null;
      }
      final own = db
          .select('SELECT raw FROM ${tables.events} WHERE entity=?', [entity])
          .map(
            (row) => _recurringTextMemo.decodeCanonical(row['raw'] as String),
          )
          .toList();
      final selected = _successorSelection(entity, seeds, own);
      // A first durable activity protects the earliest seed. Do not treat
      // an unprotected later survivor as the same birth.
      if (selected.suppressed || selected.seed.id != first.id) return null;
      return (
        kind: kind,
        parent: parent as String?,
        seed: first.id,
        sourceParent: first.entity,
        sourceItem: null,
        explicit: false,
      );
    }
    if (kind != 'checklistItem' || seeds.isNotEmpty || copies.isEmpty) {
      return null;
    }
    final first = copies.first;
    final source = first.$2['source'];
    final successor = (first.$1.data['successor'] as Map?)?['id'];
    if (source is! String ||
        parent != successor ||
        first.$1.data['inheritance'] is! Map ||
        !ready.contains(first.$1.id) ||
        copies.any(
          (copy) =>
              copy.$1.entity != first.$1.entity ||
              (copy.$1.data['successor'] as Map?)?['id'] != parent ||
              copy.$2['source'] != source,
        )) {
      return null;
    }
    return (
      kind: kind,
      parent: parent as String?,
      seed: first.$1.id,
      sourceParent: first.$1.entity,
      sourceItem: source,
      explicit: false,
    );
  }

  Map<String, _FirstDerivedTextSeed>? _firstDerivedActionSeeds(
    List<LogEvent> delta,
    Set<String> ready,
  ) {
    if (delta.length != 1) return null;
    final event = delta.single;
    final pureText =
        event.type == 'task.textEdited' &&
        event.data.length == 1 &&
        event.data['changes'] is Map &&
        (event.data['changes'] as Map).isNotEmpty;
    final taskMetadata =
        (event.type == 'task.edited' || event.type == 'task.textEdited') &&
        event.data.isNotEmpty &&
        event.data.keys.every(
          (key) =>
              key == 'schedule' ||
              key == 'assignee' ||
              key == 'tagChanges' ||
              (event.type == 'task.textEdited' && key == 'changes'),
        ) &&
        (event.type != 'task.textEdited' ||
            (event.data['changes'] is Map &&
                (event.data['changes'] as Map).isNotEmpty));
    final copiedCheckbox =
        event.type == 'checklist.itemEdited' &&
        event.data.length == 1 &&
        event.data['completed'] is bool;
    if ((!pureText && !taskMetadata && !copiedCheckbox) ||
        db.select('SELECT 1 FROM ${tables.events} WHERE entity=? LIMIT 1', [
          event.entity,
        ]).isNotEmpty) {
      return null;
    }
    final rows = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
      event.entity,
    ]);
    if (rows.length != 1) return null;
    final state = jsonDecode(rows.single['raw'] as String) as Map;
    final kind = state['kind'];
    if (kind != 'task' && kind != 'checklistItem') return null;
    if (!pureText &&
        !((kind == 'task' && taskMetadata) ||
            (kind == 'checklistItem' && copiedCheckbox))) {
      return null;
    }
    final target = _firstDerivedTextSeed(event.entity, kind as String, ready);
    if (target == null || target.explicit) return null;
    final proof = <String, _FirstDerivedTextSeed>{event.entity: target};
    if (kind == 'checklistItem') {
      final parent = target.parent;
      if (parent == null || parent == event.entity) return null;
      final parentSeed = _firstDerivedTextSeed(
        parent,
        'task',
        ready,
        allowExplicit: true,
      );
      if (parentSeed == null) return null;
      proof[parent] = parentSeed;
    }
    // The private identity proof only supplies the otherwise missing birth.
    // Reuse every existing shape and dependency guard before it can be used.
    return _settledActionTargets(delta, ready, firstActivitySeeds: proof)
        ? Map.unmodifiable(proof)
        : null;
  }

  bool _settledActionTargets(
    List<LogEvent> delta,
    Set<String> ready, {
    Map<String, _FirstDerivedTextSeed> firstActivitySeeds = const {},
  }) {
    if (_recurringActionSeeds(delta, ready) != null) return true;
    if (delta.isEmpty) return false;
    final groups = <String, List<LogEvent>>{};
    for (final event in delta) {
      (groups[event.entity] ??= []).add(event);
    }
    final captured = <String>{};
    for (final group in groups.entries) {
      if (group.value.length == 1) continue;
      if (group.value.length != 2 ||
          group.value.where((e) => e.type == 'task.createdWithText').length !=
              1 ||
          group.value.where((e) => e.type == 'task.moved').length != 1) {
        return false;
      }
      captured.add(group.key);
    }
    bool hasReadyBirth(String entity, List<String> types) => db
        .select(
          "SELECT id FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN (${List.filled(types.length, '?').join(',')})",
          [entity, ...types],
        )
        .any((r) => ready.contains(r['id']));
    Map<String, dynamic>? known(String entity, String kind) {
      final rows = db.select('SELECT raw FROM ${tables.views} WHERE id=?', [
        entity,
      ]);
      if (rows.length != 1) return null;
      final raw = rows.single['raw'] as String;
      Map<String, dynamic>? state;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded['kind'] != kind) return null;
          state = decoded;
        }
      } on FormatException {
        // Retain the existing proof/fallback and invalid-cache error ordering.
        // Only a successfully decoded wrong-kind view may short-circuit it.
      }
      final births = kind == 'user'
          ? ['user.created']
          : kind == 'task'
          ? ['task.created', 'task.createdWithText']
          : ['checklist.itemCreated'];
      if (!hasReadyBirth(entity, births) &&
          !_hasReadyDerivedIdentity(entity, kind, ready) &&
          firstActivitySeeds[entity]?.kind != kind) {
        return null;
      }
      state ??= jsonDecode(raw) as Map<String, dynamic>;
      return state['kind'] == kind ? state : null;
    }

    bool uniqueBirth(String id) =>
        db.select('SELECT 1 FROM ${tables.views} WHERE id=?', [id]).isEmpty &&
        db.select(
          "SELECT 1 FROM ${tables.events} WHERE entity=? OR json_extract(semantic,'\$.data.successor.id')=? LIMIT 1",
          [id, id],
        ).isEmpty &&
        _itemCopySeeds(id).isEmpty;
    bool metadata(LogEvent e) {
      if (!{'task.edited', 'task.textEdited'}.contains(e.type) ||
          !e.data.keys.every(
            (k) =>
                k == 'changes' ||
                k == 'schedule' ||
                k == 'assignee' ||
                k == 'tagChanges',
          )) {
        return false;
      }
      if (e.data.containsKey('assignee') &&
          known(e.data['assignee'] as String, 'user') == null) {
        return false;
      }
      if (e.data['tagChanges'] is Map) {
        for (final token in (e.data['tagChanges'] as Map)['remove'] as List) {
          final parts = (token as String).split(':');
          if (!ready.contains(parts.take(2).join(':'))) return false;
        }
      }
      return true;
    }

    bool simpleCompletion(LogEvent e) =>
        e.type == 'task.completed' &&
        e.data.containsKey('completedInstant') &&
        e.data.keys.every((k) => k == 'completedInstant');
    bool taskMove(LogEvent e) =>
        e.type == 'task.moved' &&
        (e.data['before'] == null ||
            known(e.data['before'] as String, 'task') != null);
    bool itemChange(LogEvent e) {
      if (e.type == 'checklist.itemEdited') {
        return e.data.containsKey('completed') &&
            e.data.keys.every((k) => k == 'completed');
      }
      if (e.type == 'checklist.itemDeleted') return e.data.isEmpty;
      if (e.type != 'checklist.itemMoved') return false;
      final source = known(e.entity, 'checklistItem');
      final before = e.data['before'];
      if (source == null) return false;
      if (before == null) return true;
      final anchor = known(before as String, 'checklistItem');
      return anchor != null && anchor['parent'] == source['parent'];
    }

    for (final event in delta) {
      if (event.type == 'task.createdWithText') {
        if (!uniqueBirth(event.entity) ||
            known(event.data['assignee'] as String, 'user') == null) {
          return false;
        }
        continue;
      }
      if (event.type == 'checklist.itemCreated') {
        if (!uniqueBirth(event.entity) ||
            known(event.data['parent'] as String, 'task') == null) {
          return false;
        }
        final before = event.data['before'];
        if (before != null) {
          final anchor = known(before as String, 'checklistItem');
          if (anchor == null || anchor['parent'] != event.data['parent']) {
            return false;
          }
        }
        continue;
      }
      if (captured.contains(event.entity) && event.type == 'task.moved') {
        if (!taskMove(event)) return false;
        continue;
      }
      var kind = 'task';
      if (metadata(event)) {
        // Plain native text also supports explicit checklist items.
        if (event.type == 'task.textEdited' &&
            event.data.keys.every((k) => k == 'changes') &&
            known(event.entity, 'checklistItem') != null) {
          kind = 'checklistItem';
        }
      } else if (event.type == 'task.textEditUndone' &&
          event.data.keys.every((k) => k == 'operation' || k == 'changes') &&
          ready.contains(event.data['operation'])) {
        if (known(event.entity, 'checklistItem') != null) {
          kind = 'checklistItem';
        }
      } else if (simpleCompletion(event) ||
          event.type == 'task.deleted' && event.data.isEmpty ||
          taskMove(event)) {
        // Explicit ready Task birth below excludes first derived activity.
      } else if (itemChange(event)) {
        kind = 'checklistItem';
      } else if ((event.type == 'task.operationUndone' &&
              event.data.keys.every((k) => k == 'operation')) ||
          (event.type == 'task.completionUndone' &&
              event.data.keys.every((k) => k == 'completion'))) {
        final ref =
            event.data[event.type == 'task.operationUndone'
                ? 'operation'
                : 'completion'];
        if (!ready.contains(ref)) return false;
        final rows = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
          ref,
        ]);
        if (rows.length != 1) return false;
        final old = _recurringTextMemo.decodeCanonical(
          rows.single['raw'] as String,
        );
        if (simpleCompletion(old)) {
          // Scoped Undo validation checks actual type, clock and entity.
        } else if (event.type == 'task.operationUndone' &&
            (metadata(old) ||
                taskMove(old) ||
                old.type == 'task.deleted' && old.data.isEmpty)) {
          // The referenced operation has only point dependencies.
        } else if (event.type == 'task.operationUndone' && itemChange(old)) {
          kind = 'checklistItem';
        } else {
          return false;
        }
      } else {
        return false;
      }
      if (known(event.entity, kind) == null) return false;
    }
    return true;
  }

  String? _checklistParent(String entity) {
    final own = db.select(
      "SELECT json_extract(semantic,'\$.data.parent') AS parent FROM ${tables.events} WHERE entity=? AND json_extract(semantic,'\$.type')='checklist.itemCreated'",
      [entity],
    );
    if (own.isNotEmpty) return own.first['parent'] as String;
    final copies = _itemCopySeeds(entity);
    return copies.isEmpty
        ? null
        : (copies.first.$1.data['successor'] as Map)['id'] as String;
  }

  Set<String> _semanticReadyIds(List<LogEvent> events) {
    final states = {
      for (final r in db.select('SELECT id,raw FROM ${tables.views}'))
        r['id'] as String: jsonDecode(r['raw'] as String) as Map,
    };
    final births = <String, String>{};
    final copiedBirths = <String, LogEvent>{};
    final derived = <String>{}, nativeSeeds = <String>{};
    final eventsByEntity = <String, List<LogEvent>>{};

    for (final e in events) {
      (eventsByEntity[e.entity] ??= []).add(e);
      if (isNativeTextCreation(e.type)) nativeSeeds.add(e.entity);
      if (const {
        'user.created',
        'task.created',
        'task.createdWithText',
        'checklist.itemCreated',
      }.contains(e.type)) {
        births[e.entity] = e.id;
      }
      if (isTaskCompletion(e.type) && e.data['successor'] is Map) {
        final child = (e.data['successor'] as Map)['id'] as String;
        births[child] = e.id;
        derived.add(child);
      }
      if (e.type == 'task.completedWithChecklist') {
        for (final item in (e.data['checklist'] as Map)['items'] as List) {
          final child = (item as Map)['id'] as String;
          births[child] = e.id;
          derived.add(child);
          final previous = copiedBirths[child];
          if (previous == null || compareEvents(e, previous) < 0) {
            copiedBirths[child] = e;
          }
        }
      }
    }
    // Resolve derived births with the exact same seed selection used by rows.
    for (final child in derived) {
      final seeds = db.select(
        "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
        [child],
      );
      if (seeds.isNotEmpty) {
        final own = eventsByEntity[child] ?? const <LogEvent>[];
        births[child] = _successorSelection(child, seeds, own).seed.id;
      } else {
        // The full oracle already visited every strict canonical completion.
        // Reuse its earliest claim instead of resolving each copied identity's
        // transitive text closure again. Retractions/competing claims remain in
        // this index, exactly as in _itemCopySeeds().first.
        final copied = copiedBirths[child];
        if (copied != null) births[child] = copied.id;
      }
    }
    final birthsByEvent = <String, List<String>>{};
    for (final entry in births.entries) {
      (birthsByEvent[entry.value] ??= []).add(entry.key);
    }
    final inherited = <String, bool>{};
    final nativePending = <String>{};
    if (textEngine != null) {
      for (final r in db.select('SELECT * FROM ${tables.textFields}')) {
        if (r['adapter'] == 2) {
          continue; // resolver already checks shared history
        }
        if (textEngine!.checkpointHasPending(
          NativeTextCheckpoint(
            NativeTextState.fromBytes(r['state'] as Uint8List),
          ),
          limits: NativeTextLimits(
            visibleUtf16: r['field'] == 'title' ? 500 : 10000,
          ),
        )) {
          nativePending.add(r['entity'] as String);
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
          final hasSeed = nativeSeeds.contains(e.entity);
          if (!hasSeed &&
              !inherited.putIfAbsent(
                e.entity,
                () => _hasInheritedText(e.entity),
              )) {
            if (_textBaseline == null) {
              ready = false;
            } else {
              refs.add(_textBaseline!.id);
            }
          }
        }
        if ((birthsByEvent[e.id] ?? const <String>[]).any(
          (entity) =>
              !availableState(states[entity]) || nativePending.contains(entity),
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

  int warmProjectionReuses = 0;
  int semanticProjectionReuses = 0;
  String? _unifiedTaskRevision;
  UnifiedSnapshot? _stagedSnapshot;
  UnifiedSnapshot? _textStageSnapshot;
  TaskSemanticValidator? _textReadOwner;
  int selectedTextReads = 0, selectedTextRecords = 0, selectedTextLookups = 0;
  int selectedCopySeedReads = 0, selectedCopySeedRecords = 0;
  int selectedTextInitialDecodes = 0;

  EventClock? _stagedMaximumClock;
  void Function() _stageUnifiedProjection(UnifiedSnapshot snapshot) {
    final before = _canonicalTextInput;
    final beforeScope = _textStageSnapshot;
    _textStageSnapshot = snapshot;
    try {
      final publish = _withCopySeedIndex(
        () => _stageUnifiedProjectionIndexed(snapshot),
      );
      final candidate = _canonicalTextInput;
      return () {
        _canonicalTextInput = candidate;
        publish();
      };
    } finally {
      // The caller still owns the shared SQL transaction. Publish this pure
      // candidate only after that transaction has actually committed.
      _canonicalTextInput = before;
      _textStageSnapshot = beforeScope;
    }
  }

  void Function() _stageUnifiedProjectionIndexed(UnifiedSnapshot snapshot) {
    if (_unifiedTaskRevision != null && identical(snapshot, _stagedSnapshot)) {
      final pending =
          unified!.hasPendingAfter(snapshot) || snapshot.pendingEffects;
      final oldWarning = clockWarning;
      _updateClockWarning(_stagedMaximumClock, _nowNs());
      final warning = clockWarning;
      clockWarning = oldWarning;
      return () {
        _writerHasPendingAppend = pending;
        clockWarning = warning;
      };
    }
    final validatedKey = unified!.validatedTaskRevision(snapshot);
    if (_unifiedTaskRevision != null &&
        validatedKey != null &&
        validatedKey == _unifiedTaskRevision) {
      final pending =
          unified!.hasPendingAfter(snapshot) || snapshot.pendingEffects;
      final maximum = snapshot.maximumClock;
      final oldWarning = clockWarning;
      _updateClockWarning(maximum, _nowNs());
      final warning = clockWarning;
      clockWarning = oldWarning;
      return () {
        _stagedSnapshot = snapshot;
        _stagedMaximumClock = maximum;
        _writerHasPendingAppend = pending;
        clockWarning = warning;
      };
    }
    final ownDelta = unified!.validatedTaskDelta(snapshot, _stagedSnapshot);
    final events = ownDelta == null
        ? snapshot.tasks.toList()
        : const <LogEvent>[];
    final List<LogEvent> added;
    if (ownDelta != null) {
      added = ownDelta;
    } else {
      final oldIds = db
          .select('SELECT id FROM ${tables.events}')
          .map((r) => r['id'])
          .toSet();
      added = events.where((e) => !oldIds.contains(e.id)).toList();
    }
    final affected = {
      ...added.map((e) => e.entity),
      if (added.isNotEmpty) ..._textCaptures.map((c) => c.entity),
      if (added.isNotEmpty) ..._nativeUndoFields.values.map((f) => f.entity),
    };
    final revision =
        unified!.validatedTaskRevision(snapshot) ??
        _taskProjectionRevision(events);
    final projectionChanged = revision != _unifiedTaskRevision;
    Set<String>? projectedIds;
    var orderRebuilt = true;
    final oldBaseline = _textBaseline, oldBlocked = textWriteBlocked;
    LogEvent? newBaseline = oldBaseline;
    String? newBlocked = oldBlocked;
    if (revision != _unifiedTaskRevision) {
      try {
        if (_unifiedTaskRevision == null &&
            unified!.takeReusedTaskProjectionRevision() == revision) {
          _validateTextBaseline();
          // A usable older cache may predate an additive query index.
          _ensureProjectionIndexes();
          warmProjectionReuses++;
        } else if (_unifiedTaskRevision == null) {
          // Index DDL can have rolled back with a prior failed rebuild stage.
          _projectionIndexesReady = false;
          _canonicalTextInput = null;
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
          if (unified!.copyValidatedTaskProjection(this, snapshot, revision)) {
            _validateTextBaseline();
            semanticProjectionReuses++;
          } else {
            _replaySemanticEvents(events);
          }
        } else {
          final prior = _stagedSnapshot;
          final settled =
              prior != null &&
              prior.allVisibleTasksReady &&
              added.every((e) => snapshot.readyTaskIds.contains(e.id)) &&
              (_settledActionTargets(added, prior.readyTaskIds) ||
                  _firstDerivedActionSeeds(added, prior.readyTaskIds) != null);
          final delta = _replaySemanticEvents(
            added,
            incremental: true,
            settledDelta: settled,
            // Only the owning authority can certify this exact visible input.
            // Local eligibility, packets, projection closure and order remain.
            auditCanonicalReferences:
                !(unified!.verifiesTaskRevision(snapshot, revision) &&
                    prior != null &&
                    unified!.verifiesTaskRevision(
                      prior,
                      _unifiedTaskRevision!,
                    )),
          );
          projectedIds = delta.projectedIds;
          orderRebuilt = delta.orderRebuilt;
        }
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
        : _nextProjectionView(projectedIds, orderRebuilt: orderRebuilt);
    final oldWarning = clockWarning;
    final maximum = snapshot.maximumClock;
    _updateClockWarning(maximum, _nowNs());
    final warning = clockWarning;
    clockWarning = oldWarning;
    return () => _withCopySeedIndex(() {
      _textBaseline = newBaseline;
      textWriteBlocked = newBlocked;
      if (projectionChanged) cacheTransactions++;
      _unifiedTaskRevision = revision;
      _stagedSnapshot = snapshot;
      _stagedMaximumClock = maximum;
      _writerHasPendingAppend = pending;
      clockWarning = warning;
      _currentView = candidateView;
      // Both native-owner passes observe this same committed SQL snapshot.
      // Build its immutable history resolver only if inherited text needs it,
      // and share it across fields/captures without extending its lifetime.
      RecurringTextResolver? resolution;
      Map<String, ResolvedTextField> resolve(String entity) =>
          (resolution ??= _textResolution(entities: affected)).resolve(entity);
      _updateCapturedTextDocuments(added, affected, resolve: resolve);
      _updateNativeUndoOwners(added, affected, resolve: resolve);
    });
  }

  Future<List<OperationReceipt>> _appendUnifiedCommands(
    List<(String, String, Map<String, dynamic>)> commands, {
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
    List<(String, String, Map<String, dynamic>)> Function()? buildFreshCommands,
  }) async {
    if (buildFreshCommands == null) {
      _requireWriterAppendReady();
      if (commands.isEmpty) return [];
      if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    }
    final creations = <String, LogEvent>{};
    List<UnifiedEffectBuilder> build(
      List<(String, String, Map<String, dynamic>)> commands,
    ) => [
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
    ];
    void onReserved(List<UnifiedRecord> _) {
      if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
    }

    final reservation = buildFreshCommands == null
        ? await unified!.prepareInProfileQueue(
            build(commands),
            expectedRevision: unified!.snapshot.revision,
            onReserved: onReserved,
          )
        : await unified!.prepareFromFreshInputsInProfileQueue(() {
            final freshCommands = buildFreshCommands();
            _requireWriterAppendReady();
            if (canCommit != null && !canCommit()) throw StaleTaskSnapshot();
            return build(freshCommands);
          }, onReserved: onReserved);
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
    _canonicalTextInput = null;
    _projectionIndexesReady = false;
    await _refresh(verify: true);
  });

  Future<bool> _refresh({bool verify = false}) async {
    final before = _unifiedTaskRevision;
    final previousTaskIds = verify
        ? unified!.snapshot.tasks.map((event) => event.id).toSet()
        : const <String>{};
    final snapshot = await unified!.refreshInProfileQueue(
      forceFullAudit: verify,
    );
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
    // The admitted snapshot already certifies whether any effects wait for
    // publication. Avoid scanning complete history on ordinary editor opens.
    if (common != null &&
        common.snapshot.pendingEffects &&
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
    // Canonical input is fixed through this synchronous capture. Share one
    // inherited-text resolver across cache verification and native field bases;
    // no resolver survives a later refresh or Save.
    final resolution = _hasInheritedText(entity)
        ? _textResolution(
            entities: [entity],
            pending: history
                .where((event) => event.canonicalRaw != null)
                .toList(),
          )
        : null;
    // Verify the lazily opened field checkpoints against their canonical
    // context and operation frontier; corrupt disposable state rebuilds.
    db.execute('BEGIN IMMEDIATE');
    try {
      _materializeText(task, history, resolution: resolution);
      _attachChecklist(task, resolution: resolution);
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
    final resolvedFields = resolution?.resolve(entity);
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
          checkpoint: NativeTextCheckpoint(NativeTextState.fromBytes(state)),
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
    final bases = <String, Map<String, dynamic>>{};
    final receipts = await _appendUnifiedCommands(
      const [],
      buildFreshCommands: () {
        final resolvedFields = _hasInheritedText(entity)
            ? _resolvedText(entity)
            : null;
        for (final name in changes.keys) {
          final row = _nativeTextFieldRow(
            entity,
            name,
            resolved: resolvedFields,
          );
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
        _requireWriterAppendReady();
        _requireTaskSnapshot(expectedSnapshot, ignoreSnapshotText: true);
        return [
          (entity, 'task.textEdited', {...?nonText, 'changes': changes}),
        ];
      },
      canCommit: canCommit,
      onPrepared: (receipt) {
        _preparedTextBases[receipt.id] = Map.unmodifiable(bases);
        onPrepared?.call(receipt);
      },
    );
    return _recurringTextMemo.decodeCanonical(receipts.single.raw);
  });

  void registerTextOperation(
    OperationReceipt receipt,
    TaskTextCapture capture,
  ) {
    _requireConfirmed([receipt]);
    final event = _recurringTextMemo.decodeCanonical(receipt.raw);
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
            NativeTextState.fromBytes(base['state'] as Uint8List),
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
      final event = _recurringTextMemo.decodeCanonical(receipt.raw);
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
    Set<String> affected, {
    Map<String, ResolvedTextField> Function(String)? resolve,
  }) {
    for (final capture in _textCaptures) {
      if (_hasInheritedText(capture.entity)) {
        if (!affected.contains(capture.entity)) continue;
        Map<String, ResolvedTextField> resolved;
        try {
          resolved = (resolve ?? _resolvedText)(capture.entity);
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
    Map<String, ResolvedTextField> Function(String)? resolve,
  }) {
    if (_hasInheritedText(owner.entity)) {
      Map<String, ResolvedTextField> fields;
      try {
        fields = (resolve ?? _resolvedText)(owner.entity);
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

  void _updateNativeUndoOwners(
    List<LogEvent> events,
    Set<String> affected, {
    Map<String, ResolvedTextField> Function(String)? resolve,
  }) {
    for (final owner in _nativeUndoFields.values) {
      if (!affected.contains(owner.entity)) continue;
      _syncNativeUndoField(owner, events, resolve: resolve);
    }
  }

  // Diagnostic count of display-row decoding, excluding command guards.
  int displaySnapshotRowsDecoded = 0;

  TaskViewSnapshot _nextProjectionView(
    Set<String>? projectedIds, {
    required bool orderRebuilt,
  }) {
    if (projectedIds != null && !orderRebuilt) {
      final changes = <String, Map<String, dynamic>?>{};
      for (final id in projectedIds) {
        final records = db.select(
          "SELECT ${tables.views}.raw FROM ${tables.views} JOIN ${tables.positions} ON ${tables.positions}.id=${tables.views}.id WHERE ${tables.views}.id=? AND json_extract(${tables.views}.raw,'\$.kind')<>'checklistItem' AND COALESCE(json_extract(${tables.views}.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(${tables.views}.raw,'\$.successorSuppressed'),0)=0",
          [id],
        );
        if (records.isEmpty) {
          changes[id] = null;
        } else {
          displaySnapshotRowsDecoded++;
          changes[id] =
              jsonDecode(records.single['raw'] as String)
                  as Map<String, dynamic>;
        }
      }
      final candidate = TaskViewSnapshot.replacing(changes, _currentView);
      if (candidate != null) return candidate;
    }
    final all = rows;
    displaySnapshotRowsDecoded += all.length;
    return TaskViewSnapshot.next(all, _currentView);
  }

  final Map<String, int> lastReadTimings = {};
  String get _visibleRowsQuery =>
      "SELECT ${tables.views}.raw FROM ${tables.views} JOIN ${tables.positions} ON ${tables.positions}.id=${tables.views}.id WHERE json_extract(${tables.views}.raw,'\$.kind')<>'checklistItem' AND COALESCE(json_extract(${tables.views}.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(${tables.views}.raw,'\$.successorSuppressed'),0)=0";
  String get _visibleRowsSql =>
      '$_visibleRowsQuery ORDER BY ${tables.positions}.rank';
  List<Map<String, dynamic>> get rows {
    final watch = Stopwatch()..start();
    final records = db.select(_visibleRowsSql);
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

  /// The same visible Task row as [rows], without decoding unrelated rows.
  /// Keep the join and visibility predicates identical: an unpositioned,
  /// deleted, suppressed, or non-Task entity cannot satisfy an editor guard.
  Map<String, dynamic>? visibleTaskRow(String id) {
    final records = db.select(
      "SELECT ${tables.views}.raw FROM ${tables.views} JOIN ${tables.positions} ON ${tables.positions}.id=${tables.views}.id WHERE ${tables.views}.id=? AND json_extract(${tables.views}.raw,'\$.kind')<>'checklistItem' AND COALESCE(json_extract(${tables.views}.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(${tables.views}.raw,'\$.successorSuppressed'),0)=0",
      [id],
    );
    if (records.isEmpty) return null;
    final row =
        jsonDecode(records.single['raw'] as String) as Map<String, dynamic>;
    return row['kind'] == 'task' ? row : null;
  }

  // These are diagnostic attempted-work counts, not committed cache state.
  int globalOrderRebuilds = 0;

  bool _undoMayChangeGlobalOrder(LogEvent undo) {
    final target = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
      undo.data['operation'],
    ]);
    if (target.length != 1) return true;
    final event = _recurringTextMemo.decodeCanonical(
      target.single['raw'] as String,
    );
    // The caller only uses this shortcut for a settled, validated delta.
    // Checklist order is embedded in the reprojected parent, not global ranks.
    return !const {
          'task.edited',
          'task.deleted',
          'checklist.itemEdited',
          'checklist.itemMoved',
          'checklist.itemDeleted',
          'task.completed',
        }.contains(event.type) ||
        (event.type == 'task.completed' && event.data['successor'] != null);
  }

  /// Persist disposable sequence positions only when order-affecting history changes.
  void _rebuildOrder() {
    globalOrderRebuilds++;
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
          .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String)),
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
    final insert = db.prepare('INSERT INTO ${tables.positions} VALUES (?,?)');
    try {
      for (var i = 0; i < ordered.length; i++) {
        insert.execute([ordered[i], i]);
      }
    } finally {
      insert.close();
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
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
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
    return _commandAfterRefresh(
      entity,
      type,
      data,
      expectedTaskSnapshot: expectedTaskSnapshot,
      ignoreSnapshotText: ignoreSnapshotText,
      canCommit: canCommit,
      onPrepared: onPrepared,
    );
  }

  // The caller owns the profile queue and has just refreshed, with only
  // synchronous field capture between that publication and these guards.
  // Preparation still refreshes and compares its expected canonical revision.
  Future<LogEvent> _commandAfterRefresh(
    String entity,
    String type,
    Map<String, dynamic> data, {
    String? expectedTaskSnapshot,
    bool ignoreSnapshotText = false,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    if (isTaskCompletion(type)) {
      if (data.containsKey('completedAt')) {
        throw FormatFailure('New completions require only an instant.');
      }
      try {
        decodeCompletionInstant(data['completedInstant']);
      } on FormatException catch (error) {
        throw FormatFailure(error.message);
      }
    }
    _requireWriterAppendReady();
    _requireTaskSnapshot(
      expectedTaskSnapshot,
      ignoreSnapshotText: ignoreSnapshotText,
    );
    final receipts = await _appendUnifiedCommands(
      [(entity, type, data)],
      canCommit: canCommit,
      onPrepared: onPrepared,
    );
    return _recurringTextMemo.decodeCanonical(receipts.single.raw);
  }

  void _requireTaskSnapshot(
    String? expectedTaskSnapshot, {
    required bool ignoreSnapshotText,
  }) {
    if (expectedTaskSnapshot != null) {
      final actual = taskSnapshot;
      if (expectedTaskSnapshot != actual &&
          (!ignoreSnapshotText ||
              _nonTextSnapshot(expectedTaskSnapshot) !=
                  _nonTextSnapshot(actual))) {
        throw StaleTaskSnapshot();
      }
    }
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
    final root = _recurringTextMemo.decodeCanonical(
      roots.single['raw'] as String,
    );
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
      final event = _recurringTextMemo.decodeCanonical(
        record.single['raw'] as String,
      );
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
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
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
    final event = _recurringTextMemo.decodeCanonical(receipt.raw);
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
    return _withCopySeedIndex(
      () => _prepareCommandIndexed(
        entity,
        type,
        data,
        seq,
        clock,
        previousHash: previousHash,
        pendingCreation: pendingCreation,
      ),
    );
  }

  LogEvent _prepareCommandIndexed(
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
    final e = _recurringTextMemo.decodeCanonical(
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
    final canonicalTextDelegated = const {
      'task.textEdited',
      'task.textEditUndone',
      'task.completedWithText',
      'task.completedWithChecklist',
    }.contains(type);
    if (_textTypes.contains(type) && textEngine == null) {
      throw FormatFailure('Native text support is required before saving.');
    }
    // UnifiedHistory checks the exact whole candidate, including native packets,
    // before reserving bytes or invoking any receipt callback. Keep local policy
    // here; ordinary text need not run a second scratch canonical replay.
    if (_textTypes.contains(type) && !canonicalTextDelegated) {
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
    final priorSnapshot = _stagedSnapshot;
    final settledText =
        priorSnapshot != null &&
        priorSnapshot.allVisibleTasksReady &&
        (_settledActionTargets([e], priorSnapshot.readyTaskIds) ||
            _firstDerivedActionSeeds([e], priorSnapshot.readyTaskIds) != null);
    if (settledText) {
      _validateTagReferences(e);
      _validateMoves(e);
      if (e.type.startsWith('checklist.')) {
        _validateChecklistReferences(e, scoped: true);
      } else {
        _validatePendingChecklistEligibility(e);
      }
    } else {
      _validateMoves(e);
      _validateTagReferences(e);
      _validateHistoricalCompletions(e);
      _validateChecklistReferences(e);
      if (!canonicalTextDelegated) {
        _validateChecklistCompletions(
          e,
          _stagedSnapshot?.allVisibleTasksReady != true,
        );
      }
    }
    if (type == 'task.completedWithText' ||
        type == 'task.completedWithChecklist') {
      if (data['inheritance'] is Map) {
        _requireObservedTextFrontiers(
          Map<String, dynamic>.from(data['inheritance'] as Map),
          e,
        );
      }
      if (data['checklist'] is Map) {
        _requireObservedTextFrontiers(
          Map<String, dynamic>.from(data['checklist'] as Map),
          e,
        );
      }
    }
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
            _recurringTextMemo.decodeCanonical(r.raw).type != 'task.moved',
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
    // The admitted graph is already checked. A local candidate can only
    // introduce its own reference or resolve an existing reverse reference;
    // both are checked below without scanning every unrelated Undo.
    if (pending == null) {
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
        throw FormatFailure(
          'Invalid undo reference in ${invalid.single['id']}.',
        );
      }
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
        validate(
          pending,
          _recurringTextMemo.decodeCanonical(targets.single['raw'] as String),
        );
      }
    }
    for (final row in db.select(
      "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type') IN ('task.textEditUndone','task.completionUndone','task.operationUndone','task.recurringCompletionUndone') AND COALESCE(json_extract(semantic,'\$.data.operation'),json_extract(semantic,'\$.data.completion'))=?",
      [pending.id],
    )) {
      validate(
        _recurringTextMemo.decodeCanonical(row['raw'] as String),
        pending,
      );
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
        .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String))
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
    final snapshot = _textStageSnapshot ?? _stagedSnapshot;
    final indexed = pending == null
        ? null
        : _textReadOwner?._selectTagMutationRaws(pending) ??
              (snapshot == null
                  ? null
                  : unified?.selectTaskTagMutationRaws(snapshot, pending));
    final mutations = indexed == null
        ? db
              .select(
                pending == null
                    ? "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.tagChanges') IS NOT NULL"
                    : "SELECT raw FROM ${tables.events} e WHERE EXISTS (SELECT 1 FROM json_each(json_extract(e.semantic,'\$.data.tagChanges.remove')) r WHERE r.value LIKE ?) OR e.entity=?",
                pending == null ? [] : ['${pending.id}:%', successor],
              )
              .map(
                (r) => _recurringTextMemo.decodeCanonical(r['raw'] as String),
              )
              .toList()
        : indexed.map(_recurringTextMemo.decodeCanonical).toList();
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
            : _recurringTextMemo.decodeCanonical(rows.first['raw'] as String);
        if (target == null) {
          final seeds = db.select(
            "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=?",
            [mutation.entity],
          );
          final matches = <LogEvent>[];
          for (final row in seeds) {
            final seed = _recurringTextMemo.decodeCanonical(
              row['raw'] as String,
            );
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
        .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String))
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
        creations.add(
          _recurringTextMemo.decodeCanonical(seeds.first['raw'] as String),
        );
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
        .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String))
        .toList();
    final parent = decoded.first.entity;
    final parentHistory = db
        .select('SELECT raw FROM ${tables.events} WHERE entity=?', [parent])
        .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String));
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
          .map((r) => _recurringTextMemo.decodeCanonical(r['raw'] as String))
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
  }) => _textResolution(pending: pending, entities: [entity]).resolve(entity);

  RecurringTextInput _textInput({Iterable<String> entities = const []}) {
    final roots = entities.toSet();
    if (roots.isNotEmpty) {
      final snapshot = _textStageSnapshot ?? _stagedSnapshot;
      final selection =
          _textReadOwner?._selectText(roots) ??
          (snapshot == null ? null : unified?.selectTaskText(snapshot, roots));
      if (selection != null) {
        // This scope already supplies the whole relevant immutable closure.
        // Retaining a second whole-history input would copy it on every append.
        _canonicalTextInput = null;
        final input = RecurringTextInput.fromSelectedCanonical(
          selection.records,
          selection.heads,
          selection.sequences,
          memo: _recurringTextMemo,
        );
        selectedTextReads++;
        selectedTextRecords += selection.records.length;
        selectedTextLookups += selection.lookups;
        selectedTextInitialDecodes += input.selectedDecodedRecordCount;
        return input;
      }
    }
    final input =
        _canonicalTextInput ??
        RecurringTextInput.fromCanonical(
          db
              .select('SELECT raw FROM ${tables.events}')
              .map((row) => row['raw'] as String),
          memo: _recurringTextMemo,
        );
    _canonicalTextInput = input.cacheable ? input : null;
    return input;
  }

  RecurringTextResolver _textResolution({
    List<LogEvent> pending = const [],
    Iterable<String> entities = const [],
  }) {
    var input = _textInput(
      entities: {...entities, ...pending.map((e) => e.entity)},
    );
    final added = pending
        .where((event) => !input.containsCanonical(event))
        .toList();
    if (added.isNotEmpty) {
      input =
          input.appendedCanonical(
            added.map((event) => event.canonicalRaw!),
            memo: _recurringTextMemo,
          ) ??
          RecurringTextInput.fromCanonical([
            ...input.history.map((event) => event.canonicalRaw!),
            ...added.map((event) => event.canonicalRaw!),
          ], memo: _recurringTextMemo);
    }
    return RecurringTextResolver.fromInput(
      textEngine!,
      input,
      legacyRoots: _legacyTextRoots,
      memo: _recurringTextMemo,
      legacyScope: '${_textBaseline?.hash ?? ''}|${textWriteBlocked ?? ''}',
    );
  }

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
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    final seeds = db
        .select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=?",
          [entity],
        )
        .map((row) => _recurringTextMemo.decodeCanonical(row['raw'] as String))
        .where((event) => _baselineIncludes(event, baseline))
        .toList();
    if (seeds.isNotEmpty) {
      final parent = db
          .select('SELECT raw FROM ${tables.events} WHERE entity=?', [
            seeds.first.entity,
          ])
          .map(
            (row) => _recurringTextMemo.decodeCanonical(row['raw'] as String),
          )
          .where((event) => _baselineIncludes(event, baseline));
      final anchors = db
          .select(
            "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.moved' AND json_extract(semantic,'\$.data.before')=?",
            [entity],
          )
          .map(
            (row) => _recurringTextMemo.decodeCanonical(row['raw'] as String),
          )
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
                      .map(
                        (row) => _recurringTextMemo.decodeCanonical(
                          row['raw'] as String,
                        ),
                      )
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
    final event = _recurringTextMemo.decodeCanonical(
      source.single['raw'] as String,
    );
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

  void _validateHistoricalCompletions([
    LogEvent? pending,
    bool auditExisting = true,
  ]) {
    final markers = <LogEvent>[
      if (auditExisting)
        for (final row in db.select(
          "SELECT raw FROM ${tables.events} WHERE json_extract(semantic,'\$.type')='task.completedKeepingSuccessor'",
        ))
          _recurringTextMemo.decodeCanonical(row['raw'] as String),
      if (pending?.type == 'task.completedKeepingSuccessor') pending!,
    ];
    for (final marker in markers) {
      final retained = marker.data['retainedSuccessor'] as Map;
      final rows = db.select('SELECT raw FROM ${tables.events} WHERE id=?', [
        retained['completion'],
      ]);
      final known = verifyHistoricalCompletion(
        marker,
        rows.isEmpty
            ? null
            : _recurringTextMemo.decodeCanonical(rows.single['raw'] as String),
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
    ViewTime Function()? observeCompletionTime,
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
    if ((observeCompletionTime == null) == (completionInstant == null)) {
      throw ArgumentError(
        'Supply exactly one clock observation or explicit instant.',
      );
    }
    _requireWriterAppendReady();
    final observation = observeCompletionTime?.call();
    final instant = observation?.instant ?? completionInstant!;
    final day = civilDayAt(
      instant,
      schedule.timeZone ?? observation?.localZoneId ?? localZoneId,
    );
    final data = <String, dynamic>{
      'completedInstant': encodeCompletionInstant(instant),
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
      return _commandAfterRefresh(
        entity,
        'task.completedKeepingSuccessor',
        data,
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
    return _commandAfterRefresh(entity, type, data, onPrepared: onPrepared);
  });

  /// Immutable comparison token for current task content and global order.
  /// User-only changes do not invalidate a task move. No display policy lives
  /// here: callers separately validate filters/time-dependent move eligibility.
  String get taskSnapshot {
    // Always query the live connection, including staged SQL before COMMIT.
    // Only the JSON representation is reused, after exact raw-row/order equality.
    // This carries no freshness, admission, native ownership or commit authority.
    final raw = [
      for (final row in db.select(_visibleRowsSql)) row['raw'] as String,
    ];
    final previous = _taskSnapshotRaw;
    if (previous != null && previous.length == raw.length) {
      var equal = true;
      for (var i = 0; i < raw.length; i++) {
        if (raw[i] != previous[i]) {
          equal = false;
          break;
        }
      }
      if (equal) return _taskSnapshotValue!;
    }
    taskSnapshotRowsDecoded += raw.length;
    final tasks = <Map<String, dynamic>>[];
    final taskRaw = <String>[];
    for (final source in raw) {
      final row = jsonDecode(source) as Map<String, dynamic>;
      if (row['kind'] == 'task') {
        tasks.add(row);
        taskRaw.add(source);
      }
    }
    final value = jsonEncode(tasks);
    // Filtering by SQLite's logical ID is equivalent only for the exact map
    // encoding produced by our projection writers. Duplicate JSON labels or
    // other noncanonical encodings keep the original full Dart decoder path.
    // Compare against the representation already built above, without encoding
    // the rows a second time or retaining any additional row payload.
    var selectionSafe = true;
    var offset = 1;
    for (final entry in taskRaw.indexed) {
      if (entry.$1 > 0) offset++;
      if (!value.startsWith(entry.$2, offset)) {
        selectionSafe = false;
        break;
      }
      offset += entry.$2.length;
    }
    selectionSafe = selectionSafe && offset == value.length - 1;
    final bytes = raw.fold<int>(
      raw.length * 64 + value.length * 2,
      (total, value) => total + value.length * 2,
    );
    if (raw.length <= 4096 && bytes <= 4 * 1024 * 1024) {
      _taskSnapshotRaw = List.unmodifiable(raw);
      _taskSnapshotValue = value;
      _taskSnapshotBytes = bytes;
      _taskSnapshotSelectionSafe = selectionSafe;
    } else {
      _clearTaskSnapshotMemo();
    }
    return value;
  }

  List<String>? _taskSnapshotRaw;
  String? _taskSnapshotValue;
  int _taskSnapshotBytes = 0;
  bool _taskSnapshotSelectionSafe = false;
  int get cachedTaskSnapshotBytes => _taskSnapshotBytes;
  // Attempted representation work, separate from display-row decoding.
  int taskSnapshotRowsDecoded = 0;
  void _clearTaskSnapshotMemo() {
    _taskSnapshotRaw = null;
    _taskSnapshotValue = null;
    _taskSnapshotBytes = 0;
    _taskSnapshotSelectionSafe = false;
  }

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

  // Attempted candidate work, including failed/cancelled passes.
  int occurrenceDuePlansEvaluated = 0;

  Future<OccurrenceDueMigrationResult> _migrateOccurrenceDatesInProfileQueue({
    bool Function()? canCommit,
    bool? initialChanged,
  }) async {
    var changed = initialChanged ?? await _refresh();
    final conflicts = <String, String>{};
    var migrated = 0;
    Object? failure;
    // The disposable partial index tracks only actual migration candidates.
    // Unchanged and unrelated Food refreshes decode no Task rows.
    final ids = db
        .select(
          "SELECT v.id FROM ${tables.views} v JOIN ${tables.positions} p ON p.id=v.id WHERE json_extract(v.raw,'\$.kind')='task' AND COALESCE(json_extract(v.raw,'\$.deleted'),0)=0 AND COALESCE(json_extract(v.raw,'\$.successorSuppressed'),0)=0 AND json_extract(v.raw,'\$.schedule.dueDate') IS NULL AND json_extract(v.raw,'\$.schedule.scheduledDate') IS NOT NULL ORDER BY p.rank",
        )
        .map((row) => row['id'] as String)
        .toList();
    for (final id in ids) {
      if (canCommit?.call() == false) break;
      // A preceding append may have admitted a newly synced task edit.
      changed = await _refresh() || changed;
      final current = visibleTaskRow(id);
      if (current == null) continue;
      occurrenceDuePlansEvaluated++;
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

  List<Map<String, dynamic>> _selection(
    List<String> ids, {
    required bool useFilteredProjection,
  }) {
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw FormatFailure('Choose distinct tasks.');
    }
    // Read the live projection after the snapshot/caller guard; the snapshot
    // memo is never selection authority. Filter logical IDs before decoding so
    // a small selection does not decode every visible Task/user row. Preserve
    // the same visibility join, global rank order and Dart kind/ID checks.
    // One JSON parameter also preserves large-selection validation without a
    // placeholder per ID or SQLite's variable-count limit.
    final candidates = useFilteredProjection
        ? db
              .select(
                "$_visibleRowsQuery AND json_extract(${tables.views}.raw,'\$.id') IN (SELECT value FROM json_each(?)) ORDER BY ${tables.positions}.rank",
                [jsonEncode(ids)],
              )
              .map(
                (r) => jsonDecode(r['raw'] as String) as Map<String, dynamic>,
              )
        : rows;
    final tasks = candidates
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
    if (taskSnapshot != expectedTaskSnapshot) throw StaleTaskSnapshot();
    var guardWroteSql = false;
    if (canCommit != null) {
      // Guards must not mutate the store. Preserve the legacy decoder/error
      // behavior even for a caller that stages projection writes here.
      final changes = db
          .select('SELECT total_changes() AS count')
          .single['count'];
      if (!canCommit()) throw StaleTaskSnapshot();
      guardWroteSql =
          changes !=
          db.select('SELECT total_changes() AS count').single['count'];
    }
    final selected = _selection(
      ids,
      useFilteredProjection: _taskSnapshotSelectionSafe && !guardWroteSql,
    );
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
      final event = _recurringTextMemo.decodeCanonical(
        found.single['raw'] as String,
      );
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
        (_recurringTextMemo.decodeCanonical(receipt.raw).data['operation'] ??
                _recurringTextMemo
                    .decodeCanonical(receipt.raw)
                    .data['completion'])
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
    required String? expectedTaskSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) {
    if (expectedTaskSnapshot == null && canCommit == null) {
      return Future.error(
        ArgumentError('Deletion requires a snapshot or a target guard.'),
      );
    }
    return _serialize(
      () => _command(
        id,
        'task.deleted',
        {},
        expectedTaskSnapshot: expectedTaskSnapshot,
        canCommit: canCommit,
        onPrepared: onPrepared,
      ),
    );
  }

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
      var disposed = false;
      void detachAndDispose() {
        if (disposed) return;
        unified?.detachProjectionInProfileQueue(this);
        for (final capture in _textCaptures) {
          for (final field in capture.fields.values) {
            field.document.dispose();
          }
        }
        for (final field in _nativeUndoFields.values) {
          field.document.dispose();
        }
        _canonicalTextInput = null;
        _clearTaskSnapshotMemo();
        disposed = true;
      }

      try {
        if (profileDatabase == null) {
          detachAndDispose();
          db.close();
        } else {
          try {
            await profileDatabase!.serialize(() async {
              // Foreign module refreshes finish before their shared projection
              // is detached; no publication can target disposed native owners.
              detachAndDispose();
              if (unified != null &&
                  unified!.safetyFailure == null &&
                  !unified!.hasPending &&
                  !unified!.snapshot.pendingEffects) {
                profileDatabase!.transaction(() {
                  unified!.sealTaskProjectionCache(this);
                });
              }
            });
          } on StateError {
            // A poisoned/closed queue cannot publish; cleanup still completes.
            detachAndDispose();
          } on SqliteException {
            // Optional witness failure must not retain native documents.
            detachAndDispose();
          } on LocalDatabaseFailure {
            detachAndDispose();
          }
        }
      } finally {
        detachAndDispose();
        _recurringTextMemo.clear();
        _viewChanges.clear();
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

final _taskCanonicalDigests = Expando<String>('Task canonical raw digest');

String _taskProjectionRevision(Iterable<LogEvent> events) {
  final ordered = events.toList()..sort(compareEvents);
  final leaves = ordered.map((event) {
    final raw = event.canonicalRaw;
    if (raw == null) throw StateError('Canonical Task evidence is required.');
    return _taskCanonicalDigests[event] ??= bytesDigest(utf8.encode(raw));
  });
  return bytesDigest(
    utf8.encode(
      'tandemlog:task-projection-cache:v3\n${ordered.length}\n${leaves.join('\n')}\n',
    ),
  );
}

List<String> _taskCacheTables(TaskTables t) => [
  t.events,
  t.views,
  t.streams,
  t.streamRanges,
  t.textFields,
  t.textActors,
  t.textOutbox,
  t.positions,
  t.metadata,
];

List<List<List<Object?>>> _taskCacheRows(Database db, TaskTables t) => [
  for (final entry in _taskCacheTables(t).indexed)
    // Deterministic primary-key order; checkpoint bytes remain byte arrays.
    db
        .select(
          "SELECT * FROM ${entry.$2} ${entry.$1 == 8 ? "WHERE key IN ('order_projection','text_baseline_verified') " : ''}ORDER BY ${const [1, 1, 1, 2, 2, 2, 1, 1, 1][entry.$1] == 2 ? '1,2' : '1'}",
        )
        .map((r) => r.values.toList())
        .toList(),
];

// The schema/row inventory is fixed by _taskCacheTables. Reuse each table's
// INSERT while restoring the independently checked disposable projection.
void _insertTaskCacheRows(
  Database db,
  List<String> names,
  List<List<List<Object?>>> rows,
) {
  for (var i = 0; i < names.length; i++) {
    if (rows[i].isEmpty) continue;
    final insert = db.prepare(
      'INSERT INTO ${names[i]} VALUES (${List.filled(rows[i].first.length, '?').join(',')})',
    );
    try {
      for (final row in rows[i]) {
        insert.execute(row);
      }
    } finally {
      insert.close();
    }
  }
}

String _taskCacheDigest(List<List<List<Object?>>> rows, List<String> ready) =>
    // Identical JSON UTF-8 bytes without a full intermediate UTF-16 string.
    // The entire ordered row inventory and ready list still enter the proof.
    bytesDigest(JsonUtf8Encoder().convert({'rows': rows, 'ready': ready}));

/// Disposable, process-local semantic admission oracle. Complete candidate
/// batches are staged together; a failed or non-monotonic candidate rebuilds
/// from canonical input rather than retaining partly validated SQL/native state.

final class _TaskTextRelations {
  final entity = <String, List<LogEvent>>{};
  final successor = <String, List<LogEvent>>{};
  final copies = <String, List<LogEvent>>{};
  final children = <String, List<LogEvent>>{};
  final inbound = <String, List<LogEvent>>{};
  final retractions = <String, List<LogEvent>>{};
  final tagRemovals = <String, List<LogEvent>>{};
  final baselines = <LogEvent>[];
  void add(LogEvent e) {
    (entity[e.entity] ??= []).add(e);
    final changes = e.data['tagChanges'] as Map?;
    for (final token
        in (changes?['remove'] as List? ?? const []).cast<String>()) {
      final pieces = token.split(':');
      if (pieces.length != 3) {
        throw FormatFailure('Invalid tag reference in ${e.id}.');
      }
      final target = '${pieces[0]}:${pieces[1]}';
      (tagRemovals[target] ??= []).add(e);
    }
    final next = (e.data['successor'] as Map?)?['id'];
    if (next is String) (successor[next] ??= []).add(e);
    if (e.type == 'checklist.itemCreated') {
      (children[e.data['parent'] as String] ??= []).add(e);
    }
    if (e.type == 'task.completedWithChecklist') {
      (children[next as String] ??= []).add(e);
      for (final item in (e.data['checklist'] as Map)['items'] as List) {
        (copies[(item as Map)['id'] as String] ??= []).add(e);
      }
    }
    if (e.type == 'task.moved' && e.data['before'] is String) {
      (inbound[e.data['before'] as String] ??= []).add(e);
    }
    if (e.type == 'task.operationUndone' ||
        e.type == 'task.textEditUndone' ||
        e.type == 'task.recurringCompletionUndone') {
      final target =
          e.data[e.type == 'task.recurringCompletionUndone'
                  ? 'completion'
                  : 'operation']
              as String;
      (retractions[target] ??= []).add(e);
    }
    if (e.type == 'text.baselineInitialized') baselines.add(e);
  }
}

/// Detached, strictly canonical dependency payload. Only the owning semantic
/// validator can construct it; callers cannot inject a provider into TaskStore.
final class TaskTextReadSelection {
  TaskTextReadSelection._(
    Iterable<String> records,
    Map<String, String> heads,
    Map<String, int> sequences,
    this.lookups,
  ) : records = List.unmodifiable(records),
      heads = Map.unmodifiable(heads),
      sequences = Map.unmodifiable(sequences);
  final List<String> records;
  final Map<String, String> heads;
  final Map<String, int> sequences;
  final int lookups;
}

class TaskSemanticValidator {
  TaskSemanticValidator({
    required this.space,
    required this.writer,
    this.textEngine,
    this.profile,
    this.locationKey,
    this.manifestDigest,
    this.owningHistory,
  });
  final String space, writer;
  final NativeTextEngine? textEngine;
  final LocalProfileDatabase? profile;
  final String? locationKey, manifestDigest;
  final UnifiedHistory? owningHistory;
  String? reusedProjectionRevision;
  Set<String>? _ready;
  bool _attemptedWarm = false;
  String get _proofKey => 'app5.task.cache.$locationKey';
  TaskStore? _store;
  final _raws = <String, String>{};
  final _events = <String, LogEvent>{};
  final _lastSequences = <String, int>{};
  int fullRebuilds = 0;
  int projectedEvents = 0;
  int fullReadinessRuns = 0;
  int settledTextReadinessRuns = 0;
  int warmCacheProofMicroseconds = 0;
  int warmCacheRestoreMicroseconds = 0;

  String? _validatedInputKey;
  _TaskTextRelations _textRelations = _TaskTextRelations();
  List<LogEvent>? _textCandidate;
  bool _textSelectionSuppressed = false;
  int get selectedTextReadCount => _store?.selectedTextReads ?? 0;
  int get selectedTextRecordCount => _store?.selectedTextRecords ?? 0;
  int get selectedTextLookupCount => _store?.selectedTextLookups ?? 0;

  TaskTextReadSelection? selectText(
    String expectedKey,
    Iterable<String> roots,
  ) {
    if (_validatedInputKey != expectedKey) return null;
    return _selectText(roots);
  }

  List<String>? selectCopySeedRaws(String expectedKey, String entity) {
    if (_validatedInputKey != expectedKey) return null;
    return _selectCopySeedRaws(entity);
  }

  List<String>? _selectCopySeedRaws(String entity) {
    if (!_hasOwnedSelectionScope()) return null;
    // Copy claims are a point relation, not the entire transitive text closure.
    // The same actual-scope guard verifies every inserted candidate byte first.
    final claims = <String, LogEvent>{
      for (final event in _textRelations.copies[entity] ?? const <LogEvent>[])
        event.id: event,
    };
    for (final event in _textCandidate ?? const <LogEvent>[]) {
      if (event.type == 'task.completedWithChecklist' &&
          ((event.data['checklist'] as Map)['items'] as List).any(
            (item) => (item as Map)['id'] == entity,
          )) {
        claims[event.id] = event;
      }
    }
    final ordered = claims.values.toList()..sort(compareEvents);
    return List<String>.unmodifiable(
      ordered.map((event) => event.canonicalRaw!),
    );
  }

  // Shared actual-scope guard; candidates must already exist byte-exact in SQL.
  bool _hasOwnedSelectionScope() {
    final store = _store;
    if (store == null ||
        _textSelectionSuppressed ||
        owningHistory?.ownsTaskValidator(this) != true ||
        _ready == null ||
        _ready!.length != _raws.length) {
      return false;
    }
    for (final event in _textCandidate ?? const <LogEvent>[]) {
      final row = store.db.select(
        'SELECT raw FROM ${store.tables.events} WHERE id=?',
        [event.id],
      );
      if (row.length != 1 || row.single['raw'] != event.canonicalRaw) {
        return false;
      }
    }
    return true;
  }

  List<String>? selectTagMutationRaws(String expectedKey, LogEvent pending) {
    if (_validatedInputKey != expectedKey) return null;
    return _selectTagMutationRaws(pending);
  }

  List<String>? _selectTagMutationRaws(LogEvent pending) {
    if (!_hasOwnedSelectionScope()) return null;
    final extra = _TaskTextRelations();
    for (final event in _textCandidate ?? const <LogEvent>[]) {
      extra.add(event);
    }
    final successor =
        isTaskCompletion(pending.type) && pending.data['successor'] is Map
        ? (pending.data['successor'] as Map)['id']
        : null;
    final selected = <String, String>{};
    for (final event in [
      ...?_textRelations.tagRemovals[pending.id],
      ...?extra.tagRemovals[pending.id],
      if (successor is String) ...[
        ...?_textRelations.entity[successor],
        ...?extra.entity[successor],
      ],
    ]) {
      selected[event.id] = event.canonicalRaw!;
    }
    return List.unmodifiable(selected.values);
  }

  TaskTextReadSelection? _selectText(Iterable<String> roots) {
    if (!_hasOwnedSelectionScope()) return null;
    final candidate = _textCandidate;
    final extra = _TaskTextRelations();
    final sequences = Map<String, int>.of(_lastSequences);
    final candidateById = <String, LogEvent>{};
    if (candidate != null) {
      // A scope starts before replay, but may be read only AFTER every strict
      // candidate record was actually inserted into this owning SQL transaction.
      for (final event in candidate) {
        extra.add(event);
        candidateById[event.id] = event;
        if (event.sequence > (sequences[event.writer] ?? 0)) {
          sequences[event.writer] = event.sequence;
        }
      }
    }
    final selected = <String, LogEvent>{};
    final pending = roots.toSet().toList(), seen = <String>{};
    var lookups = 0;
    Iterable<LogEvent> bucket(
      Map<String, List<LogEvent>> a,
      Map<String, List<LogEvent>> b,
      String key,
    ) {
      lookups++;
      return [...?a[key], ...?b[key]];
    }

    final heads = <String, String>{};
    void add(LogEvent event) {
      if (selected.containsKey(event.id)) return;
      selected[event.id] = event;
      // Descriptor heads are independent evidence, not fake selected history.
      for (final name in ['inheritance', 'checklist']) {
        final value = event.data[name];
        if (value is! Map || value['frontiers'] is! Map) continue;
        for (final entry in (value['frontiers'] as Map).entries) {
          final seq = (entry.value as Map)['seq'] as int;
          final id = '${entry.key}:$seq';
          final head = candidateById[id] ?? _events[id];
          if (head != null) heads[id] = head.canonicalRaw!;
        }
      }
    }

    for (final event in [..._textRelations.baselines, ...extra.baselines]) {
      add(event);
    }
    while (pending.isNotEmpty) {
      final entity = pending.removeLast();
      if (!seen.add(entity)) continue;
      for (final event in bucket(_textRelations.entity, extra.entity, entity)) {
        add(event);
      }
      for (final event in bucket(
        _textRelations.successor,
        extra.successor,
        entity,
      )) {
        add(event);
        pending.add(event.entity);
      }
      for (final event in bucket(_textRelations.copies, extra.copies, entity)) {
        add(event);
        pending.add(event.entity);
        for (final item in (event.data['checklist'] as Map)['items'] as List) {
          if ((item as Map)['id'] == entity) {
            pending.add(item['source'] as String);
          }
        }
      }
      for (final event in bucket(
        _textRelations.children,
        extra.children,
        entity,
      )) {
        add(event);
        if (event.type == 'checklist.itemCreated') {
          pending.add(event.entity);
        } else {
          for (final item
              in (event.data['checklist'] as Map)['items'] as List) {
            pending.add((item as Map)['id'] as String);
            pending.add(item['source'] as String);
          }
        }
      }
      for (final event in bucket(
        _textRelations.inbound,
        extra.inbound,
        entity,
      )) {
        add(event);
      }
    }
    // Cross-entity Undo must remain visible to the pure checklist oracle.
    final retract = selected.keys.toList(), retracted = <String>{};
    while (retract.isNotEmpty) {
      final id = retract.removeLast();
      if (!retracted.add(id)) continue;
      for (final event in bucket(
        _textRelations.retractions,
        extra.retractions,
        id,
      )) {
        add(event);
        retract.add(event.id);
      }
    }
    for (final entry in sequences.entries) {
      final id = '${entry.key}:${entry.value}';
      final head = candidateById[id] ?? _events[id];
      if (head != null) heads[id] = head.canonicalRaw!;
    }
    return TaskTextReadSelection._(
      selected.values.map((e) => e.canonicalRaw!),
      heads,
      sequences,
      lookups,
    );
  }

  void _rebuildTextRelations() {
    // A ready owner can select exact closures; do not keep a second full input.
    _store?._canonicalTextInput = null;
    _textRelations = _TaskTextRelations();
    for (final event in _events.values) {
      _textRelations.add(event);
    }
  }

  Set<String> validate(List<LogEvent> events, {String? inputKey}) {
    // Generic/interior/peer validation may replace the entire candidate. Its
    // SQL transaction must never borrow the previous committed selected scope.
    _textSelectionSuppressed = true;
    try {
      return _validateFull(events, inputKey: inputKey);
    } finally {
      _textSelectionSuppressed = false;
    }
  }

  Set<String> _validateFull(List<LogEvent> events, {String? inputKey}) {
    final incoming = {for (final e in events) e.id: e.canonicalRaw!};
    if (_store != null &&
        _raws.entries.any((e) => incoming[e.key] != e.value)) {
      close();
    }
    if (_store == null) {
      final db = sqlite3.openInMemory();
      const tables = TaskTables.legacy();
      try {
        for (final sql in TaskStore._latestProjectionSchema(tables)) {
          db.execute(sql);
        }
        _store = TaskStore._(
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
        )..space = space;
        _store!._textReadOwner = this;
      } catch (_) {
        db.close();
        rethrow;
      }
    }
    final store = _store!, db = store.db;
    return store._withCopySeedIndex(() {
      if (!_attemptedWarm) {
        _attemptedWarm = true;
        _restoreCleanCache(events, inputKey: inputKey);
        _rebuildTextRelations();
      }
      final delta = events.where((e) => !_raws.containsKey(e.id)).toList();
      if (delta.isEmpty && _ready != null) {
        _validatedInputKey = inputKey;
        return _ready!;
      }
      final incremental = _raws.isNotEmpty;
      db.execute('BEGIN IMMEDIATE');
      try {
        final recurringSeeds = _ready == null
            ? null
            : store._recurringActionSeeds(delta, _ready!);
        final priorFullyReady =
            _ready != null &&
            _ready!.length == _raws.length &&
            delta.every((e) => e.sequence > (_lastSequences[e.writer] ?? 0));
        final baseSettled =
            priorFullyReady &&
            (recurringSeeds != null ||
                store._settledActionTargets(delta, _ready!));
        final firstActivitySeeds = priorFullyReady && !baseSettled
            ? store._firstDerivedActionSeeds(delta, _ready!)
            : null;
        final settledCandidate = baseSettled || firstActivitySeeds != null;
        store._replaySemanticEvents(
          delta,
          incremental: incremental,
          settledDelta: settledCandidate,
        );
        final settled = _settledActionReadiness(
          delta,
          eligible: settledCandidate,
          priorDerivedSeeds: recurringSeeds ?? const {},
          firstActivitySeeds: firstActivitySeeds ?? const {},
        );
        // Native dependencies may still make a pure-text candidate pending.
        // Before accepting fallback readiness, restore every skipped global check.
        if (settledCandidate && settled == null) {
          store._validateSemanticReferences();
        }
        final Set<String> ready;
        if (settled != null) {
          settledTextReadinessRuns++;
          ready = settled;
        } else {
          fullReadinessRuns++;
          ready = Set<String>.unmodifiable(store._semanticReadyIds(events));
        }
        db.execute('COMMIT');
        if (!incremental) fullRebuilds++;
        projectedEvents += delta.length;
        _ready = ready;
        _validatedInputKey = inputKey;
        _lastSequences.clear();
        for (final e in events) {
          if (e.sequence > (_lastSequences[e.writer] ?? 0)) {
            _lastSequences[e.writer] = e.sequence;
          }
        }
        _raws
          ..clear()
          ..addAll(incoming);
        _events
          ..clear()
          ..addAll({for (final event in events) event.id: event});
        _rebuildTextRelations();
        return ready;
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        close();
        rethrow;
      }
    });
  }

  /// Owning-history append fast path. The key identifies the EXACT actual
  /// scratch state, not a memoized pure validation result. A mismatch or an
  /// unsettled dependency requests the unchanged generic full-input validator.
  Set<String>? validateAppend(
    List<LogEvent> delta, {
    required String expectedBaseKey,
    required String inputKey,
  }) {
    final store = _store;
    if (store == null ||
        _ready == null ||
        _validatedInputKey != expectedBaseKey ||
        _ready!.length != _raws.length ||
        delta.isEmpty ||
        delta.any(
          (e) =>
              _raws.containsKey(e.id) ||
              e.sequence <= (_lastSequences[e.writer] ?? 0),
        )) {
      return null;
    }
    if (delta.any((event) => event.type == 'text.baselineInitialized')) {
      return null;
    }
    return store._withCopySeedIndex(() {
      final recurringSeeds = store._recurringActionSeeds(delta, _ready!);
      final baseSettled =
          recurringSeeds != null || store._settledActionTargets(delta, _ready!);
      final firstActivitySeeds = baseSettled
          ? null
          : store._firstDerivedActionSeeds(delta, _ready!);
      final settled = baseSettled || firstActivitySeeds != null;
      final priorBaseline = store._textBaseline?.id;
      final priorBlocked = store.textWriteBlocked;
      final db = store.db;
      db.execute('BEGIN IMMEDIATE');
      _textCandidate = List.unmodifiable(delta);
      try {
        store._replaySemanticEvents(
          delta,
          incremental: true,
          settledDelta: settled,
          knownReadyDelta: !settled,
        );
        final Set<String>? ready;
        if (settled) {
          ready = _settledActionReadiness(
            delta,
            eligible: true,
            priorDerivedSeeds: recurringSeeds ?? const {},
            firstActivitySeeds: firstActivitySeeds ?? const {},
          );
        } else {
          fullReadinessRuns++;
          final all = [..._events.values, ...delta]..sort(compareEvents);
          ready = Set.unmodifiable(store._semanticReadyIds(all));
        }
        if (ready == null ||
            !_ready!.every(ready.contains) ||
            store._textBaseline?.id != priorBaseline ||
            store.textWriteBlocked != priorBlocked) {
          db.execute('ROLLBACK');
          close();
          return null;
        }
        db.execute('COMMIT');
        projectedEvents += delta.length;
        if (settled) settledTextReadinessRuns++;
        _ready = ready;
        _validatedInputKey = inputKey;
        for (final event in delta) {
          _raws[event.id] = event.canonicalRaw!;
          _events[event.id] = event;
          _textRelations.add(event);
          if (event.sequence > (_lastSequences[event.writer] ?? 0)) {
            _lastSequences[event.writer] = event.sequence;
          }
        }
        return ready;
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        close();
        rethrow;
      } finally {
        _textCandidate = null;
      }
    });
  }

  Set<String>? _settledActionReadiness(
    List<LogEvent> delta, {
    required bool eligible,
    Map<String, String> priorDerivedSeeds = const {},
    Map<String, _FirstDerivedTextSeed> firstActivitySeeds = const {},
  }) {
    // In a completely published graph, an ordinary text update/Undo cannot
    // introduce a new birth, baseline, order anchor or dependency for old ready
    // actions. Check only its fields; uncertain native dependencies fall back.
    final store = _store!;
    if (_ready == null || _ready!.length != _raws.length || !eligible) {
      return null;
    }
    final derived = <String, LogEvent>{};
    for (final event in delta) {
      if (isTaskCompletion(event.type) && event.data['successor'] is Map) {
        derived[(event.data['successor'] as Map)['id'] as String] = event;
      }
      if (event.type == 'task.completedWithChecklist') {
        for (final item in (event.data['checklist'] as Map)['items'] as List) {
          derived[(item as Map)['id'] as String] = event;
        }
      }
    }
    for (final entity in {
      ...delta.map((e) => e.entity),
      ...derived.keys,
      ...firstActivitySeeds.keys,
    }) {
      final rows = store.db.select(
        'SELECT raw FROM ${store.tables.views} WHERE id=?',
        [entity],
      );
      if (rows.isEmpty) return null;
      final state = jsonDecode(rows.single['raw'] as String) as Map;
      // Eligibility checked the prior graph; a derived target must still
      // have its actual selected seed and PRIOR own activity in that ready set.
      final explicit = store.db.select(
        "SELECT 1 FROM ${store.tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN ('task.created','task.createdWithText','checklist.itemCreated') LIMIT 1",
        [entity],
      ).isNotEmpty;
      final birth = derived[entity];
      final firstActivity = firstActivitySeeds[entity];
      if (firstActivity != null &&
          store._firstDerivedTextSeed(
                entity,
                firstActivity.kind,
                _ready!,
                allowExplicit: firstActivity.explicit,
              ) !=
              firstActivity) {
        return null;
      }
      if (birth != null) {
        final seeds = store.db.select(
          "SELECT raw FROM ${store.tables.events} WHERE json_extract(semantic,'\$.data.successor.id')=? ORDER BY clock,writer,seq",
          [entity],
        );
        if (seeds.isNotEmpty) {
          final selected = store
              ._successorSelection(entity, seeds, const [])
              .seed
              .id;
          if (selected != birth.id && selected != priorDerivedSeeds[entity]) {
            return null;
          }
        } else {
          final copies = store._itemCopySeeds(entity);
          final selected = priorDerivedSeeds[entity] ?? birth.id;
          if (copies.isEmpty || copies.first.$1.id != selected) return null;
        }
      }
      if (birth == null &&
          !explicit &&
          firstActivity == null &&
          !store._hasReadyDerivedIdentity(
            entity,
            state['kind'] as String,
            _ready!,
          )) {
        return null;
      }
      if (state['textUnavailable'] != null ||
          state['textInheritancePending'] == true) {
        return null;
      }
      if (store.textEngine != null) {
        for (final field in store.db.select(
          'SELECT * FROM ${store.tables.textFields} WHERE entity=?',
          [entity],
        )) {
          if (field['adapter'] == 2) continue;
          if (store.textEngine!.checkpointHasPending(
            NativeTextCheckpoint(
              NativeTextState.fromBytes(field['state'] as Uint8List),
            ),
            limits: NativeTextLimits(
              visibleUtf16: field['field'] == 'title' ? 500 : 10000,
            ),
          )) {
            return null;
          }
        }
      }
      final hasSeed = store.db.select(
        "SELECT 1 FROM ${store.tables.events} WHERE entity=? AND json_extract(semantic,'\$.type') IN ('task.createdWithText','checklist.itemCreated') LIMIT 1",
        [entity],
      ).isNotEmpty;
      final needsTextContext = delta.any(
        (e) =>
            e.entity == entity &&
            (e.type == 'task.textEdited' || e.type == 'task.textEditUndone'),
      );
      if (needsTextContext &&
          !hasSeed &&
          !store._hasInheritedText(entity) &&
          (store._textBaseline == null ||
              !_ready!.contains(store._textBaseline!.id))) {
        return null;
      }
    }
    return Set.unmodifiable({..._ready!, ...delta.map((e) => e.id)});
  }

  void _restoreCleanCache(List<LogEvent> candidate, {String? inputKey}) {
    if (profile == null || locationKey == null || manifestDigest == null) {
      return;
    }
    final watch = Stopwatch()..start();
    final source = profile!.database;
    final proofRows = source.select(
      'SELECT value FROM profile_metadata WHERE key=?',
      [_proofKey],
    );
    if (proofRows.isEmpty) return;
    // Consume the witness durably before any restored state can be exposed.
    // A later crash then requires canonical rebuild, never retry of a Save.
    profile!.transaction(
      () => source.execute('DELETE FROM profile_metadata WHERE key=?', [
        _proofKey,
      ]),
    );
    try {
      final proof = jsonDecode(proofRows.single['value'] as String) as Map;
      if (proof['generation'] != 5 ||
          proof['manifest'] != manifestDigest ||
          proof['native'] != (textEngine != null)) {
        return;
      }
      final tables = TaskTables.forLocation(locationKey!);
      final rows = _taskCacheRows(source, tables);
      final incoming = {for (final e in candidate) e.id: e};
      final cachedEvents = <LogEvent>[];
      for (final row in rows.first) {
        final event = incoming[row[0]];
        if (event == null || event.canonicalRaw != row[5]) {
          return;
        }
        cachedEvents.add(event);
      }
      final ready = (proof['ready'] as List).cast<String>();
      final ids = cachedEvents.map((e) => e.id).toSet();
      // The owning history already computed the full canonical root. Reuse it
      // only for an exact ID/raw bijection with the whole candidate. A valid
      // closed PREFIX still needs its own root before the new delta is admitted.
      final fullOwnedCandidate =
          owningHistory?.ownsTaskValidator(this) == true &&
          inputKey != null &&
          isEventHash(inputKey) &&
          incoming.length == candidate.length &&
          cachedEvents.length == candidate.length &&
          ids.length == incoming.length;
      final cachedRevision = fullOwnedCandidate
          ? inputKey
          : _taskProjectionRevision(cachedEvents);
      if (ready.toSet().length != ready.length ||
          !ready.every(ids.contains) ||
          proof['revision'] != cachedRevision ||
          proof['digest'] != _taskCacheDigest(rows, ready)) {
        return;
      }
      warmCacheProofMicroseconds = watch.elapsedMicroseconds;
      final target = _store!, names = _taskCacheTables(target.tables);
      target.db.execute('BEGIN IMMEDIATE');
      try {
        _insertTaskCacheRows(target.db, names, rows);
        target._validateTextBaseline();
        target.db.execute('COMMIT');
      } catch (_) {
        if (!target.db.autocommit) {
          target.db.execute('ROLLBACK');
        }
        rethrow;
      }
      _raws.addAll({for (final e in cachedEvents) e.id: e.canonicalRaw!});
      _events.addAll({for (final event in cachedEvents) event.id: event});
      _ready = Set.unmodifiable(ready);
      for (final e in cachedEvents) {
        if (e.sequence > (_lastSequences[e.writer] ?? 0)) {
          _lastSequences[e.writer] = e.sequence;
        }
      }
      reusedProjectionRevision = proof['revision'] as String;
      warmCacheRestoreMicroseconds =
          watch.elapsedMicroseconds - warmCacheProofMicroseconds;
    } on FormatException {
      // A damaged/disposable witness is a rebuild hint only.
    } on TypeError {
      // Malformed disposable proof: replay canonical records.
    } on SqliteException {
      // Damaged/missing cache tables: replay canonical records.
    } on FormatFailure {
      // An invalid cached field cannot authorize a write.
    }
  }

  bool copyProjectionTo(TaskStore target, Iterable<LogEvent> events) {
    if (_store == null || _ready == null) return false;
    final canonical = {for (final e in events) e.id: e.canonicalRaw!};
    if (canonical.length != _raws.length ||
        canonical.entries.any((e) => _raws[e.key] != e.value)) {
      return false;
    }
    target._invalidateCopySeedIndex();
    final rows = _taskCacheRows(_store!.db, _store!.tables);
    final names = _taskCacheTables(target.tables);
    // Only disposable projection rows cross this boundary. UI preferences,
    // protected heads, profile settings and native editor owners stay in place.
    target.db.execute(
      "DELETE FROM ${target.tables.metadata} WHERE key IN ('order_projection','text_baseline_verified')",
    );
    _insertTaskCacheRows(target.db, names, rows);
    target._ensureProjectionIndexes();
    target._canonicalTextInput = _store!._canonicalTextInput;
    return true;
  }

  void sealCleanCache(
    Database source,
    TaskTables tables,
    Iterable<LogEvent> events,
  ) {
    if (profile == null ||
        _store == null ||
        _ready == null ||
        locationKey == null ||
        manifestDigest == null) {
      return;
    }
    final canonical = {for (final e in events) e.id: e.canonicalRaw!};
    if (canonical.length != _raws.length ||
        canonical.entries.any((e) => _raws[e.key] != e.value)) {
      return;
    }
    final ready = _ready!.toList()..sort();
    final rows = _taskCacheRows(source, tables);
    final expected = _taskCacheRows(_store!.db, _store!.tables);
    final digest = _taskCacheDigest(rows, ready);
    // Do not bless an unobserved change to the live disposable cache at close.
    if (digest != _taskCacheDigest(expected, ready)) return;
    source.execute('INSERT OR REPLACE INTO profile_metadata VALUES (?,?)', [
      _proofKey,
      jsonEncode({
        'generation': 5,
        'manifest': manifestDigest,
        'native': textEngine != null,
        'revision': _taskProjectionRevision(events),
        'digest': digest,
        'ready': ready,
      }),
    ]);
  }

  void close() {
    _validatedInputKey = null;
    _textCandidate = null;
    _textRelations = _TaskTextRelations();
    final store = _store;
    _store = null;
    _raws.clear();
    _events.clear();
    _lastSequences.clear();
    _ready = null;
    reusedProjectionRevision = null;
    if (store != null) {
      store._canonicalTextInput = null;
      store._recurringTextMemo.clear();
      store.db.close();
    }
  }
}
