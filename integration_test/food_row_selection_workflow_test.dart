import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import '../test/support/toolbar_button.dart';
import 'food_preview_workflow_test.dart' as pixels;
import 'food_production_workflow_test.dart' show switchSection;
import 'native_text_fixtures.dart';
import 'profile_fixture.dart';
import 'task_flow_test.dart' show TestFolders, waitForUi;

const _beans = FoodDetails(
  name: 'Synthetic row beans',
  expiry: '2027-06-01',
  location: 'Pantry',
  estimated: null,
);
const _rice = FoodDetails(
  name: 'Synthetic row rice',
  expiry: '2027-06-02',
  location: 'Pantry',
  estimated: null,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final (width, scale) in [(1200.0, 1.0), (390.0, 2.0)]) {
    testWidgets('Next release Activity and Move some $width $scale dark', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _withWorkspace(tester, Size(width, 850), 'dark', (peer) async {
        final prefix = 'next-${width.round()}-${scale.round()}x-dark';
        Future<Map<String, String>> bytes() async => {
          for (final entry in await peer.folder.list())
            entry.name: base64Encode(await peer.folder.read(entry.name)),
        };
        final before = await bytes();
        await pixels.tap(tester, find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await pixels.tap(tester, find.text('Activity log'));
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, '$prefix-activity');
        final list = find.byKey(const ValueKey('activity-list'));
        expect(list, findsOneWidget);
        final count = tester
            .widget<ListView>(list)
            .childrenDelegate
            .estimatedChildCount!;
        expect(await bytes(), before);
        await tester.runAsync(
          () => peer.unified!.renameDevice('Synthetic receipt agent'),
        );
        await _refreshFood(tester);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ListView>(list).childrenDelegate.estimatedChildCount,
          count + 1,
        );
        expect(find.textContaining('Synthetic receipt agent'), findsWidgets);
        await pixels.tap(
          tester,
          find.descendant(of: list, matching: find.byType(ListTile)).first,
        );
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, '$prefix-activity-details');
        expect(find.textContaining('User: Not recorded'), findsOneWidget);
        await pixels.tap(tester, find.widgetWithText(TextButton, 'Close').last);
        await tester.pumpAndSettle();
        await pixels.tap(tester, find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        final page = tester.state<FoodInventoryPageState>(
          find.byType(FoodInventoryPage),
        );
        expect(page.bulkSelected, isEmpty);
        final row = find.text('Synthetic row beans').first;
        await tester.longPress(row);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await pixels.tap(
          tester,
          find.byTooltip('Actions for Synthetic row beans').first,
        );
        await tester.pumpAndSettle();
        await pixels.tap(tester, find.text('Move some…'));
        await tester.pumpAndSettle();
        final location = find.descendant(
          of: find.byKey(const ValueKey('food-move-location')),
          matching: find.byType(TextField),
        );
        if (scale == 2) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(location);
        await pixels.tap(tester, location);
        await tester.enterText(location, 'New freezer');
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, '$prefix-move-keyboard');
        expect(
          find.widgetWithText(FilledButton, 'Move').hitTestable(),
          findsOneWidget,
        );
        if (Platform.isLinux && scale == 1) {
          await tester.runAsync(() async {
            final key = await Process.run('xdotool', ['key', 'Return']);
            expect(key.exitCode, 0);
          });
        } else {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await waitForUi(
          tester,
          () => find.byKey(const ValueKey('food-move-some')).evaluate().isEmpty,
        );
        await _idle(tester);
        expect(find.text('New freezer'), findsWidgets);
        await captureNativeFixtureUi(tester, '$prefix-moved');
      });
    });
  }
  for (final (width, height) in [(1200.0, 850.0), (390.0, 844.0)]) {
    for (final appearance in ['dark', 'light']) {
      testWidgets(
        'Food row selection and Move some ${width.round()} $appearance',
        (tester) => _withWorkspace(
          tester,
          Size(width, height),
          appearance,
          (peer) => _workflow(
            tester,
            peer,
            '${width.round()}-$appearance',
            wide: width >= 900,
          ),
        ),
      );
    }
  }
}

