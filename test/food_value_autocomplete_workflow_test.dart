import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const _writer = '00000000-0000-4000-8000-000000000050';
Future<void> verifyFoodValueAutocomplete(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  FoodDetails? saved;
  final events = <FoodOperation>[
    for (var i = 0; i < 3; i++)
      FoodOperation(
        id: '$_writer:${i + 1}',
        order: i + 1,
        action: FoodAction.add,
        targets: [
          '00000000-0000-4000-8000-${(800 + i).toString().padLeft(12, '0')}',
        ],
        details: FoodDetails(
          name: 'Synthetic food $i',
          expiry: '2026-10-15',
          brand: i == 2 ? 'Historical brand' : 'Acme',
          location: i == 2 ? 'Old freezer' : 'Pantry',
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
    FoodOperation(
      id: '$_writer:4',
      order: 4,
      action: FoodAction.remove,
      targets: ['00000000-0000-4000-8000-000000000802'],
    ),
  ];
  Future<void> tap(Finder target) async {
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  Future<void> enter(String label, String value) async {
    await tester.ensureVisible(field(label));
    await tap(field(label));
    await tester.enterText(field(label), value);
    await tester.pumpAndSettle();
  }

  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('values-${brightness.name}-$textScale'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FoodInventoryPage(
        state: projectFood(events),
        onAdd: (details, _) => saved = details,
        onRemove: (_) {},
        onRestore: (_) {},
        onDetails: (_, _, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(find.byTooltip('Add food'));
  Finder option(String value) => find.descendant(
    of: find.byType(ListView),
    matching: find.widgetWithText(InkWell, value),
  );
  await enter('Brand', 'cM');
  expect(
    option('Acme'),
    findsOneWidget,
    reason: 'case-insensitive substring match, duplicates removed',
  );
  await capture?.call('brand-options');
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(field('Brand')).controller!.text, 'Acme');
  await enter('Location', 'pan');
  expect(option('Pantry'), findsOneWidget);
  await capture?.call('location-options');
  await tap(option('Pantry'));
  expect(
    tester.widget<TextField>(field('Location')).controller!.text,
    'Pantry',
  );
  await enter('Brand', 'historic');
  expect(
    option('Historical brand'),
    findsOneWidget,
    reason: 'existing deleted entries remain suggestion sources',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(option('Historical brand'), findsNothing);
  expect(
    find.byType(AlertDialog),
    findsOneWidget,
    reason: 'Escape only closes the suggestion popup',
  );
  await enter('Brand', 'A new custom brand');
  await enter('Location', 'A new custom shelf');
  await enter('Food name', 'Synthetic new food');
  await enter('Expiration', '2026-10-15');
  await capture?.call('free-text');
  await tap(find.widgetWithText(FilledButton, 'Add'));
  expect(saved?.brand, 'A new custom brand');
  expect(saved?.location, 'A new custom shelf');
  expect(tester.takeException(), isNull);
}

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Food value autocomplete ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(sample.$1, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFoodValueAutocomplete(
            tester,
            brightness: brightness,
            textScale: sample.$2,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
