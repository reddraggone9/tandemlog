import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A checklist child drag cannot be mistaken for a parent task drag.
class ChecklistItemDrag {
  ChecklistItemDrag({
    required this.parentId,
    required this.origin,
    required this.revision,
    required this.itemId,
    required List<String> observedOrder,
  }) : observedOrder = List.unmodifiable(observedOrder);
  final String parentId, itemId;
  final Object origin, revision;
  final List<String> observedOrder;
}

class ChecklistPanel extends StatefulWidget {
  const ChecklistPanel({
    super.key,
    required this.parentId,
    required this.origin,
    required this.revision,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onMove,
    required this.onDelete,
    this.enabled = true,
    this.addFocusNode,
  });
  final String parentId;
  final Object origin, revision;
  final FocusNode? addFocusNode;
  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>, String?) onMove;
  final void Function(Map<String, dynamic>) onDelete;
  final bool enabled;

  @override
  State<ChecklistPanel> createState() => _ChecklistPanelState();
}

class _ChecklistPanelState extends State<ChecklistPanel> {
  final _focusNodes = <(String, String), FocusNode>{};
  List<String> get _order =>
      widget.items.map((item) => item['id'] as String).toList();

  FocusNode _focus(String id, String control) =>
      _focusNodes.putIfAbsent((id, control), () {
        final node = FocusNode(debugLabel: 'Checklist $id $control');
        node.addListener(_focusChanged);
        return node;
      });

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ChecklistPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ids = _order.toSet();
      final removed = _focusNodes.keys
          .where((key) => !ids.contains(key.$1))
          .toList();
      for (final key in removed) {
        _focusNodes.remove(key)!.dispose();
      }
    });
  }

  bool _canAccept(ChecklistItemDrag drag, String? before) {
    final order = _order;
    if (!widget.enabled ||
        drag.parentId != widget.parentId ||
        !identical(drag.origin, widget.origin) ||
        drag.revision != widget.revision ||
        !listEquals(drag.observedOrder, order) ||
        order.toSet().length != order.length) {
      return false;
    }
    final index = order.indexOf(drag.itemId);
    if (index < 0 || before == drag.itemId) return false;
    if (before == null) return index != order.length - 1;
    return order.contains(before) &&
        (index + 1 >= order.length || order[index + 1] != before);
  }

  void _accept(ChecklistItemDrag drag, String? before) {
    // Recheck the live snapshot: reconciliation or a pending receipt can change
    // the panel after pointer entry and before drop acceptance.
    if (!_canAccept(drag, before)) return;
    widget.onMove(
      widget.items.firstWhere((item) => item['id'] == drag.itemId),
      before,
    );
  }

  void _moveBy(String id, int delta) {
    if (!widget.enabled) return;
    final order = _order;
    final index = order.indexOf(id);
    if (index < 0 || index + delta < 0 || index + delta >= order.length) return;
    final before = delta < 0
        ? order[index - 1]
        : index + 2 < order.length
        ? order[index + 2]
        : null;
    widget.onMove(widget.items[index], before);
  }

  Widget _dropTarget(String? before, Widget child) =>
      DragTarget<ChecklistItemDrag>(
        key: Key(
          before == null
              ? 'checklist-drop-end'
              : 'checklist-drop-before-$before',
        ),
        onWillAcceptWithDetails: (details) => _canAccept(details.data, before),
        onAcceptWithDetails: (details) => _accept(details.data, before),
        builder: (context, candidates, rejected) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: widget.enabled && candidates.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < widget.items.length; index++)
          _dropTarget(
            widget.items[index]['id'] as String,
            _row(context, index),
          ),
        _dropTarget(
          null,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('checklist-add'),
              focusNode: widget.addFocusNode,
              onPressed: widget.enabled ? widget.onAdd : null,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, int index) {
    final item = widget.items[index];
    final id = item['id'] as String;
    final title = item['title'] as String? ?? '';
    final notes = item['description'] as String? ?? '';
    final completed = item['completed'] == true;
    final checkFocus = _focus(id, 'checkbox');
    final moveFocus = _focus(id, 'reorder');
    final actions = <CustomSemanticsAction, VoidCallback>{
      if (widget.enabled && index > 0)
        const CustomSemanticsAction(label: 'Move up'): () => _moveBy(id, -1),
      if (widget.enabled && index + 1 < widget.items.length)
        const CustomSemanticsAction(label: 'Move down'): () => _moveBy(id, 1),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _moveBy(id, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _moveBy(id, 1),
      },
      child: Row(
        key: Key('checklist-row-$id'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            label:
                '${completed ? 'Reopen' : 'Complete'} checklist item: $title',
            checked: completed,
            enabled: widget.enabled,
            focusable: true,
            focused: checkFocus.hasFocus,
            onTap: widget.enabled
                ? () => widget.onToggle(item, !completed)
                : null,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 48,
                height: 48,
                child: Checkbox(
                  key: Key('checklist-check-$id'),
                  focusNode: checkFocus,
                  value: completed,
                  // Retain the native focused control during busy receipts. The
                  // handler guard and outer semantics enforce the disabled state.
                  onChanged: (value) {
                    if (widget.enabled && value != null) {
                      widget.onToggle(item, value);
                    }
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: TextButton(
              key: Key('checklist-edit-$id'),
              focusNode: _focus(id, 'edit'),
              onPressed: widget.enabled ? () => widget.onEdit(item) : null,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                minimumSize: const Size(48, 48),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    semanticsLabel: 'Edit checklist item: $title',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: Key('checklist-delete-$id'),
            focusNode: _focus(id, 'delete'),
            tooltip: 'Delete checklist item: $title',
            onPressed: widget.enabled ? () => widget.onDelete(item) : null,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.delete_outline),
          ),
          Draggable<ChecklistItemDrag>(
            data: ChecklistItemDrag(
              parentId: widget.parentId,
              origin: widget.origin,
              revision: widget.revision,
              itemId: id,
              observedOrder: _order,
            ),
            maxSimultaneousDrags: widget.enabled ? 1 : 0,
            feedback: ExcludeSemantics(
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(title),
                  ),
                ),
              ),
            ),
            child: Focus(
              focusNode: moveFocus,
              canRequestFocus: widget.enabled,
              child: Semantics(
                label: 'Reorder checklist item: $title',
                enabled: widget.enabled,
                focusable: widget.enabled,
                focused: moveFocus.hasFocus,
                onFocus: widget.enabled ? moveFocus.requestFocus : null,
                customSemanticsActions: actions,
                child: Listener(
                  onPointerDown: (_) {
                    if (widget.enabled) moveFocus.requestFocus();
                  },
                  child: Tooltip(
                    message: 'Reorder checklist item: $title',
                    child: SizedBox(
                      key: Key('checklist-drag-$id'),
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}
