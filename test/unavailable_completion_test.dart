import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/unavailable_completion.dart';

void main() {
  testWidgets(
    'unavailable completion explains by tap and keyboard without completing',
    (tester) async {
      var explanations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnavailableCompletion(
              title: 'Example recurring task',
              reason: 'Next dates are unchanged.',
              onExplain: () => explanations++,
              repeating: true,
            ),
          ),
        ),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      await tester.tap(find.byType(UnavailableCompletion));
      await tester.pumpAndSettle();
      expect(explanations, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.text('Next dates are unchanged.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(explanations, 2);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
