import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keep a task's standard popup actions current while incoming items arrive.
/// Grouping the entries lets the popup relayout when Add checklist disappears.
class TaskActionsMenuEntry extends PopupMenuEntry<String> {
  const TaskActionsMenuEntry({
    super.key,
    required this.viewRevision,
    required this.canAddChecklist,
  });

  final ValueListenable<int> viewRevision;
  final bool Function() canAddChecklist;

  // showMenu uses this estimate only for initial-value alignment; this menu
  // has no initial selection, and its actual child size is measured on layout.
  @override
  double get height => 2 * kMinInteractiveDimension;

  @override
  bool represents(String? value) => value == 'checklist' || value == 'delete';

  @override
  State<TaskActionsMenuEntry> createState() => _TaskActionsMenuEntryState();
}

class _TaskActionsMenuEntryState extends State<TaskActionsMenuEntry> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: widget.viewRevision,
    builder: (_, _, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canAddChecklist())
          const PopupMenuItem<String>(
            key: ValueKey('task-action-add-checklist'),
            value: 'checklist',
            child: Text('Add checklist'),
          ),
        const PopupMenuItem<String>(
          key: ValueKey('task-action-delete'),
          value: 'delete',
          child: Text('Delete task'),
        ),
      ],
    ),
  );
}
