import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/expiration_presentation.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

Future<void> verifyFoodExpirationColorWorkflow(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
}) async {
  var today = DateTime(2026, 10, 11), writes = 0;
  const writer = '00000000-0000-4000-8000-000000000091';
  final operations = [
    for (final retained in [false, true])
      for (final entry in [
        '2026-10-10',
        '2026-10-11',
        '2026-10-14',
        '2026-10-18',
      ].indexed)
        FoodOperation(
          id: '$writer:${entry.$1 + (retained ? 5 : 1)}',
          order: entry.$1 + (retained ? 5 : 1),
          action: FoodAction.add,
          targets: [
            '00000000-0000-4000-8000-${(entry.$1 + (retained ? 200 : 100)).toString().padLeft(12, '0')}',
          ],
          details: FoodDetails(
            name: ['Overdue', 'Today', 'Three days', 'One week'][entry.$1],
            expiry: entry.$2,
            retention: retained ? 'Emergency' : '',
          ),
          contents: const Contents.fraction(1, 1),
          createdAt: '2026-10-11T00:00:00Z',
        ),
  ];
  final before = jsonEncode(operations.map((e) => e.toJson()).toList());
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff267461),
    brightness: brightness,
  );
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('date-colors-${brightness.name}-$textScale'),
      theme: ThemeData(colorScheme: colors),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: projectFood(operations),
        now: () => today,
        userName: 'Synthetic household',
        identityMenu: (child) => PopupMenuButton<String>(
          tooltip: 'Active user: Synthetic household',
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings', child: Text('Settings')),
          ],
          child: child,
        ),
        sectionMenu: (compact) =>
            SectionMenu(food: true, compact: compact, onSelected: (_) {}),
        onAdd: (_, _) => writes++,
        onRemove: (_) => writes++,
        onRestore: (_) => writes++,
        onContents: (_, _) => writes++,
        onDetails: (_, _, _) => writes++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  Future<void> inspectColors(String name) async {
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    for (final date in [
      '2026-10-10',
      '2026-10-11',
      '2026-10-14',
      '2026-10-18',
    ]) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(date),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text(date));
      expect(text.style!.color, foodExpiryColor(date, today, colors));
      expect(text.style!.fontWeight, FontWeight.w600);
    }
    await capture?.call('$name-lower');
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await capture?.call('$name-upper');
  }

  await inspectColors('stock');
  await chooseFoodView(tester, 'Retained');
  await tester.ensureVisible(find.widgetWithText(ExpansionTile, 'Emergency'));
  await tester.tap(find.widgetWithText(ExpansionTile, 'Emergency'));
  await tester.pumpAndSettle();
  await inspectColors('retained');
  // Resume on another local day repaints the same records; no durable edit.
  final beforeColor = tester.widget<Text>(find.text('2026-10-14')).style!.color;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  today = DateTime(2026, 10, 14);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
  await inspectColors('retained-after-local-day-change');
  expect(
    tester.widget<Text>(find.text('2026-10-14')).style!.color,
    isNot(beforeColor),
  );
  expect(jsonEncode(operations.map((e) => e.toJson()).toList()), before);
  expect(writes, 0);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final brightness in Brightness.values) {
    for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'Food date colors and local resume ${brightness.name} ${sample.$1} ${sample.$2}x',
        (tester) async {
          tester.view.physicalSize = Size(sample.$1, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFoodExpirationColorWorkflow(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
        },
      );
    }
  }
}
