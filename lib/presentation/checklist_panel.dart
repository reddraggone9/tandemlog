import 'package:flutter/material.dart';

class ChecklistPanel extends StatelessWidget {
  const ChecklistPanel({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onMove,
    required this.onDelete,
    this.enabled = true,
  });
  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>, String?) onMove;
  final void Function(Map<String, dynamic>) onDelete;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text('Checklist', style: Theme.of(context).textTheme.titleSmall),
          Text(
            '${items.where((item) => item['completed'] == true).length}/${items.length}',
            semanticsLabel:
                '${items.where((item) => item['completed'] == true).length} of ${items.length} checklist items complete',
          ),
          TextButton.icon(
            key: const Key('checklist-add'),
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      ),
      Text(
        'Items save separately.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (var index = 0; index < items.length; index++) _row(context, index),
    ],
  );

  Widget _row(BuildContext context, int index) {
    final item = items[index];
    final id = item['id'] as String;
    final title = item['title'] as String? ?? '';
    final notes = item['description'] as String? ?? '';
    final completed = item['completed'] == true;
    final beforeUp = index > 0 ? items[index - 1]['id'] as String : null;
    final beforeDown = index + 2 < items.length
        ? items[index + 2]['id'] as String
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${completed ? 'Reopen' : 'Complete'} checklist item: $title',
          checked: completed,
          enabled: enabled,
          onTap: enabled ? () => onToggle(item, !completed) : null,
          child: ExcludeSemantics(
            child: SizedBox(
              width: 48,
              height: 48,
              child: Checkbox(
                key: Key('checklist-check-$id'),
                value: completed,
                onChanged: enabled ? (value) => onToggle(item, value!) : null,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                key: Key('checklist-edit-$id'),
                onPressed: enabled ? () => onEdit(item) : null,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  minimumSize: const Size(0, 48),
                ),
                child: Text(
                  title,
                  semanticsLabel: 'Edit checklist item: $title',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: PopupMenuButton<String>(
            key: Key('checklist-menu-$id'),
            enabled: enabled,
            tooltip: 'Actions for checklist item: $title',
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  onEdit(item);
                case 'up':
                  onMove(item, beforeUp);
                case 'down':
                  onMove(item, beforeDown);
                case 'delete':
                  onDelete(item);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'up',
                enabled: index > 0,
                child: const Text('Move up'),
              ),
              PopupMenuItem(
                value: 'down',
                enabled: index + 1 < items.length,
                child: const Text('Move down'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ],
    );
  }
}
