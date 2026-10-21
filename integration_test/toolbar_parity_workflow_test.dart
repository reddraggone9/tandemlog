import 'profile_fixture.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'food_production_workflow_test.dart' show switchSection;
import 'food_preview_workflow_test.dart' as pixels;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi, filterChoice, openSettings;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerToolbarParityTests();
}

void registerToolbarParityTests() {
  registerSectionWidthTests();
  for (final brightness in Brightness.values) {
    testWidgets('actual section toolbar parity ${brightness.name}', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('toolbar-synthetic-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Synthetic household'});
      await seed.createTasks({const Uuid().v4(): 'Parity reference'}, user);
      await seed.close();
      await seedNativeProfile(profile.path, {
        'folder': folder.path,
        'user': user,
        'appearance': brightness.name,
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final recording = Platform.environment['FOOD_PREVIEW_RECORD'] == '1';
      try {
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await waitForUi(
          tester,
          () => find.text('Parity reference').evaluate().isNotEmpty,
        );
        Future<Map<String, List<int>>> canonical() async => {
          for (final file
              in await folder
                  .list(recursive: true)
                  .where((e) => e is File && e.path.endsWith('.applog'))
                  .cast<File>()
                  .toList())
            file.path: await file.readAsBytes(),
        };
        final canonicalBefore = await canonical();
        if (recording && brightness == Brightness.dark) {
          await pixels.startRecording(tester);
        }
        for (final sample
            in recording
                ? [(1200.0, 1.0)]
                : [
                    (2048.0, 1.0),
                    (1451.0, 2.0),
                    (390.0, 1.0),
                    (320.0, 2.0),
                    (900.0, 1.0),
                    (1200.0, 2.0),
                  ]) {
          tester.view.physicalSize = Size(sample.$1, recording ? 850 : 1000);
          tester.platformDispatcher.textScaleFactorTestValue = sample.$2;
          await switchSection(tester, food: false);
          await tester.pumpAndSettle();
          final tasks = _geometry(tester, food: false);
          if (sample.$1 > 900) {
            await openSettings(tester);
            expect(
              find.byKey(const ValueKey('initialize-shared-text')),
              findsNothing,
            );
            await pixels.tap(tester, find.widgetWithText(TextButton, 'Done'));
            await tester.pumpAndSettle();
          }
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('undo-task-action')),
              matching: find.text('Undo'),
            ),
            sample.$1 >= 600 ? findsOneWidget : findsNothing,
          );
          await captureNativeFixtureUi(
            tester,
            'toolbar-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-tasks',
          );
          await filterChoice(tester, 'Everyone');
          final activeTasks = _geometry(tester, food: false);
          expect(activeTasks['filter-target'], tasks['filter-target']);
          expect(activeTasks['filter-center-y'], tasks['filter-center-y']);
          await captureNativeFixtureUi(
            tester,
            'toolbar-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-tasks-active',
          );
          await filterChoice(tester, 'Active user');
          await switchSection(tester, food: true);
          await tester.pumpAndSettle();
          final food = _geometry(tester, food: true);
          for (final key in ['undo-food-action']) {
            expect(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.text('Undo'),
              ),
              sample.$1 >= 600 ? findsOneWidget : findsNothing,
            );
          }
          await captureNativeFixtureUi(
            tester,
            'toolbar-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-food',
          );
          debugPrint(
            'TOOLBAR_PARITY $brightness $sample tasks=$tasks food=$food',
          );
          expect(tester.takeException(), isNull);
          expect(
            food['height'],
            tasks['height'],
            reason: 'same toolbar height',
          );
          for (final action in ['add', 'undo', 'filter']) {
            final target = food['$action-target'] as Size;
            expect(target.width, greaterThanOrEqualTo(48));
            expect(target.height, greaterThanOrEqualTo(48));
            expect(
              food['$action-size'],
              tasks['$action-size'],
              reason: '$action icon size',
            );
            expect(
              food['$action-center-y'],
              tasks['$action-center-y'],
              reason: '$action global vertical center',
            );
            expect(
              food['$action-color'],
              tasks['$action-color'],
              reason: '$action equivalent inactive/disabled color',
            );
          }
          for (final key in ['header-rect', 'search-rect']) {
            final foodRect = food[key] as Rect;
            final taskRect = tasks[key] as Rect;
            expect(foodRect.left, taskRect.left, reason: '$key left edge');
            expect(foodRect.right, taskRect.right, reason: '$key right edge');
          }
          expect(
            (food['section-rect'] as Rect).left,
            (tasks['section-rect'] as Rect).left,
          );
          expect(food['account-center-y'], tasks['account-center-y']);
          expect(food['account-size'], tasks['account-size']);
          if (sample.$1 > 900) {
            expect(
              find.byTooltip('Active user: Synthetic household'),
              findsOneWidget,
            );
            await openSettings(tester);
            expect(
              find.byKey(const ValueKey('initialize-shared-text')),
              findsNothing,
            );
            await pixels.tap(tester, find.widgetWithText(TextButton, 'Done'));
            await tester.pumpAndSettle();
          }
          await pixels.tap(tester, find.byKey(const ValueKey('food-filter')));
          await tester.pumpAndSettle();
          expect(find.text('Stock'), findsWidgets);
          expect(find.text('Retained'), findsOneWidget);
          expect(find.text('Deleted'), findsOneWidget);
          await pixels.tap(tester, find.text('Retained'));
          await tester.pumpAndSettle();
          expect(find.byType(Badge), findsOneWidget);
          final badge = tester.widget<Badge>(find.byType(Badge));
          expect(badge.label, isNull);
          expect(badge.isLabelVisible, isTrue);
          final active = _geometry(tester, food: true);
          expect(active['filter-dot-size'], const Size(6, 6));
          expect(active['filter-dot-size'], activeTasks['filter-dot-size']);
          expect(active['filter-dot-offset'], activeTasks['filter-dot-offset']);
          expect(
            find.byTooltip('Filter food: Retained · active filters'),
            findsOneWidget,
          );
          expect(active['filter-target'], food['filter-target']);
          expect(active['filter-center-y'], food['filter-center-y']);
          await captureNativeFixtureUi(
            tester,
            'toolbar-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-food-active',
          );
          await pixels.tap(tester, find.byKey(const ValueKey('food-filter')));
          await tester.pumpAndSettle();
          await pixels.tap(
            tester,
            find.widgetWithText(PopupMenuItem<FoodView>, 'Stock'),
          );
          await tester.pumpAndSettle();
          final filter = find.byKey(const ValueKey('food-filter'));
          final semantics = tester.ensureSemantics();
          final nodes = <SemanticsNode>[];
          void visit(SemanticsNode node) {
            final candidate = node.getSemanticsData();
            if (candidate.hasAction(SemanticsAction.tap) &&
                candidate.tooltip == 'Filter food: Stock') {
              nodes.add(node);
            }
            node.visitChildren((child) {
              visit(child);
              return true;
            });
          }

          visit(tester.getSemantics(filter));
          expect(nodes, hasLength(1), reason: 'one actionable popup node');
          final data = nodes.single.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.tooltip, 'Filter food: Stock');
          semantics.dispose();
          final focus = tester.widget<Focus>(
            find.descendant(of: filter, matching: find.byType(Focus)).first,
          );
          Focus.of(tester.element(find.byWidget(focus.child))).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Retained'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Retained'), findsNothing);
        }
        expect(
          await canonical(),
          canonicalBefore,
          reason: 'toolbar/view QA does not append canonical records',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}

