import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/expiration_presentation.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const _stockA = '11111111-1111-4111-8111-111111111111';
const _stockB = '22222222-2222-4222-8222-222222222222';
const _inbox = '33333333-3333-4333-8333-333333333333';

FoodContainer _item(
  String id,
  String name, {
  String? expiry = '2026-10-23',
  String brand = 'Acme',
  String location = 'Pantry',
  String retention = '',
  bool deleted = false,
}) => FoodContainer(
  id: id,
  details: FoodDetails(
    name: name,
    expiry: expiry,
    brand: brand,
    location: location,
    retention: retention,
  ),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-20T00:00:00Z',
  deletions: deleted ? {'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa:1'} : {},
  deletedOrder: deleted ? 1 : 0,
  lastDeletionId: deleted ? 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa:1' : null,
  contentsEdits: {},
);

List<FoodContainer> _items() => [
  _item(_stockA, 'Memo stock A'),
  _item(_stockB, 'Memo stock B', brand: 'Other', location: 'Freezer'),
  _item(_inbox, 'Memo inbox', expiry: null),
  _item(
    '44444444-4444-4444-8444-444444444444',
    'Memo retained',
    retention: 'Emergency',
  ),
  _item('55555555-5555-4555-8555-555555555555', 'Memo deleted', deleted: true),
];

