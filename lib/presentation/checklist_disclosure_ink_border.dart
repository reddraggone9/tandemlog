import 'package:flutter/material.dart';

/// Centers the ink around the disclosure content independently of its hit area.
class ChecklistDisclosureInkBorder extends OutlinedBorder {
  const ChecklistDisclosureInkBorder(this.inkWidth, this.inkHeight);

  final double inkWidth;
  final double inkHeight;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ChecklistDisclosureInkBorder copyWith({BorderSide? side}) => this;

  @override
  ChecklistDisclosureInkBorder scale(double t) =>
      ChecklistDisclosureInkBorder(inkWidth * t, inkHeight * t);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final ink = Rect.fromLTWH(
      rect.left - 8,
      rect.top,
      inkWidth,
      inkHeight.clamp(0, rect.height).toDouble(),
    );
    return Path()
      ..addRRect(RRect.fromRectAndRadius(ink, const Radius.circular(4)));
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is ChecklistDisclosureInkBorder
      ? ChecklistDisclosureInkBorder(
          a.inkWidth + (inkWidth - a.inkWidth) * t,
          a.inkHeight + (inkHeight - a.inkHeight) * t,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is ChecklistDisclosureInkBorder
      ? ChecklistDisclosureInkBorder(
          inkWidth + (b.inkWidth - inkWidth) * t,
          inkHeight + (b.inkHeight - inkHeight) * t,
        )
      : super.lerpTo(b, t);
}
