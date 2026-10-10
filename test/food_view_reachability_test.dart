import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/tag_input.dart';

import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

const inboxGuidance =
    'Needs an expiration date. A known or estimated date moves food into stock.';
const retentionReason = 'Keep for the next family birthday recipe';
const reachabilityError =
    'The synthetic folder could not save this change. Check its connection and permissions, then try again. Your existing food containers are still available.';

List<FoodOperation> reachabilityFixture() {
  const writer = '00000000-0000-4000-8000-000000000010';
  const details = [
    FoodDetails(name: 'Synthetic undated beans'),
    FoodDetails(name: 'Synthetic undated lentils'),
    FoodDetails(name: 'Synthetic dated rice', expiry: '2027-06-01'),
    FoodDetails(
      name: 'Synthetic retained oats',
      expiry: '2027-06-01',
      retention: retentionReason,
    ),
    FoodDetails(name: 'Synthetic deleted peas', expiry: '2027-06-01'),
  ];
  final operations = List.generate(
    details.length,
    (i) => FoodOperation(
      id: '$writer:${i + 1}',
      order: i + 1,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
      ],
      details: details[i],
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-10T00:00:00Z',
    ),
  );
  operations.add(
    FoodOperation(
      id: '$writer:6',
      order: 6,
      action: FoodAction.remove,
      targets: operations.last.targets,
    ),
  );
  return operations;
}