/// Observe the real domain grouping work, not a page implementation counter.
class _CountingFood extends FoodState {
  _CountingFood(super.containers);
  int views = 0;
  @override
  List<FoodGroup> view(
    FoodView view, {
    String search = '',
    Set<String> reasons = const {},
    Set<String> brands = const {},
    Set<String> locations = const {},
  }) {
    views++;
    return super.view(
      view,
      search: search,
      reasons: reasons,
      brands: brands,
      locations: locations,
    );
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Food grouping survives focus busy and midnight paint ${brightness.name}',
      (tester) async {
        final food = _CountingFood([_item(_stockA, 'Memo stock A')]);
        final workspace = Object();
        var now = DateTime(2026, 10, 20, 23, 59, 59), busy = false, writes = 0;
        late StateSetter update;
        final colors = ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: colors),
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return FoodInventoryPage(
                  state: food,
                  workspaceIdentity: workspace,
                  busy: busy,
                  now: () => now,
                  onAdd: (_, _) => writes++,
                  onRemove: (_) => writes++,
                  onRestore: (_) => writes++,
                  onDetails: (_, _, _) => writes++,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(food.views, 2, reason: 'Stock and Inbox derive once.');
        final before = tester
            .widget<Text>(find.text('2026-10-23'))
            .style!
            .color;
        await tester.tap(find.byKey(const ValueKey('food-search')));
        await tester.pumpAndSettle();
        final search = tester.widget<TextField>(
          find.byKey(const ValueKey('food-search')),
        );
        final focus = tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('food-search')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode;
        update(() => busy = true);
        await tester.pumpAndSettle();
        update(() => busy = false);
        await tester.pumpAndSettle();
        expect(food.views, 2);
        expect(focus.hasFocus, isTrue);
        expect(search.controller!.text, isEmpty);

        now = DateTime(2026, 10, 21);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        final after = tester.widget<Text>(find.text('2026-10-23')).style!.color;
        expect(after, foodExpiryColor('2026-10-23', now, colors));
        expect(
          after,
          isNot(before),
          reason: 'Memo cannot freeze date urgency.',
        );
        expect(food.views, 2, reason: 'Midnight changes paint, not grouping.');
        expect(focus.hasFocus, isTrue);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Food memo observes every filter query view and projection input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var food = _CountingFood(_items());
      var workspace = Object();
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return FoodInventoryPage(
                state: food,
                workspaceIdentity: workspace,
                onAdd: (_, _) {},
                onRemove: (_) {},
                onRestore: (_) {},
                onDetails: (_, _, _) {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.state<FoodInventoryPageState>(
        find.byType(FoodInventoryPage),
      );
      expect(food.views, 2);
      // The mounted parent rebuild driver retains the actual page state while
      // exercising in-place filter changes; no protected State API is called.
      update(() => page.brands.add('Acme'));
      await tester.pumpAndSettle();
      expect(food.views, 4);
      expect(find.text('Memo stock A'), findsOneWidget);
      expect(find.text('Memo stock B'), findsNothing);
      update(() => page.locations.add('Pantry'));
      await tester.pumpAndSettle();
      expect(food.views, 6);
      update(() => page.reasons.add('Emergency'));
      await tester.pumpAndSettle();
      expect(food.views, 8);
      update(() => page.view = FoodView.retained);
      await tester.pumpAndSettle();
      expect(food.views, 9);
      expect(find.text('Memo retained'), findsOneWidget);
      expect(find.text('Memo stock A'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('food-search')), 'Memo');
      await tester.pumpAndSettle();
      expect(food.views, 10);
      expect(
        find.text('Memo stock B'),
        findsOneWidget,
        reason: 'Search still bypasses inactive filter restrictions.',
      );
      expect(find.text('Memo deleted'), findsOneWidget);
      update(() => page.brands = {'Acme'});
      await tester.pumpAndSettle();
      expect(food.views, 10, reason: 'Equal set contents reuse grouping.');
      update(() => page.brands.add('Other'));
      await tester.pumpAndSettle();
      expect(food.views, 11, reason: 'In-place mutations invalidate grouping.');

      final old = food;
      update(
        () => food = _CountingFood([
          ...food.containers,
          _item('66666666-6666-4666-8666-666666666666', 'Memo new arrival'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(food.views, 1);
      expect(old.views, 11);
      expect(find.text('Memo new arrival'), findsOneWidget);
      update(() => page.bulkSelected.add(_stockA));
      await tester.pumpAndSettle();
      expect(page.bulkSelected, {_stockA});
      update(() => workspace = Object());
      await tester.pumpAndSettle();
      expect(food.views, 2);
      expect(page.bulkSelected, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Food publication keeps selection and an owned focused draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var food = _CountingFood(_items()), busy = false, writes = 0;
    final workspace = Object();
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return FoodInventoryPage(
              state: food,
              workspaceIdentity: workspace,
              busy: busy,
              onAdd: (_, _) => writes++,
              onRemove: (_) => writes++,
              onRestore: (_) => writes++,
              onDetails: (_, _, _) => writes++,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('food-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select matching active containers'));
    await tester.pumpAndSettle();
    final page = tester.state<FoodInventoryPageState>(
      find.byType(FoodInventoryPage),
    );
    expect(page.bulkSelected, {_stockA, _stockB, _inbox});
    final grouped = food.views;
    update(() => busy = true);
    await tester.pumpAndSettle();
    update(() => busy = false);
    await tester.pumpAndSettle();
    expect(page.bulkSelected, {_stockA, _stockB, _inbox});
    expect(food.views, grouped);
    await tester.tap(find.byTooltip('Clear Selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memo stock A'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Food name');
    await tester.enterText(name, 'Owned draft stays here');
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(name).controller!;
    controller.selection = const TextSelection.collapsed(offset: 4);
    final focus = tester
        .widget<EditableText>(
          find.descendant(of: name, matching: find.byType(EditableText)),
        )
        .focusNode;
    expect(focus.hasFocus, isTrue);
    update(
      () => food = _CountingFood([
        ...food.containers,
        _item('66666666-6666-4666-8666-666666666666', 'Memo unrelated arrival'),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      identical(tester.widget<TextField>(name).controller, controller),
      isTrue,
    );
    expect(controller.text, 'Owned draft stays here');
    expect(controller.selection.extentOffset, 4);
    expect(focus.hasFocus, isTrue);
    expect(writes, 0);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Memo stock A'), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
