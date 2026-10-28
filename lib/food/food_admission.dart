import '../domain/event.dart' show EventClock;
import 'food_record.dart';
import 'inventory.dart';

/// Complete semantic admission shared by legacy and unified storage. Unknown
/// dependencies stay pending; a transport's physical order never admits them.
FoodAdmission admitFoodRecords(
  List<FoodRecord> records, {
  int maximumContainers = 100000,
  Map<String, String> legacyOwners = const {},
}) {
  final byId = {for (final r in records) r.id: r};
  final targetSets = {
    for (final r in records) r.id: r.operation.targets.toSet(),
  };
  final births = <String, FoodRecord>{};
  for (final record in records) {
    if (record.operation.action != FoodAction.add) continue;
    for (final id in record.operation.targets) {
      if (births.containsKey(id)) {
        throw const FormatException(
          'A physical food container has different creation records.',
        );
      }
      births[id] = record;
    }
    if (births.length > maximumContainers) {
      throw const FormatException('Too many food containers.');
    }
  }
  final dependencies = <String, List<String>>{};
  for (final r in records) {
    final refs = <String>{
      ...r.createdWith.values,
      ...r.operation.observedDeletes,
      ...r.operation.observedEdits,
      if (r.operation.retracts != null) r.operation.retracts!,
    };
    _validateReferences(r, byId, targetSets, births, legacyOwners);
    dependencies[r.id] = refs.toList();
  }
  final ordered = records.toList()
    ..sort((a, b) {
      final clock = a.clock.compareTo(b.clock);
      if (clock != 0) return clock;
      final writer = a.writer.compareTo(b.writer);
      return writer != 0 ? writer : a.sequence.compareTo(b.sequence);
    });
  final ready = <String>{}, operations = <FoodOperation>[];
  for (final r in ordered) {
    if (dependencies[r.id]!.every(ready.contains)) {
      ready.add(r.id);
      operations.add(r.operation);
    }
  }
  return FoodAdmission._(
    projectFood(operations, legacyOwners: legacyOwners),
    births,
    ready,
    ready.length == byId.length
        ? _FoodAdmissionIndex(records, legacyOwners, maximumContainers)
        : null,
  );
}

void _validateReferences(
  FoodRecord r,
  Map<String, FoodRecord> byId,
  Map<String, Set<String>> targetSets,
  Map<String, FoodRecord> births,
  Map<String, String> legacyOwners,
) {
  if (r.operation.action == FoodAction.undo) {
    final basis = byId[r.operation.retracts];
    if (basis != null &&
        (basis.operation.action == FoodAction.undo ||
            (basis.writer != r.writer &&
                !(r.unified &&
                    r.operation.undoOwner == r.writer &&
                    legacyOwners[basis.writer] == r.writer)) ||
            basis.sequence >= r.sequence ||
            basis.clock >= r.clock ||
            basis.operation.targets.length != r.operation.targets.length ||
            !r.operation.targets.every(targetSets[basis.id]!.contains) ||
            (basis.operation.action.productLevel
                ? r.createdWith.isNotEmpty
                : r.createdWith.length != r.operation.targets.length))) {
      throw const FormatException(
        'Food Undo reference has wrong kind, writer, targets or clock.',
      );
    }
  }
  for (final entry in r.createdWith.entries) {
    final basis = byId[entry.value];
    if (basis != null &&
        (basis.operation.action != FoodAction.add ||
            !targetSets[basis.id]!.contains(entry.key) ||
            basis.clock >= r.clock ||
            births[entry.key]?.id != basis.id)) {
      throw const FormatException('Food target creation basis is invalid.');
    }
  }
  for (final (refs, kind) in [
    (r.operation.observedDeletes, FoodAction.remove),
    (r.operation.observedEdits, FoodAction.edit),
  ]) {
    for (final ref in refs) {
      final basis = byId[ref];
      if (basis == null) continue;
      if (basis.operation.action != kind ||
          basis.clock >= r.clock ||
          !r.operation.targets.every(targetSets[basis.id]!.contains) ||
          (kind == FoodAction.edit && basis.operation.contents == null)) {
        throw const FormatException(
          'Food observed reference has wrong kind, target or clock.',
        );
      }
    }
  }
}

