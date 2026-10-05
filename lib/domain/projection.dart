import 'event.dart';

/// A completion embeds the single authoritative seed for a derived occurrence.
/// This is a materialized creation only; never append it to canonical history.
LogEvent successorCreation(LogEvent completion) {
  final snapshot = completion.data['successor'] as Map<String, dynamic>;
  final id = snapshot['id'] as String;
  final data = Map<String, dynamic>.from(snapshot)..remove('id');
  data['tagOrigin'] = id;
  return LogEvent(
    completion.space,
    completion.writer,
    completion.sequence,
    completion.clock,
    id,
    'task.created',
    data,
  );
}

/// Minimal input used by both SQLite materialization and standalone exporters.
/// Callers provide actions in canonical event order (clock, writer, sequence).
class OrderAction {
  final String entity, type;
  final String? before, successor;
  const OrderAction(this.entity, this.type, {this.before, this.successor});
  factory OrderAction.fromEvent(LogEvent event) => OrderAction(
    event.entity,
    event.type,
    before: event.data['before'] as String?,
    successor: (event.data['successor'] as Map?)?['id'] as String?,
  );
}

List<String> projectOrder(
  Iterable<String> availableInCreationOrder,
  Iterable<OrderAction> actions,
) {
  final available = availableInCreationOrder.toSet();
  final ordered = <String>[];
  final pending = <(String, String?)>[];
  final seeded = <String>{};
  bool move(String entity, String? before) {
    if (!ordered.contains(entity) ||
        (before != null && !ordered.contains(before))) {
      return false;
    }
    ordered.remove(entity);
    ordered.insert(
      before == null ? ordered.length : ordered.indexOf(before),
      entity,
    );
    return true;
  }

  void settlePending() =>
      pending.removeWhere((action) => move(action.$1, action.$2));
  for (final action in actions) {
    if (isTaskCompletion(action.type)) {
      final next = action.successor;
      if (next == null || !seeded.add(next) || !available.contains(next)) {
        continue;
      }
      if (!ordered.contains(next)) ordered.add(next);
      if (!move(next, action.entity)) pending.add((next, action.entity));
      settlePending();
    } else if (action.type == 'task.moved') {
      if (!move(action.entity, action.before)) {
        pending.add((action.entity, action.before));
      }
    } else if ((action.type == 'task.created' ||
            action.type == 'task.createdWithText' ||
            action.type == 'user.created') &&
        available.contains(action.entity) &&
        !ordered.contains(action.entity)) {
      ordered.add(action.entity);
      settlePending();
    }
  }
  for (final id in available) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  settlePending();
  return ordered;
}

/// Cleanup only retracts an untouched proposal. Any independent history or
/// anchor dependency preserves its original seed, including late arrivals.
class SuccessorSelection {
  final LogEvent seed;
  final bool suppressed;
  const SuccessorSelection(this.seed, this.suppressed);
}

SuccessorSelection selectSuccessor(
  List<LogEvent> seeds,
  Iterable<LogEvent> parentHistory, {
  required bool protected,
}) {
  seeds.sort(compareEvents);
  if (protected) return SuccessorSelection(seeds.first, false);
  final cancelled = parentHistory
      .where((e) => e.type == 'task.recurringCompletionUndone')
      .map((e) => e.data['completion'])
      .toSet();
  final surviving = seeds.where((e) => !cancelled.contains(e.id));
  return surviving.isEmpty
      ? SuccessorSelection(seeds.first, true)
      : SuccessorSelection(surviving.first, false);
}
