import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import '../domain/validated_action_cache.dart';
import '../domain/time_zone_policy.dart';
import '../food/inventory.dart';
import '../food/food_record.dart';
import '../food/food_admission.dart';
import 'history_store.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'unified_manifest.dart';
import 'unified_record.dart';
import 'workspace_view.dart';
import 'task_store.dart';
import '../text/native_text_engine.dart';

typedef UnifiedProjectionStage =
    void Function() Function(UnifiedSnapshot snapshot);

typedef UnifiedEffectBuilder =
    UnifiedEffect Function(
      int sequence,
      EventClock clock,
      String commonPredecessor,
    );

// A same-session proof of the ORIGINAL reservation base, independent of any
// protected head advanced by lost-acknowledgement reconciliation.
/// Lets loading and refresh frames run while a long refresh holds the profile
/// queue: yields to the event loop once the isolate has been kept for a
/// frame's worth of work. Call only where nothing is half published.
class _FrameBudget {
  final _held = Stopwatch()..start();

  bool get due => _held.elapsedMicroseconds >= 8000;

  Future<void> pause() async {
    await Future<void>.delayed(Duration.zero);
    _held.reset();
  }
}

class _PendingBaseProof {
  _PendingBaseProof(
    this.pending,
    this.manifest,
    this.bytes,
    this.sequence,
    this.head,
    this.digest,
    this.clock,
  );
  final Map<String, Object?> pending;
  final String manifest, head, digest;
  final Uint8List bytes;
  final int sequence;
  final EventClock? clock;
}

class _PreparedAction {
  _PreparedAction(
    this.base,
    this.pending,
    this.record,
    this.effects,
    this.foodAdmission,
    this.readyTasks,
    this.taskRevision,
  );
  final UnifiedSnapshot base;
  final Map<String, Object?> pending;
  final UnifiedRecord record;
  final List<UnifiedEffect> effects;
  final FoodAdmission foodAdmission;
  final Set<String> readyTasks;
  final String taskRevision;
}

class UnifiedReservation {
  UnifiedReservation(this.records, this.bytes);
  final List<UnifiedRecord> records;
  final Uint8List bytes;
}

/// A single admitted revision. Physical observations include incomplete tails;
/// effects include only complete validated actions.
class UnifiedSnapshot {
  UnifiedSnapshot(
    this.revision,
    this.records,
    this.effects,
    this.physical,
    this.published,
    this.incomplete,
    this.foodAdmission,
    this.pendingEffects, {
    this.readyTaskIds = const {},
  });
  final Set<String> readyTaskIds;
  final Object _identity = Object();
  bool? _knownAllTasksReady;
  late final bool allVisibleTasksReady =
      _knownAllTasksReady ?? tasks.every((e) => readyTaskIds.contains(e.id));
  final String revision;
  final List<UnifiedRecord> records;
  final List<UnifiedEffect> effects;
  final Map<String, Uint8List> physical;
  final Map<String, int> published;
  final bool incomplete;
  final FoodAdmission foodAdmission;
  final bool pendingEffects;
  Map<String, List<UnifiedRecord>>? _writerRecords;
  Map<String, List<UnifiedRecord>> get recordsByWriter =>
      _writerRecords ??= _indexRecords();
  Map<String, List<UnifiedRecord>> _indexRecords() {
    final grouped = <String, List<UnifiedRecord>>{};
    for (final record in records) {
      (grouped[record.writer] ??= []).add(record);
    }
    return Map.unmodifiable(
      grouped.map((k, v) => MapEntry(k, List<UnifiedRecord>.unmodifiable(v))),
    );
  }

  Map<String, int>? _logicalHeads;
  Map<String, int> get logicalSequences =>
      _logicalHeads ??= _logicalSequences();
  Map<String, int> _logicalSequences() {
    final result = <String, int>{};
    for (final effect
        in records.expand((r) => r.effects).where((e) => e.isData)) {
      if (effect.sequence > (result[effect.writer] ?? 0)) {
        result[effect.writer] = effect.sequence;
      }
    }
    return Map.unmodifiable(result);
  }

  EventClock? _clock;
  bool _clockKnown = false;
  EventClock? get maximumClock {
    if (!_clockKnown) {
      _clock = records.isEmpty
          ? null
          : records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);
      _clockKnown = true;
    }
    return _clock;
  }

  Iterable<LogEvent> get tasks =>
      effects.where((e) => e.task != null).map((e) => e.task!);
  Iterable<FoodOperation> get food => effects
      .where(
        (e) => e.food != null && foodAdmission.readyIds.contains(e.food!.id),
      )
      .map((e) => e.food!.operation);
  String? deviceName(String writer) {
    String? result;
    for (final record in records) {
      if (record.writer == writer &&
          record.effects.length == 1 &&
          record.effect.kind == 'writer.named' &&
          record.sequence <= (published[writer] ?? 0)) {
        result = record.effect.name;
      }
    }
    return result;
  }

  String deviceLabel(String writer) =>
      deviceName(writer) ?? 'Unnamed device · ${writer.substring(0, 8)}';
}

/// Sole write/recovery authority. Public calls use the existing profile queue.
/// *InProfileQueue methods are for stores already executing on that same queue;
/// they must never be invoked from a second independent store queue.
final class UnifiedHistory {
  UnifiedHistory._(
    this.folder,
    this.profile,
    this.writer,
    this.now,
    this.textEngine, {
    bool deferPeerCatchUp = false,
  }) : _deferPeerCatchUp = deferPeerCatchUp;
  final LogFolder folder;
  final LocalProfileDatabase profile;
  final String writer;
  final DateTime Function() now;
  final NativeTextEngine? textEngine;
  late UnifiedManifest manifest;
  UnifiedSnapshot? _snapshot;
  String? _acceptedHeads;
  // ADR0007: provider checkpoints are hints for incremental normal reads.
  // Explicit audits and reconstruction verify every canonical byte again.
  Map<String, LogFileInfo> _fileInfos = {};
  Map<String, int> _completeEnds = {};
  Map<String, int> _migrationEnds = {};
  Set<String> _seekableFiles = {};
  UnifiedSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Unified history is not admitted.'));
  Object? safetyFailure;
  int readFiles = 0;
  final _changes = WorkspaceChanges();
  bool _viewHasPending = false;
  bool get viewHasPending => _viewHasPending;
  void reportQueueFailure(Object error) {
    safetyFailure = error;
    _changes.notify();
  }

  Future<T> _onProfile<T>(Future<T> Function() work) async {
    var entered = false;
    try {
      return await profile.serialize(() {
        entered = true;
        return work();
      });
    } catch (error) {
      if (!entered) reportQueueFailure(error);
      rethrow;
    }
  }

  void Function() listenChanges(void Function() listener) =>
      _changes.listen(listener);
  bool _closed = false;
  bool _joiningHeader = false;
  Future<void>? _closing;
  final _projections = <Object, UnifiedProjectionStage>{};
  // Cache only successful pure native/domain validation by exact semantic bytes.
  // New suffixes, protected observations and SQL projections remain checked.
  // Unchanged prefixes follow ADR0007's explicit-audit contract.
  final _taskValidation = <String, Set<String>>{};
  final _verifiedTaskRevisions = Expando<String>(
    'Owning authority exact visible Task validation',
  );

  // Only this owning authority can expose the already validated exact input key.
  String? validatedTaskRevision(UnifiedSnapshot snapshot) =>
      _verifiedTaskRevisions[snapshot];

  final _verifiedRawTaskRoots = Expando<String>(
    'Explicit canonical Task oracle',
  );

  bool verifiesTaskRevision(UnifiedSnapshot snapshot, String revision) {
    final key = _verifiedTaskRevisions[snapshot];
    if (key == null) return false;
    if (key == revision) return true;
    // Explicit callers may ask for the generic raw-root oracle. Normal internal
    // stages use the owning process key and never perform this history walk.
    final rawRoot = _verifiedRawTaskRoots[snapshot] ??=
        TaskStore.canonicalTaskRevision(snapshot.tasks);
    return rawRoot == revision;
  }

  final _validatedOwnDeltas =
      Expando<
        ({Object baseToken, List<LogEvent> tasks, List<FoodRecord> food})
      >('Own action delta');

  List<LogEvent>? validatedTaskDelta(
    UnifiedSnapshot candidate,
    UnifiedSnapshot? base,
  ) {
    final proof = _validatedOwnDeltas[candidate];
    return proof != null && identical(proof.baseToken, base?._identity)
        ? proof.tasks
        : null;
  }

  List<FoodRecord>? validatedFoodDelta(
    UnifiedSnapshot candidate,
    UnifiedSnapshot? base,
  ) {
    final proof = _validatedOwnDeltas[candidate];
    return proof != null && identical(proof.baseToken, base?._identity)
        ? proof.food
        : null;
  }

  final _foodValidation = <String, FoodAdmission>{};
  // Reuse decoding only for identical canonical source strings. File bytes,
  // trusted prefixes, manifest policy, chains and admission are still checked.
  // Bound retained strings independently of the workspace/file byte limits.
  // Same bounds as the sealed decode cache, so a restored cache is never
  // evicted back into strict decoding.
  final _decodedRecords = <String, UnifiedRecord>{};
  int _decodedRecordBytes = 0;
  static const _decodedRecordBudget = ValidatedActionCache.maximumBytes;
  int decodedRecords = 0;
  int semanticValidationRuns = 0;
  int incrementalFoodAdmissionRuns = 0, fullFoodAdmissionRuns = 0;
  TaskSemanticValidator? _semanticValidator;
  int get warmTaskCacheProofMicroseconds =>
      _semanticValidator?.warmCacheProofMicroseconds ?? 0;
  int get warmTaskCacheRestoreMicroseconds =>
      _semanticValidator?.warmCacheRestoreMicroseconds ?? 0;
  int get fullTaskReadinessRuns => _semanticValidator?.fullReadinessRuns ?? 0;
  int get settledTextReadinessRuns =>
      _semanticValidator?.settledTextReadinessRuns ?? 0;
  String? takeReusedTaskProjectionRevision() {
    final revision = _semanticValidator?.reusedProjectionRevision;
    _semanticValidator?.reusedProjectionRevision = null;
    return revision;
  }

  /// A synchronous detached dependency read from this exact owning snapshot.
  /// Prepared scratch state cannot be borrowed by an older committed snapshot.
  int get taskSelectedReadCount =>
      _semanticValidator?.selectedTextReadCount ?? 0;

  /// Validator dependency reads that scanned every canonical Task row.
  int get taskHistoryScanReads => _semanticValidator?.historyScanReadCount ?? 0;

  bool ownsTaskValidator(TaskSemanticValidator validator) =>
      identical(_semanticValidator, validator);

  TaskTextReadSelection? selectTaskText(
    UnifiedSnapshot snapshot,
    Iterable<String> roots,
  ) {
    final key = _verifiedTaskRevisions[snapshot];
    if (key == null) return null;
    return _semanticValidator?.selectText(key, roots);
  }

  List<String>? selectTaskCopySeedRaws(
    UnifiedSnapshot snapshot,
    String entity,
  ) {
    final key = _verifiedTaskRevisions[snapshot];
    if (key == null) return null;
    return _semanticValidator?.selectCopySeedRaws(key, entity);
  }

  List<String>? selectTaskTagMutationRaws(
    UnifiedSnapshot snapshot,
    LogEvent pending,
  ) {
    final key = _verifiedTaskRevisions[snapshot];
    if (key == null) return null;
    return _semanticValidator?.selectTagMutationRaws(key, pending);
  }

  bool copyValidatedTaskProjection(
    TaskStore store,
    UnifiedSnapshot candidate,
    String revision,
  ) =>
      verifiesTaskRevision(candidate, revision) &&
      (_semanticValidator?.copyProjectionTo(store, candidate.tasks) ?? false);

