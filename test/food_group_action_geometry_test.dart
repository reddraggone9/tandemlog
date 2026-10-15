import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

Future<void> verifyFoodGroupActionGeometry(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  final commands = <String>[];
  const writer = '00000000-0000-4000-8000-000000000093';
  final food = projectFood([
    for (var i = 1; i <= 2; i++)
      FoodOperation(
        id: '$writer:$i',
        order: i,
        action: FoodAction.add,
        targets: [
          '00000000-0000-4000-8000-${(i + 700).toString().padLeft(12, '0')}',
        ],
        details: const FoodDetails(
          name: 'Geometry beans',
          expiry: '2026-10-15',
          size: '500 g',
          location: 'Freezer',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
  ]);
  final beforeFood = food.containers.map((e) => e.toJson()).toList();
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('group-geometry-${brightness.name}-$textScale'),
      theme: ThemeData(
        brightness: brightness,
        platform: TargetPlatform.linux,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: food,
        now: () => DateTime(2026, 10, 11),
        onAdd: (_, _) => commands.add('add'),
        onRemove: (_) => commands.add('remove'),
        onRestore: (_) => commands.add('restore'),
        onDetails: (_, _, _) => commands.add('details'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('food-search')),
    'Geometry beans',
  );
  await tester.pumpAndSettle();
  expect(
    find.text('Geometry beans'),
    findsNWidgets(2),
    reason:
        'The exact name appears in Search and the row; target the row explicitly',
  );
  final groupName = find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('food-group:'),
    ),
    matching: find.text('Geometry beans'),
  );
  final remove = find.byTooltip('Remove one Geometry beans container');
  final menu = find.byTooltip('Actions for Geometry beans');
  final date = find.text('2026-10-15');
  final leading = find
      .ancestor(of: date, matching: find.byType(Expanded))
      .first;
  final initialRemove = tester.getCenter(remove);
  final initialMenu = tester.getCenter(menu);
  final initialWidth = tester.getSize(leading).width;
  final initialDate = tester.getSize(date);
  List<Rect> dateLines() => tester
      .renderObject<RenderParagraph>(
        find.descendant(of: date, matching: find.byType(RichText)),
      )
      .getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 10),
      )
      .map((e) => e.toRect())
      .toList();
  final initialLines = dateLines();
  List<(String?, bool)> menuActions() => [
    for (final item in tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    ))
      (item.value, item.enabled),
  ];
  Future<void> secondaryMenu(String name) async {
    await tester.tap(groupName, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(menuActions(), [('add-another', true), ('remove', true)]);
    for (final item in find.byType(PopupMenuItem<String>).evaluate()) {
      final bounds = tester.getRect(find.byWidget(item.widget));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
    }
    expect(commands, isEmpty, reason: 'opening a menu never issues a command');
    await capture?.call(name);
  }

  await secondaryMenu('collapsed-secondary-menu');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(PopupMenuItem<String>), findsNothing);
  await capture?.call('flat-row');
  for (var cycle = 0; cycle < 2; cycle++) {
    for (final control in [remove, menu]) {
      expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }
    expect(find.text('500 g · Freezer'), findsOneWidget);
    expect(find.text('2 containers'), findsOneWidget);
    expect(find.text('Full'), findsNothing);
    expect(find.text('Remaining contents'), findsNothing);
    await secondaryMenu('flat-secondary-menu-$cycle');
    final secondaryActions = menuActions();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    if (input == null) {
      await tester.tap(menu);
    } else {
      await input(menu);
    }
    await tester.pumpAndSettle();
    expect(
      menuActions(),
      secondaryActions,
      reason: 'ellipsis and secondary click share exact actions',
    );
    await capture?.call('flat-ellipsis-menu-$cycle');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.getCenter(remove), initialRemove);
    expect(tester.getCenter(menu), initialMenu);
    expect(tester.getSize(leading).width, initialWidth);
    expect(tester.getSize(date), initialDate);
    expect(
      dateLines(),
      initialLines,
      reason: 'opening a menu does not change expiration wrapping',
    );
    final row = groupName;
    if (input == null) {
      await tester.tap(row);
    } else {
      await input(row);
    }
    await tester.pumpAndSettle();
    expect(find.text('Edit 2 containers'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Food name'))
          .controller!
          .text,
      'Geometry beans',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(
      commands,
      isEmpty,
      reason: 'menus and cancelled editing never mutate',
    );
    expect(tester.getCenter(remove), initialRemove);
    expect(tester.getCenter(menu), initialMenu);
    expect(tester.getSize(leading).width, initialWidth);
    expect(tester.getSize(date), initialDate);
    expect(dateLines(), initialLines);
  }
  expect(commands, isEmpty);
  expect(food.containers.map((e) => e.toJson()).toList(), beforeFood);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final brightness in Brightness.values) {
    for (final sample in [(1200.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'Food action anchors ${brightness.name} ${sample.$1} ${sample.$2}x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 1200);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await verifyFoodGroupActionGeometry(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
        },
      );
    }
  }
}
