import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';
import '../integration_test/native_text_fixtures.dart';
import '../integration_test/profile_fixture.dart';
import 'section_navigation_host_test.dart' as host;

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  testWidgets('cold open stays neutral with saved dark theme until admission', (
    tester,
  ) async {
    final data = (await tester.runAsync(host.fixture))!;
    await tester.runAsync(
      () => seedNativeProfile(data.profile, {
        'folder': data.folder.location,
        'user': data.user,
        'appearance': 'dark',
      }),
    );
    final folder = host.FaultingFolder(data.folder)
      ..heldRead = Completer<void>();
    var themeReady = 0;
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: data.profile,
        folderFactory: (_) => folder,
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
        onAppearanceReady: () => themeReady++,
      ),
    );
    await host.ready(tester, () => folder.reading, settle: false);
    expect(find.byKey(const ValueKey('workspace-opening')), findsOneWidget);
    expect(find.textContaining('needs attention'), findsNothing);
    expect(find.textContaining('create a data folder'), findsNothing);
    expect(themeReady, 1);
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('workspace-opening'))),
      ).brightness,
      Brightness.dark,
    );
    folder.heldRead!.complete();
    await host.ready(
      tester,
      () => find.text('Synthetic section task').evaluate().isNotEmpty,
    );
    final resources = host.hostResources(tester);
    await tester.pumpWidget(const SizedBox());
    await host.waitForHostShutdown(tester, resources);
    await tester.runAsync(() => data.root.delete(recursive: true));
  });

  testWidgets(
    'bulk draft rebases unrelated changes, diverged selection offers working review',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      final target = const Uuid().v4(), unrelated = const Uuid().v4();
      await tester.runAsync(() async {
        final seed = await openNativeFixtureStore(
          data.folder,
          '${data.root.path}/seed-more',
          nativeLibraryPath: host.nativeHostLibraryPath,
        );
        try {
          for (final (id, title) in [
            (target, 'Second selected target'),
            (unrelated, 'Unrelated target'),
          ]) {
            await seed.createNativeFixtureTask(id, {
              'title': title,
              'description': '',
              'assignee': data.user,
            });
          }
        } finally {
          await seed.close();
        }
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: data.profile,
          textEngineFactory: host.createHostTextEngine,
          timeSourceFactory: host.createHostTimeSource,
        ),
      );
      await host.ready(
        tester,
        () => find.text('Second selected target').evaluate().isNotEmpty,
      );
      final resources = host.hostResources(tester);
      final dynamic page = tester.state(find.byType(TasksPage));
      final store = page.store as TaskStore;
      // The store lives in the test's fake zone, so its continuations need
      // pumps; awaiting a command inside runAsync alone never completes.
      Future<void> commandWhilePumping(String id, String due) async {
        var done = false;
        final command = store
            .command(id, 'task.edited', {
              'schedule': {'dueDate': due},
            })
            .whenComplete(() => done = true);
        await host.ready(tester, () => done, settle: false);
        await command;
      }

      try {
        await tester.longPress(find.text('Synthetic section task'));
        await host.ready(tester, () => page.selectedTasks.length == 1);
        await tester.tap(find.text('Second selected target'));
        await host.ready(
          tester,
          () => find.byType(BulkTaskEditor).evaluate().isNotEmpty,
        );
        final editorKey = page.bulkEditorKey;
        tester
                .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                .controller!
                .text =
            '2026-10-23';
        await tester.pump();
        await commandWhilePumping(unrelated, '2026-10-24');
        await host.ready(tester, () => page.bulkSnapshot == store.taskSnapshot);
        expect(page.bulkConflict, isFalse);
        expect(identical(page.bulkEditorKey, editorKey), isTrue);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('dueDate')))
              .controller!
              .text,
          '2026-10-23',
        );
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await commandWhilePumping(target, '2026-10-25');
        await host.ready(tester, () => page.bulkConflict == true);
        expect(find.text('Review selection'), findsOneWidget);
        expect(find.text('Edit 2 tasks'), findsNothing);
        // This draft cannot claim to save against a changed target.
        final action = find.byKey(const ValueKey('task-save-action'));
        expect(tester.widget<ValidationActionButton>(action).enabled, isFalse);
        await tester.tap(find.text('Review current selection'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
        await tester.tap(find.text('Discard'));
        await host.ready(
          tester,
          () =>
              page.bulkConflict == false &&
              find.text('Edit 2 tasks').evaluate().isNotEmpty,
        );
        final after = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        expect(
          after,
          isNot(before),
          reason: 'Only the intentional target command was persisted',
        );
        final raw = store.unified!.snapshot.records.last.effects;
        expect(raw.where((e) => e.task != null).map((e) => e.task!.type), [
          'task.edited',
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  group('review current selection after a target leaves', () {
    Future<void> scenario(
      WidgetTester tester,
      Future<void> Function(
        Future<void> Function(String, String, Map<String, dynamic>) command,
        String first,
        String second,
      )
      change,
      Future<void> Function(dynamic page, String first, String second)
      expectOutcome, {
      bool cancelFirst = false,
    }) async {
      final data = (await tester.runAsync(host.fixture))!;
      final second = const Uuid().v4();
      await tester.runAsync(() async {
        final seed = await openNativeFixtureStore(
          data.folder,
          '${data.root.path}/seed-more',
          nativeLibraryPath: host.nativeHostLibraryPath,
        );
        try {
          await seed.createNativeFixtureTask(second, {
            'title': 'Second selected target',
            'description': '',
            'assignee': data.user,
          });
        } finally {
          await seed.close();
        }
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: data.profile,
          textEngineFactory: host.createHostTextEngine,
          timeSourceFactory: host.createHostTimeSource,
        ),
      );
      await host.ready(
        tester,
        () => find.text('Second selected target').evaluate().isNotEmpty,
      );
      final resources = host.hostResources(tester);
      final dynamic page = tester.state(find.byType(TasksPage));
      final store = page.store as TaskStore;
      final first =
          store.rows.firstWhere(
                (row) => row['title'] == 'Synthetic section task',
              )['id']
              as String;
      Future<void> command(
        String id,
        String type,
        Map<String, dynamic> body,
      ) async {
        var done = false;
        final work = store
            .command(id, type, body)
            .whenComplete(() => done = true);
        await host.ready(tester, () => done, settle: false);
        await work;
      }

      try {
        await tester.longPress(find.text('Synthetic section task'));
        await host.ready(tester, () => page.selectedTasks.length == 1);
        await tester.tap(find.text('Second selected target'));
        await host.ready(
          tester,
          () => find.byType(BulkTaskEditor).evaluate().isNotEmpty,
        );
        tester
                .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                .controller!
                .text =
            '2026-10-23';
        await tester.pump();
        await change(command, first, second);
        await host.ready(tester, () => page.bulkConflict == true);
        expect(
          tester
              .widget<ValidationActionButton>(
                find.byKey(const ValueKey('task-save-action')),
              )
              .enabled,
          isFalse,
        );
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        if (cancelFirst) {
          await tester.tap(find.text('Review current selection'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();
          expect(page.bulkConflict, isTrue);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('dueDate')))
                .controller!
                .text,
            '2026-10-23',
          );
        }
        await tester.tap(find.text('Review current selection'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard'));
        await host.ready(tester, () => page.bulkConflict == false);
        await tester.pumpAndSettle();
        await expectOutcome(page, first, second);
        expect(
          await tester.runAsync(() => host.canonical(data.folder)),
          before,
          reason: 'Discarding the stale draft writes nothing',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    }

    testWidgets('deleted target reopens the surviving task; Cancel keeps it', (
      tester,
    ) async {
      await scenario(
        tester,
        (command, first, second) => command(second, 'task.deleted', {}),
        (page, first, second) async {
          expect(page.selectedTasks, {first});
          expect(find.byType(BulkTaskEditor), findsNothing);
          await host.ready(tester, () => page.editingTask?['id'] == first);
        },
        cancelFirst: true,
      );
    });

    testWidgets('target filtered out of view is not reopened', (tester) async {
      await scenario(
        tester,
        (command, first, second) => command(second, 'task.edited', {
          'schedule': {'startDate': '2099-01-01'},
        }),
        (page, first, second) async {
          expect(page.selectedTasks, {first});
          await host.ready(tester, () => page.editingTask?['id'] == first);
        },
      );
    });

    testWidgets('all targets gone clears selection with a clear outcome', (
      tester,
    ) async {
      await scenario(
        tester,
        (command, first, second) async {
          await command(first, 'task.deleted', {});
          await command(second, 'task.deleted', {});
        },
        (page, first, second) async {
          expect(page.selectedTasks, isEmpty);
          expect(page.selecting, isFalse);
          expect(find.byType(BulkTaskEditor), findsNothing);
          expect(
            find.text('The selected tasks are no longer in this view.'),
            findsOneWidget,
          );
        },
      );
    });
  });

  testWidgets('recurring completion names the persisted successor date', (
    tester,
  ) async {
    final data = (await tester.runAsync(host.fixture))!;
    final repeat = const Uuid().v4();
    await tester.runAsync(() async {
      final seed = await openNativeFixtureStore(
        data.folder,
        '${data.root.path}/seed-more',
        nativeLibraryPath: host.nativeHostLibraryPath,
      );
      try {
        await seed.createNativeFixtureTask(repeat, {
          'title': 'Constrained repeat',
          'description': '',
          'assignee': data.user,
          'schedule': {
            'dueDate': '2026-10-02',
            'recurrence': 'every 3 months on the 1st friday',
          },
        });
      } finally {
        await seed.close();
      }
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: data.profile,
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    await host.ready(
      tester,
      () => find.text('Constrained repeat').evaluate().isNotEmpty,
    );
    final resources = host.hostResources(tester);
    try {
      final check = find.descendant(
        of: find.byTooltip('Complete Constrained repeat'),
        matching: find.byType(Checkbox),
      );
      await tester.tap(check);
      await host.ready(
        tester,
        () => find.textContaining('Next occurrence kept').evaluate().isNotEmpty,
        settle: false,
      );
      expect(
        find.text('Completed 1 task. Next occurrence kept, due 2027-01-01.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await host.waitForHostShutdown(tester, resources);
      await tester.runAsync(() => data.root.delete(recursive: true));
    }
  });
}
