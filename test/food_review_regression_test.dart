import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/presentation/tag_input.dart';
import '../tool/food_preview.dart';

const writer = '00000000-0000-4000-8000-000000000010';
String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
FoodOperation add(int n, List<String> ids) => FoodOperation(
  id: '$writer:$n',
  order: n,
  action: FoodAction.add,
  targets: ids,
  details: const FoodDetails(name: 'Rice', expiry: '2026-10-15'),
  createdAt: '2026-10-10T00:00:00Z',
  contents: const Contents.fraction(1, 1),
);
void main() {
  testWidgets(
    '101-container group removal and Undo use bounded captured batches',
    (tester) async {
      final events = [
        add(1, List.generate(100, (i) => id(i + 1))),
        add(2, [id(101)]),
      ];
      await tester.pumpWidget(FoodPreviewApp(initialOperations: events));
      await tester.pumpAndSettle();
      final page = tester.widget<FoodInventoryPage>(
        find.byType(FoodInventoryPage),
      );
      page.onRemove(
        page.state.groups.single.containers.map((e) => e.id).toList(),
      );
      await tester.pumpAndSettle();
      final removed = tester.widget<FoodInventoryPage>(
        find.byType(FoodInventoryPage),
      );
      expect(removed.state.deleted, hasLength(101));
      removed.onUndo!();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
            .state
            .active,
        hasLength(101),
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'known wrong-kind edit reference fails even while target creation missing',
    () {
      final seed = add(1, [id(1)]);
      final orphan = FoodOperation(
        id: '$writer:2',
        order: 2,
        action: FoodAction.edit,
        targets: [id(2)],
        contents: const Contents.fraction(1, 2),
        observedEdits: [seed.id],
      );
      expect(() => projectFood([seed, orphan]), throwsFormatException);
    },
  );
  testWidgets('typed retention reason survives direct Add', (tester) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Review beans',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
      ),
      'Review trip',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Add').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final page = tester.widget<FoodInventoryPage>(
      find.byType(FoodInventoryPage),
    );
    expect(
      page.state.active.where((e) => e.details.name == 'Review beans'),
      hasLength(1),
    );
    expect(
      page.state.active
          .singleWhere((e) => e.details.name == 'Review beans')
          .details
          .retention,
      'Review trip',
    );
    await tester.tap(find.text('Retained'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ExpansionTile, 'Review trip'));
    await tester.pumpAndSettle();
    expect(find.text('Review beans'), findsOneWidget);
  });
  testWidgets('repeated dialog Cancel callback cannot pop food page', (
    tester,
  ) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    final cancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
        .onPressed!;
    cancel();
    cancel();
    await tester.pumpAndSettle();
    expect(find.text('Food inventory'), findsOneWidget);
  });
  test('known removal before physical creation is rejected', () {
    final seed = add(2, [id(1)]);
    final remove = FoodOperation(
      id: '$writer:1',
      order: 1,
      action: FoodAction.remove,
      targets: [id(1)],
    );
    expect(() => projectFood([seed, remove]), throwsFormatException);
  });
  testWidgets('active retention composition is not staged by submit', (
    tester,
  ) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    final query = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
    );
    final field = tester.widget<TextField>(query);
    field.controller!.value = const TextEditingValue(
      text: 'Partial',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 0, end: 7),
    );
    await tester.pump();
    field.onSubmitted!('Partial');
    await tester.pump();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, isEmpty);
  });
}