  Future<void> sealTaskProjectionCache(TaskStore store) async {
    profile.transaction(() {
      _semanticValidator?.sealCleanCache(
        store.db,
        store.tables,
        snapshot.tasks,
      );
    });
  }

  /// Records restored from the history store at open (none on a strict open).
  int decodedCacheReuses = 0;

  // Lee 11-05 (design/history-store.md): the whole decoded history lives in
  // the profile database, appended in the transactions that advance
  // protected_app_heads. [_storeSeals] mirrors the stored seals while the
  // store is known to match; null means the next commit rebuilds it.
  late final HistoryStore _store = HistoryStore(
    profile.database,
    bytesDigest(utf8.encode(folder.location)),
  );
  Map<String, HistorySeal>? _storeSeals;
  bool _attemptedStoreRestore = false;
  final bool _deferPeerCatchUp;
  bool _catchUpPending = false;

  /// True after an open that admitted only the stored state while peers
  /// have newer bytes; the next refresh applies them (Lee 11-05: lists are
  /// usable during catch-up).
  bool get catchUpPending => _catchUpPending;

  String _storeBinding(UnifiedManifest m) => HistoryStore.binding(
    space: m.space,
    epoch: m.epoch,
    manifestDigest: m.digest,
    writer: writer,
    nativeText: textEngine != null,
  );

  /// The open's fast check (design/history-store.md). Null means strict.
  Future<
    Map<
      String,
      ({
        List<UnifiedRecord> records,
        Uint8List bytes,
        int end,
        int migrationEnd,
      })
    >?
  >
  _restoreStore(
    UnifiedManifest current,
    Map<String, LogFileInfo> byName,
  ) async {
    if (folder is! BoundedRangeLogFolder) return null;
    final range = folder as BoundedRangeLogFolder;
    try {
      if (_store.readBinding() != _storeBinding(current)) return null;
      final seals = _store.readSeals();
      final heads = profile.database.select(
        'SELECT writer,sequence,hash,bytes FROM protected_app_heads WHERE space=? AND epoch=?',
        [current.space, current.epoch],
      );
      if (heads.length != seals.length) return null;
      for (final row in heads) {
        final seal = seals[row['writer'] as String];
        if (seal == null ||
            seal.sequence != row['sequence'] ||
            seal.hash != row['hash'] ||
            seal.end != row['bytes']) {
          return null;
        }
      }
      // Fast check for every writer first; decode rows only if all pass.
      final tails = <String, Uint8List>{};
      // Bound provider pressure even for workspaces with many writers. Wait for
      // every probe in a batch (including failures) before strict fallback can
      // begin; publish results in seal order, never provider completion order.
      final entries = seals.entries
          .where((e) => e.value.sequence != 0)
          .toList();
      const probeConcurrency = 4;
      for (var start = 0; start < entries.length; start += probeConcurrency) {
        final batch = entries.skip(start).take(probeConcurrency).toList();
        final checked = await Future.wait(
          batch.map((entry) async {
            final MapEntry(key: owner, value: seal) = entry;
            final name = unifiedLogName(owner);
            final info = byName[name];
            final size = info?.size;
            if (info == null || size != null && size < seal.end) return null;
            await _checkRegularFile(name);
            final lastRaw = _store.rawAt(owner, seal.sequence);
            if (lastRaw == null) return null;
            final last = utf8.encode(lastRaw);
            if (seal.end - seal.lastStart != last.length + 1) return null;
            final tail = await range.readFromBounded(
              name,
              seal.lastStart,
              maximumFileBytes - seal.lastStart,
            );
            readFiles++;
            if (tail == null ||
                tail.length <= last.length ||
                tail[last.length] != 10 ||
                !_samePrefix(tail, last, last.length)) {
              return null;
            }
            return tail;
          }),
          eagerError: false,
        );
        if (checked.any((tail) => tail == null)) return null;
        for (var i = 0; i < batch.length; i++) {
          tails[batch[i].key] = checked[i]!;
        }
      }
      final result =
          <
            String,
            ({
              List<UnifiedRecord> records,
              Uint8List bytes,
              int end,
              int migrationEnd,
            })
          >{};
      var reused = 0, catchUp = false;
      final rowsByOwner = <String, List<StoredRow>>{};
      final frames = _FrameBudget();
      for (final owner in tails.keys) {
        if (frames.due) await frames.pause();
        final seal = seals[owner]!;
        final rows = _store.readWriter(owner, seal);
        if (rows == null ||
            rows.last.start != seal.lastStart ||
            rows.last.start + rows.last.length + 1 != seal.end) {
          return null;
        }
        rowsByOwner[owner] = rows;
      }
      // Workers decode the rows while this isolate rebuilds each writer's
      // bytes from the same rows, a frame's worth at a time.
      final decoding = _decodeStoredRows(rowsByOwner, frames)..ignore();
      final prefixes = <String, BytesBuilder>{};
      for (final MapEntry(key: owner, value: rows) in rowsByOwner.entries) {
        final builder = prefixes[owner] = BytesBuilder(copy: false);
        for (final row in rows) {
          builder
            ..add(utf8.encode(row.raw))
            ..addByte(10);
          if (frames.due) await frames.pause();
        }
      }
      final decoded = await decoding;
      for (final MapEntry(key: owner, value: tail) in tails.entries) {
        final seal = seals[owner]!;
        final rows = rowsByOwner[owner]!;
        final historicalCount = current.owners[owner]?['count'] as int? ?? 0;
        if (historicalCount > rows.length) return null;
        final migration = historicalCount == 0
            ? null
            : rows[historicalCount - 1];
        final builder = prefixes[owner]!;
        if (builder.length != seal.end) return null;
        final suffix = Uint8List.sublistView(tail, seal.end - seal.lastStart);
        final defer = _deferPeerCatchUp && owner != writer;
        if (defer && suffix.isNotEmpty) catchUp = true;
        if (!defer) builder.add(suffix);
        result[owner] = (
          records: List.unmodifiable(decoded[owner]!),
          bytes: Uint8List.fromList(builder.takeBytes()).asUnmodifiableView(),
          end: seal.end,
          migrationEnd: migration == null
              ? 0
              : migration.start + migration.length + 1,
        );
        reused += rows.length;
      }
      _storeSeals = Map.of(seals);
      decodedCacheReuses = reused;
      _catchUpPending = catchUp;
      return result;
    } on SqliteException {
      return null;
    } on FormatException {
      return null;
    } on FormatFailure {
      return null;
    } on FolderAccessFailure {
      return null;
    } on TypeError {
      return null;
    } on RemoteError {
      return null; // A failed worker decode cannot authorize a restore.
    }
  }

  /// Decodes stored rows in parallel short-lived isolates (pure data only;
  /// no profile or native owner crosses), on this isolate if unavailable.
  static Future<Map<String, List<UnifiedRecord>>> _decodeStoredRows(
    Map<String, List<StoredRow>> rows,
    _FrameBudget frames,
  ) async {
    const chunk = 400;
    final jobs = <(String, int, List<StoredRow>)>[
      for (final MapEntry(key: owner, value: list) in rows.entries)
        for (var i = 0; i < list.length; i += chunk)
          (owner, i, list.sublist(i, min(i + chunk, list.length))),
    ];
    List<List<UnifiedRecord>> parts;
    try {
      // Starting a worker copies its rows on this isolate. A worker that
      // fails during a pause still reports through the wait below.
      final workers = <Future<List<UnifiedRecord>>>[];
      for (final job in jobs) {
        if (frames.due) await frames.pause();
        workers.add(
          Isolate.run(
            () => HistoryStore.decode(job.$3),
            debugName: 'tandemlog-store-decode',
          )..ignore(),
        );
      }
      parts = await Future.wait(workers);
    } on IsolateSpawnException {
      parts = [for (final job in jobs) HistoryStore.decode(job.$3)];
    } on UnsupportedError {
      parts = [for (final job in jobs) HistoryStore.decode(job.$3)];
    }
    final result = <String, List<UnifiedRecord>>{};
    for (var j = 0; j < jobs.length; j++) {
      (result[jobs[j].$1] ??= []).addAll(parts[j]);
    }
    return result;
  }

  /// Inside the commit transaction: append each writer's newly admitted
  /// records and move its seal to the protected head being written, or
  /// rebuild the whole store when it is not known to match.
  void _syncStore(
    UnifiedManifest current,
    List<List<Object?>> heads,
    Map<String, List<UnifiedRecord>> records,
    Map<String, Map<int, ({int start, int length})>> offsets,
    Map<String, Uint8List> observed,
  ) {
    try {
      var seals = _storeSeals;
      if (seals == null) {
        _store.reset(_storeBinding(current));
        seals = {};
      }
      final next = <String, HistorySeal>{};
      for (final row in heads) {
        final owner = row[2] as String,
            sequence = row[3] as int,
            hash = row[4] as String,
            end = row[5] as int;
        final known = offsets[owner] ?? const {};
        var old = seals[owner];
        if (old != null && old.sequence > 0 && known.containsKey(1)) {
          // This writer was re-read from byte 0 (audit or a prefix that could
          // not be reused): replace its rows with that strict decode.
          _store.deleteWriter(owner);
          old = null;
        } else if (old != null &&
            old.sequence == sequence &&
            old.hash == hash &&
            old.end == end) {
          next[owner] = old;
          continue;
        }
        final from = old?.sequence ?? 0;
        final ownerRecords = records[owner] ?? const <UnifiedRecord>[];
        if (sequence < from || ownerRecords.length < sequence) {
          throw StateError('History store is ahead of admitted history.');
        }
        var at = known;
        for (var s = from + 1; s <= sequence; s++) {
          if (!at.containsKey(s)) {
            at = _lineOffsets(observed[owner]!);
            break;
          }
        }
        final added = [
          for (var s = from + 1; s <= sequence; s++)
            (
              record: ownerRecords[s - 1],
              start: at[s]!.start,
              length: at[s]!.length,
            ),
        ];
        final seal = HistorySeal(
          sequence,
          end,
          hash,
          sequence == 0 ? 0 : (added.lastOrNull?.start ?? old!.lastStart),
        );
        if (sequence > 0 && added.isEmpty) {
          throw StateError('History store seal moved without records.');
        }
        _store.append(owner, added, seal);
        next[owner] = seal;
      }
      _storeSeals = next;
    } on Object {
      // A store that cannot follow is dropped, never left half-current; the
      // next open is strict and rebuilds it. Admission itself is unaffected.
      _storeSeals = null;
      try {
        _store.drop();
      } on SqliteException {
        // Its seals no longer equal the protected heads: still strict.
      }
    }
  }

  /// Inside the own-action confirmation transaction: this device's record
  /// goes after its own sealed head, with the protected head it moves to.
  void _appendOwnToStore(UnifiedRecord record, int start, int end) {
    final seals = _storeSeals;
    if (seals == null) return; // Rebuilt at the next commit or strict open.
    try {
      final old = seals[writer];
      if ((old?.sequence ?? 0) != record.sequence - 1 ||
          (old?.end ?? 0) != start) {
        throw StateError('Own record does not follow the sealed head.');
      }
      final seal = HistorySeal(record.sequence, end, record.hash, start);
      _store.append(writer, [
        (record: record, start: start, length: end - start - 1),
      ], seal);
      _storeSeals = {...seals, writer: seal};
    } on Object {
      _storeSeals = null;
      try {
        _store.drop();
      } on SqliteException {
        // Its seal no longer equals the protected head: still strict.
      }
    }
  }

