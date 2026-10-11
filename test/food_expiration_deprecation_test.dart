import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'food_expiry_guidance_test.dart' show foodFixtureIdentityMenu;

const writer = '00000000-0000-4000-8000-000000000010';
List<FoodOperation> legacyFoods() => [
  for (final entry in [null, false, true].indexed)
    FoodOperation(
      id: '$writer:${entry.$1 + 1}',
      order: entry.$1 + 1,
      action: FoodAction.add,
      targets: [
        '00000000-0000-4000-8000-${(entry.$1 + 1).toString().padLeft(12, '0')}',
      ],
      details: FoodDetails(
        name: 'Legacy beans',
        expiry: '2026-10-15',
        estimated: entry.$2,
      ),
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-10T00:00:00Z',
    ),
];

void main() {
  test(
    'hidden certainty cannot alter grouping, ordering or creation identity',
    () {
      final additions = legacyFoods();
      final expected = projectFood(additions).view(FoodView.inventory).single;
      final duplicated = projectFood([...additions.reversed, ...additions]);
      expect(
        duplicated.view(FoodView.inventory).single.containers.map((e) => e.id),
        expected.containers.map((e) => e.id),
      );
      final cleared = projectFood([
        ...additions,
        FoodOperation(
          id: '$writer:4',
          order: 4,
          action: FoodAction.edit,
          targets: expected.containers.map((e) => e.id).toList(),
          details: const FoodDetails(name: 'Legacy beans', estimated: null),
          fields: const ['expiry'],
        ),
      ]);
      expect(cleared.view(FoodView.inventory), isEmpty);
      expect(cleared.view(FoodView.inbox).single.containers.length, 3);
      expect(cleared.containers.map((e) => e.details.estimated), [
        null,
        false,
        true,
      ]);
      final conflict = FoodOperation(
        id: '$writer:5',
        order: 5,
        action: FoodAction.add,
        targets: additions.first.targets,
        details: const FoodDetails(
          name: 'Legacy beans',
          expiry: '2026-10-15',
          estimated: true,
        ),
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-10T00:00:00Z',
      );
      expect(
        () => projectFood([...additions, conflict]),
        throwsFormatException,
      );
      List<String> order(bool firstEstimated) {
        final groups = projectFood([
          for (final entry in ['a', 'z'].indexed)
            FoodOperation(
              id: '$writer:${entry.$1 + 1}',
              order: entry.$1 + 1,
              action: FoodAction.add,
              targets: additions[entry.$1].targets,
              details: FoodDetails(
                name: 'Beans',
                expiry: '2026-10-15',
                size: entry.$2,
                estimated: entry.$1 == 0 ? firstEstimated : !firstEstimated,
              ),
              contents: const Contents.fraction(1, 1),
              createdAt: '2026-10-10T00:00:00Z',
            ),
        ]).view(FoodView.inventory);
        return groups.map((e) => e.details.size).toList();
      }

      expect(order(true), ['a', 'z']);
      expect(order(false), ['a', 'z']);
    },
  );
  test(
    'legacy unknown/known/estimated records group by visible facts while retaining history',
    () {
      final original = legacyFoods();
      final bytes = jsonEncode(original.map((e) => e.toJson()).toList());
      final decoded = (jsonDecode(bytes) as List)
          .map((e) => FoodOperation.fromJson(e))
          .toList();
      final state = projectFood(decoded.reversed);
      expect(state.view(FoodView.inventory).single.containers.length, 3);
      expect(state.containers.map((e) => e.details.estimated), [
        null,
        false,
        true,
      ]);
      expect(jsonEncode(decoded.map((e) => e.toJson()).toList()), bytes);
      final changed = projectFood([
        ...decoded,
        FoodOperation(
          id: '$writer:4',
          order: 4,
          action: FoodAction.edit,
          targets: state.containers.map((e) => e.id).toList(),
          details: const FoodDetails(
            name: 'Legacy beans',
            expiry: '2026-10-20',
            estimated: null,
          ),
          fields: const ['expiry'],
        ),
      ]);
      expect(changed.view(FoodView.inventory).single.containers.length, 3);
      expect(changed.containers.map((e) => e.details.expiry).toSet(), {
        '2026-10-20',
      });
      expect(changed.containers.map((e) => e.details.estimated), [
        null,
        false,
        true,
      ]);
      expect(
        projectFood(decoded).containers.map((e) => e.details.expiry).toSet(),
        {'2026-10-15'},
      );
    },
  );

  testWidgets(
    'date-only grouped edit preserves hidden legacy values; new food asserts no certainty',
    (tester) async {
      await verifyExpirationDeprecationWorkflow(tester);
    },
  );
}

Future<void> verifyExpirationDeprecationWorkflow(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
    await tester.pumpAndSettle();
  }

  var operations = legacyFoods();
  FoodDetails? added;
  List<String>? changedFields;
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('date-only-${brightness.name}-$textScale'),
      theme: ThemeData(
        useMaterial3: true,
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
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => FoodInventoryPage(
            state: projectFood(operations),
            sectionMenu: (compact) =>
                SectionMenu(food: true, compact: compact, onSelected: (_) {}),
            userName: 'Synthetic household',
            identityMenu: foodFixtureIdentityMenu,
            onAdd: (details, count) => added = details,
            onRemove: (_) {},
            onRestore: (_) {},
            onContents: (_, _) {},
            onDetails: (items, details, fields) {
              changedFields = fields;
              setState(
                () => operations = [
                  ...operations,
                  FoodOperation(
                    id: '$writer:4',
                    order: 4,
                    action: FoodAction.edit,
                    targets: items.map((e) => e.id).toList(),
                    details: details,
                    fields: fields,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Legacy beans'), findsOneWidget);
  expect(find.textContaining('Certainty'), findsNothing);
  expect(find.textContaining('Estimated'), findsNothing);
  await capture?.call('collapsed');
  await tap(find.byTooltip('Inspect Legacy beans containers'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Certainty'), findsNothing);
  await capture?.call('inspect');
  await tap(find.byTooltip('Actions for Legacy beans'));
  await tester.pumpAndSettle();
  await tap(find.text('Edit group details'));
  await tester.pumpAndSettle();
  expect(
    find.widgetWithText(
      DropdownButtonFormField<String>,
      'Expiration certainty',
    ),
    findsNothing,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Expiration'),
    '2026-10-20',
  );
  await capture?.call('date-editor');
  await tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  expect(changedFields, ['expiry']);
  expect(projectFood(operations).containers.map((e) => e.details.estimated), [
    null,
    false,
    true,
  ]);
  expect(find.text('2026-10-20'), findsOneWidget);
  await tap(find.byTooltip('Add food'));
  await tester.pumpAndSettle();
  expect(
    find.widgetWithText(
      DropdownButtonFormField<String>,
      'Expiration certainty',
    ),
    findsNothing,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Food name'),
    'Fresh beans',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Expiration'),
    '2026-10-21',
  );
  await tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
  expect(added!.estimated, isNull);
  expect(added!.expiry, '2026-10-21');
  await capture?.call('new-food');
  expect(tester.takeException(), isNull);
}
