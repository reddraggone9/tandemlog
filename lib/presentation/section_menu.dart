import 'package:flutter/material.dart';

/// Section navigation belongs to the current toolbar, beside its controls.
class SectionMenu extends StatelessWidget {
  const SectionMenu({
    super.key,
    required this.food,
    required this.compact,
    required this.onSelected,
  });

  final bool food, compact;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final name = food ? 'Food' : 'Tasks';
    final theme = Theme.of(context);
    return PopupMenuButton<bool>(
      key: const ValueKey('section-menu'),
      enabled: onSelected != null,
      tooltip: 'Switch section (current: $name)',
      initialValue: food,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final section in [false, true])
          CheckedPopupMenuItem<bool>(
            key: ValueKey(section ? 'module-food' : 'module-tasks'),
            value: section,
            checked: section == food,
            child: Semantics(
              selected: section == food,
              child: Row(
                children: [
                  Icon(
                    section
                        ? Icons.kitchen_outlined
                        : Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 12),
                  Text(section ? 'Food' : 'Tasks'),
                ],
              ),
            ),
          ),
      ],
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  food ? Icons.kitchen_outlined : Icons.check_circle_outline,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: theme.textTheme.titleLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
