import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/inventory.dart';
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
      await File('${profile.path}/settings.json').writeAsString(
        jsonEncode({
          'folder': folder.path,
          'user': user,
          'appearance': brightness.name,
        }),
      );
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
                  .where(
                    (e) =>
                        e is File &&
                        (e.path.endsWith('.jsonl') ||
                            e.path.endsWith('.foodlog')),
                  )
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
                : [(390.0, 1.0), (320.0, 2.0), (900.0, 1.0), (1200.0, 2.0)]) {
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
          expect(food['account-center-y'], tasks['account-center-y']);
          if (sample.$1 <= 900) {
            expect(food['account-size'], tasks['account-size']);
          } else {
            // Food retains its 900px content bound. With more actual width,
            // Tasks can show a full name while Food uses its accessible avatar.
            for (final geometry in [food, tasks]) {
              final account = geometry['account-size'] as Size;
              expect(account.width, greaterThanOrEqualTo(48));
              expect(account.height, greaterThanOrEqualTo(48));
            }
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

Map<String, Object?> _geometry(WidgetTester tester, {required bool food}) {
  final header = find.byKey(const ValueKey('task-header'));
  final result = <String, Object?>{'height': tester.getSize(header).height};
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
