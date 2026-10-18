import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

import 'food_preview_workflow_test.dart' as pixels;
import 'native_text_fixtures.dart';

/// Real GTK widgets, native text, SQLite and direct local files. Multiple locked
/// profiles model independent installations; this does not claim separate OS
/// processes, Android document providers, or unseen-device coordination.
class _ObservedEngine extends NativeTextEngine {
  _ObservedEngine()
    : super(libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY']);
  bool closed = false;
  @override
  void dispose() {
    super.dispose();
    closed = true;
  }
}

typedef _Fixture = ({
  Directory root,
  LocalLogFolder folder,
  String user,
  String profileA,
  String profileB,
  String writerA,
  String writerB,
});

Future<_Fixture> _fixture(Brightness brightness) async {
  final root = await Directory.systemTemp.createTemp(
    'synthetic-native-guided-workspace-upgrade-',
  );
  final folder = LocalLogFolder(
    (await Directory('${root.path}/data').create()).path,
  );
  final user = const Uuid().v4();
  final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
  try {
    await seed.command(user, 'user.created', {
      'name': 'Synthetic upgrade user',
    });
    await seed.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Synthetic upgrade task',
      'description': 'Native history stays intact.',
      'assignee': user,
    });
  } finally {
    await seed.close();
  }

  Future<String> preferences(String path, Appearance appearance) async {
    final profile = await LocalProfileDatabase.open(path);
    try {
      await LocalProfileMigration(profile).run();
      final settings = LocalSettings(path, profileDatabase: profile);
      await settings.load();
      settings.folder = folder.location;
      settings.user = user;
      settings.appearance = appearance;
      await settings.save();
      return settings.writer;
    } finally {
      await profile.close();
    }
  }

  final profileA = '${root.path}/profile-a';
  final profileB = '${root.path}/profile-b';
  return (
    root: root,
    folder: folder,
    user: user,
    profileA: profileA,
    profileB: profileB,
    writerA: await preferences(
      profileA,
      Appearance.values.byName(brightness.name),
    ),
    writerB: await preferences(profileB, Appearance.dark),
  );
}

Future<Map<String, List<int>>> _legacyBytes(LocalLogFolder folder) async => {
  for (final info in await folder.list())
    if (info.name.endsWith('.jsonl') || info.name.endsWith('.foodlog'))
      info.name: await folder.read(info.name),
};

Map<String, Map<String, dynamic>> _nativeFields(dynamic state) => {
  for (final row in state.store.db.select(
    'SELECT * FROM ${state.store.tables.textFields} ORDER BY entity,field',
  ))
    '${row['entity']}/${row['field']}': {
      for (final entry in Map<String, dynamic>.from(row).entries)
        entry.key: entry.value is List<int>
            ? base64Encode(entry.value as List<int>)
            : entry.value,
    },
};

Future<void> _ready(
  WidgetTester tester,
  bool Function() ready, {
  String reason = 'Native guided upgrade must reach the expected state',
}) async {
  final elapsed = Stopwatch()..start();
  await tester.pump();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 30)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: reason);
  await tester.pumpAndSettle();
}

dynamic _state(WidgetTester tester) =>
    tester.state(find.byType(TasksPage)) as dynamic;

Future<void> _start(WidgetTester tester, String profile) async {
  await tester.pumpWidget(
    TandemlogApp(
      key: ValueKey(profile),
      profilePath: profile,
      textEngineFactory: _ObservedEngine.new,
    ),
  );
  await _ready(tester, () {
    final state = _state(tester);
    if (state.error != null) throw StateError(state.error as String);
    if (state.upgradeError != null) {
      throw StateError(state.upgradeError as String);
    }
    return !state.busy &&
        (state.store != null || state.workspaceUpgrade != null);
  });
}

Future<void> _stop(WidgetTester tester) async {
  final state = _state(tester);
  final profile = state.profileDatabase as LocalProfileDatabase;
  final db = profile.database;
  final engine = state.textEngine as _ObservedEngine;
  await tester.pumpWidget(const SizedBox.shrink());
  await _ready(tester, () {
    if (!engine.closed) return false;
    try {
      db.select('SELECT 1');
      return false;
    } on StateError catch (error) {
      return error.message == 'This database has already been closed';
    }
  });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await _ready(tester, () => target.evaluate().isNotEmpty);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await pixels.tap(tester, target);
  await tester.pump();
}

Future<void> _section(WidgetTester tester, bool food) async {
  await _tap(tester, 'section-menu');
  await _tap(tester, food ? 'module-food' : 'module-tasks');
  await _ready(tester, () => _state(tester).foodVisible == food);
}

