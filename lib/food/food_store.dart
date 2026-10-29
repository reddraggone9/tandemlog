import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../storage/local_profile_database.dart';
import '../storage/local_settings.dart';
import '../storage/log_folder.dart';
import '../storage/unified_history.dart';
import '../storage/unified_record.dart';
import '../storage/workspace_view.dart';
import 'food_record.dart';
import 'food_admission.dart';
import 'food_import.dart';
import 'food_purchase_import.dart';
import 'inventory.dart';

/// Isolated canonical Food history/provider admission failure. Shared profile,
/// installation identity and manifest faults deliberately retain their own type.
/// A caller precondition failed after fresh admission; nothing was appended.
class StaleFoodState implements Exception {
  const StaleFoodState();
}

class FoodHistoryFailure extends FormatException {
  const FoodHistoryFailure(super.message);
}

/// One module handle on the app-owned connection and queue. Canonical streams
/// remain in the selected folder; SQL stores recovery authority, never a second
/// canonical inventory. Projection publishes only after admission commits.
class FoodStore {
  FoodStore._(
    this.folder,
    this.profile,
    this.writer,
    this.space,
    this._lease,
    this.now, {
    this.unified,
  });
  final UnifiedHistory? unified;
  final LogFolder folder;
  final LocalProfileDatabase profile;
  final String writer, space, _lease;
  final DateTime Function() now;
  FoodState state = FoodState([]);
  FoodViewSnapshot _currentView = FoodViewSnapshot.empty();
  FoodViewSnapshot get currentView => _currentView;
  final _viewChanges = WorkspaceChanges();
  Object? viewFailure;
  void Function() listenView(void Function() listener) =>
      _viewChanges.listen(listener);

  List<FoodRecord> _records = [];
  Map<String, FoodRecord> _births = {};
  bool _closed = false;
  Future<void> _operations = Future<void>.value();
  Future<void>? _closing;
  int pendingReferences = 0;
  List<FoodRecord> lastPreparedRecords = [];
  bool isAdmitted(FoodRecord record) =>
      _stagedFoodAdmission?.confirmsReadyRecord(record) ??
      (_readyIds.contains(record.id) &&
          _records.any((r) => r.id == record.id && r.hash == record.hash));
  bool get hasPreparedAppend => unified!.hasPending;
  List<String> _pendingOperationIds = const [];
  List<String> get pendingOperationIds => _pendingOperationIds;
  Set<String> _readyIds = {};
  static const maximumStreamBytes = 16 * 1024 * 1024,
      maximumTotalBytes = 32 * 1024 * 1024,
      maximumRecords = 50000,
      maximumContainers = 100000;

  static Future<FoodStore> openUnified(UnifiedHistory history) async {
    final lease = 'food:app5:${history.folder.location}';
    history.profile.acquireWorkspace(lease);
    final store = FoodStore._(
      history.folder,
      history.profile,
      history.writer,
      history.manifest.space,
      lease,
      history.now,
      unified: history,
    );
    try {
      await history.profile.serialize(() async {
        history.attachProjectionInProfileQueue(
          store,
          store._stageUnifiedProjection,
        );
      });
      return store;
    } catch (_) {
      history.profile.releaseWorkspace(lease);
      rethrow;
    }
  }

  FoodAdmission? _stagedFoodAdmission;
  UnifiedSnapshot? _stagedFoodSnapshot;

