import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

// design/food-shelf-life.md: a Walmart receipt from 2026-11-07 seen on
// 2026-11-09, after an earlier receipt from 2026-10-24.
const _writer = '00000000-0000-4000-8000-000000000096';
String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

final _yogurt = _id(101),
    _mango = _id(102),
    _strawberries = _id(103),
    _cutCarrots = _id(104);
final _october = _id(201), _yogurtBuy = _id(202), _mangoBuy = _id(203);
final _strawberryBuy = _id(204);

List<FoodOperation> _events() {
  var order = 0;
  FoodOperation product(String id, String name, [Object? keepsFor]) =>
      FoodOperation(
        id: '$_writer:${++order}',
        order: order,
        action: FoodAction.product,
        targets: [id],
        product: {
          'name': name,
          'brand': '',
          'size': '',
          if (keepsFor != null) 'keepsFor': keepsFor,
        },
      );
  FoodOperation purchase(String id, String product, String date) =>
      FoodOperation(
        id: '$_writer:${++order}',
        order: order,
        action: FoodAction.purchase,
        targets: [id],
        purchase: {
          'product': product,
          'date': date,
          'store': 'Walmart',
          'amount': 298,
          'currency': 'USD',
          'quantity': 1,
        },
      );
  FoodOperation add(
    int container,
    String product,
    String name, {
    String? purchase,
    String? expiry,
    String location = '',
    bool estimated = false,
  }) => FoodOperation(
    id: '$_writer:${++order}',
    order: order,
    action: FoodAction.add,
    targets: [_id(container)],
    details: FoodDetails(
      name: name,
      expiry: expiry,
      estimated: estimated,
      location: location,
    ),
    contents: const Contents.fraction(1, 1),
    createdAt: '2026-11-07T18:00:00Z',
    link: {
      'product': product,
      if (purchase != null) 'purchase': purchase,
      if (purchase != null && (expiry != null || location.isNotEmpty))
        'prefill': true,
    },
  );
  return [
    product(_yogurt, 'Greek yogurt'),
    product(_mango, 'Mango'),
    product(_strawberries, 'Strawberries', {'count': 1, 'unit': 'week'}),
    product(_cutCarrots, 'Carrots, cut', {'count': 2, 'unit': 'week'}),
    purchase(_october, _yogurt, '2026-10-24'),
    add(1, _yogurt, 'Greek yogurt', purchase: _october),
    // Dated by hand from its label: 27 days after it was bought.
    FoodOperation(
      id: '$_writer:${++order}',
      order: order,
      action: FoodAction.edit,
      targets: [_id(1)],
      details: const FoodDetails(
        name: 'Greek yogurt',
        expiry: '2026-11-20',
        location: 'Fridge',
      ),
      fields: const ['expiry', 'location'],
    ),
    purchase(_yogurtBuy, _yogurt, '2026-11-07'),
    purchase(_mangoBuy, _mango, '2026-11-07'),
    purchase(_strawberryBuy, _strawberries, '2026-11-07'),
    add(2, _yogurt, 'Greek yogurt', purchase: _yogurtBuy, location: 'Fridge'),
    add(3, _mango, 'Mango', purchase: _mangoBuy),
    add(
      4,
      _strawberries,
      'Strawberries',
      purchase: _strawberryBuy,
      expiry: '2026-11-14',
      estimated: true,
      location: 'Fridge',
    ),
    add(
      5,
      _cutCarrots,
      'Carrots, cut',
      expiry: '2026-11-01',
      location: 'Fridge',
    ),
    // A hand entry of fresh food: no purchase day, so no offers.
    add(6, _mango, 'Mango', expiry: '2026-11-15'),
  ];
}

typedef _Edit = ({
  List<String> ids,
  FoodDetails details,
  List<String> fields,
  FoodProductChange products,
});

Future<List<_Edit>> _pump(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  double textScale = 1,
  List<(FoodDetails, int)>? adds,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final edits = <_Edit>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: tandemlogTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: projectFood(_events()),
        now: () => DateTime(2026, 11, 9, 9),
        onAdd: (details, count) => adds?.add((details, count)),
        onRemove: (_) {},
        onRestore: (_) {},
        onDetails: (items, details, fields, products) => edits.add((
          ids: items.map((e) => e.id).toList(),
          details: details,
          fields: fields,
          products: products,
        )),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return edits;
}

