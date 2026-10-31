import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';
import '../integration_test/profile_fixture.dart';
import 'section_navigation_host_test.dart' as host;

void main() => registerSelectedRecurringCompletionTests();

void registerSelectedRecurringCompletionTests({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final keepAnother in [false, true]) {
    testWidgets('compact selected recurrence completion prunes only hidden row '
        'keepAnother=$keepAnother', (tester) async {
      final repeating = const Uuid().v4();
      final data = (await tester.runAsync(() async {
        final data = await host.fixture();
        final seed = await openNativeFixtureStore(
          data.folder,
          '${data.root.path}/recurrence',
          nativeLibraryPath: host.nativeHostLibraryPath,
        );
        try {
          await seed.createNativeFixtureTask(repeating, {
            'title': 'Selected repeating task',
            'description': '',
            'assignee': data.user,
            'schedule': {
              'startDate': '2026-10-12',
              'dueDate': '2026-10-12',
              'recurrence': 'every day',
            },
          });
          await seed.createNativeFixtureTask(const Uuid().v4(), {
            'title': 'Next visible task',
            'description': '',
            'assignee': data.user,
          });
        } finally {
          await seed.close();
        }
        await seedNativeProfile(data.profile, {
          'folder': data.folder.location,
          'user': data.user,
          'appearance': 'dark',
        });
        return data;
      }))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 850);
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
        () => find.text('Selected repeating task').evaluate().isNotEmpty,
      );
      final resources = host.hostResources(tester);
      final dynamic page = tester.state(find.byType(TasksPage));
      try {
        // Native GTK must process the first requested window size before
        // deriving pointer coordinates (the host-only binding is immediate).
        await capture?.call(tester, 'recurring-warmup-not-evidence');
        await host.ready(tester, () => !page.busy && page.syncing == null);
        await tester.longPress(find.text('Selected repeating task'));
        await host.ready(tester, () => page.selectedTasks.contains(repeating));
        if (keepAnother) {
          await tester.tap(find.text('Synthetic section task'));
          await host.ready(tester, () => page.selectedTasks.length == 2);
        }
        await capture?.call(
          tester,
          'recurring-${keepAnother ? 2 : 1}-selected',
        );
        final others = Set<String>.from(page.selectedTasks)..remove(repeating);
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey('task-row-$repeating')),
            matching: find.byType(TaskCompletionCheckbox),
          ),
        );
        try {
          await host.ready(
            tester,
            () =>
                !page.busy &&
                find.text('Selected repeating task').evaluate().isEmpty,
          );
        } catch (_) {
          debugPrint(
            'RECURRING_COMPLETION_DIAGNOSTIC busy=${page.busy} '
            'error=${page.error} safety=${page.sharedSafetyError} '
            'selected=${page.selectedTasks} rows=${page.store.rows}',
          );
          await capture?.call(
            tester,
            'recurring-${keepAnother ? 2 : 1}-failed',
          );
          rethrow;
        }
        expect(
          page.selectedTasks,
          others,
          reason: 'Hidden completed occurrence is no longer selected',
        );
        expect(page.selecting, keepAnother);
        expect(
          find.byType(TaskEditor),
          findsNothing,
          reason: 'A hidden selection editor must not reopen after completion',
        );
        await capture?.call(
          tester,
          'recurring-${keepAnother ? 2 : 1}-completed',
        );
        // Simulate a retained editor snapshot (for example after an incoming
        // change) to independently exercise stale-ID recovery on the next tap.
        page.selectedTasks.add(repeating);
        await tester.tap(find.text('Next visible task'));
        await host.ready(
          tester,
          () =>
              page.selectedTasks.length == (keepAnother ? 2 : 1) &&
              !page.selectedTasks.contains(repeating),
        );
        expect(page.selectedTasks.containsAll(others), isTrue);
        await capture?.call(tester, 'recurring-${keepAnother ? 2 : 1}-next');
        expect(
          find.textContaining('Some selected tasks are no longer visible'),
          findsNothing,
        );
        expect(page.selectedTasks.contains(repeating), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    });
  }
}
