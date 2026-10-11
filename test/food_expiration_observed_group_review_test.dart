import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const _writer = '00000000-0000-4000-8000-000000000010';
String _container(int index) =>
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

FoodOperation _add(int index, bool? estimated) => FoodOperation(
  id: '$_writer:$index',
  order: index,
  action: FoodAction.add,
  targets: [_container(index)],
  details: FoodDetails(
    name: 'Legacy lentils',
    expiry: '2026-10-15',
    estimated: estimated,
  ),
  contents: const Contents.fraction(1, 1),
  createdAt: '2026-10-10T00:00:00Z',
);

Future<void> _mount(
  WidgetTester tester,
  ValueNotifier<List<FoodOperation>> operations, {
  required Future<void> Function(List<String>) remove,
  required Future<void> Function(List<FoodContainer>, FoodDetails, List<String>)
  edit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<FoodOperation>>(
          valueListenable: operations,
          builder: (_, values, _) => FoodInventoryPage(
            state: projectFood(values),
            onAdd: (_, _) {},
            onRemove: remove,
            onRestore: (_) {},
            onContents: (_, _) {},
            onDetails: edit,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mixed legacy group remains inspected after first representative is removed',
    (tester) async {
      final operations = ValueNotifier([
        _add(1, null),
        _add(2, false),
        _add(3, true),
      ]);
      addTearDown(operations.dispose);
      List<String>? removed;
      await _mount(
        tester,
        operations,
        remove: (ids) async {
          removed = ids;
          operations.value = [
            ...operations.value,
            FoodOperation(
              id: '$_writer:4',
              order: 4,
              action: FoodAction.remove,
              targets: ids,
            ),
          ];
        },
        edit: (_, _, _) async {},
      );
      await _tap(tester, find.byTooltip('Inspect Legacy lentils containers'));
      expect(
        find.byTooltip('Collapse Legacy lentils containers'),
        findsOneWidget,
      );
      await _tap(tester, find.byTooltip('Remove one Legacy lentils container'));
      expect(removed, [_container(1)]);
      expect(
        find.byTooltip('Collapse Legacy lentils containers'),
        findsOneWidget,
      );
      expect(find.text('Container 00000002 · Full'), findsOneWidget);
      expect(find.text('Container 00000003 · Full'), findsOneWidget);
      expect(find.text('Container 00000001 · Full'), findsNothing);
      expect(
        projectFood(operations.value).active.map((e) => e.details.estimated),
        [false, true],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date-only mixed group edit targets observed containers and leaves a late arrival alone',
    (tester) async {
      final operations = ValueNotifier([
        _add(1, null),
        _add(2, false),
        _add(3, true),
      ]);
      addTearDown(operations.dispose);
      List<String>? editedIds;
      List<String>? editedFields;
      await _mount(
        tester,
        operations,
        remove: (_) async {},
        edit: (items, details, fields) async {
          editedIds = items.map((e) => e.id).toList();
          editedFields = fields;
          operations.value = [
            ...operations.value,
            FoodOperation(
              id: '$_writer:5',
              order: 5,
              action: FoodAction.edit,
              targets: editedIds!,
              details: details,
              fields: fields,
            ),
          ];
        },
      );
      await _tap(tester, find.byTooltip('Inspect Legacy lentils containers'));
      await _tap(tester, find.byTooltip('Actions for Legacy lentils'));
      await _tap(tester, find.text('Edit group details'));
      operations.value = [...operations.value, _add(4, true)];
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Expiration'),
        '2026-10-20',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(editedIds, [_container(1), _container(2), _container(3)]);
      expect(editedFields, ['expiry']);
      final state = projectFood(operations.value);
      expect(state.containers.map((e) => e.details.estimated), [
        null,
        false,
        true,
        true,
      ]);
      expect(state.containers.map((e) => e.details.expiry), [
        '2026-10-20',
        '2026-10-20',
        '2026-10-20',
        '2026-10-15',
      ]);
      expect(state.view(FoodView.inventory).map((e) => e.containers.length), [
        1,
        3,
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
