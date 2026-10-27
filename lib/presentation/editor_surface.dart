import 'package:flutter/material.dart';

/// The two sections share presentation geometry, while owning their own drafts.
class EditorSurface extends StatelessWidget {
  const EditorSurface({
    super.key,
    required this.list,
    required this.panel,
    this.editor,
  });
  static const breakpoint = 900.0;
  static const panelWidth = 420.0;
  final Widget list;
  final Widget? editor;
  final bool panel;
  @override
  Widget build(BuildContext context) {
    final modal = editor != null && !panel;
    // Keep the list in the same element slot across opening, closing and
    // resizing. Reparenting its keyed viewport still deactivates descendants
    // and recreates unkeyed controls outside that viewport.
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ExcludeFocus(
                excluding: modal,
                child: ExcludeSemantics(excluding: modal, child: list),
              ),
            ),
            if (panel && editor != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: panelWidth, child: editor),
            ],
          ],
        ),
        if (modal) ...[
          const ModalBarrier(color: Colors.black54, dismissible: false),
          MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Center(child: editor),
          ),
        ],
      ],
    );
  }
}
