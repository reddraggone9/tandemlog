import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/presentation/workspace_upgrade.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import 'section_navigation_host_test.dart' as host;

class RevocableUpgradeFolder extends LocalLogFolder {
  RevocableUpgradeFolder(super.location);
  bool granted = true;
  int deniedReads = 0;
  void _access() {
    if (!granted) {
      deniedReads++;
      throw FileSystemException('Synthetic revoked folder grant', location);
    }
  }

  @override
  Future<List<LogFileInfo>> list() {
    _access();
    return super.list();
  }
}

class RestoreUpgradeFolderActions extends FolderActions {
  RestoreUpgradeFolderActions(this.folder);
  final RevocableUpgradeFolder folder;
  String? next;
  String? expected;
  int restores = 0;
  @override
  bool get requiresPicker => true;
  @override
  Future<String?> restoreAccess(String expectedLocation) async {
    restores++;
    expected = expectedLocation;
    if (next == expectedLocation) folder.granted = true;
    return next;
  }

  @override
  Future<String?> pick() =>
      throw StateError('Ordinary folder switch was not authorized');
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;

  Future<void> start(
    WidgetTester tester,
    String profile, {
    FolderActions? actions,
    LogFolder? folder,
  }) async {
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: profile,
        folderActions: actions,
        folderFactory: folder == null ? null : (_) => folder,
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    await host.ready(tester, () {
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      if (state.error != null) {
        throw StateError('Startup: ${state.error}');
      }
      return state.busy == false &&
          (state.store != null || state.upgradeFolder != null);
    });
  }