  static Map<int, ({int start, int length})> _lineOffsets(Uint8List bytes) {
    final result = <int, ({int start, int length})>{};
    var start = 0, sequence = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 10) continue;
      result[++sequence] = (start: start, length: i - start);
      start = i + 1;
    }
    return result;
  }

  UnifiedRecord _decodeRecord(String raw, {bool force = false}) {
    final remembered = _decodedRecords.remove(raw);
    if (remembered != null && !force) {
      _decodedRecords[raw] = remembered;
      return remembered;
    }
    if (remembered != null) _decodedRecordBytes -= raw.length * 4;
    final record = UnifiedRecord.decode(raw);
    decodedRecords++;
    final cost = raw.length * 4;
    if (cost <= _decodedRecordBudget) {
      while (_decodedRecords.isNotEmpty &&
          (_decodedRecords.length >= ValidatedActionCache.maximumRecords ||
              _decodedRecordBytes + cost > _decodedRecordBudget)) {
        final oldest = _decodedRecords.keys.first;
        _decodedRecords.remove(oldest);
        _decodedRecordBytes -= oldest.length * 4;
      }
      _decodedRecords[raw] = record;
      _decodedRecordBytes += cost;
    }
    return record;
  }

  Map<String, Object?>? _pending;
  _PendingBaseProof? _pendingBaseProof;
  Map<String, dynamic>? _pendingProvenance;
  _PreparedAction? _preparedAction;

  /// Called on the shared profile queue. Staging runs synchronously inside the
  /// same SQL transaction as admission; memory publishes only after its commit.
  void attachProjectionInProfileQueue(
    Object owner,
    UnifiedProjectionStage stage,
  ) {
    if (_closed || _projections.containsKey(owner)) {
      throw StateError('Invalid app projection attachment.');
    }
    late void Function() publish;
    profile.transaction(() {
      publish = stage(snapshot);
    });
    _projections[owner] = stage;
    publish();
  }

  void detachProjectionInProfileQueue(Object owner) {
    _projections.remove(owner);
  }

  TimeZoneNamePolicy get timeZonePolicy => manifest.timeZonePolicy;

  String get _lease => 'app5:${folder.location}';
  String get _locationKey =>
      'app5.location.${bytesDigest(utf8.encode(folder.location))}';
  static const maximumFileBytes = maximumUnifiedFileBytes;
  static const maximumTotalBytes = maximumUnifiedWorkspaceBytes;

  static Future<UnifiedHistory> open(
    LogFolder folder, {
    required LocalProfileDatabase profile,
    required String writer,
    DateTime Function()? now,
    NativeTextEngine? textEngine,
    bool deferPeerCatchUp = false,
  }) async {
    if (!isCanonicalId(writer)) {
      throw FormatFailure('Invalid installation writer.');
    }
    if (LocalSettings.protectedValues(profile)['writer'] != writer) {
      throw FormatFailure(
        'Installation writer differs from protected settings.',
      );
    }
    final result = UnifiedHistory._(
      folder,
      profile,
      writer,
      now ?? DateTime.now,
      textEngine,
      deferPeerCatchUp: deferPeerCatchUp,
    );
    profile.acquireWorkspace(result._lease);
    try {
      await result.refresh();
      return result;
    } catch (_) {
      profile.releaseWorkspace(result._lease);
      rethrow;
    }
  }

  /// Only a genuinely empty folder can be initialized. Unsupported manifests,
  /// conflicted histories and interrupted conversions are never replaced.
  static Future<UnifiedHistory> create(
    LogFolder folder, {
    required LocalProfileDatabase profile,
    required String writer,
    NativeTextEngine? textEngine,
    DateTime Function()? now,
  }) async {
    final creationLease = 'creating:${const Uuid().v4()}';
    profile.acquireWorkspace(creationLease);
    try {
      final locationKey =
          'app5.location.${bytesDigest(utf8.encode(folder.location))}';
      if (profile.database.select(
        'SELECT 1 FROM profile_metadata WHERE key=?',
        [locationKey],
      ).isNotEmpty) {
        throw FormatFailure(
          'This workspace location was previously bound. Restore its missing history before opening it.',
        );
      }
      if ((await folder.list()).isNotEmpty) {
        throw FormatFailure(
          'This folder is not empty. Open a converted workspace or choose a new empty folder.',
        );
      }
      if (LocalSettings.protectedValues(profile)['writer'] != writer) {
        throw FormatFailure(
          'Installation identity differs from protected settings.',
        );
      }
      final manifest = UnifiedManifest.empty(const Uuid().v4(), writer);
      await folder.create(
        'tandemlog-space.json',
        Uint8List.fromList(utf8.encode(manifest.encode())),
      );
      return await open(
        folder,
        profile: profile,
        writer: writer,
        textEngine: textEngine,
        now: now,
      );
    } finally {
      profile.releaseWorkspace(creationLease);
    }
  }

  /// Validate a prospective ready manifest and exact files without binding an
  /// active epoch, creating a writer, or updating protected observations.
  static Future<UnifiedSnapshot> preflight(
    LogFolder folder, {
    required LocalProfileDatabase profile,
    required String writer,
    NativeTextEngine? textEngine,
  }) => profile.serialize(() async {
    if (!isCanonicalId(writer) ||
        LocalSettings.protectedValues(profile)['writer'] != writer) {
      throw FormatFailure('Invalid preflight installation identity.');
    }
    final probe = UnifiedHistory._(
      folder,
      profile,
      writer,
      DateTime.now,
      textEngine,
    );
    return probe._refresh(observe: false);
  });

  Future<UnifiedSnapshot> refresh() => _onProfile(refreshInProfileQueue);
  Future<UnifiedSnapshot> refreshInProfileQueue({
    bool forceFullAudit = false,
  }) async {
    try {
      if (_closed) throw StateError('App workspace is closed.');
      if (LocalSettings.protectedValues(profile)['writer'] != writer) {
        throw FormatFailure(
          'Installation writer differs from protected settings.',
        );
      }
      // Any refresh after the open reads every writer up to its end.
      final catchingUp = _attemptedStoreRestore;
      await _refresh(forceFullAudit: forceFullAudit);
      if (catchingUp) _catchUpPending = false;
      if (!_joiningHeader &&
          !manifest.owners.containsKey(writer) &&
          physicalSequence == 0 &&
          !hasPending &&
          !snapshot.pendingEffects) {
        _joiningHeader = true;
        try {
          await _prepareInProfileQueue([
            (seq, clock, head) => UnifiedEffect.joined(),
          ], reserve: true);
          await commitInProfileQueue();
        } finally {
          _joiningHeader = false;
        }
      }
      safetyFailure = null;
      _changes.notify();
      return snapshot;
    } catch (e) {
      safetyFailure = e;
      _changes.notify();
      rethrow;
    }
  }

  // A v5 outer record hash commits to its entire strictly canonical body and
  // predecessor. Unlike historical effect reference hashes it cannot be retained
  // across a body change. The tag distinguishes this from old full-byte SHA256.
  static String _chainCommitment(String head) => 'chain1:$head';

  static bool _validCommitment(
    String commitment,
    String head,
    Uint8List bytes,
    int end,
  ) {
    if (commitment.startsWith('chain1:')) {
      return commitment == _chainCommitment(head);
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(commitment)) return false;
    return bytesDigest(Uint8List.sublistView(bytes, 0, end)) == commitment;
  }

  static bool _canonicalPrefixMatches(
    UnifiedManifest m,
    String owner,
    Uint8List bytes,
    int end,
    int expectedSequence,
    String expectedHead,
  ) {
    var start = 0, sequence = 0;
    var head = unifiedGenesis(m.space, m.epoch, owner);
    EventClock? clock;
    try {
      for (var i = 0; i < end; i++) {
        if (bytes[i] != 10) continue;
        final r = UnifiedRecord.decode(
          utf8.decode(Uint8List.sublistView(bytes, start, i)),
        );
        if (r.space != m.space ||
            r.epoch != m.epoch ||
            r.writer != owner ||
            r.sequence != ++sequence ||
            r.previousHash != head ||
            clock != null && r.firstClock <= clock) {
          return false;
        }
        head = r.hash;
        clock = r.clock;
        start = i + 1;
      }
      return start == end &&
          sequence == expectedSequence &&
          head == expectedHead;
    } on FormatException {
      return false;
    } on FormatFailure {
      return false;
    }
  }

  Future<void> _checkRegularFile(String name) async {
    if (folder is LocalLogFolder) {
      final file = (folder as LocalLogFolder).file(name);
      if (await FileSystemEntityTypeCheck.regularFile(file.path) == false) {
        throw FormatFailure('Linked or missing unified history is unsafe.');
      }
    }
  }

  Future<Uint8List> _read(String name, int limit) async {
    if (folder is! BoundedLogFolder) {
      throw FormatFailure(
        'Provider cannot enforce unified history read limits.',
      );
    }
    await _checkRegularFile(name);
    final bytes = await (folder as BoundedLogFolder).readBounded(name, limit);
    if (name.endsWith('.applog')) readFiles++;
    return bytes;
  }

  Future<Uint8List> _readWithSeekProbe(
    String name,
    Set<String> seekable,
  ) async {
    var bytes = Uint8List.fromList(
      await _read(name, maximumFileBytes),
    ).asUnmodifiableView();
    seekable.remove(name);
    if (folder is BoundedRangeLogFolder) {
      final result = await (folder as BoundedRangeLogFolder).readFromBounded(
        name,
        bytes.length,
        maximumFileBytes - bytes.length,
      );
      readFiles++;
      if (result != null) {
        seekable.add(name);
        if (result.isNotEmpty) {
          final suffix = Uint8List.fromList(result);
          bytes = Uint8List.fromList(
            (BytesBuilder(copy: false)
                  ..add(bytes)
                  ..add(suffix))
                .takeBytes(),
          ).asUnmodifiableView();
        }
      }
    }
    return bytes;
  }

  Future<UnifiedSnapshot> _refresh({
    bool observe = true,
    bool forceFullAudit = false,
  }) => profile.observeAsynchronous(
    'history.refresh',
    () => _refreshObserved(observe: observe, forceFullAudit: forceFullAudit),
  );

  Future<UnifiedSnapshot> _refreshObserved({
    required bool observe,
    required bool forceFullAudit,
  }) async {
    final rawManifest = utf8.decode(
      await _read('tandemlog-space.json', 1024 * 1024),
    );
    final current = UnifiedManifest.decode(rawManifest);
    final bound = profile.database.select(
      'SELECT epoch,manifest,observed FROM protected_app_workspaces WHERE space=?',
      [current.space],
    );
    if (bound.isNotEmpty &&
        (bound.single['epoch'] != current.epoch ||
            bound.single['manifest'] != rawManifest)) {
      throw FormatFailure(
        'Workspace bootstrap changed. Preserve the profile and history before recovery.',
      );
    }
    final locationBinding = canonicalDataJson({
      'space': current.space,
      'epoch': current.epoch,
    });
    final locationRows = profile.database.select(
      'SELECT value FROM profile_metadata WHERE key=?',
      [_locationKey],
    );
    if (locationRows.isNotEmpty &&
        locationRows.single['value'] != locationBinding) {
      throw FormatFailure(
        'Workspace identity changed at a previously bound location. Preserve the profile and history.',
      );
    }
    final registered = <String>{};
    if (bound.isNotEmpty) {
      final raw = bound.single['observed'] as String;
      final j = jsonDecode(raw);
      if (j is! List ||
          j.any((v) => !isCanonicalId(v)) ||
          j.toSet().length != j.length ||
          !j.contains(writer) ||
          !j.toSet().containsAll(current.owners.keys) ||
          canonicalDataJson(j) != raw) {
        throw FormatFailure('Invalid protected app writer inventory.');
      }
      registered.addAll(j.cast<String>());
    }
    final authority = profile.database
        .select(
          'SELECT writer FROM protected_app_heads WHERE space=? AND epoch=?',
          [current.space, current.epoch],
        )
        .map((r) => r['writer'] as String)
        .toSet();
    if (authority.length != registered.length ||
        !authority.containsAll(registered)) {
      throw FormatFailure(
        'App writer observations differ from protected inventory.',
      );
    }
    final ownerSet = {...current.owners.keys, ...registered, writer};
    final infos = await folder.list(),
        byName = {for (final i in infos) i.name: i};
    if (byName.length != infos.length) {
      throw FormatFailure('Ambiguous app history filenames.');
    }
    for (final info in infos) {
      final name = info.name;
      if (name.toLowerCase().contains('sync-conflict')) {
        throw FormatFailure(
          'A sync conflict is present. Preserve both copies before recovery.',
        );
      }
      if (isSyncthingAppLogStagingName(name)) continue;
      if (name.contains('.applog')) {
        if (!name.endsWith('.applog')) {
          throw FormatFailure('Conflicting app history filename.');
        }
        final owner = name.substring(0, name.length - 7);
        if (!isCanonicalId(owner) || name != unifiedLogName(owner)) {
          throw FormatFailure('Unknown or conflicting app writer file $name.');
        }
        ownerSet.add(owner);
      }
      if (name.endsWith('.jsonl') || name.endsWith('.foodlog')) {
        throw FormatFailure(
          'Legacy history is not accepted in a normalized workspace. Preserve it outside this folder.',
        );
      }
    }
    final stored = observe && !forceFullAudit && !_attemptedStoreRestore
        ? await _restoreStore(current, byName)
        : null;
    _attemptedStoreRestore = true;
    final previous = _snapshot;
    final sameAcceptedHeads =
        previous != null &&
        current.digest == manifest.digest &&
        _acceptedHeads == _protectedHeads(current);
    // Keep the lookup receiver non-null independently of inferred bool flow.
    // AOT must not hoist a nullable previous.physical dereference out of the loop.
    final priorPhysical = previous?.physical ?? const <String, Uint8List>{};
    final physicalNow = <String, Uint8List>{};
    final retainedPrefixes = <String>{};
    final seekable = Set<String>.of(_seekableFiles);
    var physicalTotal = 0;
    for (final owner in ownerSet) {
      final name = unifiedLogName(owner);
      final info = byName[name];
      Uint8List bytes;
      final old = sameAcceptedHeads ? priorPhysical[owner] : null;
      final oldInfo = _fileInfos[name];
      final end = _completeEnds[owner];
      final prefix = stored?[owner];
      if (info == null) {
        bytes = Uint8List(0).asUnmodifiableView();
      } else {
        // Even zero-read metadata reuse must reject a symlink/replaced pathname.
        await _checkRegularFile(name);
        final size = info.size;
        if (size != null && (size < 0 || size > maximumFileBytes)) {
          throw FormatFailure('App history exceeds safe limits.');
        }
        final canSeek =
            folder is BoundedRangeLogFolder && seekable.contains(name);
        final forceOwnedObservation = _pending != null && owner == writer;
        final sameIdentity =
            oldInfo != null && oldInfo.identity == info.identity;
        if (prefix != null) {
          // Passed the open's fast check: stored prefix plus the bytes read
          // after the seal (none yet for a peer deferred to catch-up).
          bytes = prefix.bytes;
          retainedPrefixes.add(owner);
          seekable.add(name);
        } else if (!forceFullAudit &&
            canSeek &&
            !forceOwnedObservation &&
            old != null &&
            sameIdentity &&
            size == old.length &&
            info.stamp.isNotEmpty &&
            info.stamp == oldInfo.stamp) {
          bytes = old;
          retainedPrefixes.add(owner);
        } else if (!forceFullAudit &&
            canSeek &&
            old != null &&
            sameIdentity &&
            end != null &&
            size != null &&
            (size > old.length ||
                forceOwnedObservation &&
                    size == old.length &&
                    info.stamp == oldInfo.stamp)) {
          // Re-read an incomplete tail from the last COMPLETE LF boundary.
          // A provider without actual seek returns null, never skips the prefix.
          final suffix = await (folder as BoundedRangeLogFolder)
              .readFromBounded(name, end, maximumFileBytes - end);
          readFiles++;
          if (suffix != null) {
            // Own the provider buffer before validation or cooperative yields.
            bytes = suffix.isEmpty && end == old.length
                ? old
                : Uint8List.fromList(
                    (BytesBuilder(copy: false)
                          ..add(Uint8List.sublistView(old, 0, end))
                          ..add(Uint8List.fromList(suffix)))
                        .takeBytes(),
                  ).asUnmodifiableView();
            retainedPrefixes.add(owner);
          } else {
            bytes = await _readWithSeekProbe(name, seekable);
          }
        } else {
          bytes = await _readWithSeekProbe(name, seekable);
        }
      }
      physicalTotal += bytes.length;
      if (physicalTotal > maximumTotalBytes) {
        throw FormatFailure('App history exceeds safe limits.');
      }
      physicalNow[owner] = bytes;
    }
    if (observe &&
        !forceFullAudit &&
        previous != null &&
        current.digest == manifest.digest &&
        physicalNow.length == previous.physical.length &&
        physicalNow.entries.every(
          (e) =>
              previous.physical.containsKey(e.key) &&
              _sameBytes(e.value, previous.physical[e.key]!),
        ) &&
        sameAcceptedHeads) {
      // Preserve missing-file checks even for genuinely empty writer streams.
      for (final owner in ownerSet) {
        if (!byName.containsKey(unifiedLogName(owner)) &&
            (previous.records.any((r) => r.writer == owner) ||
                (current.owners[owner]?['count'] as int? ?? 0) > 0)) {
          throw FormatFailure('Expected app writer file is missing.');
        }
      }
      final pending = _outbox(current);
      if (pending.isNotEmpty) {
        _validatePreparedPrefix(current, previous, pending.single);
      }
      final publications = <void Function()>[];
      profile.transaction(() {
        for (final stage in _projections.values) {
          publications.add(stage(previous));
        }
      });
      _fileInfos = Map.of(byName);
      _seekableFiles = seekable;
      _viewHasPending = pending.isNotEmpty;
      for (final publish in publications) {
        publish();
      }
      return previous;
    }
    final migrationEnds = <String, int>{};
    final observed = <String, Uint8List>{},
        all = <UnifiedRecord>[],
        admitted = <UnifiedEffect>[],
        published = <String, int>{},
        heads = <List<Object?>>[];
    final semantic = <String, UnifiedEffect>{};
    final ownerRecords = <String, List<UnifiedRecord>>{};
    final parsedOffsets = <String, Map<int, ({int start, int length})>>{};
    var incomplete = false, total = 0;
    var reusedHistoricalCoverage =
        previous != null && current.digest == manifest.digest;
    void includeRecord(UnifiedRecord r) {
      all.add(r);
      for (final e in r.effects) {
        if (e.isData) {
          final existing = semantic[e.key];
          if (existing != null && existing.raw != e.raw) {
            throw FormatFailure('Conflicting semantic effect identity.');
          }
          if (existing == null) {
            semantic[e.key] = e;
            admitted.add(e);
          }
        } else {
          admitted.add(e);
        }
      }
    }

    final frames = _FrameBudget();
    final owners = ownerSet.toList()..sort();
    for (final owner in owners) {
      final name = unifiedLogName(owner);
      final exists = byName.containsKey(name);
      final protected = profile.database.select(
        'SELECT * FROM protected_app_heads WHERE space=? AND epoch=? AND writer=?',
        [current.space, current.epoch, owner],
      );
      final protectedSequence = protected.isEmpty
          ? null
          : protected.single['sequence'] as int;
      int? protectedEnd = protectedSequence == 0 ? 0 : null;
      final missingNewSelf =
          ((owner == writer && !current.owners.containsKey(owner)) ||
              current.owners[owner]?['count'] == 0) &&
          (protected.isEmpty ||
              protected.single['sequence'] == 0 &&
                  protected.single['bytes'] == 0);
      if (!exists && !missingNewSelf) {
        throw FormatFailure('Expected app writer file is missing: $name');
      }
      final bytes = physicalNow[owner]!;
      total += bytes.length;
      if (total > maximumTotalBytes) {
        throw FormatFailure('App history exceeds safe limits.');
      }
      observed[owner] = bytes;
      // This owner's records are appended contiguously from here, in chain order.
      final ownerStart = all.length;

      var start = 0,
          sequence = 0,
          head = unifiedGenesis(current.space, current.epoch, owner);
      EventClock? clock;
      var semanticSequence = 0;
      var completeSequence = 0;
      var migrationEnd = 0;
      final historicalCount = current.owners[owner]?['count'] as int? ?? 0;
      final prefix = stored?[owner];
      final oldBytes = prefix?.bytes ?? previous?.physical[owner];
      final oldRecords =
          prefix?.records ??
          previous?.recordsByWriter[owner] ??
          const <UnifiedRecord>[];
      final oldEnd =
          prefix?.end ??
          (oldBytes == null
              ? 0
              : (_completeEnds[owner] ?? oldBytes.lastIndexOf(10) + 1));
      final reusePrefix =
          prefix != null ||
          !forceFullAudit &&
              previous != null &&
              current.digest == manifest.digest &&
              oldBytes != null &&
              bytes.length >= oldEnd &&
              (retainedPrefixes.contains(owner) ||
                  _samePrefix(bytes, oldBytes, oldEnd));
      // An exact fresh byte match and unchanged protected tuple reuse the
      // existing proof; every new complete suffix is still parsed and checked.
      // A store prefix equals the protected head by its fast check.
      final reuseTrustedPrefix =
          reusePrefix &&
          (prefix != null || sameAcceptedHeads) &&
          protected.isNotEmpty &&
          (protected.single['bytes'] as int) <= oldEnd;
      if (protected.isNotEmpty) {
        final old = protected.single, length = old['bytes'] as int;
        if (bytes.length < length ||
            !reuseTrustedPrefix &&
                !_validCommitment(
                  old['digest'] as String,
                  old['hash'] as String,
                  bytes,
                  length,
                )) {
          throw FormatFailure(
            'Previously observed app history changed or was truncated.',
          );
        }
      }
      if (reusePrefix) {
        for (final record in oldRecords) {
          includeRecord(record);
          for (final e in record.effects.where(
            (e) => e.isData && e.writer == owner,
          )) {
            if (e.sequence > semanticSequence) semanticSequence = e.sequence;
          }
        }
        if (oldRecords.isNotEmpty) {
          sequence = oldRecords.last.sequence;
          head = oldRecords.last.hash;
          clock = oldRecords.last.clock;
          completeSequence = sequence;
        }
        start = oldEnd;
        if (protectedSequence == sequence) {
          protectedEnd = oldEnd;
        } else if (protectedSequence != null && protectedSequence > 0) {
          var lines = 0;
          for (var i = 0; i < oldEnd; i++) {
            if (bytes[i] == 10 && ++lines == protectedSequence) {
              protectedEnd = i + 1;
              break;
            }
          }
        }
        if (historicalCount > 0) {
          final cachedEnd = prefix?.migrationEnd ?? _migrationEnds[owner];
          if (cachedEnd != null) {
            migrationEnd = cachedEnd;
          } else {
            var lines = 0;
            for (var i = 0; i < oldEnd; i++) {
              if (bytes[i] == 10 && ++lines == historicalCount) {
                migrationEnd = i + 1;
                break;
              }
            }
          }
        }
      } else if (historicalCount > 0) {
        reusedHistoricalCoverage = false;
      }
      for (var i = start; i < bytes.length; i++) {
        if (bytes[i] != 10) {
          if (i - start >= maximumUnifiedRecordBytes) {
            throw HistoryVerificationFailure(
              name,
              sequence + 1,
              start,
              'Oversized app record.',
            );
          }
          continue;
        }
        final recordNumber = sequence + 1;
        try {
          final raw = utf8.decode(Uint8List.sublistView(bytes, start, i));
          final r = _decodeRecord(raw, force: forceFullAudit);
          for (final e in r.effects) {
            final task = e.task;
            if (task != null) {
              assertWorkspaceTaskTimeZonePolicy(task, current.timeZonePolicy);
            }
          }
          if (r.space != current.space ||
              r.epoch != current.epoch ||
              r.writer != owner ||
              r.sequence != sequence + 1 ||
              r.previousHash != head ||
              clock != null && r.firstClock <= clock) {
            throw FormatFailure(
              'App writer sequence, identity, clock or chain differs.',
            );
          }
          if (!current.owners.containsKey(owner) &&
              r.sequence == 1 &&
              (r.effects.length != 1 || r.effect.kind != 'writer.joined')) {
            throw FormatFailure(
              'New installation history must begin with its own header.',
            );
          }
          if (r.effects.any((e) => e.kind == 'writer.joined') &&
              (r.sequence != 1 || current.owners.containsKey(owner))) {
            throw FormatFailure('Installation header is misplaced.');
          }
          if (r.sequence <= historicalCount) {
            if (!r.historical ||
                r.effects.length != 1 ||
                current.authorOfReference(r.effect.writer) != owner) {
              throw FormatFailure(
                'App migration prefix is not original owner history.',
              );
            }
          } else if (r.historical) {
            throw FormatFailure(
              'Unexpected late legacy event in the active writer chain.',
            );
          }
          includeRecord(r);
          (parsedOffsets[owner] ??= {})[r.sequence] = (
            start: start,
            length: i - start,
          );
          sequence = r.sequence;
          head = r.hash;
          clock = r.clock;
          if (r.sequence == historicalCount) {
            migrationEnd = i + 1;
            if (head != current.owners[owner]!['head']) {
              throw FormatFailure('Migration prefix head differs.');
            }
          }
          for (final e in r.effects) {
            if (e.isData && e.writer == owner) {
              if (!e.historical && e.sequence <= semanticSequence) {
                throw FormatFailure(
                  'Logical effect sequence was reused or reordered.',
                );
              }
              if (e.sequence > semanticSequence) semanticSequence = e.sequence;
            }
          }
          completeSequence = sequence;
          start = i + 1;
          if (sequence == protectedSequence) protectedEnd = start;
        } on FormatFailure catch (failure) {
          throw HistoryVerificationFailure(
            name,
            recordNumber,
            start,
            failure.message,
          );
        } on FormatException {
          throw HistoryVerificationFailure(
            name,
            recordNumber,
            start,
            'App record is not valid UTF-8.',
          );
        }
        // Complete input snapshots are already frozen and publication has not
        // begun. Let loading/refresh frames run between bounded decode slices;
        // the profile queue still excludes competing commands.
        if (frames.due) await frames.pause();
      }
      if (current.owners.containsKey(owner) &&
          (sequence < historicalCount ||
              !reuseTrustedPrefix &&
                  bytesDigest(Uint8List.sublistView(bytes, 0, migrationEnd)) !=
                      current.owners[owner]!['digest'])) {
        throw FormatFailure('Incomplete or changed migration prefix.');
      }
      if (protected.isNotEmpty) {
        final old = protected.single,
            oldSeq = old['sequence'] as int,
            oldBytes = old['bytes'] as int;
        // Positional lookup in this owner's gap-free chain; the generic scan
        // remains only if that invariant is ever violated.
        final at = ownerStart + oldSeq - 1;
        final matches =
            oldSeq >= 1 &&
                at < all.length &&
                all[at].writer == owner &&
                all[at].sequence == oldSeq
            ? [all[at]]
            : all.where((r) => r.writer == owner && r.sequence == oldSeq);
        if (oldBytes < 0 ||
            oldSeq < 0 ||
            (old['published'] as int) < 0 ||
            (old['published'] as int) > oldSeq ||
            protectedEnd != oldBytes ||
            (oldSeq == 0
                ? old['hash'] !=
                      unifiedGenesis(current.space, current.epoch, owner)
                : matches.length != 1 || matches.single.hash != old['hash'])) {
          throw FormatFailure('Trusted app prefix identity or head differs.');
        }
      }
      if (start < bytes.length) incomplete = true;
      published[owner] = completeSequence;
      migrationEnds[owner] = migrationEnd;
      heads.add([
        current.space,
        current.epoch,
        owner,
        sequence,
        head,
        start,
        _chainCommitment(head),
        completeSequence,
      ]);
      ownerRecords[owner] = all.sublist(ownerStart);
    }
    if (!reusedHistoricalCoverage) {
      _validateReferenceCoverage(all, current);
    }
    // Validate all physical evidence before deciding visibility. A blocked action
    // cannot conceal a malformed event or relax the app-wide format fence.
    var taskReady = <String>{};
    String? allTaskRevision;
    final allAdmission = await _validateEffectsBetweenFrames(
      admitted,
      current,
      frames,
      onTaskReady: (ids) => taskReady = ids,
      onTaskValidated: (key) => allTaskRevision = key,
    );
    // Last frame before publication; the commit below and the projection
    // publications after it run without a break.
    if (frames.due) await frames.pause();
    final publication = _publishActions(
      all,
      published,
      current,
      admitted,
      allAdmission,
      taskReady,
      allTaskRevision!,
    );
    final visible = publication.$1;
    final foodAdmission = publication.$2;
    final pendingEffects = all.any(
      (r) => r.sequence > (published[r.writer] ?? 0),
    );
    for (final row in heads) {
      row[7] = published[row[2] as String] ?? 0;
    }
    final revision = bytesDigest(
      utf8.encode(
        canonicalDataJson({
          'manifest': current.digest,
          'heads': heads.map((h) => [h[2], h[3], h[4], h[6], h[7]]).toList(),
        }),
      ),
    );
    final result = UnifiedSnapshot(
      revision,
      List.unmodifiable(all),
      List.unmodifiable(visible),
      Map.unmodifiable(observed),
      Map.unmodifiable(published),
      incomplete,
      foodAdmission,
      pendingEffects,
      readyTaskIds: Set.unmodifiable(publication.$3),
    );
    _verifiedTaskRevisions[result] = publication.$4;
    final pending = _outbox(current);
    if (pending.isNotEmpty) {
      _validatePreparedPrefix(current, result, pending.single);
    }
    if (!observe) return result;
    final publications = <void Function()>[];
    var pendingAfterCommit = false;
    final retirePending =
        pending.isNotEmpty && _preparedComplete(result, pending.single);
    profile.transaction(() {
      profile.database.execute(
        'INSERT OR IGNORE INTO profile_metadata VALUES (?,?)',
        [_locationKey, locationBinding],
      );
      profile.database.execute(
        'INSERT INTO protected_app_workspaces VALUES (?,?,?,?) ON CONFLICT(space) DO UPDATE SET observed=excluded.observed',
        [current.space, current.epoch, rawManifest, canonicalDataJson(owners)],
      );
      for (final row in heads) {
        profile.database.execute(
          'INSERT OR REPLACE INTO protected_app_heads VALUES (?,?,?,?,?,?,?,?)',
          row,
        );
      }
      _syncStore(current, heads, ownerRecords, parsedOffsets, observed);
      for (final stage in _projections.values) {
        publications.add(stage(result));
      }
      pendingAfterCommit = !retirePending && _outbox(current).isNotEmpty;
    });
    if (retirePending) {
      _pending = null;
      _pendingBaseProof = null;
      _preparedAction = null;
      _pendingProvenance = null;
    }
    manifest = current;
    _snapshot = result;
    _fileInfos = Map.of(byName);
    _seekableFiles = seekable;
    _completeEnds = {for (final row in heads) row[2] as String: row[5] as int};
    _migrationEnds = migrationEnds;
    _acceptedHeads = _protectedHeads(current);
    _viewHasPending = pendingAfterCommit;
    for (final publish in publications) {
      publish();
    }
    return result;
  }

  String _protectedHeads(UnifiedManifest m) => canonicalDataJson(
    profile.database
        .select(
          'SELECT writer,sequence,hash,bytes,digest,published FROM protected_app_heads WHERE space=? AND epoch=? ORDER BY writer',
          [m.space, m.epoch],
        )
        .map((r) => r.values.toList())
        .toList(),
  );

  static bool _samePrefix(Uint8List a, Uint8List b, int length) {
    if (a.length < length || b.length < length) return false;
    if (identical(a, b)) return true;
    for (var i = 0; i < length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Publish complete writer prefixes to a fixed point. A missing typed
  /// dependency holds the entire action and actions observing its frontier.
  (List<UnifiedEffect>, FoodAdmission, Set<String>, String) _publishActions(
    List<UnifiedRecord> actions,
    Map<String, int> published,
    UnifiedManifest m,
    List<UnifiedEffect> admitted,
    FoodAdmission allAdmission,
    Set<String> taskReady,
    String taskRevision,
  ) {
    // Every complete record has this manifest's epoch and a gap-free writer
    // chain from sequence 1 (checked while decoding), so `app:epoch:w:s`
    // identity is a positional lookup. Do not format and hash an ID string for
    // every historical record on each peer delivery.
    final physical = <String, List<UnifiedRecord>>{};
    for (final r in actions) {
      (physical[r.writer] ??= []).add(r);
    }
    UnifiedRecord? physicalAt(String writer, int sequence) {
      final chain = physical[writer];
      if (chain == null || sequence < 1 || sequence > chain.length) return null;
      final r = chain[sequence - 1];
      return r.sequence == sequence && r.epoch == m.epoch
          ? r
          : chain
                .where((r) => r.sequence == sequence && r.epoch == m.epoch)
                .firstOrNull;
    }

    for (final action in actions) {
      for (final entry in action.observed.entries) {
        final f = entry.value;
        if (f.sequence == 0) {
          if (f.hash != unifiedGenesis(m.space, m.epoch, entry.key)) {
            throw FormatFailure('App action observes a different genesis.');
          }
        } else {
          final target = physicalAt(entry.key, f.sequence);
          if (target != null &&
              (target.hash != f.hash || target.clock >= action.firstClock)) {
            throw FormatFailure('App action observes an invalid frontier.');
          }
        }
      }
    }
    final complete = Map<String, int>.from(published);
    for (final owner in complete.keys) {
      final prior = profile.database.select(
        'SELECT published FROM protected_app_heads WHERE space=? AND epoch=? AND writer=?',
        [m.space, m.epoch, owner],
      );
      final trusted = prior.isEmpty
          ? (m.owners[owner]?['count'] as int? ?? 0)
          : prior.single['published'] as int;
      if (trusted < (m.owners[owner]?['count'] as int? ?? 0) ||
          trusted > (complete[owner] ?? 0) ||
          trusted > 0 && physicalAt(owner, trusted) == null) {
        throw FormatFailure(
          'Trusted app publication frontier differs from physical history.',
        );
      }
      published[owner] = trusted;
    }
    bool ready(UnifiedEffect e, FoodAdmission food, Set<String> tasks) =>
        (e.task == null || tasks.contains(e.task!.id)) &&
        (e.food == null || food.readyIds.contains(e.food!.id));
    // Complete delivery needs one semantic pass, rather than replay per action.
    if (actions.every(
      (a) =>
          a.observed.entries.every(
            (e) => e.value.sequence <= (complete[e.key] ?? 0),
          ) &&
          a.effects.every((e) => ready(e, allAdmission, taskReady)),
    )) {
      published.addAll(complete);
      return (admitted, allAdmission, taskReady, taskRevision);
    }
    final visible = <UnifiedEffect>[], seen = <String>{};
    for (final action in actions) {
      if (action.sequence > (published[action.writer] ?? 0)) {
        continue;
      }
      for (final e in action.effects) {
        if (!e.isData || seen.add(e.key)) {
          visible.add(e);
        }
      }
    }
    var visibleReady = <String>{};
    String? visibleRevision;
    var admission = _validateEffects(
      visible,
      m,
      onTaskReady: (ids) => visibleReady = ids,
      onTaskValidated: (key) => visibleRevision = key,
    );
    while (true) {
      var changed = false;
      for (final action in actions) {
        if (action.historical ||
            action.sequence != (published[action.writer] ?? 0) + 1 ||
            !action.observed.entries.every(
              (e) => e.value.sequence <= (published[e.key] ?? 0),
            )) {
          continue;
        }
        final candidate = [...visible, ...action.effects];
        var readyTasks = <String>{};
        String? candidateRevision;
        final checked = _validateEffects(
          candidate,
          m,
          onTaskReady: (ids) => readyTasks = ids,
          onTaskValidated: (key) => candidateRevision = key,
        );
        if (!action.effects.every((e) => ready(e, checked, readyTasks))) {
          continue;
        }
        published[action.writer] = action.sequence;
        visible.addAll(action.effects);
        admission = checked;
        visibleReady = readyTasks;
        visibleRevision = candidateRevision;
        changed = true;
      }
      if (!changed) {
        return (visible, admission, visibleReady, visibleRevision!);
      }
    }
  }

  void _validateReferenceCoverage(
    List<UnifiedRecord> records,
    UnifiedManifest m,
  ) {
    final streams = <String, List<UnifiedEffect>>{};
    for (final r in records.where((r) => r.historical)) {
      streams
          .putIfAbsent(
            '${r.effect.task == null ? 'food' : 'task'}:${r.effect.writer}',
            () => [],
          )
          .add(r.effect);
    }
    for (final stream in streams.values) {
      stream.sort((a, b) => a.sequence.compareTo(b.sequence));
      var sequence = 0, head = eventGenesisHash(m.space, stream.first.writer);
      EventClock? clock;
      for (final effect in stream) {
        if (effect.sequence != ++sequence ||
            effect.previousHash != head ||
            clock != null && effect.clock <= clock ||
            effect.author != m.authorOfReference(effect.writer)) {
          throw FormatFailure(
            'Normalized reference continuity or attribution differs.',
          );
        }
        head = effect.semanticHash;
        clock = effect.clock;
      }
    }
  }

  (FoodAdmission, Set<String>, String)? _validateLocalAppend(
    UnifiedSnapshot base,
    List<UnifiedEffect> effects,
  ) {
    final key = _verifiedTaskRevisions[base];
    if (key == null || !base.allVisibleTasksReady) return null;
    final food = effects.map((e) => e.food).whereType<FoodRecord>().toList();
    if (food.isNotEmpty) {
      if (effects.any((e) => e.task != null)) return null;
      final admission = appendReadyFoodRecords(
        base.foodAdmission,
        food,
        legacyOwners: manifest.referenceAuthors,
      );
      return admission == null ? null : (admission, base.readyTaskIds, key);
    }
    final tasks = effects.map((e) => e.task).whereType<LogEvent>().toList();
    if (tasks.isEmpty) return (base.foodAdmission, base.readyTaskIds, key);
    final nextKey =
        'task-append1:${bytesDigest(utf8.encode(canonicalDataJson([
          key,
          for (final e in tasks) [e.id, e.hash, e.integrityHash],
        ])))}';
    final ready = _semanticValidator?.validateAppend(
      tasks,
      expectedBaseKey: key,
      inputKey: nextKey,
    );
    if (ready == null) return null;
    semanticValidationRuns++;
    return (base.foodAdmission, ready, nextKey);
  }

  int fullEffectValidationRuns = 0;
  int semanticTaskSortRuns = 0;
  int monotonicTaskValidationRuns = 0;

  FoodAdmission _validateEffects(
    Iterable<UnifiedEffect> effects,
    UnifiedManifest m, {
    void Function(Set<String>)? onTaskReady,
    void Function(String)? onTaskValidated,
  }) => profile.observeSynchronous('history.semanticValidation', () {
    final validation = _effectValidation(
      effects,
      m,
      onTaskReady: onTaskReady,
      onTaskValidated: onTaskValidated,
    );
    for (final stage in validation.stages) {
      stage();
    }
    return validation.result();
  });

  /// [_validateEffects] for a refresh: the same stages in the same order, but
  /// a frame may run between them. Only the caller's frozen inputs and this
  /// history's validation state are touched, and the profile queue keeps every
  /// other command out until the refresh ends.
  Future<FoodAdmission> _validateEffectsBetweenFrames(
    Iterable<UnifiedEffect> effects,
    UnifiedManifest m,
    _FrameBudget frames, {
    void Function(Set<String>)? onTaskReady,
    void Function(String)? onTaskValidated,
  }) => profile.observeAsynchronous('history.semanticValidation', () async {
    final validation = _effectValidation(
      effects,
      m,
      onTaskReady: onTaskReady,
      onTaskValidated: onTaskValidated,
    );
    for (final stage in validation.stages) {
      if (frames.due) await frames.pause();
      stage();
    }
    return validation.result();
  });

  /// Semantic validation as ordered stages (Task identity, Task validation,
  /// Food admission). Every stage must run, in order, before [result].
  ({List<void Function()> stages, FoodAdmission Function() result})
  _effectValidation(
    Iterable<UnifiedEffect> effects,
    UnifiedManifest m, {
    void Function(Set<String>)? onTaskReady,
    void Function(String)? onTaskValidated,
  }) {
    fullEffectValidationRuns++;
    final tasks = <LogEvent>[], food = <String, FoodRecord>{};
    final foodRaw = <String, String>{};
    final foodEffects = <String, UnifiedEffect>{};
    for (final effect in effects.where((e) => e.isData)) {
      final e = effect.task;
      if (e != null) {
        tasks.add(e);
      } else {
        final r = effect.food!, previous = food[r.id];
        if (previous != null && foodRaw[r.id] != effect.raw) {
          throw FormatFailure('Conflicting Food operation identity.');
        }
        food[r.id] = r;
        foodRaw[r.id] = effect.raw;
        foodEffects[r.id] = effect;
      }
    }
    final semanticTasks = tasks;
    // A physical peer/header/Food change must not rename unchanged Task
    // evidence after an owned append used an incremental process key. Reuse
    // only this authority's already-ready exact canonical set in this manifest.
    final prior = _snapshot;
    final priorKey =
        prior != null &&
            prior.allVisibleTasksReady &&
            m.digest == manifest.digest
        ? _verifiedTaskRevisions[prior]
        : null;
    final priorTasks = priorKey == null
        ? const <String, String>{}
        : {for (final event in prior!.tasks) event.id: event.canonicalRaw!};
    final priorCount = priorTasks.length;
    final sameTasks =
        priorKey != null &&
        priorTasks.length == semanticTasks.length &&
        semanticTasks.every(
          (event) =>
              event.canonicalRaw != null &&
              priorTasks.remove(event.id) == event.canonicalRaw,
        );
    // Exact unchanged-set proof is order-independent. Do not regroup and sort
    // all Task history for an unrelated peer Food/header change.
    String? taskKey = sameTasks ? priorKey : null;
    Set<String>? taskReady = sameTasks ? prior!.readyTaskIds : null;
    // A delivered peer action usually only extends the exact ready set. Like an
    // owned append, its process key chains the prior key with the new events,
    // and the owning validator admits only that delta with the generic checks.
    // Whole-history sort and digest remain for every other changed input.
    if (!sameTasks && priorKey != null && semanticTasks.length > priorCount) {
      final added = <LogEvent>[];
      var retained = 0;
      for (final event in semanticTasks) {
        final raw = priorTasks[event.id];
        if (raw == null) {
          added.add(event);
        } else if (raw == event.canonicalRaw) {
          retained++;
        } else {
          retained = -1;
          break;
        }
      }
      if (retained == priorCount) {
        added.sort(compareEvents);
        final extensionKey =
            'task-append1:${bytesDigest(utf8.encode(canonicalDataJson([
              priorKey,
              for (final e in added) [e.id, e.hash, e.integrityHash],
            ])))}';
        taskReady = _taskValidation.remove(extensionKey);
        if (taskReady == null) {
          taskReady = _semanticValidator?.validateMonotonicDelta(
            added,
            expectedBaseKey: priorKey,
            inputKey: extensionKey,
            orderedEvents: () {
              semanticTaskSortRuns++;
              return semanticTasks..sort(compareEvents);
            },
          );
          if (taskReady != null) {
            semanticValidationRuns++;
            monotonicTaskValidationRuns++;
          }
        }
        if (taskReady != null) taskKey = extensionKey;
      }
    }
    void identifyTasks() {
      if (taskKey != null) return;
      semanticTaskSortRuns++;
      semanticTasks.sort(compareEvents);
      final revision = TaskStore.canonicalTaskRevision(semanticTasks);
      taskKey = revision;
      taskReady = _taskValidation.remove(revision);
    }

    void validateTasks() {
      final key = taskKey!;
      var ready = taskReady;
      if (ready == null) {
        semanticValidationRuns++;
        final validator = _semanticValidator ??= TaskSemanticValidator(
          owningHistory: this,
          space: m.space,
          writer: writer,
          textEngine: textEngine,
          profile: profile,
          locationKey: bytesDigest(
            utf8.encode('${folder.location}#app5:${m.epoch}'),
          ),
          manifestDigest: m.digest,
        );
        ready = validator.validate(semanticTasks, inputKey: key);
      }
      _taskValidation[key] = ready;
      if (_taskValidation.length > 4) {
        _taskValidation.remove(_taskValidation.keys.first);
      }
      onTaskReady?.call(ready);
      onTaskValidated?.call(key);
    }

    FoodAdmission admitFood() {
      // Peer delivery can extend a fully admitted Food input just like an owned
      // append. Prove every prior ID has the exact same canonical bytes first;
      // removals, replacements, older clocks and pending dependencies fall back.
      // A manifest/owner change cannot borrow the prior admission index.
      if (priorKey != null) {
        final priorFood = <String, String>{
          for (final effect in prior!.effects)
            if (effect.food != null) effect.food!.id: effect.raw,
        };
        if (priorFood.length <= foodRaw.length &&
            priorFood.entries.every(
              (entry) => foodRaw[entry.key] == entry.value,
            )) {
          final appended = appendReadyFoodRecords(prior.foodAdmission, [
            for (final entry in food.entries)
              if (!priorFood.containsKey(entry.key)) entry.value,
          ], legacyOwners: m.referenceAuthors);
          if (appended != null) {
            incrementalFoodAdmissionRuns++;
            return appended;
          }
        }
      }
      final foodIds = foodRaw.keys.toList()..sort();
      final foodKey = bytesDigest(
        utf8.encode(
          canonicalDataJson([
            m.digest,
            ...foodIds.map((id) => foodEffects[id]!.validationDigest),
          ]),
        ),
      );
      var foodResult = _foodValidation.remove(foodKey);
      if (foodResult == null) {
        fullFoodAdmissionRuns++;
        foodResult = admitFoodRecords(
          food.values.toList(),
          legacyOwners: m.referenceAuthors,
        );
      }
      _foodValidation[foodKey] = foodResult;
      if (_foodValidation.length > 4) {
        _foodValidation.remove(_foodValidation.keys.first);
      }
      return foodResult;
    }

    late final FoodAdmission admitted;
    return (
      stages: [identifyTasks, validateTasks, () => admitted = admitFood()],
      result: () => admitted,
    );
  }

  // Same-session only. Closing/crashing discards unacknowledged intent;
  // no private bytes can trigger a write after restart.
  List<Map<String, Object?>> _outbox(UnifiedManifest m) =>
      _pending == null ? const [] : [_pending!];
  Map<String, dynamic>? get pendingProvenance => _pendingProvenance;

  bool get hasPending => _outbox(manifest).isNotEmpty;

  /// Projection staging describes the state AFTER its SQL admission commits.
  /// Until then, the same-session bytes remain available if any stage aborts.
  bool hasPendingAfter(UnifiedSnapshot candidate) =>
      _pending != null && !_preparedComplete(candidate, _pending!);

  List<UnifiedRecord> get pendingRecords {
    final pending = _outbox(manifest);
    return pending.isEmpty
        ? const []
        : List.unmodifiable(_validateReservedRecords(manifest, pending.single));
  }

  void _validatePreparedPrefix(
    UnifiedManifest m,
    UnifiedSnapshot s,
    Map<String, Object?> p,
  ) {
    _validatePreparedBytes(m, s, s.physical[writer]!, p);
  }

  void _validatePreparedBytes(
    UnifiedManifest m,
    UnifiedSnapshot s,
    Uint8List bytes,
    Map<String, Object?> p,
  ) {
    final reserved = _validateReservedRecords(m, p);
    final base = p['base_bytes'] as int, expected = p['raw'] as List<int>;
    final seq = p['base_sequence'] as int;
    final proof = _pendingBaseProof;
    final knownBase =
        proof != null &&
        identical(proof.pending, p) &&
        proof.manifest == m.digest &&
        proof.sequence == seq &&
        proof.bytes.length == base &&
        proof.head == p['base_hash'] &&
        proof.digest == p['base_digest'];
    final prefix = s.records.where(
      (r) => r.writer == writer && r.sequence == seq,
    );
    if (base < 0 ||
        seq < 0 ||
        (seq == 0
            ? base != 0 ||
                  p['base_hash'] != unifiedGenesis(m.space, m.epoch, writer)
            : prefix.length != 1 ||
                  prefix.single.hash != p['base_hash'] ||
                  reserved.first.clock <= prefix.single.clock) ||
        bytes.length < base ||
        (knownBase
            ? (seq > 0 && prefix.single.clock.value != proof.clock?.value) ||
                  !_samePrefix(bytes, proof.bytes, base)
            : (base > 0 &&
                      (bytes[base - 1] != 10 ||
                          bytes.take(base).where((b) => b == 10).length !=
                              seq)) ||
                  !_validCommitment(
                    p['base_digest'] as String,
                    p['base_hash'] as String,
                    bytes,
                    base,
                  ) ||
                  (p['base_digest'] as String).startsWith('chain1:') &&
                      !_canonicalPrefixMatches(
                        m,
                        writer,
                        bytes,
                        base,
                        seq,
                        p['base_hash'] as String,
                      )) ||
        bytes.length > base + expected.length) {
      throw FormatFailure(
        'Owned app history differs from its exact reservation.',
      );
    }
    for (var i = base; i < bytes.length; i++) {
      if (bytes[i] != expected[i - base]) {
        throw FormatFailure(
          'Owned app append differs from immutable recovery bytes.',
        );
      }
    }
  }

  List<UnifiedRecord> _validateReservedRecords(
    UnifiedManifest m,
    Map<String, Object?> p,
  ) {
    final bytes = p['raw'] as List<int>;
    if (bytes.isEmpty || bytes.last != 10) {
      throw FormatFailure('Invalid in-memory action bytes.');
    }
    final r = UnifiedRecord.decode(
      utf8.decode(bytes.sublist(0, bytes.length - 1)),
    );
    if (r.space != m.space ||
        r.epoch != m.epoch ||
        r.writer != writer ||
        r.sequence != (p['base_sequence'] as int) + 1 ||
        r.previousHash != p['base_hash'] ||
        r.historical) {
      throw FormatFailure('In-memory action identity differs.');
    }
    return [r];
  }

  bool _preparedComplete(UnifiedSnapshot s, Map<String, Object?> p) =>
      (s.published[writer] ?? 0) >=
          (p['base_sequence'] as int) +
              (p['raw'] as List<int>).where((b) => b == 10).length &&
      s.physical[writer]!.length ==
          (p['base_bytes'] as int) + (p['raw'] as List<int>).length;

  int get physicalSequence =>
      snapshot.recordsByWriter[writer]?.last.sequence ?? 0;
  int get logicalSequence => snapshot.logicalSequences[writer] ?? 0;
  String get commonHead =>
      snapshot.recordsByWriter[writer]?.last.hash ??
      unifiedGenesis(manifest.space, manifest.epoch, writer);
  EventClock? get maximumClock => snapshot.maximumClock;
  Map<String, UnifiedFrontier> get _observedFrontier => {
    for (final e in snapshot.published.entries)
      e.key: UnifiedFrontier(
        e.value,
        e.value == 0
            ? unifiedGenesis(manifest.space, manifest.epoch, e.key)
            : snapshot.recordsByWriter[e.key]![e.value - 1].hash,
      ),
  };

  /// Reserve final canonical bytes before native receipts/onPrepared callbacks.
  Future<UnifiedReservation> prepareInProfileQueue(
    List<UnifiedEffectBuilder> builders, {
    String? expectedRevision,
    void Function(List<UnifiedRecord>)? onReserved,
    Map<String, dynamic>? provenance,
  }) => _prepareInProfileQueue(
    builders,
    expectedRevision: expectedRevision,
    onReserved: onReserved,
    provenance: provenance,
    reserve: true,
  );

  /// Refresh and clean the owned tail before synchronously building this action.
  /// The caller owns the profile queue; no reusable freshness authority escapes.
  Future<UnifiedReservation> prepareFromFreshInputsInProfileQueue(
    List<UnifiedEffectBuilder> Function() build, {
    void Function(List<UnifiedRecord>)? onReserved,
    Map<String, dynamic>? provenance,
  }) => _prepareInProfileQueue(
    const [],
    buildFreshInputs: build,
    onReserved: onReserved,
    provenance: provenance,
    reserve: true,
  );

  /// Read-only semantic validation using the same fresh observation boundary.
  Future<UnifiedReservation> validateFromFreshInputsInProfileQueue(
    List<UnifiedEffectBuilder> Function() build,
  ) =>
      _prepareInProfileQueue(const [], buildFreshInputs: build, reserve: false);

  Future<UnifiedReservation> validateInProfileQueue(
    List<UnifiedEffectBuilder> builders,
  ) => _prepareInProfileQueue(builders, reserve: false);

  Future<UnifiedReservation> _prepareInProfileQueue(
    List<UnifiedEffectBuilder> builders, {
    String? expectedRevision,
    void Function(List<UnifiedRecord>)? onReserved,
    Map<String, dynamic>? provenance,
    required bool reserve,
    List<UnifiedEffectBuilder> Function()? buildFreshInputs,
  }) async {
    await refreshInProfileQueue();
    if (reserve && !hasPending) await _discardOwnedTail();
    if (snapshot.pendingEffects || hasPending) {
      throw FormatFailure(
        'App history has an incomplete command; preserve drafts and recover.',
      );
    }
    if (buildFreshInputs != null) {
      final observed = snapshot;
      final observedManifest = manifest;
      final observedDigest = manifest.digest;
      final observedHeads = _acceptedHeads;
      void requireUnchangedContext() {
        profile.database; // Also refuses a closed or poisoned local profile.
        if (_closed ||
            _closing != null ||
            safetyFailure != null ||
            !identical(snapshot, observed) ||
            snapshot.revision != observed.revision ||
            !identical(manifest, observedManifest) ||
            manifest.digest != observedDigest ||
            _acceptedHeads != observedHeads ||
            observedHeads != _protectedHeads(manifest) ||
            LocalSettings.protectedValues(profile)['writer'] != writer ||
            snapshot.pendingEffects ||
            hasPending) {
          throw FormatFailure(
            'App history changed while preparing this command.',
          );
        }
      }

      requireUnchangedContext();
      builders =
          buildFreshInputs(); // Concrete List return: never await a caller.
      requireUnchangedContext();
    }
    if (expectedRevision != null && expectedRevision != snapshot.revision) {
      throw FormatFailure('App history changed while preparing this command.');
    }
    if (builders.isEmpty || builders.length > 10000) {
      throw FormatFailure('Choose a bounded nonempty app command.');
    }
    final base = snapshot.physical[writer]!;
    final currentTotal = snapshot.physical.values.fold<int>(
      0,
      (n, b) => n + b.length,
    );
    final effects = <UnifiedEffect>[];
    var effectBytes = 0;
    var semanticSequence = logicalSequence;
    var semanticHead = commonHead;
    EventClock? clock = maximumClock;
    for (final build in builders) {
      clock = EventClock.next(
        BigInt.from(now().microsecondsSinceEpoch) * BigInt.from(1000),
        clock,
      );
      final e = build(++semanticSequence, clock, semanticHead);
      if (e.historical) {
        throw FormatFailure('Historical effects require offline conversion.');
      }
      if (e.task != null) {
        if (reserve &&
            isTaskCompletion(e.task!.type) &&
            !{3, 4}.contains(e.task!.operationRevision)) {
          throw FormatFailure(
            'New completions require an exact completion instant.',
          );
        }
        assertWorkspaceTaskTimeZonePolicy(e.task!, timeZonePolicy);
      }
      effectBytes += utf8.encode(canonicalDataJson(e.toJson())).length;
      if (effectBytes > maximumUnifiedRecordBytes) {
        throw FormatFailure(
          'Action exceeds safe record size; nothing was written.',
        );
      }
      effects.add(e);
      if (e.isData) semanticHead = e.integrityHash;
    }
    final record = UnifiedRecord(
      space: manifest.space,
      epoch: manifest.epoch,
      writer: writer,
      sequence: physicalSequence + 1,
      clock: clock!,
      previousHash: commonHead,
      effects: effects,
      observed: _observedFrontier,
      provenance: provenance,
    );
    final records = [record];
    final bytes = Uint8List.fromList(
      utf8.encode('${record.encode()}\n'),
    ).asUnmodifiableView();
    if (base.length + bytes.length > maximumFileBytes ||
        currentTotal + bytes.length > maximumTotalBytes) {
      throw FormatFailure(
        'Action exceeds safe byte budgets; nothing was written.',
      );
    }
    if (!manifest.owners.containsKey(writer) &&
        physicalSequence == 0 &&
        (records.length != 1 ||
            records.single.effect.kind != 'writer.joined')) {
      throw FormatFailure(
        'Complete this installation header before other commands.',
      );
    }
    var taskReady = <String>{};
    String? taskRevision;
    final candidateEffects = List<UnifiedEffect>.unmodifiable([
      ...snapshot.effects,
      ...effects,
    ]);
    final appended = _validateLocalAppend(snapshot, effects);
    final FoodAdmission admission;
    if (appended != null) {
      admission = appended.$1;
      taskReady = appended.$2;
      taskRevision = appended.$3;
    } else {
      admission = _validateEffects(
        candidateEffects,
        manifest,
        onTaskReady: (ids) => taskReady = ids,
        onTaskValidated: (key) => taskRevision = key,
      );
    }
    if (effects.any(
      (e) =>
          e.task != null && !taskReady.contains(e.task!.id) ||
          e.food != null && !admission.readyIds.contains(e.food!.id),
    )) {
      throw FormatFailure(
        'Resolve missing app dependencies before reserving a command.',
      );
    }
    if (reserve) {
      _pending = Map<String, Object?>.unmodifiable({
        'space': manifest.space,
        'epoch': manifest.epoch,
        'writer': writer,
        'base_sequence': physicalSequence,
        'base_hash': commonHead,
        'base_bytes': base.length,
        'base_digest': _chainCommitment(commonHead),
        'raw': bytes,
      });
      _pendingBaseProof = _PendingBaseProof(
        _pending!,
        manifest.digest,
        base,
        physicalSequence,
        commonHead,
        _pending!['base_digest'] as String,
        snapshot.recordsByWriter[writer]?.lastOrNull?.clock,
      );
      _preparedAction = _PreparedAction(
        snapshot,
        _pending!,
        record,
        candidateEffects,
        admission,
        Set.unmodifiable(taskReady),
        taskRevision!,
      );
      _pendingProvenance = provenance;
      try {
        onReserved?.call(List.unmodifiable(records));
      } catch (error) {
        _pending = null;
        _pendingBaseProof = null;
        _preparedAction = null;
        _pendingProvenance = null;
        if (error is LocalDatabaseFailure || error is SqliteException) {
          reportQueueFailure(error);
        }
        rethrow;
      }
      _viewHasPending = true;
      _changes.notify();
    }
    return UnifiedReservation(List.unmodifiable(records), bytes);
  }

  Future<void> _discardOwnedTail() async {
    final actual = snapshot.physical[writer]!;
    final end = actual.lastIndexOf(10) + 1;
    if (end == actual.length) return;
    if (folder is! TailTruncateLogFolder) {
      throw FormatFailure(
        'This provider cannot discard an incomplete owned save safely.',
      );
    }
    await (folder as TailTruncateLogFolder).truncateOwnedTail(
      unifiedLogName(writer),
      actual,
      end,
    );
    final confirmed = (await refreshInProfileQueue()).physical[writer]!;
    if (confirmed.length != end ||
        bytesDigest(confirmed) !=
            bytesDigest(Uint8List.sublistView(actual, 0, end))) {
      throw FormatFailure(
        'Owned suffix cleanup was not confirmed; no new action was reserved.',
      );
    }
  }

  Future<(Uint8List, bool)> _ownedActual() async {
    final name = unifiedLogName(writer);
    final infos = await folder.list();
    final matches = infos.where((i) => i.name == name).toList();
    if (matches.length > 1) throw FormatFailure('Ambiguous owned app history.');
    if (matches.isNotEmpty) return (await _read(name, maximumFileBytes), true);
    final pending = _outbox(manifest);
    if (pending.length == 1 &&
        pending.single['base_sequence'] == 0 &&
        pending.single['base_bytes'] == 0 &&
        (manifest.owners[writer]?['count'] == 0 ||
            !manifest.owners.containsKey(writer) &&
                _validateReservedRecords(
                      manifest,
                      pending.single,
                    ).first.effect.kind ==
                    'writer.joined')) {
      return (Uint8List(0), false);
    }
    throw FormatFailure(
      'Owned app history is missing; preserve its exact receipt.',
    );
  }

  Future<UnifiedSnapshot> commitInProfileQueue() async {
    try {
      return await _commitInProfileQueue();
    } catch (error) {
      safetyFailure = error;
      _changes.notify();
      rethrow;
    }
  }

  Future<UnifiedSnapshot> _commitInProfileQueue() async {
    await refreshInProfileQueue();
    final pending = _outbox(manifest);
    if (pending.length != 1) {
      throw FormatFailure('No exact app reservation is available.');
    }
    final p = pending.single;
    final actual = snapshot.physical[writer]!;
    final exists = _fileInfos.containsKey(unifiedLogName(writer));
    final base = p['base_bytes'] as int, expected = p['raw'] as List<int>;
    // The refresh above validates inventory, current own head, and the original
    // reservation. It is the coherent pre-append observation, not a second read.
    if (actual.length != base) {
      throw FormatFailure(
        'App append needs exact recovery; no new IDs were allocated.',
      );
    }
    final prepared = _preparedAction;
    final canPublishPrepared =
        prepared != null &&
        identical(prepared.pending, p) &&
        identical(prepared.base, snapshot) &&
        _acceptedHeads == _protectedHeads(manifest);
    if (exists) {
      await folder.append(unifiedLogName(writer), Uint8List.fromList(expected));
    } else {
      await folder.create(unifiedLogName(writer), Uint8List.fromList(expected));
    }
    final result = canPublishPrepared
        ? await _confirmPreparedAction(prepared)
        : await refreshInProfileQueue();
    if (hasPending) {
      throw FormatFailure(
        'App command was not confirmed; recovery bytes were preserved.',
      );
    }
    return result;
  }

  Future<UnifiedSnapshot> _confirmPreparedAction(
    _PreparedAction prepared,
  ) async {
    final p = prepared.pending;
    if (!identical(_pending, p) ||
        !identical(_snapshot, prepared.base) ||
        _acceptedHeads != _protectedHeads(manifest)) {
      throw FormatFailure('App reservation changed before confirmation.');
    }
    final name = unifiedLogName(writer);
    final base = p['base_bytes'] as int;
    final expected = p['raw'] as Uint8List;
    final infos = await folder.list();
    final matches = infos.where((i) => i.name == name).toList();
    if (matches.length != 1) {
      throw FormatFailure('Owned app append pathname is missing or ambiguous.');
    }
    await _checkRegularFile(name);
    final info = matches.single;
    final oldInfo = _fileInfos[name];
    Uint8List? suffix;
    if (folder is BoundedRangeLogFolder &&
        _seekableFiles.contains(name) &&
        oldInfo?.identity == info.identity) {
      final raw = await (folder as BoundedRangeLogFolder).readFromBounded(
        name,
        base,
        maximumFileBytes - base,
      );
      readFiles++;
      if (raw != null) suffix = Uint8List.fromList(raw).asUnmodifiableView();
    }
    if (suffix == null) {
      // Conservative fallback keeps exact original reservation proof.
      final actual = await _read(name, maximumFileBytes);
      _validatePreparedBytes(manifest, prepared.base, actual, p);
      suffix = Uint8List.fromList(actual.sublist(base)).asUnmodifiableView();
    }
    if (!_sameBytes(suffix, expected)) {
      throw FormatFailure(
        'App append was not confirmed; exact bytes remain available.',
      );
    }
    // Both source chunks are frozen. takeBytes owns the concatenation (or
    // returns an already-frozen sole chunk); another full-buffer copy is idle.
    final ownBytes =
        (BytesBuilder(copy: false)
              ..add(prepared.base.physical[writer]!)
              ..add(suffix))
            .takeBytes()
            .asUnmodifiableView();
    final heads = profile.database
        .select(
          'SELECT writer,sequence,hash,bytes,digest,published FROM protected_app_heads WHERE space=? AND epoch=? ORDER BY writer',
          [manifest.space, manifest.epoch],
        )
        .map(
          (row) => [
            row['writer'],
            row['writer'] == writer
                ? prepared.record.sequence
                : row['sequence'],
            row['writer'] == writer ? prepared.record.hash : row['hash'],
            row['writer'] == writer
                ? _chainCommitment(prepared.record.hash)
                : row['digest'],
            row['writer'] == writer
                ? prepared.record.sequence
                : row['published'],
          ],
        )
        .toList();
    final revision = bytesDigest(
      utf8.encode(
        canonicalDataJson({'manifest': manifest.digest, 'heads': heads}),
      ),
    );
    final result = UnifiedSnapshot(
      revision,
      List.unmodifiable([...prepared.base.records, prepared.record]),
      prepared.effects,
      Map.unmodifiable({...prepared.base.physical, writer: ownBytes}),
      Map.unmodifiable({
        ...prepared.base.published,
        writer: prepared.record.sequence,
      }),
      prepared.base.incomplete,
      prepared.foodAdmission,
      false,
      readyTaskIds: prepared.readyTasks,
    );
    if (prepared.base.allVisibleTasksReady) result._knownAllTasksReady = true;
    _validatedOwnDeltas[result] = (
      baseToken: prepared.base._identity,
      tasks: List<LogEvent>.unmodifiable(
        prepared.record.effects.map((e) => e.task).whereType<LogEvent>(),
      ),
      food: List<FoodRecord>.unmodifiable(
        prepared.record.effects.map((e) => e.food).whereType<FoodRecord>(),
      ),
    );
    result._writerRecords = Map.unmodifiable({
      ...prepared.base.recordsByWriter,
      writer: List<UnifiedRecord>.unmodifiable([
        ...?prepared.base.recordsByWriter[writer],
        prepared.record,
      ]),
    });
    final logical = Map<String, int>.of(prepared.base.logicalSequences);
    for (final effect in prepared.record.effects.where((e) => e.isData)) {
      if (effect.sequence > (logical[effect.writer] ?? 0)) {
        logical[effect.writer] = effect.sequence;
      }
    }
    result._logicalHeads = Map.unmodifiable(logical);
    result._clock = prepared.record.clock;
    result._clockKnown = true;
    _verifiedTaskRevisions[result] = prepared.taskRevision;
    final publications = <void Function()>[];
    profile.transaction(() {
      profile.database.execute(
        'UPDATE protected_app_heads SET sequence=?,hash=?,bytes=?,digest=?,published=? WHERE space=? AND epoch=? AND writer=?',
        [
          prepared.record.sequence,
          prepared.record.hash,
          ownBytes.length,
          _chainCommitment(prepared.record.hash),
          prepared.record.sequence,
          manifest.space,
          manifest.epoch,
          writer,
        ],
      );
      _appendOwnToStore(prepared.record, base, ownBytes.length);
      for (final stage in _projections.values) {
        publications.add(stage(result));
      }
    });
    // Checkpoints, projections, receipt retirement and publication are one
    // transaction boundary. No private candidate grants authority before it.
    _snapshot = result;
    _completeEnds = {..._completeEnds, writer: ownBytes.length};
    _fileInfos = {..._fileInfos, name: info};
    _acceptedHeads = _protectedHeads(manifest);
    _pending = null;
    _pendingBaseProof = null;
    _preparedAction = null;
    _pendingProvenance = null;
    _viewHasPending = false;
    for (final publish in publications) {
      publish();
    }
    safetyFailure = null;
    _changes.notify();
    return result;
  }

  Future<UnifiedSnapshot> appendAtomic(List<UnifiedEffectBuilder> builders) =>
      _onProfile(() async {
        await prepareInProfileQueue(builders);
        return commitInProfileQueue();
      });

  Future<UnifiedSnapshot> recoverPrepared() =>
      _onProfile(recoverPreparedInProfileQueue);
  Future<UnifiedSnapshot> recoverPreparedInProfileQueue() async {
    try {
      return await _recoverPreparedInProfileQueue();
    } catch (error) {
      safetyFailure = error;
      _changes.notify();
      rethrow;
    }
  }

  Future<UnifiedSnapshot> _recoverPreparedInProfileQueue() async {
    await refreshInProfileQueue();
    final pending = _outbox(manifest);
    if (pending.isEmpty) return snapshot;
    final p = pending.single;
    final (actual, exists) = await _ownedActual();
    _validatePreparedBytes(manifest, snapshot, actual, p);
    final base = p['base_bytes'] as int, expected = p['raw'] as List<int>;
    final missing = expected.skip(actual.length - base).toList(growable: false);
    if (missing.isNotEmpty) {
      // Complete only the exact reserved prefix. Never truncate or rewrite the
      // canonical base; this is repeatable on append-only SAF providers too.
      if (exists) {
        await folder.append(
          unifiedLogName(writer),
          Uint8List.fromList(missing),
        );
      } else {
        await folder.create(
          unifiedLogName(writer),
          Uint8List.fromList(missing),
        );
      }
    }
    final result = await refreshInProfileQueue();
    if (hasPending) {
      throw FormatFailure('Recovered app append was not confirmed.');
    }
    return result;
  }

  Future<void> close() => _closing ??= profile.closeWorkspace(_lease, () {
    _closed = true;
    _pendingBaseProof = null;
    _preparedAction = null;
    _projections.clear();
    _decodedRecords.clear();
    _decodedRecordBytes = 0;
    _taskValidation.clear();
    _foodValidation.clear();
    _semanticValidator?.close();
    _semanticValidator = null;
    _changes.clear();
  });

  Future<UnifiedSnapshot> renameDevice(String? name) =>
      appendAtomic([(sequence, clock, head) => UnifiedEffect.named(name)]);

  Future<void> rebuildOwned() => _onProfile(() async {
    await refreshInProfileQueue(forceFullAudit: true);
    if (snapshot.incomplete ||
        hasPending ||
        folder is! AtomicReplaceLogFolder) {
      throw FormatFailure(
        'Rebuild requires complete history, resolved receipts and safe replacement.',
      );
    }
    final original = Uint8List.fromList(snapshot.physical[writer]!);
    await (folder as AtomicReplaceLogFolder).replaceOwned(
      unifiedLogName(writer),
      original,
      original,
    );
    await refreshInProfileQueue();
  });
}

/// Kept here to avoid requiring dart:io on pure wire/model files.
abstract final class FileSystemEntityTypeCheck {
  static Future<bool> regularFile(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.file;
}
