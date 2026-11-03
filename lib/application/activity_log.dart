import '../domain/event_clock.dart';
import '../storage/unified_history.dart';
import '../storage/unified_record.dart';

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
    this.deviceNamed = true,
    this.positions,
    this.containers,
  });

  /// One change inside a batched record: the effects at [positions] (1-based)
  /// and, for a split food operation, only its [containers].
  ActivityEntry part({
    required Set<int> positions,
    required List<String> types,
    required List<String> targets,
    Set<String>? containers,
  }) => ActivityEntry(
    id: id,
    writer: writer,
    device: device,
    deviceNamed: deviceNamed,
    clock: clock,
    sequence: sequence,
    stream: stream,
    types: List.unmodifiable(types),
    targets: List.unmodifiable(targets),
    historical: historical,
    positions: Set.unmodifiable(positions),
    containers: containers == null ? null : Set.unmodifiable(containers),
  );

  /// Null for a whole record.
  final Set<int>? positions;
  final Set<String>? containers;

  /// Unique per row: the record, or the record and this part's effects.
  String get key => positions == null
      ? id
      : '$id#${(positions!.toList()..sort()).join(',')}'
            '${containers == null ? '' : '@${(containers!.toList()..sort()).join(',')}'}';
  final String id, writer, device, stream;

  /// Unnamed devices are identified only by their installation ID.
  final bool deviceNamed;
  final EventClock clock;
  final int sequence;
  final List<String> types, targets;
  final bool historical;

  String get summary {
    final labels = types.map(activityLabel).toSet();
    // Capture's positioning effect is not a second user action.
    if (labels.contains('Task added')) labels.remove('Task reordered');
    // Nor is the product or purchase a food add or link records with it.
    if (labels.contains('Food added') ||
        labels.contains('Food linked to product')) {
      labels.removeAll(const ['Product changed', 'Purchase recorded']);
    }
    if (labels.contains('Food added')) labels.remove('Food linked to product');
    return labels.join(', ');
  }

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
    final types = <String>{for (final e in r.effects) activityEffectType(e)};
    final targets = activityTargets(r.effects);
    // Shared-text setup is bookkeeping, not something a person did.
    if (types.every((type) => type == 'text.baselineInitialized')) continue;
    result.add(
      ActivityEntry(
        id: r.recordId,
        writer: writer,
        stream: historical ? data.single.writer : r.writer,
        device: names[writer] ?? 'Unnamed device · ${writer.substring(0, 8)}',
        deviceNamed: names.containsKey(writer),
        clock: historical ? data.single.clock : r.clock,
        sequence: historical ? data.single.sequence : r.sequence,
        types: List.unmodifiable(types),
        targets: targets,
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

/// `6 foods added` for [n] parts labelled [label] (`Food added`).
String activityCount(String label, int n) {
  if (label.contains(', ')) return '$n changes';
  final special = switch (label) {
    'Food location changed' => 'foods moved',
    'Food linked to product' => 'foods linked to products',
    'Food change undone' => 'food changes undone',
    'Task change undone' => 'task changes undone',
    'Products merged' => 'product merges',
    'Purchase recorded' => 'purchases recorded',
    _ => null,
  };
  if (special != null) return '$n $special';
  final space = label.indexOf(' ');
  if (space < 0) return '$n ${label.toLowerCase()}';
  return '$n ${label.substring(0, space).toLowerCase()}s'
      '${label.substring(space)}';
}

String activityEffectType(UnifiedEffect e) {
  final food = e.food?.operation;
  if (food == null) return e.task?.type ?? e.kind;
  return food.action.name == 'edit' &&
          food.fields.length == 1 &&
          food.fields.single == 'location'
      ? 'food.location'
      : 'food.${food.action.name}';
}

/// The items a change is about: tasks and food containers. Products and
/// purchases count only when nothing else was changed.
List<String> activityTargets(
  Iterable<UnifiedEffect> effects, {
  Set<String>? containers,
}) {
  final items = <String>{}, products = <String>{};
  for (final e in effects) {
    if (e.task != null) items.add(e.task!.entity);
    final op = e.food?.operation;
    if (op == null) continue;
    if (op.action.productLevel) {
      products.addAll(op.targets);
    } else {
      items.addAll(
        containers == null ? op.targets : op.targets.where(containers.contains),
      );
    }
  }
  return List.unmodifiable(items.isEmpty ? products : items);
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
  'food.location' => 'Food location changed',
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