  Future<void> stop(WidgetTester tester) async {
    final resources = host.hostResources(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await host.waitForHostShutdown(tester, resources);
  }

  void progress(WidgetTester tester, String action) {
    final state = tester.state(find.byType(TasksPage)) as dynamic;
    final profile = state.profileDatabase as LocalProfileDatabase;
    debugPrint(
      'UPGRADE_HOST_PROBE action=$action busy=${state.busy} controller=${state.workspaceUpgrade?.phase} input=${state.workspaceUpgrade?.inputAcknowledged} output=${state.workspaceUpgrade?.outputAcknowledged} syncing=${state.syncing != null} journal=${profile.database.select('SELECT state FROM protected_app_migrations').map((row) => row['state']).toList()}',
    );
  }

  Future<void> upgradeSettled(
    WidgetTester tester,
    bool Function() condition,
    String action,
  ) async {
    // Widget FakeAsync must explicitly yield each real filesystem completion.
    // A complete durable migration or converted Undo has many such steps
    // (including native replay),
    // unlike ordinary frame readiness. This wall-clock bound is an operation
    // timeout, not a native performance measurement or a larger UI budget.
    final elapsed = Stopwatch()..start();
    while (!condition() && elapsed.elapsed < const Duration(seconds: 30)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    if (!condition()) progress(tester, action);
    expect(
      condition(),
      isTrue,
      reason: 'The complete durable operation must settle within 30 seconds',
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await host.ready(tester, () => target.evaluate().isNotEmpty);
    await tester.ensureVisible(target);
    await tester.tap(target);
    final wait = key == 'workspace-upgrade-available'
        ? (bool Function() condition) => host.ready(tester, condition)
        : (bool Function() condition) => upgradeSettled(tester, condition, key);
    await wait(() {
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      if (state.upgradeError != null) {
        final profile = state.profileDatabase as LocalProfileDatabase;
        debugPrint(
          'UPGRADE_FAILED_PROTECTED_GUARDS=${profile.database.select('SELECT space,writer,raw FROM protected_writer_guards').map((row) => row.toString()).join(';')}',
        );
        debugPrint(
          'UPGRADE_FAILED_OWNER_ROSTER=${state.workspaceUpgrade?.owners.toString() ?? 'not started'}',
        );
        throw StateError('Upgrade: ${state.upgradeError}');
      }
      return state.busy == false;
    });
  }

  Future<void> begin(WidgetTester tester, {String? otherDevice}) async {
    await press(tester, 'workspace-upgrade-available');
    await host.ready(
      tester,
      () => find.byType(WorkspaceUpgradeDialog).evaluate().isNotEmpty,
    );
    if (otherDevice != null) {
      final extra = find.byKey(const ValueKey('upgrade-extra-participants'));
      await tester.ensureVisible(extra);
      await tester.enterText(extra, otherDevice);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(extra).controller!.text, otherDevice);
    }
    final button = find.byKey(const ValueKey('begin-workspace-upgrade'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final confirmation = find.byKey(
      const ValueKey('upgrade-coordination-confirmation'),
    );
    await tester.ensureVisible(confirmation);
    await tester.tap(confirmation);
    await tester.pump();
    await press(tester, 'begin-workspace-upgrade');
    await host.ready(tester, () {
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      return state.busy == false &&
          (state.upgradeFolder != null || state.store?.unified != null);
    });
  }

  Future<void> cleanup(WidgetTester tester, Directory root) async {
    if (find.byType(TasksPage).evaluate().isNotEmpty) await stop(tester);
    await tester.runAsync(() => root.delete(recursive: true));
  }

  testWidgets(
    'v3 detection is an offer; Later preserves history and profile writer',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final writer = state.settings.writer as String;
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await press(tester, 'workspace-upgrade-available');
        await host.ready(
          tester,
          () => find.byType(WorkspaceUpgradeDialog).evaluate().isNotEmpty,
        );
        expect(find.text(writer), findsWidgets);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('begin-workspace-upgrade')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Later'));
        await tester.pumpAndSettle();
        expect(state.workspaceUpgrade, isNull);
        expect(state.settings.writer, writer);
        expect(
          await tester.runAsync(() => host.canonical(data.folder)),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'one confirmation completes real profile conversion and preserves logs and settings',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        var state = tester.state(find.byType(TasksPage)) as dynamic;
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        final oldRows = jsonDecode(jsonEncode(state.store.rows));
        final writer = state.settings.writer as String;
        final settings = LocalSettings.protectedValues(
          state.profileDatabase as LocalProfileDatabase,
        );
        await begin(tester);
        await host.ready(tester, () => state.store?.unified != null);
        expect(find.byType(WorkspaceUpgradePanel), findsNothing);
        expect(state.store.rows, oldRows);
        expect(state.settings.writer, writer);
        expect(LocalSettings.protectedValues(state.profileDatabase), settings);
        final after = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        for (final entry in before.entries.where(
          (entry) =>
              entry.key.endsWith('.jsonl') || entry.key.endsWith('.foodlog'),
        )) {
          expect(after[entry.key], entry.value);
        }
        expect(
          (jsonDecode(utf8.decode(after['tandemlog-space.json']!)) as Map)['v'],
          4,
        );
        expect(
          WorkspaceUpgrade.isFrozen(state.profileDatabase, state.store.space),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'cancel before staging releases freeze and preserves every canonical byte',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await tester.tap(find.byType(TaskCompletionCheckbox).first);
        await host.ready(
          tester,
          () => state.undoHistory.latest != null && state.busy == false,
        );
        final undo = state.undoHistory.latest;
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        final space = state.store.space as String;
        await begin(
          tester,
          otherDevice: '11111111-1111-4111-8111-111111111111',
        );
        await press(tester, 'cancel-workspace-upgrade');
        await host.ready(
          tester,
          () => state.store != null && state.upgradeFolder == null,
        );
        expect(state.store.unified, isNull);
        expect(
          WorkspaceUpgrade.isFrozen(state.profileDatabase, space),
          isFalse,
        );
        final after = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        for (final entry in before.entries) {
          expect(after[entry.key], entry.value);
        }
        expect(identical(state.undoHistory.latest, undo), isTrue);
        await tester.tap(find.byKey(const ValueKey('undo-task-action')));
        await host.ready(
          tester,
          () => state.undoHistory.latest == null && state.busy == false,
        );
        expect(find.text('Synthetic section task'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'dirty draft Cancel prevents local upgrade and creates no session or ACK',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await tester.tap(find.text('Synthetic section task'));
        final notes = find.byKey(const ValueKey('description'));
        await host.ready(tester, () => notes.evaluate().isNotEmpty);
        await tester.enterText(notes, 'Synthetic retained upgrade draft');
        final button = find.byKey(
          const ValueKey('workspace-upgrade-available'),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await host.ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic retained upgrade draft',
        );
        expect(find.byType(WorkspaceUpgradeDialog), findsNothing);
        expect(
          await tester.runAsync(() => host.canonical(data.folder)),
          before,
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(state.workspaceUpgrade, isNull);
        expect(
          WorkspaceUpgrade.isFrozen(state.profileDatabase, state.store.space),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'consented cold resume waits for the actual peer without fabricating its receipt',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        var state = tester.state(find.byType(TasksPage)) as dynamic;
        final writer = state.settings.writer as String;
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await begin(
          tester,
          otherDevice: '11111111-1111-4111-8111-111111111111',
        );
        expect(state.workspaceUpgrade.inputAcknowledged, {writer});
        expect(state.workspaceUpgrade.hasLocalConsent, isTrue);
        await stop(tester);
        await start(tester, data.profile);
        state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(state.store, isNull);
        expect(state.workspaceUpgrade.phase, 'input');
        expect(state.workspaceUpgrade.inputAcknowledged, {writer});
        expect(
          find.byKey(const ValueKey('join-workspace-upgrade')),
          findsNothing,
        );
        final resumed = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        for (final entry in before.entries) {
          expect(resumed[entry.key], entry.value);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'same installation keeps Task and Food session Undo across successful conversion',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await tester.tap(find.byType(TaskCompletionCheckbox).first);
        await host.ready(
          tester,
          () => state.undoHistory.latest != null && state.busy == false,
        );
        final taskUndo = state.undoHistory.latest;
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(true);
        await host.ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        final food = tester.widget<FoodInventoryPage>(
          find.byType(FoodInventoryPage),
        );
        final adding = Future<void>.sync(
          () => food.onAdd(
            const FoodDetails(
              name: 'Synthetic upgrade Undo food',
              expiry: '2026-12-01',
            ),
            1,
          ),
        );
        await host.ready(
          tester,
          () => state.foodUndoHistory.latest != null && state.busy == false,
        );
        await adding;
        final foodUndo = state.foodUndoHistory.latest;
        final originalFoodRecords = List.of(foodUndo.records);
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(false);
        await host.ready(
          tester,
          () => state.foodVisible == false && state.busy == false,
        );
        await begin(tester);
        await host.ready(tester, () => state.store?.unified != null);
        expect(identical(state.undoHistory.latest, taskUndo), isTrue);
        expect(identical(state.foodUndoHistory.latest, foodUndo), isTrue);
        expect(state.foodUndoHistory.latest.records, originalFoodRecords);
        await tester.tap(find.byKey(const ValueKey('undo-task-action')));
        try {
          await upgradeSettled(
            tester,
            () => state.undoHistory.latest == null && state.busy == false,
            'converted-task-undo',
          );
        } catch (_) {
          debugPrint(
            'UPGRADE_UNDO_DIAGNOSTIC busy=${state.busy} error=${state.error} sharedSafety=${state.sharedSafetyError} remaining=${state.undoHistory.latest?.operations}',
          );
          rethrow;
        }
        expect(find.text('Synthetic section task'), findsOneWidget);
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(true);
        await host.ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('undo-food-action')));
        await upgradeSettled(
          tester,
          () => state.foodUndoHistory.latest == null && state.busy == false,
          'converted-food-undo',
        );
        expect(state.foodStore.state.containers, isEmpty);
        final inverse = state.foodStore.unified.snapshot.effects
            .where((dynamic effect) => effect.food != null)
            .last
            .food;
        expect(inverse.operation.retracts, originalFoodRecords.single.id);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'staged cold resume restores only the same grant; picker Cancel and mismatch preserve authority',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      final folder = RevocableUpgradeFolder(data.folder.location);
      final actions = RestoreUpgradeFolderActions(folder);
      try {
        final saved = (await tester.runAsync(() async {
          final profile = await LocalProfileDatabase.open(data.profile);
          final local = LocalSettings(data.profile, profileDatabase: profile);
          await local.load();
          final engine = NativeTextEngine(
            libraryPath: host.nativeHostLibraryPath,
          );
          try {
            final upgrade = await WorkspaceUpgrade.start(
              folder: folder,
              profile: profile,
              writer: local.writer,
              participants: {local.writer},
              textEngine: engine,
            );
            await upgrade.acknowledgeInput();
            await upgrade.stage();
            return (
              writer: local.writer,
              space: upgrade.space,
              settings: LocalSettings.protectedValues(profile),
            );
          } finally {
            engine.dispose();
            await profile.close();
          }
        }))!;
        folder.granted = false;
        await start(tester, data.profile, actions: actions, folder: folder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(state.store, isNull);
        expect(state.upgradeError, contains('revoked'));
        final profile = state.profileDatabase as LocalProfileDatabase;
        final before = profile.database
            .select(
              'SELECT hex(plan) AS plan,state FROM protected_app_migrations',
            )
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final settingsBefore = LocalSettings.protectedValues(profile);
        Future<void> choose(String? result) async {
          actions.next = result;
          await tester.tap(
            find.byKey(const ValueKey('restore-upgrade-folder-access')),
          );
          await upgradeSettled(
            tester,
            () => state.busy == false,
            'restore-grant',
          );
        }

        await choose(null);
        expect(actions.expected, folder.location);
        expect(folder.granted, isFalse);
        expect(state.upgradeError, contains('revoked'));
        expect(LocalSettings.protectedValues(profile), settingsBefore);
        expect(
          profile.database
              .select(
                'SELECT hex(plan) AS plan,state FROM protected_app_migrations',
              )
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
          before,
        );
        await choose('content://synthetic.invalid/tree/wrong-folder');
        expect(state.store, isNull);
        expect(folder.granted, isFalse);
        expect(state.upgradeError, contains('original data folder'));
        expect(LocalSettings.protectedValues(profile), settingsBefore);
        expect(
          profile.database
              .select(
                'SELECT hex(plan) AS plan,state FROM protected_app_migrations',
              )
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
          before,
        );
        expect(WorkspaceUpgrade.isFrozen(profile, saved.space), isTrue);
        await choose(folder.location);
        await host.ready(tester, () => state.store?.unified != null);
        expect(folder.granted, isTrue);
        expect(state.settings.writer, saved.writer);
        expect(LocalSettings.protectedValues(profile), saved.settings);
        expect(WorkspaceUpgrade.isFrozen(profile, saved.space), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  testWidgets(
    'unreadable protected upgrade journal stays in recovery without initializing history',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      try {
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await tester.runAsync(() async {
          final profile = await LocalProfileDatabase.open(data.profile);
          try {
            final manifest =
                jsonDecode(
                      utf8.decode(
                        await data.folder.read('tandemlog-space.json'),
                      ),
                    )
                    as Map;
            profile.database.execute(
              'INSERT INTO protected_app_migrations VALUES (?,?,?,?)',
              [
                manifest['id'],
                '11111111-1111-4111-8111-111111111111',
                utf8.encode('incomplete protected journal'),
                'staging',
              ],
            );
          } finally {
            await profile.close();
          }
        });
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(state.store, isNull);
        expect(state.upgradeFolder, isNotNull);
        expect(state.upgradeError, isNotNull);
        expect(find.text('Workspace upgrade needs attention'), findsOneWidget);
        expect(
          await tester.runAsync(() => host.canonical(data.folder)),
          before,
        );
        final profile = state.profileDatabase as LocalProfileDatabase;
        expect(
          profile.database
              .select('SELECT plan FROM protected_app_migrations')
              .single['plan'],
          utf8.encode('incomplete protected journal'),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );

  for (final orphan in [
    'upgrade-11111111-1111-4111-8111-111111111111-staging.json',
    '11111111-1111-4111-8111-111111111111.applog',
  ]) {
    testWidgets(
      'orphan $orphan arriving before control blocks legacy startup without appends',
      (tester) async {
        final data = (await tester.runAsync(host.fixture))!;
        try {
          final before = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          await tester.runAsync(
            () => File('${data.folder.location}/$orphan').writeAsString('{}'),
          );
          await start(tester, data.profile);
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          expect(state.store, isNull);
          expect(state.upgradeFolder, isNotNull);
          expect(state.upgradeError, isNotNull);
          expect(find.text('A little less to remember.'), findsNothing);
          final after = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          for (final entry in before.entries) {
            expect(after[entry.key], entry.value);
          }
          expect(after.keys.toSet(), {...before.keys, orphan});
          expect(tester.takeException(), isNull);
        } finally {
          await cleanup(tester, data.root);
        }
      },
    );
  }

  testWidgets(
    'peer session freezes before background writes and Cancel preserves editor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final data = (await tester.runAsync(host.fixture))!;
      final folder = RevocableUpgradeFolder(data.folder.location);
      final actions = RestoreUpgradeFolderActions(folder);
      LocalProfileDatabase? peer;
      NativeTextEngine? engine;
      try {
        await start(tester, data.profile, actions: actions, folder: folder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await tester.tap(find.text('Synthetic section task'));
        final notes = find.byKey(const ValueKey('description'));
        await host.ready(tester, () => notes.evaluate().isNotEmpty);
        await tester.enterText(notes, 'Synthetic peer-upgrade draft');
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await tester.runAsync(() async {
          peer = await LocalProfileDatabase.open('${data.root.path}/peer');
          await LocalProfileMigration(peer!).run();
          final local = LocalSettings(peer!.root, profileDatabase: peer);
          await local.load();
          engine = NativeTextEngine(libraryPath: host.nativeHostLibraryPath);
          await WorkspaceUpgrade.start(
            folder: data.folder,
            profile: peer!,
            writer: local.writer,
            participants: {local.writer, state.settings.writer as String},
            textEngine: engine,
          );
        });
        state.importer.request();
        await host.ready(tester, () => state.workspaceUpgrade != null);
        expect(state.upgradeScreen, isFalse);
        expect(
          WorkspaceUpgrade.isFrozen(state.profileDatabase, state.store.space),
          isTrue,
        );
        expect(state.workspaceUpgrade.inputAcknowledged, isEmpty);
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic peer-upgrade draft',
        );
        await tester.tap(
          find.byKey(const ValueKey('workspace-upgrade-available')),
        );
        await host.ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic peer-upgrade draft',
        );
        expect(state.workspaceUpgrade.inputAcknowledged, isEmpty);
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('identity-menu')),
            )
            .onSelected!('settings');
        final restoreSetting = find.byKey(
          const ValueKey('restore-upgrade-folder-access-setting'),
        );
        await host.ready(tester, () => restoreSetting.evaluate().isNotEmpty);
        await tester.ensureVisible(restoreSetting);
        await tester.tap(restoreSetting);
        await host.ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();
        expect(
          actions.restores,
          0,
          reason: 'Cancel before restoration must not open a grant picker',
        );
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic peer-upgrade draft',
        );
        expect(state.upgradeScreen, isFalse);
        expect(state.workspaceUpgrade.inputAcknowledged, isEmpty);
        final after = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        for (final entry in before.entries) {
          expect(after[entry.key], entry.value);
        }
        expect(tester.takeException(), isNull);
      } finally {
        engine?.dispose();
        await tester.runAsync(() async => peer?.close());
        await cleanup(tester, data.root);
      }
    },
  );
}
