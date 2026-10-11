import '../food/food_record.dart';
import '../food/inventory.dart';

class FoodUndoEntry {
  FoodUndoEntry(this.verb, Iterable<FoodRecord> receipts)
    : records = List.unmodifiable(receipts);

  final String verb;
  final List<FoodRecord> records;
  String get label {
    final count = records.expand((r) => r.operation.targets).toSet().length;
    return '$verb $count container${count == 1 ? '' : 's'}';
  }
}

/// Session-local action receipts; Food transport owns preparation/confirmation.
/// Navigation and notifications do not affect history. Workspace changes do.
class FoodUndoHistory {
  static const capacity = 50;
  String? _workspace;
  final _entries = <FoodUndoEntry>[];
  FoodUndoEntry? get latest => _entries.lastOrNull;
  int get length => _entries.length;

  void setWorkspace(String workspace) {
    if (_workspace == workspace) return;
    _entries.clear();
    _workspace = workspace;
  }

  void record(
    String verb,
    Iterable<FoodRecord> receipts, {
    required bool Function(FoodRecord) confirmed,
  }) {
    final records = receipts.toList();
    if (records.isEmpty) return;
    if (_workspace == null || !records.every(confirmed)) {
      throw StateError('Food Undo requires a workspace and confirmed action.');
    }
    final first = records.first;
    if (records.any(
          (r) =>
              r.space != first.space ||
              r.writer != first.writer ||
              r.operation.action == FoodAction.undo,
        ) ||
        records.map((r) => r.id).toSet().length != records.length) {
      throw StateError('Food Undo receipts must belong to one local action.');
    }
    final ids = records.map((r) => r.id).toSet();
    for (final entry in _entries) {
      if (entry.records.any((r) => ids.contains(r.id))) {
        final same =
            entry.records.length == records.length &&
            records.every(
              (r) => entry.records.any(
                (old) => old.id == r.id && old.hash == r.hash,
              ),
            );
        if (same) return;
        throw StateError('Food Undo action receipts disagree.');
      }
    }
    _entries.add(FoodUndoEntry(verb, records));
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  // Called only after the complete exact inverse is admitted. A failed or
  // partial inverse retains this entry until transport recovery confirms it.
  void complete(FoodUndoEntry entry) {
    if (!identical(latest, entry)) {
      throw StateError('The Food Undo action changed.');
    }
    _entries.removeLast();
  }

  void clear() {
    _entries.clear();
    _workspace = null;
  }
}
