import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single native pinned heading, scoped by its surrounding SliverMainAxisGroup.
/// Measuring the same text used for painting keeps its extent correct when the
/// viewport or accessibility text scale changes, without a duplicate overlay.
class StickyTaskGroupHeading extends StatelessWidget {
  const StickyTaskGroupHeading({
    super.key,
    required this.title,
    this.headingKey,
    this.inset = 0,
  });

  final String title;
  final Key? headingKey;

  /// Horizontal inset of the text only. The opaque background always spans the
  /// sliver, so edge-to-edge rows scrolling under it never show at its sides.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final painter =
            TextPainter(
              text: TextSpan(text: title, style: style),
              textDirection: direction,
              textScaler: scaler,
            )..layout(
              maxWidth: math.max(0, constraints.crossAxisExtent - inset * 2),
            );
        final extent = painter.height + 20;
        painter.dispose();
        return SliverPersistentHeader(
          pinned: true,
          delegate: _HeadingDelegate(
            extent: extent,
            child: ColoredBox(
              key: headingKey,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Padding(
                padding: EdgeInsets.fromLTRB(inset, 16, inset, 4),
                child: Semantics(
                  header: true,
                  child: Text(title, style: style),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeadingDelegate extends SliverPersistentHeaderDelegate {
  const _HeadingDelegate({required this.extent, required this.child});
  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(_HeadingDelegate oldDelegate) =>
      extent != oldDelegate.extent || child != oldDelegate.child;
}