class _FoodAdmissionIndex {
  _FoodAdmissionIndex(
    List<FoodRecord> records,
    Map<String, String> owners,
    this.maximumContainers,
  ) : legacyOwners = Map.unmodifiable(owners),
      byId = Map.unmodifiable({for (final r in records) r.id: r}),
      targets = Map.unmodifiable({
        for (final r in records)
          r.id: Set<String>.unmodifiable(r.operation.targets),
      }),
      byTarget = _indexTargets(records),
      retracted = Set.unmodifiable({
        for (final record in records)
          if (record.operation.action == FoodAction.undo)
            record.operation.retracts!,
      }),
      productRecords = List.unmodifiable(
        records.where((r) => r.operation.action.productLevel),
      ),
      maximumClock = records.isEmpty
          ? null
          : records.map((r) => r.clock).reduce((a, b) => a > b ? a : b);
  _FoodAdmissionIndex._updated(
    Map<String, FoodRecord> records,
    Map<String, Set<String>> targetSets,
    Map<String, List<FoodRecord>> histories,
    this.maximumClock,
    _FoodAdmissionIndex context,
    this.retracted,
    this.productRecords,
  ) : legacyOwners = context.legacyOwners,
      maximumContainers = context.maximumContainers,
      byId = Map.unmodifiable(records),
      targets = Map.unmodifiable(targetSets),
      byTarget = Map.unmodifiable(histories);
  final Map<String, String> legacyOwners;
  final int maximumContainers;
  final Map<String, FoodRecord> byId;
  final Map<String, Set<String>> targets;
  final Map<String, List<FoodRecord>> byTarget;
  final Set<String> retracted;

  /// Product-level records, for refolding the catalog after product changes.
  final List<FoodRecord> productRecords;
  final EventClock? maximumClock;
  static Map<String, List<FoodRecord>> _indexTargets(List<FoodRecord> records) {
    final result = <String, List<FoodRecord>>{};
    for (final r in records) {
      for (final target in r.operation.targets) {
        (result[target] ??= []).add(r);
      }
    }
    return Map.unmodifiable(
      result.map(
        (key, value) => MapEntry(key, List<FoodRecord>.unmodifiable(value)),
      ),
    );
  }
}

