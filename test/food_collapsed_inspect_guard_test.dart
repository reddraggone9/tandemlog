import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';

const writer = '00000000-0000-4000-8000-000000000010';
const container = '00000000-0000-4000-8000-000000000001';

List<FoodOperation> fixture() => [
  FoodOperation(
    id: '$writer:1',
    order: 1,
    action: FoodAction.add,
    targets: const [container],
    details: const FoodDetails(
      name: 'Rice',
      brand: 'Sample Foods',
      expiry: '2026-10-15',
      size: '500 g',
      location: 'Freezer',
    ),
    contents: const Contents.fraction(1, 1),
    createdAt: '2026-10-10T00:00:00Z',
  ),
  FoodOperation(
    id: '$writer:2',
    order: 2,
    action: FoodAction.edit,
    targets: const [container],
    contents: const Contents.fraction(1, 2),
  ),
  FoodOperation(
    id: '$writer:3',
    order: 3,
    action: FoodAction.edit,
    targets: const [container],
    contents: const Contents.fraction(1, 1),
  ),
];

Future<void> keyboardActivate(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  final focus = Focus.of(tester.element(control));
  for (var i = 0; i < 20 && !focus.hasPrimaryFocus; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  expect(
    focus.hasPrimaryFocus,
    isTrue,
    reason: 'Real Tab reaches the editable row',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('legacy contents conflict survives flat row editing '
          '${brightness.name} ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final operations = fixture();
        for (final operation in operations) {
          operation.validate();
        }
        final state = projectFood(operations);
        final before = state.containers.map((e) => e.toJson()).toList();
        expect(state.active.single.contents.full, isTrue);
        expect(state.active.single.contentsConflict, isTrue);
        expect(state.groups.single.quickRemoveTarget, isNull);
        final commands = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness, useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: FoodInventoryPage(
              state: state,
              onAdd: (_, _) => commands.add('add'),
              onRemove: (_) => commands.add('remove'),
              onRestore: (_) => commands.add('restore'),
              onDetails: (_, _, _, _) => commands.add('details'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('contents need review'), findsNothing);
        expect(find.byTooltip('Remove one Rice container'), findsOneWidget);
        expect(find.text('Full'), findsNothing);
        expect(find.text('Remaining contents'), findsNothing);
        expect(find.text('Sample Foods · 500 g'), findsOneWidget);
        expect(find.text('Freezer'), findsOneWidget);
        await keyboardActivate(tester, find.text('Rice'));
        expect(find.text('Edit 1 container'), findsOneWidget);
        expect(find.text('Remaining contents'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(state.active.single.contentsConflict, isTrue);
        expect(state.active.single.contentsEdits, hasLength(2));
        expect(commands, isEmpty);
        expect(state.containers.map((e) => e.toJson()).toList(), before);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
