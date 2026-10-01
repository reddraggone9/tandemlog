import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/compact_selection_actions.dart';

void main() {
  testWidgets('selection commands wrap without losing touch targets', (
    tester,
  ) async {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          var clear = 0, edit = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      child: CompactSelectionActions(
                        count: 10000,
                        onClear: () => clear++,
                        onEdit: () => edit++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final bar = tester.getRect(find.byType(CompactSelectionActions));
          for (final key in ['clear-selected-tasks', 'edit-selected-tasks']) {
            final button = find.byKey(ValueKey(key));
            final rect = tester.getRect(button);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.right, lessThanOrEqualTo(bar.right));
            await tester.tap(button);
          }
          expect(clear, 1);
          expect(edit, 1);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
