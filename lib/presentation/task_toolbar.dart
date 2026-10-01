import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fit is measured using the actual name and current text scale, rather than
/// truncating a capped label or selecting an avatar at a screen breakpoint.
class TaskToolbar extends StatelessWidget {
  final String? userName;
  final Widget Function(Widget?) identityMenu;
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
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context),
          scaler = MediaQuery.textScalerOf(context);
      final style = theme.textTheme.bodyMedium!;
      Size measure(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final size = painter.size;
        painter.dispose();
        return size;
      }

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
      final searchMinimum = searchField == null
          ? 0.0
          : measure('Search').width + 64;
      final available =
          constraints.maxWidth -
          32 -
          48 -
          (searchField == null && search != null ? 48 : 0) -
          searchMinimum;
      final fullName = name != null && namedWidth <= available;
      final identity = name == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: fullName ? namedWidth : avatarWidth,
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
      return Row(
        children: [
          Semantics(
            label: 'Tasks',
            child: Icon(
              Icons.check_circle_outline,
              size: 24,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          if (searchField != null)
            Expanded(child: searchField!)
          else
            const Spacer(),
          undo,
          if (searchField == null && search != null)
            IconButton(
              key: const ValueKey('open-search'),
              tooltip: 'Search all tasks (Ctrl+F)',
              onPressed: search,
              icon: const Icon(Icons.search),
            ),
          identityMenu(identity),
        ],
      );
    },
  );
}
