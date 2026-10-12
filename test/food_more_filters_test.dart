import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

void main() {
  testWidgets(
    'reason dialog is Retained-only; search bypass and dormant reasons survive views',
    (tester) async {
      const writer = '00000000-0000-4000-8000-000000000061';
      final operations = <FoodOperation>[
        for (final pair in [
          const FoodDetails(name: 'Synthetic stock', expiry: '2027-06-01'),
          const FoodDetails(
            name: 'Synthetic retained A',
            expiry: '2027-06-01',
            retention: 'Emergency',
          ),
          const FoodDetails(
            name: 'Synthetic retained B',
            expiry: '2027-06-01',
            retention: 'Reference',
          ),
          const FoodDetails(
            name: 'Synthetic deleted',
            expiry: '2027-06-01',
            retention: 'Reference',
          ),
        ].indexed)
          FoodOperation(
            id: '$writer:${pair.$1 + 1}',
            order: pair.$1 + 1,
            action: FoodAction.add,
            targets: [
              '00000000-0000-4000-8000-${(100 + pair.$1).toString().padLeft(12, '0')}',
            ],
            details: pair.$2,
            contents: const Contents.fraction(1, 1),
            createdAt: '2026-10-12T00:00:00Z',
          ),
        FoodOperation(
          id: '$writer:5',
          order: 5,
          action: FoodAction.remove,
          targets: ['00000000-0000-4000-8000-000000000103'],
        ),
      ];
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FoodInventoryPage(
            state: projectFood(operations),
            onAdd: (_, _) => writes++,
            onRemove: (_) => writes++,
            onRestore: (_) => writes++,
            onContents: (_, _) => writes++,
            onDetails: (_, _, _) => writes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> filters() async {
        await tester.tap(find.byKey(const ValueKey('food-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('More filters…'));
        await tester.pumpAndSettle();
      }

      await filters();
      expect(
        find.byKey(const ValueKey('food-reason-filter-query')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await chooseFoodView(tester, 'Retained');
      expect(
        find.byKey(const ValueKey('food-reason-filter-query')),
        findsNothing,
      );
      await filters();
      final reason = find.byKey(const ValueKey('food-reason-filter-query'));
      expect(find.text('Retention reason'), findsOneWidget);
      expect(
        tester.widget<TextField>(reason).decoration?.hintText,
        'All reasons',
      );
      await tester.tap(reason);
      await tester.enterText(reason, 'emer');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-option-Reference')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tag-option-Emergency')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic retained A'), findsOneWidget);
      expect(find.text('Synthetic retained B'), findsNothing);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'Synthetic',
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic retained B'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      await tester.tap(find.byTooltip('Clear food search'));
      await tester.pumpAndSettle();
      await chooseFoodView(tester, 'Stock');
      expect(find.text('Synthetic stock'), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      await chooseFoodView(tester, 'Deleted');
      expect(find.text('Synthetic deleted'), findsOneWidget);
      await filters();
      expect(reason, findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await chooseFoodView(tester, 'Retained');
      expect(find.text('Synthetic retained A'), findsOneWidget);
      expect(find.text('Synthetic retained B'), findsNothing);
      expect(
        tester
            .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
            .reasons,
        {'Emergency'},
      );
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
