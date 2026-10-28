import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const _writer = '00000000-0000-4000-8000-000000000095';

FoodOperation _add(
  int order,
  String id,
  String name, {
  String brand = '',
  String size = '',
  String expiry = '2026-11-01',
}) => FoodOperation(
  id: '$_writer:$order',
  order: order,
  action: FoodAction.add,
  targets: [id],
  details: FoodDetails(name: name, brand: brand, size: size, expiry: expiry),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-26T00:00:00Z',
);

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _events = [
  _add(1, _id(1), 'Beans'),
  _add(2, _id(2), 'Milk', brand: 'Great Value', size: '1 gal'),
  _add(
    3,
    _id(3),
    'Milk',
    brand: 'Great Value',
    size: '1 gal',
    expiry: '2026-11-05',
  ),
  _add(4, _id(4), 'Rice'),
];

typedef _Edit = ({
  List<String> ids,
  List<String> fields,
  FoodProductChange products,
});

Future<List<_Edit>> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  List<FoodOperation>? events,
  List<(FoodDetails, int)>? adds,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final edits = <_Edit>[];
  await tester.pumpWidget(
    MaterialApp(
      home: FoodInventoryPage(
        state: projectFood(events ?? _events),
        onAdd: (details, count) => adds?.add((details, count)),
        onRemove: (_) {},
        onRestore: (_) {},
        onDetails: (items, _, fields, products) => edits.add((
          ids: items.map((e) => e.id).toList(),
          fields: fields,
          products: products,
        )),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return edits;
}

FocusNode _rowFocus(WidgetTester tester, String name) => Focus.of(
  tester.element(
    find
        .descendant(
          of: find.ancestor(
            of: find.text(name).first,
            matching: find.byType(InkWell),
          ),
          matching: find.byType(Semantics),
        )
        .first,
  ),
);

Future<void> _longPress(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name).first);
  await tester.pumpAndSettle();
}

Future<void> _ctrlTap(WidgetTester tester, Finder target) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.tap(target);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Up/Down move between Food rows; Shift extends the selection', (
    tester,
  ) async {
    await _pump(tester);
    _rowFocus(tester, 'Beans').requestFocus();
    await tester.pumpAndSettle();
    // Rows sort by expiration, then description: Beans, Rice, Milk, Milk.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowFocus(tester, 'Rice').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_rowFocus(tester, 'Beans').hasPrimaryFocus, isTrue);
    // Shift+Down selects from the focused row through the next one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    // Narrow layouts keep the dialog behind Edit.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Edit 3 containers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide selection edits in the side pane; one whole row returns to single',
    (tester) async {
      await _pump(tester, size: const Size(1400, 900));
      await _longPress(tester, 'Beans');
      expect(find.byKey(const ValueKey('nameApply')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await _ctrlTap(tester, find.text('Rice'));
      expect(
        find.byKey(const ValueKey('food-search')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Edit 2 containers'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // The pane bulk editor is the Tasks-style editor, with Apply boxes.
      expect(find.byKey(const ValueKey('nameApply')), findsOneWidget);
      // Ctrl-click back to one whole row: that row's own editor.
      await _ctrlTap(tester, find.text('Beans').first);
      expect(find.textContaining('selected'), findsNothing);
      expect(find.byKey(const ValueKey('nameApply')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Food name'))
            .controller!
            .text,
        'Rice',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide Shift+Down keeps extending from the list', (tester) async {
    await _pump(tester, size: const Size(1400, 900));
    _rowFocus(tester, 'Beans').requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Edit 2 containers'), findsOneWidget);
    // The pane opening does not take focus from the list.
    expect(_rowFocus(tester, 'Rice').hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('food-search')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Edit 3 containers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel clears selection and closes the wide bulk pane', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1400, 900));
    await _longPress(tester, 'Beans');
    await _ctrlTap(tester, find.text('Rice'));
    expect(find.text('Edit 2 containers'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit 2 containers'), findsNothing);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets(
    'row editor edits the product, with scope, link and keep-at-least',
    (tester) async {
      final edits = await _pump(tester, size: const Size(1400, 900));
      await tester.tap(find.text('Milk').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('food-product-scope')), findsOneWidget);
      expect(find.text('Also changes 1 other container'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Food name'),
        'Milk 2%',
      );
      await tester.enterText(
        find.byKey(const ValueKey('food-store-link')),
        'https://www.walmart.com/ip/10450114',
      );
      await tester.enterText(
        find.byKey(const ValueKey('food-keep-at-least')),
        '2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('food-save-action')));
      await tester.pumpAndSettle();
      expect(edits, hasLength(1));
      expect(edits.single.fields, isEmpty);
      expect(edits.single.products.roots, [
        implicitFoodProductId(
          const FoodDetails(name: 'Milk', brand: 'Great Value', size: '1 gal'),
        ),
      ]);
      expect(edits.single.products.changes, {
        'name': 'Milk 2%',
        'links': ['https://www.walmart.com/ip/10450114'],
        'minimum': 2,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renaming to another product says it merges', (tester) async {
    await _pump(tester, size: const Size(1400, 900));
    await tester.tap(find.text('Beans'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('food-product-scope')), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Food name'), 'rice');
    await tester.pumpAndSettle();
    expect(find.text('Merges with 1 container of Rice'), findsOneWidget);
  });

  testWidgets('invalid store links and minimums are field errors', (
    tester,
  ) async {
    final edits = await _pump(tester, size: const Size(1400, 900));
    await tester.tap(find.text('Beans'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('food-store-link')),
      'walmart.com/beans',
    );
    await tester.enterText(
      find.byKey(const ValueKey('food-keep-at-least')),
      '1000',
    );
    await tester.tap(find.byKey(const ValueKey('food-save-action')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a web address starting https://'), findsOneWidget);
    expect(find.text('Enter 0 to 999, or leave blank.'), findsOneWidget);
    expect(edits, isEmpty);
  });

  testWidgets('Running low lists products below their minimum', (tester) async {
    final product = implicitFoodProductId(const FoodDetails(name: 'Beans'));
    final adds = <(FoodDetails, int)>[];
    await _pump(
      tester,
      adds: adds,
      events: [
        ..._events,
        FoodOperation(
          id: '$_writer:5',
          order: 5,
          action: FoodAction.product,
          targets: [product],
          product: const {
            'name': 'Beans',
            'brand': '',
            'size': '',
            'minimum': 3,
            'links': ['https://example.com/beans'],
          },
        ),
      ],
    );
    expect(find.text('Running low'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.byTooltip('Open store link for Beans'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    await tester.tap(find.byTooltip('Add another Beans'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Food name'))
          .controller!
          .text,
      'Beans',
    );
    // Searching hides it.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('food-search')), 'rice');
    await tester.pumpAndSettle();
    expect(find.text('Running low'), findsNothing);
  });

  testWidgets('Add suggests products and fills Brand and size', (tester) async {
    final adds = <(FoodDetails, int)>[];
    await _pump(tester, adds: adds, size: const Size(1400, 900));
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Food name'), 'mil');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milk · Great Value · 1 gal'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Brand'))
          .controller!
          .text,
      'Great Value',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Container size'))
          .controller!
          .text,
      '1 gal',
    );
    expect(tester.takeException(), isNull);
  });
}
