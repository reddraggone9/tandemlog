import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'food_production_workflow_test.dart' show switchSection;
import 'food_preview_workflow_test.dart' as pixels;
import 'task_flow_test.dart' show waitForUi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerSectionNavigationTests();
}

void registerSectionNavigationTests() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'section dropdown ${brightness.name} fits and guards drafts without writes',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'section-navigation-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final user = const Uuid().v4(), task = const Uuid().v4();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/seed',
        );
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createNativeFixtureTask(task, {
          'title': 'Synthetic navigation task',
          'description': '',
          'assignee': user,
        });
        await seed.close();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': data.path,
            'user': user,
            'appearance': brightness.name,
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        Future<Map<String, List<int>>> records() async => {
          for (final file
              in await data
                  .list()
                  .where(
                    (e) =>
                        e.path.endsWith('.jsonl') ||
                        e.path.endsWith('.foodlog'),
                  )
                  .cast<File>()
                  .toList())
            file.path: await file.readAsBytes(),
        };
        try {
          await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
          await waitForUi(
            tester,
            () => find.text('Synthetic navigation task').evaluate().isNotEmpty,
          );
          final before = await records();
          if (brightness == Brightness.dark) {
            await pixels.startRecording(tester);
          }
          for (final sample in [(1200.0, 1.0), (390.0, 1.0), (320.0, 2.5)]) {
            tester.view.physicalSize = Size(sample.$1, 850);
            tester.platformDispatcher.textScaleFactorTestValue = sample.$2;
            await tester.pumpAndSettle();
            final prefix =
                'section-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x';
            expect(find.byType(SegmentedButton<bool>), findsNothing);
            for (final food in [false, true]) {
              final trigger = find.byKey(const ValueKey('section-menu'));
              expect(tester.getSize(trigger).width, greaterThanOrEqualTo(48));
              expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));
              expect(
                find.byTooltip(
                  'Switch section (current: ${food ? 'Food' : 'Tasks'})',
                ),
                findsOneWidget,
              );
              if (sample.$1 < 600) {
                expect(find.text(food ? 'Food' : 'Tasks'), findsNothing);
              }
              await pixels.capture(
                tester,
                '$prefix-${food ? 'food' : 'tasks'}',
              );
              await pixels.tap(tester, trigger);
              await tester.pumpAndSettle();
              final selected = find.byKey(
                ValueKey(food ? 'module-food' : 'module-tasks'),
              );
              expect(
                tester.widget<CheckedPopupMenuItem<bool>>(selected).checked,
                true,
              );
              await pixels.capture(
                tester,
                '$prefix-${food ? 'food' : 'tasks'}-menu',
              );
              await pixels.tap(
                tester,
                find.byKey(ValueKey(food ? 'module-tasks' : 'module-food')),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          tester.view.physicalSize = const Size(1200, 850);
          tester.platformDispatcher.textScaleFactorTestValue = 1;
          await tester.pumpAndSettle();
          await pixels.capture(
            tester,
            'section-${brightness.name}-wide-return',
          );
          await pixels.tap(tester, find.byKey(ValueKey('task-body-$task')));
          await tester.pumpAndSettle();
          await pixels.capture(
            tester,
            'section-${brightness.name}-task-middle-editor',
          );
          final title = find.widgetWithText(TextField, 'Title');
          await tester.enterText(title, 'Unsaved synthetic task draft');
          await switchSection(tester, food: false);
          expect(find.text('Unsaved changes'), findsNothing);
          expect(
            tester.widget<TextField>(title).controller!.text,
            'Unsaved synthetic task draft',
          );
          await switchSection(tester, food: true);
          expect(find.text('Unsaved changes'), findsOneWidget);
          await pixels.capture(
            tester,
            'section-${brightness.name}-task-dirty-guard',
          );
          await pixels.tap(tester, find.text('Cancel').last);
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(title).controller!.text,
            'Unsaved synthetic task draft',
          );
          await switchSection(tester, food: true);
          await pixels.tap(tester, find.text('Discard'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Add food'), findsOneWidget);
          await pixels.tap(tester, find.byTooltip('Add food'));
          await tester.pumpAndSettle();
          final foodName = find.widgetWithText(TextField, 'Food name');
          await tester.enterText(foodName, 'Unsaved synthetic food draft');
          await pixels.capture(
            tester,
            'section-${brightness.name}-food-date-only-editor',
          );
          // Food's modal owns input. Exercise the real host callback while the
          // modal is active; this does not claim tapping through its barrier.
          tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
            false,
          );
          await tester.pumpAndSettle();
          expect(find.text('Discard food changes?'), findsOneWidget);
          await pixels.tap(tester, find.text('Keep editing'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(foodName).controller!.text,
            'Unsaved synthetic food draft',
          );
          tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
            false,
          );
          await tester.pumpAndSettle();
          await pixels.tap(tester, find.text('Discard'));
          await tester.pumpAndSettle();
          // Module selection also awaits disposal of both modal routes. Frames
          // settling alone does not establish completion of that host callback.
          await waitForUi(
            tester,
            () =>
                find
                    .byTooltip('Switch section (current: Tasks)')
                    .evaluate()
                    .isNotEmpty &&
                find.text('Synthetic navigation task').evaluate().isNotEmpty &&
                find.byType(AlertDialog).evaluate().isEmpty,
          );
          expect(find.text('Synthetic navigation task'), findsOneWidget);
          await pixels.capture(
            tester,
            'section-${brightness.name}-returned-tasks',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(await records(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