/// Reuse only a fully admitted immutable base. New records cannot retroactively
/// resolve pending old dependencies. Keep original bulk target sets in every
/// validation and affected-container projection.
FoodAdmission? appendReadyFoodRecords(
  FoodAdmission base,
  List<FoodRecord> delta, {
  int maximumContainers = 100000,
  Map<String, String> legacyOwners = const {},
}) {
  final index = base._index;
  if (index == null ||
      base.readyIds.length != index.byId.length ||
      maximumContainers != index.maximumContainers ||
      legacyOwners.length != index.legacyOwners.length ||
      legacyOwners.entries.any((e) => index.legacyOwners[e.key] != e.value)) {
    return null;
  }
  if (delta.any((r) => index.byId.containsKey(r.id))) {
    throw const FormatException('Food append reuses an operation identity.');
  }
  if (delta.isEmpty) return base;
  if (index.maximumClock != null &&
      delta.any((r) => r.clock <= index.maximumClock!)) {
    return null;
  }
  final byId = Map<String, FoodRecord>.of(index.byId);
  final targets = Map<String, Set<String>>.of(index.targets);
  final births = Map<String, FoodRecord>.of(base.births);
  final byTarget = Map<String, List<FoodRecord>>.of(index.byTarget);
  final affected = <String>{};
  for (final record in delta) {
    record.operation.validate();
    if (byId.containsKey(record.id)) {
      throw const FormatException('Food append reuses an operation identity.');
    }
    byId[record.id] = record;
    targets[record.id] = record.operation.targets.toSet();
    affected.addAll(record.operation.targets);
    if (record.operation.action == FoodAction.add) {
      for (final target in record.operation.targets) {
        if (births.containsKey(target)) {
          throw const FormatException(
            'A physical food container has different creation records.',
          );
        }
        births[target] = record;
      }
      if (births.length > maximumContainers) {
        throw const FormatException('Too many food containers.');
      }
    }
  }
  final ready = Set<String>.of(base.readyIds);
  final ordered = delta.toList()
    ..sort((a, b) {
      final clock = a.clock.compareTo(b.clock);
      return clock != 0 ? clock : a.id.compareTo(b.id);
    });
  for (final r in ordered) {
    _validateReferences(r, byId, targets, births, legacyOwners);
    final refs = {
      ...r.createdWith.values,
      ...r.operation.observedDeletes,
      ...r.operation.observedEdits,
      if (r.operation.retracts != null) r.operation.retracts!,
    };
    if (!refs.every(ready.contains)) return null;
    ready.add(r.id);
  }
  for (final target in affected) {
    byTarget[target] = List.unmodifiable([
      ...?index.byTarget[target],
      ...delta.where((r) => r.operation.targets.contains(target)),
    ]);
  }
  final history = <String, FoodOperation>{};
  for (final target in affected) {
    for (final record in byTarget[target]!) {
      history[record.id] = record.operation;
    }
  }
  final newRetractions = {
    for (final record in ordered)
      if (record.operation.action == FoodAction.undo)
        record.operation.retracts!,
  };
  final retracted = newRetractions.isEmpty
      ? index.retracted
      : Set<String>.unmodifiable({...index.retracted, ...newRetractions});
  final productChange = ordered.any(
    (r) =>
        r.operation.action.productLevel ||
        (r.operation.action == FoodAction.undo &&
            byId[r.operation.retracts]!.operation.action.productLevel),
  );
  final productRecords = !productChange
      ? index.productRecords
      : List<FoodRecord>.unmodifiable([
          ...index.productRecords,
          ...ordered.where((r) => r.operation.action.productLevel),
        ]);
  // A product-level change refolds the (small) product catalog and re-resolves
  // every container's product; container-only changes reuse both.
  final catalog = !productChange
      ? base.state.catalog
      : FoodCatalog.build(
          productRecords
              .where((r) => !retracted.contains(r.id))
              .map((r) => r.operation)
              .toList()
            ..sort(compareFoodOperations),
        );
  final changed = projectFood(
    history.values,
    legacyOwners: legacyOwners,
    catalog: catalog,
  );
  final containers = productChange
      ? [
          for (final c in base.state.containers)
            if (!affected.contains(c.id)) c.withCatalog(catalog),
          ...changed.containers.where((c) => affected.contains(c.id)),
        ]
      : [
          ...base.state.containers.where((c) => !affected.contains(c.id)),
          ...changed.containers.where((c) => affected.contains(c.id)),
        ];
  containers.sort((a, b) => a.id.compareTo(b.id));
  return FoodAdmission._(
    FoodState(containers, catalog: catalog),
    births,
    ready,
    _FoodAdmissionIndex._updated(
      byId,
      targets,
      byTarget,
      ordered.last.clock,
      index,
      retracted,
      productRecords,
    ),
  );
}

class FoodAdmission {
  FoodAdmission(
    FoodState state,
    Map<String, FoodRecord> births,
    Set<String> readyIds,
  ) : this._(state, births, readyIds, null);

  FoodAdmission._(
    this.state,
    Map<String, FoodRecord> births,
    Set<String> readyIds,
    this._index,
  ) : births = Map.unmodifiable(births),
      readyIds = Set.unmodifiable(readyIds);
  final _FoodAdmissionIndex? _index;
  final FoodState state;
  final Map<String, FoodRecord> births;
  final Set<String> readyIds;

  /// Null means the full ready index is unavailable; callers retain their
  /// existing ready-record fallback. Hash identity is the semantic reference
  /// hash, including sealed imported records whose integrity hash differs.
  bool? confirmsReadyRecord(FoodRecord record) {
    final index = _index;
    if (index == null) return null;
    return readyIds.contains(record.id) &&
        index.byId[record.id]?.hash == record.hash;
  }

  /// Only a fully ready canonical graph can certify an existing retraction.
  bool? hasReadyRetraction(String operation) =>
      _index?.retracted.contains(operation);
}
