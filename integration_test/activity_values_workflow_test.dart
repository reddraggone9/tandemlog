import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/activity_log.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'profile_fixture.dart';
import 'task_flow_test.dart' show TestFolders, waitForUi;

/// Activity rows and details name what changed, on synthetic history written
/// by a second device. Captures are real GTK windows when enabled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final (width, theme, scale) in [
    (1000.0, 'dark', 1.0),
    (390.0, 'dark', 1.0),
    (1000.0, 'light', 1.0),
    (390.0, 'light', 1.0),
    (1000.0, 'dark', 2.0),
    (390.0, 'dark', 2.0),
  ]) {
    testWidgets('Activity values ${width.round()} $theme ${scale}x', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('activity-values-');
      final data = await Directory('${root.path}/data').create();
      final profile = await Directory('${root.path}/profile').create();
      final folder = LocalLogFolder(data.path);
      final alex = const Uuid().v4(), task = const Uuid().v4();
      final errand = const Uuid().v4();
      final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
      await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
      await seed.createNativeFixtureTask(task, {
        'title': 'Synthetic call plumber',
        'description': '',
        'assignee': alex,
      });
      await seed.createNativeFixtureTask(errand, {
        'title': 'Synthetic old errand',
        'description': '',
        'assignee': alex,
      });
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
      await peerTasks.unified!.renameDevice('Synthetic tablet');
      await peerTasks.unified!.renameDevice('Synthetic kitchen tablet');
      await peerTasks.refresh();
      await peerTasks.editNativeFixtureTask(task, {
        'title': 'Synthetic call plumber about the sink',
      });
      await peer.add(
        const FoodDetails(
          name: 'Synthetic oat milk',
          brand: 'Synthetic dairy',
          location: 'Pantry',
          expiry: '2027-03-01',
          estimated: null,
        ),
        1,
      );
      final id = peer.state.containers.single.id;
      await peer.changeDetails(
        [id],
        const FoodDetails(
          name: 'Synthetic oat milk',
          brand: 'Synthetic dairy',
          size: '1 L',
          location: 'Fridge',
          expiry: '2026-11-20',
          retention: 'Synthetic opened',
          estimated: null,
        ),
        ['location', 'expiry', 'size', 'retention'],
      );
      await peerTasks.command(errand, 'task.deleted', {});
      await seedNativeProfile(profile.path, {
        'folder': data.path,
        'user': alex,
        'appearance': theme,
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefix = scale == 1 && theme == 'dark'
          ? 'activity-values-${width.round()}'
          : 'activity-values-${width.round()}-$theme-${scale.round()}x';
      try {
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderActions: TestFolders()),
        );
        await waitForUi(
          tester,
          () => find
              .text('Synthetic call plumber about the sink')
              .evaluate()
              .isNotEmpty,
        );
        // A search that hides the task; Open must clear it.
        await tester.enterText(
          find.byKey(const ValueKey('task-search')),
          'no such synthetic task',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Synthetic call plumber about the sink'),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity log'));
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, '$prefix-list');
        final list = find.byKey(const ValueKey('activity-list'));
        expect(find.textContaining('not recorded'), findsNothing);
        // Rows build lazily: scroll from the top until the row is shown.
        Future<void> reveal(Finder row) async {
          final scrollable = find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(row, 100, scrollable: scrollable);
          await tester.pumpAndSettle();
          // Fully inside the viewport, so a tap lands on the row.
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
        }

        final locationLine = find.descendant(
          of: list,
          matching: find.textContaining('Location: Pantry → Fridge'),
        );
        await reveal(locationLine);
        expect(locationLine, findsOneWidget);
        // Native title values fill in after the first frame, without a tap.
        final titleLine = find.descendant(
          of: list,
          matching: find.textContaining(
            'Title: Synthetic call plumber → '
            'Synthetic call plumber about the sink',
          ),
        );
        await reveal(titleLine);
        expect(titleLine, findsOneWidget);
        expect(find.textContaining('Now named'), findsNothing);
        // Day headings carry the date; rows show the time and device only.
        final today = find.descendant(of: list, matching: find.text('Today'));
        await reveal(today);
        expect(today, findsOneWidget);
        expect(
          find.descendant(
            of: list,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  RegExp(
                    r'^\d\d:\d\d:\d\d · Synthetic kitchen tablet$',
                  ).hasMatch(w.data ?? ''),
            ),
          ),
          findsWidgets,
        );
        final renameLine = find.descendant(
          of: list,
          matching: find.textContaining(
            'Name: Synthetic tablet → Synthetic kitchen tablet',
          ),
        );
        await reveal(renameLine);
        expect(renameLine, findsOneWidget);
        // Rows show at most 3 changes; details show all.
        final more = find.descendant(of: list, matching: find.text('+1 more'));
        await reveal(more);
        expect(more, findsOneWidget);
        // A deleted task can't be opened.
        final deleted = find.descendant(
          of: list,
          matching: find.text('Task deleted: Synthetic old errand'),
        );
        await reveal(deleted);
        await tester.tap(deleted);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Open'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Close').last);
        await tester.pumpAndSettle();
        // Events without a single item have no Open.
        await reveal(renameLine);
        await tester.tap(renameLine);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Open'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Close').last);
        await tester.pumpAndSettle();
        for (final (row, name) in [
          ('Food edited', 'food'),
          ('Task edited', 'task'),
        ]) {
          final tile = find.descendant(
            of: list,
            matching: find.textContaining(row),
          );
          await reveal(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
          await captureNativeFixtureUi(tester, '$prefix-$name-details');
          final details = find.byKey(const ValueKey('activity-details'));
          expect(find.text('Activity details'), findsNothing);
          String all() => [
            for (final w in tester.widgetList<Text>(
              find.descendant(of: details, matching: find.byType(Text)),
            ))
              w.data ?? w.textSpan?.toPlainText() ?? '',
          ].join('\n');
          final text = all();
          expect(
            text,
            startsWith(
              name == 'food'
                  ? 'Food edited: Synthetic oat milk (Synthetic dairy)\n'
                  : 'Task edited: Synthetic call plumber about the sink\n',
            ),
          );
          expect(text, isNot(contains('User:')));
          expect(text, isNot(contains('Action:')));
          expect(text, isNot(contains('Now named')));
          expect(text, isNot(contains(id)));
          expect(
            text,
            matches(
              RegExp(
                r'\n\d{4}-\d\d-\d\d \d\d:\d\d:\d\d · Synthetic kitchen tablet\n',
              ),
            ),
          );
          expect(
            text,
            contains(
              name == 'food'
                  ? 'Location\nPantry → Fridge\n'
                        'Expiration\n2027-03-01 → 2026-11-20\n'
                        'Container size\nnone → 1 L\n'
                        'Retention reason\nnone → Synthetic opened'
                  : 'Title\nSynthetic call plumber → '
                        'Synthetic call plumber about the sink',
            ),
          );
          if (name == 'food') {
            await tester.tap(find.widgetWithText(TextButton, 'Close').last);
            await tester.pumpAndSettle();
            continue;
          }
          // Open jumps to the item and opens it as a tap would.
          await tester.tap(find.widgetWithText(TextButton, 'Open'));
          await tester.pumpAndSettle();
          expect(find.byType(ActivityLogDialog), findsNothing);
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('task-search')))
                .controller!
                .text,
            isEmpty,
          );
          await captureNativeFixtureUi(tester, '$prefix-task-opened');
        }
        // Food Open switches section, from the same log.
        await tester.tap(find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity log'));
        await tester.pumpAndSettle();
        final foodRow = find.descendant(
          of: list,
          matching: find.textContaining('Food edited'),
        );
        await reveal(foodRow);
        await tester.tap(foodRow);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Open'));
        await tester.pumpAndSettle();
        expect(find.byType(ActivityLogDialog), findsNothing);
        expect(find.byType(FoodEditor), findsOneWidget);
        await captureNativeFixtureUi(tester, '$prefix-food-opened');
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
