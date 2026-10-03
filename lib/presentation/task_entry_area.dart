import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'compact_selection_actions.dart';

/// The same fixed slot hosts capture and compact selection. The mounted capture
/// keeps draft/selection/scroll state; hidden input receives no focus or semantics.
class TaskEntryArea extends StatelessWidget {
  const TaskEntryArea({
    super.key,
    required this.selecting,
    required this.captureVisible,
    required this.selectionCount,
    required this.maximumSelectionCount,
    required this.capture,
    required this.onClear,
    required this.onEdit,
  });
  final bool selecting, captureVisible;
  final int selectionCount, maximumSelectionCount;
  final Widget capture;
  final VoidCallback? onClear, onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context),
            scaler = MediaQuery.textScalerOf(context);
        final label = TextPainter(
          text: TextSpan(text: 'Edit', style: theme.textTheme.labelLarge),
          textScaler: scaler,
          textDirection: Directionality.of(context),
        )..layout();
        final editWidth = math.max(48.0, label.width + 24);
        label.dispose();
        final counter =
            TextPainter(
              text: TextSpan(
                text: '$maximumSelectionCount selected',
                style: theme.textTheme.bodyMedium,
              ),
              textScaler: scaler,
              textDirection: Directionality.of(context),
            )..layout(
              maxWidth: math.max(1, constraints.maxWidth - 48 - editWidth - 16),
            );
        final minimumHeight = math.max(48.0, counter.height);
        counter.dispose();
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Keep the mounted capture buffer. Completed reserves only the
            // compact action height, not an invisible multiline draft.
            Offstage(
              offstage: !captureVisible,
              child: Visibility(
                visible: !selecting,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: ExcludeFocus(
                  excluding: !captureVisible || selecting,
                  child: capture,
                ),
              ),
            ),
            SizedBox(height: minimumHeight, width: double.infinity),
            if (selecting)
              Positioned.fill(
                child: CompactSelectionActions(
                  key: const ValueKey('compact-selection-actions'),
                  count: selectionCount,
                  onClear: onClear,
                  onEdit: onEdit,
                ),
              ),
          ],
        );
      },
    ),
  );
}
