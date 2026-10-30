import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/food_undo_history.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const _writer = '00000000-0000-4000-8000-000000000071';
String _id(int i) =>
    '00000000-0000-4000-8000-${(700 + i).toString().padLeft(12, '0')}';

const _beans = FoodDetails(
  name: 'Synthetic beans',
  expiry: '2026-11-01',
  location: 'Pantry',
);
const _rice = FoodDetails(
  name: 'Synthetic rice',
  expiry: '2026-11-02',
  location: 'Pantry',
);

FoodOperation _add(int order, int container, FoodDetails details) =>
    FoodOperation(
      id: '$_writer:$order',
      order: order,
      action: FoodAction.add,
      targets: [_id(container)],
      details: details,
      contents: const Contents.fraction(1, 1),
      createdAt: '2026-10-29T00:00:00Z',
    );

typedef _Write = ({
  List<String> ids,
  FoodDetails details,
  List<String> fields,
  FoodProductChange products,
});

class _Harness {
  _Harness(this.tester);
  final WidgetTester tester;
  final operations = <FoodOperation>[
    _add(1, 1, _beans),
    _add(2, 2, _beans),
    _add(3, 3, _rice),
  ];
  final writes = <_Write>[];
  late StateSetter update;

  FoodInventoryPageState get page =>
      tester.state<FoodInventoryPageState>(find.byType(FoodInventoryPage));