Future<void> verifyFoodViewReachability(
  WidgetTester tester, {
  required Brightness brightness,
  required double textScale,
  required FoodView mode,
  bool withError = false,
  bool empty = false,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  final label = switch (mode) {
    FoodView.inventory => 'Stock',
    FoodView.inbox => 'Inbox',
    FoodView.retained => 'Retained',
    FoodView.deleted => 'Deleted',
  };
  final name = switch (mode) {
    FoodView.inventory => 'Synthetic dated rice',
    FoodView.inbox => 'Synthetic undated lentils',
    FoodView.retained => 'Synthetic retained oats',
    FoodView.deleted => 'Synthetic deleted peas',
  };
  final prefix =
      '${brightness.name}-${textScale.toInt()}x-${mode.name}${withError ? '-error' : ''}${empty ? '-empty' : ''}';
  // Decode saved operation bytes into a fresh projection, independent of UI
  // draft state. This is a synthetic layout fixture, not a disk replay claim.
  final saved = jsonEncode(
    (empty ? <FoodOperation>[] : reachabilityFixture())
        .map((e) => e.toJson())
        .toList(),
  );
  final state = projectFood(
    (jsonDecode(saved) as List).map((e) => FoodOperation.fromJson(e)).toList(),
  );
  final before = jsonEncode(state.containers.map((e) => e.toJson()).toList());
  var commandCount = 0;
  String? restoredId;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(prefix),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Match the production module strip above the Food page.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Tasks'),
                            icon: Icon(Icons.checklist),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Food'),
                            icon: Icon(Icons.kitchen_outlined),
                          ),
                        ],
                        selected: const {true},
                        onSelectionChanged: (_) {},
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () {},
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FoodInventoryPage(
                  state: state,
                  error: withError ? reachabilityError : null,
                  onAdd: (_, _) => commandCount++,
                  onRemove: (_) => commandCount++,
                  onRestore: (item) {
                    commandCount++;
                    restoredId = item.id;
                  },
                  onContents: (_, _) => commandCount++,
                  onDetails: (_, _, _) => commandCount++,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  Future<void> tap(Finder target) async {
    expect(target.hitTestable(), findsOneWidget);
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    try {
      if (input == null) {
        await tester.tap(target);
      } else {
        await input(target);
      }
    } finally {
      WidgetController.hitTestWarningShouldBeFatal = previous;
    }
    await tester.pumpAndSettle();
  }

  await tap(find.widgetWithText(ChoiceChip, label));
  await capture?.call('$prefix-initial');
  final scrollable = find
      .descendant(
        of: find.byType(FoodInventoryPage),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final viewport = tester.getRect(scrollable);
  expect(
    viewport.height,
    greaterThanOrEqualTo(48),
    reason: 'A real scroll viewport must remain for rows and action targets',
  );
  Future<void> swipeTo(
    Finder target, {
    bool backwards = false,
    String? fragment,
  }) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      if (target.evaluate().isNotEmpty) {
        var rect = tester.getRect(target);
        if (fragment != null) {
          final rich = find.descendant(
            of: target,
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          final value = tester.widget<Text>(target).data!;
          final start = value.indexOf(fragment);
          expect(start, greaterThanOrEqualTo(0));
          final origin = tester.getTopLeft(rich);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + fragment.length,
            ),
          );
          expect(
            boxes,
            isNotEmpty,
            reason: 'Readability requires actual rendered glyphs',
          );
          rect = boxes
              .map((box) => box.toRect().shift(origin))
              .reduce((a, b) => a.expandToInclude(b));
        }
        if ((fragment != null || target.hitTestable().evaluate().isNotEmpty) &&
            rect.intersect(viewport).height >= rect.height - 0.5) {
          return;
        }
      }
      // Use normal dragging within the actual viewport, not ensureVisible or
      // jumping a zero-height list to an off-screen widget.
      await tester.drag(
        scrollable,
        Offset(0, viewport.height * (backwards ? 0.2 : -0.2)),
      );
      await tester.pumpAndSettle();
    }
    fail('$prefix: target must be fully reachable by swiping: $target');
  }

  for (final text in [
    if (withError) reachabilityError,
    if (mode == FoodView.inbox) inboxGuidance,
  ]) {
    final notice = find.text(text);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(of: notice, matching: find.byType(RichText)),
          )
          .didExceedMaxLines,
      isFalse,
    );
    await swipeTo(notice, fragment: text.substring(0, 20));
    await capture?.call(
      '$prefix-${text == inboxGuidance ? 'guidance' : 'notice'}-start-readable',
    );
    await swipeTo(notice, fragment: text.substring(text.length - 20));
    await capture?.call(
      '$prefix-${text == inboxGuidance ? 'guidance' : 'notice'}-end-readable',
    );
  }
  if (empty) {
    final message = find.text(switch (mode) {
      FoodView.inventory => 'No dated stock',
      FoodView.inbox => 'Everything has an expiration date',
      FoodView.retained => 'No retained food',
      FoodView.deleted => 'No deleted containers',
    });
    await swipeTo(message);
    await capture?.call('$prefix-message-reached');
    expect(commandCount, 0);
    expect(tester.takeException(), isNull);
    return;
  }
  if (mode == FoodView.retained) {
    final show = find.byTooltip('Show retention reasons');
    await swipeTo(show, backwards: true);
    await tap(show);
    final option = find.byKey(const ValueKey('tag-option-$retentionReason'));
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    await tap(option);
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, {
      retentionReason,
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final clear = find.byTooltip('Clear retention filters');
    await swipeTo(clear, backwards: true);
    await tap(clear);
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, isEmpty);
    await capture?.call('$prefix-retention-filter-cleared');
    final section = find.widgetWithText(ExpansionTile, retentionReason);
    final expand = find.descendant(
      of: section,
      matching: find.byIcon(Icons.expand_more),
    );
    await swipeTo(expand);
    await tap(expand);
  }
  if (mode == FoodView.inbox) {
    await swipeTo(find.byTooltip('Inspect Synthetic undated beans containers'));
  }
  final inspect = find.byTooltip('Inspect $name containers');
  await swipeTo(inspect);
  expect(tester.getSize(inspect).height, greaterThanOrEqualTo(48));
  expect(tester.getSize(inspect).width, greaterThanOrEqualTo(48));
  await capture?.call('$prefix-row-reached');
  if (mode == FoodView.inbox) {
    final savedName = find.text(name);
    await swipeTo(savedName);
    final card = find
        .ancestor(of: savedName, matching: find.byType(Card))
        .first;
    final needsExpiration = find.descendant(
      of: card,
      matching: find.text('Needs expiration'),
    );
    await swipeTo(needsExpiration);
    expect(
      tester.getRect(savedName).intersect(viewport).height,
      greaterThanOrEqualTo(tester.getRect(savedName).height - 0.5),
    );
    await capture?.call('$prefix-saved-name-and-expiration-reached');
    await swipeTo(inspect, backwards: true);
  }
  await tap(inspect);
  if (mode == FoodView.deleted) {
    final restore = find.byTooltip('Restore $name container 00000005');
    await swipeTo(restore);
    await capture?.call('$prefix-restore-reached');
    expect(commandCount, 0, reason: 'Browsing and scrolling must not write');
    await tap(restore);
    expect(commandCount, 1);
    expect(restoredId, state.deleted.single.id);
  } else {
    final actions = find.byTooltip('Actions for $name');
    await swipeTo(actions);
    await tap(actions);
    expect(find.text('Edit group details').hitTestable(), findsOneWidget);
    await capture?.call('$prefix-actions-reached');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(commandCount, 0, reason: 'Browsing and scrolling must not write');
  }
  expect(jsonEncode(state.containers.map((e) => e.toJson()).toList()), before);
  expect(tester.takeException(), isNull);
  if (mode == FoodView.inbox && textScale == 2 && !withError) {
    final query = find.byKey(const ValueKey('food-search'));
    await swipeTo(query, backwards: true);
    await tester.ensureVisible(query);
    await tester.pumpAndSettle();
    await tap(query);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(query);
    await tester.pumpAndSettle();
    await capture?.call('$prefix-search-ime');
    expect(tester.takeException(), isNull);
    final editable = find.descendant(
      of: query,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    final available = tester.getRect(scrollable);
    final line = tester.getRect(editable);
    expect(
      line.intersect(available).height,
      greaterThanOrEqualTo(line.height - 0.5),
    );
    await tester.enterText(query, 'Synthetic undated');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(query).controller!.text,
      'Synthetic undated',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await swipeTo(find.byTooltip('Collapse $name containers'));
    expect(commandCount, 0);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  setUpAll(loadSdkRoboto);
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      for (final view in FoodView.values) {
        for (final withError in [false, true]) {
          testWidgets(
            'Food ${view.name} reachable at320/${brightness.name}/${scale}x/error=$withError',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(320, 640);
              tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(tester.view.resetPadding);
              addTearDown(tester.view.resetViewInsets);
              await verifyFoodViewReachability(
                tester,
                brightness: brightness,
                textScale: scale,
                mode: view,
                withError: withError,
              );
            },
          );
        }
        if (scale == 2) {
          testWidgets(
            'empty Food ${view.name} remains reachable at320/${brightness.name}/2x',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(320, 640);
              tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(tester.view.resetPadding);
              await verifyFoodViewReachability(
                tester,
                brightness: brightness,
                textScale: scale,
                mode: view,
                empty: true,
              );
            },
          );
        }
      }
    }
  }
}
