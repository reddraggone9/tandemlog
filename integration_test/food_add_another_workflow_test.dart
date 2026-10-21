import 'profile_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';
import '../test/food_add_another_test.dart' show verifyFoodAddAnother;
import '../test/food_context_menu_test.dart' show verifyFoodContextMenu;
import '../test/food_retained_flat_list_test.dart' show verifyFlatRetained;
import 'food_production_workflow_test.dart' show switchSection;
import 'food_preview_workflow_test.dart' as pixels;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFoodAddAnotherTests();
}

void registerFoodAddAnotherTests() {
  testWidgets('native Food flat Retained expiry filters and metadata', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      for (final sample in [(1200.0, 1.0), (320.0, 2.0)]) {
        tester.view.physicalSize = Size(sample.$1, 1200);
        await verifyFlatRetained(
          tester,
          brightness: brightness,
          scale: sample.$2,
          capture: (name) => pixels.capture(
            tester,
            'retained-${brightness.name}-${sample.$1.toInt()}-${sample.$2}x-$name',
          ),
        );
      }
    }
  });
  testWidgets('native Food Add another drafts and shared menu eligibility', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final variant in [(false, false), (false, true), (true, true)]) {
      await verifyFoodAddAnother(
        tester,
        deleted: variant.$1,
        retained: variant.$2,
        capture: (name) => pixels.capture(tester, 'food-$name-draft'),
      );
    }
    await verifyFoodContextMenu(tester);
  });
  for (final deleted in [false, true]) {
    testWidgets(
      'native Food Add another creates one Full container and Undo ${deleted ? 'deleted' : 'retained'} template',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'food-add-another-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final folder = LocalLogFolder(data.path), user = const Uuid().v4();
        final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createTasks({
          const Uuid().v4(): 'Independent synthetic task',
        }, user);
        final legacyFood = await FoodStore.openUnified(seed.unified!);
        await legacyFood.add(
          const FoodDetails(
            name: 'Synthetic repurchase beans',
            brand: 'Synthetic brand',
            size: '500 g',
            location: 'Pantry',
            expiry: '2026-10-15',
            retention: 'Reference',
            estimated: true,
          ),
          1,
        );
        await legacyFood.changeContents(
          legacyFood.state.containers.single,
          const Contents.fraction(1, 3),
        );
        await legacyFood.close();
        await seed.close();
        await seedNativeProfile(profile.path, {
          'folder': data.path,
          'user': user,
          'appearance': 'dark',
        });
        tester.view.physicalSize = Size(
          1200,
          Platform.environment['FOOD_PREVIEW_RECORD'] == '1' ? 850 : 1000,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FoodInventoryPage page() =>
            tester.widget<FoodInventoryPage>(find.byType(FoodInventoryPage));
        Future<Map<String, List<int>>> canonical() async => {
          for (final file in await folder.list())
            file.name: await folder.read(file.name),
        };
        Future<List<FoodRecord>> records() async => [
          for (final file in await folder.list())
            if (file.name.endsWith('.applog'))
              ...utf8
                  .decode(await folder.read(file.name))
                  .split('\n')
                  .where((line) => line.isNotEmpty)
                  .expand(foodEffectsFromAction),
        ];
        try {
          await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
          await flows.waitForUi(
            tester,
            () => find.text('Independent synthetic task').evaluate().isNotEmpty,
          );
          await switchSection(tester, food: true);
          var source = page().state.containers.single;
          if (deleted) {
            await page().onRemove([source.id]);
            await tester.pumpAndSettle();
          }
          source = page().state.containers.single;
          final sourceBefore = source.toJson(),
              before = await canonical(),
              eventsBefore = await records();
          await tester.enterText(
            find.byKey(const ValueKey('food-search')),
            'repurchase',
          );
          await tester.pumpAndSettle();
          final search = tester
              .widget<TextField>(find.byKey(const ValueKey('food-search')))
              .controller!;
          final searchValue = search.value;
          Future<void> open() async {
            await pixels.tap(
              tester,
              find.text('Synthetic repurchase beans'),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            await pixels.tap(
              tester,
              find.widgetWithText(PopupMenuItem<String>, 'Add another…'),
            );
            await tester.pumpAndSettle();
          }

          await pixels.capture(
            tester,
            'add-another-host-${deleted ? 'deleted' : 'retained'}-before',
          );
          if (!deleted) await pixels.startRecording(tester);
          await open();
          expect(await canonical(), before);
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('food-expiration')),
                )
                .focusNode!
                .hasFocus,
            true,
          );
          await pixels.capture(
            tester,
            'add-another-host-${deleted ? 'deleted' : 'retained'}-draft',
          );
          await pixels.tap(tester, find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          expect(await canonical(), before);
          expect(search.value, searchValue);
          await open();
          await pixels.tap(tester, find.widgetWithText(FilledButton, 'Add'));
          await tester.pumpAndSettle();
          expect(find.text('Expiration is required.'), findsOneWidget);
          expect(await canonical(), before);
          final editor = tester.state<FoodEditorState>(find.byType(FoodEditor));
          final template = editor.widget.template;
          final action = find.byKey(const ValueKey('food-save-action'));
          expect(
            find.descendant(of: action, matching: find.text('Review errors')),
            findsOneWidget,
          );
          final expiry = find.byKey(const ValueKey('food-expiration'));
          await pixels.tap(tester, expiry);
          await tester.enterText(expiry, '2026-12-10');
          await tester.pumpAndSettle();
          final corrected = {
            for (final c in [
              editor.name,
              editor.brand,
              editor.expiry,
              editor.size,
              editor.location,
              editor.count,
              editor.retentionQuery,
            ])
              c: c.value,
          };
          expect(
            tester.widget<TextField>(expiry).decoration!.errorText,
            isNull,
          );
          expect(
            find.descendant(of: action, matching: find.text('Review errors')),
            findsNothing,
          );
          expect(
            tester.state<FoodEditorState>(find.byType(FoodEditor)),
            same(editor),
          );
          expect(editor.widget.template, same(template));
          for (final entry in corrected.entries) {
            expect(entry.key.value, entry.value);
          }
          expect(editor.count.text, '1');
          expect(editor.retention, isEmpty);
          expect(editor.estimated, isNull);
          expect(page().state.containers.single.toJson(), sourceBefore);
          expect(
            await canonical(),
            before,
            reason: 'Correction itself cannot allocate or append an Add',
          );
          expect(
            find.descendant(of: action, matching: find.text('Add')),
            findsOneWidget,
          );
          await pixels.tap(tester, action);
          await flows.waitForUi(
            tester,
            () => page().state.containers.length == 2,
          );
          final added = page().state.containers.singleWhere(
            (e) => e.id != source.id,
          );
          expect(
            added.contents.toJson(),
            const Contents.fraction(1, 1).toJson(),
          );
          expect(added.deleted, false);
          expect(added.details.retention, isEmpty);
          expect(added.details.estimated, isNull);
          expect(added.details.expiry, '2026-12-10');
          expect(added.details.name, source.details.name);
          expect(added.details.brand, source.details.brand);
          expect(added.details.size, source.details.size);
          expect(added.details.location, source.details.location);
          expect(
            page().state.containers
                .singleWhere((e) => e.id == source.id)
                .toJson(),
            sourceBefore,
          );
          final after = await records();
          expect(after.length, eventsBefore.length + 1);
          final beforeIds = eventsBefore.map((record) => record.id).toSet();
          final authored = after
              .where((record) => !beforeIds.contains(record.id))
              .toList();
          expect(
            authored,
            hasLength(1),
            reason: 'One Add, independent of writer/file ordering',
          );
          for (final old in eventsBefore) {
            expect(
              after.singleWhere((record) => record.id == old.id).encode(),
              old.encode(),
              reason: 'Existing canonical records retain exact encoded bytes',
            );
          }
          final addition = authored.single;
          expect(addition.operation.action, FoodAction.add);
          expect(addition.operation.targets, [added.id]);
          expect(addition.operation.observedDeletes, isEmpty);
          expect(addition.operation.observedEdits, isEmpty);
          expect(search.value, searchValue);
          await pixels.capture(
            tester,
            'add-another-host-${deleted ? 'deleted' : 'retained'}-after',
          );
          await pixels.tap(
            tester,
            find.byKey(const ValueKey('undo-food-action')),
          );
          await flows.waitForUi(
            tester,
            () => page().state.containers.length == 1,
          );
          expect(page().state.containers.single.toJson(), sourceBefore);
          final undoneRecords = await records();
          expect(undoneRecords.length, eventsBefore.length + 2);
          final inverse = undoneRecords
              .where(
                (record) =>
                    !beforeIds.contains(record.id) && record.id != addition.id,
              )
              .toList();
          expect(inverse, hasLength(1));
          expect(inverse.single.operation.action, FoodAction.undo);
          expect(inverse.single.operation.targets, [added.id]);
          expect(inverse.single.operation.retracts, addition.id);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 500));
        }
      },
    );
  }
}
