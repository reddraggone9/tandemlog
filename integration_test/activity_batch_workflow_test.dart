import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_purchase_import.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'profile_fixture.dart';
import 'task_flow_test.dart' show TestFolders, waitForUi;

/// A receipt import from another device reads as one summary row that
/// expands inline into one ordinary row per food; the log fills the window
/// height; store links read as the store's name. Captures are real GTK
/// windows when enabled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerActivityBatchWorkflowTests();
}

void registerActivityBatchWorkflowTests({
  List<(double, String, double)> variants = const [
    (1000, 'dark', 1),
    (390, 'dark', 1),
  ],
}) {
  for (final (width, theme, scale) in variants) {
    testWidgets('Activity batch ${width.round()} $theme ${scale}x', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('activity-batch-');
      final data = await Directory('${root.path}/data').create();
      final profile = await Directory('${root.path}/profile').create();
      final folder = LocalLogFolder(data.path);
      final alex = const Uuid().v4(), repeat = const Uuid().v4();
      final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
      await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
      await seed.createNativeFixtureTask(repeat, {
        'title': 'Synthetic water the plants',
        'description': '',
        'assignee': alex,
      });
      await seed.command(repeat, 'task.edited', {
        'schedule': {'dueDate': '2026-11-03', 'recurrence': 'every week'},
      });
      for (var i = 1; i <= 4; i++) {
        await seed.createNativeFixtureTask(const Uuid().v4(), {
          'title': 'Synthetic chore $i',
          'description': '',
          'assignee': alex,
        });
      }
      await seed.close();
      final peerProfile = await LocalProfileDatabase.open(
        '${root.path}/peer-profile',
      );
      final peerTasks = await TaskStore.open(
        folder,
        peerProfile.root,
        profileDatabase: peerProfile,
        writerIdentity: const Uuid().v4(),
        textEngine: seed.textEngine,
      );
      final peer = await FoodStore.openUnified(peerTasks.unified!);
      await peerTasks.unified!.renameDevice('Synthetic kitchen tablet');
      await peerTasks.refresh();
      FoodPurchaseLine line(String key, String name, int n, String link) =>
          FoodPurchaseLine(
            sourceKind: 'ynab',
            sourceKey: key,
            date: '2026-11-02',
            store: 'Walmart',
            amount: 300,
            quantity: n,
            name: name,
            link: link,
          );
      await peer.commitPurchaseImport(
        FoodPurchaseImportPlan(
          space: peer.space,
          importId: '11111111-1111-4111-8111-111111111111',
          sourceSha256: 'a' * 64,
          lines: [
            line('r#1', 'Synthetic milk', 2, 'https://www.walmart.com/ip/1'),
            line('r#2', 'Synthetic beans', 1, 'https://www.walmart.com/ip/2'),
            line('r#3', 'Synthetic rice', 1, 'https://www.walmart.com/ip/3'),
          ],
        ),
      );
      await seedNativeProfile(profile.path, {
        'folder': data.path,
        'user': alex,
        'appearance': theme,
      });
      tester.view.devicePixelRatio = 1;
      final height = width < 600 ? 844.0 : 820.0;
      tester.view.physicalSize = Size(width, height);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefix = 'activity-batch-${width.round()}-$theme-${scale.round()}x';
      try {
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderActions: TestFolders()),
        );
        await waitForUi(
          tester,
          () => find.text('Synthetic chore 1').evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity log'));
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('activity-list'));
        // The log uses the window's height, not a fixed box.
        expect(tester.getSize(list).height, greaterThan(height * 0.6));
        final summary = find.descendant(
          of: list,
          matching: find.text('3 foods added from a Walmart purchase'),
        );
        expect(summary, findsOneWidget);
        await captureNativeFixtureUi(tester, '$prefix-list');
        expect(find.text('Synthetic beans'), findsNothing);
        const names = 'Synthetic rice, Synthetic beans, Synthetic milk ×2';
        expect(
          find.descendant(of: list, matching: find.text(names)),
          findsOneWidget,
        );
        await tester.tap(summary);
        await tester.pumpAndSettle();
        // Rows build lazily; at large text the parts start below the fold.
        final scrollable = find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first;
        Future<void> reveal(Finder row) async {
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(row, 80, scrollable: scrollable);
          await tester.pumpAndSettle();
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
        }

        Finder inList(String text) =>
            find.descendant(of: list, matching: find.textContaining(text));
        Finder part(String name) =>
            find.descendant(of: list, matching: find.text(name));
        // Expanded, the parts name the items: the summary drops its names
        // line, and the parts don't repeat the summary's "Food added".
        for (final name in ['Synthetic rice', 'Synthetic milk ×2']) {
          await reveal(part(name));
          expect(part(name), findsOneWidget);
        }
        final beans = part('Synthetic beans');
        await reveal(beans);
        expect(beans, findsOneWidget);
        expect(inList(names), findsNothing);
        expect(inList('Food added'), findsNothing);
        // The summary names Walmart, so its parts don't repeat the link.
        expect(inList('Store link'), findsNothing);
        expect(find.textContaining('https://'), findsNothing);
        // Capture from the top, with the parent row in view.
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pumpAndSettle();
        if (scale == 1) {
          // The group's end shows: a wider gap after its last part than
          // between parts, so the next entry doesn't read as another part.
          final tops = [
            for (final name in [
              'Synthetic rice',
              'Synthetic beans',
              'Synthetic milk ×2',
            ])
              tester.getTopLeft(part(name)).dy,
          ]..sort();
          final next = tester
              .getTopLeft(
                find.descendant(
                  of: list,
                  matching: find.text('Device renamed'),
                ),
              )
              .dy;
          expect(next - tops.last, greaterThan(tops[1] - tops[0] + 8));
        }
        await captureNativeFixtureUi(tester, '$prefix-expanded');
        // A part opens the ordinary details for just that food.
        await reveal(beans);
        await tester.tap(beans);
        await tester.pumpAndSettle();
        final details = find.byKey(const ValueKey('activity-details'));
        expect(details, findsOneWidget);
        expect(
          find.descendant(of: details, matching: find.text('Walmart')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: details, matching: find.text('Open')),
          findsOneWidget,
        );
        await captureNativeFixtureUi(tester, '$prefix-part-details');
        await tester.tap(
          find.descendant(of: details, matching: find.text('Close')),
        );
        await tester.pumpAndSettle();
        // Collapse again.
        await reveal(summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        expect(part('Synthetic beans'), findsNothing);
        expect(inList(names), findsOneWidget);
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
        // Completion notice names the next due date plainly.
        final check = find.descendant(
          of: find.byTooltip('Complete Synthetic water the plants'),
          matching: find.byType(Checkbox),
        );
        await tester.tap(check.first);
        await waitForUi(
          tester,
          () => find.textContaining('Completed 1 task').evaluate().isNotEmpty,
        );
        expect(
          find.text('Completed 1 task. Next due 2026-11-10.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await captureNativeFixtureUi(tester, '$prefix-completed');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await peer.close();
        await peerTasks.close();
        await peerProfile.close();
        await root.delete(recursive: true);
      }
    });
  }
}
