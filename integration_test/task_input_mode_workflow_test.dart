import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show filterChoice, waitForUi;
import 'food_production_workflow_test.dart' show switchSection;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskInputModeTests();
}

void registerTaskInputModeTests() {
  for (final variant in const [
    (width: 1200.0, scale: 1.0, theme: 'dark'),
    (width: 1200.0, scale: 2.0, theme: 'light'),
    (width: 390.0, scale: 1.0, theme: 'light'),
    (width: 320.0, scale: 2.5, theme: 'dark'),
  ]) {
    testWidgets(
      'Search/Add clears explicit outgoing input and captures repeatedly ${variant.width} x${variant.scale}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('task-input-mode-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/seed',
        );
        final user = const Uuid().v4();
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createTasks({
          const Uuid().v4(): 'Reference task',
          const Uuid().v4(): 'Other task',
        }, user);
        await seed.close();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': variant.theme,
          }),
        );
        tester.view.physicalSize = Size(variant.width, 850);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        try {
          await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
          await waitForUi(
            tester,
            () => find.text('Reference task').evaluate().isNotEmpty,
          );
          final input = find.byKey(const ValueKey('task-search'));
          final capture = find.widgetWithText(TextField, 'What needs doing?');
          expect(input, findsOneWidget);
          expect(capture, findsNothing);
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
          expect(find.text('Search tasks'), findsOneWidget);
          final headerAction = find.byKey(const ValueKey('open-capture'));
          final actionRect = tester.getRect(headerAction);
          expect(actionRect.width, greaterThanOrEqualTo(48));
          expect(actionRect.height, greaterThanOrEqualTo(48));
          expect(actionRect.right, lessThanOrEqualTo(variant.width));
          await captureNativeFixtureUi(
            tester,
            'input-${variant.theme}-${variant.width}-${variant.scale}-search',
          );
          await tester.enterText(input, 'Reference');
          await waitForUi(
            tester,
            () => find.text('Other task').evaluate().isEmpty,
          );
          final dynamic state = tester.state(find.byType(TasksPage));
          for (var flip = 0; flip < 3; flip++) {
            await tester.tap(find.byKey(const ValueKey('open-capture')));
            await tester.pumpAndSettle();
            await waitForUi(
              tester,
              () => find.text('Other task').evaluate().isNotEmpty,
            );
            expect(input, findsNothing);
            expect(capture, findsOneWidget);
            expect(state.search.text, isEmpty);
            expect(state.searchQuery, isEmpty);
            expect(
              tester.widget<TextField>(capture).focusNode!.hasFocus,
              isTrue,
            );
            await tester.enterText(capture, 'Discarded unfinished $flip');
            await tester.tap(find.byKey(const ValueKey('open-search')));
            await tester.pumpAndSettle();
            expect(capture, findsNothing);
            expect(state.capture.text, isEmpty);
            expect(tester.widget<TextField>(input).controller!.text, isEmpty);
            expect(find.text('Unsaved changes'), findsNothing);
          }
          await filterChoice(tester, 'Completed');
          expect(input.hitTestable(), findsOneWidget);
          expect(state.showCompleted, isTrue);
          await tester.enterText(input, 'Reference');
          await waitForUi(
            tester,
            () => find.text('Reference task').evaluate().isNotEmpty,
          );
          await tester.tap(find.byKey(const ValueKey('open-capture')));
          await tester.pumpAndSettle();
          expect(state.showCompleted, isTrue);
          expect(state.searchQuery, isEmpty);
          expect(capture.hitTestable(), findsOneWidget);
          expect(find.text('Reference task'), findsNothing);
          await tester.enterText(capture, 'Captured one\nCaptured two');
          await tester.tap(find.byKey(const ValueKey('capture-add')));
          await waitForUi(
            tester,
            () => state.pendingCapture.isEmpty && !state.busy,
          );
          expect(capture, findsOneWidget);
          expect(state.capture.text, isEmpty);
          expect(tester.widget<TextField>(capture).focusNode!.hasFocus, isTrue);
          await tester.enterText(capture, 'Captured three');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await waitForUi(
            tester,
            () => state.pendingCapture.isEmpty && !state.busy,
          );
          expect(capture, findsOneWidget);
          final titles = (state.store.rows as List)
              .where((r) => r['kind'] == 'task')
              .map((r) => r['title'])
              .toList();
          for (final title in [
            'Captured one',
            'Captured two',
            'Captured three',
          ]) {
            expect(titles.where((value) => value == title), hasLength(1));
          }
          expect(
            titles.any(
              (value) => value.toString().startsWith('Discarded unfinished'),
            ),
            isFalse,
          );
          await captureNativeFixtureUi(
            tester,
            'input-${variant.theme}-${variant.width}-${variant.scale}-add',
          );
          await tester.tap(find.byKey(const ValueKey('open-search')));
          await tester.pumpAndSettle();
          expect(state.showCompleted, isTrue);
          await switchSection(tester, food: true);
          await switchSection(tester, food: false);
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
