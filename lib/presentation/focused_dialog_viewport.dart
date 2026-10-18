import 'package:flutter/material.dart';

/// Reveals the caller-owned input when a name dialog's viewport changes.
/// Validation, focus ownership and submission stay in the two calling dialogs.
class FocusedDialogViewport extends StatefulWidget {
  const FocusedDialogViewport({
    super.key,
    required this.focusNode,
    required this.fieldKey,
    required this.builder,
  });
  final FocusNode focusNode;
  final GlobalKey fieldKey;
  final Widget Function(BuildContext context, EdgeInsets insetPadding) builder;

  @override
  State<FocusedDialogViewport> createState() => _FocusedDialogViewportState();
}

class _FocusedDialogViewportState extends State<FocusedDialogViewport> {
  Object? _geometry;
  double? _viewportHeight;
  bool _revealQueued = false;

  void _queueReveal() {
    if (_revealQueued) return;
    _revealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      if (!mounted ||
          !widget.focusNode.hasFocus ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      final anchor = widget.fieldKey.currentContext;
      if (anchor != null && anchor.mounted) {
        Scrollable.ensureVisible(anchor, alignment: 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final geometry = (media.size, media.viewInsets, media.textScaler.scale(14));
    if (geometry != _geometry) {
      _geometry = geometry;
      _queueReveal();
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.viewportDimension != _viewportHeight) {
          _viewportHeight = notification.metrics.viewportDimension;
          _queueReveal();
        }
        return false;
      },
      child: widget.builder(
        context,
        EdgeInsets.symmetric(
          horizontal: 16,
          vertical: media.viewInsets.bottom > 0 ? 8 : 24,
        ),
      ),
    );
  }
}
