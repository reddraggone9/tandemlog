import 'dart:convert';

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
  }) async {
    while (true) {
      await store.refresh();
      final task = store.currentTextRow(entity);
      if (task == null || task['completed'] == true) return null;
      if (task['kind'] != 'task') {
        throw FormatFailure('Only a task can be completed.');
      }
      final items = List<Map<String, dynamic>>.unmodifiable(
        (task['checklist'] as List? ?? []).map(
          (item) => Map<String, dynamic>.unmodifiable(item as Map),
        ),
      );
      final snapshot = jsonEncode(task['checklist'] ?? []);
      if (items.any((item) => item['completed'] != true) &&
          !await confirmUnfinished(items)) {
        return null;
      }
      await store.refresh();
      final current = store.currentTextRow(entity);
      if (current == null || current['completed'] == true) return null;
      if (jsonEncode(current['checklist'] ?? []) != snapshot) continue;
      // Commands reconcile again. A changed item snapshot invalidates this
      // consent before any receipt; the next iteration observes it afresh.
      try {
        return await store.complete(
          entity,
          completionInstant: completionInstant,
          localZoneId: localZoneId,
          expectedChecklistSnapshot: snapshot,
          requireIncomplete: true,
          onPrepared: onPrepared,
        );
      } on StaleTaskSnapshot {
        continue;
      }
    }
  }
}
