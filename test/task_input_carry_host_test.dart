import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'section_navigation_host_test.dart' as host;

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  testWidgets(
    'mode toggles carry current value and pause query without writing',
    (tester) async {
      final data = (await tester.runAsync(() => host.fixture()))!;
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
      final resources = host.hostResources(tester);
      try {
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        final input = find.byKey(const ValueKey('task-search'));
        await tester.enterText(input, 'Unsubmitted wrong-mode text');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        expect(
          tester.widget<TextField>(capture).controller!.text,
          'Unsubmitted wrong-mode text',
        );
        final dynamic state = tester.state(find.byType(TasksPage));
        expect(state.searchQuery, isEmpty);
        expect(find.text('Synthetic section task'), findsOneWidget);
        await tester.enterText(capture, 'Another unsubmitted draft');
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Another unsubmitted draft',
        );
        expect(state.searchQuery, 'Another unsubmitted draft');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Another unsubmitted draft',
        );
        expect(find.text('Synthetic section task'), findsNothing);
        expect(
          (await tester.runAsync(() => host.canonical(data.folder)))!,
          before,
        );
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(capture).controller!.text, isEmpty);
        await tester.enterText(
          capture,
          'First carried task\nSecond carried task',
        );
        final controller = tester.widget<TextField>(capture).controller!;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'First carried task\nSecond carried task',
        );
        expect(
          tester.widget<TextField>(input).controller!.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        await host.ready(
          tester,
          () => state.capture.text.isNotEmpty && !state.busy,
        );
        await tester.tap(find.byKey(const ValueKey('capture-add')));
        await host.ready(
          tester,
          () =>
              state.capture.text.isEmpty &&
              state.pendingCapture.isEmpty &&
              !state.busy,
        );
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        expect(find.text('First carried task'), findsOneWidget);
        expect(find.text('Second carried task'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
}
