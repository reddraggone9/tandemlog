import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/food_undo_history.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_record.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

import 'batch_storage_test.dart' show CountingFolder;

// Component tests cover storage/retraction invariants; the final widget test
// invokes the actual application's onDetails/onUndo callbacks. Neither claims
// native pointer, selection, or visual acceptance coverage.
void main() {
  registerFoodBulkDetailsUndoReviewTests();
}

void registerFoodBulkDetailsUndoReviewTests({
  bool components = true,
  bool actualHost = false,
}) {
  group('Food bulk details Undo independent review', () {
    late Directory root;
    late CountingFolder folder;
    late LocalProfileDatabase profile, peerProfile;
    late TaskStore tasks, peerTasks;
    late FoodStore food, peer;
    late FoodUndoHistory history;
    late String installation, peerInstallation;
    NativeTextEngine? engine;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('food-bulk-undo-review-');
      folder = CountingFolder(
        LocalLogFolder((await Directory('${root.path}/data').create()).path),
      );
      profile = await LocalProfileDatabase.open('${root.path}/local');
      await LocalProfileMigration(profile).run();
      installation = LocalSettings.protectedValues(profile)['writer'] as String;
      final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
      engine = library == null && !actualHost
          ? null
          : NativeTextEngine(libraryPath: library);
      tasks = await TaskStore.open(
        folder,
        profile.root,
        profileDatabase: profile,
        writerIdentity: installation,
        textEngine: engine,
        initializeNewWorkspaceText: engine != null,
      );
      food = await FoodStore.open(
        folder,
        profile: profile,
        installationWriter: installation,
        space: tasks.space,
        now: () => DateTime.utc(2026, 10, 11),
      );
      peerProfile = await LocalProfileDatabase.open('${root.path}/peer');
      await LocalProfileMigration(peerProfile).run();
      peerInstallation =
          LocalSettings.protectedValues(peerProfile)['writer'] as String;
      peerTasks = await TaskStore.open(
        folder,
        peerProfile.root,
        profileDatabase: peerProfile,
        writerIdentity: peerInstallation,
        textEngine: engine,
        initializeNewWorkspaceText: engine != null,
      );
      peer = await FoodStore.open(
        folder,
        profile: peerProfile,
        installationWriter: peerInstallation,
        space: tasks.space,
        now: () => DateTime.utc(2026, 10, 11),
      );
      history = FoodUndoHistory()
        ..setWorkspace(jsonEncode([folder.location, food.space, food.writer]));

      for (final seed in const [
        (
          count: 100,
          details: FoodDetails(
            name: 'Mixed bulk food',
            brand: 'Original A',
            location: 'Pantry',
            expiry: '2026-10-15',
            estimated: true,
            size: '500 g',
          ),
        ),
        (
          count: 100,
          details: FoodDetails(
            name: 'Mixed bulk food',
            brand: 'Original B',
            location: 'Freezer',
            expiry: '2027-02-03',
            estimated: null,
            size: '1 lb',
            retention: 'Keep frozen',
          ),
        ),
        (
          count: 7,
          details: FoodDetails(
            name: 'Mixed bulk food',
            expiry: null,
            estimated: false,
            size: '250 ml',
          ),
        ),
      ]) {
        await food.add(seed.details, seed.count);
      }
      final ids = food.state.active.map((item) => item.id).toList();
      await food.changeContents(
        _item(food, ids[0]),
        const Contents.fraction(1, 2),
      );
      await food.changeContents(
        _item(food, ids[100]),
        const Contents.amount(3, 2, 'cups'),
      );
      await food.changeContents(
        _item(food, ids[204]),
        const Contents.fraction(0, 1),
      );
      await food.add(
        const FoodDetails(
          name: 'Mixed bulk food',
          brand: 'Deleted brand',
          location: 'Deleted shelf',
          expiry: '2026-10-15',
        ),
        1,
      );
      await food.remove(food.lastPreparedRecords.single.operation.targets);
    });

    tearDown(() async {
      await peer.close();
      await food.close();
      await peerTasks.close();
      await tasks.close();
      await peerProfile.close();
      await profile.close();
      engine?.dispose();
      engine = null;
      await root.delete(recursive: true);
    });

    if (components) {
      test(
        '205-container Brand edit is one confirmed action; untouched mixed fields and later arrivals survive Undo',
        () async {
          final observed = food.state.active.take(205).toList();
          final selected = observed.map((item) => item.id).toList();
          expect(selected, hasLength(205));
          await food.add(
            const FoodDetails(
              name: 'Mixed bulk food',
              brand: 'Late arrival',
              location: 'Other shelf',
              expiry: '2027-08-09',
            ),
            1,
          );
          final before = _snapshot(food);
          final originalBytes = await folder.read(foodLogName(food.writer));
          folder.reset();
          await food.changeDetails(
            selected,
            const FoodDetails(
              name: 'Carrier name must not replace mixed names',
              brand: 'Unified brand',
              location: 'Carrier location must not replace mixed locations',
              expiry: '2099-12-31',
              estimated: false,
              size: 'Carrier size',
              retention: 'Carrier retention',
            ),
            ['brand'],
          );
          final records = food.lastPreparedRecords;
          _expectOneAction(history, food, records, selected, ['brand']);
          expect(folder.appends, 1);
          for (final item in food.state.containers) {
            final expected = _copy(before[item.id]!);
            if (selected.contains(item.id)) {
              (expected['details'] as Map)['brand'] = 'Unified brand';
            }
            expect(item.toJson(), expected, reason: item.id);
          }
          final entry = history.latest!;
          final inverse = await food.undoOperations(entry.records);
          _expectExactInverse(inverse, records);
          expect(inverse.every(food.isAdmitted), true);
          history.complete(entry);
          expect(history.length, 0);
          expect(_snapshot(food), before);
          expect(folder.appends, 2);
          final after = await folder.read(foodLogName(food.writer));
          expect(after.take(originalBytes.length).toList(), originalBytes);
          final calls = folder.appends;
          expect(await food.undoOperations(entry.records), isEmpty);
          expect(folder.appends, calls);
          expect(await folder.read(foodLogName(food.writer)), after);
          await food.close();
          food = await FoodStore.open(
            folder,
            profile: profile,
            installationWriter: installation,
            space: tasks.space,
          );
          expect(_snapshot(food), before);
          expect(await folder.read(foodLogName(food.writer)), after);
        },
      );

      test(
        'explicit Location clear over 205 containers retains one exact action through partial Undo recovery',
        () async {
          final selected = food.state.active
              .take(205)
              .map((item) => item.id)
              .toList();
          final before = _snapshot(food);
          await food.changeDetails(
            selected,
            const FoodDetails(
              name: 'Unused carrier',
              brand: 'Unused brand',
              location: '',
              expiry: '2099-12-31',
            ),
            ['location'],
          );
          final originals = food.lastPreparedRecords;
          _expectOneAction(history, food, originals, selected, ['location']);
          for (final item in food.state.containers) {
            final expected = _copy(before[item.id]!);
            if (selected.contains(item.id)) {
              (expected['details'] as Map)['location'] = '';
            }
            expect(item.toJson(), expected, reason: item.id);
          }
          final entry = history.latest!;
          folder.reset();
          folder.fault = 'prefix';
          await expectLater(
            food.undoOperations(entry.records),
            throwsStateError,
          );
          final preparedInverse = food.lastPreparedRecords;
          _expectExactInverse(preparedInverse, originals);
          await food.refresh();
          expect(preparedInverse.map(food.isAdmitted), [true, false, false]);
          expect(history.latest, same(entry));
          expect(history.length, 1);
          expect(entry.records, originals);
          expect(() => entry.records.clear(), throwsUnsupportedError);
          final partial = await folder.read(foodLogName(food.writer));
          await food.recoverPrepared();
          expect(preparedInverse.every(food.isAdmitted), true);
          history.complete(entry);
          expect(history.latest, isNull);
          expect(history.length, 0);
          expect(_snapshot(food), before);
          final recovered = await folder.read(foodLogName(food.writer));
          expect(recovered.take(partial.length).toList(), partial);
          final calls = folder.appends;
          expect(await food.undoOperations(entry.records), isEmpty);
          expect(folder.appends, calls);
          expect(await folder.read(foodLogName(food.writer)), recovered);
        },
      );

      test(
        '205-container Brand/Location Undo restores only local contributions and preserves newer peer fields across chunks',
        () async {
          final selected = food.state.active
              .take(205)
              .map((item) => item.id)
              .toList();
          final before = _snapshot(food);
          final untouched = food.state.active.last.id;
          await food.changeDetails(
            selected,
            const FoodDetails(
              name: 'Unused carrier',
              brand: 'Local brand',
              location: 'Local shelf',
              expiry: '2099-12-31',
              estimated: false,
            ),
            ['brand', 'location'],
          );
          final originals = food.lastPreparedRecords;
          _expectOneAction(history, food, originals, selected, [
            'brand',
            'location',
          ]);
          final entry = history.latest!;
          await peer.refresh();
          final peerChanges = [
            (
              id: selected[0],
              brand: 'Peer brand',
              location: 'Unused',
              fields: ['brand'],
            ),
            (
              id: selected[100],
              brand: 'Unused',
              location: 'Peer shelf',
              fields: ['location'],
            ),
            (
              id: selected[204],
              brand: 'Peer both brand',
              location: 'Peer both shelf',
              fields: ['brand', 'location'],
            ),
            (
              id: untouched,
              brand: 'Peer unselected brand',
              location: 'Peer unselected shelf',
              fields: ['brand', 'location'],
            ),
          ];
          for (final edit in peerChanges) {
            await peer.changeDetails(
              [edit.id],
              FoodDetails(
                name: 'Unused peer carrier',
                brand: edit.brand,
                location: edit.location,
                expiry: '2099-12-31',
              ),
              edit.fields,
            );
            expect(
              peer.lastPreparedRecords.single.clock.value,
              greaterThan(originals.last.clock.value),
            );
          }
          await food.refresh();
          expect(_item(food, selected[0]).details.brand, 'Peer brand');
          expect(_item(food, selected[100]).details.location, 'Peer shelf');
          final peerBytes = await folder.read(foodLogName(peer.writer));
          final localBytes = await folder.read(foodLogName(food.writer));
          folder.reset();
          final inverse = await food.undoOperations(entry.records);
          _expectExactInverse(inverse, originals);
          expect(inverse.every(food.isAdmitted), true);
          history.complete(entry);
          expect(folder.appends, 1);
          expect(history.length, 0);
          for (final edit in peerChanges) {
            final details = before[edit.id]!['details'] as Map;
            if (edit.fields.contains('brand')) details['brand'] = edit.brand;
            if (edit.fields.contains('location')) {
              details['location'] = edit.location;
            }
          }
          expect(_snapshot(food), before);
          expect(await folder.read(foodLogName(peer.writer)), peerBytes);
          final after = await folder.read(foodLogName(food.writer));
          expect(after.take(localBytes.length).toList(), localBytes);
          await peer.refresh();
          expect(_snapshot(peer), before);
        },
      );
    }

    if (actualHost) {
      testWidgets(
        'actual Food host groups a 205-container details callback into one Undo action',
        (tester) async {
          const user = '00000000-0000-4000-8000-000000000043';
          final profilePath = profile.root;
          await tester.runAsync(() async {
            await tasks.command(user, 'user.created', {
              'name': 'Bulk review user',
            });
            final preferences = LocalSettings(
              profile.root,
              profileDatabase: profile,
            );
            await preferences.load();
            preferences.folder = folder.location;
            preferences.user = user;
            await preferences.save();
            await food.close();
            await tasks.close();
            await profile.close();
          });
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profilePath,
              folderFactory: (_) => folder,
              timeSourceFactory: (changed) => ViewTimeSource(
                onChanged: changed,
                loadZone: () async => 'UTC',
                now: () => DateTime.utc(2026, 10, 11),
              ),
            ),
          );
          dynamic host;
          try {
            await _waitForHost(
              tester,
              () => find.byType(SectionMenu).evaluate().isNotEmpty,
            );
            host = tester.state(find.byType(TasksPage));
            tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(
              true,
            );
            await _waitForHost(
              tester,
              () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
            final page = tester.widget<FoodInventoryPage>(
              find.byType(FoodInventoryPage),
            );
            final observed = page.state.active.take(205).toList();
            final ids = observed.map((item) => item.id).toList();
            final origin = host.foodStore as FoodStore;
            final before = _snapshot(origin);
            final actualHistory = host.foodUndoHistory as FoodUndoHistory;
            expect(actualHistory.length, 0);
            folder.reset();
            await tester.runAsync(() async {
              await page.onDetails(
                observed,
                const FoodDetails(
                  name: 'Unused carrier',
                  brand: 'Host bulk brand',
                  location: '',
                  expiry: '2099-12-31',
                ),
                ['brand', 'location'],
              );
            });
            await tester.pumpAndSettle();
            expect(actualHistory.length, 1);
            final entry = actualHistory.latest!;
            expect(entry.label, 'editing 205 containers');
            expect(entry.records, origin.lastPreparedRecords);
            expect(entry.records, hasLength(3));
            expect(
              entry.records.expand((record) => record.operation.targets),
              ids,
            );
            expect(entry.records.every(origin.isAdmitted), true);
            expect(folder.appends, 1);
            await tester.runAsync(() async {
              await peer.refresh();
              await peer.changeDetails(
                [ids.last],
                const FoodDetails(
                  name: 'Unused peer carrier',
                  brand: 'Newer peer brand',
                  location: 'Newer peer shelf',
                  expiry: '2099-12-31',
                ),
                ['brand', 'location'],
              );
            });
            final peerBytes = await tester.runAsync(
              () => folder.read(foodLogName(peer.writer)),
            );
            final currentPage = tester.widget<FoodInventoryPage>(
              find.byType(FoodInventoryPage),
            );
            expect(currentPage.onUndo, isNotNull);
            await tester.runAsync(() async => await currentPage.onUndo!());
            await tester.pumpAndSettle();
            expect(actualHistory.length, 0);
            expect(actualHistory.latest, isNull);
            final peerDetails = before[ids.last]!['details'] as Map;
            peerDetails['brand'] = 'Newer peer brand';
            peerDetails['location'] = 'Newer peer shelf';
            expect(_snapshot(origin), before);
            expect(
              await tester.runAsync(
                () => folder.read(foodLogName(peer.writer)),
              ),
              peerBytes,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            if (host != null) {
              await tester.runAsync(() async {
                await host.foodStore?.close();
                await host.store?.close();
                await host.profileDatabase?.close();
              });
            }
          }
        },
      );
    }
  });
}

