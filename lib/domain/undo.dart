/// Immutable pre-append receipt. An uncertain append is confirmed only when
/// the canonical cache contains these exact bytes, never just a reused ID.
class OperationReceipt {
  final String id, raw, entity;
  const OperationReceipt(this.id, this.raw, this.entity);
}

const reversibleTaskEvents = {
  'task.edited',
  'task.moved',
  'task.deleted',
  'task.completed',
  'task.completionUndone',
};

class TaskUndoResult {
  final List<String> undone, remaining;
  final bool keptNewerChanges;
  final Object? error;
  TaskUndoResult(
    Iterable<String> undone,
    Iterable<String> remaining,
    this.keptNewerChanges, [
    this.error,
  ]) : undone = List.unmodifiable(undone),
       remaining = List.unmodifiable(remaining);
}
