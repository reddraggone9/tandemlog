import 'package:flutter/material.dart';

/// Shared paint and feedback only. Callers retain all gestures, focus and content.
class ListRowSurface extends StatefulWidget {
  const ListRowSurface({
    super.key,
    required this.child,
    this.color,
    this.focused = false,
    this.interactive = true,
    this.divider = true,
  });
  final Widget child;
  final Color? color;
  final bool focused, interactive, divider;

  @override
  State<ListRowSurface> createState() => _ListRowSurfaceState();
}

class _ListRowSurfaceState extends State<ListRowSurface> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: Material(
        color: widget.color ?? colors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                // Foreground tint remains visible over selected ListTile ink.
                color: hovering && widget.interactive
                    ? colors.primary.withValues(alpha: .04)
                    : null,
                border: widget.focused
                    ? Border.all(color: colors.outline)
                    : null,
              ),
              child: widget.child,
            ),
            if (widget.divider) const ListRowDivider(),
          ],
        ),
      ),
    );
  }
}

/// Scope ink styling to row actions; popup routes keep the app's own theme.
WidgetStateProperty<Color?> listRowInkOverlay(ColorScheme colors) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return colors.primary.withValues(alpha: .16);
      }
      if (states.contains(WidgetState.focused)) {
        return colors.primary.withValues(alpha: .08);
      }
      if (states.contains(WidgetState.hovered)) return Colors.transparent;
      return null;
    });

class ListRowDivider extends StatelessWidget {
  const ListRowDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5),
  );
}
