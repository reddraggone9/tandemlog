import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/food_product_fields.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';

Future<void> verifyFoodBulkDetails(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  const writer = '00000000-0000-4000-8000-000000000051';
  String id(int i) =>
      '00000000-0000-4000-8000-${(900 + i).toString().padLeft(12, '0')}';
  final operations = <FoodOperation>[
    for (var i = 1; i <= 4; i++)
      FoodOperation(
        id: '$writer:$i',
        order: i,
        action: FoodAction.add,
        targets: [id(i)],
        details: FoodDetails(
          name: 'Synthetic food $i',
          expiry: '2026-10-${14 + i}',
          brand: i.isOdd ? 'Acme' : 'Other',
          location: i.isOdd ? 'Pantry' : 'Freezer',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    FoodOperation(
      id: '$writer:5',
      order: 5,
      action: FoodAction.remove,
      targets: [id(4)],
    ),
  ];
  final writes =
      <({List<String> ids, FoodDetails details, List<String> fields})>[];
  late StateSetter update;
  var workspace = Object();
  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
    await tester.pumpAndSettle();
  }

  Future<void> selectAll() async {
    await tap(find.byKey(const ValueKey('food-filter')));
    await tap(find.text('Select matching containers'));
  }

  Future<void> openSelection() async {
    final edit = find.byKey(const ValueKey('edit-selected-tasks'));
    if (edit.evaluate().isNotEmpty) await tap(edit);
  }

  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('bulk-${brightness.name}-$textScale'),
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return FoodInventoryPage(
            state: projectFood(operations),
            workspaceIdentity: workspace,
            onAdd: (_, _) {},
            onRemove: (_) {},
            onRestore: (_) {},
            onDetails: (items, details, fields, products) => writes.add((
              ids: items.map((e) => e.id).toList(),
              details: details,
              fields: foodTouchedFields(fields, products),
            )),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await selectAll();
  expect(
    tester
        .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
        .bulkSelected,
    hasLength(3),
  );
  await openSelection();
  expect(find.text('Edit 3 containers'), findsOneWidget);
  expect(find.text('Expiration'), findsNothing);
  await capture?.call('mixed-untouched');
  await tap(find.widgetWithText(FilledButton, 'Save'));
  expect(writes, isEmpty, reason: 'Untouched mixed fields are a no-op');
  await selectAll();
  await openSelection();
  await tap(find.byKey(const ValueKey('brandApply')));
  final brand = find.widgetWithText(TextField, 'Brand');
  await tester.enterText(brand, 'Unified');
  await tester.pumpAndSettle();
  // A new arrival in a different row does not join the selected rows.
  update(
    () => operations.add(
      FoodOperation(
        id: '$writer:6',
        order: 6,
        action: FoodAction.add,
        targets: [id(5)],
        details: const FoodDetails(
          name: 'Synthetic new arrival',
          expiry: '2026-10-20',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    ),
  );
  await tester.pumpAndSettle();
  await capture?.call('apply-brand');
  await tap(find.widgetWithText(FilledButton, 'Save'));
  expect(writes, hasLength(1));
  expect(writes.single.ids.toSet(), {id(1), id(2), id(3)});
  expect(writes.single.fields, ['brand']);
  expect(writes.single.details.brand, 'Unified');
  // Search selection follows the shown rows and restores capture on clear.
  final search = find.byKey(const ValueKey('food-search'));
  await tap(search);
  await tester.enterText(search, 'Synthetic food 2');
  await tester.pumpAndSettle();
  await selectAll();
  expect(
    tester
        .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
        .bulkSelected,
    hasLength(1),
  );
  await openSelection();
  // An applied blank field clears that value, as in the Tasks bulk editor.
  await tester.enterText(find.widgetWithText(TextField, 'Location'), '');
  await tester.pumpAndSettle();
  // Escape first dismisses the field's suggestions.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, 'Save'));
  expect(writes.last.ids, [id(2)]);
  expect(writes.last.fields, ['location']);
  expect(writes.last.details.location, '');
  await tap(search);
  await tester.enterText(search, 'Synthetic food 4');
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(search).controller!.text, 'Synthetic food 4');
  expect(
    tester
        .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
        .search
        .text,
    'Synthetic food 4',
  );
  await capture?.call('deleted-only-selectable');
  await tap(find.byKey(const ValueKey('food-filter')));
  expect(
    tester
        .widget<PopupMenuItem>(
          find.widgetWithText(
            PopupMenuItem<FoodView>,
            'Select matching containers',
          ),
        )
        .enabled,
    isTrue,
  );
  await tester.tapAt(const Offset(2, 2));
  await tester.pumpAndSettle();
  await tap(search);
  await tester.enterText(search, 'Synthetic food');
  await tester.pumpAndSettle();
  await selectAll();
  await openSelection();
  await tap(find.widgetWithText(TextButton, 'Cancel'));
  expect(writes, hasLength(2));
  expect(
    tester
        .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
        .bulkSelected,
    isEmpty,
  );
  expect(
    find.byKey(const ValueKey('food-search')).hitTestable(),
    findsOneWidget,
  );
  await selectAll();
  final page = tester.state<FoodInventoryPageState>(
    find.byType(FoodInventoryPage),
  );
  // Rows have no selection checkbox; Ctrl/Cmd-click deselects a row, as on
  // Tasks.
  expect(
    find.descendant(
      of: find.byType(ListRowSurface),
      matching: find.byType(Checkbox),
    ),
    findsNothing,
  );
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tap(find.text('Synthetic food 2'));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(page.bulkSelected, {id(1), id(3), id(4)});
  await capture?.call('deselected-row');
  final scrolling = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  tester.state<ScrollableState>(scrolling).position.jumpTo(0);
  await tester.pumpAndSettle();
  await openSelection();
  expect(find.text('Edit 3 containers'), findsOneWidget);
  await tap(find.byKey(const ValueKey('locationApply')));
  await tester.enterText(
    find.widgetWithText(TextField, 'Location'),
    'Temporary',
  );
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(TextButton, 'Cancel'));
  await tap(find.widgetWithText(FilledButton, 'Discard'));
  expect(writes, hasLength(2));
  await selectAll();
  await openSelection();
  await tap(find.byKey(const ValueKey('brandApply')));
  await tester.enterText(
    find.widgetWithText(TextField, 'Brand'),
    'Unsafe after switch',
  );
  await tester.pumpAndSettle();
  update(() => workspace = Object());
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, 'Save'));
  expect(
    find.text(
      'The selected containers changed. Close this editor and select again.',
    ),
    findsOneWidget,
  );
  expect(writes, hasLength(2));
  expect(page.bulkSelected, isEmpty);
  await tap(find.widgetWithText(TextButton, 'Cancel'));
  await tap(find.widgetWithText(FilledButton, 'Discard'));
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Food bulk details ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 1100);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFoodBulkDetails(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
        },
      );
    }
  }
}
