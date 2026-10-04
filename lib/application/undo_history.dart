import '../domain/undo.dart';

class UndoEntry {
  final String verb;
  final Map<String, String> entities = {};
  String get label {
    final n = operations.map((id) => entities[id]).toSet().length;
    return "$verb $n ${n == 1 ? 'task' : 'tasks'}";
  }

  final Object? group;
  final Set<String> operations = {};
  final List<OperationReceipt> pending = [];
  UndoEntry(this.verb, this.group);
}

/// Process-local history. Transport/storage owns confirmation, and a workspace
/// switch clears it. Snackbar lifetime has no relationship to these entries.
class SessionUndoHistory {
  static const capacity = 50;
  final List<UndoEntry> _entries = [];
  Set<String> get retainedOperationIds => Set.unmodifiable({
    for (final entry in _entries) ...entry.operations,
    for (final entry in _entries) ...entry.pending.map((receipt) => receipt.id),
  });
  UndoEntry? get latest =>
      _entries.where((e) => e.operations.isNotEmpty).lastOrNull;
  void record(
    String label,
    Iterable<OperationReceipt> receipts, {
    Object? group,
  }) {
    if (receipts.isEmpty) return;
    final entry =
        group != null && _entries.isNotEmpty && _entries.last.group == group
        ? _entries.last
        : UndoEntry(label, group);
    if (_entries.isEmpty || !identical(_entries.last, entry)) {
      _entries.add(entry);
    }
    for (final r in receipts) {
      entry.entities[r.id] = r.entity;
    }
    final pending = {for (final r in entry.pending) (r.id, r.raw)};
    entry.pending.addAll(
      receipts.where(
        (r) => !entry.operations.contains(r.id) && pending.add((r.id, r.raw)),
      ),
    );
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }

  void reconcile(Set<String> Function(Iterable<OperationReceipt>) confirm) {
    for (final entry in _entries) {
      final confirmed = confirm(entry.pending);
      entry.operations.addAll(confirmed);
      entry.pending.removeWhere((r) => confirmed.contains(r.id));
    }
  }

  void acknowledge(UndoEntry entry, Iterable<String> operations) {
    entry.operations.removeAll(operations);
    if (entry.operations.isEmpty && entry.pending.isEmpty) {
      _entries.remove(entry);
    }
  }

  void clear() => _entries.clear();
}
