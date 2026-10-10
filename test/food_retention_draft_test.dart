import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/presentation/tag_input.dart';
import '../tool/food_preview.dart';

void main() {
  testWidgets('removing newly created retention chip stays removed on Add', (
    tester,
  ) async {
    await tester.pumpWidget(const FoodPreviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Review beans',
    );
    final query = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
    );
    await tester.enterText(query, 'Review trip');
    await tester.pumpAndSettle();
    tester.widget<TextField>(query).onSubmitted!('Review trip');
    await tester.pumpAndSettle();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, {
      'Review trip',
    });
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pumpAndSettle();
    expect(tester.widget<TagInput>(find.byType(TagInput)).selected, isEmpty);
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
      page.state.active
          .singleWhere((e) => e.details.name == 'Review beans')
          .details
          .retention,
      isEmpty,
    );
  });
}