  Future<void> pump({
    double width = 800,
    double height = 1000,
    double textScale = 1,
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return FoodInventoryPage(
              state: projectFood(operations),
              onAdd: (_, _) {},
              onRemove: (_) {},
              onRestore: (_) {},
              onDetails: (items, details, fields, products) => writes.add((
                ids: items.map((e) => e.id).toList(),
                details: details,
                fields: fields,
                products: products,
              )),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A peer's container arriving in the Beans row.
  Future<void> arrive(int container) async {
    update(
      () => operations.add(_add(operations.length + 1, container, _beans)),
    );
    await tester.pumpAndSettle();
  }

  /// A peer moving one Beans container to the Freezer, out of the row.
  Future<void> leave(int container) async {
    update(
      () => operations.add(
        FoodOperation(
          id: '$_writer:${operations.length + 1}',
          order: operations.length + 1,
          action: FoodAction.edit,
          targets: [_id(container)],
          details: const FoodDetails(
            name: 'Synthetic beans',
            expiry: '2026-11-01',
            location: 'Freezer',
          ),
          fields: const ['location'],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ctrlTap(String name) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text(name).first);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(String name) async {
    await tester.tap(find.byTooltip('Actions for $name').first);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'a selected row includes arrivals and drops departures; Esc clears',
    (tester) async {
      final h = _Harness(tester);
      await h.pump();
      final before = tester.getTopLeft(find.text('Synthetic beans'));
      await h.ctrlTap('Synthetic beans');
      expect(h.page.selecting, isTrue);
      expect(h.page.bulkSelected, {_id(1), _id(2)});
      expect(find.text('2 selected'), findsOneWidget);
      // Selection is a highlight, not a checkbox column: nothing shifts.
      expect(
        find.descendant(
          of: find.byType(ListRowSurface),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      expect(tester.getTopLeft(find.text('Synthetic beans')), before);

      await h.arrive(4);
      expect(h.page.bulkSelected, {_id(1), _id(2), _id(4)});
      expect(find.text('3 selected'), findsOneWidget);
      // No partial state exists to display.
      expect(find.textContaining(' of '), findsNothing);

      await h.leave(1);
      expect(h.page.bulkSelected, {_id(2), _id(4)});
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Synthetic beans'), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.page.selecting, isFalse);
      expect(h.page.bulkSelected, isEmpty);
      expect(h.writes, isEmpty);
    },
  );

  testWidgets('the bulk editor counts and saves current containers live', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(width: 1400);
    await h.ctrlTap('Synthetic beans');
    // One selected row opens its own editor, which also follows the row.
    expect(find.text('Edit 2 containers'), findsOneWidget);
    await h.arrive(4);
    expect(find.text('Edit 3 containers'), findsOneWidget);
    await h.ctrlTap('Synthetic rice');
    expect(find.text('Edit 4 containers'), findsOneWidget);
    await h.arrive(5);
    expect(find.text('Edit 5 containers'), findsOneWidget);
    await h.leave(1);
    expect(find.text('Edit 4 containers'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('brandApply')));
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Unified');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(1));
    expect(h.writes.single.ids.toSet(), {_id(2), _id(3), _id(4), _id(5)});
    expect(h.page.selecting, isFalse);
  });

  testWidgets('one selected row edits its current containers', (tester) async {
    final h = _Harness(tester);
    await h.pump(width: 1400);
    await h.ctrlTap('Synthetic beans');
    await h.arrive(4);
    expect(find.text('Edit 3 containers'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Location'),
      'Cellar',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(h.writes.single.ids, [_id(1), _id(2), _id(4)]);
    expect(h.writes.single.fields, ['location']);
  });

  testWidgets('Move some validates beside its fields and sends one action', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    // A single container has nothing to split.
    await h.openMenu('Synthetic rice');
    expect(find.text('Move some…'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await h.openMenu('Synthetic beans');
    await tester.tap(find.text('Move some…'));
    await tester.pumpAndSettle();
    expect(find.text('Move some Synthetic beans'), findsOneWidget);
    final count = find.byKey(const ValueKey('food-move-count'));
    final location = find.descendant(
      of: find.byKey(const ValueKey('food-move-location')),
      matching: find.byType(TextField),
    );
    Future<void> move() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await tester.pumpAndSettle();
    }

    // Location first, so its suggestions close when How many takes focus.
    await tester.enterText(location, 'Pantry');
    await tester.enterText(count, '0');
    await tester.pumpAndSettle();
    await move();
    expect(find.text('Enter 1 to 2.'), findsOneWidget);
    expect(find.text('Choose a different location.'), findsOneWidget);
    expect(h.writes, isEmpty);

    // Errors follow corrections once revealed.
    await tester.enterText(count, '3');
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 2.'), findsOneWidget);
    // A container arriving while the dialog is open widens the range.
    await h.arrive(4);
    await tester.enterText(location, 'Freezer');
    await tester.enterText(count, '2');
    await tester.pumpAndSettle();
    expect(find.text('Enter 1 to 2.'), findsNothing);
    expect(find.text('Choose a different location.'), findsNothing);
    await move();
    expect(find.byKey(const ValueKey('food-move-some')), findsNothing);
    expect(h.writes, hasLength(1));
    final write = h.writes.single;
    expect(write.ids, [_id(1), _id(2)]);
    expect(write.fields, ['location']);
    expect(write.products.isEmpty, isTrue);
    expect(write.details.location, 'Freezer');
    expect(write.details.name, 'Synthetic beans');
    expect(write.details.expiry, '2026-11-01');
  });

  testWidgets('Move some Enter accepts an option then commits once', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    await h.openMenu('Synthetic beans');
    await tester.tap(find.text('Move some…'));
    await tester.pumpAndSettle();
    final location = find.descendant(
      of: find.byKey(const ValueKey('food-move-location')),
      matching: find.byType(TextField),
    );
    // Free text has no autocomplete option and Enter runs Move.
    await tester.enterText(location, 'New freezer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(1));
    expect(h.writes.single.details.location, 'New freezer');
    expect(find.byKey(const ValueKey('food-move-some')), findsNothing);
  });

  testWidgets('Move some at 200% text with keyboard keeps actions reachable', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump(width: 390, height: 844, textScale: 2, keyboard: 300);
    await h.openMenu('Synthetic beans');
    await tester.tap(find.text('Move some…'));
    await tester.pumpAndSettle();
    final location = find.descendant(
      of: find.byKey(const ValueKey('food-move-location')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(location);
    await tester.enterText(location, 'Freezer');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final move = find.widgetWithText(FilledButton, 'Move');
    expect(move.hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'Cancel').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(move);
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(1));
    expect(h.writes.single.details.location, 'Freezer');
  });

  testWidgets('Move some suggestion Enter does not also commit', (
    tester,
  ) async {
    final h = _Harness(tester);
    h.operations.add(
      FoodOperation(
        id: '$_writer:4',
        order: 4,
        action: FoodAction.edit,
        targets: [_id(3)],
        fields: const ['location'],
        details: const FoodDetails(
          name: 'Synthetic rice',
          expiry: '2026-11-02',
          location: 'Freezer',
        ),
      ),
    );
    await h.pump();
    await h.openMenu('Synthetic beans');
    await tester.tap(find.text('Move some…'));
    await tester.pumpAndSettle();
    final location = find.descendant(
      of: find.byKey(const ValueKey('food-move-location')),
      matching: find.byType(TextField),
    );
    await tester.enterText(location, 'Fre');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.writes, isEmpty);
    expect(tester.widget<TextField>(location).controller!.text, 'Freezer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(h.writes, hasLength(1));
  });

  testWidgets('Move some Cancel writes nothing', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    await h.openMenu('Synthetic beans');
    await tester.tap(find.text('Move some…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('food-move-some')), findsNothing);
    expect(h.writes, isEmpty);
  });

  group('Move some through the store', () {
    late Directory root;
    late LocalProfileDatabase profile;
    late TaskStore tasks;
    late FoodStore food;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('food-move-some-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/data').create()).path,
      );
      profile = await LocalProfileDatabase.open('${root.path}/profile');
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: _writer,
      );
      food = await FoodStore.openUnified(tasks.unified!);
    });
    tearDown(() async {
      await food.close();
      await tasks.close();
      await profile.close();
      await root.delete(recursive: true);
    });

    Map<String, dynamic> snapshot() => {
      for (final item in food.state.containers)
        item.id: jsonDecode(jsonEncode(item.toJson())),
    };

    test(
      'splits containers into their own row; one Undo rejoins them',
      () async {
        await food.add(_beans, 3);
        final before = snapshot();
        final row = food.state.groups.single;
        final moving = food.state.rows[row.rowKey]!.take(2).toList();
        final history = FoodUndoHistory()..setWorkspace('synthetic');
        await food.changeDetails(
          moving.map((e) => e.id).toList(),
          const FoodDetails(
            name: 'Synthetic beans',
            expiry: '2026-11-01',
            location: 'Freezer',
          ),
          const ['location'],
        );
        history.record(
          'editing',
          food.lastPreparedRecords,
          confirmed: food.isAdmitted,
        );
        expect(history.length, 1);
        final groups = food.state.groups;
        expect(groups.map((g) => g.containers.length).toList()..sort(), [1, 2]);
        expect(
          groups
              .firstWhere((g) => g.details.location == 'Freezer')
              .containers
              .map((e) => e.id),
          moving.map((e) => e.id),
        );

        final entry = history.latest!;
        await food.undoOperations(entry.records);
        history.complete(entry);
        expect(history.length, 0);
        expect(snapshot(), before);
        expect(food.state.groups.single.containers, hasLength(3));
      },
    );
  });
}
