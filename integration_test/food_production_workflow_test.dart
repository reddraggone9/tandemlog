import 'package:tandemlog/domain/event.dart' show FormatFailure;
import 'package:tandemlog/food/food_store.dart';
import 'profile_fixture.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;
import 'food_preview_workflow_test.dart' as pixels;
import '../test/food_expiry_guidance_test.dart' show selectFoodView;

class _HeldFoodManifestFolder implements LogFolder, BoundedLogFolder {
  _HeldFoodManifestFolder(this.inner);
  final LocalLogFolder inner;
  bool pause = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) async {
    if (pause && name == 'tandemlog-space.json') {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return inner.readBounded(name, maximumBytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodProductionTests();
}

Future<void> switchSection(WidgetTester tester, {required bool food}) async {
  await pixels.tap(tester, find.byKey(const ValueKey('section-menu')));
  await tester.pumpAndSettle();
  await pixels.tap(
    tester,
    find.byKey(ValueKey(food ? 'module-food' : 'module-tasks')),
  );
  await tester.pumpAndSettle();
}

void registerFoodProductionTests() {
  testWidgets(
    'queued task capture cannot append after reconciliation discovers shared authority loss',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'food-shared-stop-native-',
      );
      final data = await Directory('${root.path}/data').create(),
          private = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4(), task = const Uuid().v4();
      final seed = await openNativeFixtureStore(
        LocalLogFolder(data.path),
        '${root.path}/seed',
      );
      await seed.command(user, 'user.created', {'name': 'Synthetic household'});
      await seed.createNativeFixtureTask(task, {
        'title': 'Preserved synthetic task',
        'description': '',
        'assignee': user,
      });
      await seed.close();
      await seedNativeProfile(private.path, {
        'folder': data.path,
        'user': user,
        'appearance': 'dark',
      });
      final gate = _HeldFoodManifestFolder(LocalLogFolder(data.path));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<Map<String, List<int>>> taskBytes() async => {
        for (final file
            in await data
                .list()
                .where((e) => e.path.endsWith('.applog'))
                .cast<File>()
                .toList())
          file.path: await file.readAsBytes(),
      };
      try {
        await tester.pumpWidget(
          TandemlogApp(profilePath: private.path, folderFactory: (_) => gate),
        );
        await flows.waitForUi(
          tester,
          () => find.text('Preserved synthetic task').evaluate().isNotEmpty,
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await flows.waitForUi(
          tester,
          () => state.syncing == null && state.busy == false,
        );
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'What needs doing?'),
          'Must not append',
        );
        final before = await taskBytes();
        gate.pause = true;
        state.importer.request();
        await flows.waitForUi(tester, () => gate.entered.isCompleted);
        await tester.tap(find.byTooltip('Add tasks'));
        await tester.pump();
        expect(state.busy, true);
        state.profileDatabase.database.execute(
          'DELETE FROM protected_app_heads WHERE space=? AND writer=?',
          [state.store.space, state.settings.writer],
        );
        gate.release.complete();
        await flows.waitForUi(
          tester,
          () =>
              find.text('Workspace requires recovery').evaluate().isNotEmpty &&
              state.busy == false,
        );
        expect(await taskBytes(), before);
        expect(find.byTooltip('Add tasks').hitTestable(), findsNothing);
        await tester.tap(find.byKey(const ValueKey('retry-shared-read')));
        await flows.waitForUi(tester, () => state.busy == false);
        expect(find.text('Workspace requires recovery'), findsOneWidget);
        expect(await taskBytes(), before);
        expect(find.byTooltip('Add tasks').hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await root.delete(recursive: true);
      }
    },
  );

  for (final loseGuard in [true, false]) {
    testWidgets(
      loseGuard
          ? 'shared recovery retains private task editor draft and rejects a retained Save'
          : 'restored exact manifest resumes the same draft after guarded repeated Retry',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'food-draft-stop-native-',
        );
        final data = await Directory('${root.path}/data').create(),
            private = await Directory('${root.path}/profile').create();
        final user = const Uuid().v4(), task = const Uuid().v4();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/seed',
        );
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createNativeFixtureTask(task, {
          'title': 'Preserved synthetic task',
          'description': '',
          'assignee': user,
        });
        await seed.close();
        await seedNativeProfile(private.path, {
          'folder': data.path,
          'user': user,
          'appearance': 'dark',
        });
        final gate = _HeldFoodManifestFolder(LocalLogFolder(data.path));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<Map<String, List<int>>> taskBytes() async => {
          for (final file
              in await data
                  .list()
                  .where((e) => e.path.endsWith('.applog'))
                  .cast<File>()
                  .toList())
            file.path: await file.readAsBytes(),
        };
        try {
          await tester.pumpWidget(
            TandemlogApp(profilePath: private.path, folderFactory: (_) => gate),
          );
          await flows.waitForUi(
            tester,
            () => find.text('Preserved synthetic task').evaluate().isNotEmpty,
          );
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          await flows.waitForUi(
            tester,
            () => state.syncing == null && state.busy == false,
          );
          await tester.tap(find.text('Preserved synthetic task'));
          await tester.pumpAndSettle();
          final editor = tester.widget<TaskEditor>(find.byType(TaskEditor));
          await tester.enterText(
            find.byKey(const ValueKey('title')),
            'Unsubmitted title',
          );
          await tester.enterText(
            find.byKey(const ValueKey('dueDate')),
            '2026-10-21',
          );
          final titleController = tester
              .widget<TextField>(find.byKey(const ValueKey('title')))
              .controller!;
          final dateController = tester
              .widget<TextField>(find.byKey(const ValueKey('dueDate')))
              .controller!;
          final before = await taskBytes();
          gate.pause = true;
          state.importer.request();
          await flows.waitForUi(tester, () => gate.entered.isCompleted);
          File? movedManifest;
          final manifest = File('${data.path}/tandemlog-space.json');
          if (loseGuard) {
            state.profileDatabase.database.execute(
              'DELETE FROM protected_app_heads WHERE space=? AND writer=?',
              [state.store.space, state.settings.writer],
            );
          } else {
            movedManifest = await manifest.rename(
              '${root.path}/manifest-backup.json',
            );
          }
          gate.release.complete();
          await flows.waitForUi(
            tester,
            () =>
                find
                    .text('Workspace requires recovery')
                    .evaluate()
                    .isNotEmpty &&
                state.busy == false,
          );
          expect(await taskBytes(), before);
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('title')))
                .controller,
            same(titleController),
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                .controller,
            same(dateController),
          );
          expect(titleController.text, 'Unsubmitted title');
          expect(dateController.text, '2026-10-21');
          await expectLater(
            editor.save({'title': 'Attempt after stop'}, [], []),
            throwsStateError,
          );
          expect(await taskBytes(), before);
          if (!loseGuard) {
            tester.view.physicalSize = const Size(390, 800);
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpAndSettle();
            await pixels.capture(tester, 'shared-recovery-warmup-not-evidence');
            await pixels.capture(
              tester,
              'production-narrow-shared-recovery-2x',
            );
          }
          final retryFinder = find.byKey(const ValueKey('retry-shared-read'));
          expect(retryFinder.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(retryFinder).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          await tester.tap(retryFinder);
          await flows.waitForUi(tester, () => state.busy == false);
          expect(find.text('Workspace requires recovery'), findsOneWidget);
          expect(await taskBytes(), before);
          if (!loseGuard) {
            await movedManifest!.rename(manifest.path);
            final retry = tester.widget<TextButton>(retryFinder).onPressed!;
            retry();
            retry(); // Second invocation must coalesce while the first is busy.
            await flows.waitForUi(
              tester,
              () => state.busy == false && state.sharedSafetyError == null,
            );
            expect(await taskBytes(), before);
            expect(
              tester
                  .widget<TextField>(find.byKey(const ValueKey('title')))
                  .controller,
              same(titleController),
            );
            expect(
              tester
                  .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                  .controller,
              same(dateController),
            );
            expect(titleController.text, 'Unsubmitted title');
            expect(dateController.text, '2026-10-21');
            tester.view.physicalSize = const Size(1200, 850);
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            await tester.pumpAndSettle();
            final save = find.text('Save changes');
            await tester.ensureVisible(save);
            await tester.tap(save);
            await flows.waitForUi(
              tester,
              () => find.byType(TaskEditor).evaluate().isEmpty,
            );
            expect(find.text('Unsubmitted title'), findsOneWidget);
            expect(await taskBytes(), isNot(before));
          }
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.release.isCompleted) gate.release.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await root.delete(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'unknown complete shared record blocks both modules and preserves their last views',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'shared-corruption-native-',
      );
      final data = await Directory('${root.path}/data').create();
      final profile = await Directory('${root.path}/profile').create();
      final folder = LocalLogFolder(data.path);
      final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
      final user = const Uuid().v4(), task = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Synthetic household'});
      await seed.createNativeFixtureTask(task, {
        'title': 'Preserved synthetic task',
        'description': '',
        'assignee': user,
      });
      final food = await FoodStore.openUnified(seed.unified!);
      await food.add(
        const FoodDetails(
          name: 'Preserved synthetic rice',
          expiry: '2026-11-03',
        ),
        1,
      );
      await food.close();
      await seed.close();
      await seedNativeProfile(profile.path, {
        'folder': data.path,
        'user': user,
      });
      final malformed = File(
        '${data.path}/00000000-0000-4000-8000-000000000010.applog',
      );
      try {
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.text('Preserved synthetic task').evaluate().isNotEmpty,
        );
        final host = tester.state(find.byType(TasksPage)) as dynamic;
        final before = {
          for (final file in await folder.list())
            file.name: await folder.read(file.name),
        };
        await malformed.writeAsString('{"v":99}\n', flush: true);
        host.importer.request();
        await flows.waitForUi(tester, () => host.sharedSafetyError != null);
        expect(find.text('Preserved synthetic task'), findsOneWidget);
        await expectLater(
          host.store.edit(
            task,
            {'assignee': user},
            tags: <String>[],
            observedTagRefs: <String, String>{},
          ),
          throwsA(isA<FormatFailure>()),
        );
        await expectLater(
          host.foodStore.add(
            const FoodDetails(name: 'Must not append', expiry: '2026-11-03'),
            1,
          ),
          throwsA(isA<FormatFailure>()),
        );
        for (final entry in before.entries) {
          expect(await folder.read(entry.key), entry.value);
        }
        expect(await malformed.readAsString(), '{"v":99}\n');
        await malformed.delete();
        await flows.recoverSharedReadForTest(tester);
        expect(host.sharedSafetyError, isNull);
        expect(host.busy, isFalse);
        await switchSection(tester, food: true);
        expect(find.text('Preserved synthetic rice'), findsOneWidget);
        await switchSection(tester, food: false);
        expect(find.text('Preserved synthetic task'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'production Food navigation persists Deleted and restores after restart',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'food-production-native-',
      );
      final data = await Directory('${root.path}/data').create(),
          private = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4(), task = const Uuid().v4();
      final seed = await openNativeFixtureStore(
        LocalLogFolder(data.path),
        '${root.path}/seed',
      );
      await seed.command(user, 'user.created', {'name': 'Synthetic household'});
      await seed.createNativeFixtureTask(task, {
        'title': 'Preserved synthetic task',
        'description': '',
        'assignee': user,
      });
      await seed.close();
      await seedNativeProfile(private.path, {
        'folder': data.path,
        'user': user,
        'appearance': 'dark',
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(TandemlogApp(profilePath: private.path));
        await flows.waitForUi(
          tester,
          () => find.text('Preserved synthetic task').evaluate().isNotEmpty,
        );
        await switchSection(tester, food: true);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Switch section (current: Food)'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Add food'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Food name'),
          'Synthetic Rice',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Expiration'),
          '2026-10-15',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Containers to add'),
          '2',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await flows.waitForUi(
          tester,
          () => find.text('2 containers').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        await pixels.capture(tester, 'production-wide-warmup-not-evidence');
        await pixels.capture(tester, 'production-wide-stock');
        tester.view.physicalSize = const Size(390, 850);
        await tester.pumpAndSettle();
        await pixels.capture(tester, 'production-narrow-stock');
        await tester.tap(find.byTooltip('Remove one Synthetic Rice container'));
        await flows.waitForUi(
          tester,
          () =>
              tester
                  .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
                  .state
                  .active
                  .length ==
              1,
        );
        expect(find.text('1 full'), findsNothing);
        expect(find.text('Full'), findsNothing);
        expect(find.byTooltip('Actions for Synthetic Rice'), findsOneWidget);
        await selectFoodView(tester, FoodView.deleted);
        await tester.pumpAndSettle();
        expect(find.text('Synthetic Rice'), findsOneWidget);
        await pixels.tap(tester, find.byKey(const ValueKey('food-search')));
        await tester.enterText(
          find.byKey(const ValueKey('food-search')),
          'Synthetic Rice',
        );
        await tester.pumpAndSettle();
        FoodState currentFood() => tester
            .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
            .state;
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsNWidgets(2),
        );
        expect(
          find.byKey(const ValueKey('food-deleted-heading')),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Remove one Synthetic Rice container'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Restore one Synthetic Rice container'),
          findsOneWidget,
        );
        await pixels.capture(tester, 'production-all-food-search-separated');
        await pixels.tap(
          tester,
          find.byTooltip('Restore one Synthetic Rice container'),
        );
        await flows.waitForUi(tester, () => currentFood().active.length == 2);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('food-deleted-heading')),
          findsNothing,
        );
        await pixels.tap(
          tester,
          find.byKey(const ValueKey('undo-food-action')),
        );
        await flows.waitForUi(tester, () => currentFood().deleted.length == 1);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsNWidgets(2),
        );
        await pixels.tap(
          tester,
          find.byTooltip('Remove one Synthetic Rice container'),
        );
        await flows.waitForUi(tester, () => currentFood().active.isEmpty);
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Remove one Synthetic Rice container'),
          findsNothing,
        );
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsOneWidget,
        );
        await pixels.tap(
          tester,
          find.byKey(const ValueKey('undo-food-action')),
        );
        await flows.waitForUi(tester, () => currentFood().active.length == 1);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsNWidgets(2),
        );
        await pixels.capture(tester, 'production-all-food-search-after-undo');
        await pixels.tap(tester, find.byTooltip('Clear food search'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ListRowSurface, 'Synthetic Rice'),
          findsOneWidget,
          reason: 'clearing restores saved Deleted view',
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final owner = state.profileDatabase, oldFood = state.foodStore;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await oldFood.close();
          await owner.close();
        });
        await tester.pumpWidget(TandemlogApp(profilePath: private.path));
        await flows.waitForUi(
          tester,
          () => find.text('Preserved synthetic task').evaluate().isNotEmpty,
        );
        await switchSection(tester, food: true);
        await tester.pumpAndSettle();
        await selectFoodView(tester, FoodView.deleted);
        await tester.pumpAndSettle();
        expect(find.text('Synthetic Rice'), findsOneWidget);
        await tester.tap(
          find.byTooltip('Restore one Synthetic Rice container'),
        );
        await flows.waitForUi(
          tester,
          () => find.text('No deleted containers').evaluate().isNotEmpty,
        );
        await selectFoodView(tester, FoodView.inventory);
        await tester.pumpAndSettle();
        expect(find.text('2 containers'), findsOneWidget);
        await switchSection(tester, food: false);
        await tester.pumpAndSettle();
        expect(find.text('Preserved synthetic task'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await root.delete(recursive: true);
      }
    },
  );
}
