import 'package:flutter/widgets.dart';

/// Centers a dialog when it first lays out, then keeps its bottom edge, and so
/// its actions, where they settled while content such as validation text grows
/// or shrinks. Growth extends upward; once the top inset is reached, the dialog
/// keeps its existing scrolling behavior.
///
/// Create a new instance whenever the available space changes for reasons
/// other than content (window size, keyboard insets) so the dialog recenters.
/// Instances compare by identity so the render object accepts the replacement.
class SettledCenterAlignment extends Alignment {
  SettledCenterAlignment() : super(0, 0);

  // Alignment is @immutable; the settled gap lives in a final box that only
  // this instance's layouts write.
  final _settled = _BottomGap();

  @override
  Offset alongOffset(Offset other) {
    final free = other.dy;
    final gap = _settled.value ??= free / 2;
    final top = (free - gap).clamp(0.0, free < 0 ? 0.0 : free);
    return Offset(other.dx / 2, top);
  }

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

class _BottomGap {
  double? value;
}

/// Owns one editor's [SettledCenterAlignment], replacing it when the window,
/// keyboard insets or text scale change so the dialog recenters.
class SettledDialogPlacement {
  Object? _geometry;
  SettledCenterAlignment _alignment = SettledCenterAlignment();

  SettledCenterAlignment alignmentFor(BuildContext context) {
    final media = MediaQuery.of(context);
    final geometry = (media.size, media.viewInsets, media.textScaler);
    if (geometry != _geometry) {
      _geometry = geometry;
      _alignment = SettledCenterAlignment();
    }
    return _alignment;
  }
}
