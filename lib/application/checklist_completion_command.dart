import '../domain/event.dart';
import '../storage/task_store.dart';

/// Completion UI observes a refreshed checklist before preparing durable bytes.
class ChecklistCompletionCommand {
  const ChecklistCompletionCommand(this.store);
  final TaskStore store;

  Future<LogEvent?> complete(
    String entity, {
    required DateTime completionInstant,
    required String? localZoneId,
    required Future<bool> Function(List<Map<String, dynamic>> items)
    confirmUnfinished,
    void Function(OperationReceipt)? onPrepared,
  }) => store.complete(
    entity,
    completionInstant: completionInstant,
    localZoneId: localZoneId,
    onPrepared: onPrepared,
  );
}