Future<void> _workflow(
  WidgetTester tester,
  FoodStore peer,
  String prefix, {
  required bool wide,
}) async {
  Future<void> shot(String name) =>
      captureNativeFixtureUi(tester, '$prefix-$name');
  FoodInventoryPageState page() =>
      tester.state<FoodInventoryPageState>(find.byType(FoodInventoryPage));
  Finder row(String name) => find.text(name).first;
  Future<void> ctrlTap(String name) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await pixels.tap(tester, row(name));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await pixels.tap(tester, target);
    await tester.pumpAndSettle();
  }

  void expectCount(int containers) {
    expect(page().bulkSelected, hasLength(containers));
    expect(
      find.text(wide ? 'Edit $containers containers' : '$containers selected'),
      findsOneWidget,
    );
  }

  await shot('01-list');
  final before = tester.getTopLeft(row('Synthetic row beans'));
  await ctrlTap('Synthetic row beans');
  expectCount(3);
  // Selection is the row highlight: no checkbox, no shifted row content.
  expect(
    find.descendant(
      of: find.byType(ListRowSurface),
      matching: find.byType(Checkbox),
    ),
    findsNothing,
  );
  expect(tester.getTopLeft(row('Synthetic row beans')), before);
  await shot('02-row-selected');

  // A peer's container arrives in the selected row and joins the selection.
  await tester.runAsync(() async {
    await peer.refresh();
    await peer.add(_beans, 1);
  });
  await _refreshFood(tester);
  expectCount(4);
  await shot('03-arrival-joined');

  await ctrlTap('Synthetic row rice');
  expectCount(5);
  await shot('04-two-rows');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(page().selecting, isFalse);
  expect(page().bulkSelected, isEmpty);

  await tap(find.byTooltip('Actions for Synthetic row beans'));
  expect(find.text('Move some…'), findsOneWidget);
  await shot('05-row-menu');
  await tap(find.text('Move some…'));
  await shot('06-move-dialog');
  final count = find.byKey(const ValueKey('food-move-count'));
  final location = find.descendant(
    of: find.byKey(const ValueKey('food-move-location')),
    matching: find.byType(TextField),
  );
  await tester.enterText(location, 'Pantry');
  await tester.enterText(count, '9');
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, 'Move'));
  expect(find.text('Enter 1 to 4.'), findsOneWidget);
  expect(find.text('Choose a different location.'), findsOneWidget);
  await shot('07-move-errors');
  await tester.enterText(location, 'Freezer');
  await tester.enterText(count, '2');
  await tester.pumpAndSettle();
  await tap(find.widgetWithText(FilledButton, 'Move'));
  await _idle(tester);
  await tester.pumpAndSettle();
  final groups = page().widget.state
      .view(FoodView.inventory)
      .where((g) => g.details.name == _beans.name)
      .toList();
  expect(
    {for (final g in groups) g.details.location: g.containers.length},
    {'Pantry': 2, 'Freezer': 2},
  );
  final undo = find.byKey(const ValueKey('undo-food-action'));
  expect(toolbarButton(tester, undo).tooltip, 'Undo editing 2 containers');
  await shot('08-moved');

  await tap(undo);
  await _idle(tester);
  await waitForUi(
    tester,
    () =>
        page().widget.state
            .view(FoodView.inventory)
            .where((g) => g.details.name == _beans.name)
            .map((g) => g.containers.length)
            .join(',') ==
        '4',
  );
  await tester.pumpAndSettle();
  await shot('09-undone');
}

Future<void> _withWorkspace(
  WidgetTester tester,
  Size size,
  String appearance,
  Future<void> Function(FoodStore peer) run,
) async {
  final root = await Directory.systemTemp.createTemp(
    'food-row-selection-synthetic-',
  );
  final data = await Directory('${root.path}/data').create();
  final profile = await Directory('${root.path}/profile').create();
  final folder = LocalLogFolder(data.path);
  final alex = const Uuid().v4();
  final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
  await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
  await seed.createNativeFixtureTask(const Uuid().v4(), {
    'title': 'Synthetic Alex task',
    'description': '',
    'assignee': alex,
  });
  await seed.close();
  final peerProfile = await LocalProfileDatabase.open(
    '${root.path}/peer-profile',
  );
  final peerTasks = await TaskStore.open(
    folder,
    peerProfile.root,
    profileDatabase: peerProfile,
    writerIdentity: const Uuid().v4(),
    textEngine: seed.textEngine,
  );
  final peer = await FoodStore.openUnified(peerTasks.unified!);
  await peer.add(_beans, 3);
  await peer.add(_rice, 1);
  await seedNativeProfile(profile.path, {
    'folder': data.path,
    'user': alex,
    'appearance': appearance,
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  try {
    await tester.pumpWidget(
      TandemlogApp(profilePath: profile.path, folderActions: TestFolders()),
    );
    await waitForUi(
      tester,
      () => find.text('Synthetic Alex task').evaluate().isNotEmpty,
    );
    await switchSection(tester, food: true);
    await _idle(tester);
    await waitForUi(
      tester,
      () => find.text('Synthetic row beans').evaluate().isNotEmpty,
    );
    await captureNativeFixtureUi(tester, 'food-row-warmup-not-evidence');
    await run(peer);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await peer.close();
    await peerTasks.close();
    await peerProfile.close();
    await root.delete(recursive: true);
  }
}

Future<void> _idle(WidgetTester tester) async {
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  await waitForUi(tester, () => host.busy == false && host.syncing == null);
}

Future<void> _refreshFood(WidgetTester tester) async {
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  await tester.runAsync(() async => host.foodStore.refresh());
  // The production refresh importer publishes its newly admitted projection.
  host.importer.request();
  await waitForUi(
    tester,
    () => identical(
      tester
          .state<FoodInventoryPageState>(find.byType(FoodInventoryPage))
          .widget
          .state,
      host.foodStore.state,
    ),
  );
  await _idle(tester);
  await tester.pumpAndSettle();
}
