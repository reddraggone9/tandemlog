import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import '../integration_test/native_text_fixtures.dart';
import 'section_navigation_host_test.dart' as host;
import 'unified_host_test.dart' as unified;

/// A real local folder without OS watch hints. Only the ordering of normal
/// foreground reconciliation is controlled; all bytes, bounds and native
/// operations are the production implementations.
class _PolledFolder implements LogFolder, BoundedLogFolder {
  _PolledFolder(this.delegate);
  final LocalLogFolder delegate;
  int lists = 0;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() {
    lists++;
    return delegate.list();
  }

  @override
  Future<Uint8List> read(String name) => delegate.read(name);
  @override
  Future<Uint8List> readBounded(String name, int limit) =>
      delegate.readBounded(name, limit);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      delegate.append(name, bytes);
}

class _Peer {
  _Peer(this.profile, this.engine, this.history, this.tasks);
  final LocalProfileDatabase profile;
  final NativeTextEngine engine;
  final UnifiedHistory history;
  final TaskStore tasks;

  static Future<_Peer> open(LocalLogFolder folder, String root) async {
    final profile = await LocalProfileDatabase.open(root);
    final engine = NativeTextEngine(libraryPath: host.nativeHostLibraryPath);
    UnifiedHistory? history;
    TaskStore? tasks;
    try {
      await LocalSettings.initialize(profile);
      final settings = LocalSettings(root, profileDatabase: profile);
      await settings.load();
      await settings.save();
      history = await UnifiedHistory.open(
        folder,
        profile: profile,
        writer: settings.writer,
        textEngine: engine,
        now: () => DateTime.utc(2026, 10, 20, 12),
      );
      tasks = await TaskStore.openUnified(history);
      return _Peer(profile, engine, history, tasks);
    } catch (_) {
      await tasks?.close();
      await history?.close();
      await profile.close();
      engine.dispose();
      rethrow;
    }
  }

  Future<void> close() async {
    await tasks.close();
    await history.close();
    await profile.close();
    engine.dispose();
  }
}

enum _LateNativeSaveCase {
  editedNontext,
  unchangedNontext,
  revertedNontext,
  editedDeleted,
  unchangedDeleted,
  editedCorrupt,
  unchangedCorrupt,
}

enum _Consumer { taskPoll, foodRefresh, foodCommand }

Future<void> _poll(
  WidgetTester tester,
  dynamic state,
  _PolledFolder folder, {
  required bool start,
}) async {
  await host.ready(tester, () => state.syncing == null);
  final before = folder.lists;
  if (start) {
    state.importer.start();
  } else {
    state.importer.request();
  }
  await host.ready(
    tester,
    () => folder.lists > before && state.syncing == null,
  );
}

