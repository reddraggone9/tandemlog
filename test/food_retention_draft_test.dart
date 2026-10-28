import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/tag_input.dart';
import 'food_stock_toolbar_workflow_test.dart' show chooseFoodView;

void main() {
  testWidgets('Add omits retention and creates ordinary stock', (tester) async {
    FoodDetails? added;
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: FoodState([]),
          onAdd: (details, _) => added = details,
          onRemove: (_) {},
          onRestore: (_) {},
          onDetails: (_, _, _, _) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    expect(find.byType(TagInput), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Synthetic beans',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Expiration'),
      '2027-06-01',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(added?.name, 'Synthetic beans');
    expect(added?.retention, isEmpty);
  });

  testWidgets('Edit retains reason creation, clear and exact Save', (
    tester,
  ) async {
    const writer = '00000000-0000-4000-8000-000000000051';
    final state = projectFood([
      FoodOperation(
        id: '$writer:1',
        order: 1,
        action: FoodAction.add,
        targets: ['00000000-0000-4000-8000-000000000052'],
        details: const FoodDetails(
          name: 'Synthetic retained beans',
          expiry: '2027-06-01',
          retention: 'Emergency',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-12T00:00:00Z',
      ),
    ]);
    FoodDetails? saved;
    List<String>? fields;
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          state: state,
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onDetails: (_, details, changed, _) {
            saved = details;
            fields = changed;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await chooseFoodView(tester, 'Retained');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic retained beans'));
    await tester.pumpAndSettle();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, {
      'Emergency',
    });
    await tester.tap(find.byTooltip('Clear retention reason'));
    final query = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
    );
    await tester.enterText(query, 'Synthetic trip');
    await tester.pumpAndSettle();
    tester.widget<TextField>(query).onSubmitted!('Synthetic trip');
    await tester.pumpAndSettle();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, {
      'Synthetic trip',
    });
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pumpAndSettle();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved?.retention, isEmpty);
    expect(fields, contains('retention'));
    expect(
      state.active.single.details.retention,
      'Emergency',
      reason:
          'The editor only sends a command; it does not mutate its input state',
    );
  });
}
