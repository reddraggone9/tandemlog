import 'package:tandemlog/food/food_store.dart';
import 'profile_fixture.dart';
import '../test/support/toolbar_button.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import '../test/batch_storage_test.dart' show CountingFolder;
import '../test/food_expiry_guidance_test.dart' show selectFoodView;
import 'food_production_workflow_test.dart' show switchSection;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart'
    show readProfileSettings, waitForUi, recoverSharedReadForTest;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodAccountWorkflowTests();
}

void registerFoodAccountWorkflowTests() {
  testWidgets(
    'Task completion snackbar and its retained Undo cannot affect Tasks from Food',
    (tester) async {
      await _withWorkspace(tester, Brightness.dark, (fixture) async {
        await switchSection(tester, food: false);
        final host = tester.state(find.byType(TasksPage)) as dynamic;
        final task =
            (host.rows as Iterable).singleWhere(
                  (row) => row['title'] == 'Synthetic Alex task',
                )['id']
                as String;
        await tester.enterText(
          find.byKey(const ValueKey('task-search')),
          'Synthetic Alex task',
        );
        await tester.pumpAndSettle();
        final checkbox = find.descendant(
          of: find.byKey(ValueKey('task-row-$task')),
          matching: find.byType(Checkbox),
        );
        await tester.tap(checkbox);
        await waitForUi(
          tester,
          () => find.text('Completed 1 task.').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(checkbox).value, true);
        final action = tester.widget<SnackBarAction>(
          find.byType(SnackBarAction),
        );
        expect(action.label, 'Undo');
        final completedBytes = await _records(fixture.folder.delegate);
        final appendCount = fixture.folder.appends;
        await switchSection(tester, food: true);
        final noticeRemains = find.byType(SnackBar).evaluate().isNotEmpty;
        expect(await _records(fixture.folder.delegate), completedBytes);
        await captureNativeFixtureUi(tester, 'food-task-snackbar-crossover');

        // Retain the actual callback before removing its widget. A callback
        // from the old section must also be rejected after the section changes.
        action.onPressed();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        await waitForUi(tester, () => host.busy == false);
        final after = await _records(fixture.folder.delegate);
        final recordChanged = !_sameBytes(after, completedBytes);
        final appendedTypes = <String>[
          for (final entry in after.entries)
            if (entry.key.endsWith('.applog') &&
                entry.value.length > (completedBytes[entry.key]?.length ?? 0))
              for (final line
                  in utf8
                      .decode(
                        entry.value.sublist(
                          completedBytes[entry.key]?.length ?? 0,
                        ),
                      )
                      .split('\n')
                      .where((line) => line.isNotEmpty))
                ...taskEffectsFromAction(line).map((event) => event.type),
        ];
        final completed =
            (host.rows as Iterable).singleWhere(
                  (row) => row['id'] == task,
                )['completed']
                as bool;
        debugPrint(
          'TASK_FOOD_SNACKBAR_PROBE noticeRemains=$noticeRemains '
          'canonicalChanged=$recordChanged '
          'additionalAppends=${fixture.folder.appends - appendCount} '
          'taskCompleted=$completed appendedTypes=$appendedTypes',
        );
        expect(
          {
            'noticeRemains': noticeRemains,
            'canonicalChanged': recordChanged,
            'additionalAppends': fixture.folder.appends - appendCount,
            'taskCompleted': completed,
          },
          {
            'noticeRemains': false,
            'canonicalChanged': false,
            'additionalAppends': 0,
            'taskCompleted': true,
          },
        );
        expect(find.byType(FoodInventoryPage), findsOneWidget);
        // Hiding a section's notice must keep its ordinary session Undo usable
        // when the user returns to that section.
        await switchSection(tester, food: false);
        final undo = find.byKey(const ValueKey('undo-task-action'));
        expect(toolbarButton(tester, undo).onPressed, isNotNull);
        await tester.tap(undo);
        await waitForUi(
          tester,
          () => tester.widget<Checkbox>(checkbox).value == false,
        );
        expect(fixture.folder.appends, appendCount + 1);
        expect(tester.takeException(), isNull);
      });
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'Food ${brightness.name} account retains view/query/reasons and Settings; Manage users returns to Tasks',
      (tester) async {
        await _withWorkspace(
          tester,
          brightness,
          (fixture) async {
            final page = tester.state<FoodInventoryPageState>(
              find.byType(FoodInventoryPage),
            );
            final before = await _records(fixture.folder.delegate);
            await selectFoodView(tester, FoodView.retained);
            await tester.tap(find.byKey(const ValueKey('food-filter')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('More filters…'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Show retention reasons'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('tag-option-Freezer')));
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
            await tester.pumpAndSettle();
            expect(page.reasons, {'Freezer'});
            await tester.enterText(
              find.byKey(const ValueKey('food-search')),
              'Synthetic',
            );
            await tester.pumpAndSettle();
            await _chooseAccount(tester, 'Synthetic Blair');
            expect(readProfileSettings(tester)['user'], fixture.blair);
            expect(
              find.byTooltip('Active user: Synthetic Blair'),
              findsOneWidget,
            );
            expect(find.byType(FoodInventoryPage), findsOneWidget);
            expect(
              tester.state<FoodInventoryPageState>(
                find.byType(FoodInventoryPage),
              ),
              same(page),
            );
            expect(page.view, FoodView.retained);
            expect(page.reasons, {'Freezer'});
            expect(page.search.text, 'Synthetic');
            expect(find.text('Synthetic retained peas'), findsOneWidget);
            expect(find.text('Synthetic stock rice'), findsOneWidget);
            expect(await _records(fixture.folder.delegate), before);

            await tester.tap(find.byKey(const ValueKey('identity-menu')));
            await tester.pumpAndSettle();
            final entries = tester
                .widgetList<PopupMenuEntry<String>>(
                  find.byWidgetPredicate(
                    (widget) => widget is PopupMenuEntry<String>,
                  ),
                )
                .toList();
            expect((entries.last as PopupMenuItem<String>).value, 'settings');
            await tester.tap(
              find.widgetWithText(PopupMenuItem<String>, 'Settings'),
            );
            await tester.pumpAndSettle();
            expect(find.text('Settings'), findsOneWidget);
            await captureNativeFixtureUi(
              tester,
              'food-account-${brightness.name}-settings',
            );
            await tester.tap(find.widgetWithText(TextButton, 'Done'));
            await tester.pumpAndSettle();
            expect(page.view, FoodView.retained);
            expect(page.reasons, {'Freezer'});
            expect(page.search.text, 'Synthetic');
            expect(readProfileSettings(tester)['user'], fixture.blair);
            expect(await _records(fixture.folder.delegate), before);

            await _chooseAccount(tester, 'Manage users');
            final host = tester.state(find.byType(TasksPage)) as dynamic;
            await waitForUi(
              tester,
              () => host.user == null && host.busy == false,
            );
            expect(readProfileSettings(tester)['user'], isNull);
            expect(readProfileSettings(tester)['lastSection'], 'tasks');
            expect(find.byType(FoodInventoryPage), findsNothing);
            expect(find.text('Synthetic Alex'), findsOneWidget);
            expect(find.text('Synthetic Blair'), findsOneWidget);
            await captureNativeFixtureUi(
              tester,
              'food-account-${brightness.name}-manage-users',
            );
            await tester.tap(find.text('Synthetic Alex'));
            await waitForUi(
              tester,
              () =>
                  host.user == fixture.alex &&
                  host.busy == false &&
                  host.sectionWork == null,
            );
            await waitForUi(
              tester,
              () => find.text('Synthetic Alex task').evaluate().isNotEmpty,
            );
            expect(readProfileSettings(tester)['user'], fixture.alex);
            expect(readProfileSettings(tester)['lastSection'], 'tasks');
            expect(find.byType(FoodInventoryPage), findsNothing);
            expect(await _records(fixture.folder.delegate), before);
            expect(tester.takeException(), isNull);
          },
          size: brightness == Brightness.light
              ? const Size(320, 850)
              : const Size(1200, 850),
          scale: brightness == Brightness.light ? 2 : 1,
        );
      },
    );
  }

  testWidgets(
    'Food account switching respects Keep editing and Discard without writes',
    (tester) async {
      await _withWorkspace(tester, Brightness.dark, (fixture) async {
        final before = await _records(fixture.folder.delegate);
        await tester.tap(find.byTooltip('Add food'));
        await tester.pumpAndSettle();
        final name = find.widgetWithText(TextField, 'Food name');
        await tester.enterText(name, 'Unsaved synthetic food');
        await tester.enterText(
          find.widgetWithText(TextField, 'Expiration'),
          '2026-11-03',
        );
        final controller = tester.widget<TextField>(name).controller!;
        // A Food modal owns input. Invoke the actual host menu callback; this
        // intentionally does not claim pointer access through the modal barrier.
        _accountCallback(tester)(fixture.blair);
        await tester.pumpAndSettle();
        expect(find.text('Discard food changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(readProfileSettings(tester)['user'], fixture.alex);
        expect(tester.widget<TextField>(name).controller, same(controller));
        expect(controller.text, 'Unsaved synthetic food');
        expect(find.text('Discard food changes?'), findsNothing);
        expect(await _records(fixture.folder.delegate), before);
        await captureNativeFixtureUi(tester, 'food-account-dirty-kept');

        _accountCallback(tester)(fixture.blair);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await waitForUi(
          tester,
          () => readProfileSettings(tester)['user'] == fixture.blair,
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
        expect(find.byType(FoodInventoryPage), findsOneWidget);
        expect(find.byTooltip('Active user: Synthetic Blair'), findsOneWidget);
        expect(await _records(fixture.folder.delegate), before);
        expect(tester.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Uncertain Food save blocks account changes and Retry retains original records',
    (tester) async {
      await _withWorkspace(tester, Brightness.dark, (fixture) async {
        await tester.tap(find.byTooltip('Add food'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Food name'),
          'Synthetic pending oats',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Expiration'),
          '2026-11-03',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Containers to add'),
          '2',
        );
        fixture.folder.fault = 'before';
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await waitForUi(tester, () => fixture.folder.delayedSuffix != null);
        await recoverSharedReadForTest(tester);
        await tester.pumpAndSettle();
        final host = tester.state(find.byType(TasksPage)) as dynamic;
        final reservedName = fixture.folder.delayedName!;
        final reservedBytes = List<int>.of(fixture.folder.delayedSuffix!);
        final pendingRecords = List<FoodRecord>.from(
          host.pendingFoodCommand.records as Iterable,
        );
        final originalIds = pendingRecords.map((record) => record.id).toList();
        final originalTargets = pendingRecords
            .expand((record) => record.operation.targets)
            .toList();
        expect(originalTargets.length, 2);
        expect(originalTargets.toSet().length, 2);
        final before = await _records(fixture.folder.delegate);
        final appendCount = fixture.folder.appends;
        for (final target in [fixture.blair, 'new']) {
          _accountCallback(tester)(target);
          await tester.pumpAndSettle();
          expect(readProfileSettings(tester)['user'], fixture.alex);
          expect(find.text('Discard food changes?'), findsNothing);
          expect(find.widgetWithText(TextField, 'Food name'), findsOneWidget);
          expect(fixture.folder.delayedName, reservedName);
          expect(fixture.folder.delayedSuffix, reservedBytes);
          expect(await _records(fixture.folder.delegate), before);
        }
        expect(find.widgetWithText(FilledButton, 'Retry save'), findsOneWidget);
        expect(
          (host.pendingFoodCommand.records as Iterable<FoodRecord>)
              .map((record) => record.id)
              .toList(),
          originalIds,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Close food editor?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Close editor'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'Food name'), findsNothing);
        await _chooseAccount(tester, 'Synthetic Blair');
        expect(readProfileSettings(tester)['user'], fixture.alex);
        await _chooseAccount(tester, 'Manage users');
        expect(readProfileSettings(tester)['user'], fixture.alex);
        expect(find.byType(FoodInventoryPage), findsOneWidget);
        expect(fixture.folder.appends, appendCount);
        expect(await _records(fixture.folder.delegate), before);
        await captureNativeFixtureUi(tester, 'food-account-pending-blocked');

        await tester.tap(find.byKey(const ValueKey('retry-food-save')));
        await waitForUi(
          tester,
          () => host.pendingFoodCommand == null && host.busy == false,
        );
        await tester.pumpAndSettle();
        expect(host.foodStore.hasPreparedAppend, false);
        expect(await fixture.folder.delegate.read(reservedName), reservedBytes);
        expect(fixture.folder.appends, appendCount + 1);
        final added = tester
            .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
            .state
            .active
            .where((item) => item.details.name == 'Synthetic pending oats')
            .toList();
        expect(added.map((item) => item.id).toSet(), originalTargets.toSet());
        expect(find.text('Synthetic pending oats'), findsOneWidget);
        final confirmed = await _records(fixture.folder.delegate);
        await _chooseAccount(tester, 'Synthetic Blair');
        expect(readProfileSettings(tester)['user'], fixture.blair);
        expect(await _records(fixture.folder.delegate), confirmed);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

ValueChanged<String> _accountCallback(WidgetTester tester) => tester
    .widget<PopupMenuButton<String>>(
      find.byKey(const ValueKey('identity-menu')),
    )
    .onSelected!;

Future<void> _chooseAccount(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('identity-menu')));
  await tester.pumpAndSettle();
  final choice = find.byWidgetPredicate(
    (widget) =>
        widget is PopupMenuItem<String> &&
        widget.child is Text &&
        (widget.child! as Text).data == label,
  );
  expect(choice.hitTestable(), findsOneWidget);
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

Future<Map<String, List<int>>> _records(LocalLogFolder folder) async => {
  for (final file in await folder.list())
    if (file.name.endsWith('.applog')) file.name: await folder.read(file.name),
};

bool _sameBytes(Map<String, List<int>> left, Map<String, List<int>> right) =>
    left.length == right.length &&
    left.entries.every((entry) {
      final other = right[entry.key];
      return other != null &&
          entry.value.length == other.length &&
          List.generate(
            entry.value.length,
            (index) => index,
          ).every((index) => entry.value[index] == other[index]);
    });

Future<void> _withWorkspace(
  WidgetTester tester,
  Brightness brightness,
  Future<void> Function(_Fixture) run, {
  Size size = const Size(1200, 850),
  double scale = 1,
}) async {
  final root = await Directory.systemTemp.createTemp('food-account-synthetic-');
  final data = await Directory('${root.path}/data').create();
  final profile = await Directory('${root.path}/profile').create();
  final folder = _FoodFaultFolder(LocalLogFolder(data.path));
  final alex = const Uuid().v4(), blair = const Uuid().v4();
  final seed = await openNativeFixtureStore(
    folder.delegate,
    '${root.path}/seed',
  );
  await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
  await seed.command(blair, 'user.created', {'name': 'Synthetic Blair'});
  await seed.createNativeFixtureTask(const Uuid().v4(), {
    'title': 'Synthetic Alex task',
    'description': '',
    'assignee': alex,
  });
  await seed.createNativeFixtureTask(const Uuid().v4(), {
    'title': 'Synthetic Blair task',
    'description': '',
    'assignee': blair,
  });
  final food = await FoodStore.openUnified(seed.unified!);
  for (final details in [
    const FoodDetails(name: 'Synthetic stock rice', expiry: '2026-11-03'),
    const FoodDetails(
      name: 'Synthetic retained peas',
      expiry: '2026-11-03',
      retention: 'Freezer',
    ),
  ]) {
    await food.add(details, 1);
  }
  await food.close();
  await seed.close();
  await seedNativeProfile(profile.path, {
    'folder': data.path,
    'user': alex,
    'appearance': brightness.name,
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  try {
    await tester.pumpWidget(
      TandemlogApp(profilePath: profile.path, folderFactory: (_) => folder),
    );
    await waitForUi(
      tester,
      () => find.text('Synthetic Alex task').evaluate().isNotEmpty,
    );
    await switchSection(tester, food: true);
    expect(find.text('Synthetic stock rice'), findsOneWidget);
    await run(_Fixture(folder, alex, blair));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  }
}

class _Fixture {
  const _Fixture(this.folder, this.alex, this.blair);
  final _FoodFaultFolder folder;
  final String alex, blair;
}

// Current enrollment creates the app stream; ordinary appends use the common
// before-write fault adapter and retain exact same-session bytes.
class _FoodFaultFolder extends CountingFolder {
  _FoodFaultFolder(super.delegate);
}
