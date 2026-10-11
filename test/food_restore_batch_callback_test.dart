import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

const _writer = '00000000-0000-4000-8000-000000000094';

FoodState _deletedGroup() => projectFood([
  for (var i = 1; i <= 3; i++)
    FoodOperation(
      id: '$_writer:$i',
      order: i,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(i + 800).toString().padLeft(12, '0')}',
      ],
      details: const FoodDetails(name: 'Batch beans', expiry: '2026-10-15'),
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-11T00:00:00Z',
    ),
  FoodOperation(
    id: '$_writer:4',
    order: 4,
    action: FoodAction.remove,
    targets: [
      for (var i = 1; i <= 3; i++)
        '00000000-0000-4000-8000-${(i + 800).toString().padLeft(12, '0')}',
    ],
  ),
]);

void main() {
  testWidgets(
    'Deleted group Restore calls one batch with exact observed containers; individual Restore stays single',
    (tester) async {
      final food = _deletedGroup();
      final batches = <List<FoodContainer>>[], singles = <FoodContainer>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FoodInventoryPage(
            state: food,
            now: () => DateTime(2026, 10, 11),
            onAdd: (_, _) {},
            onRemove: (_) {},
            onRestore: singles.add,
            onRestoreBatch: (items) => batches.add(items),
            onContents: (_, _) {},
            onDetails: (_, _, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseFoodView(tester, 'Deleted');
      await tester.tap(find.byTooltip('Restore Batch beans containers'));
      await tester.pumpAndSettle();
      expect(batches, hasLength(1));
      expect(
        batches.single,
        orderedEquals(food.view(FoodView.deleted).single.containers),
      );
      expect(
        batches.single.map((e) => e.id).toSet(),
        food.deleted.map((e) => e.id).toSet(),
      );
      expect(singles, isEmpty);
      await tester.tap(find.byTooltip('Inspect Batch beans containers'));
      await tester.pumpAndSettle();
      final item = food.view(FoodView.deleted).single.containers.first;
      await tester.ensureVisible(
        find.byKey(ValueKey('food-container-restore:${item.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('food-container-restore:${item.id}')),
      );
      await tester.pumpAndSettle();
      expect(singles, [item]);
      expect(batches, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Deleted group Restore preserves optional-callback fallback and busy guard',
    (tester) async {
      final food = _deletedGroup();
      final singles = <FoodContainer>[];
      var busy = false;
      late void Function(VoidCallback) update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return FoodInventoryPage(
                state: food,
                busy: busy,
                now: () => DateTime(2026, 10, 11),
                onAdd: (_, _) {},
                onRemove: (_) {},
                onRestore: singles.add,
                onContents: (_, _) {},
                onDetails: (_, _, _) {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseFoodView(tester, 'Deleted');
      await tester.tap(find.byTooltip('Restore Batch beans containers'));
      await tester.pumpAndSettle();
      expect(
        singles,
        orderedEquals(food.view(FoodView.deleted).single.containers),
      );
      singles.clear();
      update(() => busy = true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is IconButton &&
                    w.tooltip == 'Restore Batch beans containers',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(singles, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
