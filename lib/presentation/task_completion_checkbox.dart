import 'package:flutter/material.dart';

/// Keeps the native checkbox's hit target, focus, reaction and semantics. Only
/// its repeating-task perimeter is replaced by Lee's approved 18 × 22 vector.
class TaskCompletionCheckbox extends StatelessWidget {
  const TaskCompletionCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.repeating = false,
  });

  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool repeating;

  @override
  Widget build(BuildContext context) {
    final checkbox = Checkbox(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      value: value,
      onChanged: onChanged,
      side: repeating ? BorderSide.none : null,
    );
    if (!repeating) return checkbox;
    final colors = Theme.of(context).colorScheme;
    final color = onChanged == null
        ? colors.onSurface.withValues(alpha: 0.38)
        : value
        ? colors.primary
        : colors.onSurfaceVariant;
    return Stack(
      alignment: Alignment.center,
      children: [
        checkbox,
        IgnorePointer(
          child: ExcludeSemantics(
            child: CustomPaint(
              size: const Size(18, 22),
              painter: _RepeatPerimeter(color),
            ),
          ),
        ),
      ],
    );
  }
}

class _RepeatPerimeter extends CustomPainter {
  const _RepeatPerimeter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox="0 -2 18 22": retain the 18px square and intentional tip
    // bleed, rather than scaling its full height down to an 18px icon slot.
    canvas.translate(0, 2);
    final perimeter = Path()
      ..moveTo(1.5, 16.866)
      ..arcToPoint(const Offset(1, 16), radius: const Radius.circular(1))
      ..lineTo(1, 2)
      ..arcToPoint(const Offset(2, 1), radius: const Radius.circular(1))
      ..lineTo(11.8, 1)
      ..moveTo(16.5, 1.134)
      ..arcToPoint(const Offset(17, 2), radius: const Radius.circular(1))
      ..lineTo(17, 16)
      ..arcToPoint(const Offset(16, 17), radius: const Radius.circular(1))
      ..lineTo(6.2, 17);
    canvas.drawPath(
      perimeter,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final tips = Path()
      ..moveTo(11.4, -1.3)
      ..lineTo(14, 1)
      ..lineTo(11.4, 3.3)
      ..close()
      ..moveTo(6.6, 14.7)
      ..lineTo(4, 17)
      ..lineTo(6.6, 19.3)
      ..close();
    canvas.drawPath(tips, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RepeatPerimeter oldDelegate) =>
      color != oldDelegate.color;
}
