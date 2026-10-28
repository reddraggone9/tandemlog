import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

Future<void> verifyFoodAddAnother(
  WidgetTester tester, {
  bool deleted = false,
  bool retained = false,
  Future<void> Function(String)? capture,
}) async {
  const writer = '00000000-0000-4000-8000-000000000093';
  const id = '00000000-0000-4000-8000-000000000799';
  final state = projectFood([
    FoodOperation(
      id: '$writer:1',
      order: 1,
      action: FoodAction.add,
      targets: [id],
      details: FoodDetails(
        name: 'Template beans',
        brand: 'Test brand',
        expiry: '2026-10-15',
        size: '500 g',
        location: 'Pantry',
        retention: retained ? 'Reference only' : '',
        estimated: true,
      ),
      contents: const Contents.fraction(1, 3),
      createdAt: '2026-10-11T00:00:00Z',
    ),
    if (deleted)
      FoodOperation(
        id: '$writer:2',
        order: 2,
        action: FoodAction.remove,
        targets: [id],
      ),
  ]);
  final before = state.containers.map((e) => e.toJson()).toList();
  final added = <(FoodDetails, int)>[];
  final other = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        platform: TargetPlatform.linux,
      ),
      home: FoodInventoryPage(
        state: state,
        now: () => DateTime(2026, 10, 11),
        onAdd: (details, count) => added.add((details, count)),
        onRemove: (_) => other.add('remove'),
        onRestore: (_) => other.add('restore'),
        onDetails: (_, _, _, _) => other.add('details'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final search = find.byKey(const ValueKey('food-search'));
  await tester.enterText(search, 'Template beans');
  await tester.pumpAndSettle();
  final searchValue = tester.widget<TextField>(search).controller!.value;
  final saveAction = find.byKey(const ValueKey('food-save-action'));
  Finder field(String label) => find.widgetWithText(TextField, label);
  Future<void> open({bool secondary = true}) async {
    if (secondary) {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Template beans',
        ),
        buttons: kSecondaryMouseButton,
      );
    } else {
      await tester.tap(find.byTooltip('Actions for Template beans'));
    }
    await tester.pumpAndSettle();
    final action = find.widgetWithText(PopupMenuItem<String>, 'Add another…');
    expect(action, findsOneWidget);
    if (deleted) expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
    expect(added, isEmpty);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Add food'), findsOneWidget);
    expect(find.text('Retention reason'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Retention reason',
      ),
      findsNothing,
    );
    for (final pair in [
      ('Food name', 'Template beans'),
      ('Brand', 'Test brand'),
      ('Container size', '500 g'),
      ('Location', 'Pantry'),
      ('Expiration', ''),
      ('Containers to add', '1'),
    ]) {
      expect(
        tester.widget<TextField>(field(pair.$1)).controller!.text,
        pair.$2,
      );
    }
    expect(
      tester.widget<TextField>(field('Expiration')).focusNode!.hasFocus,
      true,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reference only'),
      ),
      findsNothing,
    );
    expect(added, isEmpty);
    expect(other, isEmpty);
    expect(state.containers.map((e) => e.toJson()).toList(), before);
    await capture?.call(
      'add-another-${deleted
          ? 'deleted'
          : retained
          ? 'retained'
          : 'active'}',
    );
  }

  await open();
  await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  await tester.pumpAndSettle();
  expect(added, isEmpty);
  expect(tester.widget<TextField>(search).controller!.value, searchValue);
  await open(secondary: false);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('Add food'), findsNothing);
  expect(added, isEmpty);
  await open();
  await tester.ensureVisible(saveAction);
  await tester.tap(saveAction);
  await tester.pumpAndSettle();
  expect(find.text('Expiration is required.'), findsOneWidget);
  expect(added, isEmpty);
  await tester.ensureVisible(field('Expiration'));
  await tester.tap(field('Expiration'));
  await tester.enterText(field('Expiration'), '2026-99-99');
  await tester.tap(saveAction);
  await tester.pumpAndSettle();
  expect(added, isEmpty);
  await tester.tap(field('Expiration'));
  await tester.enterText(field('Expiration'), '2026-12-10');
  await tester.pump();
  expect(
    find.descendant(of: saveAction, matching: find.text('Review errors')),
    findsNothing,
  );
  expect(added, isEmpty, reason: 'Correcting the draft cannot Add');
  expect(other, isEmpty);
  expect(state.containers.map((e) => e.toJson()).toList(), before);
  expect(
    find.descendant(of: saveAction, matching: find.text('Add')),
    findsOneWidget,
  );
  await tester.tap(saveAction);
  await tester.pumpAndSettle();
  expect(added, hasLength(1));
  expect(added.single.$2, 1);
  expect(
    added.single.$1.toJson(),
    const FoodDetails(
      name: 'Template beans',
      brand: 'Test brand',
      expiry: '2026-12-10',
      size: '500 g',
      location: 'Pantry',
      estimated: null,
    ).toJson(),
  );
  expect(other, isEmpty);
  expect(state.containers.map((e) => e.toJson()).toList(), before);
  expect(tester.widget<TextField>(search).controller!.value, searchValue);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('disposing a dirty Food decision releases the close request', (
    tester,
  ) async {
    final key = GlobalKey<FoodInventoryPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: FoodInventoryPage(
          key: key,
          state: projectFood([]),
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onDetails: (_, _, _, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Private draft',
    );
    var completed = false;
    unawaited(
      key.currentState!.requestCloseEditor().whenComplete(
        () => completed = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard food changes?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(
      completed,
      true,
      reason: 'Navigator disposal releases pending close admission',
    );
    expect(tester.takeException(), isNull);
  });
  for (final variant in [(false, false), (false, true), (true, true)]) {
    testWidgets('Add another prefilled independent draft $variant', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await verifyFoodAddAnother(
        tester,
        deleted: variant.$1,
        retained: variant.$2,
      );
    });
  }
}
