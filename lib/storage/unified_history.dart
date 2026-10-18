import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/event.dart';
import '../food/inventory.dart';
import '../food/food_record.dart';
import '../food/food_admission.dart';
import '../food/food_import_evidence.dart';
import 'local_profile_database.dart';
import 'local_settings.dart';
import 'log_folder.dart';
import 'unified_manifest.dart';
import 'unified_record.dart';
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

/// A single admitted revision. Physical observations include incomplete frames;
/// effects include only complete validated transactions.
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
  bool _closed = false;
  Future<void>? _closing;
  final _projections = <Object, UnifiedProjectionStage>{};
  // Cache only successful pure native/domain validation by exact semantic bytes.
  // Real provider bytes, protected observations and SQL projections are still
  // checked on every refresh. No metadata-only freshness assumptions.
  final _taskValidation = <String, Set<String>>{};

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

  String get _lease => 'app4:${folder.location}';
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
      if (!result.manifest.owners.containsKey(writer) &&
          result.physicalSequence == 0 &&
          !result.hasPending) {
        await result.appendAtomic([
          (seq, clock, head) => UnifiedEffect.joined(),
        ]);
      }
      return result;
    } catch (_) {
      profile.releaseWorkspace(result._lease);
      rethrow;
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

  Future<UnifiedSnapshot> refresh() => profile.serialize(refreshInProfileQueue);
  Future<UnifiedSnapshot> refreshInProfileQueue() async {
    try {
      if (_closed) throw StateError('App workspace is closed.');
      if (LocalSettings.protectedValues(profile)['writer'] != writer) {
        throw FormatFailure(
          'Installation writer differs from protected settings.',
        );
      }
      final result = await _refresh();
      safetyFailure = null;
      return result;
    } catch (e) {
      safetyFailure = e;
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
    return (folder as BoundedLogFolder).readBounded(name, limit);
  }

  Future<UnifiedSnapshot> _refresh({bool observe = true}) async {
    final rawManifest = utf8.decode(
      await _read('tandemlog-space.json', 1024 * 1024),
    );
    final current = UnifiedManifest.decode(rawManifest);
    if (!current.ready) {
      throw FormatFailure(
        'App cutover is staged; waiting for verified participant acknowledgements.',
      );
    }
    final bound = profile.database.select(
      'SELECT epoch,manifest,observed FROM protected_app_workspaces WHERE space=?',
      [current.space],
    );
    if (bound.isNotEmpty &&
        (bound.single['epoch'] != current.epoch ||
            bound.single['manifest'] != rawManifest)) {
      throw FormatFailure(
        'App workspace epoch changed. Preserve history before recovery.',
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
    final seals = {for (final s in current.seals) s.name: s};
    for (final info in infos) {
      final name = info.name;
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
        final seal = seals[name];
        if (seal == null || info.size != null && info.size != seal.length) {
          throw FormatFailure('Late, changed or unknown legacy history $name.');
        }
        final bytes = await _read(name, maximumFileBytes);
        if (bytes.length != seal.length || bytesDigest(bytes) != seal.digest) {
          throw FormatFailure('Sealed legacy history changed: $name.');
        }
      }
    }
    if (ownerSet.length > 256) {
      throw FormatFailure('Too many installation histories.');
    }
    final observed = <String, Uint8List>{},
        all = <UnifiedRecord>[],
        admitted = <UnifiedEffect>[],
        frames = <List<UnifiedRecord>>[],
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
          owner == writer &&
          !current.owners.containsKey(owner) &&
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
      var completeSequence = 0, frameStart = 0, frameCount = 0;
      final frame = <UnifiedRecord>[];
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
        if (r.space != current.space ||
            r.epoch != current.epoch ||
            r.writer != owner ||
            r.sequence != sequence + 1 ||
            r.previousHash != head ||
            clock != null && r.clock <= clock) {
          throw FormatFailure(
            'App writer sequence, identity, clock or chain differs.',
          );
        }
        if (!current.owners.containsKey(owner) &&
            r.sequence == 1 &&
            (r.effect.kind != 'writer.joined' || r.transactionCount != 1)) {
          throw FormatFailure(
            'New installation history must begin with its own header.',
          );
        }
        if (r.effect.kind == 'writer.joined' &&
            (r.sequence != 1 || current.owners.containsKey(owner))) {
          throw FormatFailure('Installation header is misplaced.');
        }
        if (r.sequence <= historicalCount) {
          if (!r.effect.historical ||
              r.transactionCount != 1 ||
              current.ownerOfLegacy(r.effect.writer, r.effect.kind) != owner) {
            throw FormatFailure(
              'App migration prefix is not original owner history.',
            );
          }
        } else if (r.effect.historical) {
          throw FormatFailure(
            'Unexpected late legacy event in the active writer chain.',
          );
        }
        if (frame.isEmpty) {
          if (r.transactionIndex != 0 || r.transactionStart != r.sequence) {
            throw FormatFailure('App transaction starts in the middle.');
          }
          frameStart = r.transactionStart;
          frameCount = r.transactionCount;
        }
        if (r.transactionStart != frameStart ||
            r.transactionCount != frameCount ||
            r.transactionIndex != frame.length) {
          throw FormatFailure('App transaction frame is inconsistent.');
        }
        frame.add(r);
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
        if (r.completesTransaction) {
          for (final event in frame) {
            final e = event.effect;
            if (e.isData) {
              final existing = semantic[e.key];
              if (existing != null && existing.raw != e.raw) {
                throw FormatFailure(
                  'Conflicting original semantic event identity.',
                );
              }
              if (existing == null) {
                semantic[e.key] = e;
                admitted.add(e);
              }
            } else {
              admitted.add(e);
            }
          }
          frames.add(List.unmodifiable(frame));
          completeSequence = sequence;
          frame.clear();
        }
        start = i + 1;
      }
      if (current.owners.containsKey(owner) &&
          (sequence < historicalCount ||
              bytesDigest(Uint8List.sublistView(bytes, 0, migrationEnd)) !=
                  current.owners[owner]!['digest'])) {
        throw FormatFailure('Incomplete or changed migration prefix.');
      }
      if (!current.owners.containsKey(owner) && sequence == 0 && exists) {
        final pending = owner == writer
            ? _outbox(current)
            : <Map<String, Object?>>[];
        if (pending.isEmpty ||
            _validateReservedRecords(
                  current,
                  pending.single,
                ).first.effect.kind !=
                'writer.joined') {
          throw FormatFailure(
            'New installation header is missing or incomplete.',
          );
        }
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
      if (start < bytes.length || frame.isNotEmpty) incomplete = true;
      published[owner] = completeSequence;
      heads.add([
        current.space,
        current.epoch,
        owner,
        sequence,
        head,
        bytes.length,
        bytesDigest(bytes),
        completeSequence,
      ]);
    }
    final imports = readFoodImportEvidence(profile, current.space);
    final foodHashes = <String, String>{
      for (final r in all)
        if (r.effect.food != null) r.effect.food!.id: r.effect.food!.hash,
    };
    final reserved = _outbox(current);
    if (reserved.isNotEmpty) {
      for (final r in _validateReservedRecords(current, reserved.single)) {
        if (r.effect.food != null) {
          foodHashes[r.effect.food!.id] = r.effect.food!.hash;
        }
      }
    }
    for (final attempt in imports) {
      for (final record in attempt['records'] as List) {
        if (foodHashes[record['id']] != record['hash']) {
          throw FormatFailure(
            'Retained import evidence is missing from exact app history or its receipt.',
          );
        }
      }
    }
    _validateLegacyCoverage(all, current);
    // Validate all physical evidence before deciding visibility. A blocked frame
    // cannot conceal a malformed event or relax the app-wide format fence.
    var taskReady = <String>{};
    final allAdmission = _validateEffects(
      admitted,
      current,
      onTaskReady: (ids) => taskReady = ids,
    );
    final publication = _publishFrames(
      frames,
      published,
      current,
      all,
      admitted,
      allAdmission,
      taskReady,
    );
    final visible = publication.$1;
    final foodAdmission = publication.$2;
    final pendingEffects = frames.any(
      (f) => f.last.sequence > (published[f.first.writer] ?? 0),
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
    if (bound.isEmpty) await _validateLegacyProtectedAuthority(current, result);
    final pending = _outbox(current);
    if (pending.isNotEmpty) {
      _validatePreparedPrefix(current, result, pending.single);
    }
    if (!observe) return result;
    final publications = <void Function()>[];
    profile.transaction(() {
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
      if (pending.isNotEmpty && _preparedComplete(result, pending.single)) {
        profile.database.execute(
          'DELETE FROM protected_app_outbox WHERE space=? AND epoch=? AND writer=?',
          [current.space, current.epoch, writer],
        );
      }
      for (final stage in _projections.values) {
        publications.add(stage(result));
      }
    });
    manifest = current;
    _snapshot = result;
    for (final publish in publications) {
      publish();
    }
    return result;
  }

  /// Semantic publication is a fixed point of complete writer prefixes.
  /// Hold the entire future frame for a missing Food dependency, and hold any
  /// later frame whose observed prefix is held. Legacy single events preserve
  /// their existing per-domain pending-reference rules.
  (List<UnifiedEffect>, FoodAdmission) _publishFrames(
    List<List<UnifiedRecord>> frames,
    Map<String, int> published,
    UnifiedManifest m,
    List<UnifiedRecord> all,
    List<UnifiedEffect> admitted,
    FoodAdmission allAdmission,
    Set<String> taskReady,
  ) {
    final physical = {for (final r in all) r.recordId: r};
    for (final frame in frames) {
      final first = frame.first;
      final observed = canonicalDataJson(
        first.observed.map((k, v) => MapEntry(k, v.toJson())),
      );
      for (final r in frame) {
        if (canonicalDataJson(
              r.observed.map((k, v) => MapEntry(k, v.toJson())),
            ) !=
            observed) {
          throw FormatFailure('App frame has inconsistent observed history.');
        }
      }
      for (final entry in first.observed.entries) {
        final f = entry.value;
        if (f.sequence == 0) {
          if (f.hash != unifiedGenesis(m.space, m.epoch, entry.key)) {
            throw FormatFailure('App command observes a different genesis.');
          }
        } else {
          final target = physical['app:${m.epoch}:${entry.key}:${f.sequence}'];
          if (target != null &&
              (target.hash != f.hash ||
                  !target.completesTransaction ||
                  target.clock >= first.clock)) {
            throw FormatFailure('App command observes an invalid frontier.');
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
              !physical['app:${m.epoch}:$owner:$trusted']!
                  .completesTransaction) {
        throw FormatFailure(
          'Trusted app publication frontier differs from physical history.',
        );
      }
      published[owner] = trusted;
    }
    // The ordinary complete case needs one semantic pass, not one native
    // replay per historical frame. Missing delivery retains the ascending
    // protected-prefix algorithm below.
    if (frames.every(
      (frame) =>
          frame.first.observed.entries.every(
            (e) => e.value.sequence <= (complete[e.key] ?? 0),
          ) &&
          frame.every(
            (r) =>
                (r.effect.task == null ||
                    taskReady.contains(r.effect.task!.id)) &&
                (r.effect.food == null ||
                    allAdmission.readyIds.contains(r.effect.food!.id)),
          ),
    )) {
      published.addAll(complete);
      return (admitted, allAdmission);
    }
    List<UnifiedEffect> effects() {
      final result = <UnifiedEffect>[], seen = <String>{};
      for (final frame in frames) {
        if (frame.last.sequence > (published[frame.first.writer] ?? 0)) {
          continue;
        }
        for (final r in frame) {
          if (!r.effect.isData || seen.add(r.effect.key)) result.add(r.effect);
        }
      }
      return result;
    }

    var visible = effects();
    var admission = _validateEffects(visible, m);
    while (true) {
      var changed = false;
      for (final frame in frames) {
        final first = frame.first;
        if (first.effect.historical ||
            first.sequence != (published[first.writer] ?? 0) + 1 ||
            !first.observed.entries.every(
              (e) => e.value.sequence <= (published[e.key] ?? 0),
            )) {
          continue;
        }
        final candidate = [...visible, ...frame.map((r) => r.effect)];
        var taskReady = <String>{};
        final checked = _validateEffects(
          candidate,
          m,
          onTaskReady: (ids) => taskReady = ids,
        );
        if (!frame.every(
          (r) =>
              (r.effect.food == null ||
                  checked.readyIds.contains(r.effect.food!.id)) &&
              (r.effect.task == null || taskReady.contains(r.effect.task!.id)),
        )) {
          continue;
        }
        published[first.writer] = frame.last.sequence;
        visible = candidate;
        admission = checked;
        changed = true;
      }
      if (!changed) return (visible, admission);
    }
  }

  void _validateLegacyCoverage(List<UnifiedRecord> records, UnifiedManifest m) {
    final covered = <String>{};
    for (final seal in m.seals) {
      final original =
          records
              .where(
                (r) =>
                    r.writer == seal.owner &&
                    r.effect.kind == seal.kind &&
                    r.effect.historical,
              )
              .map((r) => r.effect)
              .toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
      var sequence = 0,
          head = eventGenesisHash(
            m.space,
            seal.kind == 'legacy.task' ? seal.owner : foodWriter(seal.owner),
          );
      final output = BytesBuilder(copy: false);
      EventClock? clock;
      for (final e in original) {
        if (e.sequence != ++sequence ||
            e.previousHash != head ||
            clock != null && e.clock <= clock ||
            !covered.add(e.key)) {
          throw FormatFailure(
            'Historical source continuity or coverage differs.',
          );
        }
        output.add(utf8.encode('${e.raw}\n'));
        head = e.semanticHash;
        clock = e.clock;
      }
      final bytes = output.takeBytes();
      if (sequence != seal.count ||
          head != seal.head ||
          bytes.length != seal.length ||
          bytesDigest(bytes) != seal.digest) {
        throw FormatFailure(
          'Converted history does not preserve its sealed source.',
        );
      }
    }
    if (records
        .where((r) => r.effect.historical)
        .any((r) => !covered.contains(r.effect.key))) {
      throw FormatFailure('Converted event has no sealed source.');
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
      legacyOwners: {
        for (final owner in m.owners.keys) foodWriter(owner): owner,
      },
    );
  }

  Future<void> _validateLegacyProtectedAuthority(
    UnifiedManifest m,
    UnifiedSnapshot s,
  ) async {
    final originals = <String, Uint8List>{};
    for (final owner in m.owners.keys) {
      final tasks =
          s.records
              .where((r) => r.writer == owner && r.effect.kind == 'legacy.task')
              .map((r) => r.effect)
              .toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
      if (m.seals.any((seal) => seal.name == '$owner.jsonl')) {
        originals['$owner.jsonl'] = Uint8List.fromList(
          utf8.encode(tasks.map((e) => '${e.raw}\n').join()),
        );
      }
    }
    await TaskStore.verifyConvertedHistoryObservations(
      profile,
      m.space,
      originals,
    );
    final db = profile.database;
    for (final table in ['protected_text_intents', 'protected_food_intents']) {
      if (db.select('SELECT 1 FROM $table WHERE space=? LIMIT 1', [
        m.space,
      ]).isNotEmpty) {
        throw FormatFailure(
          'Resolve exact legacy pending appends before cutover.',
        );
      }
    }
    final index = {for (final e in s.effects.where((e) => e.isData)) e.key: e};
    for (final row in db.select(
      'SELECT * FROM protected_writer_guards WHERE space=?',
      [m.space],
    )) {
      final raw = row['raw'];
      final guard = decodeWriterGuardState(
        raw is String ? utf8.encode(raw) : raw as List<int>,
        m.space,
        row['writer'] as String,
      );
      final seq = guard.sequence;
      if (guard.pending.isNotEmpty) {
        throw FormatFailure('Legacy writer still has reserved bytes.');
      }
      final author = row['writer'] as String;
      if (!m.owners.containsKey(author) &&
          !m.owners.keys.any((o) => foodWriter(o) == author)) {
        throw FormatFailure(
          'Trusted legacy writer is missing from the owner roster.',
        );
      }
      if (seq > 0) {
        final matches = ['task', 'food']
            .map((kind) => index['$kind:${m.space}:$author:$seq'])
            .whereType<UnifiedEffect>()
            .toList();
        if (matches.length != 1 || matches.single.semanticHash != guard.hash) {
          throw FormatFailure(
            'Cutover does not preserve the trusted legacy writer head.',
          );
        }
      }
    }
    for (final row in db.select(
      'SELECT * FROM protected_food_heads WHERE space=?',
      [m.space],
    )) {
      final seq = row['sequence'] as int;
      if (seq > 0) {
        final key = 'food:${m.space}:${row['writer'] as String}:$seq';
        if (index[key]?.semanticHash != row['hash']) {
          throw FormatFailure(
            'Cutover does not preserve the trusted Food head.',
          );
        }
      }
    }
  }

  List<Map<String, Object?>> _outbox(UnifiedManifest m) => profile.database
      .select(
        'SELECT * FROM protected_app_outbox WHERE space=? AND epoch=? AND writer=?',
        [m.space, m.epoch, writer],
      )
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  bool get hasPending => _outbox(manifest).isNotEmpty;
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
                  !prefix.single.completesTransaction ||
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
    if (bytes.isEmpty || bytes.last != 10 || bytes.length > maximumFileBytes) {
      throw FormatFailure('Invalid app recovery receipt bytes.');
    }
    final records = <UnifiedRecord>[];
    var sequence = p['base_sequence'] as int, head = p['base_hash'] as String;
    EventClock? clock;
    final start = sequence + 1;
    final lines = utf8.decode(bytes).split('\n');
    final count = lines.length - 1;
    for (final raw in lines.take(count)) {
      final r = UnifiedRecord.decode(raw);
      if (r.space != m.space ||
          r.epoch != m.epoch ||
          r.writer != writer ||
          r.sequence != ++sequence ||
          r.previousHash != head ||
          r.transactionStart != start ||
          r.transactionCount != count ||
          r.transactionIndex != records.length ||
          r.effect.historical ||
          clock != null && r.clock <= clock) {
        throw FormatFailure('App recovery reservation is inconsistent.');
      }
      records.add(r);
      clock = r.clock;
      head = r.hash;
    }
    return records;
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
  String get commonHead {
    final own = snapshot.records.where((r) => r.writer == writer);
    return own.isEmpty
        ? unifiedGenesis(manifest.space, manifest.epoch, writer)
        : own.last.hash;
  }

  EventClock? get maximumClock => snapshot.records.isEmpty
      ? null
      : snapshot.records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);

  UnifiedRecord preview(
    UnifiedEffect e, {
    required int sequence,
    required EventClock clock,
    required String predecessor,
    required int start,
    required int count,
    required int index,
    Map<String, UnifiedFrontier>? observed,
  }) => UnifiedRecord(
    space: manifest.space,
    epoch: manifest.epoch,
    writer: writer,
    sequence: sequence,
    clock: clock,
    previousHash: predecessor,
    effect: e,
    transactionStart: start,
    transactionCount: count,
    transactionIndex: index,
    observed: observed ?? _observedFrontier,
  );

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
  }) => _prepareInProfileQueue(
    builders,
    expectedRevision: expectedRevision,
    onReserved: onReserved,
    reserve: true,
  );

  Future<UnifiedReservation> validateInProfileQueue(
    List<UnifiedEffectBuilder> builders,
  ) => _prepareInProfileQueue(builders, reserve: false);

  Future<UnifiedReservation> _prepareInProfileQueue(
    List<UnifiedEffectBuilder> builders, {
    String? expectedRevision,
    void Function(List<UnifiedRecord>)? onReserved,
    required bool reserve,
  }) async {
    await refreshInProfileQueue();
    if (snapshot.incomplete || snapshot.pendingEffects || hasPending) {
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
    final records = <UnifiedRecord>[];
    final prepared = BytesBuilder(copy: false);
    final base = snapshot.physical[writer]!;
    final currentTotal = snapshot.physical.values.fold<int>(
      0,
      (n, b) => n + b.length,
    );
    var sequence = physicalSequence, head = commonHead;
    EventClock? clock = maximumClock;
    final start = sequence + 1;
    for (var i = 0; i < builders.length; i++) {
      clock = EventClock.next(
        BigInt.from(now().microsecondsSinceEpoch) * BigInt.from(1000),
        clock,
      );
      final e = builders[i](++sequence, clock, head);
      if (e.historical) {
        throw FormatFailure('Legacy events require coordinated conversion.');
      }
      final record = preview(
        e,
        sequence: sequence,
        clock: clock,
        predecessor: head,
        start: start,
        count: builders.length,
        index: i,
      );
      final encoded = utf8.encode('${record.encode()}\n');
      if (base.length + prepared.length + encoded.length > maximumFileBytes ||
          currentTotal + prepared.length + encoded.length > maximumTotalBytes) {
        throw FormatFailure(
          'App command exceeds safe byte budgets; no bytes were reserved.',
        );
      }
      prepared.add(encoded);
      records.add(record);
      head = record.hash;
    }
    if (!manifest.owners.containsKey(writer) &&
        physicalSequence == 0 &&
        (records.length != 1 ||
            records.single.effect.kind != 'writer.joined')) {
      throw FormatFailure(
        'Complete this installation header before other commands.',
      );
    }
    final bytes = prepared.takeBytes().asUnmodifiableView();
    var taskReady = <String>{};
    final admission = _validateEffects(
      [...snapshot.effects, ...records.map((r) => r.effect)],
      manifest,
      onTaskReady: (ids) => taskReady = ids,
    );
    if (records.any(
          (r) =>
              r.effect.task != null && !taskReady.contains(r.effect.task!.id),
        ) ||
        records.any(
          (r) =>
              r.effect.food != null &&
              !admission.readyIds.contains(r.effect.food!.id),
        )) {
      throw FormatFailure(
        'Resolve missing app dependencies before reserving a command.',
      );
    }
    if (reserve) {
      profile.transaction(() {
        profile.database.execute(
          'INSERT INTO protected_app_outbox VALUES (?,?,?,?,?,?,?,?)',
          [
            manifest.space,
            manifest.epoch,
            writer,
            physicalSequence,
            commonHead,
            base.length,
            bytesDigest(base),
            bytes,
          ],
        );
        onReserved?.call(List.unmodifiable(records));
      });
    }
    return UnifiedReservation(List.unmodifiable(records), bytes);
  }

  Future<(Uint8List, bool)> _ownedActual() async {
    final name = unifiedLogName(writer);
    final infos = await folder.list();
    final matches = infos.where((i) => i.name == name).toList();
    if (matches.length > 1) throw FormatFailure('Ambiguous owned app history.');
    if (matches.isNotEmpty) return (await _read(name, maximumFileBytes), true);
    final pending = _outbox(manifest);
    if (!manifest.owners.containsKey(writer) &&
        pending.length == 1 &&
        pending.single['base_sequence'] == 0 &&
        pending.single['base_bytes'] == 0 &&
        _validateReservedRecords(manifest, pending.single).first.effect.kind ==
            'writer.joined') {
      return (Uint8List(0), false);
    }
    throw FormatFailure(
      'Owned app history is missing; preserve its exact receipt.',
    );
  }

  Future<UnifiedSnapshot> commitInProfileQueue() async {
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
      profile.serialize(() async {
        await prepareInProfileQueue(builders);
        return commitInProfileQueue();
      });

  Future<UnifiedSnapshot> recoverPrepared() =>
      profile.serialize(recoverPreparedInProfileQueue);
  Future<UnifiedSnapshot> recoverPreparedInProfileQueue() async {
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
    _taskValidation.clear();
  });

  Future<UnifiedSnapshot> renameDevice(String? name) =>
      appendAtomic([(sequence, clock, head) => UnifiedEffect.named(name)]);

  Future<void> rebuildOwned() => profile.serialize(() async {
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
