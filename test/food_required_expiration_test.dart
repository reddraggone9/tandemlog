import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';

const _writer = '00000000-0000-4000-8000-000000000092';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, Finder field, String value) async {
  // A native Save transfers focus; tap the field again before replacing text.
  await _tap(tester, field);
  await tester.enterText(field, value);
  final controller = tester.widget<TextField>(field).controller!;
  for (var attempt = 0; attempt < 50 && controller.text != value; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  expect(
    controller.text,
    value,
    reason: 'The native field must receive the intended input before Save.',
  );
}

Future<void> openFoodGroupEditor(WidgetTester tester, String name) async {
  if (find.byTooltip('Inspect $name containers').evaluate().isNotEmpty) {
    await _tap(tester, find.byTooltip('Inspect $name containers'));
  }
  await _tap(tester, find.byTooltip('Actions for $name'));
  await _tap(tester, find.text('Edit group details'));
}

Future<void> _mount(
  WidgetTester tester, {
  List<FoodOperation> operations = const [],
  required void Function(FoodDetails) onAdd,
  required void Function(List<FoodContainer>, FoodDetails, List<String>) onEdit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FoodInventoryPage(
        state: projectFood(operations),
        now: () => DateTime(2026, 10, 11),
        onAdd: (details, _) => onAdd(details),
        onDetails: onEdit,
        onRemove: (_) {},
        onRestore: (_) {},
        onContents: (_, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<FoodOperation> _foods(String? expiry, {int count = 1}) => [
  for (var i = 0; i < count; i++)
    FoodOperation(
      id: '$_writer:${i + 1}',
      order: i + 1,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(i + 500).toString().padLeft(12, '0')}',
      ],
      details: FoodDetails(
        name: 'Synthetic beans',
        expiry: expiry,
        estimated: i.isEven ? null : true,
      ),
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-11T00:00:00Z',
    ),
];

void main() {
  registerFoodRequiredExpirationTests();
}

void registerFoodRequiredExpirationTests() {
  testWidgets(
    'manual Food Add requires a valid expiration before any command',
    (tester) async {
      final additions = <FoodDetails>[];
      await _mount(tester, onAdd: additions.add, onEdit: (_, _, _) {});
      await _tap(tester, find.byTooltip('Add food'));
      expect(find.byType(CivilDateInput), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Choose Expiration')).height,
        greaterThanOrEqualTo(48),
      );
      await _enterText(
        tester,
        find.widgetWithText(TextField, 'Food name'),
        'New beans',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(additions, isEmpty);
      expect(find.text('Expiration is required.'), findsOneWidget);
      expect(find.textContaining('(optional)'), findsNothing);
      await _enterText(
        tester,
        find.widgetWithText(TextField, 'Expiration'),
        '2026-02-30',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(additions, isEmpty);
      await _enterText(
        tester,
        find.widgetWithText(TextField, 'Expiration'),
        '2026-10-14',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Add'));
      expect(additions.single.expiry, '2026-10-14');
      expect(additions.single.brand, '');
      expect(additions.single.location, '');
      expect(additions.single.retention, '');
      expect(additions.single.estimated, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('manual edit cannot clear an existing valid Food expiration', (
    tester,
  ) async {
    var writes = 0;
    FoodDetails? edited;
    List<String>? fields;
    final operations = _foods('2026-10-14');
    await _mount(
      tester,
      operations: operations,
      onAdd: (_) {},
      onEdit: (_, details, changed) {
        writes++;
        edited = details;
        fields = changed;
      },
    );
    await openFoodGroupEditor(tester, 'Synthetic beans');
    await _enterText(tester, find.widgetWithText(TextField, 'Expiration'), '');
    await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(writes, 0);
    expect(find.text('Expiration is required.'), findsOneWidget);
    expect(projectFood(operations).active.single.details.expiry, '2026-10-14');
    await _enterText(
      tester,
      find.widgetWithText(TextField, 'Expiration'),
      '2026-10-18',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(writes, 1);
    expect(edited!.expiry, '2026-10-18');
    expect(fields, ['expiry']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'legacy undated Food stays readable and Cancel preserves it; manual Save requires date',
    (tester) async {
      var writes = 0;
      final operations = _foods(null);
      FoodDetails? edited;
      await _mount(
        tester,
        operations: operations,
        onAdd: (_) {},
        onEdit: (_, details, _) {
          writes++;
          edited = details;
        },
      );
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('Needs expiration'), findsOneWidget);
      await openFoodGroupEditor(tester, 'Synthetic beans');
      await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(writes, 0);
      expect(projectFood(operations).active.single.details.expiry, isNull);
      await openFoodGroupEditor(tester, 'Synthetic beans');
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(writes, 0);
      expect(find.text('Expiration is required.'), findsOneWidget);
      await _enterText(
        tester,
        find.widgetWithText(TextField, 'Expiration'),
        '2026-10-20',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(writes, 1);
      expect(edited!.expiry, '2026-10-20');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'observed grouped edit preserves concurrently mixed dates unless expiration explicitly changes',
    (tester) async {
      final births = _foods('2026-10-14', count: 2);
      final original = projectFood(births).active;
      final peerDate = FoodOperation(
        id: '$_writer:3',
        order: 3,
        action: FoodAction.edit,
        targets: [original.last.id],
        details: const FoodDetails(
          name: 'Synthetic beans',
          expiry: '2026-10-18',
        ),
        fields: const ['expiry'],
      );
      List<String>? fields;
      List<FoodOperation>? applied;
      await _mount(
        tester,
        operations: births,
        onAdd: (_) {},
        onEdit: (items, details, changed) {
          fields = changed;
          applied = [
            ...births,
            peerDate,
            FoodOperation(
              id: '$_writer:4',
              order: 4,
              action: FoodAction.edit,
              targets: items.map((e) => e.id).toList(),
              details: details,
              fields: changed,
            ),
          ];
        },
      );
      await openFoodGroupEditor(tester, 'Synthetic beans');
      await _enterText(
        tester,
        find.widgetWithText(TextField, 'Brand'),
        'Brand A',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(fields, ['brand']);
      expect(
        projectFood(applied!).active.map((e) => e.details.expiry).toSet(),
        {'2026-10-14', '2026-10-18'},
      );
      expect(
        projectFood(applied!).active.map((e) => e.id),
        original.map((e) => e.id),
      );
      expect(projectFood(applied!).active.map((e) => e.details.estimated), [
        null,
        true,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
