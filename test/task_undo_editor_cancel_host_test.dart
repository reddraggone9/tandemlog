import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';

import 'section_navigation_host_test.dart' as host;
import 'support/toolbar_button.dart';

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  testWidgets(
    'cancelled dirty editor close re-enables Undo after a guard rebuild',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      host.HostResources? resources;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      try {
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: data.profile,
            textEngineFactory: host.createHostTextEngine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        );
        await host.ready(
          tester,
          () => find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        resources = host.hostResources(tester);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final store = state.store as TaskStore;
        await tester.tap(find.text('Synthetic section task'));
        await host.ready(
          tester,
          () => find.byType(TaskEditor).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Saved local title',
        );
        await tester.tap(find.text('Save changes'));
        await host.ready(
          tester,
          () =>
              find.byType(TaskEditor).evaluate().isEmpty && state.busy == false,
        );
        final undo = find.byKey(const ValueKey('undo-task-action'));
        expect(toolbarButton(tester, undo).onPressed, isNotNull);
        final originalEntry = state.undoHistory.latest;
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        final sequence = store.unified!.physicalSequence;
        await tester.tap(find.text('Saved local title'));
        await host.ready(
          tester,
          () => find.byType(TaskEditor).evaluate().isNotEmpty,
        );
        final notes = find.byKey(const ValueKey('description'));
        await tester.enterText(notes, 'Unsaved notes');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(undo);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        expect(state.closingEditor, isTrue);
        // A real viewport change while the confirmation is open rebuilds the
        // toolbar using the guard. Closing it must invalidate that disabled view.
        tester.view.physicalSize = const Size(1202, 800);
        await tester.pumpAndSettle();
        expect(toolbarButton(tester, undo).onPressed, isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await host.ready(tester, () => state.closingEditor == false);
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Unsaved notes',
        );
        expect(identical(state.undoHistory.latest, originalEntry), isTrue);
        expect(store.unified!.physicalSequence, sequence);
        expect(
          (await tester.runAsync(() => host.canonical(data.folder)))!,
          before,
        );
        expect(
          toolbarButton(tester, undo).onPressed,
          isNotNull,
          reason:
              'Cancel must re-enable Undo without an unrelated later rebuild.',
        );
        await tester.tap(undo);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await host.ready(
          tester,
          () =>
              find.byType(TaskEditor).evaluate().isEmpty &&
              find.text('Synthetic section task').evaluate().isNotEmpty &&
              state.busy == false,
        );
        expect(store.unified!.physicalSequence, sequence + 1);
        expect(state.undoHistory.latest, isNull);
        final row = store.rows.singleWhere((row) => row['kind'] == 'task');
        expect(row['description'], '');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (resources != null) {
          await host.waitForHostShutdown(tester, resources);
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
}