Future<void> _begin(
  WidgetTester tester, {
  String? peer,
  required String capture,
}) async {
  await _tap(tester, 'workspace-upgrade-available');
  await _ready(
    tester,
    () => find
        .byKey(const ValueKey('upgrade-coordination-confirmation'))
        .evaluate()
        .isNotEmpty,
  );
  if (peer != null) {
    final extra = find.byKey(const ValueKey('upgrade-extra-participants'));
    await tester.ensureVisible(extra);
    await tester.enterText(extra, peer);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(extra).controller!.text, peer);
  }
  await pixels.capture(tester, '$capture-setup');
  await _tap(tester, 'upgrade-coordination-confirmation');
  await pixels.capture(tester, '$capture-confirmation');
  await _tap(tester, 'begin-workspace-upgrade');
  await _ready(tester, () {
    final state = _state(tester);
    if (state.upgradeError != null) {
      throw StateError(state.upgradeError as String);
    }
    return !state.busy &&
        (state.workspaceUpgrade != null || state.store?.unified != null);
  });
}

Future<void> _assertLegacy(
  LocalLogFolder folder,
  Map<String, List<int>> original,
) async {
  final actual = await _legacyBytes(folder);
  expect(actual.keys.toSet(), original.keys.toSet());
  for (final entry in original.entries) {
    expect(
      actual[entry.key],
      entry.value,
      reason: 'Every original Task/Food log remains byte exact',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerWorkspaceUpgradeWorkflowTests();
}

void registerWorkspaceUpgradeWorkflowTests() {
  for (final sample in [
    (Brightness.light, const Size(1200, 850), 1.0),
    (Brightness.dark, const Size(390, 850), 2.0),
  ]) {
    testWidgets(
      'native guided one-confirmation upgrade preserves prior Task/Food Undo ${sample.$1.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = sample.$2;
        tester.platformDispatcher.textScaleFactorTestValue = sample.$3;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final data = await _fixture(sample.$1);
        try {
          await _start(tester, data.profileA);
          final state = _state(tester);
          await pixels.tap(tester, find.byType(TaskCompletionCheckbox).first);
          await _ready(
            tester,
            () => !state.busy && state.undoHistory.latest != null,
          );
          final taskUndo = state.undoHistory.latest;
          await _section(tester, true);
          await pixels.tap(tester, find.byTooltip('Add food'));
          await _ready(
            tester,
            () => find
                .byKey(const ValueKey('food-expiration'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Food name'),
            'Synthetic upgrade Undo food',
          );
          await tester.enterText(
            find.byKey(const ValueKey('food-expiration')),
            '2026-12-01',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          await _tap(tester, 'food-save-action');
          await _ready(
            tester,
            () => !state.busy && state.foodUndoHistory.latest != null,
          );
          final foodUndo = state.foodUndoHistory.latest;
          final target = foodUndo.records.single.id;
          await _section(tester, false);
          final rows = jsonDecode(jsonEncode(state.store.rows));
          final native = _nativeFields(state);
          final profile = state.profileDatabase as LocalProfileDatabase;
          final settings = LocalSettings.protectedValues(profile);
          final legacy = await _legacyBytes(data.folder);
          await _begin(tester, capture: 'upgrade-native-${sample.$1.name}');
          await _ready(
            tester,
            () => state.store?.unified != null && !state.busy,
          );
          expect(state.store.rows, rows);
          expect(_nativeFields(state), native);
          expect(LocalSettings.protectedValues(profile), settings);
          expect(state.settings.writer, data.writerA);
          expect(identical(state.undoHistory.latest, taskUndo), isTrue);
          expect(identical(state.foodUndoHistory.latest, foodUndo), isTrue);
          await _assertLegacy(data.folder, legacy);
          await pixels.capture(
            tester,
            'upgrade-native-${sample.$1.name}-complete',
          );
          await _tap(tester, 'undo-task-action');
          await _ready(
            tester,
            () => !state.busy && state.undoHistory.latest == null,
          );
          expect(find.text('Synthetic upgrade task'), findsOneWidget);
          await _section(tester, true);
          await _tap(tester, 'undo-food-action');
          await _ready(
            tester,
            () => !state.busy && state.foodUndoHistory.latest == null,
          );
          expect(state.foodStore.state.containers, isEmpty);
          final inverse = state.foodStore.unified.snapshot.effects
              .where((dynamic effect) => effect.food != null)
              .last
              .food;
          expect(inverse.operation.retracts, target);
          await _assertLegacy(data.folder, legacy);
          await pixels.capture(tester, 'upgrade-native-${sample.$1.name}-undo');
          expect(tester.takeException(), isNull);
        } finally {
          if (find.byType(TasksPage).evaluate().isNotEmpty) await _stop(tester);
          await data.root.delete(recursive: true);
        }
      },
    );
  }

  testWidgets(
    'native independent peer Join, both real barriers and cold resumes preserve history',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final data = await _fixture(Brightness.light);
      try {
        await _start(tester, data.profileA);
        var state = _state(tester);
        final rows = jsonDecode(jsonEncode(state.store.rows));
        final native = _nativeFields(state);
        final settingsA = LocalSettings.protectedValues(state.profileDatabase);
        final legacy = await _legacyBytes(data.folder);
        await _begin(
          tester,
          peer: data.writerB,
          capture: 'upgrade-native-peer',
        );
        state = _state(tester);
        expect(state.workspaceUpgrade.inputAcknowledged, {data.writerA});
        expect(state.workspaceUpgrade.outputAcknowledged, isEmpty);
        expect(state.workspaceUpgrade.phase, 'input');
        expect(
          WorkspaceUpgrade.isFrozen(
            state.profileDatabase,
            state.workspaceUpgrade.space,
          ),
          isTrue,
        );
        await pixels.capture(tester, 'upgrade-native-peer-wait-input');
        await _stop(tester);

        // Cold A retains its own consent and waits; it cannot invent B's ACK.
        await _start(tester, data.profileA);
        state = _state(tester);
        expect(state.store, isNull);
        expect(state.workspaceUpgrade.inputAcknowledged, {data.writerA});
        expect(state.workspaceUpgrade.hasLocalConsent, isTrue);
        await _assertLegacy(data.folder, legacy);
        await _stop(tester);

        // B is a separate real locked profile, not a synthesized acknowledgement.
        tester.view.physicalSize = const Size(320, 850);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await _start(tester, data.profileB);
        state = _state(tester);
        final settingsB = LocalSettings.protectedValues(state.profileDatabase);
        expect(state.workspaceUpgrade.hasLocalConsent, isFalse);
        expect(state.workspaceUpgrade.inputAcknowledged, {data.writerA});
        await pixels.capture(tester, 'upgrade-native-peer-dark-200-join');
        await _tap(tester, 'join-workspace-upgrade');
        await _ready(
          tester,
          () =>
              !state.busy &&
              state.workspaceUpgrade.inputAcknowledged.contains(data.writerB),
        );
        expect(state.workspaceUpgrade.inputAcknowledged, {
          data.writerA,
          data.writerB,
        });
        expect(state.workspaceUpgrade.outputAcknowledged, isEmpty);
        expect(state.workspaceUpgrade.phase, 'input');
        expect(
          (jsonDecode(
                utf8.decode(await data.folder.read('tandemlog-space.json')),
              )
              as Map)['v'],
          3,
        );
        await pixels.capture(tester, 'upgrade-native-peer-dark-200-paused');
        await _stop(tester);

        tester.view.physicalSize = const Size(1200, 850);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await _start(tester, data.profileA);
        state = _state(tester);
        await _ready(
          tester,
          () =>
              !state.busy &&
              state.workspaceUpgrade?.phase == 'staged' &&
              state.workspaceUpgrade.outputAcknowledged.contains(data.writerA),
        );
        expect(state.workspaceUpgrade.outputAcknowledged, {data.writerA});
        expect(state.store, isNull);
        await pixels.capture(tester, 'upgrade-native-peer-wait-output');
        await _stop(tester);

        tester.view.physicalSize = const Size(320, 850);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await _start(tester, data.profileB);
        state = _state(tester);
        await _ready(
          tester,
          () =>
              !state.busy &&
              state.workspaceUpgrade.outputAcknowledged.contains(data.writerB),
        );
        expect(state.workspaceUpgrade.outputAcknowledged, {
          data.writerA,
          data.writerB,
        });
        expect(state.workspaceUpgrade.phase, 'staged');
        final staged =
            jsonDecode(
                  utf8.decode(await data.folder.read('tandemlog-space.json')),
                )
                as Map;
        expect(staged['v'], 4);
        expect(staged['ready'], isFalse);
        await pixels.capture(tester, 'upgrade-native-peer-dark-200-verified');
        await _stop(tester);

        tester.view.physicalSize = const Size(1200, 850);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        await _start(tester, data.profileA);
        state = _state(tester);
        await _ready(tester, () => !state.busy && state.store?.unified != null);
        expect(state.store.rows, rows);
        expect(_nativeFields(state), native);
        expect(LocalSettings.protectedValues(state.profileDatabase), settingsA);
        expect(state.settings.writer, data.writerA);
        await _assertLegacy(data.folder, legacy);
        await pixels.capture(tester, 'upgrade-native-peer-leading-complete');
        await _stop(tester);

        // B completes after A may already have appended its own joined header.
        await _start(tester, data.profileB);
        state = _state(tester);
        await _ready(tester, () => !state.busy && state.store?.unified != null);
        expect(state.store.rows, rows);
        expect(state.settings.writer, data.writerB);
        expect(LocalSettings.protectedValues(state.profileDatabase), settingsB);
        await _assertLegacy(data.folder, legacy);
        await pixels.capture(tester, 'upgrade-native-peer-second-complete');
        expect(tester.takeException(), isNull);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) await _stop(tester);
        await data.root.delete(recursive: true);
      }
    },
  );
}
