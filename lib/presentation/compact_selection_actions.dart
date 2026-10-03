import 'package:flutter/material.dart';

/// Swaps into the capture slot, keeping actions available while the list scrolls.
class CompactSelectionActions extends StatelessWidget {
  const CompactSelectionActions({
    super.key,
    required this.count,
    required this.onClear,
    required this.onEdit,
  });
  final int count;
  final VoidCallback? onClear, onEdit;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(liveRegion: true, child: Text('$count selected')),
      ),
      const SizedBox(width: 8),
      IconButton(
        key: const ValueKey('clear-selected-tasks'),
        tooltip: 'Clear Selection',
        onPressed: onClear,
        icon: const Icon(Icons.close),
      ),
      const SizedBox(width: 8),
      TextButton(
        key: const ValueKey('edit-selected-tasks'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: onEdit,
        child: const Text('Edit'),
      ),
    ],
  );
}
