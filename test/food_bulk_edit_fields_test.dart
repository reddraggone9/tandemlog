import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/food_undo_history.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/bulk_apply.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const _writer = '00000000-0000-4000-8000-000000000051';
String _id(int i) =>
    '00000000-0000-4000-8000-${(900 + i).toString().padLeft(12, '0')}';

// The same product entered three ways, as in Lee's unification goal.
const _variants = [
  FoodDetails(
    name: 'Protein bars',
    brand: 'Acme',
    expiry: '2026-11-01',
    size: '12 ct',
    location: 'Pantry',
  ),
  FoodDetails(
    name: 'protein bar',
    brand: 'ACME',
    expiry: '2026-12-01',
    size: '12 bars',
    location: 'Pantry',
    retention: 'Snack drawer',
  ),
  FoodDetails(
    name: 'Bars, protein',
    expiry: '2027-01-01',
    size: '12 ct',
    location: 'Pantry',
  ),
];

typedef _Write = ({List<String> ids, FoodDetails details, List<String> fields});

Future<List<_Write>> _pumpSelected(WidgetTester tester) async {
  final operations = <FoodOperation>[
    for (final (i, details) in _variants.indexed)
      FoodOperation(
        id: '$_writer:${i + 1}',
        order: i + 1,
        action: FoodAction.add,
        targets: [_id(i + 1)],
        details: details,
        contents: const Contents.fraction(1, 1),
        createdAt: '2026-10-11T00:00:00Z',
      ),
  ];
  final writes = <_Write>[];
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: FoodInventoryPage(
        state: projectFood(operations),
        onAdd: (_, _) {},
        onRemove: (_) {},
        onRestore: (_) {},
        onDetails: (items, details, fields) => writes.add((
          ids: items.map((e) => e.id).toList(),
          details: details,
          fields: List.of(fields),
        )),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Search shows Stock and Retained variants together.
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'pro');
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('food-search')), 'ba');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('food-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select matching containers'));
  await tester.pumpAndSettle();
  expect(find.text('3 selected'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Edit'));
  await tester.pumpAndSettle();
  expect(find.text('Edit 3 containers'), findsOneWidget);
  return writes;
}

Checkbox _apply(WidgetTester tester, String field) =>
    tester.widget<Checkbox>(find.byKey(ValueKey('${field}Apply')));

void main() {
  testWidgets('bulk Food edit offers every field except Expiration', (
    tester,
  ) async {
    final writes = await _pumpSelected(tester);
    for (final label in ['Food name', 'Brand', 'Container size', 'Location']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.bySemanticsLabel('Apply Retention reason'), findsOneWidget);
    expect(find.text('Expiration'), findsNothing);
    expect(find.text('Containers to add'), findsNothing);
    // Mixed values start blank, marked mixed and unapplied; a shared value
    // is shown. Untouched Save writes nothing.
    for (final field in ['name', 'brand', 'size', 'retention']) {
      expect(_apply(tester, field).value, isFalse, reason: field);
    }
    expect(find.text(bulkMixedHint), findsNWidgets(3));
    expect(find.text('Retention reason — Mixed'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Location'))
          .controller!
          .text,
      'Pantry',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only touched fields apply, including an applied blank clear', (
    tester,
  ) async {
    final writes = await _pumpSelected(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Food name'),
      'Protein bars',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Container size'),
      '12 ct',
    );
    await tester.pumpAndSettle();
    expect(_apply(tester, 'name').value, isTrue);
    expect(_apply(tester, 'size').value, isTrue);
    expect(_apply(tester, 'brand').value, isFalse);
    // An applied blank field clears the value, as in the Tasks bulk editor.
    await tester.tap(find.byKey(const ValueKey('retentionApply')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    final write = writes.single;
    expect(write.ids.toSet(), {_id(1), _id(2), _id(3)});
    expect(write.fields, ['name', 'size', 'retention']);
    expect(write.details.name, 'Protein bars');
    expect(write.details.size, '12 ct');
    expect(write.details.retention, '');
    // Applying to the projection keeps each container's own Brand/Expiration.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an applied blank Food name is rejected beside the field', (
    tester,
  ) async {
    final writes = await _pumpSelected(tester);
    await tester.tap(find.byKey(const ValueKey('nameApply')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a food name.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('food-save-action')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a food name.'), findsOneWidget);
    expect(find.text('Edit 3 containers'), findsOneWidget);
    expect(writes, isEmpty);
  });

  group('bulk Food edit Undo', () {
    late Directory root;
    late LocalProfileDatabase profile;
    late TaskStore tasks;
    late FoodStore food;
    late LocalLogFolder folder;

    Future<FoodStore> open(String profilePath) async {
      profile = await LocalProfileDatabase.open(profilePath);
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: _writer,
      );
      return FoodStore.openUnified(tasks.unified!);
    }

    Future<void> close() async {
      await food.close();
      await tasks.close();
      await profile.close();
    }

    Map<String, dynamic> snapshot(FoodStore store) => {
      for (final item in store.state.containers)
        item.id: jsonDecode(jsonEncode(item.toJson())),
    };

    setUp(() async {
      root = await Directory.systemTemp.createTemp('food-bulk-fields-');
      folder = LocalLogFolder(
        (await Directory('${root.path}/data').create()).path,
      );
      food = await open('${root.path}/profile');
    });
    tearDown(() async {
      await close();
      await root.delete(recursive: true);
    });

    test(
      'one Undo restores every selected container across reload and replay',
      () async {
        for (final details in _variants) {
          await food.add(details, 2);
        }
        await food.remove([food.state.active.last.id]);
        final untouched = food.state.active.first.id;
        final selected = food.state.containers
            .map((e) => e.id)
            .where((id) => id != untouched)
            .toList();
        final before = snapshot(food);
        final history = FoodUndoHistory()..setWorkspace('synthetic');
        await food.changeDetails(
          selected,
          const FoodDetails(
            name: 'Protein bars',
            brand: 'Acme',
            expiry: '2099-12-31',
            size: '12 ct',
            location: 'Snack shelf',
            retention: '',
          ),
          ['name', 'brand', 'size', 'location', 'retention'],
        );
        history.record(
          'editing',
          food.lastPreparedRecords,
          confirmed: food.isAdmitted,
        );
        expect(history.length, 1);
        expect(history.latest!.label, 'editing ${selected.length} containers');
        final edited = snapshot(food);
        for (final id in selected) {
          final details = edited[id]['details'] as Map;
          expect(details['name'], 'Protein bars');
          expect(details['brand'], 'Acme');
          expect(details['size'], '12 ct');
          expect(details['location'], 'Snack shelf');
          expect(details['retention'], '');
          // Expiration and deletion state are per container and untouched.
          expect(details['expiry'], (before[id]['details'] as Map)['expiry']);
          expect(edited[id]['deleted'], before[id]['deleted']);
        }
        expect(edited[untouched], before[untouched]);

        // The edited state replays from the log in a reopened profile and in a
        // fresh profile that reads every record.
        await close();
        food = await open('${root.path}/profile');
        expect(snapshot(food), edited);
        await close();
        food = await open('${root.path}/fresh-before-undo');
        expect(snapshot(food), edited);

        // Undo history is session-local; the reopened store undoes the same
        // confirmed receipts as one action.
        final entry = history.latest!;
        final inverse = await food.undoOperations(entry.records);
        expect(inverse, isNotEmpty);
        expect(inverse.every(food.isAdmitted), isTrue);
        history.complete(entry);
        expect(history.length, 0);
        expect(snapshot(food), before);

        await close();
        food = await open('${root.path}/fresh-profile');
        expect(snapshot(food), before);
        await close();
        food = await open('${root.path}/profile');
        expect(snapshot(food), before);
      },
    );
  });
}
