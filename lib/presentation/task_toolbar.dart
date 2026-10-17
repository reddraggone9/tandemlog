import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared section geometry; reserve both status counts without selection drift.
class TaskToolbar extends StatelessWidget {
  final String? userName, count;
  final List<String> countLabels;
  final Widget Function(Widget?) identityMenu;
  final Widget Function(bool compact)? sectionMenu;
  final Widget Function(bool compact)? filter;
  final Widget undo;
  final Widget Function(bool compact)? undoAction;
  final Widget Function(bool compact)? inputModeAction;
  final String sectionName;
  final IconData sectionIcon;
  const TaskToolbar({
    super.key,
    required this.userName,
    required this.identityMenu,
    required this.undo,
    this.undoAction,
    this.inputModeAction,
    this.sectionName = 'Tasks',
    this.sectionIcon = Icons.check_circle_outline,
    this.count,
    this.countLabels = const [],
    this.filter,
    this.sectionMenu,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
    child: _contents(),
  );

  Widget _contents() => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context),
          scaler = MediaQuery.textScalerOf(context);
      final style = theme.textTheme.bodyMedium!;
      Size measure(String text, [TextStyle? textStyle]) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: textStyle ?? style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final size = painter.size;
        painter.dispose();
        return size;
      }

      final compact = constraints.maxWidth < 600;
      final name = userName;
      final initial = name == null
          ? ''
          : String.fromCharCode(name.trim().runes.first).toUpperCase();
      final initialSize = measure(initial);
      final diameter = math.max(
        32.0,
        math.max(initialSize.width, initialSize.height) + 8,
      );
      final avatarWidth = math.max(48.0, diameter + 16);
      final namedWidth = name == null ? 48.0 : measure(name).width + 62;
      final countWidth = count == null
          ? 0.0
          : [
              count!,
              ...countLabels,
            ].map((label) => measure(label).width).reduce(math.max);
      final titleStyle = theme.textTheme.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
      );
      final titleWidth = compact || (count == null && sectionMenu == null)
          ? 0.0
          : measure(sectionName, titleStyle).width + 8;
      final minimumRowHeight = math.max(
        48.0,
        compact || count == null
            ? 0.0
            : measure(sectionName, titleStyle).height,
      );
      final filterWidth = filter == null
          ? 0.0
          : compact
          ? 48.0
          : measure('Filter', theme.textTheme.labelLarge).width + 64;
      final closedActionsWidth =
          (undoAction == null || compact
              ? 48.0
              : measure('Undo', theme.textTheme.labelLarge).width + 68) +
          (inputModeAction == null
              ? 0.0
              : compact
              ? 48.0
              : math.max(
                      measure('Add', theme.textTheme.labelLarge).width,
                      measure('Search', theme.textTheme.labelLarge).width,
                    ) +
                    64) +
          filterWidth;
      final actionsWidth = closedActionsWidth;
      // Keep the whole switch target, counts and actions comfortable. The
      // current section name yields when enlarged text consumes that space.
      final sectionCompact =
          compact ||
          48 +
                  titleWidth +
                  (count == null ? 0 : countWidth + 8) +
                  closedActionsWidth +
                  avatarWidth >
              constraints.maxWidth;
      final sectionWidth = sectionMenu == null
          ? 24.0 + titleWidth
          : 48.0 + (sectionCompact ? 0 : titleWidth);
      final headingWidth = sectionWidth + (count == null ? 0 : countWidth + 8);
      final fullName =
          !compact &&
          name != null &&
          headingWidth + closedActionsWidth + namedWidth <=
              constraints.maxWidth;
      final identityWidth = fullName ? namedWidth : avatarWidth;
      // Enlarged text can use two rows; normal narrow layouts omit a count that
      // cannot fit rather than shrinking text or comfortable targets.
      final enlarged = scaler.scale(14) > 20;
      final secondRow =
          sectionWidth + actionsWidth + identityWidth > constraints.maxWidth ||
          (count != null &&
              !compact &&
              headingWidth <= constraints.maxWidth &&
              enlarged &&
              headingWidth + actionsWidth + identityWidth >
                  constraints.maxWidth);
      final showCount =
          count != null &&
          headingWidth <= constraints.maxWidth &&
          (secondRow ||
              headingWidth + actionsWidth + identityWidth <=
                  constraints.maxWidth);
      final identity = name == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: identityWidth,
                minHeight: 48,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: fullName
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_outline, size: 20),
                          const SizedBox(width: 6),
                          Text(name, style: style),
                          const Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      )
                    : ExcludeSemantics(
                        child: Container(
                          width: diameter,
                          height: diameter,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                          ),
                          child: Text(
                            initial,
                            style: style.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
              ),
            );
      Widget heading({bool withCount = true}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sectionMenu != null)
            sectionMenu!(sectionCompact)
          else
            Semantics(
              label: sectionName,
              excludeSemantics: true,
              child: Icon(
                sectionIcon,
                size: 24,
                color: theme.colorScheme.primary,
              ),
            ),
          if (withCount &&
              sectionMenu == null &&
              !compact &&
              count != null) ...[
            const SizedBox(width: 8),
            Text(sectionName, style: titleStyle),
          ],
          if (withCount && showCount) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: countWidth,
              child: Text(count!, style: style),
            ),
          ],
        ],
      );
      Widget actions() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inputModeAction != null)
            SizedBox(
              width: compact
                  ? 48
                  : math.max(
                          measure('Add', theme.textTheme.labelLarge).width,
                          measure('Search', theme.textTheme.labelLarge).width,
                        ) +
                        64,
              child: inputModeAction!(compact),
            ),
          undoAction?.call(compact) ?? undo,
          if (filter != null) filter!(compact),
          identityMenu(identity),
        ],
      );
      return Column(
        key: const ValueKey('task-header'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secondRow) ...[
            Row(children: [Expanded(child: heading())]),
            Row(children: [const Spacer(), actions()]),
          ] else
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumRowHeight),
              child: Row(children: [heading(), const Spacer(), actions()]),
            ),
        ],
      );
    },
  );
}
