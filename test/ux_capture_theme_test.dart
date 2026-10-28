import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

import 'support/ux_capture.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('UX capture accepts the production ${brightness.name} theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('ux-root'),
          child: MaterialApp(
            theme: tandemlogTheme(brightness),
            darkTheme: tandemlogTheme(Brightness.dark),
            home: const Scaffold(body: Text('Theme capture')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureUx(tester, 'theme-${brightness.name}');
    });
  }

  testWidgets('UX capture refuses the default purple theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(),
      ),
    );
    await expectLater(
      captureUx(tester, 'wrong-theme'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('UX capture refuses a mismatched dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tandemlogTheme(Brightness.light),
        darkTheme: ThemeData.dark(),
        home: const Scaffold(),
      ),
    );
    await expectLater(
      captureUx(tester, 'wrong-dark-theme'),
      throwsA(isA<TestFailure>()),
    );
  });
}
