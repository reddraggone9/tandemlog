import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

import 'food_expiry_guidance_test.dart' show selectFoodView;

// Drives the real row hit path: pointer gestures with real modifier key state,
// not the row callbacks, semantics actions or the Actions menu.
const _writer = '00000000-0000-4000-8000-000000000094';
String _id(int i) =>
    '00000000-0000-4000-8000-${(800 + i).toString().padLeft(12, '0')}';

FoodOperation _add(int order, String name) => FoodOperation(
  id: '$_writer:$order',
  order: order,
  action: FoodAction.add,
  targets: [_id(order)],
  details: FoodDetails(name: name, expiry: '2026-10-${20 + order}'),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-26T00:00:00Z',
);

FoodOperation _remove(int order, int target) => FoodOperation(
  id: '$_writer:$order',
  order: order,
  action: FoodAction.remove,
  targets: [_id(target)],
);

class _Calls {
  final removed = <List<String>>[];
  final restored = <List<String>>[];
  final edits = <List<String>>[];
}

Future<_Calls> _pump(
  WidgetTester tester,
  List<FoodOperation> events, {
  double width = 800,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: FoodInventoryPage(
        state: projectFood(events),
        onAdd: (_, _) {},
        onRemove: (ids) => calls.removed.add(List.of(ids)),
        onRestore: (item) => calls.restored.add([item.id]),
        onRestoreBatch: (items) =>
            calls.restored.add(items.map((e) => e.id).toList()),
        onDetails: (items, _, _) =>
            calls.edits.add(items.map((e) => e.id).toList()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _modifiedClick(
  WidgetTester tester,
  Finder target,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

final _events = [
  _add(1, 'Beans'),
  _add(2, 'Rice'),
  _add(3, 'Oats'),
  _add(4, 'Lentils'),
  _remove(5, 4),
  _add(6, 'Flour'),
  _remove(7, 6),
];

void main() {
  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets(
      '${modifier.keyLabel}-click on a Stock row starts and extends selection',
      variant: TargetPlatformVariant.desktop(),
      (tester) async {
        final calls = await _pump(tester, _events);
        await _modifiedClick(tester, find.text('Beans'), modifier);
        expect(find.text('1 selected'), findsOneWidget);
        await _modifiedClick(tester, find.text('Oats'), modifier);
        expect(find.text('2 selected'), findsOneWidget);
        await _modifiedClick(tester, find.text('Beans'), modifier);
        expect(find.text('1 selected'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
        expect(calls.edits, isEmpty);
      },
    );
  }

  testWidgets('long press on a Deleted row starts selection', (tester) async {
    await _pump(tester, _events);
    await selectFoodView(tester, FoodView.deleted);
    await tester.longPress(find.text('Lentils'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Flour'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets(
    'Ctrl-click on a Deleted row starts selection',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pump(tester, _events);
      await selectFoodView(tester, FoodView.deleted);
      await _modifiedClick(
        tester,
        find.text('Flour'),
        LogicalKeyboardKey.controlLeft,
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
    },
  );

  testWidgets(
    'Shift-click selects the visible range from the anchor',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pump(tester, _events);
      await _modifiedClick(
        tester,
        find.text('Beans'),
        LogicalKeyboardKey.controlLeft,
      );
      await _modifiedClick(
        tester,
        find.text('Oats'),
        LogicalKeyboardKey.shiftLeft,
      );
      expect(find.text('3 selected'), findsOneWidget);
    },
  );

  testWidgets(
    'wide Ctrl-click while editing one row selects both rows, like Tasks',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pump(tester, _events, width: 1200);
      await tester.tap(find.text('Beans'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Edit 1 container'), findsOneWidget);
      await _modifiedClick(
        tester,
        find.text('Rice'),
        LogicalKeyboardKey.controlLeft,
      );
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Edit 1 container'), findsNothing);
    },
  );

  testWidgets('selected Deleted rows restore together from the bulk editor', (
    tester,
  ) async {
    final calls = await _pump(tester, _events);
    await selectFoodView(tester, FoodView.deleted);
    await tester.longPress(find.text('Lentils'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flour'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit 2 containers'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(calls.restored, hasLength(1));
    expect(calls.restored.single.toSet(), {_id(4), _id(6)});
    expect(find.text('Edit 2 containers'), findsNothing);
    expect(find.textContaining(' selected'), findsNothing);
  });

  testWidgets('selected Stock rows remove together after confirmation', (
    tester,
  ) async {
    final calls = await _pump(tester, _events);
    await tester.longPress(find.text('Beans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove 2 containers?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(calls.removed, hasLength(1));
    expect(calls.removed.single.toSet(), {_id(1), _id(2)});
    expect(find.textContaining(' selected'), findsNothing);
  });
}
