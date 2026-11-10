// THROWAWAY: renders mock-ups for design/food-shelf-life.md with the real
// Food page and editor plus the prototype changes on this branch.
// TANDEMLOG_UX_CAPTURES=<dir> flutter test test/shelf_life_mockup_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/food/shelf_life_prototype.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

import 'support/ux_capture.dart';

const _writer = '00000000-0000-4000-8000-000000000095';
var _n = 0;

List<FoodOperation> _add(
  String name, {
  String brand = '',
  String size = '',
  String? expiry,
  bool estimated = false,
  String location = '',
  int count = 1,
}) => [
  for (var i = 0; i < count; i++)
    () {
      _n++;
      return FoodOperation(
        id: '$_writer:$_n',
        order: _n,
        action: FoodAction.add,
        targets: ['00000000-0000-4000-8000-${_n.toString().padLeft(12, '0')}'],
        details: FoodDetails(
          name: name,
          brand: brand,
          size: size,
          expiry: expiry,
          estimated: estimated,
          location: location,
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-11-07T18:00:00Z',
      );
    }(),
];

List<FoodOperation> _events() {
  _n = 0;
  return [
    // Hand entries already in Stock.
    ..._add('Milk', brand: 'Great Value', size: '1 gal', expiry: '2026-11-15', location: 'Fridge'),
    ..._add('Greek yogurt', brand: 'Oikos', size: '32 oz', expiry: '2026-11-20', location: 'Fridge'),
    ..._add('Carrots, cut', expiry: '2026-11-17', location: 'Fridge'),
    // Walmart receipt of 2026-11-07: products with Keeps for arrive dated.
    ..._add('Broccoli', expiry: '2026-11-12', estimated: true, location: 'Fridge'),
    ..._add('Strawberries', size: '1 lb', expiry: '2026-11-14', estimated: true, location: 'Fridge', count: 2),
    ..._add('Romaine lettuce', expiry: '2026-11-21', estimated: true, location: 'Fridge'),
    ..._add('Oranges', expiry: '2026-11-28', estimated: true, location: 'Fridge', count: 6),
    ..._add('Onions', brand: 'Great Value', size: '3 lb', expiry: '2027-02-07', estimated: true, location: 'Pantry'),
    // Products without Keeps for stay undated in the Inbox.
    ..._add('Mango'),
    ..._add('Baby spinach', brand: 'Marketside', size: '10 oz'),
  ];
}

void _seed() {
  prototypeKeepsFor
    ..clear()
    ..addAll({
      'Broccoli': (count: 5, unit: 'day'),
      'Strawberries': (count: 1, unit: 'week'),
      'Romaine lettuce': (count: 2, unit: 'week'),
      'Oranges': (count: 3, unit: 'week'),
      'Onions': (count: 3, unit: 'month'),
      'Carrots, cut': (count: 2, unit: 'week'),
    });
  prototypePurchaseDay
    ..clear()
    ..addAll({
      for (final name in [
        'Broccoli',
        'Strawberries',
        'Romaine lettuce',
        'Oranges',
        'Onions',
        'Mango',
        'Baby spinach',
      ])
        name: '2026-11-07',
    });
  prototypeUsualLocation
    ..clear()
    ..addAll({'Carrots, cut': 'Fridge', 'Milk': 'Fridge'});
}

Future<void> _fonts() async {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final font = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    if (await font.exists()) {
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        final f = File(
          '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
        );
        if (await f.exists()) {
          loader.addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        }
      }
      await loader.load();
      return;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('Roboto not found');
    directory = parent;
  }
}

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  _seed();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 892);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('ux-root'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tandemlogTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FoodInventoryPage(
          state: projectFood(_events()),
          now: () => DateTime(2026, 11, 9, 12),
          onAdd: (_, _) {},
          onRemove: (_) {},
          onRestore: (_) {},
          onDetails: (_, _, _, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.theme, tandemlogTheme(Brightness.dark));
  final directory = Platform.environment['TANDEMLOG_UX_CAPTURES'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ux-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.625);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _openRow(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    find.text(name),
    120,
    scrollable: find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    ).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

Future<void> _setExpiry(WidgetTester tester, String value) async {
  final field = find.descendant(
    of: find.byKey(const ValueKey('food-expiration')),
    matching: find.byType(EditableText),
  );
  await tester.enterText(field.evaluate().isEmpty
      ? find.byKey(const ValueKey('food-expiration'))
      : field, value);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _fonts();
    await loadUxIcons();
  });

  testWidgets('01 food list after import', (tester) async {
    await _pump(tester);
    expect(find.textContaining('est.'), findsWidgets);
    await _capture(tester, '01-food-list-after-import');
  });

  for (final scale in [1.0, 2.0]) {
    final suffix = scale == 1 ? '' : '-2x-text';
    testWidgets('02 row editor estimated$suffix', (tester) async {
      await _pump(tester, textScale: scale);
      await _openRow(tester, 'Oranges');
      expect(find.text('3 weeks'), findsOneWidget);
      await _capture(tester, '02-product-editor-keeps-for$suffix');
      if (scale != 1) {
        await _show(tester, 'food-keeps-for');
        await tester.ensureVisible(find.text('Save'));
        await tester.pumpAndSettle();
        await _capture(tester, '02-product-editor-keeps-for$suffix-scrolled');
      }
    });

    testWidgets('03 dating an Inbox item learns$suffix', (tester) async {
      await _pump(tester, textScale: scale);
      await _openRow(tester, 'Mango');
      await _setExpiry(tester, '2026-11-19');
      expect(find.text('12 days'), findsOneWidget);
      await _show(tester, 'food-keeps-for');
      await _capture(tester, '03-inbox-dating-learns-keeps-for$suffix');
    });

    testWidgets('04 changed estimate offers update$suffix', (tester) async {
      await _pump(tester, textScale: scale);
      await _openRow(tester, 'Strawberries');
      await _setExpiry(tester, '2026-11-12');
      expect(find.text('Use 5 days instead'), findsOneWidget);
      await _show(tester, 'food-keeps-for-offer');
      await _capture(tester, '04-changed-estimate-offers-update$suffix');
    });

    testWidgets('05 Add autofills date and location$suffix', (tester) async {
      await _pump(tester, textScale: scale);
      await tester.tap(find.byTooltip('Add food'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Food name'),
        'carr',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carrots, cut').last);
      await tester.pumpAndSettle();
      expect(find.text('Keeps 2 weeks from today'), findsOneWidget);
      await _capture(tester, '05-add-autofills-date-and-location$suffix');
    });
  }
}
