import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'food_stock_toolbar_workflow_test.dart'
    show stockToolbarFoods, chooseFoodView;

const _writer = '00000000-0000-4000-8000-000000000090';
const _sharedActive = '00000000-0000-4000-8000-000000000201';
const _sharedDeleted = '00000000-0000-4000-8000-000000000202';

Finder _scrollable() => find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  ),
);
Future<void> _top(WidgetTester tester) async {
  tester.state<ScrollableState>(_scrollable()).position.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _reach(WidgetTester tester, Finder target) async {
  await _top(tester);
  await tester.scrollUntilVisible(target, 180, scrollable: _scrollable());
  await tester.pumpAndSettle();
}

Future<void> _query(
  WidgetTester tester,
  String text, {
  Future<void> Function(Finder)? input,
}) async {
  await _top(tester);
  if (input == null) {
    await tester.tap(find.byKey(const ValueKey('food-search')));
  } else {
    await input(find.byKey(const ValueKey('food-search')));
  }
  await tester.enterText(find.byKey(const ValueKey('food-search')), text);
  await tester.pumpAndSettle();
}

/// Synthetic commands exercise the actual page's observed targets and reproject
/// after remove/restore/Undo. Store persistence is covered by production tests.
Future<void> verifyFoodAllStatusSearch(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  Future<void> Function(String)? capture,
  Future<void> Function(Finder)? input,
}) async {
  Future<void> tap(Finder target) async {
    if (input == null) {
      await tester.tap(target);
    } else {
      await input(target);
    }
  }

  final events = stockToolbarFoods();
  var sequence = 7;
  FoodOperation operation(
    FoodAction action,
    List<String> targets, {
    FoodDetails? details,
    List<String> observed = const [],
    String? retracts,
  }) {
    sequence++;
    return FoodOperation(
      id: '$_writer:$sequence',
      order: sequence,
      action: action,
      targets: targets,
      details: details,
      contents: action == FoodAction.add ? const Contents.fraction(1, 1) : null,
      createdAt: action == FoodAction.add ? '2026-10-11T00:00:00Z' : null,
      observedDeletes: observed,
      retracts: retracts,
    );
  }

  events.add(
    operation(FoodAction.add, [
      _sharedActive,
      _sharedDeleted,
    ], details: const FoodDetails(name: 'Food shared', expiry: '2026-10-15')),
  );
  events.add(operation(FoodAction.remove, [_sharedDeleted]));
  for (var i = 0; i < 18; i++) {
    final id =
        '00000000-0000-4000-8000-${(300 + i).toString().padLeft(12, '0')}';
    events.add(
      operation(FoodAction.add, [
        id,
      ], details: FoodDetails(name: 'Food deleted $i', expiry: '2026-10-15')),
    );
    events.add(operation(FoodAction.remove, [id]));
  }
  final history = <FoodOperation>[];
  late StateSetter update;
  void command(FoodOperation op) => update(() {
    events.add(op);
    history.add(op);
  });
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('all-food-${brightness.name}-$textScale'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff267461),
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return FoodInventoryPage(
            state: projectFood(events),
            userName: 'Synthetic household',
            now: () => DateTime(2026, 10, 11),
            onAdd: (_, _) {},
            onContents: (_, _) {},
            onDetails: (_, _, _) {},
            onRemove: (ids) => command(operation(FoodAction.remove, ids)),
            onRestore: (container) => command(
              operation(FoodAction.restore, [
                container.id,
              ], observed: container.deletions.toList()),
            ),
            onUndo: history.isEmpty
                ? null
                : () {
                    final source = history.removeLast();
                    update(
                      () => events.add(
                        operation(
                          FoodAction.undo,
                          source.targets,
                          retracts: source.id,
                        ),
                      ),
                    );
                  },
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Search food'), findsOneWidget);
  await chooseFoodView(tester, 'Retained', input: input);
  await _query(tester, 'Food', input: input);
  expect(
    find.byTooltip('Filter food: all food; saved Retained filters paused'),
    findsOneWidget,
  );
  expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  await _reach(tester, find.byTooltip('Remove one Food shared container'));
  final activeCard = find.ancestor(
    of: find.byTooltip('Remove one Food shared container'),
    matching: find.byType(Card),
  );
  expect(
    find.descendant(of: activeCard, matching: find.byIcon(Icons.restore)),
    findsNothing,
  );
  await capture?.call('mixed-active');
  // An incoming projection can remove a preceding row while a group's actions
  // menu is open. Its pending callback must not inherit a different row's data.
  await tap(find.byTooltip('Inspect Food shared containers'));
  await tester.pumpAndSettle();
  await tap(find.byTooltip('Actions for Food shared'));
  await tester.pumpAndSettle();
  final preceding = projectFood(
    events,
  ).active.singleWhere((c) => c.details.name == 'Food early');
  final incoming = operation(FoodAction.remove, [preceding.id]);
  update(() => events.add(incoming));
  await tester.pumpAndSettle();
  final staleRemove = find.widgetWithText(
    PopupMenuItem<String>,
    'Remove 1 container',
  );
  if (staleRemove.evaluate().isNotEmpty) {
    await tap(staleRemove);
    await tester.pumpAndSettle();
  }
  expect(
    find.byType(AlertDialog),
    findsNothing,
    reason: 'disposed row popup cannot act on its replacement',
  );
  expect(
    projectFood(events).active.any((c) => c.details.name == 'Food late'),
    isTrue,
  );
  update(
    () => events.add(
      operation(FoodAction.undo, incoming.targets, retracts: incoming.id),
    ),
  );
  await tester.pumpAndSettle();
  await _reach(tester, find.byTooltip('Actions for Food shared'));
  await tap(find.byTooltip('Actions for Food shared'));
  await tester.pumpAndSettle();
  final newMember = operation(FoodAction.add, [
    '00000000-0000-4000-8000-000000000900',
  ], details: const FoodDetails(name: 'Food shared', expiry: '2026-10-15'));
  update(() => events.add(newMember));
  await tester.pumpAndSettle();
  if (staleRemove.evaluate().isNotEmpty) {
    await tap(staleRemove);
    await tester.pumpAndSettle();
  }
  expect(
    find.byType(AlertDialog),
    findsNothing,
    reason: 'old Remove1 menu cannot inherit an unseen new container',
  );
  update(
    () => events.add(
      operation(FoodAction.undo, newMember.targets, retracts: newMember.id),
    ),
  );
  await tester.pumpAndSettle();
  await _reach(tester, find.byTooltip('Collapse Food shared containers'));
  await tap(find.byTooltip('Collapse Food shared containers'));
  await tester.pumpAndSettle();
  await _reach(tester, find.byKey(const ValueKey('food-deleted-heading')));
  final heading = find.byKey(const ValueKey('food-deleted-heading'));
  final position = tester.state<ScrollableState>(_scrollable()).position;
  // Scroll beyond the heading's original position. It pins at the real viewport
  // top while the long deleted section remains onscreen, without an overlay.
  final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
  position.jumpTo(
    position.pixels + tester.getTopLeft(heading).dy - viewportTop + 50,
  );
  await tester.pumpAndSettle();
  expect(tester.getTopLeft(heading).dy, closeTo(viewportTop, .01));
  expect(find.byKey(const ValueKey('food-deleted-heading')), findsOneWidget);
  final semantics = tester.ensureSemantics();
  expect(
    tester
        .getSemantics(find.text('Deleted').last)
        .getSemanticsData()
        .flagsCollection
        .isHeader,
    isTrue,
  );
  semantics.dispose();
  await capture?.call('deleted-pinned');
  await _reach(tester, find.byTooltip('Restore Food shared containers'));
  final deletedCard = find.ancestor(
    of: find.byTooltip('Restore Food shared containers'),
    matching: find.byType(Card),
  );
  expect(
    find.descendant(
      of: deletedCard,
      matching: find.byIcon(Icons.remove_circle_outline),
    ),
    findsNothing,
  );
  expect(tester.widget<Card>(deletedCard).color, isNotNull);
  expect(
    history,
    isEmpty,
    reason: 'search/navigation never restores or removes food',
  );
  await capture?.call('deleted-restore');
  await tap(find.byTooltip('Restore Food shared containers'));
  await tester.pumpAndSettle();
  expect(
    projectFood(events).active.where((c) => c.details.name == 'Food shared'),
    hasLength(2),
  );
  expect(
    projectFood(events).deleted.where((c) => c.details.name == 'Food shared'),
    isEmpty,
  );
  await tap(find.byKey(const ValueKey('undo-food-action')));
  await tester.pumpAndSettle();
  expect(
    projectFood(events).deleted.where((c) => c.details.name == 'Food shared'),
    hasLength(1),
  );
  await _reach(tester, find.byTooltip('Remove one Food shared container'));
  await tap(find.byTooltip('Remove one Food shared container'));
  await tester.pumpAndSettle();
  expect(
    projectFood(events).active.where((c) => c.details.name == 'Food shared'),
    isEmpty,
  );
  await _reach(tester, find.byTooltip('Restore Food shared containers'));
  await tap(find.byKey(const ValueKey('undo-food-action')));
  await tester.pumpAndSettle();
  expect(
    projectFood(events).active.where((c) => c.details.name == 'Food shared'),
    hasLength(1),
  );

  await _query(tester, 'Food early', input: input);
  expect(find.widgetWithText(Card, 'Food early'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-deleted-heading')), findsNothing);
  await chooseFoodView(tester, 'Deleted', input: input);
  expect(
    find.widgetWithText(Card, 'Food early'),
    findsOneWidget,
    reason: 'saved Deleted filter cannot narrow search',
  );
  expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  await capture?.call('active-only-saved-deleted');
  await _query(tester, 'Food deleted', input: input);
  expect(find.byKey(const ValueKey('food-deleted-heading')), findsOneWidget);
  expect(find.text('Food early'), findsNothing);
  await capture?.call('deleted-only');
  await _query(tester, 'no matching synthetic food', input: input);
  expect(find.text('No matching food'), findsOneWidget);
  expect(find.byKey(const ValueKey('food-deleted-heading')), findsNothing);
  await capture?.call('no-results');
  await _query(tester, '', input: input);
  expect(
    find.byTooltip('Filter food: Deleted · active filters'),
    findsOneWidget,
  );
  expect(find.text('Food early'), findsNothing);
  await chooseFoodView(tester, 'Retained', input: input);
  expect(find.byType(ExpansionTile), findsNothing);
  expect(find.widgetWithText(Card, 'Food retained undated'), findsOneWidget);
  await _query(tester, 'Food early', input: input);
  await _query(tester, '', input: input);
  expect(find.byType(ExpansionTile), findsNothing);
  expect(find.widgetWithText(Card, 'Food retained undated'), findsOneWidget);
  expect(find.text('Food early'), findsNothing);
  expect(find.text('Search food'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final sample in [(900.0, 1.0), (320.0, 2.0)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'all-status Food search ${sample.$1} ${sample.$2}x ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(sample.$1, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await verifyFoodAllStatusSearch(
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
