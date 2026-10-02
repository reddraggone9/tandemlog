import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';

void main() {
  testWidgets('repeat geometry retains padded touch and checked semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var checked = false, changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => TaskCompletionCheckbox(
                repeating: true,
                value: checked,
                onChanged: (value) => setState(() {
                  checked = value!;
                  changes++;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    final checkbox = find.byType(Checkbox);
    expect(tester.getSize(checkbox), const Size(48, 48));
    final vector = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.size == const Size(18, 26),
    );
    expect(vector, findsOneWidget);
    expect(tester.getCenter(vector), tester.getCenter(checkbox));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    // Near the edge of the existing hit target, outside the 18px drawing.
    await tester.tapAt(tester.getCenter(checkbox) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(changes, 1);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(checked, isFalse);
    semantics.dispose();
  });

  testWidgets('disabled repeat target cannot complete at enlarged text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: TaskCompletionCheckbox(
              repeating: true,
              value: false,
              onChanged: null,
            ),
          ),
        ),
      ),
    );
    final checkbox = find.byType(Checkbox);
    expect(tester.getSize(checkbox), const Size(48, 48));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(hasCheckedState: true, hasEnabledState: true),
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