  void Function() _stageUnifiedProjection(UnifiedSnapshot snapshot) {
    if (identical(snapshot.foodAdmission, _stagedFoodAdmission) &&
        !snapshot.pendingEffects &&
        _pendingOperationIds.isEmpty &&
        pendingReferences == 0) {
      final pending = unified!.pendingRecords
          .expand((r) => r.effects)
          .map((e) => e.food)
          .whereType<FoodRecord>()
          .toList();
      return () {
        _stagedFoodSnapshot = snapshot;
        if (pending.isNotEmpty) {
          lastPreparedRecords = List.unmodifiable(pending);
        }
      };
    }
    final ownDelta = unified!.validatedFoodDelta(snapshot, _stagedFoodSnapshot);
    final records = ownDelta != null
        ? [..._records, ...ownDelta]
        : snapshot.effects
              .where((e) => e.food != null)
              .map((e) => e.food!)
              .toList();
    final admission = snapshot.foodAdmission;
    final candidateView = FoodViewSnapshot.next(admission.state, _currentView);
    final pendingIds = ownDelta != null && !snapshot.pendingEffects
        ? <String>[]
        : snapshot.records
              .expand((r) => r.effects)
              .map((e) => e.food)
              .whereType<FoodRecord>()
              .where((r) => !admission.readyIds.contains(r.id))
              .map((r) => r.id)
              .toSet()
              .toList();
    final pending = unified!.pendingRecords
        .expand((r) => r.effects)
        .where((e) => e.food != null)
        .map((e) => e.food!)
        .toList();
    return () {
      _stagedFoodSnapshot = snapshot;
      _stagedFoodAdmission = admission;
      _currentView = candidateView;
      state = candidateView.state;
      _births = admission.births;
      _readyIds = admission.readyIds;
      _records = List.unmodifiable(records);
      _pendingOperationIds = List.unmodifiable(pendingIds);
      pendingReferences =
          pendingIds.length +
          (snapshot.pendingEffects && pendingIds.isEmpty ? 1 : 0);
      if (pending.isNotEmpty) lastPreparedRecords = List.unmodifiable(pending);
    };
  }

  bool _ownsFood(String author) =>
      author == writer || unified!.manifest.referenceAuthors[author] == writer;

  List<UnifiedEffectBuilder> _unifiedBuilders(List<_FoodChange> changes) {
    String? previousEdit;
    return [
      for (final change in changes)
        (seq, clock, head) {
          final basis = <String, String>{};
          if (change.action != FoodAction.add &&
              !change.action.productLevel &&
              !change.productUndo) {
            for (final id in change.targets) {
              final birth = _births[id];
              if (birth == null || !_readyIds.contains(birth.id)) {
                throw const FormatException(
                  'Food target is not an admitted container.',
                );
              }
              basis[id] = birth.id;
            }
          }
          final record = FoodRecord(
            unified: true,
            space: space,
            writer: writer,
            sequence: seq,
            clock: clock,
            previousHash: head,
            createdWith: basis,
            operation: FoodOperation(
              id: '$writer:$seq',
              order: clock.value.toInt(),
              action: change.action,
              targets: change.targets,
              details: change.details,
              contents: change.contents,
              fields: change.fields,
              createdAt: change.action == FoodAction.add
                  ? change.createdAt ?? now().toUtc().toIso8601String()
                  : null,
              observedDeletes: change.deletes,
              observedEdits: [
                ...change.edits,
                if (change.observePreviousEdit)
                  previousEdit ??
                      (throw const FormatException(
                        'Missing previous Food edit.',
                      )),
              ],
              retracts: change.retracts,
              product: change.product,
              purchase: change.purchase,
              link: change.link,
              into: change.into,
              undoOwner:
                  change.action == FoodAction.undo &&
                      change.retracts!.split(':').first != writer
                  ? writer
                  : null,
            ),
          );
          previousEdit = record.id;
          return UnifiedEffect('food', record.encode());
        },
    ];
  }

