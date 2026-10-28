import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

Future<void> verifyFoodContextMenu(WidgetTester tester) async {
  const writer = '00000000-0000-4000-8000-000000000094';
  final operations = <FoodOperation>[
    for (var i = 1; i <= 4; i++)
      FoodOperation(
        id: '$writer:$i',
        order: i,
        action: FoodAction.add,
        targets: [
          '00000000-0000-4000-8000-${(800 + i).toString().padLeft(12, '0')}',
        ],
        details: FoodDetails(
          name: i <= 2
              ? 'Active beans'
              : i == 3
              ? 'Retained beans'
              : 'Deleted beans',
          expiry: '2026-10-15',
          retention: i == 3 ? 'Reference' : '',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    FoodOperation(
      id: '$writer:5',
      order: 5,
      action: FoodAction.remove,
      targets: ['00000000-0000-4000-8000-000000000804'],
    ),
  ];
  var workspace = Object(), busy = false, pending = false;
  late StateSetter update;
  final removals = <List<String>>[], other = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return FoodInventoryPage(
            state: projectFood(operations),
            workspaceIdentity: workspace,
            busy: busy,
            savePending: pending,
            now: () => DateTime(2026, 10, 11),
            onAdd: (_, _) => other.add('add'),
            onRemove: removals.add,
            onRestore: (_) => other.add('restore'),
            onDetails: (_, _, _, _) => other.add('details'),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'beans');
  await tester.pumpAndSettle();
  Future<void> open(String name) async {
    await tester.tap(find.text(name), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  List<(String?, bool)> actions() => [
    for (final item in tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    ))
      (item.value, item.enabled),
  ];
  Future<void> dismiss() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  for (final name in ['Active beans', 'Retained beans']) {
    await open(name);
    expect(actions(), [
      ('add-another', true),
      ('select', true),
      ('remove', true),
    ]);
    expect(removals, isEmpty);
    expect(other, isEmpty);
    await dismiss();
  }
  await open('Deleted beans');
  expect(actions(), [
    ('add-another', true),
    ('select', true),
    ('restore', true),
  ]);
  await dismiss();
  // PopupMenuButton awaits its route then reads its current widget callback.
  // A workspace change must dispose that state even if canonical rows match.
  await tester.tap(find.byTooltip('Actions for Active beans'));
  await tester.pumpAndSettle();
  update(() => workspace = Object());
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Add another…'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(other, isEmpty);
  for (final control in [
    find.text('Active beans'),
    find.byTooltip('Remove one Active beans container'),
  ]) {
    final gesture = await tester.startGesture(tester.getCenter(control));
    update(() => workspace = Object());
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(removals, isEmpty);
    expect(other, isEmpty);
  }
  update(() => pending = true);
  await tester.pumpAndSettle();
  await open('Active beans');
  expect(actions(), [
    ('add-another', false),
    ('select', false),
    ('remove', true),
  ]);
  await dismiss();
  update(() => pending = false);
  await tester.pumpAndSettle();
  await open('Active beans');
  update(() => workspace = Object());
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Add another…'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(other, isEmpty);
  await open('Active beans');
  update(
    () => operations.add(
      FoodOperation(
        id: '$writer:6',
        order: 6,
        action: FoodAction.add,
        targets: ['00000000-0000-4000-8000-000000000805'],
        details: const FoodDetails(name: 'Active beans', expiry: '2026-10-15'),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(PopupMenuItem<String>, 'Remove 2 containers'),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
  expect(removals, isEmpty);
  await open('Active beans');
  await tester.tap(
    find.widgetWithText(PopupMenuItem<String>, 'Remove 3 containers'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  expect(removals, isEmpty);
  await open('Active beans');
  await tester.tap(
    find.widgetWithText(PopupMenuItem<String>, 'Remove 3 containers'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
  await tester.pumpAndSettle();
  expect(removals, [
    [
      '00000000-0000-4000-8000-000000000801',
      '00000000-0000-4000-8000-000000000802',
      '00000000-0000-4000-8000-000000000805',
    ],
  ]);
  await open('Retained beans');
  await tester.tap(
    find.widgetWithText(PopupMenuItem<String>, 'Remove 1 container'),
  );
  await tester.pumpAndSettle();
  update(() => workspace = Object());
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
  await tester.pumpAndSettle();
  expect(
    removals,
    hasLength(1),
    reason: 'a stale confirmation cannot remove in a new workspace',
  );
  update(() => busy = true);
  await tester.pumpAndSettle();
  await open('Active beans');
  expect(find.byType(PopupMenuItem<String>), findsNothing);
  expect(other, isEmpty);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'Food context menu eligibility, stale observations and exact targets',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await verifyFoodContextMenu(tester);
    },
  );
}
