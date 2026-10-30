import '../domain/event_clock.dart';
import '../storage/unified_history.dart';

/// Read-only derived view. No store open, replay, clock repair or canonical write.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.writer,
    required this.device,
    required this.clock,
    required this.sequence,
    required this.stream,
    required this.types,
    required this.targets,
    required this.historical,
  });
  final String id, writer, device, stream;
  final EventClock clock;
  final int sequence;
  final List<String> types, targets;
  final bool historical;

  String get summary => types.map(activityLabel).toSet().join(', ');

  DateTime get recordedAt => DateTime.fromMicrosecondsSinceEpoch(
    (clock.value ~/ BigInt.from(1000)).toInt(),
    isUtc: true,
  );
}

List<ActivityEntry> activityEntries(UnifiedSnapshot snapshot) {
  // deviceLabel scans history; index labels once, not once per activity.
  final names = <String, String>{};
  for (final r in snapshot.records) {
    if (r.sequence <= (snapshot.published[r.writer] ?? 0) &&
        r.effects.length == 1 &&
        r.effect.kind == 'writer.named') {
      if (r.effect.name == null) {
        names.remove(r.writer);
      } else {
        names[r.writer] = r.effect.name!;
      }
    }
  }
  final result = <ActivityEntry>[];
  for (final r in snapshot.records) {
    if (r.sequence > (snapshot.published[r.writer] ?? 0)) continue;
    final data = r.effects.where((e) => e.isData).toList();
    final historical = r.historical;
    // Historical envelopes have one effect; its author is the writing device,
    // which can differ from the logical namespace or physical migration owner.
    final writer = historical ? data.single.author : r.writer;
    final types = <String>{};
    final targets = <String>{};
    for (final e in r.effects) {
      types.add(
        e.task?.type ??
            (e.food != null ? 'food.${e.food!.operation.action.name}' : e.kind),
      );
      if (e.task != null) targets.add(e.task!.entity);
      if (e.food != null) targets.addAll(e.food!.operation.targets);
    }
    result.add(
      ActivityEntry(
        id: r.recordId,
        writer: writer,
        stream: historical ? data.single.writer : r.writer,
        device: names[writer] ?? 'Unnamed device · ${writer.substring(0, 8)}',
        clock: historical ? data.single.clock : r.clock,
        sequence: historical ? data.single.sequence : r.sequence,
        types: List.unmodifiable(types),
        targets: List.unmodifiable(targets),
        historical: historical,
      ),
    );
  }
  result.sort((a, b) {
    final time = b.clock.compareTo(a.clock);
    if (time != 0) return time;
    final writer = a.stream.compareTo(b.stream);
    if (writer != 0) return writer;
    final sequence = a.sequence.compareTo(b.sequence);
    return sequence != 0 ? sequence : a.id.compareTo(b.id);
  });
  return List.unmodifiable(result);
}

String activityLabel(String type) => switch (type) {
  'writer.joined' => 'Device joined',
  'writer.named' => 'Device renamed',
  'user.created' => 'User added',
  'user.renamed' => 'User renamed',
  'task.created' || 'task.createdWithText' => 'Task added',
  'task.completed' ||
  'task.completedWithText' ||
  'task.completedKeepingSuccessor' ||
  'task.completedWithChecklist' => 'Task completed',
  'task.reopened' => 'Task reopened',
  'task.deleted' => 'Task deleted',
  'task.moved' => 'Task reordered',
  'task.textEdited' || 'task.edited' => 'Task edited',
  'task.textEditUndone' ||
  'text.compensate' ||
  'task.undo' ||
  'task.operationUndone' ||
  'task.completionUndone' ||
  'task.recurringCompletionUndone' ||
  'task.deletionUndone' => 'Task change undone',
  'text.baselineInitialized' => 'Shared text initialized',
  'food.add' => 'Food added',
  'food.edit' => 'Food edited',
  'food.remove' => 'Food removed',
  'food.restore' => 'Food restored',
  'food.undo' => 'Food change undone',
  'food.product' => 'Product changed',
  'food.merge' => 'Products merged',
  'food.purchase' => 'Purchase recorded',
  'food.purchaseEdit' => 'Purchase edited',
  'food.link' => 'Food linked to product',
  _ when type.startsWith('checklist.') => 'Checklist changed',
  _ when type.startsWith('food.') => 'Food changed',
  _ when type.startsWith('task.') => 'Task changed',
  _ => 'Workspace changed',
};
