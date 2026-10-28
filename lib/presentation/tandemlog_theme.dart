import 'package:flutter/material.dart';

/// The production theme, shared by the app and UX capture harnesses.
ThemeData tandemlogTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff267461),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff6f7f2)
        : colors.surface,
    cardTheme: CardThemeData(color: colors.surfaceContainerLow),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: colors.onSurface),
      actionTextColor: colors.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
    ),
  );
}
