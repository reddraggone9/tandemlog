import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import '../integration_test/native_text_fixtures.dart';
import '../integration_test/profile_fixture.dart';
import 'food_editor_pane_test.dart' show paneFoods;
import 'section_navigation_host_test.dart' as host;

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final food in [false, true]) {
    testWidgets(
      '${food ? 'Food' : 'Tasks'} Search closes retained pane when matching target is deleted during guard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1400, 900);
        addTearDown(tester.view.reset);
        Directory? root;
        host.HostResources? resources;
        late Future<void> Function() deleteMatching;
        final foodKey = GlobalKey<FoodInventoryPageState>();
        if (food) {
          var inventory = paneFoods();
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return FoodInventoryPage(
                    key: foodKey,
                    state: inventory,
                    workspaceIdentity: 'stale-search-test',
                    now: () => DateTime(2026, 10, 15),
                    onAdd: (_, _) {},
                    onRemove: (_) {},
                    onRestore: (_) {},
                    onDetails: (_, _, _, _) {},
                  );
                },
              ),
            ),
          );
          deleteMatching = () async {
            // Deliver a new synchronized inventory while the decision route is open.
            update(
              () => inventory = projectFood([
                for (var i = 1; i <= 2; i++)
                  FoodOperation(
                    id: '00000000-0000-4000-8000-000000000093:$i',
                    order: i,
                    action: FoodAction.add,
                    targets: [
                      '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
                    ],
                    details: FoodDetails(
                      name: 'Pane beans $i',
                      brand: 'Synthetic brand',
                      expiry: '2026-10-20',
                      size: '500 g',
                      location: 'Pantry',
                      estimated: true,
                    ),
                    contents: const Contents.fraction(1, 3),
                    createdAt: '2026-10-15T00:00:00Z',
                  ),
                FoodOperation(
                  id: '00000000-0000-4000-8000-000000000093:3',
                  order: 3,
                  action: FoodAction.remove,
                  targets: ['00000000-0000-4000-8000-000000000001'],
                ),
              ]),
            );
            await tester.pumpAndSettle();
          };
        } else {
          final data = (await tester.runAsync(host.fixture))!;
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
            });
          });
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
          final dynamic page = tester.state(find.byType(TasksPage));
          final store = page.store as TaskStore;
          final first =
              store.rows.firstWhere(
                    (row) => row['title'] == 'Synthetic section task',
                  )['id']
                  as String;
          deleteMatching = () async {
            var done = false;
            final work = store
                .command(first, 'task.deleted', {})
                .whenComplete(() => done = true);
            await host.ready(tester, () => done, settle: false);
            await work;
            await tester.pumpAndSettle();
          };
        }
        try {
          await tester.pumpAndSettle();
          await tester.longPress(
            find.text(food ? 'Pane beans 1' : 'Synthetic section task').first,
          );
          if (!food) {
            await host.ready(
              tester,
              () => find.byType(TaskEditor).evaluate().isNotEmpty,
            );
          }
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(food ? 'Pane beans 2' : 'Second section task').first,
          );
          if (!food) {
            await host.ready(
              tester,
              () => find.byType(BulkTaskEditor).evaluate().isNotEmpty,
            );
          }
          await tester.pumpAndSettle();
          await tester.enterText(
            food
                ? find.widgetWithText(TextField, 'Brand')
                : find.byKey(const ValueKey('addTags')),
            'Unsaved draft',
          );
          await tester.enterText(
            find.byKey(ValueKey(food ? 'food-search' : 'task-search')),
            food ? 'Pane beans 1' : 'Synthetic',
          );
          await tester.pumpAndSettle();
          final prompt = find.text(
            food ? 'Discard food changes?' : 'Unsaved changes',
          );
          expect(prompt, findsOneWidget);
          await deleteMatching();
          expect(prompt, findsOneWidget);
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
          expect(prompt, findsNothing);
          expect(find.byType(BulkTaskEditor), findsNothing);
          expect(find.byType(TaskEditor), findsNothing);
          expect(find.byType(FoodEditor), findsNothing);
          if (food) {
            expect(foodKey.currentState!.bulkSelected, isEmpty);
          } else {
            final dynamic page = tester.state(find.byType(TasksPage));
            expect(page.selectedTasks, isEmpty);
            expect(page.selecting, isFalse);
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
      },
    );
  }
}
