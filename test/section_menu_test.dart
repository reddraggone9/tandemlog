import 'dart:ui' show SemanticsAction, Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/section_menu.dart';

void main() {
  testWidgets('wide and narrow triggers expose full selected section choices', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      bool food = false;
      for (final compact in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SectionMenu(
                  food: food,
                  compact: compact,
                  onSelected: (next) => setState(() => food = next),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final trigger = find.byKey(const ValueKey('section-menu'));
        expect(tester.getSize(trigger).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));
        expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
        expect(
          find.text(food ? 'Food' : 'Tasks'),
          compact ? findsNothing : findsOneWidget,
        );
        expect(
          find.byTooltip(
            'Switch section (current: ${food ? 'Food' : 'Tasks'})',
          ),
          findsOneWidget,
        );
        final triggerData = tester.getSemantics(trigger).getSemanticsData();
        expect(
          triggerData.tooltip,
          'Switch section (current: ${food ? 'Food' : 'Tasks'})',
        );
        expect(triggerData.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        for (final section in [false, true]) {
          expect(
            find.descendant(
              of: find.byKey(
                ValueKey(section ? 'module-food' : 'module-tasks'),
              ),
              matching: find.text(section ? 'Food' : 'Tasks'),
            ),
            findsOneWidget,
          );
        }
        final selected = find.byKey(
          ValueKey(food ? 'module-food' : 'module-tasks'),
        );
        expect(
          tester.widget<CheckedPopupMenuItem<bool>>(selected).checked,
          isTrue,
        );
        final selectedSemantics = find.descendant(
          of: selected,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true,
          ),
        );
        expect(
          tester
              .getSemantics(selectedSemantics)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        final other = find.byKey(
          ValueKey(food ? 'module-tasks' : 'module-food'),
        );
        await tester.tap(other);
        await tester.pumpAndSettle();
        expect(food, compact ? false : true);
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('keyboard opens and selects; disabled trigger cannot switch', (
    tester,
  ) async {
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionMenu(
            food: false,
            compact: true,
            onSelected: (next) => selected = next,
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<PopupMenuButton<bool>>()
          ?.key,
      const ValueKey('section-menu'),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionMenu(food: false, compact: true, onSelected: null),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('section-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
  });
}
