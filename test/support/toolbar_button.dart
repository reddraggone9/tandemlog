import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Native action state across its narrow IconButton and wide text-button forms.
({VoidCallback? onPressed, String? tooltip}) toolbarButton(
  WidgetTester tester,
  Finder target,
) {
  final button = tester.widget(target);
  final onPressed = switch (button) {
    IconButton(:final onPressed) => onPressed,
    ButtonStyleButton(:final onPressed) => onPressed,
    _ => throw StateError(
      'Expected a native toolbar button, got ${button.runtimeType}',
    ),
  };
  final tooltip = button is IconButton
      ? button.tooltip
      : tester
            .widget<Tooltip>(
              find.ancestor(of: target, matching: find.byType(Tooltip)).first,
            )
            .message;
  return (onPressed: onPressed, tooltip: tooltip);
}
