import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

void main() {
  testWidgets('a failed durable Add retains editor and exact visible draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          onAdd: (_, _) => throw StateError('synthetic save failure'),
          onRemove: (_) {},
          onRestore: (_) {},
          onContents: (_, _) {},
          onDetails: (_, _, _) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Synthetic Rice',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add food'), findsOneWidget);
    expect(find.text('Synthetic Rice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending receipt prevents opening a different Add editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          savePending: true,
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onContents: (_, _) {},
          onDetails: (_, _, _) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add food'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
  });

  testWidgets('failed prepared Save retries the frozen original draft', (
    tester,
  ) async {
    var pending = false, calls = 0;
    final names = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          hasPendingSave: () => pending,
          onAdd: (details, _) {
            names.add(details.name);
            if (++calls == 1) {
              pending = true;
              throw StateError('ambiguous append');
            }
            pending = false;
          },
          onRemove: (_) {},
          onRestore: (_) {},
          onContents: (_, _) {},
          onDetails: (_, _, _) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Synthetic Rice',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Food name'))
          .enabled,
      false,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Retry save'));
    await tester.pumpAndSettle();
    expect(names, ['Synthetic Rice', 'Synthetic Rice']);
    expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated captured discard decision cannot pop another route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onContents: (_, _) {},
          onDetails: (_, _, _) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Synthetic Rice',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    final decision = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Discard'))
        .onPressed!;
    decision();
    await tester.pumpAndSettle();
    expect(() => decision(), returnsNormally);
    expect(find.text('Food inventory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a retained rendered removal callback keeps its workspace origin',
    (tester) async {
      final state = projectFood([
        FoodOperation(
          id: '00000000-0000-4000-8000-000000000010:1',
          order: 1,
          action: FoodAction.add,
          targets: ['00000000-0000-4000-8000-000000000002'],
          details: const FoodDetails(
            name: 'Synthetic Rice',
            expiry: '2026-10-15',
          ),
          contents: const Contents.fraction(1, 1),
          createdAt: '2026-10-10T00:00:00Z',
        ),
      ]);
      final key = GlobalKey<FoodInventoryPageState>();
      var first = 0, second = 0;
      Widget page(bool other) => MaterialApp(
        home: FoodInventoryPage(
          key: key,
          state: state,
          onAdd: (_, _) {},
          onRemove: (_) {
            if (other) {
              second++;
            } else {
              first++;
            }
          },
          onRestore: (_) {},
          onContents: (_, _) {},
          onDetails: (_, _, _) {},
        ),
      );
      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();
      final callback = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  w.tooltip == 'Remove one Synthetic Rice container',
            ),
          )
          .onPressed!;
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(first, 1);
      expect(second, 0);
    },
  );
}