  // Empty semantic plans still require the fresh observation, but never reserve
  // an empty action. The sentinel is private to this synchronous callback.
  Future<List<FoodRecord>> _freshCommandLocked(
    List<_FoodChange> Function() plan, {
    Map<String, dynamic>? provenance,
    bool validateOnly = false,
    bool Function()? canCommit,
  }) async {
    try {
      List<UnifiedEffectBuilder> build() {
        if (canCommit != null && !canCommit()) throw const StaleFoodState();
        final changes = plan();
        if (changes.isEmpty) throw const _EmptyFoodPlan();
        return _unifiedBuilders(changes);
      }

      final reservation = validateOnly
          ? await unified!.validateFromFreshInputsInProfileQueue(build)
          : await unified!.prepareFromFreshInputsInProfileQueue(
              build,
              provenance: provenance,
            );
      if (validateOnly) return const [];
      final batch = List<FoodRecord>.unmodifiable(
        reservation.records.expand((r) => r.effects).map((e) => e.food!),
      );
      lastPreparedRecords = batch;
      await unified!.commitInProfileQueue();
      return batch;
    } on _EmptyFoodPlan {
      if (!validateOnly) lastPreparedRecords = const [];
      return const [];
    }
  }

  Future<T> _queue<T>(Future<T> Function() work) {
    if (_closed || _closing != null) {
      return Future.error(StateError('Food workspace is closed.'));
    }
    var entered = false;
    final result = profile.serialize(() async {
      entered = true;
      if (_closed) throw StateError('Food workspace is closed.');
      try {
        return await work();
      } finally {
        if (unified == null) _viewChanges.notify();
      }
    });
    final observed = result.then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        if (!entered) {
          if (unified != null) {
            unified!.reportQueueFailure(error);
          } else {
            viewFailure = error;
            _viewChanges.notify();
          }
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _operations = observed.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return observed;
  }

  /// Drain this handle's already admitted work without requiring a healthy SQL
  /// owner. Poisoned profiles must still be able to release all handle leases.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    return _closing ??= _operations.then((_) {
      _closed = true;
      _viewChanges.clear();
      unified?.detachProjectionInProfileQueue(this);
      profile.releaseWorkspace(_lease);
    });
  }

  Future<void> refresh() => _queue(_refresh);

  Future<void> _refresh() => unified!.refreshInProfileQueue();
  Future<void> recoverPrepared() =>
      _queue(() => unified!.recoverPreparedInProfileQueue());

  Future<List<FoodRecord>> _command(
    List<_FoodChange> changes, {
    bool Function()? canCommit,
  }) => _queue(() => _commandLocked(changes, canCommit: canCommit));
  Future<List<FoodRecord>> _commandLocked(
    List<_FoodChange> changes, {
    Map<String, dynamic>? provenance,
    bool Function()? canCommit,
  }) async {
    return _freshCommandLocked(
      () => changes,
      provenance: provenance,
      canCommit: canCommit,
    );
  }

  // Import identity is committed with the actual containers. No private
  // attempt ledger or restart-recovery intent can cause a second import.
  List<Map<String, dynamic>> _importAttempts() {
    final records = [
      ...unified!.snapshot.records,
      ...unified!.pendingRecords.where(
        (p) => !unified!.snapshot.records.any((r) => r.recordId == p.recordId),
      ),
    ];
    return [
      for (final action in records)
        if (action.provenance?['kind'] == 'food.import')
          {
            'importId': action.provenance!['namespace'],
            'sourceSha256': action.provenance!['sourceSha256'],
            'planHash': action.provenance!['planHash'],
            'writer': action.writer,
            'records': [
              for (final e in action.effects)
                {'id': e.food!.id, 'hash': e.food!.hash},
            ],
          },
    ];
  }

  List<_FoodChange> _importChanges(FoodImportPlan plan) => [
    for (final container in plan.containers)
      _FoodChange(
        FoodAction.add,
        [container.targetId(plan.importId)],
        details: container.details,
        contents: container.contents,
        createdAt: container.createdAt,
      ),
  ];
  FoodImportReport _importReport(
    FoodImportPlan plan,
    FoodImportStatus status, [
    List<String> ids = const [],
  ]) => FoodImportReport(status, plan.planHash, writer, plan.targetIds, ids);

  Future<FoodImportReport> _inspectImport(
    FoodImportPlan plan,
    List<Map<String, dynamic>> attempts,
  ) async {
    plan.validate();
    _checkImportWriter();
    if (plan.space != space) {
      throw const FormatException('Import workspace differs.');
    }
    final matches = attempts
        .where((a) => a['importId'] == plan.importId)
        .toList();
    if (matches.isEmpty) {
      if (attempts.any((a) => a['sourceSha256'] == plan.sourceSha256)) {
        throw const FormatException(
          'This source already has an import namespace.',
        );
      }
      if (attempts.length >= 100) {
        throw const FormatException('Import attempt limit reached.');
      }
      // Never recover another command or multiply target UUID derivations just
      // to reject its pending suffix. All receipts were validated by refresh.
      if (hasPreparedAppend || pendingReferences > 0) {
        throw const FormatException('Recover or sync Food before importing.');
      }
      final targetIds = plan.targetIds;
      if (targetIds.any(_births.containsKey)) {
        throw const FormatException(
          'Import physical identity already exists without this attempt.',
        );
      }
      await unified!.validateInProfileQueue(
        _unifiedBuilders(_importChanges(plan)),
      );
      return _importReport(plan, FoodImportStatus.ready);
    }
    final attempt = matches.single;
    if (attempt['planHash'] != plan.planHash ||
        attempt['sourceSha256'] != plan.sourceSha256 ||
        !_ownsFood(attempt['writer'] as String)) {
      throw const FormatException(
        'Import attempt source, plan or writer differs.',
      );
    }
    final evidence = (attempt['records'] as List).cast<Map<String, dynamic>>();
    if (evidence.length != plan.containers.length) {
      throw const FormatException('Import count differs.');
    }
    final known = {for (final r in _records) r.id: r};
    final pending = unified!.pendingRecords
        .expand((r) => r.effects)
        .where((e) => e.food != null)
        .map((e) => e.food!)
        .toList();
    final pendingById = {for (final r in pending) r.id: r};
    var complete = true;
    final missing = <String>{};
    for (var i = 0; i < evidence.length; i++) {
      final proof = evidence[i];
      final record = known[proof['id']] ?? pendingById[proof['id']];
      final container = plan.containers[i];
      if (record == null ||
          record.hash != proof['hash'] ||
          record.space != space ||
          record.writer != attempt['writer'] ||
          record.operation.action != FoodAction.add ||
          record.operation.targets.length != 1 ||
          record.operation.targets.single !=
              container.targetId(plan.importId) ||
          record.operation.createdAt != container.createdAt ||
          canonicalDataJson(record.operation.details?.toJson()) !=
              canonicalDataJson(container.details.toJson()) ||
          canonicalDataJson(record.operation.contents?.toJson()) !=
              canonicalDataJson(container.contents.toJson())) {
        throw const FormatException(
          'Original import record differs or is missing.',
        );
      }
      if (!isAdmitted(record)) {
        complete = false;
        missing.add(record.id);
      }
    }
    if (!complete &&
        (pending.length != missing.length ||
            pending.any((r) => !missing.contains(r.id)) ||
            !hasPreparedAppend)) {
      throw const FormatException(
        'Import recovery differs from its exact protected receipts.',
      );
    }
    return FoodImportReport(
      complete ? FoodImportStatus.committed : FoodImportStatus.pendingRecovery,
      plan.planHash,
      attempt['writer'] as String,
      plan.targetIds,
      evidence.map((r) => r['id'] as String).toList(),
    );
  }

  void _checkImportWriter() {
    final installation =
        LocalSettings.protectedValues(profile)['writer'] as String;
    if (installation != writer) {
      throw const FormatException(
        'Import writer differs from current protected settings.',
      );
    }
  }

  Future<FoodImportReport> dryRunImport(FoodImportPlan plan) =>
      _queue(() async {
        _checkImportWriter();
        await _refresh();
        return _inspectImport(plan, _importAttempts());
      });
  Future<FoodImportReport> commitImport(FoodImportPlan plan) =>
      _queue(() async {
        _checkImportWriter();
        await _refresh();
        final attempts = _importAttempts();
        final inspected = await _inspectImport(plan, attempts);
        if (inspected.status == FoodImportStatus.committed) return inspected;
        if (inspected.status == FoodImportStatus.pendingRecovery) {
          await unified!.recoverPreparedInProfileQueue();
          await _refresh();
        } else {
          await _commandLocked(
            _importChanges(plan),
            provenance: {
              'kind': 'food.import',
              'namespace': plan.importId,
              'sourceSha256': plan.sourceSha256,
              'planHash': plan.planHash,
            },
          );
        }
        return _inspectImport(plan, _importAttempts());
      });

  /// Adds containers to the product matching the description, or to a new
  /// one, in one action (design/food-products.md, section 3).
  ///
  /// Caller-chosen [ids] make a retry idempotent: when every ID is already
  /// present the add is complete and appends nothing.
  Future<void> add(FoodDetails details, int count, {List<String>? ids}) {
    if (count < 1 || count > 100) {
      return Future.error(
        const FormatException('Choose between 1 and 100 physical containers.'),
      );
    }
    if (ids != null &&
        (ids.length != count ||
            ids.toSet().length != count ||
            !ids.every(isCanonicalId))) {
      return Future.error(const FormatException('Invalid container IDs.'));
    }
    return _queue(() {
      return _freshCommandLocked(() {
        if (ids != null) {
          final known = {for (final c in state.containers) c.id};
          final present = ids.where(known.contains).length;
          if (present == ids.length) return const [];
          if (present != 0) {
            throw const FormatException('Some of these containers exist.');
          }
        }
        final plan = planFoodAdd(state, details);
        return [
          if (plan.create != null)
            _FoodChange(FoodAction.product, [
              plan.product!,
            ], product: plan.create),
          _FoodChange(
            FoodAction.add,
            List.generate(count, (i) => ids?[i] ?? const Uuid().v4()),
            details: details,
            contents: const Contents.fraction(1, 1),
            link: plan.product == null ? null : {'product': plan.product},
          ),
        ];
      });
    });
  }

  static List<_FoodChange> _productChanges(List<FoodProductStep> steps) => [
    for (final step in steps)
      switch (step) {
        FoodProductEdit(:final product, :final values) => _FoodChange(
          FoodAction.product,
          [product],
          product: values,
        ),
        FoodProductMerge(:final source, :final into) => _FoodChange(
          FoodAction.merge,
          [source],
          into: into,
        ),
      },
  ];

  List<_FoodChange> _purchaseImportChanges(List<FoodImportStep> steps) => [
    for (final step in steps)
      switch (step) {
        FoodImportProduct(:final product, :final values) => _FoodChange(
          FoodAction.product,
          [product],
          product: values,
        ),
        FoodImportPurchase(:final purchase, :final values) => _FoodChange(
          FoodAction.purchase,
          [purchase],
          purchase: values,
        ),
        FoodImportLink(:final containers, :final purchase) => _FoodChange(
          FoodAction.link,
          containers,
          link: {'purchase': purchase},
        ),
        FoodImportCreate(
          :final containers,
          :final details,
          :final product,
          :final purchase,
        ) =>
          _FoodChange(
            FoodAction.add,
            containers,
            details: details,
            contents: const Contents.fraction(1, 1),
            link: {'product': product, 'purchase': purchase},
          ),
      },
  ];

  FoodPurchaseImportReport _inspectPurchaseImport(FoodPurchaseImportPlan plan) {
    _checkImportWriter();
    if (plan.space != space) {
      throw const FormatException('Import workspace differs.');
    }
    if (hasPreparedAppend || pendingReferences > 0) {
      throw const FormatException('Recover or sync Food before importing.');
    }
    for (final action in unified!.snapshot.records) {
      final proof = action.provenance;
      if (proof?['kind'] == 'food.purchase-import' &&
          proof?['namespace'] == plan.importId &&
          (proof?['planHash'] != plan.planHash ||
              proof?['sourceSha256'] != plan.sourceSha256)) {
        throw const FormatException(
          'Receipt import plan differs from its immutable original.',
        );
      }
    }
    return _planPurchaseImport(plan).report;
  }

  // Original purchase records are durable source evidence even after Undo or
  // purchase edits. Never infer attempt identity from mutable product labels.
  ({FoodPurchaseImportReport report, List<FoodImportStep> steps})
  _planPurchaseImport(FoodPurchaseImportPlan plan) => planFoodPurchaseImport(
    state,
    plan,
    recordedPurchases: FoodCatalog.build(
      _records
          .where((r) => r.operation.action == FoodAction.purchase)
          .map((r) => r.operation)
          .toList()
        ..sort(compareFoodOperations),
    ).purchases,
  );

  /// Validates a reviewed receipt plan against current Food without writing.
  Future<FoodPurchaseImportReport> dryRunPurchaseImport(
    FoodPurchaseImportPlan plan,
  ) => _queue(() async {
    late FoodPurchaseImportReport report;
    await _freshCommandLocked(() {
      report = _inspectPurchaseImport(plan);
      return _purchaseImportChanges(_planPurchaseImport(plan).steps);
    }, validateOnly: true);
    return report;
  });

  /// Records every new purchase line as one action. A retry finds its
  /// purchases present and writes nothing.
  Future<FoodPurchaseImportReport> commitPurchaseImport(
    FoodPurchaseImportPlan plan,
  ) => _queue(() async {
    late FoodPurchaseImportReport report;
    await _freshCommandLocked(
      () {
        report = _inspectPurchaseImport(plan);
        return _purchaseImportChanges(_planPurchaseImport(plan).steps);
      },
      provenance: {
        'kind': 'food.purchase-import',
        'namespace': plan.importId,
        'sourceSha256': plan.sourceSha256,
        'planHash': plan.planHash,
      },
    );
    return report;
  });

  /// [canCommit] runs after fresh admission, immediately before the append.
  Future<List<FoodRecord>> remove(
    List<String> ids, {
    bool Function()? canCommit,
  }) => _command(
    _batches(
      ids,
    ).map((batch) => _FoodChange(FoodAction.remove, batch)).toList(),
    canCommit: canCommit,
  );
  Future<void> restore(
    List<FoodContainer> observed, {
    bool Function()? canCommit,
  }) async {
    _batches(observed.map((item) => item.id).toList());
    final changes = <_FoodChange>[];
    for (final item in observed) {
      final refs = item.deletions.toList();
      for (var i = 0; i < refs.length; i += 1000) {
        changes.add(
          _FoodChange(FoodAction.restore, [
            item.id,
          ], deletes: refs.sublist(i, (i + 1000).clamp(0, refs.length))),
        );
      }
    }
    await _command(changes, canCommit: canCommit);
  }

  /// Container fields of [ids] and product changes of [products], planned
  /// against current Food, as one action and one Undo.
  Future<void> changeDetails(
    List<String> ids,
    FoodDetails details,
    List<String> fields, {
    FoodProductChange products = const FoodProductChange(),
    bool Function()? canCommit,
  }) {
    _batches(ids);
    return _queue(
      () => _freshCommandLocked(
        canCommit: canCommit,
        () => [
          if (fields.isNotEmpty)
            for (final batch in _batches(ids))
              _FoodChange(
                FoodAction.edit,
                batch,
                details: details,
                fields: fields,
              ),
          if (!products.isEmpty)
            ..._productChanges(
              planFoodProductChanges(state, products.roots, products.changes),
            ),
        ],
      ),
    );
  }

  Future<void> changeContents(FoodContainer observed, Contents contents) async {
    final refs = observed.contentsEdits.keys.toList(),
        changes = <_FoodChange>[];
    if (refs.isEmpty) {
      changes.add(
        _FoodChange(FoodAction.edit, [observed.id], contents: contents),
      );
    }
    for (var i = 0; i < refs.length; i += 999) {
      changes.add(
        _FoodChange(
          FoodAction.edit,
          [observed.id],
          contents: contents,
          edits: refs.sublist(i, (i + 999).clamp(0, refs.length)),
          observePreviousEdit: i > 0,
        ),
      );
    }
    await _command(changes);
  }

  Future<void> undoRemovals(List<FoodRecord> removals) => _queue(() async {
    await _refresh();
    final changes = <_FoodChange>[];
    for (final remove in removals) {
      if (!_ownsFood(remove.writer) ||
          remove.operation.action != FoodAction.remove ||
          !isAdmitted(remove)) {
        throw const FormatException(
          'Undo requires an admitted local food removal.',
        );
      }
      changes.add(
        _FoodChange(
          FoodAction.restore,
          remove.operation.targets,
          deletes: [remove.id],
        ),
      );
    }
    await _commandLocked(changes);
  });

  /// Retract exact admitted local contributions without writing old snapshots.
  /// A failed append retains all prepared receipts in [lastPreparedRecords];
  /// callers acknowledge only the exact receipts admitted after read-back.
  /// [canCommit] runs after fresh admission, immediately before the append.
  Future<List<FoodRecord>> undoOperations(
    List<FoodRecord> originals, {
    bool Function()? canCommit,
  }) => _queue(() async {
    await _refresh();
    if (originals.isEmpty ||
        originals.map((r) => r.id).toSet().length != originals.length ||
        originals.length > 10000) {
      throw const FormatException('Choose distinct saved Food operations.');
    }
    for (final original in originals) {
      if (original.space != space ||
          !_ownsFood(original.writer) ||
          original.operation.action == FoodAction.undo ||
          !isAdmitted(original)) {
        throw const FormatException(
          'Undo requires an exact admitted local Food operation.',
        );
      }
    }
    Set<String>? fallbackRetractions;
    bool retracted(String operation) =>
        _stagedFoodAdmission?.hasReadyRetraction(operation) ??
        (fallbackRetractions ??= {
          for (final record in _records)
            if (_readyIds.contains(record.id) &&
                record.operation.action == FoodAction.undo)
              record.operation.retracts!,
        }).contains(operation);
    final changes = [
      for (final original in originals)
        if (!retracted(original.id))
          _FoodChange(
            FoodAction.undo,
            original.operation.targets,
            retracts: original.id,
            productUndo: original.operation.action.productLevel,
          ),
    ];
    // An exact retry after acknowledgement failure is already complete;
    // do not append another inverse or replace the prepared receipt set.
    if (changes.isEmpty) return <FoodRecord>[];
    return _commandLocked(changes, canCommit: canCommit);
  });
  static List<List<String>> _batches(List<String> ids) {
    if (ids.isEmpty || ids.toSet().length != ids.length || ids.length > 10000) {
      throw const FormatException('Invalid food selection.');
    }
    return [
      for (var i = 0; i < ids.length; i += 100)
        ids.sublist(i, (i + 100).clamp(0, ids.length)),
    ];
  }
}

class _FoodChange {
  _FoodChange(
    this.action,
    this.targets, {
    this.details,
    this.contents,
    this.createdAt,
    this.fields,
    this.deletes = const [],
    this.edits = const [],
    this.observePreviousEdit = false,
    this.retracts,
    this.product,
    this.purchase,
    this.link,
    this.into,
    this.productUndo = false,
  });
  final FoodAction action;
  final List<String> targets;
  final FoodDetails? details;
  final Contents? contents;
  final String? createdAt;
  final List<String>? fields;
  final List<String> deletes, edits;
  final bool observePreviousEdit;
  final String? retracts;
  final Map<String, Object?>? product, purchase, link;
  final String? into;

  /// Undo of a product-level operation carries no container basis.
  final bool productUndo;
}

class _EmptyFoodPlan implements Exception {
  const _EmptyFoodPlan();
}
