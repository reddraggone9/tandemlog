import 'package:flutter/material.dart';

/// Keeps the native checkbox's hit target, focus, reaction and semantics. Only
/// its repeating-task perimeter is replaced by Lee's approved 18 × 26 vector.
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
              size: const Size(18, 26),
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
    // SVG viewBox="0 -4 18 26": retain the 18px square and intentional tip
    // bleed, rather than scaling its full height down to an 18px icon slot.
    canvas.translate(0, 4);
    final perimeter = Path()
      ..moveTo(3, 17)
      ..lineTo(2, 17)
      ..arcToPoint(const Offset(1, 16), radius: const Radius.circular(1))
      ..lineTo(1, 2)
      ..arcToPoint(const Offset(2, 1), radius: const Radius.circular(1))
      ..lineTo(7.2, 1)
      ..moveTo(15, 1)
      ..lineTo(16, 1)
      ..arcToPoint(const Offset(17, 2), radius: const Radius.circular(1))
      ..lineTo(17, 16)
      ..arcToPoint(const Offset(16, 17), radius: const Radius.circular(1))
      ..lineTo(10.8, 17);
    canvas.drawPath(
      perimeter,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final tips = Path()
      ..moveTo(6.8, -3.4)
      ..lineTo(12, 1)
      ..lineTo(6.8, 5.4)
      ..close()
      ..moveTo(11.2, 12.6)
      ..lineTo(6, 17)
      ..lineTo(11.2, 21.4)
      ..close();
    canvas.drawPath(tips, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RepeatPerimeter oldDelegate) =>
      color != oldDelegate.color;
}
