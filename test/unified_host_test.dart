import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../integration_test/native_text_fixtures.dart'
    show captureNativeFixtureUi;
import 'package:tandemlog/presentation/activity_log.dart';
import 'package:tandemlog/application/activity_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/presentation/device_name_dialog.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'section_navigation_host_test.dart' as host;
import 'unified_history_test.dart' show FaultFolder;
import 'package:tandemlog/storage/unified_record.dart';
import 'package:tandemlog/storage/log_folder.dart';

class SyntheticWorkspace {
  SyntheticWorkspace(this.root, this.folder);
  final Directory root;
  final LocalLogFolder folder;
  Future<void> close() async {}
}

Future<({SyntheticWorkspace trial, String profile, String writer})>
unifiedFixture() async {
  final source = await host.fixture();
  final p = await LocalProfileDatabase.open(source.profile);
  try {
    final settings = LocalSettings(source.profile, profileDatabase: p);
    await settings.load();
    return (
      trial: SyntheticWorkspace(source.root, source.folder),
      profile: source.profile,
      writer: settings.writer,
    );
  } finally {
    await p.close();
  }
}

class _HeldFoodAppend extends host.FaultingFolder {
  _HeldFoodAppend(super.delegate);
  Completer<void>? gate;
  bool entered = false, fail = false;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (gate != null) {
      entered = true;
      await gate!.future;
      if (fail) throw const FileSystemException('Synthetic append refusal');
    }
    return super.append(name, bytes);
  }
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
    'Activity log is read-only and follows published device changes',
    (tester) async {
      final data = (await tester.runAsync(unifiedFixture))!;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final history = state.store.unified as UnifiedHistory;
        final before = await tester.runAsync(
          () => host.canonical(data.trial.folder),
        );
        await tester.tap(find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity log'));
        await tester.pumpAndSettle();
        expect(find.byType(ActivityLogDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('activity-list')), findsOneWidget);
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
        );
        final count = activityEntries(history.snapshot).length;
        var renamed = false;
        unawaited(
          history
              .renameDevice('Activity synthetic device')
              .then((_) => renamed = true),
        );
        await host.ready(tester, () => renamed);
        await tester.pumpAndSettle();
        expect(activityEntries(history.snapshot), hasLength(count + 1));
        expect(find.textContaining('Activity synthetic device'), findsWidgets);
        final revision = history.snapshot.revision;
        final beforeFailure = await tester.runAsync(
          () => host.canonical(data.trial.folder),
        );
        history.reportQueueFailure(
          StateError('Synthetic Activity refresh failure'),
        );
        await tester.pump();
        expect(history.snapshot.revision, revision);
        expect(
          find.byKey(const ValueKey('activity-refresh-error')),
          findsOneWidget,
        );
        var refreshed = false;
        unawaited(history.refresh().then((_) => refreshed = true));
        await host.ready(tester, () => refreshed);
        expect(
          find.byKey(const ValueKey('activity-refresh-error')),
          findsNothing,
        );
        expect(history.snapshot.revision, revision);
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          beforeFailure,
        );

        await tester.tap(find.byTooltip('About Activity log'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Device clock skew'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Close').last);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(find.byType(ActivityLogDialog), findsNothing);
      } finally {
        await stop(tester);
        await tester.runAsync(() async {
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  for (final (width, scale) in [(800.0, 1.0), (390.0, 2.0), (320.0, 2.0)]) {
    testWidgets(
      'Food recovery banner skips in-flight save but retains failed retry $width x$scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 850);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final data = (await tester.runAsync(unifiedFixture))!;
        final folder = _HeldFoodAppend(data.trial.folder);
        try {
          await start(tester, data.profile, folder: folder);
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
            true,
          );
          await host.ready(
            tester,
            () =>
                find.byType(FoodInventoryPage).evaluate().isNotEmpty &&
                !state.busy,
          );
          Future<void> addHeld({required bool fail}) async {
            folder.gate = Completer<void>();
            folder.entered = false;
            folder.fail = fail;
            Object? error;
            var done = false;
            final page = tester.widget<FoodInventoryPage>(
              find.byType(FoodInventoryPage),
            );
            unawaited(
              Future<void>.sync(
                    () => page.onAdd(
                      FoodDetails(
                        name: fail ? 'Refused food' : 'Healthy food',
                        expiry: '2027-03-01',
                      ),
                      1,
                    ),
                  )
                  .catchError((Object e) {
                    error = e;
                  })
                  .whenComplete(() => done = true),
            );
            await host.ready(tester, () => folder.entered, settle: false);
            await tester.pump();
            expect(state.busy, isTrue);
            expect(find.byKey(const ValueKey('retry-food-save')), findsNothing);
            folder.gate!.complete();
            await host.ready(tester, () => done && !state.busy);
            expect(error != null, fail);
          }

          await addHeld(fail: false);
          expect(find.byKey(const ValueKey('retry-food-save')), findsNothing);
          await addHeld(fail: true);
          expect(find.byKey(const ValueKey('retry-food-save')), findsOneWidget);
          expect(
            state.pendingFoodCommand,
            isNotNull,
            reason: 'Failed save keeps its immutable receipt for recovery.',
          );
          if (scale == 2) {
            // Recover shared admission through the real UI; do not bypass its
            // safety overlay or replay the unresolved immutable Food receipt.
            folder.gate = null;
            final pendingBytes = await tester.runAsync(
              () => host.canonical(data.trial.folder),
            );
            await tester.tap(find.byKey(const ValueKey('retry-shared-read')));
            await host.ready(
              tester,
              () => state.sharedSafetyError == null && !state.busy,
            );
            expect(
              await tester.runAsync(() => host.canonical(data.trial.folder)),
              pendingBytes,
            );
            final notice = find.byKey(const ValueKey('action-error-scroll'));
            expect(notice, findsOneWidget);
            final bar = find.ancestor(
              of: notice,
              matching: find.byType(Scrollbar),
            );
            expect(bar, findsOneWidget);
            expect(tester.widget<Scrollbar>(bar).thumbVisibility, isTrue);
            final scrollable = find.descendant(
              of: notice,
              matching: find.byType(Scrollable),
            );
            final position = tester.state<ScrollableState>(scrollable).position;
            expect(position.maxScrollExtent, greaterThan(0));
            final before = await tester.runAsync(
              () => host.canonical(data.trial.folder),
            );
            await captureNativeFixtureUi(
              tester,
              'recovery-${width.round()}-200-start',
            );
            await tester.drag(notice, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(position.pixels, position.maxScrollExtent);
            final copy = find.descendant(
              of: notice,
              matching: find.byType(Text),
            );
            expect(
              tester.widget<Text>(copy).data,
              contains('Retry to finish it.'),
            );
            expect(
              tester.getRect(copy).bottom,
              lessThanOrEqualTo(tester.getRect(notice).bottom + .1),
            );
            expect(
              find.byKey(const ValueKey('retry-food-save')).hitTestable(),
              findsOneWidget,
            );
            await captureNativeFixtureUi(
              tester,
              'recovery-${width.round()}-200-end',
            );
            expect(
              await tester.runAsync(() => host.canonical(data.trial.folder)),
              before,
            );
            expect(tester.takeException(), isNull);
          }
        } finally {
          folder.gate = null;
          await stop(tester);
          await tester.runAsync(() async {
            await data.trial.close();
            await data.trial.root.delete(recursive: true);
          });
        }
      },
    );
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
    'cold reopen forgets unfinished name intent; a new Save cleans the owned tail',
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
        final partial = (await tester.runAsync(
          () => folder.read(unifiedLogName(data.writer)),
        ))!;
        expect(state.store.pendingTextOperations, isEmpty);
        await stop(tester);
        await start(tester, data.profile, folder: folder, pending: true);
        final reopened = tester.state(find.byType(TasksPage)) as dynamic;
        final recovered = reopened.store.unified as UnifiedHistory;
        expect(recovered.hasPending, isFalse);
        expect(recovered.snapshot.deviceName(data.writer), isNull);
        expect(
          await tester.runAsync(() => folder.read(unifiedLogName(data.writer))),
          partial,
        );
        var recoveryDone = false;
        final recovery = recovered.recoverPrepared().whenComplete(
          () => recoveryDone = true,
        );
        await host.ready(tester, () => recoveryDone);
        await recovery;
        expect(
          await tester.runAsync(() => folder.read(unifiedLogName(data.writer))),
          partial,
        );
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
          'New label',
        );
        await tester.tap(find.text('Save'));
        await host.ready(
          tester,
          () =>
              recovered.snapshot.deviceName(data.writer) == 'New label' &&
              reopened.busy == false,
        );
        expect(recovered.hasPending, isFalse);
        expect(
          recovered.snapshot.records.where(
            (r) =>
                r.writer == data.writer &&
                r.effects.any((e) => e.kind == 'writer.named'),
          ),
          hasLength(1),
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
        final name = h.snapshot.records.first.writer;
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
