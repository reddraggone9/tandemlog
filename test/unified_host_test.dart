import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/unified_trial.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/presentation/device_name_dialog.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'section_navigation_host_test.dart' as host;
import 'unified_history_test.dart' show FaultFolder;
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/log_folder.dart';

Future<({UnifiedTrial trial, String profile, String writer})>
unifiedFixture() async {
  final source = await host.fixture();
  final p = await LocalProfileDatabase.open(source.profile);
  final settings = LocalSettings(source.profile, profileDatabase: p);
  await settings.load();
  final writer = settings.writer;
  await p.close();
  final sources = <String, List<int>>{};
  for (final info in await source.folder.list()) {
    if (info.name.endsWith('.jsonl') || info.name.endsWith('.foodlog')) {
      sources[info.name] = await source.folder.read(info.name);
    }
  }
  final owners = {
    writer,
    ...sources.keys
        .where((n) => n.endsWith('.jsonl'))
        .map((n) => n.substring(0, n.length - 6)),
  };
  final taskManifest = await source.folder.read('tandemlog-space.json');
  // Read the already-created synthetic workspace ID.
  final space = (jsonDecode(utf8.decode(taskManifest)) as Map)['id'] as String;
  final trial = await UnifiedTrial.createSynthetic(
    space: space,
    owners: owners,
    participants: {writer},
    sources: sources,
  );
  final engine = NativeTextEngine(libraryPath: host.nativeHostLibraryPath);
  try {
    await trial.acknowledgeInput(writer, textEngine: engine);
    await trial.stage();
    await trial.acknowledgeOutput(writer, textEngine: engine);
    await trial.activate(textEngine: engine);
    await trial.retireSyntheticSources();
  } finally {
    engine.dispose();
  }
  final profile = trial.profileRoot(writer),
      preferences = await trial.openParticipant(writer);
  final local = LocalSettings(profile, profileDatabase: preferences);
  await local.load();
  local.folder = trial.folder.location;
  local.user = source.user;
  await local.save();
  await preferences.close();
  await source.root.delete(recursive: true);
  return (trial: trial, profile: profile, writer: writer);
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  Future<void> start(
    WidgetTester tester,
    String profile, {
    LogFolder? folder,
    bool pending = false,
  }) async {
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: profile,
        folderFactory: folder == null ? null : (_) => folder,
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    await host.ready(tester, () {
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      if (state.error != null && !pending) {
        throw StateError('Host startup: ${state.error}');
      }
      return state.store != null && state.busy == false;
    });
  }

  Future<void> stop(WidgetTester tester) async {
    final resources = host.hostResources(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await host.waitForHostShutdown(tester, resources);
  }

  testWidgets(
    'host shares one history and Settings label survives clear/reopen without changing data effects',
    (tester) async {
      final data = (await tester.runAsync(unifiedFixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final h = state.store.unified as UnifiedHistory;
        expect(identical(h, state.foodStore.unified), isTrue);
        final before = h.snapshot.effects
            .where((e) => e.isData)
            .map((e) => e.raw)
            .toList();
        final seq = h.physicalSequence;
        // Use the actual identity menu action to open Settings.
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('identity-menu')),
            )
            .onSelected!('settings');
        await host.ready(
          tester,
          () => find
              .byKey(const ValueKey('device-name-setting'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('device-name-setting')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('device-name-field')),
          'Office',
        );
        await tester.tap(find.text('Save'));
        await host.ready(
          tester,
          () =>
              h.snapshot.deviceName(data.writer) == 'Office' &&
              state.busy == false,
        );
        expect(h.physicalSequence, seq + 1);
        expect(
          h.snapshot.effects.where((e) => e.isData).map((e) => e.raw),
          before,
        );
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(true);
        await host.ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        expect(identical(state.store.unified, state.foodStore.unified), isTrue);
        await stop(tester);
        await start(tester, data.profile);
        final reopened = tester.state(find.byType(TasksPage)) as dynamic;
        final restored = reopened.store.unified as UnifiedHistory;
        expect(restored.snapshot.deviceName(data.writer), 'Office');
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('identity-menu')),
            )
            .onSelected!('settings');
        await host.ready(
          tester,
          () => find
              .byKey(const ValueKey('device-name-setting'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('device-name-setting')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('device-name-field')),
          ' ',
        );
        await tester.tap(find.text('Save'));
        await host.ready(
          tester,
          () =>
              restored.snapshot.deviceName(data.writer) == null &&
              reopened.busy == false,
        );
        expect(restored.snapshot.deviceName(data.writer), isNull);
        expect(tester.takeException(), isNull);
        await stop(tester);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) {
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          if (state.textEngine != null) {
            await stop(tester);
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
        await tester.runAsync(() async {
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'cold reopen exposes generic name receipt and Retry completes exact bytes',
    (tester) async {
      final data = (await tester.runAsync(unifiedFixture))!;
      final folder = FaultFolder(data.trial.folder.location);
      try {
        await start(tester, data.profile, folder: folder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final h = state.store.unified as UnifiedHistory;
        folder.cut = 20;
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('identity-menu')),
            )
            .onSelected!('settings');
        await host.ready(
          tester,
          () => find
              .byKey(const ValueKey('device-name-setting'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('device-name-setting')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('device-name-field')),
          'Interrupted label',
        );
        await tester.tap(find.text('Save'));
        await host.ready(tester, () => state.busy == false && h.hasPending);
        final expected = h.pendingRecords.single.encode();
        expect(state.store.pendingTextOperations, isEmpty);
        await stop(tester);
        await start(tester, data.profile, folder: folder, pending: true);
        final reopened = tester.state(find.byType(TasksPage)) as dynamic;
        final recovered = reopened.store.unified as UnifiedHistory;
        expect(recovered.hasPending, isTrue);
        expect(recovered.snapshot.deviceName(data.writer), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Retry').first);
        await host.ready(
          tester,
          () => !recovered.hasPending && reopened.busy == false,
        );
        expect(recovered.snapshot.deviceName(data.writer), 'Interrupted label');
        expect(
          recovered.snapshot.records
              .singleWhere(
                (r) =>
                    r.writer == data.writer && r.effect.kind == 'writer.named',
              )
              .encode(),
          expected,
        );
        await stop(tester);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) await stop(tester);
        await tester.runAsync(() async {
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'corrupted common history stops both sections and admission-only Retry preserves bytes',
    (tester) async {
      final data = (await tester.runAsync(unifiedFixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final h = state.store.unified as UnifiedHistory;
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(true);
        await host.ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        final name = h.manifest.owners.entries
            .firstWhere((e) => (e.value['count'] as int) > 0)
            .key;
        final file = data.trial.folder.file(unifiedLogName(name));
        final bytes = (await tester.runAsync(() => file.readAsBytes()))!;
        await tester.runAsync(
          () => file.writeAsBytes([...bytes, 10], flush: true),
        );
        await host.ready(tester, () => state.sharedSafetyError != null);
        expect(state.foodError, isNull);
        await tester.runAsync(() => file.writeAsBytes(bytes, flush: true));
        await tester.tap(find.widgetWithText(TextButton, 'Retry').first);
        await host.ready(
          tester,
          () => state.sharedSafetyError == null && state.busy == false,
        );
        expect(await tester.runAsync(() => file.readAsBytes()), bytes);
        expect(state.foodVisible, isTrue);
        expect(tester.takeException(), isNull);
        await stop(tester);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) await stop(tester);
        await tester.runAsync(() async {
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'Task command first discovery of common admission failure immediately stops both sections',
    (tester) async {
      final data = (await tester.runAsync(unifiedFixture))!;
      final folder = host.FaultingFolder(data.trial.folder);
      try {
        await start(tester, data.profile, folder: folder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final before = (await tester.runAsync(
          () => host.canonical(data.trial.folder),
        ))!;
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        final field = find.widgetWithText(TextField, 'What needs doing?');
        await tester.enterText(field, 'Keep this synthetic draft');
        await host.ready(tester, () => state.syncing == null);
        state.importer.stop();
        folder.wrongManifest = true;
        await tester.tap(find.byKey(const ValueKey('capture-add')));
        await host.ready(
          tester,
          () => state.sharedSafetyError != null && state.busy == false,
        );
        expect(state.foodError, isNull);
        expect(state.capture.text, 'Keep this synthetic draft');
        expect((state.store.unified as UnifiedHistory).hasPending, isFalse);
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
        );
        folder.wrongManifest = false;
        await tester.tap(find.widgetWithText(TextButton, 'Retry').first);
        await host.ready(
          tester,
          () => state.sharedSafetyError == null && state.busy == false,
        );
        expect(state.capture.text, 'Keep this synthetic draft');
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
        );
        await stop(tester);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) await stop(tester);
        await tester.runAsync(() async {
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'device name Cancel, blank, validation, IME and repeated submit preserve route ownership',
    (tester) async {
      DeviceNameChange? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<DeviceNameChange>(
                    context: context,
                    builder: (_) => const DeviceNameDialog(name: 'Old'),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('device-name-field')),
        'x' * 81,
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(
        find.text('Use up to 80 characters without control characters.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('device-name-field')),
      );
      field.controller!.value = const TextEditingValue(
        text: 'Composing',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 3),
      );
      expect(
        field.controller!.value.composing,
        const TextRange(start: 0, end: 3),
      );
      field.onSubmitted!('Composing');
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(DeviceNameDialog), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('device-name-field')),
        ' ',
      );
      await tester.pumpAndSettle();
      expect(find.text('Review errors'), findsNothing);
      expect(find.byType(DeviceNameDialog), findsOneWidget);
      expect(
        result,
        isNull,
        reason: 'Correcting input cannot submit the dialog.',
      );
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.name, isNull);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      result = null;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('device-name-field')),
        'Discarded',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final staleSave = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed!;
      Navigator.of(tester.element(find.byType(DeviceNameDialog))).pop();
      staleSave();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
