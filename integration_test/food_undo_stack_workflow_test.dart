import 'package:tandemlog/storage/unified_record.dart';
import 'profile_fixture.dart';
import '../test/support/toolbar_button.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import '../test/batch_storage_test.dart' show CountingFolder;
import '../test/food_expiry_guidance_test.dart' show selectFoodView;
import 'food_production_workflow_test.dart' show switchSection;
import 'food_preview_workflow_test.dart' as pixels;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart'
    show TestFolders, waitForUi, recoverSharedReadForTest;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodUndoStackWorkflowTests();
}

void registerFoodUndoStackWorkflowTests() {
  testWidgets('Food bulk actions Undo through every original state', (
    tester,
  ) async {
    await _withWorkspace(tester, (fixture) async {
      await pixels.capture(tester, 'food-undo-demo-warmup-not-evidence');
      await pixels.startRecording(tester);
      final states = [_snapshot(tester)];
      await _add(tester, 'Synthetic undo rice', count: 2);
      final originalIds = _named(
        tester,
        'Synthetic undo rice',
      ).map((item) => item.id).toSet();
      expect(originalIds, hasLength(2));
      states.add(_snapshot(tester));
      await captureNativeFixtureUi(tester, 'food-undo-bulk-add');
      _expectUndo(tester, contains('adding'));

      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'Synthetic undo rice',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('food-filter')));
      await _tap(tester, find.text('Select matching containers'));
      // One whole selected row opens its single editor immediately at wide
      // widths; editing the product still updates both containers as one Undo.
      expect(
        tester
            .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
            .bulkSelected,
        hasLength(2),
      );
      expect(
        find.byKey(const ValueKey('food-search')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('brandApply')), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand'),
        'Synthetic bulk brand',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
      await _idle(tester);
      expect(
        _named(
          tester,
          'Synthetic undo rice',
        ).every((item) => item.details.brand == 'Synthetic bulk brand'),
        isTrue,
      );
      _expectUndo(tester, contains('editing'));
      await captureNativeFixtureUi(tester, 'food-undo-brand-bulk-applied');
      await _undo(
        tester,
        () => _named(
          tester,
          'Synthetic undo rice',
        ).every((item) => item.details.brand.isEmpty),
      );
      expect(_snapshot(tester), states.last);
      _expectUndo(tester, contains('adding'));
      await captureNativeFixtureUi(tester, 'food-undo-brand-bulk-restored');

      await _edit(tester, 'Synthetic undo rice', {
        'Brand': 'Edited brand',
        'Expiration': '2027-07-09',
        'Container size': '500 g',
        'Location': 'Pantry',
        'Retention reason': 'Synthetic trip',
      });
      await tester.enterText(
        find.byKey(const ValueKey('food-search')),
        'Synthetic undo rice',
      );
      await tester.pumpAndSettle();
      expect(
        _named(tester, 'Synthetic undo rice').map((e) => e.id).toSet(),
        originalIds,
      );
      expect(
        _named(tester, 'Synthetic undo rice').every(
          (item) =>
              item.details.expiry == '2027-07-09' &&
              item.details.brand == 'Edited brand' &&
              item.details.retention == 'Synthetic trip' &&
              item.details.location == 'Pantry' &&
              item.details.size == '500 g',
        ),
        isTrue,
      );
      states.add(_snapshot(tester));
      _expectUndo(tester, contains('editing'));

      final first = _named(tester, 'Synthetic undo rice').first;
      final historicalContents = {
        for (final item in _named(tester, 'Synthetic undo rice'))
          item.id: item.contents.toJson(),
      };
      await _tap(
        tester,
        find.byTooltip('Remove one Synthetic undo rice container'),
      );
      await _idle(tester);
      expect(
        _named(
          tester,
          'Synthetic undo rice',
        ).where((e) => e.deleted).map((e) => e.id),
        [first.id],
      );
      states.add(_snapshot(tester));
      _expectUndo(tester, contains('removing'));
      await _tap(
        tester,
        find.byTooltip('Restore one Synthetic undo rice container'),
      );
      await _idle(tester);
      expect(
        _named(tester, 'Synthetic undo rice').every((e) => !e.deleted),
        isTrue,
      );
      expect({
        for (final item in _named(tester, 'Synthetic undo rice'))
          item.id: item.contents.toJson(),
      }, historicalContents);
      states.add(_snapshot(tester));
      _expectUndo(tester, contains('restoring'));

      await _tap(tester, find.byTooltip('Actions for Synthetic undo rice'));
      await _tap(tester, find.text('Remove 2 containers'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Remove'));
      await _idle(tester);
      expect(
        _named(tester, 'Synthetic undo rice').every((e) => e.deleted),
        isTrue,
      );
      states.add(_snapshot(tester));
      _expectUndo(tester, contains('removing'));

      await tester.enterText(find.byKey(const ValueKey('food-search')), '');
      await tester.pumpAndSettle();
      await selectFoodView(tester, FoodView.deleted);
      await _tap(tester, find.byTooltip('Actions for Synthetic undo rice'));
      await _tap(tester, find.text('Restore 2 containers'));
      await _idle(tester);
      expect(
        _named(tester, 'Synthetic undo rice').every((e) => !e.deleted),
        isTrue,
      );
      states.add(_snapshot(tester));
      _expectUndo(tester, contains('restoring'));

      // Each bulk command occupies one action, regardless of container count.
      for (var index = states.length - 2; index >= 0; index--) {
        await _undo(tester, () => _snapshot(tester) == states[index]);
        expect(_snapshot(tester), states[index]);
        await captureNativeFixtureUi(tester, 'food-undo-stack-state-$index');
      }
      expect(
        _state(tester).containers.any((e) => originalIds.contains(e.id)),
        isFalse,
      );
      expect(
        _state(tester).deleted.any((e) => originalIds.contains(e.id)),
        isFalse,
        reason: 'Undo Add does not manufacture a removal',
      );
      expect(_undoButton(tester).onPressed, isNull);
      final records = await _foodRecords(fixture.folder.delegate);
      final births = records.where(
        (record) =>
            record.operation.action == FoodAction.add &&
            record.operation.targets.any(originalIds.contains),
      );
      expect(births, hasLength(1));
      expect(
        births.single.operation.targets.toSet(),
        originalIds,
        reason: 'Undo retains the canonical original physical births',
      );
      expect(records.map((e) => e.id).toSet().length, records.length);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'Food Undo survives navigation and users, isolates Tasks and folders',
    (tester) async {
      await _withWorkspace(tester, (fixture) async {
        await _add(tester, 'Synthetic session oats');
        await switchSection(tester, food: false);
        await tester.enterText(
          find.byKey(const ValueKey('task-search')),
          'Synthetic Alex task',
        );
        await tester.pumpAndSettle();
        final checkbox = find.descendant(
          of: find.byKey(ValueKey('task-row-${fixture.task}')),
          matching: find.byType(Checkbox),
        );
        await tester.tap(checkbox);
        await waitForUi(
          tester,
          () => tester.widget<Checkbox>(checkbox).value == true,
        );
        await switchSection(tester, food: true);
        await selectFoodView(tester, FoodView.retained);
        await tester.enterText(
          find.byKey(const ValueKey('food-search')),
          'Synthetic',
        );
        await tester.pumpAndSettle();
        await _account(tester, 'Synthetic Blair');
        expect(find.byTooltip('Active user: Synthetic Blair'), findsOneWidget);
        final taskBytes = await _records(
          fixture.folder.delegate,
          tasksOnly: true,
        );
        await _undo(
          tester,
          () => _named(tester, 'Synthetic session oats').isEmpty,
        );
        expect(
          await _records(fixture.folder.delegate, tasksOnly: true),
          taskBytes,
        );
        await switchSection(tester, food: false);
        expect(tester.widget<Checkbox>(checkbox).value, true);
        final taskUndo = find.byKey(const ValueKey('undo-task-action'));
        expect(toolbarButton(tester, taskUndo).onPressed, isNotNull);
        await tester.tap(taskUndo);
        await waitForUi(
          tester,
          () => tester.widget<Checkbox>(checkbox).value == false,
        );
        await switchSection(tester, food: true);
        expect(_undoButton(tester).onPressed, isNull);

        await tester.enterText(find.byKey(const ValueKey('food-search')), '');
        await tester.pumpAndSettle();
        await _add(tester, 'Synthetic workspace oats');
        final staleUndo = _undoButton(tester).onPressed!;
        final original = await _records(fixture.folder.delegate);
        await _changeWorkspace(tester, fixture, fixture.otherFolder);
        expect(_undoButton(tester).onPressed, isNull);
        final other = await _records(LocalLogFolder(fixture.otherFolder));
        staleUndo();
        await _idle(tester);
        expect(await _records(fixture.folder.delegate), original);
        expect(await _records(LocalLogFolder(fixture.otherFolder)), other);
        await _changeWorkspace(tester, fixture, fixture.folder.location);
        expect(_undoButton(tester).onPressed, isNull);
        expect(_named(tester, 'Synthetic workspace oats'), hasLength(1));
        expect(await _records(fixture.folder.delegate), original);
        await captureNativeFixtureUi(tester, 'food-undo-folder-isolation');
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Food Undo retracts local details while preserving independent peer edits',
    (tester) async {
      await _withWorkspace(tester, (fixture) async {
        await _edit(tester, 'Synthetic baseline beans', {
          'Brand': 'Local brand',
        });
        final beforePeer = _named(tester, 'Synthetic baseline beans').single;
        await tester.runAsync(() async {
          await fixture.peer.refresh();
          await fixture.peer.changeDetails(
            [beforePeer.id],
            const FoodDetails(
              name: 'Synthetic baseline beans',
              expiry: '2027-06-01',
              location: 'Peer shelf',
            ),
            ['location'],
          );
        });
        await _refreshFood(tester);
        expect(
          _named(tester, 'Synthetic baseline beans').single.details.brand,
          'Local brand',
        );
        expect(
          _named(tester, 'Synthetic baseline beans').single.details.location,
          'Peer shelf',
        );
        final peerBytes = await fixture.folder.delegate.read(
          unifiedLogName(fixture.peer.unified!.writer),
        );
        await _undo(
          tester,
          () =>
              _named(tester, 'Synthetic baseline beans').single.details.brand ==
              'Seed brand',
        );
        final restored = _named(tester, 'Synthetic baseline beans').single;
        expect(restored.id, beforePeer.id);
        expect(restored.details.location, 'Peer shelf');
        expect(
          await fixture.folder.delegate.read(
            unifiedLogName(fixture.peer.unified!.writer),
          ),
          peerBytes,
        );
        expect(restored.details.expiry, '2027-06-01');
        await _edit(tester, 'Synthetic baseline beans', {
          'Brand': 'Second local brand',
        });
        await tester.runAsync(() async {
          await fixture.peer.refresh();
          await fixture.peer.changeDetails(
            [beforePeer.id],
            const FoodDetails(
              name: 'Synthetic baseline beans',
              expiry: '2027-06-01',
              brand: 'Newer peer brand',
            ),
            ['brand'],
          );
        });
        await _refreshFood(tester);
        final newer = _snapshot(tester);
        expect(
          _named(tester, 'Synthetic baseline beans').single.details.brand,
          'Newer peer brand',
        );
        final newerPeerBytes = await fixture.folder.delegate.read(
          unifiedLogName(fixture.peer.unified!.writer),
        );
        final appendedBeforeUndo = fixture.folder.appends;
        _expectUndo(tester, contains('editing'));
        await tester.tap(_undoFinder(tester));
        await waitForUi(
          tester,
          () =>
              fixture.folder.appends > appendedBeforeUndo &&
              _undoButton(tester).onPressed == null,
        );
        await _idle(tester);
        expect(
          _snapshot(tester),
          newer,
          reason:
              'Withdrawing a superseded local edit cannot overwrite the newer peer',
        );
        expect(
          await fixture.folder.delegate.read(
            unifiedLogName(fixture.peer.unified!.writer),
          ),
          newerPeerBytes,
        );
        expect(
          _named(tester, 'Synthetic baseline beans').single.details.location,
          'Peer shelf',
        );
        await captureNativeFixtureUi(tester, 'food-undo-independent-peer-edit');
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Failed Food Add keeps prior Undo and retries the original identities',
    (tester) async {
      await _withWorkspace(tester, (fixture) async {
        final baseline = _snapshot(tester);
        await _add(tester, 'Synthetic prior rice');
        final prior = _snapshot(tester);
        await _openAdd(tester, 'Synthetic pending rice', count: 2);
        fixture.folder.fault = 'before';
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await waitForUi(tester, () => fixture.folder.delayedSuffix != null);
        await recoverSharedReadForTest(tester);
        final name = fixture.folder.delayedName!;
        final reserved = List<int>.of(fixture.folder.delayedSuffix!);
        final packets = _decodeRecords(reserved);
        final targetIds = packets.expand((e) => e.operation.targets).toSet();
        expect(targetIds, hasLength(2));
        expect(_snapshot(tester), prior);
        expect(_undoButton(tester).onPressed, isNull);
        final bytes = await _records(fixture.folder.delegate);
        await captureNativeFixtureUi(tester, 'food-undo-pending-add');
        await tester.tap(find.widgetWithText(FilledButton, 'Retry save'));
        await waitForUi(
          tester,
          () => find.widgetWithText(TextField, 'Food name').evaluate().isEmpty,
        );
        await _idle(tester);
        final prefix = bytes[name] ?? const <int>[];
        expect(await fixture.folder.delegate.read(name), [
          ...prefix,
          ...reserved,
        ]);
        expect(
          _named(tester, 'Synthetic pending rice').map((e) => e.id).toSet(),
          targetIds,
        );
        await _undo(tester, () => _snapshot(tester) == prior);
        await _undo(tester, () => _snapshot(tester) == baseline);
        final all = await _foodRecords(fixture.folder.delegate);
        expect(all.map((e) => e.id).toSet().length, all.length);
        expect(
          all.where(
            (e) =>
                e.operation.action == FoodAction.add &&
                e.operation.targets.any(targetIds.contains),
          ),
          hasLength(1),
        );
        expect(_undoButton(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Failed Food inverse keeps the stack until exact Retry confirms it',
    (tester) async {
      await _withWorkspace(tester, (fixture) async {
        final baseline = _snapshot(tester);
        await _add(tester, 'Synthetic inverse oats');
        final added = _snapshot(tester);
        await _edit(tester, 'Synthetic inverse oats', {'Brand': 'Local edit'});
        final edited = _snapshot(tester);
        _expectUndo(tester, contains('editing'));
        fixture.folder.fault = 'before';
        await tester.tap(_undoFinder(tester));
        await waitForUi(tester, () => fixture.folder.delayedSuffix != null);
        await recoverSharedReadForTest(tester);
        await _idle(tester);
        final name = fixture.folder.delayedName!;
        final reserved = List<int>.of(fixture.folder.delayedSuffix!);
        final packets = _decodeRecords(reserved);
        expect(packets, hasLength(1));
        expect(packets.single.operation.action, FoodAction.undo);
        expect(_snapshot(tester), edited);
        expect(
          _undoButton(tester).onPressed,
          isNull,
          reason: 'An uncertain inverse cannot pop or admit another action',
        );
        final bytes = await _records(fixture.folder.delegate);
        final beforeRetry = fixture.folder.appends;
        await captureNativeFixtureUi(tester, 'food-undo-pending-inverse');
        await tester.tap(find.byKey(const ValueKey('retry-food-save')));
        await waitForUi(tester, () => _snapshot(tester) == added);
        await _idle(tester);
        final prefix = bytes[name] ?? const <int>[];
        expect(await fixture.folder.delegate.read(name), [
          ...prefix,
          ...reserved,
        ]);
        expect(fixture.folder.appends, beforeRetry + 1);
        _expectUndo(tester, contains('adding'));
        final confirmed = await _records(fixture.folder.delegate);
        await _refreshFood(tester);
        expect(await _records(fixture.folder.delegate), confirmed);
        await _undo(tester, () => _snapshot(tester) == baseline);
        final records = await _foodRecords(fixture.folder.delegate);
        expect(
          records.where((record) => record.id == packets.single.id),
          hasLength(1),
        );
        expect(records.map((e) => e.id).toSet().length, records.length);
        expect(_undoButton(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

FoodState _state(WidgetTester tester) =>
    tester.widget<FoodInventoryPage>(find.byType(FoodInventoryPage)).state;
List<FoodContainer> _named(WidgetTester tester, String name) =>
    _state(tester).containers.where((e) => e.details.name == name).toList();
String _snapshot(WidgetTester tester) {
  final rows = _state(tester).containers.toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode([
    for (final item in rows)
      {
        'id': item.id,
        'details': item.details.toJson(),
        'contents': item.contents.toJson(),
        'createdAt': item.createdAt,
        'deleted': item.deleted,
        'conflict': item.contentsConflict,
      },
  ]);
}

Finder _undoFinder(WidgetTester tester) {
  final keyed = find.byKey(const ValueKey('undo-food-action'));
  if (keyed.evaluate().isNotEmpty) return keyed;
  // Baseline fallback proves that Add cannot be undone, independently of the
  // future accessibility key. GREEN must use the permanent toolbar key.
  return find.ancestor(
    of: find.descendant(
      of: find.byType(FoodInventoryPage),
      matching: find.byIcon(Icons.undo),
    ),
    matching: find.byType(IconButton),
  );
}

({VoidCallback? onPressed, String? tooltip}) _undoButton(WidgetTester tester) =>
    toolbarButton(tester, _undoFinder(tester));
void _expectUndo(WidgetTester tester, Matcher label) {
  final button = _undoButton(tester);
  expect(
    button.onPressed,
    isNotNull,
    reason: 'Every confirmed Food command must retain a session Undo action',
  );
  expect(button.tooltip, label);
  expect(tester.getSize(_undoFinder(tester)).height, greaterThanOrEqualTo(48));
}

Future<void> _undo(WidgetTester tester, bool Function() ready) async {
  expect(_undoButton(tester).onPressed, isNotNull);
  await pixels.tap(tester, _undoFinder(tester));
  await waitForUi(tester, ready);
  await _idle(tester);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await pixels.tap(tester, target);
  await tester.pumpAndSettle();
}

Future<void> _idle(WidgetTester tester) async {
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  await waitForUi(tester, () => host.busy == false && host.syncing == null);
}

Future<void> _openAdd(WidgetTester tester, String name, {int count = 1}) async {
  await _tap(tester, find.byTooltip('Add food'));
  for (final entry in {
    'Food name': name,
    'Expiration': '2027-06-01',
    'Containers to add': '$count',
  }.entries) {
    await tester.enterText(
      find.widgetWithText(TextField, entry.key),
      entry.value,
    );
  }
}

Future<void> _add(WidgetTester tester, String name, {int count = 1}) async {
  await _openAdd(tester, name, count: count);
  await pixels.tap(tester, find.widgetWithText(FilledButton, 'Add'));
  await waitForUi(
    tester,
    () =>
        _named(tester, name).length == count &&
        find.widgetWithText(TextField, 'Food name').evaluate().isEmpty,
  );
  await _idle(tester);
}

Future<void> _reachActions(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.byTooltip('Actions for $name'));
  await tester.pumpAndSettle();
}

Future<void> _edit(
  WidgetTester tester,
  String name,
  Map<String, String> fields,
) async {
  await _reachActions(tester, name);
  final row = find.ancestor(
    of: find.byTooltip('Remove one $name container'),
    matching: find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('food-group:'),
    ),
  );
  expect(row, findsOneWidget, reason: 'Edit the one observed active group');
  await _tap(tester, find.descendant(of: row, matching: find.text(name)));
  for (final entry in fields.entries) {
    final field = entry.key == 'Retention reason'
        ? find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText == 'Retention reason',
          )
        : find.widgetWithText(TextField, entry.key);
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
    await tester.pumpAndSettle();
    if (entry.key == 'Retention reason') {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
  }
  await _tap(tester, find.widgetWithText(FilledButton, 'Save'));
  await _idle(tester);
}

Future<void> _account(WidgetTester tester, String label) async {
  await _tap(tester, find.byKey(const ValueKey('identity-menu')));
  await _tap(
    tester,
    find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<String> &&
          widget.child is Text &&
          (widget.child! as Text).data == label,
    ),
  );
  await _idle(tester);
}

Future<void> _changeWorkspace(
  WidgetTester tester,
  _Fixture fixture,
  String path,
) async {
  fixture.actions.selection = path;
  await _account(tester, 'Settings');
  await _tap(tester, find.text('Use a different folder'));
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  await waitForUi(
    tester,
    () => host.store.folder.location == path && host.busy == false,
  );
  if (find.byType(FoodInventoryPage).evaluate().isEmpty) {
    await switchSection(tester, food: true);
  }
  await _idle(tester);
}

Future<void> _refreshFood(WidgetTester tester) async {
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  await tester.runAsync(() async => host.foodStore.refresh());
  // The production refresh importer publishes its newly admitted projection.
  host.importer.request();
  await waitForUi(
    tester,
    () => identical(_state(tester), host.foodStore.state),
  );
  await _idle(tester);
  await tester.pumpAndSettle();
}

List<FoodRecord> _decodeRecords(List<int> raw) => utf8
    .decode(raw)
    .split('\n')
    .where((line) => line.isNotEmpty)
    .expand(foodEffectsFromAction)
    .toList();
Future<List<FoodRecord>> _foodRecords(LocalLogFolder folder) async => [
  for (final file in await folder.list())
    if (file.name.endsWith('.applog'))
      ..._decodeRecords(await folder.read(file.name)),
];
Future<Map<String, List<int>>> _records(
  LocalLogFolder folder, {
  bool tasksOnly = false,
}) async => {
  for (final file in await folder.list())
    if (file.name.endsWith('.applog'))
      if (!tasksOnly)
        file.name: await folder.read(file.name)
      else
        for (final line in const LineSplitter().convert(
          utf8.decode(await folder.read(file.name)),
        ))
          for (final event in taskEffectsFromAction(line))
            event.id: utf8.encode(event.canonicalRaw!),
};

Future<void> _withWorkspace(
  WidgetTester tester,
  Future<void> Function(_Fixture) run,
) async {
  final root = await Directory.systemTemp.createTemp(
    'food-undo-stack-synthetic-',
  );
  final data = await Directory('${root.path}/data').create();
  final other = await Directory('${root.path}/other').create();
  final profile = await Directory('${root.path}/profile').create();
  final folder = _FoodFaultFolder(LocalLogFolder(data.path));
  final actions = TestFolders();
  final alex = const Uuid().v4(),
      blair = const Uuid().v4(),
      task = const Uuid().v4();
  final seed = await openNativeFixtureStore(
    folder.delegate,
    '${root.path}/seed',
  );
  await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
  await seed.command(blair, 'user.created', {'name': 'Synthetic Blair'});
  await seed.createNativeFixtureTask(task, {
    'title': 'Synthetic Alex task',
    'description': '',
    'assignee': alex,
  });
  await seed.createNativeFixtureTask(const Uuid().v4(), {
    'title': 'Synthetic Blair task',
    'description': '',
    'assignee': blair,
  });
  await seed.close();
  final second = await openNativeFixtureStore(
    LocalLogFolder(other.path),
    '${root.path}/other-seed',
  );
  await second.command(alex, 'user.created', {'name': 'Synthetic Alex'});
  await second.command(blair, 'user.created', {'name': 'Synthetic Blair'});
  await second.createNativeFixtureTask(const Uuid().v4(), {
    'title': 'Synthetic other workspace task',
    'description': '',
    'assignee': alex,
  });
  await second.close();
  final peerProfile = await LocalProfileDatabase.open(
    '${root.path}/peer-profile',
  );
  final peerTasks = await TaskStore.open(
    folder.delegate,
    peerProfile.root,
    profileDatabase: peerProfile,
    writerIdentity: const Uuid().v4(),
    textEngine: seed.textEngine,
  );
  final peer = await FoodStore.openUnified(peerTasks.unified!);
  await peer.add(
    const FoodDetails(
      name: 'Synthetic baseline beans',
      expiry: '2027-06-01',
      brand: 'Seed brand',
      estimated: null,
    ),
    1,
  );
  await seedNativeProfile(profile.path, {
    'folder': data.path,
    'user': alex,
    'appearance': 'dark',
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 850);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: profile.path,
        folderActions: actions,
        folderFactory: (location) =>
            location == folder.location ? folder : LocalLogFolder(location),
      ),
    );
    await waitForUi(
      tester,
      () => find.text('Synthetic Alex task').evaluate().isNotEmpty,
    );
    await switchSection(tester, food: true);
    await _idle(tester);
    await captureNativeFixtureUi(tester, 'food-undo-warmup-not-evidence');
    await run(_Fixture(folder, peer, actions, task, other.path));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await peer.close();
    await peerTasks.close();
    await peerProfile.close();
    await root.delete(recursive: true);
  }
}

class _Fixture {
  const _Fixture(
    this.folder,
    this.peer,
    this.actions,
    this.task,
    this.otherFolder,
  );
  final _FoodFaultFolder folder;
  final FoodStore peer;
  final TestFolders actions;
  final String task, otherFolder;
}

class _FoodFaultFolder extends CountingFolder {
  _FoodFaultFolder(super.delegate);
}
