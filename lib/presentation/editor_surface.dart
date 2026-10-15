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
    if (editor == null) return list;
    if (panel) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: list),
          const VerticalDivider(width: 1),
          SizedBox(width: panelWidth, child: editor),
        ],
      );
    }
    return Stack(
      children: [
        ExcludeFocus(child: ExcludeSemantics(child: list)),
        const ModalBarrier(color: Colors.black54, dismissible: false),
        MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Center(child: editor),
        ),
      ],
    );
  }
}
