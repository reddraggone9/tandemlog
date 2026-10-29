import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/agent/registry.dart';

/// Every store write the app's UI calls has an agent command (design
/// agent-interface.md section 8). A new UI write without a mapping fails here.
const storeFiles = [
  'lib/storage/task_store.dart',
  'lib/storage/checklist_store.dart',
  'lib/food/food_store.dart',
  'lib/storage/unified_history.dart',
];
const uiFiles = [
  'lib/main.dart',
  'lib/food/food_page.dart',
  'lib/food/food_editor.dart',
];

/// Store method → agent commands that cover it.
const covered = {
  'createTasks': ['tasks add'],
  'complete': ['tasks complete'],
  'reopen': ['tasks reopen'],
  'deleteTask': ['tasks delete'],
  'deleteTasks': ['tasks bulk-delete'],
  'edit': ['tasks edit'],
  'editNativeTask': ['tasks edit', 'checklist edit'],
  'bulkEdit': ['tasks bulk-edit'],
  'moveBefore': ['tasks move'],
  'moveBlockBefore': ['tasks bulk-move'],
  'command': ['people add', 'checklist check', 'checklist uncheck'],
  'addChecklistItem': ['checklist add'],
  'setChecklistCompleted': ['checklist check', 'checklist uncheck'],
  'deleteChecklistItem': ['checklist delete'],
  'moveChecklistItem': ['checklist move'],
  'add': ['food add', 'food add-another'],
  'remove': ['food remove'],
  'restore': ['food restore'],
  'changeDetails': ['food edit', 'products set', 'products merge'],
  'commitPurchaseImport': ['purchases import'],
  'undoOperations': ['undo'],
  'undoRemovals': ['undo'],
  'verifyHistory': ['verify'],
};

/// Reads, lifecycle and recovery plumbing, and device-local settings
/// (device name) that the agent interface deliberately excludes.
const excluded = {
  'captureTaskText',
  'close',
  'create',
  'list',
  'read',
  'refresh',
  'recoverPrepared',
  'retryTextOperation',
  'initializeSharedText',
  'migrateOccurrenceDates',
  'renameDevice',
};

void main() {
  test('every UI store write has an agent command', () {
    final methods = <String>{
      for (final f in storeFiles)
        for (final m in RegExp(
          r'^  Future<[^\n]*?> ([a-z][A-Za-z]*)\(',
          multiLine: true,
        ).allMatches(File(f).readAsStringSync()))
          m.group(1)!,
    };
    final used = <String>{
      for (final f in uiFiles)
        for (final m in RegExp(
          r'\.([a-z][A-Za-z]*)\(',
        ).allMatches(File(f).readAsStringSync()))
          if (methods.contains(m.group(1))) m.group(1)!,
    };
    // Guard against a scan that silently matches nothing.
    expect(used.length, greaterThan(15));
    final names = {for (final c in registry) c.name};
    final unmapped = used.difference({...covered.keys, ...excluded});
    expect(unmapped, isEmpty, reason: 'Add agent commands for $unmapped');
    for (final e in covered.entries) {
      expect(
        names.containsAll(e.value),
        isTrue,
        reason: '${e.key}: missing ${e.value.toSet().difference(names)}',
      );
    }
  });
}
