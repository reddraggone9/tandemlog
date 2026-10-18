import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'section_navigation_host_test.dart' as host;
import 'support/toolbar_button.dart';

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final blank in ['', ' \t \n  \n ']) {
    final kind = blank.isEmpty ? 'empty' : 'whitespace';
    testWidgets(
      'blank capture is inactive and Enter preserves draft focus: $kind',
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
          await tester.tap(find.byKey(const ValueKey('open-capture')));
          await tester.pumpAndSettle();
          final field = find.widgetWithText(TextField, 'What needs doing?');
          final add = find.byKey(const ValueKey('capture-add'));
          await tester.enterText(field, blank);
          await tester.pumpAndSettle();
          final before = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          final input = tester.widget<TextField>(field);
          expect(input.decoration!.suffixIcon, isNotNull);
          expect(toolbarButton(tester, add).onPressed, isNull);
          expect(input.focusNode!.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          input.onSubmitted!(blank);
          await tester.pumpAndSettle();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(input.controller!.text, blank);
          expect(input.focusNode!.hasFocus, isTrue);
          expect(tester.testTextInput.isVisible, isTrue);
          expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
          expect(toolbarButton(tester, add).tooltip, 'Add tasks');
          expect(
            find.descendant(of: add, matching: find.text('Review errors')),
            findsNothing,
          );
          expect(state.pendingCapture, isEmpty);
          expect(
            (await tester.runAsync(() => host.canonical(data.folder)))!,
            before,
          );
          await tester.enterText(field, 'Ready to capture');
          await tester.pumpAndSettle();
          expect(toolbarButton(tester, add).onPressed, isNotNull);
          await tester.enterText(field, blank);
          await tester.pumpAndSettle();
          expect(toolbarButton(tester, add).onPressed, isNull);
          expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
          await tester.enterText(field, 'x' * 501);
          await tester.pumpAndSettle();
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(field).decoration!.errorText,
            'Keep each task title to 500 characters or fewer.',
          );
          await tester.enterText(field, blank);
          await tester.pumpAndSettle();
          expect(toolbarButton(tester, add).onPressed, isNull);
          expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
          expect(
            find.descendant(of: add, matching: find.text('Review errors')),
            findsNothing,
          );
          expect(state.pendingCapture, isEmpty);
          expect(
            (await tester.runAsync(() => host.canonical(data.folder)))!,
            before,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await host.waitForHostShutdown(tester, resources);
          await tester.runAsync(() => data.root.delete(recursive: true));
        }
      },
    );
  }
}
