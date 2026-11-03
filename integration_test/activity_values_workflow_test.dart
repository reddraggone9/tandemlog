import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
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
  for (final width in [1000.0, 420.0]) {
    testWidgets('Activity values ${width.round()} dark', (tester) async {
      final root = await Directory.systemTemp.createTemp('activity-values-');
      final data = await Directory('${root.path}/data').create();
      final profile = await Directory('${root.path}/profile').create();
      final folder = LocalLogFolder(data.path);
      final alex = const Uuid().v4(), task = const Uuid().v4();
      final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
      await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
      await seed.createNativeFixtureTask(task, {
        'title': 'Synthetic call plumber',
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
          location: 'Fridge',
          expiry: '2026-11-20',
          estimated: null,
        ),
        ['location', 'expiry'],
      );
      await seedNativeProfile(profile.path, {
        'folder': data.path,
        'user': alex,
        'appearance': 'dark',
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefix = 'activity-values-${width.round()}';
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
        await tester.tap(find.byKey(const ValueKey('identity-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity log'));
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, '$prefix-list');
        final list = find.byKey(const ValueKey('activity-list'));
        expect(find.textContaining('not recorded'), findsNothing);
        expect(
          find.descendant(
            of: list,
            matching: find.textContaining('Location: Pantry → Fridge'),
          ),
          findsOneWidget,
        );
        // Native title values fill in after the first frame, without a tap.
        expect(
          find.descendant(
            of: list,
            matching: find.textContaining(
              'Title: Synthetic call plumber → '
              'Synthetic call plumber about the sink',
            ),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Now named'), findsNothing);
        for (final (row, name) in [
          ('Food edited', 'food'),
          ('Task edited', 'task'),
        ]) {
          await tester.tap(
            find.descendant(of: list, matching: find.textContaining(row)),
          );
          await tester.pumpAndSettle();
          await captureNativeFixtureUi(tester, '$prefix-$name-details');
          final details = find.byType(SelectableText).last;
          final text = tester.widget<SelectableText>(details).data!;
          expect(text, isNot(contains('User:')));
          expect(text, isNot(contains('Action:')));
          expect(text, isNot(contains('Now named')));
          expect(text, isNot(contains(id)));
          expect(text, contains('Device: Synthetic kitchen tablet'));
          expect(
            text,
            contains(
              name == 'food'
                  ? 'Location: Pantry → Fridge\n'
                        'Expiration: 2027-03-01 → 2026-11-20'
                  : 'Title: Synthetic call plumber → '
                        'Synthetic call plumber about the sink',
            ),
          );
          await tester.tap(find.widgetWithText(TextButton, 'Close').last);
          await tester.pumpAndSettle();
        }
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