void registerSectionWidthTests() {
  for (final brightness in Brightness.values) {
    testWidgets('section outer edges and task editor ${brightness.name}', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp(
        'section-width-synthetic-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final seed = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4();
      await seed.command(user, 'user.created', {'name': 'Synthetic household'});
      await seed.createTasks({const Uuid().v4(): 'Width reference task'}, user);
      await seed.close();
      await seedNativeProfile(profile.path, {
        'folder': folder.path,
        'user': user,
        'appearance': brightness.name,
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Future<Map<String, List<int>>> canonical() async => {
        for (final file
            in await folder
                .list(recursive: true)
                .where(
                  (e) =>
                      e is File &&
                      (e.path.endsWith('.applog') ||
                          e.path.endsWith('.foodlog')),
                )
                .cast<File>()
                .toList())
          file.path: await file.readAsBytes(),
      };
      try {
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await waitForUi(
          tester,
          () => find.text('Width reference task').evaluate().isNotEmpty,
        );
        for (final populated in [false, true]) {
          if (populated) {
            await switchSection(tester, food: true);
            final page = tester.widget<FoodInventoryPage>(
              find.byType(FoodInventoryPage),
            );
            // Fixture preparation uses the actual admitted host command.
            await page.onAdd(
              const FoodDetails(
                name: 'Synthetic long food title for the shared section width',
                expiry: '2026-11-03',
                brand: 'Synthetic brand',
                location: 'Pantry',
              ),
              2,
            );
            await tester.pumpAndSettle();
          }
          final before = await canonical();
          for (final sample in [
            (2048.0, 1.0),
            (1451.0, 2.0),
            (1200.0, 1.0),
            (390.0, 1.0),
            (320.0, 2.0),
          ]) {
            tester.view.physicalSize = Size(sample.$1, 1000);
            tester.platformDispatcher.textScaleFactorTestValue = sample.$2;
            await switchSection(tester, food: false);
            final closed = _geometry(tester, food: false);
            await tester.tap(find.text('Width reference task'));
            await waitForUi(
              tester,
              () => find.byType(TaskEditor).evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
            final open = _geometry(tester, food: false);
            expect(open['header-rect'], closed['header-rect']);
            expect(
              (open['section-rect'] as Rect).left,
              (closed['section-rect'] as Rect).left,
            );
            if (sample.$1 >= 900) {
              expect(tester.getSize(find.byType(TaskEditor)).width, 420);
              expect(
                (open['search-rect'] as Rect).left,
                (closed['search-rect'] as Rect).left,
              );
              expect(
                (open['search-rect'] as Rect).right,
                (closed['search-rect'] as Rect).right - 421,
              );
            } else {
              expect(open['search-rect'], closed['search-rect']);
              expect(
                find.descendant(
                  of: find.byType(TaskEditor),
                  matching: find.byType(AlertDialog),
                ),
                findsOneWidget,
              );
            }
            if (sample.$1 == 2048 || sample.$1 == 320) {
              await captureNativeFixtureUi(
                tester,
                'section-width-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-$populated-editor',
              );
            }
            await tester.tap(
              find.descendant(
                of: find.byType(TaskEditor),
                matching: find.widgetWithText(TextButton, 'Cancel'),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              _geometry(tester, food: false)['search-rect'],
              closed['search-rect'],
            );
            if (sample.$1 >= 900) {
              await tester.tap(find.text('Width reference task'));
              await waitForUi(
                tester,
                () => find.byType(TaskEditor).evaluate().isNotEmpty,
              );
              await tester.pumpAndSettle();
              if (sample.$1 == 2048) {
                final title = find.widgetWithText(TextField, 'Title');
                await tester.enterText(title, 'Unsaved synthetic width draft');
                final value = tester.widget<TextField>(title).controller!.value;
                await switchSection(tester, food: true);
                expect(find.text('Unsaved changes'), findsOneWidget);
                await tester.tap(
                  find.descendant(
                    of: find.widgetWithText(AlertDialog, 'Unsaved changes'),
                    matching: find.widgetWithText(TextButton, 'Cancel'),
                  ),
                );
                await tester.pumpAndSettle();
                expect(
                  tester.widget<TextField>(title).controller!.value,
                  value,
                );
                expect(find.byType(FoodInventoryPage), findsNothing);
                expect(
                  _geometry(tester, food: false)['header-rect'],
                  closed['header-rect'],
                );
                await switchSection(tester, food: true);
                await tester.tap(find.widgetWithText(TextButton, 'Discard'));
                await tester.pumpAndSettle();
              } else {
                await switchSection(tester, food: true);
              }
            } else {
              // The narrow editor owns its modal barrier; switch after closing it.
              await switchSection(tester, food: true);
            }
            expect(find.byType(TaskEditor), findsNothing);
            final food = _geometry(tester, food: true);
            expect(food['header-rect'], closed['header-rect']);
            expect(food['search-rect'], closed['search-rect']);
            expect(
              (food['section-rect'] as Rect).left,
              (closed['section-rect'] as Rect).left,
            );
            expect(
              find.text(
                'Synthetic long food title for the shared section width',
              ),
              populated ? findsOneWidget : findsNothing,
            );
            if (sample.$1 == 2048 || sample.$1 == 320) {
              await captureNativeFixtureUi(
                tester,
                'section-width-${brightness.name}-${sample.$1.toInt()}-${sample.$2}-$populated-food',
              );
            }
            await switchSection(tester, food: false);
            expect(
              _geometry(tester, food: false)['header-rect'],
              closed['header-rect'],
            );
            expect(
              _geometry(tester, food: false)['search-rect'],
              closed['search-rect'],
            );
            expect(
              await canonical(),
              before,
              reason:
                  'layout/switch/Cancel/Discard do not append canonical records',
            );
            expect(tester.takeException(), isNull);
            debugPrint(
              'SECTION_WIDTH $brightness $sample populated=$populated closed=$closed food=$food',
            );
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}

Map<String, Object?> _geometry(WidgetTester tester, {required bool food}) {
  final header = find.byKey(const ValueKey('task-header'));
  final result = <String, Object?>{
    'height': tester.getSize(header).height,
    'header-rect': tester.getRect(header),
    'section-rect': tester.getRect(find.byKey(const ValueKey('section-menu'))),
    'search-rect': tester.getRect(
      find.byKey(ValueKey(food ? 'food-search' : 'task-search')),
    ),
  };
  final actions = {
    'add': food
        ? find.byTooltip('Add food')
        : find.byKey(const ValueKey('open-capture')),
    'undo': find.byKey(
      ValueKey(food ? 'undo-food-action' : 'undo-task-action'),
    ),
    'filter': find.byKey(ValueKey(food ? 'food-filter' : 'task-filter')),
  };
  for (final entry in actions.entries) {
    final icon = find
        .descendant(of: entry.value, matching: find.byType(Icon))
        .first;
    final rect = tester.getRect(icon);
    final glyph = tester.widget<RichText>(
      find.descendant(of: icon, matching: find.byType(RichText)).first,
    );
    result['${entry.key}-size'] = rect.size;
    result['${entry.key}-center-y'] = rect.center.dy;
    result['${entry.key}-color'] = (glyph.text as TextSpan).style!.color;
    final target = tester.getRect(entry.value);
    result['${entry.key}-target'] = target.size;
    if (entry.key == 'filter') {
      final badge = find.descendant(
        of: entry.value,
        matching: find.byType(Badge),
      );
      if (tester.widget<Badge>(badge).isLabelVisible) {
        final dot = tester.getRect(
          find.descendant(of: badge, matching: find.byType(Container)).first,
        );
        result['filter-dot-size'] = dot.size;
        result['filter-dot-offset'] = dot.topLeft - rect.topLeft;
      }
    }
  }
  final account = find.byTooltip('Active user: Synthetic household');
  result['account-center-y'] = tester.getRect(account).center.dy;
  result['account-size'] = tester.getRect(account).size;
  return result;
}
