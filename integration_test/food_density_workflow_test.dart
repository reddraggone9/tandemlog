import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/inventory.dart';
import '../tool/food_preview.dart';
import 'food_preview_workflow_test.dart' as pixels;

List<FoodOperation> densityFixture() {
  const writer = '00000000-0000-4000-8000-000000000010';
  const names = [
    'Oat milk',
    'Rice',
    'Peas',
    'Yogurt',
    'Beans',
    'Carrots',
    'Flour',
    'Eggs',
    'Lentils',
    'Pasta',
    'Soup',
    'Tomatoes',
  ];
  return List.generate(
    names.length,
    (i) => FoodOperation(
      id: '$writer:${i + 1}',
      order: i + 1,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(i + 1).toRadixString(16).padLeft(12, '0')}',
      ],
      details: FoodDetails(
        name: names[i],
        brand: 'Sample Foods',
        expiry: '2026-10-${11 + i}',
        size: '500 g',
        location: 'Freezer',
      ),
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-10T00:00:00Z',
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'dense collapsed rows preserve targets in both themes and enlarged text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final measurements = <Map<String, Object>>[];
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpWidget(
        FoodPreviewApp(initialOperations: densityFixture()),
      );
      await tester.pumpAndSettle();
      await pixels.capture(tester, 'density-warmup-not-evidence');
      for (final brightness in [Brightness.dark, Brightness.light]) {
        for (final scale in [1.0, 2.0]) {
          for (final width in [390.0, 1200.0]) {
            final name =
                'density-${brightness.name}-${scale.toInt()}x-${width.toInt()}';
            tester.view.physicalSize = Size(width, 850);
            await tester.pumpWidget(
              FoodPreviewApp(
                key: ValueKey(name),
                initialOperations: densityFixture(),
                brightness: brightness,
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();
            await pixels.capture(tester, name);
            final viewport = tester.getRect(find.byType(ListView));
            final cards = find
                .byType(Card)
                .evaluate()
                .map((e) => tester.getRect(find.byWidget(e.widget)))
                .toList();
            final fullyVisible = cards
                .where(
                  (r) => r.top >= viewport.top && r.bottom <= viewport.bottom,
                )
                .toList();
            final inspect = find.byTooltip('Inspect Oat milk containers');
            expect(tester.getSize(inspect).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(inspect).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            measurements.add({
              'name': name,
              'viewport': '${width.toInt()}x850',
              'theme': brightness.name,
              'textScale': scale,
              'fixtureGroups': 12,
              'fullyVisibleGroups': fullyVisible.length,
              'rowHeights': fullyVisible.map((r) => r.height).toList(),
              'listViewportHeight': viewport.height,
              'minimumActionTarget': 48,
            });
          }
        }
      }
      final output = Platform.environment['FOOD_PREVIEW_EVIDENCE'];
      if (output != null) {
        await File('$output/density-measurements.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(measurements)}\n',
        );
      }
    },
  );
}
