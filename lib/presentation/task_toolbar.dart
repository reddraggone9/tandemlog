import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reserve both status counts. Selection never affects header geometry.
class TaskToolbar extends StatelessWidget {
  final String? userName, count;
  final List<String> countLabels;
  final Widget Function(Widget?) identityMenu;
  final Widget Function(bool compact)? filter;
  final Widget undo;
  final Widget? searchField;
  final VoidCallback? search;
  const TaskToolbar({
    super.key,
    required this.userName,
    required this.identityMenu,
    required this.undo,
    this.searchField,
    this.search,
    this.count,
    this.countLabels = const [],
    this.filter,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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
      final titleWidth = compact || count == null
          ? 0.0
          : measure('Tasks', titleStyle).width + 8;
      final minimumRowHeight = math.max(
        48.0,
        compact || count == null ? 0.0 : measure('Tasks', titleStyle).height,
      );
      final filterWidth = filter == null
          ? 0.0
          : compact
          ? 48.0
          : measure('Filter', theme.textTheme.labelLarge).width + 64;
      final closedActionsWidth =
          48.0 + (search != null ? 48.0 : 0) + filterWidth;
      final actionsWidth =
          closedActionsWidth -
          (searchField != null && search != null ? 48.0 : 0);
      final headingWidth =
          24.0 + titleWidth + (count == null ? 0 : countWidth + 8);
      final searchMinimum = measure('Search').width + 64;
      final fullName =
          !compact &&
          name != null &&
          // Reserve Search's opening/close slot in both header modes, keeping
          // the identity shape stable so Undo stays anchored beside it.
          math.max(headingWidth, 32 + searchMinimum) +
                  closedActionsWidth +
                  namedWidth <=
              constraints.maxWidth;
      final identityWidth = fullName ? namedWidth : avatarWidth;
      // Enlarged text can use two rows; normal narrow layouts omit a count that
      // cannot fit rather than shrinking text or comfortable targets.
      final enlarged = scaler.scale(14) > 20;
      final secondRow = searchField != null
          ? 32 + actionsWidth + identityWidth + searchMinimum >
                constraints.maxWidth
          : count != null &&
                !compact &&
                headingWidth <= constraints.maxWidth &&
                enlarged &&
                headingWidth + actionsWidth + identityWidth >
                    constraints.maxWidth;
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
          Semantics(
            label: 'Tasks',
            excludeSemantics: true,
            child: Icon(
              Icons.check_circle_outline,
              size: 24,
              color: theme.colorScheme.primary,
            ),
          ),
          if (withCount &&
              !compact &&
              count != null &&
              (searchField == null || secondRow)) ...[
            const SizedBox(width: 8),
            Text('Tasks', style: titleStyle),
          ],
          if (withCount && showCount && (searchField == null || secondRow)) ...[
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
          if (searchField == null && search != null)
            IconButton(
              key: const ValueKey('open-search'),
              tooltip: 'Search all tasks (Ctrl+F)',
              onPressed: search,
              icon: const Icon(Icons.search),
            ),
          undo,
          if (filter != null) filter!(compact),
          identityMenu(identity),
        ],
      );
      return Column(
        key: const ValueKey('task-header'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secondRow) ...[
            if (searchField != null) ...[
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumRowHeight),
                child: Row(
                  children: [
                    heading(withCount: false),
                    const Spacer(),
                    actions(),
                  ],
                ),
              ),
              searchField!,
            ] else ...[
              Row(children: [Expanded(child: heading())]),
              Row(children: [const Spacer(), actions()]),
            ],
          ] else
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumRowHeight),
              child: Row(
                children: [
                  if (searchField != null) ...[
                    heading(),
                    const SizedBox(width: 8),
                    Expanded(child: searchField!),
                  ] else ...[
                    heading(),
                    const Spacer(),
                  ],
                  actions(),
                ],
              ),
            ),
        ],
      );
    },
  );
}
