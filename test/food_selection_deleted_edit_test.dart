import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'support/ux_capture.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(() async {
    await loadSdkRoboto();
    await loadUxIcons();
  });
  testWidgets(
    'long press selects physical group; deleted food edits without restore',
    (tester) async {
      const writer = '00000000-0000-4000-8000-000000000094';
      const id = '00000000-0000-4000-8000-000000000801';
      final events = <FoodOperation>[
        FoodOperation(
          id: '$writer:1',
          order: 1,
          action: FoodAction.add,
          targets: [id],
          details: const FoodDetails(name: 'Beans', expiry: '2026-10-28'),
          contents: const Contents.fraction(1, 1),
          createdAt: '2026-10-26T00:00:00Z',
        ),
      ];
      var restores = 0;
      late StateSetter update;
      final edits = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) =>
              RepaintBoundary(key: const ValueKey('ux-root'), child: child!),
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return FoodInventoryPage(
                state: projectFood(events),
                onAdd: (_, _) {},
                onRemove: (_) {},
                onRestore: (_) => restores++,
                onDetails: (items, details, fields) {
                  edits.add(details.name);
                  update(
                    () => events.add(
                      FoodOperation(
                        id: '$writer:3',
                        order: 3,
                        action: FoodAction.edit,
                        targets: items.map((e) => e.id).toList(),
                        details: details,
                        fields: fields,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await captureUx(tester, 'food-selected-800');
      // Remount to leave the page-local selection, then use search's Deleted group.
      await tester.pumpWidget(const SizedBox());
      events.add(
        FoodOperation(
          id: '$writer:2',
          order: 2,
          action: FoodAction.remove,
          targets: [id],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) =>
              RepaintBoundary(key: const ValueKey('ux-root'), child: child!),
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return FoodInventoryPage(
                state: projectFood(events),
                onAdd: (_, _) {},
                onRemove: (_) {},
                onRestore: (_) => restores++,
                onDetails: (items, details, fields) {
                  edits.add(details.name);
                  update(
                    () => events.add(
                      FoodOperation(
                        id: '$writer:3',
                        order: 3,
                        action: FoodAction.edit,
                        targets: [id],
                        details: details,
                        fields: fields,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'Beans',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beans').last);
      await tester.pumpAndSettle();
      await captureUx(tester, 'food-deleted-editor-800');
      await tester.enterText(
        find.widgetWithText(TextField, 'Food name'),
        'Corrected beans',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(edits, ['Corrected beans']);
      final container = projectFood(events).containers.single;
      expect(container.deleted, isTrue);
      expect(container.deletions, {'$writer:2'});
      expect(container.details.name, 'Corrected beans');
      expect(restores, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
