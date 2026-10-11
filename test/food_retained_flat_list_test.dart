import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/tag_input.dart';
import 'food_expiry_guidance_test.dart' show selectFoodView;

const _alpha = 'Alpha reference recipe';
const _zeta = 'Zeta keep for the next household recipe';
Future<void> verifyFlatRetained(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double scale = 1,
  Future<void> Function(String)? capture,
}) async {
  const writer = '00000000-0000-4000-8000-000000000095';
  final operations = <FoodOperation>[
    for (final (index, details) in [
      const FoodDetails(
        name: 'Early retained beans',
        expiry: '2026-10-14',
        retention: _zeta,
      ),
      const FoodDetails(
        name: 'Early retained beans',
        expiry: '2026-10-14',
        retention: _zeta,
      ),
      const FoodDetails(
        name: 'Middle retained beans',
        expiry: '2026-10-15',
        retention: _alpha,
      ),
      const FoodDetails(
        name: 'Late retained beans',
        expiry: '2026-10-16',
        retention: _zeta,
      ),
      const FoodDetails(
        name: 'Twin retained beans',
        expiry: '2026-10-17',
        retention: _alpha,
      ),
      const FoodDetails(
        name: 'Twin retained beans',
        expiry: '2026-10-17',
        retention: _zeta,
      ),
      const FoodDetails(
        name: 'Deleted retained beans',
        expiry: '2026-10-13',
        retention: _alpha,
      ),
    ].indexed)
      FoodOperation(
        id: '$writer:${index + 1}',
        order: index + 1,
        action: FoodAction.add,
        targets: [
          '00000000-0000-4000-8000-${(900 + index).toString().padLeft(12, '0')}',
        ],
        details: details,
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    FoodOperation(
      id: '$writer:8',
      order: 8,
      action: FoodAction.remove,
      targets: ['00000000-0000-4000-8000-000000000906'],
    ),
  ];
  final food = projectFood(operations), commands = <String>[];
  final before = food.containers.map((e) => e.toJson()).toList();
  final key = GlobalKey<FoodInventoryPageState>();
  var displayed = food;
  late StateSetter incoming;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (_, setState) {
          incoming = setState;
          return FoodInventoryPage(
            key: key,
            state: displayed,
            now: () => DateTime(2026, 10, 11),
            onAdd: (_, _) => commands.add('add'),
            onRemove: (_) => commands.add('remove'),
            onRestore: (_) => commands.add('restore'),
            onContents: (_, _) => commands.add('contents'),
            onDetails: (_, _, _) => commands.add('details'),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await selectFoodView(tester, FoodView.retained);
  expect(
    find.byType(ExpansionTile),
    findsNothing,
    reason: 'retention reasons are row metadata, not sections',
  );
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  ScrollPosition position() =>
      tester.state<ScrollableState>(scrollable).position;
  Future<void> top() async {
    position().jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> reach(Finder target) async {
    await top();
    await tester.scrollUntilVisible(target, 160, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  final contentPositions = <double>[];
  for (final pair in [
    ('Early retained beans', _zeta),
    ('Middle retained beans', _alpha),
    ('Late retained beans', _zeta),
  ]) {
    final title = find.text(pair.$1);
    await reach(title);
    contentPositions.add(tester.getRect(title).top + position().pixels);
    final card = find.ancestor(of: title, matching: find.byType(Card));
    final reason = find.descendant(of: card, matching: find.text(pair.$2));
    expect(reason, findsOneWidget);
    expect(
      tester.getRect(reason).left,
      greaterThanOrEqualTo(tester.getRect(card).left),
    );
    expect(
      tester.getRect(reason).right,
      lessThanOrEqualTo(tester.getRect(card).right),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: reason, matching: find.byType(RichText)),
    );
    debugPrint(
      'RETAINED_TEXT_GEOMETRY=${jsonEncode({
        'text': pair.$2,
        'paragraphWidth': paragraph.size.width,
        'paragraphHeight': paragraph.size.height,
        'rangeBoxes': [
          for (final box in paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: pair.$2.length))) [box.left, box.top, box.right, box.bottom],
        ],
        'characters': [
          for (var i = 0; i < pair.$2.length; i++) {
              'offset': i,
              'character': pair.$2[i],
              'boxes': [
                for (final box in paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1))) [box.left, box.top, box.right, box.bottom],
              ],
            },
        ],
      })}',
    );
    await capture?.call('flat-retained-geometry-${pair.$1.split(' ').first}');
    for (var i = 0; i < pair.$2.length; i++) {
      if (pair.$2[i].trim().isEmpty) continue;
      // Selected whitespace at a soft line break may extend beyond horizontal
      // paint bounds (TextPainter.width). Check every visible fixture letter
      // with the same tight tolerance, plus the whole metadata/card above.
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      expect(
        boxes,
        isNotEmpty,
        reason: 'Retained reason character $i is visible',
      );
      for (final box in boxes) {
        expect(box.left, greaterThanOrEqualTo(-.5));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width + .5));
        expect(box.top, greaterThanOrEqualTo(-.5));
        expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + .5));
      }
    }
  }
  expect(contentPositions[0], lessThan(contentPositions[1]));
  expect(
    contentPositions[1],
    lessThan(contentPositions[2]),
    reason: 'different reasons interleave by expiry',
  );
  await reach(find.byTooltip('Inspect Early retained beans containers'));
  await tester.tap(find.byTooltip('Inspect Early retained beans containers'));
  await tester.pumpAndSettle();
  expect(
    find.byTooltip('Collapse Early retained beans containers'),
    findsOneWidget,
  );
  expect(find.byTooltip('Actions for Early retained beans'), findsOneWidget);
  await capture?.call('flat-retained-expanded');
  expect(
    food
        .view(FoodView.retained)
        .where((e) => e.details.name == 'Twin retained beans'),
    hasLength(2),
  );
  await top();
  await tester.tap(find.byTooltip('Show retention reasons'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('tag-option-$_zeta')));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  expect(key.currentState!.reasons, {_zeta});
  expect(tester.widget<TagInput>(find.byType(TagInput)).selected, {_zeta});
  expect(find.text('Middle retained beans'), findsNothing);
  await capture?.call('flat-retained-filtered');
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'beans');
  await tester.pumpAndSettle();
  await reach(find.text('Middle retained beans'));
  expect(find.text('Middle retained beans'), findsOneWidget);
  await reach(find.text('Deleted retained beans'));
  expect(find.byKey(const ValueKey('food-deleted-heading')), findsOneWidget);
  expect(key.currentState!.reasons, {_zeta});
  await capture?.call('flat-retained-search-deleted');
  await top();
  await tester.tap(find.byTooltip('Clear food search'));
  await tester.pumpAndSettle();
  expect(key.currentState!.reasons, {_zeta});
  expect(find.text('Middle retained beans'), findsNothing);
  await tester.tap(find.byTooltip('Clear retention filters'));
  await tester.pumpAndSettle();
  expect(key.currentState!.reasons, isEmpty);
  await reach(find.text('Middle retained beans'));
  expect(find.text('Middle retained beans'), findsOneWidget);
  // A saved reason can cease to have active containers; keep its filter and show
  // the empty state rather than silently clearing the user's selection.
  await top();
  await tester.tap(find.byTooltip('Show retention reasons'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('tag-option-$_zeta')));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  FocusManager.instance.primaryFocus?.unfocus();
  incoming(
    () => displayed = projectFood([
      ...operations,
      FoodOperation(
        id: '$writer:9',
        order: 9,
        action: FoodAction.remove,
        targets: [
          for (final item in food.active)
            if (item.details.retention == _zeta) item.id,
        ],
      ),
    ]),
  );
  await tester.pumpAndSettle();
  expect(find.text('No retained food'), findsOneWidget);
  expect(key.currentState!.reasons, {_zeta});
  expect(commands, isEmpty);
  expect(food.containers.map((e) => e.toJson()).toList(), before);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'flat Retained expiry/filter/metadata ${brightness.name} $sample',
        (tester) async {
          tester.view.physicalSize = Size(sample.$1, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFlatRetained(
            tester,
            brightness: brightness,
            scale: sample.$2,
          );
        },
      );
    }
  }
}