FoodContainer _item(FoodStore store, String id) =>
    store.state.containers.singleWhere((item) => item.id == id);

Map<String, Map<String, dynamic>> _snapshot(FoodStore store) => {
  for (final item in store.state.containers) item.id: _copy(item.toJson()),
};

Map<String, dynamic> _copy(Map<String, dynamic> source) =>
    (jsonDecode(jsonEncode(source)) as Map).cast<String, dynamic>();

void _expectOneAction(
  FoodUndoHistory history,
  FoodStore store,
  List<FoodRecord> records,
  List<String> selected,
  List<String> fields,
) {
  expect(records, hasLength(3));
  expect(records.map((record) => record.operation.targets.length), [
    100,
    100,
    5,
  ]);
  expect(records.expand((record) => record.operation.targets), selected);
  expect(records.every(store.isAdmitted), true);
  for (final record in records) {
    expect(record.operation.action, FoodAction.edit);
    expect(record.operation.fields, fields);
  }
  history.record('editing', records, confirmed: store.isAdmitted);
  expect(history.length, 1);
  expect(history.latest!.label, 'editing 205 containers');
  expect(history.latest!.records, records);
  expect(
    history.latest!.records.map((record) => record.hash),
    records.map((record) => record.hash),
  );
}

void _expectExactInverse(List<FoodRecord> inverse, List<FoodRecord> originals) {
  expect(inverse, hasLength(3));
  expect(
    inverse.map((record) => record.operation.retracts),
    originals.map((record) => record.id),
  );
  for (var i = 0; i < inverse.length; i++) {
    expect(inverse[i].operation.action, FoodAction.undo);
    expect(inverse[i].operation.targets, originals[i].operation.targets);
    expect(inverse[i].operation.details, isNull);
    expect(inverse[i].operation.contents, isNull);
  }
}

Future<void> _waitForHost(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    if (ready()) return;
  }
  final host = tester.state(find.byType(TasksPage)) as dynamic;
  fail(
    'The synthetic host did not become ready within the bounded wait: '
    'busy=${host.busy}, settingsLoaded=${host.settingsLoaded}, '
    'error=${host.error}, safety=${host.sharedSafetyError}',
  );
}
