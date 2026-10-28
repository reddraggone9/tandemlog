import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

import 'support/food_product_fields.dart';
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
          theme: tandemlogTheme(Brightness.dark),
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
                onDetails: (items, details, fields, products) {
                  edits.add(details.name);
                  update(
                    () => events.add(
                      FoodOperation(
                        id: '$writer:3',
                        order: 3,
                        action: FoodAction.edit,
                        targets: items.map((e) => e.id).toList(),
                        details: details,
                        fields: foodTouchedFields(fields, products),
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
          theme: tandemlogTheme(Brightness.dark),
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
                onDetails: (items, details, fields, products) {
                  edits.add(details.name);
                  update(
                    () => events.add(
                      FoodOperation(
                        id: '$writer:3',
                        order: 3,
                        action: FoodAction.edit,
                        targets: [id],
                        details: details,
                        fields: foodTouchedFields(fields, products),
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

  testWidgets(
    'group long press selects all observed IDs and respects busy and pending',
    (tester) async {
      const writer = '00000000-0000-4000-8000-000000000094';
      final events = [
        for (var i = 1; i <= 3; i++)
          FoodOperation(
            id: '$writer:$i',
            order: i,
            action: FoodAction.add,
            targets: [
              '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            ],
            details: FoodDetails(
              name: i == 3 ? 'Rice' : 'Beans',
              expiry: '2026-10-28',
            ),
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-26T00:00:00Z',
          ),
      ];
      late StateSetter update;
      var busy = true, pending = false, writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return FoodInventoryPage(
                state: projectFood(events),
                busy: busy,
                hasPendingSave: () => pending,
                onAdd: (_, _) => writes++,
                onRemove: (_) => writes++,
                onRestore: (_) => writes++,
                onDetails: (_, _, _, _) => writes++,
              );
            },
          ),
        ),
      );
      await tester.longPress(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsNothing);
      update(() {
        busy = false;
        pending = true;
      });
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsNothing);
      update(() => pending = false);
      await tester.pumpAndSettle();
      // A prepared Save can become pending after pointer-down without rebuilding
      // the page. Recognition must re-read the current host receipt state.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Beans')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      pending = true;
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsNothing);
      pending = false;
      await tester.longPress(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.text('Beans'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incoming restore refuses a deleted-food draft without retargeting Save',
    (tester) async {
      const writer = '00000000-0000-4000-8000-000000000094';
      const id = '00000000-0000-4000-8000-000000000801';
      final events = [
        FoodOperation(
          id: '$writer:1',
          order: 1,
          action: FoodAction.add,
          targets: [id],
          details: const FoodDetails(name: 'Beans', expiry: '2026-10-28'),
          contents: const Contents.fraction(1, 1),
          createdAt: '2026-10-26T00:00:00Z',
        ),
        FoodOperation(
          id: '$writer:2',
          order: 2,
          action: FoodAction.remove,
          targets: [id],
        ),
      ];
      late StateSetter update;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return FoodInventoryPage(
                state: projectFood(events),
                onAdd: (_, _) {},
                onRemove: (_) {},
                onRestore: (_) {},
                onDetails: (_, _, _, _) => saves++,
              );
            },
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'Beans',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beans').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Food name'),
        'Draft beans',
      );
      update(
        () => events.add(
          FoodOperation(
            id: '$writer:3',
            order: 3,
            action: FoodAction.restore,
            targets: [id],
            observedDeletes: const ['$writer:2'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(
        find.textContaining('workspace or containers changed'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Draft beans'), findsOneWidget);
      expect(projectFood(events).containers.single.deleted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
