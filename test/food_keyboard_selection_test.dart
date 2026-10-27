import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const _writer = '00000000-0000-4000-8000-000000000094';

FoodOperation _add(int order, String id, String name) => FoodOperation(
  id: '$_writer:$order',
  order: order,
  action: FoodAction.add,
  targets: [id],
  details: FoodDetails(name: name, expiry: '2026-10-28'),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-26T00:00:00Z',
);

final _events = [
  _add(1, '00000000-0000-4000-8000-000000000801', 'Beans'),
  _add(2, '00000000-0000-4000-8000-000000000802', 'Rice'),
];

Future<List<List<String>>> _pump(WidgetTester tester) async {
  final removed = <List<String>>[];
  await tester.pumpWidget(
    MaterialApp(
      home: FoodInventoryPage(
        state: projectFood(_events),
        onAdd: (_, _) {},
        onRemove: removed.add,
        onRestore: (_) {},
        onDetails: (_, _, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return removed;
}

/// The row's own focus target: the InkWell around the group's visible name.
FocusNode _rowFocus(WidgetTester tester, String name) => Focus.of(
  tester.element(
    find
        .descendant(
          of: find.ancestor(
            of: find.text(name),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Semantics),
        )
        .first,
  ),
);

Future<void> _focusRow(WidgetTester tester, String name) async {
  _rowFocus(tester, name).requestFocus();
  await tester.pumpAndSettle();
}

SemanticsNode _rowSemantics(WidgetTester tester, String name) {
  var node = tester.getSemantics(find.text(name).first);
  while (!node.getSemanticsData().flagsCollection.isButton) {
    node = node.parent!;
  }
  return node;
}

void main() {
  testWidgets('Space on a focused Food row selects it; Enter still edits', (
    tester,
  ) async {
    await _pump(tester);
    await _focusRow(tester, 'Beans');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);

    await _focusRow(tester, 'Rice');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    // Outside selection, keyboard activation with Enter edits the group.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _focusRow(tester, 'Rice');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Food name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Space on a row button keeps that button action', (tester) async {
    final removed = await _pump(tester);
    final button = find.byTooltip('Remove one Beans container');
    Focus.of(
      tester.element(find.descendant(of: button, matching: find.byType(Icon))),
    ).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(removed, [
      ['00000000-0000-4000-8000-000000000801'],
    ]);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('screen readers get Select and long-press actions with state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final node = _rowSemantics(tester, 'Beans');
    var row = node.getSemanticsData();
    expect(row.hasAction(SemanticsAction.longPress), isTrue);
    final select = row.customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .singleWhere((action) => action!.label == 'Select food')!;
    expect(row.flagsCollection.isSelected, isNot(Tristate.isTrue));
    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(select),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    row = _rowSemantics(tester, 'Beans').getSemanticsData();
    expect(row.flagsCollection.isSelected, Tristate.isTrue);
    expect(
      row.customSemanticsActionIds!.map(
        (id) => CustomSemanticsAction.getAction(id)!.label,
      ),
      contains('Deselect food'),
    );
    handle.dispose();
  });

  testWidgets('row Actions menu offers Select and Deselect', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Actions for Beans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Actions for Rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Actions for Beans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deselect'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
