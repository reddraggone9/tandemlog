import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';

import 'section_navigation_host_test.dart' as host;

Future<void> _stopHost(WidgetTester tester) async {
  if (find.byType(TasksPage).evaluate().isEmpty) return;
  final resources = host.hostResources(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await host.waitForHostShutdown(tester, resources);
}

Future<void> _saveTitle(
  WidgetTester tester,
  dynamic state,
  String from,
  String to,
) async {
  await tester.tap(find.text(from));
  await host.ready(tester, () => find.byType(TaskEditor).evaluate().isNotEmpty);
  await tester.enterText(find.byKey(const ValueKey('title')), to);
  await tester.tap(find.text('Save changes'));
  await host.ready(
    tester,
    () => find.byType(TaskEditor).evaluate().isEmpty && state.busy == false,
  );
  expect(find.text(to), findsOneWidget);
}

Future<void> _undo(WidgetTester tester, dynamic state, String restored) async {
  await tester.tap(find.byKey(const ValueKey('undo-task-action')));
  await host.ready(
    tester,
    () => find.text(restored).evaluate().isNotEmpty && state.busy == false,
  );
}

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (library == null || library.isEmpty || !File(library).existsSync()) {
    throw StateError('Text Undo host regression requires the native library.');
  }
  host.nativeHostLibraryPath = File(library).absolute.path;

  testWidgets(
    'Task Undo of a text save releases its native Undo owner immediately',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = (await tester.runAsync(() => host.fixture()))!;
      try {
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: data.profile,
            textEngineFactory: host.createHostTextEngine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        );
        await host.ready(tester, () {
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          return state.store != null && state.busy == false;
        });
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        state.importer.stop();
        await host.ready(
          tester,
          () => state.syncing == null && state.busy == false,
        );
        final store = state.store as TaskStore;
        final operations = store.retainedNativeTextOperationCount;
        final fields = store.retainedNativeUndoFieldCount;

        await _saveTitle(
          tester,
          state,
          'Synthetic section task',
          'First saved title',
        );
        await _saveTitle(
          tester,
          state,
          'First saved title',
          'Second saved title',
        );
        expect(store.retainedNativeTextOperationCount, operations + 2);
        expect(store.retainedNativeUndoFieldCount, fields + 1);

        await _undo(tester, state, 'First saved title');
        expect(
          store.retainedNativeTextOperationCount,
          operations + 1,
          reason: 'The undone save can no longer be undone; release it.',
        );
        expect(
          store.retainedNativeUndoFieldCount,
          fields + 1,
          reason: 'The older save still owns the shared field document.',
        );

        await _undo(tester, state, 'Synthetic section task');
        expect(store.retainedNativeTextOperationCount, operations);
        expect(
          store.retainedNativeUndoFieldCount,
          fields,
          reason:
              'Released owners are no longer re-projected on every refresh.',
        );
        expect(state.undoHistory.latest, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _stopHost(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
}
