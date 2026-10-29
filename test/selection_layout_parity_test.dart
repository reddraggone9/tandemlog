import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_entry_area.dart';
import 'package:tandemlog/presentation/task_editor.dart';

import '../integration_test/native_text_fixtures.dart';
import '../integration_test/profile_fixture.dart';
import 'food_editor_pane_test.dart' show mountFoodPane;
import 'section_navigation_host_test.dart' as host;

void main() => registerSelectionLayoutParityTests();

void registerSelectionLayoutParityTests({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final width in [390.0, 899.0, 900.0, 1400.0]) {
    final wide = width >= 900;
    for (final food in [false, true]) {
      testWidgets('${food ? 'Food' : 'Tasks'} selection at width $width', (
        tester,
      ) async {
        final section = food ? 'food' : 'tasks';
        final prefix = '$section-${width.toInt()}';
        host.HostResources? resources;
        Directory? root;
        if (food) {
          await mountFoodPane(
            tester,
            width: width,
            brightness: Brightness.dark,
          );
        } else {
          final data = (await tester.runAsync(() => host.fixture()))!;
          root = data.root;
          await tester.runAsync(() async {
            final writer = await openNativeFixtureStore(
              data.folder,
              '${data.root.path}/extra',
              nativeLibraryPath: host.nativeHostLibraryPath,
            );
            try {
              await writer.createNativeFixtureTask(
                '00000000-0000-4000-8000-000000000088',
                {
                  'title': 'Second section task',
                  'description': '',
                  'assignee': data.user,
                },
              );
            } finally {
              await writer.close();
            }
            await seedNativeProfile(data.profile, {
              'folder': data.folder.location,
              'user': data.user,
              'appearance': 'dark',
            });
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
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
            () => find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          resources = host.hostResources(tester);
        }
        try {
          final first = find
              .text(food ? 'Pane beans 1' : 'Synthetic section task')
              .first;
          final second = find
              .text(food ? 'Pane beans 2' : 'Second section task')
              .first;
          final search = find.byKey(
            ValueKey(food ? 'food-search' : 'task-search'),
          );
          bool compact() => tester
              .widget<TaskEntryArea>(find.byType(TaskEntryArea))
              .showSelection;
          Future<void> snap(String stage) async {
            if (width == 390 || width == 1400) {
              await capture?.call(tester, '$prefix-$stage');
            }
          }

          // Ordinary single activation opens an editor at either width.
          await tester.tap(first);
          if (!food) {
            await host.ready(
              tester,
              () => find.byType(TaskEditor).evaluate().isNotEmpty,
            );
          }
          await tester.pumpAndSettle();
          expect(
            food ? find.byType(FoodEditor) : find.byType(TaskEditor),
            findsOneWidget,
          );
          expect(compact(), isFalse);
          if (wide) {
            if (food) {
              Focus.of(tester.element(first)).requestFocus();
            } else {
              final dynamic page = tester.state(find.byType(TasksPage));
              (page.rowFocus[page.selectedTasks.single] as FocusNode)
                  .requestFocus();
            }
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(TaskEditor).evaluate().isEmpty,
              );
            }
            await tester.pumpAndSettle();
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsNothing,
              reason: 'Space toggles off a plain-opened sole row.',
            );
            await tester.tap(first);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(TaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
          }
          await snap('single');
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          // Explicit selection: immediate side pane only at the breakpoint.
          await tester.longPress(first);
          if (!food) {
            await host.ready(
              tester,
              () =>
                  (tester.state(find.byType(TasksPage)) as dynamic)
                          .selectedTasks
                          .length ==
                      1 &&
                  (!wide || find.byType(TaskEditor).evaluate().isNotEmpty),
            );
          }
          await tester.pumpAndSettle();
          expect(compact(), !wide);
          if (wide) {
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsOneWidget,
            );
            expect(find.byKey(const ValueKey('nameApply')), findsNothing);
          } else {
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsNothing,
            );
          }
          await snap('selected-one');
          if (wide) {
            final editor = tester.element(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
            );
            await tester.tap(first);
            await tester.pumpAndSettle();
            expect(
              tester.element(
                food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              ),
              same(editor),
            );
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.tap(first);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            if (!food) {
              await host.ready(
                tester,
                () => (tester.state(find.byType(TasksPage)) as dynamic)
                    .selectedTasks
                    .isEmpty,
              );
            }
            await tester.pumpAndSettle();
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsNothing,
            );
            await tester.longPress(first);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(TaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
          }

          final paneWidths = <double>[];
          var observing = wide;
          final paneWidth = tester.getSize(search).width;
          WidgetsBinding.instance.addPersistentFrameCallback((_) {
            if (observing && search.evaluate().isNotEmpty) {
              paneWidths.add(tester.getSize(search).width);
            }
          });
          await tester.tap(second);
          if (!food) {
            await host.ready(
              tester,
              () =>
                  (tester.state(find.byType(TasksPage)) as dynamic)
                          .selectedTasks
                          .length ==
                      2 &&
                  (!wide || find.byType(BulkTaskEditor).evaluate().isNotEmpty),
            );
          }
          await tester.pumpAndSettle();
          observing = false;
          if (wide) {
            expect(
              paneWidths,
              everyElement(paneWidth),
              reason: 'Selection must not close the pane between frames.',
            );
          }
          expect(compact(), !wide);
          expect(
            find.text(food ? 'Edit 2 containers' : 'Edit 2 tasks'),
            wide ? findsOneWidget : findsNothing,
          );
          await snap('selected-two');
          if (wide) {
            final widths = <double>[];
            var measuring = true;
            final width = tester.getSize(search).width;
            WidgetsBinding.instance.addPersistentFrameCallback((_) {
              if (measuring && search.evaluate().isNotEmpty) {
                widths.add(tester.getSize(search).width);
              }
            });
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.tap(second);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(TaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsOneWidget,
            );
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.tap(second);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(BulkTaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
            measuring = false;
            expect(
              widths,
              everyElement(width),
              reason:
                  'Removing and re-adding a selected row keeps the pane mounted.',
            );
            // Use the actual visible input, not just its change callback.
            expect(search.hitTestable(), findsOneWidget);
            final draft = food
                ? find.widgetWithText(TextField, 'Brand')
                : find.byKey(const ValueKey('addTags'));
            await tester.enterText(draft, 'Unsaved parity draft');
            await tester.pumpAndSettle();
            await tester.enterText(
              search,
              food ? 'Pane beans' : 'section task',
            );
            await tester.pumpAndSettle();
            expect(
              find.text(food ? 'Discard food changes?' : 'Unsaved changes'),
              findsOneWidget,
            );
            await tester.tap(
              find
                  .widgetWithText(TextButton, food ? 'Keep editing' : 'Cancel')
                  .last,
            );
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(search).controller!.text, isEmpty);
            expect(
              tester.widget<TextField>(draft).controller!.text,
              'Unsaved parity draft',
            );
            final dynamic state = tester.state(
              find.byType(food ? FoodInventoryPage : TasksPage),
            );
            expect(
              food ? state.bulkSelected : state.selectedTasks,
              hasLength(2),
            );
            await tester.enterText(
              search,
              food ? 'Pane beans' : 'section task',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Discard'));
            if (!food) {
              await host.ready(tester, () => state.selectedTasks.isEmpty);
            }
            await tester.pumpAndSettle();
            expect(food ? state.bulkSelected : state.selectedTasks, isEmpty);
            expect(
              food ? find.byType(FoodEditor) : find.byType(BulkTaskEditor),
              findsNothing,
            );
            expect(compact(), isFalse);
            await snap('searched');
            // Clear search follows the same guarded close/clear lifecycle.
            await tester.longPress(first);
            if (!food) {
              await host.ready(
                tester,
                () =>
                    (tester.state(find.byType(TasksPage)) as dynamic)
                            .selectedTasks
                            .length ==
                        1 &&
                    find.byType(TaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
            await tester.tap(second);
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(BulkTaskEditor).evaluate().isNotEmpty,
              );
            }
            await tester.pumpAndSettle();
            await tester.enterText(draft, 'Guarded Clear draft');
            await tester.pumpAndSettle();
            final clear = find.byTooltip(
              food ? 'Clear food search' : 'Clear search',
            );
            expect(clear.hitTestable(), findsOneWidget);
            await tester.tap(clear);
            await tester.pumpAndSettle();
            await tester.tap(
              find
                  .widgetWithText(TextButton, food ? 'Keep editing' : 'Cancel')
                  .last,
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(search).controller!.text,
              food ? 'Pane beans' : 'section task',
            );
            expect(
              food ? state.bulkSelected : state.selectedTasks,
              hasLength(2),
            );
            expect(
              tester.widget<TextField>(draft).controller!.text,
              'Guarded Clear draft',
            );
            await tester.tap(clear);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Discard'));
            if (!food) {
              await host.ready(tester, () => state.selectedTasks.isEmpty);
            }
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(search).controller!.text, isEmpty);
            expect(food ? state.bulkSelected : state.selectedTasks, isEmpty);
          } else {
            expect(search.hitTestable(), findsNothing);
            await tester.tap(find.byKey(const ValueKey('edit-selected-tasks')));
            await tester.pumpAndSettle();
            expect(
              find.text(food ? 'Edit 2 containers' : 'Edit 2 tasks'),
              findsOneWidget,
            );
            await snap('edit-dialog');
            tester.view.physicalSize = const Size(1400, 900);
            await tester.pumpAndSettle();
            expect(
              food
                  ? tester.widget<FoodEditor>(find.byType(FoodEditor)).panel
                  : tester
                        .widget<BulkTaskEditor>(find.byType(BulkTaskEditor))
                        .panel,
              isTrue,
            );
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpAndSettle();
            expect(
              food
                  ? tester.widget<FoodEditor>(find.byType(FoodEditor)).panel
                  : tester
                        .widget<BulkTaskEditor>(find.byType(BulkTaskEditor))
                        .panel,
              isFalse,
            );
            await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
            await tester.pumpAndSettle();
            expect(compact(), isFalse);
            // Selecting on narrow, without Edit, then widening auto-opens.
            await tester.longPress(first);
            if (!food) {
              await host.ready(
                tester,
                () =>
                    (tester.state(find.byType(TasksPage)) as dynamic)
                        .selectedTasks
                        .length ==
                    1,
              );
            }
            await tester.pumpAndSettle();
            tester.view.physicalSize = const Size(1400, 900);
            await tester.pumpAndSettle();
            if (!food) {
              await host.ready(
                tester,
                () => find.byType(TaskEditor).evaluate().isNotEmpty,
              );
            }
            expect(
              food ? find.byType(FoodEditor) : find.byType(TaskEditor),
              findsOneWidget,
            );
            expect(compact(), isFalse);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          if (resources != null) {
            await host.waitForHostShutdown(tester, resources);
          }
          if (root != null) {
            await tester.runAsync(() => root!.delete(recursive: true));
          }
        }
      });
    }
  }
  testWidgets('Food Select matching guards the existing single draft', (
    tester,
  ) async {
    await mountFoodPane(tester, width: 1400, brightness: Brightness.dark);
    await tester.tap(find.text('Pane beans 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions for Pane beans 1'));
    await tester.pumpAndSettle();
    // Editing highlight is not explicit selection: this action still selects.
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Deselect'), findsNothing);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    final draft = find.widgetWithText(TextField, 'Brand');
    await tester.enterText(draft, 'Owned single draft');
    await tester.pumpAndSettle();
    Future<void> matching() async {
      await tester.tap(find.byKey(const ValueKey('food-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select matching containers'));
      await tester.pumpAndSettle();
    }

    final search = find.byKey(const ValueKey('food-search'));
    final width = tester.getSize(search).width;
    final widths = <double>[];
    var observing = true;
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (observing && search.evaluate().isNotEmpty) {
        widths.add(tester.getSize(search).width);
      }
    });
    await matching();
    expect(find.text('Discard food changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(draft).controller!.text,
      'Owned single draft',
    );
    final page = tester.state<FoodInventoryPageState>(
      find.byType(FoodInventoryPage),
    );
    expect(page.bulkSelected, isEmpty);
    expect(find.byKey(const ValueKey('nameApply')), findsNothing);
    await matching();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    observing = false;
    expect(
      widths,
      everyElement(width),
      reason: 'Select matching preserves the pane through Keep and Discard.',
    );
    expect(page.bulkSelected, hasLength(2));
    expect(find.text('Edit 2 containers'), findsOneWidget);
    expect(find.byKey(const ValueKey('nameApply')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