final _offer = find.byKey(const ValueKey('food-expiry-offer'));
final _note = find.byKey(const ValueKey('food-expiry-note'));
final _expiration = find.byKey(const ValueKey('food-expiration'));
final _keepsFor = find.byKey(const ValueKey('food-keeps-for'));
final _save = find.byKey(const ValueKey('food-save-action'));

String _text(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

Future<void> _open(WidgetTester tester, String name, {int row = 0}) async {
  await tester.tap(find.text(name).at(row));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only dates estimated from Keeps for read est.', (tester) async {
    await _pump(tester);
    expect(
      find.textContaining('2026-11-14 est.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('est.', findRichText: true), findsOneWidget);
  });

  testWidgets('row editor order: Location under Expiration, Store link last', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Strawberries');
    final tops = [
      for (final label in [
        'Food name',
        'Brand',
        'Expiration',
        'Location',
        'Keeps for',
        'Container size',
        'Keep at least',
        'Store link',
        'Retention reason',
      ])
        tester.getTopLeft(find.text(label).last).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(tops.length));
    expect(_text(tester, _keepsFor), '1 week');
    expect(find.text('Estimated: bought 2026-11-07 + 1 week'), findsOneWidget);
    expect(_offer, findsNothing);
  });

  testWidgets('a corrected estimate offers to update Keeps for; Save makes '
      'the date the user\'s own', (tester) async {
    final edits = await _pump(tester);
    await _open(tester, 'Strawberries');
    await tester.enterText(_expiration, '2026-11-12');
    await tester.pumpAndSettle();
    expect(_note, findsNothing);
    expect(find.text('Remember: keeps 5 days'), findsOneWidget);
    await tester.tap(_offer);
    await tester.pumpAndSettle();
    expect(_text(tester, _keepsFor), '5 days');
    expect(_offer, findsNothing);
    expect(edits, isEmpty);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.fields, unorderedEquals(['expiry', 'estimated']));
    expect(edits.single.details.expiry, '2026-11-12');
    expect(edits.single.details.estimated, false);
    expect(edits.single.products.changes, {
      'keepsFor': {'count': 5, 'unit': 'day'},
    });
  });

  testWidgets('an estimate changed without pressing the offer leaves Keeps '
      'for alone', (tester) async {
    final edits = await _pump(tester);
    await _open(tester, 'Strawberries');
    await tester.enterText(_expiration, '2026-11-21');
    await tester.pumpAndSettle();
    expect(find.text('Remember: keeps 2 weeks'), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.fields, unorderedEquals(['expiry', 'estimated']));
    expect(edits.single.products.changes, isEmpty);
  });

  testWidgets('dating an Inbox item offers Remember once and never sets '
      'Keeps for by itself', (tester) async {
    final edits = await _pump(tester);
    await _open(tester, 'Mango');
    expect(_offer, findsNothing);
    expect(_text(tester, _keepsFor), '');
    await tester.enterText(_expiration, '2026-11-19');
    await tester.pumpAndSettle();
    expect(find.text('Remember: keeps 12 days'), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.fields, ['expiry']);
    expect(edits.single.products.changes, isEmpty);
  });

  testWidgets('Remember fills Keeps for; clearing it before Save saves none', (
    tester,
  ) async {
    final edits = await _pump(tester);
    await _open(tester, 'Mango');
    await tester.enterText(_expiration, '2026-11-19');
    await tester.pumpAndSettle();
    await tester.tap(_offer);
    await tester.pumpAndSettle();
    expect(_text(tester, _keepsFor), '12 days');
    expect(_offer, findsNothing);
    // A different date offers the new duration again.
    await tester.enterText(_expiration, '2026-11-21');
    await tester.pumpAndSettle();
    expect(find.text('Remember: keeps 2 weeks'), findsOneWidget);
    await tester.enterText(_keepsFor, '');
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.products.changes, isEmpty);
  });

  testWidgets('Remember then Save sets the date and Keeps for in one Save', (
    tester,
  ) async {
    final edits = await _pump(tester);
    await _open(tester, 'Mango');
    await tester.enterText(_expiration, '2026-11-21');
    await tester.pumpAndSettle();
    await tester.tap(_offer);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits, hasLength(1));
    expect(edits.single.fields, ['expiry']);
    expect(edits.single.products.changes, {
      'keepsFor': {'count': 2, 'unit': 'week'},
    });
  });

  testWidgets('labeled food offers the date from last time and no Remember', (
    tester,
  ) async {
    final edits = await _pump(tester);
    await _open(tester, 'Greek yogurt');
    expect(_text(tester, _expiration), '');
    expect(find.text('Like last time: 2026-12-04'), findsOneWidget);
    await tester.tap(_offer);
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '2026-12-04');
    expect(_offer, findsNothing);
    expect(edits, isEmpty);
    // Any other date: still no Remember for a product dated before.
    await tester.enterText(_expiration, '2026-11-30');
    await tester.pumpAndSettle();
    expect(_offer, findsNothing);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.fields, ['expiry']);
    expect(edits.single.products.changes, isEmpty);
  });

  testWidgets('the calendar opens on the suggested date while Expiration is '
      'empty', (tester) async {
    await _pump(tester);
    await _open(tester, 'Greek yogurt');
    await tester.tap(
      find.descendant(of: _expiration, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    // Nothing is filled in until a day is picked: Cancel leaves it empty.
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '');
    await tester.tap(
      find.descendant(of: _expiration, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '2026-12-04');
  });

  testWidgets('hand entries have no purchase day and get no offers', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mango', row: 1);
    expect(_text(tester, _expiration), '2026-11-15');
    await tester.enterText(_expiration, '2026-11-25');
    await tester.pumpAndSettle();
    expect(_offer, findsNothing);
    expect(_note, findsNothing);
  });

  testWidgets('Keeps for refuses text that is not a duration', (tester) async {
    final edits = await _pump(tester);
    await _open(tester, 'Strawberries');
    await tester.enterText(_keepsFor, 'a while');
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.text(FoodKeepsFor.hint), findsOneWidget);
    expect(edits, isEmpty);
    await tester.enterText(_keepsFor, '10 days');
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(edits.single.fields, isEmpty);
    expect(edits.single.products.changes, {
      'keepsFor': {'count': 10, 'unit': 'day'},
    });
  });

  testWidgets('Add fills the date and location of a product with Keeps for, '
      'never over typed text', (tester) async {
    final adds = <(FoodDetails, int)>[];
    await _pump(tester, adds: adds);
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Food name');
    final location = find.widgetWithText(TextField, 'Location');
    await tester.enterText(name, 'Carrots, cut');
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '2026-11-23');
    expect(_text(tester, location), 'Fridge');
    expect(find.text('Keeps 2 weeks from today'), findsOneWidget);
    expect(_offer, findsNothing);
    expect(_keepsFor, findsNothing);
    // Another product replaces an untouched autofill.
    await tester.enterText(name, 'Strawberries');
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '2026-11-16');
    expect(find.text('Keeps 1 week from today'), findsOneWidget);
    // A product without Keeps for clears it again.
    await tester.enterText(name, 'Mango');
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '');
    expect(_text(tester, location), '');
    expect(_note, findsNothing);
    // Typed text stays.
    await tester.enterText(_expiration, '2026-12-01');
    await tester.enterText(location, 'Counter');
    await tester.enterText(name, 'Carrots, cut');
    await tester.pumpAndSettle();
    expect(_text(tester, _expiration), '2026-12-01');
    expect(_text(tester, location), 'Counter');
    expect(_note, findsNothing);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(adds.single.$1.expiry, '2026-12-01');
    expect(adds.single.$1.location, 'Counter');
    expect(adds.single.$1.estimated, isNot(true));
  });

  testWidgets('a changed autofilled date hides its helper and offers nothing', (
    tester,
  ) async {
    final adds = <(FoodDetails, int)>[];
    await _pump(tester, adds: adds);
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Carrots, cut',
    );
    await tester.pumpAndSettle();
    await tester.enterText(_expiration, '2026-11-20');
    await tester.pumpAndSettle();
    expect(_note, findsNothing);
    expect(_offer, findsNothing);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(adds.single.$1.expiry, '2026-11-20');
    expect(adds.single.$1.location, 'Fridge');
  });

  testWidgets('Add field order: Location under Expiration', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    final tops = [
      for (final label in [
        'Food name',
        'Brand',
        'Expiration',
        'Location',
        'Container size',
        'Containers to add',
      ])
        tester.getTopLeft(find.text(label).last).dy,
    ];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(tops.length));
  });

  for (final (width, scale) in [(412.0, 1.0), (412.0, 2.0), (360.0, 2.0)]) {
    testWidgets('offers fit a ${width.toInt()} dp phone at ${scale}x text', (
      tester,
    ) async {
      await _pump(tester, size: Size(width, 915), textScale: scale);
      await _open(tester, 'Mango');
      await tester.enterText(_expiration, '2027-01-16');
      await tester.pumpAndSettle();
      expect(find.text('Remember: keeps 10 weeks'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(_offer);
      await tester.pumpAndSettle();
      expect(_offer, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
