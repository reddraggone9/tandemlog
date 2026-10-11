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
        onContents: (_, _) => commands.add('contents'),
        onDetails: (_, _, _) => commands.add('details'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final remove = find.byTooltip('Remove one Geometry beans container');
  final inspect = find.byTooltip('Inspect Geometry beans containers');
  final date = find.text('2026-10-15');
  final leading = find
      .ancestor(of: date, matching: find.byType(Expanded))
      .first;
  final initialRemove = tester.getCenter(remove);
  final initialInspect = tester.getCenter(inspect);
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
    await tester.tap(
      find.text('Geometry beans'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(menuActions(), [
      ('add-another', true),
      ('edit', true),
      ('remove', true),
    ]);
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
  expect(find.byTooltip('Actions for Geometry beans'), findsNothing);
  await capture?.call('collapsed');
  for (var cycle = 0; cycle < 2; cycle++) {
    if (input == null) {
      await tester.tap(inspect);
    } else {
      await input(inspect);
    }
    await tester.pumpAndSettle();
    final collapse = find.byTooltip('Collapse Geometry beans containers');
    expect(
      tester.getCenter(remove),
      initialRemove,
      reason: 'Remove must keep its header anchor',
    );
    expect(
      tester.getCenter(collapse),
      initialInspect,
      reason: 'Inspect and Collapse share one anchor',
    );
    expect(
      tester.getSize(leading).width,
      initialWidth,
      reason: 'Opening actions must not take header text width',
    );
    expect(tester.getSize(date), initialDate);
    expect(
      dateLines(),
      initialLines,
      reason: 'The expiration wrapping stays unchanged',
    );
    final menu = find.byTooltip('Actions for Geometry beans');
    for (final control in [remove, collapse, menu]) {
      expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getRect(menu).top,
      greaterThanOrEqualTo(tester.getRect(collapse).bottom),
    );
    final metadata = find.text('500 g · Freezer');
    expect(
      tester.getRect(metadata).right,
      lessThanOrEqualTo(tester.getRect(menu).left),
    );
    expect(find.textContaining('Container 000'), findsNothing);
    expect(find.text('Full'), findsNWidgets(2));
    expect(tester.widget<Divider>(find.byType(Divider)).height, 1);
    await secondaryMenu('expanded-secondary-menu-$cycle');
    final secondaryActions = menuActions();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(
      menuActions(),
      secondaryActions,
      reason: 'ellipsis and secondary click share exact actions',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await secondaryMenu('expanded-secondary-edit-$cycle');
    await tester.tap(
      find.widgetWithText(PopupMenuItem<String>, 'Edit group details'),
    );
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
    expect(commands, isEmpty);
    await capture?.call('expanded-$cycle');
    if (input == null) {
      await tester.tap(collapse);
    } else {
      await input(collapse);
    }
    await tester.pumpAndSettle();
    expect(tester.getCenter(remove), initialRemove);
    expect(tester.getCenter(inspect), initialInspect);
    expect(tester.getSize(leading).width, initialWidth);
    expect(find.byTooltip('Actions for Geometry beans'), findsNothing);
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
