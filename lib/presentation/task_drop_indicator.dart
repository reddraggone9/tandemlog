import 'package:flutter/material.dart';

/// Paint after child surfaces and after layout, without adding a hit target.
class TaskDropIndicatorPainter extends CustomPainter {
  TaskDropIndicatorPainter({
    required this.boundary,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Rect? Function() boundary;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = boundary();
    if (rect != null) canvas.drawRect(rect, Paint()..color = color);
  }

  // A new drag session can change geometry without changing the theme.
  @override
  bool shouldRepaint(TaskDropIndicatorPainter oldDelegate) => true;
}
