import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/startup_screens.dart';

/// Lee 11-13 (60 fps): the loading screen matches the first list's font
/// variants between frames; it must finish on its own and stop when the
/// screen goes, leaving no timer behind.
void main() {
  testWidgets('loading screen warms its variants and then goes quiet', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartupLoading()));
    // Before the delay nothing has run; afterwards one variant per frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('workspace-opening')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the loading screen early cancels the warmup', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartupLoading()));
    await tester.pump(const Duration(milliseconds: 10));
    // Replaced before its first turn: the pending start timer is cancelled
    // (the test fails on a pending timer otherwise).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
