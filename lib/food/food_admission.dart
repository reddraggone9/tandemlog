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
              !r.operation.targets.every(targetSets[basis.id]!.contains))) {
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
  return FoodAdmission(
    projectFood(operations, legacyOwners: legacyOwners),
    births,
    ready,
  );
}

class FoodAdmission {
  FoodAdmission(
    this.state,
    Map<String, FoodRecord> births,
    Set<String> readyIds,
  ) : births = Map.unmodifiable(births),
      readyIds = Set.unmodifiable(readyIds);
  final FoodState state;
  final Map<String, FoodRecord> births;
  final Set<String> readyIds;
}
