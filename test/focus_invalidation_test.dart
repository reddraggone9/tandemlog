import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/expiration_presentation.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/unified_history.dart';

import 'food_editor_pane_test.dart' as pane;
import 'section_navigation_host_test.dart' as host;

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Finder _pageScaffold(Type page) => find
    .descendant(of: find.byType(page), matching: find.byType(Scaffold))
    .first;

FocusNode _controlFocus(WidgetTester tester, Finder control) {
  final icon = find.descendant(of: control, matching: find.byType(Icon)).first;
  var node = Focus.of(tester.element(icon));
  // Food's popup owns focus outside its ignored outlined visual trigger.
  while (!node.canRequestFocus || node is FocusScopeNode) {
    node = node.parent!;
  }
  expect(node.canRequestFocus, isTrue);
  return node;
}

FocusNode _editableFocus(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode;

Future<void> _focus(WidgetTester tester, FocusNode node) async {
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(node.hasFocus, isTrue);
}

Map<ShortcutActivator, VoidCallback> _hostBindings(WidgetTester tester) =>
    tester
        .widget<CallbackShortcuts>(
          find
              .ancestor(
                of: _pageScaffold(TasksPage),
                matching: find.byType(CallbackShortcuts),
              )
              .first,
        )
        .bindings;

Future<void> _ctrlZ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> _stopImporter(WidgetTester tester, dynamic state) async {
  // stop() is synchronous: prevent new polls, then drain the actual in-flight
  // reconciliation with the established pump-and-poll helper. A Future created
  // in the widget FakeAsync zone must not be awaited inside runAsync.
  state.importer.stop();
  await host.ready(tester, () => state.syncing == null && state.busy == false);
}

Future<void> _stopHost(WidgetTester tester) async {
  if (find.byType(TasksPage).evaluate().isEmpty) return;
  final resources = host.hostResources(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await host.waitForHostShutdown(tester, resources);
}

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (library == null || library.isEmpty || !File(library).existsSync()) {
    throw StateError('Focus host regression requires the real native library.');
  }
  host.nativeHostLibraryPath = File(library).absolute.path;

  testWidgets(
    'Task parent ignores same editable classification but updates shortcuts',
    (tester) async {
      _viewport(tester);
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
        await _stopImporter(tester, state);
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        final add = _controlFocus(
          tester,
          find.byKey(const ValueKey('open-capture')),
        );
        final filter = _controlFocus(
          tester,
          find.byKey(const ValueKey('task-filter')),
        );
        await _focus(tester, add);
        final buttonScaffold = tester.widget<Scaffold>(
          _pageScaffold(TasksPage),
        );
        await _focus(tester, filter);
        expect(
          tester.widget<Scaffold>(_pageScaffold(TasksPage)),
          same(buttonScaffold),
          reason:
              'Button focus paints locally without rebuilding the Task page.',
        );

        await tester.tap(find.text('Synthetic section task'));
        await host.ready(
          tester,
          () => find.byType(TaskEditor).evaluate().isNotEmpty,
        );
        final title = find.byKey(const ValueKey('title'));
        final notes = find.byKey(const ValueKey('description'));
        await _focus(tester, _editableFocus(tester, title));
        final fieldScaffold = tester.widget<Scaffold>(_pageScaffold(TasksPage));
        expect(
          _hostBindings(tester).containsKey(
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
          ),
          isFalse,
        );
        await _focus(tester, _editableFocus(tester, notes));
        expect(
          tester.widget<Scaffold>(_pageScaffold(TasksPage)),
          same(fieldScaffold),
          reason:
              'Moving between attached editable fields preserves parent widget identity.',
        );
        expect(
          _hostBindings(tester).containsKey(
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
          ),
          isFalse,
        );
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        await _focus(
          tester,
          _controlFocus(tester, find.byKey(const ValueKey('task-filter'))),
        );
        expect(
          tester.widget<Scaffold>(_pageScaffold(TasksPage)),
          isNot(same(fieldScaffold)),
        );
        expect(
          _hostBindings(tester).containsKey(
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
          ),
          isTrue,
        );
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(() => host.canonical(data.folder)),
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _stopHost(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'live editable focus blocks stale Task Undo and CtrlZ preserves task history',
    (tester) async {
      _viewport(tester);
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
        await _stopImporter(tester, state);
        await tester.tap(find.text('Synthetic section task'));
        await host.ready(
          tester,
          () => find.byType(TaskEditor).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Focus edit saved',
        );
        await tester.tap(find.text('Save changes'));
        await host.ready(
          tester,
          () =>
              find.byType(TaskEditor).evaluate().isEmpty && state.busy == false,
        );
        final history = state.store.unified as UnifiedHistory;
        final afterSave = history.physicalSequence;
        expect(find.text('Focus edit saved'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        await tester.enterText(capture, 'Unsubmitted local text');
        await tester.pumpAndSettle();
        final button = _controlFocus(
          tester,
          find.byKey(const ValueKey('open-search')),
        );
        await _focus(tester, button);
        final staleUndo = _hostBindings(
          tester,
        )[const SingleActivator(LogicalKeyboardKey.keyZ, control: true)]!;
        _editableFocus(tester, capture).requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        // The old rendered callback must consult live focus even before a build.
        staleUndo();
        await tester.pumpAndSettle();
        await _ctrlZ(tester);
        await tester.pumpAndSettle();
        expect(history.physicalSequence, afterSave);
        expect(find.text('Focus edit saved'), findsOneWidget);
        expect(state.undoHistory.latest, isNotNull);

        await _focus(tester, button);
        await _ctrlZ(tester);
        await host.ready(
          tester,
          () =>
              find.text('Synthetic section task').evaluate().isNotEmpty &&
              state.busy == false,
        );
        expect(
          history.physicalSequence,
          afterSave + 1,
          reason:
              'Exactly one Task Undo is allowed after leaving editable focus.',
        );
        expect(state.undoHistory.latest, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _stopHost(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'Food same-class focus preserves parent and editor insets stay live',
    (tester) async {
      var writes = 0;
      await pane.mountFoodPane(
        tester,
        onAdd: (_, _) => writes++,
        onDetails: (_, _, _, _) => writes++,
        onRemove: (_) => writes++,
      );
      final add = _controlFocus(tester, find.byTooltip('Add food'));
      final filter = _controlFocus(
        tester,
        find.byKey(const ValueKey('food-filter')),
      );
      await _focus(tester, add);
      final buttonScaffold = tester.widget<Scaffold>(
        _pageScaffold(FoodInventoryPage),
      );
      await _focus(tester, filter);
      expect(
        tester.widget<Scaffold>(_pageScaffold(FoodInventoryPage)),
        same(buttonScaffold),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text('More filters\u2026'),
        findsOneWidget,
        reason: 'The retained button focus still activates its actual menu.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pane beans 1'));
      await tester.pumpAndSettle();
      final name = pane.foodField('Food name');
      final size = pane.foodField('Container size');
      await _focus(tester, _editableFocus(tester, name));
      final fieldScaffold = tester.widget<Scaffold>(
        _pageScaffold(FoodInventoryPage),
      );
      await _focus(tester, _editableFocus(tester, size));
      expect(
        tester.widget<Scaffold>(_pageScaffold(FoodInventoryPage)),
        same(fieldScaffold),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Scaffold>(_pageScaffold(FoodInventoryPage))
            .resizeToAvoidBottomInset,
        isTrue,
      );
      expect(tester.getRect(pane.foodAction).bottom, lessThanOrEqualTo(650));
      final insetScaffold = tester.widget<Scaffold>(
        _pageScaffold(FoodInventoryPage),
      );
      await _focus(tester, _editableFocus(tester, name));
      expect(
        tester.widget<Scaffold>(_pageScaffold(FoodInventoryPage)),
        same(insetScaffold),
        reason:
            'Ordinary MediaQuery rebuild synchronizes the focus classification.',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(FoodEditor), findsNothing);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Food expiry still invalidates with unchanged focus and busy controls remain guarded',
    (tester) async {
      _viewport(tester);
      var now = DateTime(2026, 10, 17, 23, 59, 59), writes = 0, busy = false;
      late StateSetter update;
      final food = pane.paneFoods();
      final colors = ColorScheme.fromSeed(seedColor: const Color(0xff267461));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: colors, platform: TargetPlatform.linux),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return FoodInventoryPage(
                state: food,
                now: () => now,
                busy: busy,
                onAdd: (_, _) => writes++,
                onRemove: (_) => writes++,
                onRestore: (_) => writes++,
                onDetails: (_, _, _, _) => writes++,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _focus(tester, _controlFocus(tester, find.byTooltip('Add food')));
      final before = tester
          .widget<Text>(find.text('2026-10-20').first)
          .style!
          .color;
      final beforeScaffold = tester.widget<Scaffold>(
        _pageScaffold(FoodInventoryPage),
      );
      now = DateTime(2026, 10, 18);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final after = tester
          .widget<Text>(find.text('2026-10-20').first)
          .style!
          .color;
      expect(after, foodExpiryColor('2026-10-20', now, colors));
      expect(after, isNot(before));
      expect(
        tester.widget<Scaffold>(_pageScaffold(FoodInventoryPage)),
        isNot(same(beforeScaffold)),
        reason:
            'The expiration listener always invalidates independently of focus.',
      );

      update(() => busy = true);
      await tester.pump(); // Do not wait for an indeterminate busy animation.
      final add = find.byTooltip('Add food');
      final disabled = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: add,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        ),
      );
      expect(disabled.onPressed, isNull);
      await tester.tap(add, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(FoodEditor), findsNothing);
      update(() => busy = false);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add food'));
      await tester.pumpAndSettle();
      expect(find.byType(FoodEditor), findsOneWidget);
      expect(writes, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
