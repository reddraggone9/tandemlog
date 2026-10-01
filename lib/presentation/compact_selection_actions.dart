import 'package:flutter/material.dart';

/// Selection commands sit above the scroll viewport, never over task rows.
class CompactSelectionActions extends StatelessWidget {
  const CompactSelectionActions({
    super.key,
    required this.count,
    required this.onClear,
    required this.onEdit,
  });

  final int count;
  final VoidCallback? onClear;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(liveRegion: true, child: Text('$count selected')),
              TextButton(
                key: const ValueKey('clear-selected-tasks'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onClear,
                child: const Text('Clear Selection'),
              ),
              TextButton(
                key: const ValueKey('edit-selected-tasks'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
    ],
  );
}
