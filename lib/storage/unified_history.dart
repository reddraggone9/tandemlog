import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:uuid/uuid.dart';

import '../domain/event.dart';
import '../domain/time_zone_policy.dart';
import '../food/inventory.dart';
import '../food/food_record.dart';
import '../food/food_admission.dart';
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
    this.pendingEffects,
  );
  final String revision;
  final List<UnifiedRecord> records;
  final List<UnifiedEffect> effects;
  final Map<String, Uint8List> physical;
  final Map<String, int> published;
  final bool incomplete;
  final FoodAdmission foodAdmission;
  final bool pendingEffects;
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
class UnifiedHistory {
  UnifiedHistory._(
    this.folder,
    this.profile,
    this.writer,
    this.now,
    this.textEngine,
  );
  final LogFolder folder;
  final LocalProfileDatabase profile;
  final String writer;
  final DateTime Function() now;
  final NativeTextEngine? textEngine;
  late UnifiedManifest manifest;
  UnifiedSnapshot? _snapshot;
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
  // Real provider bytes, protected observations and SQL projections are still
  // checked on every refresh. No metadata-only freshness assumptions.
  final _taskValidation = <String, Set<String>>{};
  Map<String, Object?>? _pending;
  Map<String, dynamic>? _pendingProvenance;

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
  Future<UnifiedSnapshot> refreshInProfileQueue() async {
    try {
      if (_closed) throw StateError('App workspace is closed.');
      if (LocalSettings.protectedValues(profile)['writer'] != writer) {
        throw FormatFailure(
          'Installation writer differs from protected settings.',
        );
      }
      await _refresh();
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

  Future<Uint8List> _read(String name, int limit) async {
    if (folder is! BoundedLogFolder) {
      throw FormatFailure(
        'Provider cannot enforce unified history read limits.',
      );
    }
    if (folder is LocalLogFolder) {
      final file = (folder as LocalLogFolder).file(name);
      if (await FileSystemEntityTypeCheck.regularFile(file.path) == false) {
        throw FormatFailure('Linked or missing unified history is unsafe.');
      }
    }
    final bytes = await (folder as BoundedLogFolder).readBounded(name, limit);
    if (name.endsWith('.applog')) readFiles++;
    return bytes;
  }

  Future<UnifiedSnapshot> _refresh({bool observe = true}) async {
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
          j.length > 256 ||
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
    if (ownerSet.length > 256) {
      throw FormatFailure('Too many installation histories.');
    }
    final observed = <String, Uint8List>{},
        all = <UnifiedRecord>[],
        admitted = <UnifiedEffect>[],
        published = <String, int>{},
        heads = <List<Object?>>[];
    final semantic = <String, UnifiedEffect>{};
    var incomplete = false, total = 0;
    final owners = ownerSet.toList()..sort();
    for (final owner in owners) {
      final name = unifiedLogName(owner);
      final exists = byName.containsKey(name);
      final protected = profile.database.select(
        'SELECT * FROM protected_app_heads WHERE space=? AND epoch=? AND writer=?',
        [current.space, current.epoch, owner],
      );
      final missingNewSelf =
          ((owner == writer && !current.owners.containsKey(owner)) ||
              current.owners[owner]?['count'] == 0) &&
          (protected.isEmpty ||
              protected.single['sequence'] == 0 &&
                  protected.single['bytes'] == 0);
      if (!exists && !missingNewSelf) {
        throw FormatFailure('Expected app writer file is missing: $name');
      }
      final bytes = exists ? await _read(name, maximumFileBytes) : Uint8List(0);
      total += bytes.length;
      if (total > maximumTotalBytes) {
        throw FormatFailure('App history exceeds safe limits.');
      }
      observed[owner] = Uint8List.fromList(bytes).asUnmodifiableView();

      if (protected.isNotEmpty) {
        final old = protected.single, length = old['bytes'] as int;
        if (bytes.length < length ||
            bytesDigest(Uint8List.sublistView(bytes, 0, length)) !=
                old['digest']) {
          throw FormatFailure(
            'Previously observed app history changed or was truncated.',
          );
        }
      }
      var start = 0,
          sequence = 0,
          head = unifiedGenesis(current.space, current.epoch, owner);
      EventClock? clock;
      var semanticSequence = 0;
      var completeSequence = 0;
      var migrationEnd = 0;
      final historicalCount = current.owners[owner]?['count'] as int? ?? 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != 10) {
          if (i - start >= maximumUnifiedRecordBytes) {
            throw FormatFailure('Oversized app record.');
          }
          continue;
        }
        final raw = utf8.decode(Uint8List.sublistView(bytes, start, i));
        final r = UnifiedRecord.decode(raw);
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
        all.add(r);
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
        completeSequence = sequence;
        start = i + 1;
      }
      if (current.owners.containsKey(owner) &&
          (sequence < historicalCount ||
              bytesDigest(Uint8List.sublistView(bytes, 0, migrationEnd)) !=
                  current.owners[owner]!['digest'])) {
        throw FormatFailure('Incomplete or changed migration prefix.');
      }
      if (protected.isNotEmpty) {
        final old = protected.single,
            oldSeq = old['sequence'] as int,
            oldBytes = old['bytes'] as int;
        final matches = all.where(
          (r) => r.writer == owner && r.sequence == oldSeq,
        );
        if (oldBytes < 0 ||
            oldSeq < 0 ||
            (old['published'] as int) < 0 ||
            (old['published'] as int) > oldSeq ||
            bytes.take(oldBytes).where((b) => b == 10).length != oldSeq ||
            (oldSeq == 0
                ? old['hash'] !=
                      unifiedGenesis(current.space, current.epoch, owner)
                : matches.length != 1 || matches.single.hash != old['hash'])) {
          throw FormatFailure('Trusted app prefix identity or head differs.');
        }
      }
      if (start < bytes.length) incomplete = true;
      published[owner] = completeSequence;
      heads.add([
        current.space,
        current.epoch,
        owner,
        sequence,
        head,
        start,
        bytesDigest(Uint8List.sublistView(bytes, 0, start)),
        completeSequence,
      ]);
    }
    _validateReferenceCoverage(all, current);
    // Validate all physical evidence before deciding visibility. A blocked action
    // cannot conceal a malformed event or relax the app-wide format fence.
    var taskReady = <String>{};
    final allAdmission = _validateEffects(
      admitted,
      current,
      onTaskReady: (ids) => taskReady = ids,
    );
    final publication = _publishActions(
      all,
      published,
      current,
      admitted,
      allAdmission,
      taskReady,
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
    );
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
      for (final stage in _projections.values) {
        publications.add(stage(result));
      }
      pendingAfterCommit = !retirePending && _outbox(current).isNotEmpty;
    });
    if (retirePending) {
      _pending = null;
      _pendingProvenance = null;
    }
    manifest = current;
    _snapshot = result;
    _viewHasPending = pendingAfterCommit;
    for (final publish in publications) {
      publish();
    }
    return result;
  }

  /// Publish complete writer prefixes to a fixed point. A missing typed
  /// dependency holds the entire action and actions observing its frontier.
  (List<UnifiedEffect>, FoodAdmission) _publishActions(
    List<UnifiedRecord> actions,
    Map<String, int> published,
    UnifiedManifest m,
    List<UnifiedEffect> admitted,
    FoodAdmission allAdmission,
    Set<String> taskReady,
  ) {
    final physical = {for (final r in actions) r.recordId: r};
    for (final action in actions) {
      for (final entry in action.observed.entries) {
        final f = entry.value;
        if (f.sequence == 0) {
          if (f.hash != unifiedGenesis(m.space, m.epoch, entry.key)) {
            throw FormatFailure('App action observes a different genesis.');
          }
        } else {
          final target = physical['app:${m.epoch}:${entry.key}:${f.sequence}'];
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
          trusted > 0 &&
              !physical.containsKey('app:${m.epoch}:$owner:$trusted')) {
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
      return (admitted, allAdmission);
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
    var admission = _validateEffects(visible, m);
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
        final checked = _validateEffects(
          candidate,
          m,
          onTaskReady: (ids) => readyTasks = ids,
        );
        if (!action.effects.every((e) => ready(e, checked, readyTasks))) {
          continue;
        }
        published[action.writer] = action.sequence;
        visible.addAll(action.effects);
        admission = checked;
        changed = true;
      }
      if (!changed) {
        return (visible, admission);
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

  FoodAdmission _validateEffects(
    Iterable<UnifiedEffect> effects,
    UnifiedManifest m, {
    void Function(Set<String>)? onTaskReady,
  }) {
    final tasks = <String, List<LogEvent>>{}, food = <String, FoodRecord>{};
    for (final effect in effects.where((e) => e.isData)) {
      final e = effect.task;
      if (e != null) {
        tasks.putIfAbsent(e.entity, () => []).add(e);
      } else {
        final r = effect.food!, previous = food[r.id];
        if (previous != null && previous.encode() != r.encode()) {
          throw FormatFailure('Conflicting Food operation identity.');
        }
        food[r.id] = r;
      }
    }
    final semanticTasks = tasks.values.expand((v) => v).toList();
    final key = bytesDigest(
      utf8.encode(
        canonicalDataJson([
          m.space,
          ...effects.where((e) => e.task != null).map((e) => e.raw),
        ]),
      ),
    );
    var ready = _taskValidation.remove(key);
    if (ready == null) {
      TaskStore.validateSemanticHistory(
        semanticTasks,
        space: m.space,
        writer: writer,
        textEngine: textEngine,
        onReady: (ids) => ready = Set.unmodifiable(ids),
      );
      ready ??= const <String>{};
    }
    _taskValidation[key] = ready!;
    if (_taskValidation.length > 4) {
      _taskValidation.remove(_taskValidation.keys.first);
    }
    onTaskReady?.call(ready!);
    return admitFoodRecords(
      food.values.toList(),
      legacyOwners: m.referenceAuthors,
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
        (base > 0 &&
            (bytes[base - 1] != 10 ||
                bytes.take(base).where((b) => b == 10).length != seq)) ||
        bytesDigest(Uint8List.sublistView(bytes, 0, base)) !=
            p['base_digest'] ||
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

  int get physicalSequence => snapshot.records
      .where((r) => r.writer == writer)
      .fold(0, (a, r) => r.sequence > a ? r.sequence : a);
  int get logicalSequence => snapshot.records
      .expand((r) => r.effects)
      .where((e) => e.isData && e.writer == writer)
      .fold<int>(0, (n, e) => e.sequence > n ? e.sequence : n);
  String get commonHead {
    final own = snapshot.records.where((r) => r.writer == writer);
    return own.isEmpty
        ? unifiedGenesis(manifest.space, manifest.epoch, writer)
        : own.last.hash;
  }

  EventClock? get maximumClock => snapshot.records.isEmpty
      ? null
      : snapshot.records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);

  Map<String, UnifiedFrontier> get _observedFrontier => {
    for (final e in snapshot.published.entries)
      e.key: UnifiedFrontier(
        e.value,
        e.value == 0
            ? unifiedGenesis(manifest.space, manifest.epoch, e.key)
            : snapshot.records
                  .firstWhere((r) => r.writer == e.key && r.sequence == e.value)
                  .hash,
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

  Future<UnifiedReservation> validateInProfileQueue(
    List<UnifiedEffectBuilder> builders,
  ) => _prepareInProfileQueue(builders, reserve: false);

  Future<UnifiedReservation> _prepareInProfileQueue(
    List<UnifiedEffectBuilder> builders, {
    String? expectedRevision,
    void Function(List<UnifiedRecord>)? onReserved,
    Map<String, dynamic>? provenance,
    required bool reserve,
  }) async {
    await refreshInProfileQueue();
    if (reserve && !hasPending) await _discardOwnedTail();
    if (snapshot.pendingEffects || hasPending) {
      throw FormatFailure(
        'App history has an incomplete command; preserve drafts and recover.',
      );
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
    final admission = _validateEffects(
      [...snapshot.effects, ...effects],
      manifest,
      onTaskReady: (ids) => taskReady = ids,
    );
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
      _pending = {
        'space': manifest.space,
        'epoch': manifest.epoch,
        'writer': writer,
        'base_sequence': physicalSequence,
        'base_hash': commonHead,
        'base_bytes': base.length,
        'base_digest': bytesDigest(base),
        'raw': bytes,
      };
      _pendingProvenance = provenance;
      try {
        onReserved?.call(List.unmodifiable(records));
      } catch (error) {
        _pending = null;
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
    final (actual, exists) = await _ownedActual();
    final base = p['base_bytes'] as int, expected = p['raw'] as List<int>;
    if (actual.length != base || bytesDigest(actual) != p['base_digest']) {
      throw FormatFailure(
        'App append needs exact recovery; no new IDs were allocated.',
      );
    }
    if (exists) {
      await folder.append(unifiedLogName(writer), Uint8List.fromList(expected));
    } else {
      await folder.create(unifiedLogName(writer), Uint8List.fromList(expected));
    }
    final result = await refreshInProfileQueue();
    if (hasPending) {
      throw FormatFailure(
        'App command was not confirmed; recovery bytes were preserved.',
      );
    }
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
    _projections.clear();
    _changes.clear();
    _taskValidation.clear();
  });

  Future<UnifiedSnapshot> renameDevice(String? name) =>
      appendAtomic([(sequence, clock, head) => UnifiedEffect.named(name)]);

  Future<void> rebuildOwned() => _onProfile(() async {
    await refreshInProfileQueue();
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
