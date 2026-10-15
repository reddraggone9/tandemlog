import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
            _ListRowPaintBounds(
              tint: hovering && widget.interactive
                  ? colors.primary.withValues(alpha: .04)
                  : null,
              focusColor: widget.focused ? colors.outline : null,
              child: widget.child,
            ),
            if (widget.divider) const ListRowDivider(),
          ],
        ),
      ),
    );
  }
}

/// Extends only body feedback to its enclosing main row. Hit testing, gestures,
/// focus and the Material ink controller remain those of the original InkWell.
class ListRowBodyInkWell extends InkWell {
  const ListRowBodyInkWell({
    super.key,
    super.onTap,
    super.onLongPress,
    super.onSecondaryTapUp,
    super.canRequestFocus,
    super.overlayColor,
    super.splashFactory,
    super.highlightColor,
    super.splashColor,
    super.child,
  });

  @override
  RectCallback getRectCallback(RenderBox referenceBox) => () {
    if (!referenceBox.attached || !referenceBox.hasSize) return Rect.zero;
    final fallback = Offset.zero & referenceBox.size;
    RenderObject? ancestor = referenceBox.parent;
    while (ancestor != null && ancestor is! _RenderListRowPaintBounds) {
      ancestor = ancestor.parent;
    }
    if (ancestor is! _RenderListRowPaintBounds) return fallback;
    if (!ancestor.attached || !ancestor.hasSize) return Rect.zero;
    final transform = ancestor.getTransformTo(referenceBox);
    if (transform.storage.any((value) => !value.isFinite) ||
        !transform.determinant().isFinite ||
        transform.determinant() == 0) {
      return Rect.zero;
    }
    final rect = MatrixUtils.transformRect(
      transform,
      Offset.zero & ancestor.size,
    );
    return rect.isFinite && !rect.isEmpty ? rect : Rect.zero;
  };
}

/// Layout-neutral main-row marker, excluding the divider and expanded panels.
class _ListRowPaintBounds extends SingleChildRenderObjectWidget {
  const _ListRowPaintBounds({
    required super.child,
    required this.tint,
    required this.focusColor,
  });
  final Color? tint, focusColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderListRowPaintBounds(tint, focusColor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderListRowPaintBounds renderObject,
  ) => renderObject.updatePaint(tint, focusColor);
}

class _RenderListRowPaintBounds extends RenderProxyBox {
  _RenderListRowPaintBounds(this._tint, this._focusColor);
  Color? _tint, _focusColor;

  void updatePaint(Color? tint, Color? focusColor) {
    if (_tint == tint && _focusColor == focusColor) return;
    _tint = tint;
    _focusColor = focusColor;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rect = offset & size;
    // Foreground tint stays visible above selected ListTile ink. Keeping paint
    // here also avoids ListTile's background-DecoratedBox debug heuristic.
    if (_tint case final tint?) {
      context.canvas.drawRect(rect, Paint()..color = tint);
    }
    if (_focusColor case final focusColor?) {
      Border.all(color: focusColor).paint(context.canvas, rect);
    }
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
