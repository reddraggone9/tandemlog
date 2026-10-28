import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/food/food_admission.dart';
import 'package:tandemlog/food/food_purchase_import.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

const installation = '00000000-0000-4000-8000-000000000001';

void main() {
  late Directory root;
  late LocalProfileDatabase profile;
  late TaskStore tasks;
  late FoodStore food;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('food-products-');
    profile = await LocalProfileDatabase.open('${root.path}/profile');
    final data = await Directory('${root.path}/data').create();
    final folder = LocalLogFolder(data.path);
    tasks = await TaskStore.open(
      folder,
      profile.root,
      profileDatabase: profile,
      writerIdentity: installation,
    );
    await folder.create('$installation.applog', Uint8List(0));
    await tasks.refresh();
    food = await FoodStore.openUnified(tasks.unified!);
  });
  tearDown(() async {
    await food.close();
    await tasks.close();
    await profile.close();
    await root.delete(recursive: true);
  });

  List<FoodRecord> records() => [
    for (final action in tasks.unified!.snapshot.records)
      for (final effect in action.effects)
        if (effect.food != null) effect.food!,
  ];

  /// Full admission of every record must equal the incremental store state.
  void expectReplayEquivalent() {
    final full = admitFoodRecords(records()).state;
    expect(
      full.containers.map((e) => e.toJson()).toList(),
      food.state.containers.map((e) => e.toJson()).toList(),
    );
    expect(full.products.keys.toSet(), food.state.products.keys.toSet());
  }

  List<String> rows() => [
    for (final group in food.state.groups)
      '${group.details.name}|${group.details.brand}|${group.details.size}|'
          '${group.details.expiry}|${group.containers.length}',
  ];

  Future<FoodGroup> rowOf(String name, String expiry) async => food.state.groups
      .firstWhere((g) => g.details.name == name && g.details.expiry == expiry);

  test('ordinary Adds stay revision 1 and form implicit products', () async {
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 2);
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-03'), 1);
    final families = [
      for (final r in records())
        '${r.currentOperation.family}/${r.currentOperation.revision}',
    ];
    expect(families, ['container.add/1', 'container.add/1']);
    expect(food.state.products, hasLength(1));
    final product = food.state.products.values.single;
    expect(product.id, implicitFoodProductId(const FoodDetails(name: 'Milk')));
    expect(product.onHand, 3);
    expect(rows(), ['Milk|||2026-11-01|2', 'Milk|||2026-11-03|1']);
    expectReplayEquivalent();
  });

  test(
    'renaming a product renames every row of it, as one Undo action',
    () async {
      await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 2);
      await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-03'), 1);
      final row = await rowOf('Milk', '2026-11-01');
      await food.changeDetails(
        row.containers.map((e) => e.id).toList(),
        row.details,
        const [],
        products: FoodProductChange(
          roots: [row.product],
          changes: const {'name': 'Milk 2%', 'brand': 'Great Value'},
        ),
      );
      final edit = food.lastPreparedRecords;
      expect(edit.single.currentOperation.family, 'product.edit');
      // The first edit of an implicit product records its whole description.
      expect(edit.single.operation.product, {
        'name': 'Milk 2%',
        'brand': 'Great Value',
        'size': '',
      });
      expect(rows(), [
        'Milk 2%|Great Value||2026-11-01|2',
        'Milk 2%|Great Value||2026-11-03|1',
      ]);
      expectReplayEquivalent();
      await food.undoOperations(edit);
      expect(food.lastPreparedRecords.single.createdWith, isEmpty);
      expect(rows(), ['Milk|||2026-11-01|2', 'Milk|||2026-11-03|1']);
      expectReplayEquivalent();
    },
  );

  test('renaming into an existing product merges; Undo separates', () async {
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 2);
    await food.add(
      const FoodDetails(name: 'Whole milk', expiry: '2026-11-01'),
      1,
    );
    final row = await rowOf('Whole milk', '2026-11-01');
    await food.changeDetails(
      row.containers.map((e) => e.id).toList(),
      row.details,
      const [],
      products: FoodProductChange(
        roots: [row.product],
        changes: const {'name': 'milk'},
      ),
    );
    final merge = food.lastPreparedRecords;
    expect(merge.map((r) => r.currentOperation.family), [
      'product.edit',
      'product.merge',
    ]);
    expect(food.state.products, hasLength(1));
    expect(rows(), ['Milk|||2026-11-01|3']);
    expectReplayEquivalent();
    await food.undoOperations(merge);
    expect(food.state.products, hasLength(2));
    expect(rows(), ['Milk|||2026-11-01|2', 'Whole milk|||2026-11-01|1']);
    expectReplayEquivalent();
  });

  test('bulk unify merges products whose new descriptions coincide', () async {
    await food.add(const FoodDetails(name: 'Bars', expiry: '2026-12-01'), 3);
    await food.add(
      const FoodDetails(name: 'Protein bar', expiry: '2026-12-01'),
      1,
    );
    await food.add(
      const FoodDetails(name: 'Quest bar', expiry: '2026-12-05'),
      1,
    );
    final selected = food.state.groups.toList();
    await food.changeDetails(
      [for (final g in selected) ...g.containers.map((e) => e.id)],
      selected.first.details,
      const [],
      products: FoodProductChange(
        roots: {for (final g in selected) g.product}.toList(),
        changes: const {'name': 'Protein bar', 'brand': 'Quest'},
      ),
    );
    expect(food.state.products, hasLength(1));
    // The product with the most containers keeps its identity.
    expect(
      food.state.products.keys.single,
      implicitFoodProductId(const FoodDetails(name: 'Bars')),
    );
    expect(rows(), [
      'Protein bar|Quest||2026-12-01|4',
      'Protein bar|Quest||2026-12-05|1',
    ]);
    expectReplayEquivalent();
  });

  test('Add joins a product by case-insensitive description', () async {
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 1);
    final row = await rowOf('Milk', '2026-11-01');
    await food.changeDetails(
      [row.containers.single.id],
      row.details,
      const [],
      products: FoodProductChange(
        roots: [row.product],
        changes: const {'name': 'Milk 2%'},
      ),
    );
    await food.add(const FoodDetails(name: 'milk 2%', expiry: '2026-11-01'), 1);
    expect(food.lastPreparedRecords.single.currentOperation.revision, 2);
    expect(rows(), ['Milk 2%|||2026-11-01|2']);
    // The renamed product's old description now names a new product.
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 1);
    expect(food.lastPreparedRecords.map((r) => r.currentOperation.family), [
      'product.edit',
      'container.add',
    ]);
    expect(food.state.products, hasLength(2));
    expect(rows(), ['Milk 2%|||2026-11-01|2', 'Milk|||2026-11-01|1']..sort());
    expectReplayEquivalent();
  });

  test('keep-at-least minimums list products running low', () async {
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 1);
    final row = await rowOf('Milk', '2026-11-01');
    await food.changeDetails(
      [row.containers.single.id],
      row.details,
      const [],
      products: FoodProductChange(
        roots: [row.product],
        changes: const {
          'minimum': 2,
          'links': ['https://www.walmart.com/ip/10450114'],
        },
      ),
    );
    expect(food.state.runningLow.single.name, 'Milk');
    expect(food.state.runningLow.single.onHand, 1);
    expect(food.state.runningLow.single.links, [
      'https://www.walmart.com/ip/10450114',
    ]);
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-04'), 1);
    expect(food.state.runningLow, isEmpty);
    await food.remove([
      for (final g in food.state.groups) g.containers.first.id,
    ]);
    // A product with no containers left still shows (decision 5).
    expect(food.state.runningLow.single.onHand, 0);
    expectReplayEquivalent();
  });

  group('purchase import', () {
    FoodPurchaseImportPlan plan(List<FoodPurchaseLine> lines) =>
        FoodPurchaseImportPlan(
          space: food.space,
          importId: '11111111-1111-4111-8111-111111111111',
          sourceSha256: 'a' * 64,
          lines: lines,
        );
    FoodPurchaseLine milk({int quantity = 3, int amount = 1044}) =>
        FoodPurchaseLine(
          sourceKind: 'ynab',
          sourceKey: 'txn-1#2',
          date: DateTime.now().toUtc().toIso8601String().substring(0, 10),
          store: 'Walmart',
          amount: amount,
          quantity: quantity,
          name: 'milk',
          link: 'https://www.walmart.com/ip/10450114',
        );

    test(
      'links recent hand entries and creates the rest in the Inbox',
      () async {
        await food.add(
          const FoodDetails(name: 'Milk', expiry: '2026-11-01'),
          1,
        );
        final hand = food.state.containers.single.id;
        final dry = await food.dryRunPurchaseImport(plan([milk()]));
        expect(dry.status, FoodPurchaseImportStatus.ready);
        expect(dry.lines.single.matched, [hand]);
        expect(dry.lines.single.created, hasLength(2));
        final before = records().length;
        expect(records().length, before);
        final report = await food.commitPurchaseImport(plan([milk()]));
        expect(report.lines.single.matched, [hand]);
        final product = food.state.products.values.single;
        expect(product.onHand, 3);
        expect(product.links, ['https://www.walmart.com/ip/10450114']);
        expect(product.last!.unitCost, closeTo(348, .001));
        expect(food.state.view(FoodView.inbox).single.containers, hasLength(2));
        expect(food.state.containers.map((c) => c.purchase).toSet(), {
          milk().purchaseId,
        });
        expectReplayEquivalent();
        // A retry writes nothing.
        final count = records().length;
        final retry = await food.commitPurchaseImport(plan([milk()]));
        expect(retry.status, FoodPurchaseImportStatus.committed);
        expect(records().length, count);
        // A different value for the same receipt line fails before writing.
        await expectLater(
          food.dryRunPurchaseImport(plan([milk(amount: 999)])),
          throwsFormatException,
        );
      },
    );

    test('Undo of an import removes containers and the purchase', () async {
      await food.commitPurchaseImport(plan([milk(quantity: 2)]));
      expect(food.state.active, hasLength(2));
      await food.undoOperations(food.lastPreparedRecords);
      expect(food.state.active, isEmpty);
      expect(food.state.catalog.purchases, isEmpty);
      expectReplayEquivalent();
    });
  });

  test('every new family round-trips through its exact bytes', () async {
    await food.add(const FoodDetails(name: 'Milk', expiry: '2026-11-01'), 1);
    final row = await rowOf('Milk', '2026-11-01');
    await food.add(
      const FoodDetails(name: 'Oat milk', expiry: '2026-11-01'),
      1,
    );
    await food.changeDetails(
      [row.containers.single.id],
      row.details,
      const [],
      products: FoodProductChange(
        roots: [row.product],
        changes: const {'name': 'Oat milk', 'minimum': 1},
      ),
    );
    for (final record in records()) {
      final decoded = FoodRecord.decode(record.encode());
      expect(decoded.encode(), record.encode());
      expect(decoded.hash, record.hash);
    }
  });

  test('unknown future Food families fail closed with the update message', () {
    final operation = CurrentOperation(
      module: 'food',
      space: '00000000-0000-4000-8000-0000000000aa',
      author: '00000000-0000-4000-8000-0000000000bb',
      writer: '00000000-0000-4000-8000-0000000000bb',
      sequence: 1,
      clock: '5',
      subject: '00000000-0000-4000-8000-0000000000aa',
      family: 'product.retire',
      revision: 1,
      value: {
        'values': {
          'targets': ['00000000-0000-4000-8000-0000000000cc'],
        },
        'creationBasis': <String, String>{},
      },
      predecessor: '0' * 64,
    );
    expect(
      () => FoodRecord.decode(operation.encode()),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Update the app'),
        ),
      ),
    );
  });

  test('merge races resolve identically in every delivery order', () {
    final ops = <FoodOperation>[
      FoodOperation(
        id: 'aaaaaaaa-0000-4000-8000-000000000000:1',
        order: 1,
        action: FoodAction.add,
        targets: const ['00000000-0000-4000-8000-0000000000c1'],
        details: const FoodDetails(name: 'A'),
        createdAt: '2026-10-28T00:00:00Z',
      ),
      FoodOperation(
        id: 'aaaaaaaa-0000-4000-8000-000000000000:2',
        order: 2,
        action: FoodAction.add,
        targets: const ['00000000-0000-4000-8000-0000000000c2'],
        details: const FoodDetails(name: 'B'),
        createdAt: '2026-10-28T00:00:00Z',
      ),
    ];
    final a = implicitFoodProductId(const FoodDetails(name: 'A')),
        b = implicitFoodProductId(const FoodDetails(name: 'B'));
    final merges = [
      FoodOperation(
        id: 'bbbbbbbb-0000-4000-8000-000000000000:1',
        order: 10,
        action: FoodAction.merge,
        targets: [a],
        into: b,
      ),
      FoodOperation(
        id: 'cccccccc-0000-4000-8000-000000000000:1',
        order: 10,
        action: FoodAction.merge,
        targets: [b],
        into: a,
      ),
    ];
    final first = projectFood([...ops, ...merges]);
    final second = projectFood([...merges.reversed, ...ops.reversed]);
    expect(first.products.keys, [b]);
    expect(
      second.containers.map((e) => e.toJson()).toList(),
      first.containers.map((e) => e.toJson()).toList(),
    );
    expect(first.containers.map((c) => c.product).toSet(), {b});
  });
}