Future<void> _stopHost(WidgetTester tester) async {
  final resources = host.hostResources(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await host.waitForHostShutdown(tester, resources);
}

void main() {
  final configured = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (configured == null ||
      configured.isEmpty ||
      !File(configured).existsSync()) {
    throw StateError('This regression requires the real native text library.');
  }
  host.nativeHostLibraryPath = File(configured).absolute.path;

  for (final consumer in _Consumer.values) {
    testWidgets(
      'shared Task title paints after ${consumer.name} consumes peer history',
      (tester) async {
        final data = (await tester.runAsync(unified.unifiedFixture))!;
        _Peer? peer;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          // The independent installation writes through its own real protected
          // profile and native Task adapter, never by rewriting shared files.
          final activePeer = peer = (await tester.runAsync(
            () => _Peer.open(
              data.trial.folder,
              '${data.trial.root.path}/refresh-peer-profile',
            ),
          ))!;
          final folder = _PolledFolder(data.trial.folder);
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: data.profile,
              folderFactory: (_) => folder,
              textEngineFactory: host.createHostTextEngine,
              timeSourceFactory: host.createHostTimeSource,
            ),
          );
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          await host.ready(
            tester,
            () =>
                state.store != null &&
                state.foodStore != null &&
                state.busy == false &&
                state.syncing == null &&
                find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          final tasks = state.store as TaskStore;
          final food = state.foodStore as FoodStore;
          expect(identical(tasks.unified, food.unified), isTrue);
          expect(activePeer.history.writer, isNot(tasks.writer));
          final taskId =
              tasks.rows.singleWhere((row) => row['kind'] == 'task')['id']
                  as String;
          final title = find.byKey(ValueKey('task-title-$taskId'));
          expect(title.hitTestable(), findsOneWidget);
          expect(tester.widget<Text>(title).data, 'Synthetic section task');

          if (consumer == _Consumer.foodCommand) {
            tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
              true,
            );
            await host.ready(
              tester,
              () =>
                  find.byType(FoodInventoryPage).evaluate().isNotEmpty &&
                  state.sectionWork == null,
            );
          }
          await host.ready(tester, () => state.syncing == null);
          state.importer.stop();
          const changedTitle = 'Peer changed this shared Task';
          await tester.runAsync(
            () => activePeer.tasks.editNativeFixtureTask(taskId, {
              'title': changedTitle,
            }),
          );
          expect(
            activePeer.tasks.rows.singleWhere(
              (row) => row['id'] == taskId,
            )['title'],
            changedTitle,
          );
          // No automatic notification/poll has consumed the peer write yet.
          expect(
            tasks.rows.singleWhere((row) => row['id'] == taskId)['title'],
            'Synthetic section task',
          );

          if (consumer == _Consumer.foodRefresh) {
            await tester.runAsync(food.refresh);
            expect(
              tasks.rows.singleWhere((row) => row['id'] == taskId)['title'],
              changedTitle,
              reason:
                  'Food must admit the peer edit into the attached Task projection.',
            );
            await _poll(tester, state, folder, start: true);
          } else if (consumer == _Consumer.foodCommand) {
            final page = tester.widget<FoodInventoryPage>(
              find.byType(FoodInventoryPage),
            );
            var commandDone = false;
            Object? commandError;
            StackTrace? commandStack;
            // Prior host queue continuations can belong to FakeAsync. Start
            // real I/O here, then pump both zones until this actual callback
            // completes instead of blocking runAsync on a fake-zone callback.
            await tester.runAsync(() async {
              unawaited(
                Future<void>.sync(
                  () => page.onAdd(
                    const FoodDetails(
                      name: 'Synthetic refresh witness',
                      expiry: '2026-10-21',
                    ),
                    1,
                  ),
                ).then<void>(
                  (_) => commandDone = true,
                  onError: (Object error, StackTrace stack) {
                    commandError = error;
                    commandStack = stack;
                    commandDone = true;
                  },
                ),
              );
            });
            final commandWait = Stopwatch()..start();
            while (!commandDone &&
                commandWait.elapsed < const Duration(seconds: 30)) {
              await tester.runAsync(() => Future<void>.delayed(Duration.zero));
              await tester.pump(const Duration(milliseconds: 30));
            }
            expect(
              commandDone,
              isTrue,
              reason:
                  'The actual Food callback must complete while both zones pump.',
            );
            if (commandError != null) {
              Error.throwWithStackTrace(commandError!, commandStack!);
            }
            await host.ready(
              tester,
              () => state.busy == false && state.syncing == null,
            );
            expect(
              food.state.containers.single.details.name,
              'Synthetic refresh witness',
            );
            expect(
              tasks.rows.singleWhere((row) => row['id'] == taskId)['title'],
              changedTitle,
            );
            tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
              false,
            );
            await host.ready(
              tester,
              () =>
                  find.byType(FoodInventoryPage).evaluate().isEmpty &&
                  state.sectionWork == null,
            );
          } else {
            await _poll(tester, state, folder, start: true);
          }

          // A subsequent unchanged poll must still bring the host's painted
          // Task row to the already-admitted projection, without appending.
          final beforePoll = (await tester.runAsync(
            () => host.canonical(data.trial.folder),
          ))!;
          await _poll(tester, state, folder, start: false);
          expect(
            await tester.runAsync(() => host.canonical(data.trial.folder)),
            beforePoll,
          );
          expect(state.error, isNull);
          expect(state.sharedSafetyError, isNull);
          expect(title.hitTestable(), findsOneWidget);
          expect(
            tester.widget<Text>(title).data,
            changedTitle,
            reason:
                'The actually painted Task title must reflect the peer edit, '
                'even when Food already consumed its shared-history revision.',
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (find.byType(TasksPage).evaluate().isNotEmpty) {
            await _stopHost(tester);
          }
          await tester.runAsync(() async {
            await peer?.close();
            await data.trial.close();
            await data.trial.root.delete(recursive: true);
          });
        }
      },
    );
  }

  for (final lateCase in _LateNativeSaveCase.values) {
    testWidgets(
      'native Save freshly refuses unadmitted peer ${lateCase.name}',
      (tester) async {
        final data = (await tester.runAsync(unified.unifiedFixture))!;
        _Peer? peer;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          final activePeer = peer = (await tester.runAsync(
            () => _Peer.open(
              data.trial.folder,
              '${data.trial.root.path}/late-native-save-peer',
            ),
          ))!;
          final folder = _PolledFolder(data.trial.folder);
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: data.profile,
              folderFactory: (_) => folder,
              textEngineFactory: host.createHostTextEngine,
              timeSourceFactory: host.createHostTimeSource,
            ),
          );
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          await host.ready(
            tester,
            () =>
                state.store != null &&
                state.foodStore != null &&
                state.busy == false &&
                state.syncing == null &&
                find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          final tasks = state.store as TaskStore;
          final taskId =
              tasks.rows.singleWhere((row) => row['kind'] == 'task')['id']
                  as String;
          await tester.tap(find.byKey(ValueKey('task-title-$taskId')));
          final notes = find.byKey(const ValueKey('description'));
          await host.ready(
            tester,
            () =>
                notes.evaluate().isNotEmpty &&
                state.editingText != null &&
                state.syncing == null,
          );
          final controller = tester.widget<TextField>(notes).controller!;
          final originalNotes = controller.text;
          final unchanged = lateCase.name.startsWith('unchanged');
          final reverted = lateCase == _LateNativeSaveCase.revertedNontext;
          final deleted = lateCase.name.endsWith('Deleted');
          final corrupt = lateCase.name.endsWith('Corrupt');
          const localDraft = 'Local draft must survive a late refusal';
          if (!unchanged) {
            await tester.enterText(notes, localDraft);
            if (reverted) await tester.enterText(notes, originalNotes);
            await tester.pumpAndSettle();
          }
          final expectedDraft = unchanged || reverted
              ? originalNotes
              : localDraft;
          final editor = tester.state<TaskEditorState>(find.byType(TaskEditor));
          final textSession = state.editingText;
          if (reverted) {
            expect(
              textSession.hasTextChanges,
              isTrue,
              reason:
                  'Edit then revert must exercise actual no-op result, '
                  'not a guessed pre-Save dirty flag.',
            );
          }
          await host.ready(tester, () => state.syncing == null);
          state.importer.stop();
          final priorRevision = tasks.unified!.snapshot.revision;
          if (corrupt) {
            // Complete invalid record, including LF, on the synthetic peer
            // stream. No application truncation/repair is permitted.
            await tester.runAsync(
              () => data.trial.folder.append(
                '${activePeer.history.writer}.applog',
                Uint8List.fromList([123, 125, 10]),
              ),
            );
          } else if (deleted) {
            await tester.runAsync(
              () => activePeer.tasks.deleteTask(
                taskId,
                expectedTaskSnapshot: null,
                canCommit: () => true,
              ),
            );
          } else {
            final peerRow = activePeer.tasks.rows.singleWhere(
              (row) => row['id'] == taskId,
            );
            await tester.runAsync(
              () => activePeer.tasks.edit(
                taskId,
                {
                  'schedule': {'dueDate': '2026-10-22'},
                },
                tags: List<String>.from(peerRow['tags'] as List? ?? const []),
                observedTagRefs: Map<String, String>.from(
                  peerRow['tagRefs'] as Map? ?? const {},
                ),
              ),
            );
          }
          expect(
            tasks.unified!.snapshot.revision,
            priorRevision,
            reason:
                'No Food refresh/poll/host admission may consume peer '
                'mutation before actual Save.',
          );
          final staleRow = tasks.rows.singleWhere((row) => row['id'] == taskId);
          expect(staleRow['deleted'], isNot(true));
          expect(
            staleRow['schedule'],
            isNot(containsPair('dueDate', '2026-10-22')),
          );
          final beforeSave = (await tester.runAsync(
            () => host.canonical(data.trial.folder),
          ))!;
          final listsBefore = folder.lists;
          // Real editor commit and visible error; not a direct storage call.
          final body =
              tester.state(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget.runtimeType.toString() == '_EditorBody',
                    ),
                  )
                  as dynamic;
          await tester.tap(find.byKey(const ValueKey('task-save-action')));
          await host.ready(
            tester,
            () =>
                body.failure != null &&
                !editor.closeBusy &&
                folder.lists > listsBefore,
          );
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(controller.text, expectedDraft);
          expect(identical(state.editingText, textSession), isTrue);
          expect(textSession.hasPendingReceipt, isFalse);
          if (!corrupt) {
            expect(
              find.textContaining('other details changed. Your draft is kept;'),
              findsOneWidget,
            );
          } else {
            expect(body.failure, isNotEmpty);
            expect(tasks.unified!.safetyFailure, isNotNull);
          }
          expect(
            await tester.runAsync(() => host.canonical(data.trial.folder)),
            beforeSave,
            reason:
                'Late refusal must neither append local history nor '
                'change/repair any peer canonical bytes.',
          );
          if (lateCase == _LateNativeSaveCase.editedNontext) {
            // Rejection occurs after native prepare; an enabled editor must
            // not reject its next keystroke because an unreserved packet froze.
            const continuedDraft = 'Draft remains editable after refusal';
            await tester.enterText(notes, continuedDraft);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(controller.text, continuedDraft);
            expect(textSession.text('description'), continuedDraft);
            expect(
              await tester.runAsync(() => host.canonical(data.trial.folder)),
              beforeSave,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          if (find.byType(TasksPage).evaluate().isNotEmpty) {
            await _stopHost(tester);
          }
          await tester.runAsync(() async {
            await peer?.close();
            await data.trial.close();
            await data.trial.root.delete(recursive: true);
          });
        }
      },
    );
  }

  testWidgets('idle unified host poll scans shared v4 history once', (
    tester,
  ) async {
    final data = (await tester.runAsync(unified.unifiedFixture))!;
    try {
      final folder = _PolledFolder(data.trial.folder);
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: data.profile,
          folderFactory: (_) => folder,
          textEngineFactory: host.createHostTextEngine,
          timeSourceFactory: host.createHostTimeSource,
        ),
      );
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      await host.ready(
        tester,
        () =>
            state.store != null &&
            state.foodStore != null &&
            state.busy == false &&
            state.syncing == null &&
            find.text('Synthetic section task').evaluate().isNotEmpty,
      );
      state.importer.stop();
      final before = (await tester.runAsync(
        () => host.canonical(data.trial.folder),
      ))!;
      final scans = folder.lists;
      await _poll(tester, state, folder, start: true);
      expect(
        folder.lists - scans,
        1,
        reason:
            'One idle host reconciliation must scan the common v4 history once, '
            'rather than independently refreshing Tasks, migration and Food.',
      );
      expect(find.text('Synthetic section task').hitTestable(), findsOneWidget);
      expect(
        await tester.runAsync(() => host.canonical(data.trial.folder)),
        before,
      );
      expect(state.sharedSafetyError, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      if (find.byType(TasksPage).evaluate().isNotEmpty) await _stopHost(tester);
      await tester.runAsync(() async {
        await data.trial.close();
        await data.trial.root.delete(recursive: true);
      });
    }
  });

  testWidgets(
    'Food admission updates Task row behind an owned dirty editor safely',
    (tester) async {
      final data = (await tester.runAsync(unified.unifiedFixture))!;
      _Peer? peer;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        final activePeer = peer = (await tester.runAsync(
          () => _Peer.open(
            data.trial.folder,
            '${data.trial.root.path}/dirty-task-peer',
          ),
        ))!;
        final folder = _PolledFolder(data.trial.folder);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: data.profile,
            folderFactory: (_) => folder,
            textEngineFactory: host.createHostTextEngine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await host.ready(
          tester,
          () =>
              state.store != null &&
              state.foodStore != null &&
              state.busy == false &&
              state.syncing == null &&
              find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        final tasks = state.store as TaskStore,
            food = state.foodStore as FoodStore;
        final taskId =
            tasks.rows.singleWhere((row) => row['kind'] == 'task')['id']
                as String;
        final title = find.byKey(ValueKey('task-title-$taskId'));
        await tester.tap(title);
        final notes = find.byKey(const ValueKey('description'));
        await host.ready(
          tester,
          () =>
              notes.evaluate().isNotEmpty &&
              state.editingText != null &&
              state.syncing == null,
        );
        await tester.enterText(notes, 'Local Task draft must stay');
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(notes).controller!;
        const selection = TextSelection(baseOffset: 6, extentOffset: 16);
        controller.selection = selection;
        final focus = tester
            .widget<EditableText>(
              find.descendant(of: notes, matching: find.byType(EditableText)),
            )
            .focusNode;
        final editor = tester.state<TaskEditorState>(find.byType(TaskEditor));
        final editorKey = state.editorKey;
        final textSession = state.editingText;
        expect(focus.hasFocus, isTrue);
        await host.ready(tester, () => state.syncing == null);
        state.importer.stop();
        const changedTitle = 'Peer title admitted behind dirty editor';
        await tester.runAsync(
          () => activePeer.tasks.editNativeFixtureTask(taskId, {
            'title': changedTitle,
            // A genuine concurrent non-text change must still stop stale Save.
            'schedule': {'dueDate': '2026-10-22'},
          }),
        );
        final before = (await tester.runAsync(
          () => host.canonical(data.trial.folder),
        ))!;
        await tester.runAsync(food.refresh);
        await tester.pumpAndSettle();
        expect(
          tasks.rows.singleWhere((row) => row['id'] == taskId)['title'],
          changedTitle,
        );
        expect(
          tester.widget<Text>(title).data,
          changedTitle,
          reason: 'The row behind the editor must receive shared publication.',
        );
        expect(
          identical(
            tester.state<TaskEditorState>(find.byType(TaskEditor)),
            editor,
          ),
          isTrue,
        );
        expect(identical(state.editorKey, editorKey), isTrue);
        expect(identical(state.editingText, textSession), isTrue);
        expect(
          identical(tester.widget<TextField>(notes).controller, controller),
          isTrue,
        );
        expect(controller.text, 'Local Task draft must stay');
        expect(controller.selection, selection);
        expect(focus.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);

        await tester.tap(find.byKey(const ValueKey('task-save-action')));
        await host.ready(
          tester,
          () => find
              .textContaining(
                'This task’s other details changed. Your draft is kept;',
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(controller.text, 'Local Task draft must stay');
        expect(identical(state.editingText, textSession), isTrue);
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
          reason: 'Stale Save must not overwrite or append the draft.',
        );
        expect(
          tasks.rows.singleWhere((row) => row['id'] == taskId)['schedule'],
          containsPair('dueDate', '2026-10-22'),
        );

        final editorCancel = find.descendant(
          of: find.byType(TaskEditor),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        );
        await tester.tap(editorCancel);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsNothing);
        expect(controller.text, 'Local Task draft must stay');
        expect(
          identical(
            tester.state<TaskEditorState>(find.byType(TaskEditor)),
            editor,
          ),
          isTrue,
        );
        await tester.tap(editorCancel);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        final discard = find.widgetWithText(TextButton, 'Discard');
        expect(discard.hitTestable(), findsOneWidget);
        await tester.tap(discard);
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(tester.widget<Text>(title).data, changedTitle);
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) {
          await _stopHost(tester);
        }
        await tester.runAsync(() async {
          await peer?.close();
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );

  testWidgets(
    'Task-only publication reuses Food state and focused page while hidden',
    (tester) async {
      final data = (await tester.runAsync(unified.unifiedFixture))!;
      _Peer? peer;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        final activePeer = peer = (await tester.runAsync(
          () => _Peer.open(
            data.trial.folder,
            '${data.trial.root.path}/food-visible-peer',
          ),
        ))!;
        await tester.runAsync(() async {
          final seedFood = await FoodStore.openUnified(activePeer.history);
          try {
            await seedFood.add(
              const FoodDetails(
                name: 'Food grouping witness',
                expiry: '2026-10-23',
              ),
              1,
            );
          } finally {
            await seedFood.close();
          }
        });
        final folder = _PolledFolder(data.trial.folder);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: data.profile,
            folderFactory: (_) => folder,
            textEngineFactory: host.createHostTextEngine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await host.ready(
          tester,
          () =>
              state.store != null &&
              state.foodStore != null &&
              state.busy == false &&
              state.syncing == null &&
              find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        final tasks = state.store as TaskStore,
            food = state.foodStore as FoodStore;
        final taskId =
            tasks.rows.singleWhere((row) => row['kind'] == 'task')['id']
                as String;
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(true);
        await host.ready(
          tester,
          () =>
              find.byType(FoodInventoryPage).evaluate().isNotEmpty &&
              state.sectionWork == null &&
              state.syncing == null,
        );
        expect(find.text('Food grouping witness'), findsOneWidget);
        final originalFood = tester
            .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
            .state;
        final page = tester.state<FoodInventoryPageState>(
          find.byType(FoodInventoryPage),
        );
        final search = find.byKey(const ValueKey('food-search'));
        await tester.showKeyboard(search);
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(search).controller!;
        final focus = tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .focusNode;
        await host.ready(tester, () => state.syncing == null);
        state.importer.stop();
        const changedTitle = 'Hidden Task receives peer title';
        await tester.runAsync(
          () => activePeer.tasks.editNativeFixtureTask(taskId, {
            'title': changedTitle,
          }),
        );
        final before = (await tester.runAsync(
          () => host.canonical(data.trial.folder),
        ))!;
        await tester.runAsync(food.refresh);
        await tester.pumpAndSettle();
        expect(
          identical(
            tester
                .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
                .state,
            originalFood,
          ),
          isTrue,
          reason:
              'Task-only admission must reuse the semantic Food slice; '
              'the grouping memo tests prove reuse avoids additional grouping.',
        );
        expect(
          identical(
            tester.state<FoodInventoryPageState>(
              find.byType(FoodInventoryPage),
            ),
            page,
          ),
          isTrue,
        );
        expect(
          identical(tester.widget<TextField>(search).controller, controller),
          isTrue,
        );
        expect(controller.text, isEmpty);
        expect(focus.hasFocus, isTrue);
        expect(find.text('Food grouping witness'), findsOneWidget);
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(false);
        await host.ready(
          tester,
          () =>
              find.byType(FoodInventoryPage).evaluate().isEmpty &&
              state.sectionWork == null,
        );
        expect(
          tester.widget<Text>(find.byKey(ValueKey('task-title-$taskId'))).data,
          changedTitle,
        );
        expect(
          await tester.runAsync(() => host.canonical(data.trial.folder)),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (find.byType(TasksPage).evaluate().isNotEmpty) {
          await _stopHost(tester);
        }
        await tester.runAsync(() async {
          await peer?.close();
          await data.trial.close();
          await data.trial.root.delete(recursive: true);
        });
      }
    },
  );
}
