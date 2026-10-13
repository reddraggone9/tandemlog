import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/platform/android_section_navigation.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/checklist_panel.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import '../integration_test/native_text_fixtures.dart';

late String nativeHostLibraryPath;

NativeTextEngine createHostTextEngine() =>
    NativeTextEngine(libraryPath: nativeHostLibraryPath);

class HeldPicker extends FolderActions {
  final picked = Completer<String?>();
  bool started = false;
  @override
  Future<String?> pick() {
    started = true;
    return picked.future;
  }

  @override
  Future<bool> canOpen(String location) async => false;
}

class FaultingFolder implements LogFolder, BoundedLogFolder {
  FaultingFolder(this.delegate);
  final LocalLogFolder delegate;
  bool wrongManifest = false;
  Completer<void>? heldRead;
  bool reading = false;
  @override
  String get location => delegate.location;
  @override
  Future<List<LogFileInfo>> list() => delegate.list();
  @override
  Future<Uint8List> read(String name) => readBounded(name, 32 * 1024 * 1024);
  @override
  Future<Uint8List> readBounded(String name, int limit) async {
    if (name == 'tandemlog-space.json') {
      if (heldRead != null) {
        reading = true;
        await heldRead!.future;
      }
      if (wrongManifest) {
        return Uint8List.fromList(
          utf8.encode('{"v":3,"id":"00000000-0000-4000-8000-000000000099"}'),
        );
      }
    }
    return delegate.readBounded(name, limit);
  }

  @override
  Future<void> create(String name, Uint8List bytes) =>
      delegate.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) =>
      delegate.append(name, bytes);
}

Future<void> ready(
  WidgetTester tester,
  bool Function() condition, {
  bool settle = true,
}) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(condition(), isTrue, reason: 'The guarded host must become ready');
  if (settle) await tester.pumpAndSettle();
}

Future<({Directory root, String profile, LocalLogFolder folder, String user})>
fixture({bool selectUser = true, AppSection section = AppSection.tasks}) async {
  final root = await Directory.systemTemp.createTemp('synthetic-section-host-');
  final data = await Directory('${root.path}/data').create(),
      profile = '${root.path}/profile';
  final user = const Uuid().v4(), task = const Uuid().v4();
  final folder = LocalLogFolder(data.path),
      seed = await openNativeFixtureStore(
        LocalLogFolder(data.path),
        '${root.path}/seed',
        nativeLibraryPath: nativeHostLibraryPath,
      );
  await seed.command(user, 'user.created', {'name': 'Synthetic section user'});
  await seed.createNativeFixtureTask(task, {
    'title': 'Synthetic section task',
    'description': '',
    'assignee': user,
  });
  await seed.close();
  final db = await LocalProfileDatabase.open(profile);
  await LocalProfileMigration(db).run();
  final settings = LocalSettings(profile, profileDatabase: db);
  await settings.load();
  settings.folder = folder.location;
  settings.user = selectUser ? user : null;
  await settings.save();
  if (section != AppSection.tasks) await settings.saveSection(section);
  await db.close();
  return (root: root, profile: profile, folder: folder, user: user);
}

Future<Map<String, List<int>>> canonical(LocalLogFolder folder) async => {
  for (final file in await Directory(
    folder.location,
  ).list().where((e) => e is File).cast<File>().toList())
    file.uri.pathSegments.last: await file.readAsBytes(),
};

void main() {
  final configured = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  if (configured == null ||
      configured.isEmpty ||
      !File(configured).existsSync()) {
    throw StateError(
      'section_navigation_host_test requires TANDEMLOG_TEXT_LIBRARY to name '
      'the real native test library built by CI.',
    );
  }
  nativeHostLibraryPath = File(configured).absolute.path;
  const channel = MethodChannel('tandemlog/sections-host-test');
  Future<void> native(WidgetTester tester, int id, String section) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('openSection', {'id': id, 'section': section}),
          ),
          (_) => done.complete(),
        );
    await done.future;
    await tester.pump();
  }

  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Future<void> cleanup(WidgetTester tester, Directory root) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.runAsync(() => root.delete(recursive: true));
  }

  testWidgets(
    'remembered Food and native Food wait for user setup; manual Tasks persists on reopen',
    (tester) async {
      final data = (await tester.runAsync(
        () => fixture(selectUser: false, section: AppSection.food),
      ))!;
      final before = (await tester.runAsync(() => canonical(data.folder)))!;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => {'id': 1, 'section': 'food'},
            );
        await tester.pumpWidget(
          TandemlogApp(
            textEngineFactory: createHostTextEngine,
            profilePath: data.profile,
            sectionNavigation: AndroidSectionNavigation(channel: channel),
          ),
        );
        await ready(
          tester,
          () => find.text('Synthetic section user').evaluate().isNotEmpty,
        );
        expect(find.byType(FoodInventoryPage), findsNothing);
        await tester.tap(find.text('Synthetic section user'));
        await ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        tester.widget<SectionMenu>(find.byType(SectionMenu)).onSelected!(false);
        await ready(
          tester,
          () => find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        final host = tester.state(find.byType(TasksPage)) as dynamic;
        final LocalProfileDatabase database = host.profileDatabase;
        await tester.pumpWidget(const SizedBox.shrink());
        // Disposal awaits pending preferences, importer and native handles.
        // A fixed sleep can reopen before the real installation lease closes.
        await ready(tester, () {
          try {
            database.database;
            return false;
          } on StateError {
            return true;
          }
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        await tester.pumpWidget(
          TandemlogApp(
            textEngineFactory: createHostTextEngine,
            profilePath: data.profile,
            sectionNavigation: AndroidSectionNavigation(channel: channel),
          ),
        );
        await ready(
          tester,
          () => find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        expect(find.byType(FoodInventoryPage), findsNothing);
        expect(await tester.runAsync(() => canonical(data.folder)), before);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );
  testWidgets(
    'coalesced shortcuts respect draft Cancel and newer Tasks wins Discard',
    (tester) async {
      final data = (await tester.runAsync(() => fixture()))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          TandemlogApp(
            textEngineFactory: createHostTextEngine,
            profilePath: data.profile,
            sectionNavigation: AndroidSectionNavigation(channel: channel),
          ),
        );
        await ready(
          tester,
          () => find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        final before = (await tester.runAsync(() => canonical(data.folder)))!;
        await tester.tap(find.text('Synthetic section task'));
        final notes = find.byKey(const ValueKey('description'));
        await ready(tester, () => notes.evaluate().isNotEmpty);
        await tester.enterText(notes, 'Synthetic preserved draft');
        await native(tester, 1, 'food');
        await ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await native(tester, 2, 'food');
        final cancel = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel').last)
            .onPressed!;
        cancel();
        cancel();
        await tester.pumpAndSettle();
        expect(find.byType(FoodInventoryPage), findsNothing);
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic preserved draft',
        );
        expect(find.text('Unsaved changes'), findsNothing);
        await native(tester, 3, 'food');
        await ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await native(tester, 4, 'tasks');
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic section task'), findsOneWidget);
        expect(find.byType(FoodInventoryPage), findsNothing);
        expect(await tester.runAsync(() => canonical(data.folder)), before);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester, data.root);
      }
    },
  );
  for (final sameFolder in [false, true]) {
    testWidgets(
      'shortcut drains after picker ${sameFolder ? 'same-folder' : 'Cancel'}',
      (tester) async {
        final data = (await tester.runAsync(() => fixture()))!;
        final picker = HeldPicker();
        try {
          await tester.pumpWidget(
            TandemlogApp(
              textEngineFactory: createHostTextEngine,
              profilePath: data.profile,
              folderActions: picker,
              sectionNavigation: AndroidSectionNavigation(channel: channel),
            ),
          );
          await ready(
            tester,
            () => find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          await tester.tap(find.byKey(const ValueKey('identity-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await ready(
            tester,
            () => find.text('Use a different folder').evaluate().isNotEmpty,
          );
          await tester.ensureVisible(find.text('Use a different folder'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Use a different folder'));
          await ready(tester, () => picker.started);
          await native(tester, 1, 'food');
          expect(find.byType(FoodInventoryPage), findsNothing);
          picker.picked.complete(sameFolder ? data.folder.location : null);
          await ready(
            tester,
            () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await cleanup(tester, data.root);
        }
      },
    );
  }
  testWidgets('shortcut drains when shared read recovery finishes', (
    tester,
  ) async {
    final data = (await tester.runAsync(() => fixture()))!;
    final folder = FaultingFolder(data.folder);
    try {
      await tester.pumpWidget(
        TandemlogApp(
          textEngineFactory: createHostTextEngine,
          profilePath: data.profile,
          folderFactory: (_) => folder,
          sectionNavigation: AndroidSectionNavigation(channel: channel),
        ),
      );
      await ready(
        tester,
        () => find.text('Synthetic section task').evaluate().isNotEmpty,
      );
      final host = tester.state(find.byType(TasksPage)) as dynamic;
      folder.wrongManifest = true;
      host.importer.request();
      await ready(tester, () => host.sharedSafetyError != null);
      folder.wrongManifest = false;
      folder.heldRead = Completer<void>();
      await tester.tap(find.widgetWithText(TextButton, 'Retry').last);
      await ready(tester, () => folder.reading, settle: false);
      await native(tester, 1, 'food');
      expect(find.byType(FoodInventoryPage), findsNothing);
      folder.heldRead!.complete();
      await ready(
        tester,
        () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
      );
      expect(host.sharedSafetyError, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester, data.root);
    }
  });
  testWidgets('newer Tasks shortcut survives workspace user setup', (
    tester,
  ) async {
    final first = (await tester.runAsync(
      () => fixture(section: AppSection.food),
    ))!;
    final second = (await tester.runAsync(() => fixture(selectUser: false)))!;
    final nextFolder = FaultingFolder(second.folder)
      ..heldRead = Completer<void>();
    final picker = HeldPicker();
    try {
      final beforeFirst = (await tester.runAsync(
        () => canonical(first.folder),
      ))!;
      final beforeSecond = (await tester.runAsync(
        () => canonical(second.folder),
      ))!;
      await tester.pumpWidget(
        TandemlogApp(
          textEngineFactory: createHostTextEngine,
          profilePath: first.profile,
          folderActions: picker,
          folderFactory: (location) =>
              location == second.folder.location ? nextFolder : first.folder,
          sectionNavigation: AndroidSectionNavigation(channel: channel),
        ),
      );
      await ready(
        tester,
        () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('identity-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await ready(
        tester,
        () => find.text('Use a different folder').evaluate().isNotEmpty,
      );
      await tester.ensureVisible(find.text('Use a different folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a different folder'));
      await ready(tester, () => picker.started);
      picker.picked.complete(second.folder.location);
      await ready(tester, () => nextFolder.reading, settle: false);
      await native(tester, 1, 'tasks');
      nextFolder.heldRead!.complete();
      await ready(
        tester,
        () => find.text('Synthetic section user').evaluate().isNotEmpty,
      );
      expect(find.byType(FoodInventoryPage), findsNothing);
      await tester.tap(find.text('Synthetic section user'));
      await ready(
        tester,
        () => find.text('Synthetic section task').evaluate().isNotEmpty,
      );
      expect(find.byType(FoodInventoryPage), findsNothing);
      final host = tester.state(find.byType(TasksPage)) as dynamic;
      await ready(tester, () => host.sectionWork == null);
      expect(host.settings.lastSection, AppSection.tasks);
      expect(await tester.runAsync(() => canonical(first.folder)), beforeFirst);
      expect(
        await tester.runAsync(() => canonical(second.folder)),
        beforeSecond,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester, first.root);
      await tester.runAsync(() => second.root.delete(recursive: true));
    }
  });
  testWidgets(
    'shortcut waits for checklist opening rather than treating it as Cancel',
    (tester) async {
      final data = (await tester.runAsync(() => fixture()))!;
      final gate = Completer<void>();
      try {
        final before = (await tester.runAsync(() => canonical(data.folder)))!;
        await tester.pumpWidget(
          TandemlogApp(
            textEngineFactory: createHostTextEngine,
            profilePath: data.profile,
            sectionNavigation: AndroidSectionNavigation(channel: channel),
          ),
        );
        await ready(
          tester,
          () => find.text('Synthetic section task').evaluate().isNotEmpty,
        );
        final host = tester.state(find.byType(TasksPage)) as dynamic;
        final String id = host.rows.singleWhere(
          (dynamic row) => row['kind'] == 'task',
        )['id'];
        host.setState(() => host.expandedChecklists.add(id));
        await tester.pumpAndSettle();
        host.syncing = gate.future;
        tester.widget<ChecklistPanel>(find.byType(ChecklistPanel)).onAdd();
        await tester.pump();
        expect(host.openingChecklistEditor, isTrue);
        await native(tester, 1, 'food');
        expect(find.byType(FoodInventoryPage), findsNothing);
        expect(
          host.requestedSection,
          isNotNull,
          reason:
              'An opening editor is a temporary block, not a user cancellation',
        );
        host.syncing = null;
        gate.complete();
        await ready(
          tester,
          () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
        );
        expect(find.byType(ChecklistItemEditor), findsNothing);
        expect(await tester.runAsync(() => canonical(data.folder)), before);
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await cleanup(tester, data.root);
      }
    },
  );
  for (final editor in ['Tasks', 'checklist', 'Food']) {
    for (final failSave in [false, true]) {
      testWidgets(
        'shortcut waits for $editor direct Save ${failSave ? 'failure' : 'success'}',
        (tester) async {
          final food = editor == 'Food';
          final data = (await tester.runAsync(
            () => fixture(section: food ? AppSection.food : AppSection.tasks),
          ))!;
          final gate = Completer<void>();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1100, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          try {
            final before = (await tester.runAsync(
              () => canonical(data.folder),
            ))!;
            await tester.pumpWidget(
              TandemlogApp(
                textEngineFactory: createHostTextEngine,
                profilePath: data.profile,
                sectionNavigation: AndroidSectionNavigation(channel: channel),
              ),
            );
            await ready(
              tester,
              () => food
                  ? find.byType(FoodInventoryPage).evaluate().isNotEmpty
                  : find.text('Synthetic section task').evaluate().isNotEmpty,
            );
            final host = tester.state(find.byType(TasksPage)) as dynamic;
            late Finder input, save;
            if (editor == 'Tasks') {
              await tester.tap(find.text('Synthetic section task'));
              input = find.byKey(const ValueKey('description'));
              await ready(tester, () => input.evaluate().isNotEmpty);
              await tester.enterText(input, 'Synthetic held Save');
              save = find.widgetWithText(FilledButton, 'Save changes');
            } else if (editor == 'checklist') {
              final String id = host.rows.singleWhere(
                (dynamic row) => row['kind'] == 'task',
              )['id'];
              host.setState(() => host.expandedChecklists.add(id));
              await tester.pumpAndSettle();
              tester
                  .widget<ChecklistPanel>(find.byType(ChecklistPanel))
                  .onAdd();
              input = find.byKey(const Key('checklist-item-title'));
              await ready(tester, () => input.evaluate().isNotEmpty);
              await tester.enterText(input, 'Synthetic held Save');
              save = find.byKey(const Key('checklist-item-save'));
            } else {
              await tester.tap(find.byTooltip('Add food'));
              await tester.pumpAndSettle();
              input = find.widgetWithText(TextField, 'Food name');
              await tester.enterText(input, 'Synthetic held Save');
              await tester.enterText(
                find.byKey(const ValueKey('food-expiration')),
                '2027-06-01',
              );
              save = find.widgetWithText(FilledButton, 'Add');
            }
            host.syncing = gate.future;
            await tester.ensureVisible(save);
            await tester.tap(save);
            await tester.pump();
            await native(tester, 1, food ? 'tasks' : 'food');
            expect(
              host.requestedSection,
              isNotNull,
              reason: 'A saving child is not a cancelled guard',
            );
            expect(host.foodVisible, food);
            host.syncing = null;
            if (failSave) {
              gate.completeError(StateError('Synthetic held save failure'));
              await ready(
                tester,
                () => find
                    .text(food ? 'Discard food changes?' : 'Unsaved changes')
                    .evaluate()
                    .isNotEmpty,
              );
              await tester.tap(
                find
                    .widgetWithText(
                      TextButton,
                      food ? 'Keep editing' : 'Cancel',
                    )
                    .last,
              );
              await tester.pumpAndSettle();
              expect(host.foodVisible, food);
              expect(
                tester.widget<TextField>(input).controller!.text,
                'Synthetic held Save',
              );
              expect(
                host.settings.lastSection,
                food ? AppSection.food : AppSection.tasks,
              );
              expect(
                await tester.runAsync(() => canonical(data.folder)),
                before,
              );
            } else {
              gate.complete();
              await ready(tester, () => host.foodVisible != food);
              if (editor == 'Tasks') {
                expect(
                  host.store.rows.singleWhere(
                    (dynamic row) => row['kind'] == 'task',
                  )['description'],
                  'Synthetic held Save',
                );
              } else if (editor == 'checklist') {
                expect(
                  host.store.rows
                      .singleWhere(
                        (dynamic row) => row['kind'] == 'task',
                      )['checklist']
                      .single['title'],
                  'Synthetic held Save',
                );
              } else {
                expect(
                  host.foodStore.state.containers.single.details.name,
                  'Synthetic held Save',
                );
              }
              final saved = (await tester.runAsync(
                () => canonical(data.folder),
              ))!;
              await native(tester, 2, food ? 'food' : 'tasks');
              await ready(
                tester,
                () => host.foodVisible == food && host.sectionWork == null,
              );
              expect(
                await tester.runAsync(() => canonical(data.folder)),
                saved,
              );
            }
            expect(tester.takeException(), isNull);
          } finally {
            if (!gate.isCompleted) gate.complete();
            await cleanup(tester, data.root);
          }
        },
      );
    }
  }
  for (final discard in [false, true]) {
    testWidgets(
      'shortcut shares an already-open Food close decision ${discard ? 'Discard' : 'Keep editing'}',
      (tester) async {
        final data = (await tester.runAsync(
          () => fixture(section: AppSection.food),
        ))!;
        try {
          final before = (await tester.runAsync(() => canonical(data.folder)))!;
          await tester.pumpWidget(
            TandemlogApp(
              textEngineFactory: createHostTextEngine,
              profilePath: data.profile,
              sectionNavigation: AndroidSectionNavigation(channel: channel),
            ),
          );
          await ready(
            tester,
            () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
          );
          final host = tester.state(find.byType(TasksPage)) as dynamic;
          await tester.tap(find.byTooltip('Add food'));
          await tester.pumpAndSettle();
          final name = find.widgetWithText(TextField, 'Food name');
          await tester.enterText(name, 'Synthetic decision draft');
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          await native(tester, 1, 'tasks');
          expect(find.text('Discard food changes?'), findsOneWidget);
          expect(host.requestedSection, isNotNull);
          await tester.tap(find.text(discard ? 'Discard' : 'Keep editing'));
          if (discard) {
            await ready(
              tester,
              () =>
                  find.text('Synthetic section task').evaluate().isNotEmpty &&
                  host.sectionWork == null,
            );
            expect(find.byType(FoodInventoryPage), findsNothing);
            expect(host.settings.lastSection, AppSection.tasks);
          } else {
            await tester.pumpAndSettle();
            expect(host.foodVisible, isTrue);
            expect(host.requestedSection, isNull);
            expect(find.text('Discard food changes?'), findsNothing);
            expect(
              tester.widget<TextField>(name).controller!.text,
              'Synthetic decision draft',
            );
            expect(host.settings.lastSection, AppSection.food);
          }
          expect(await tester.runAsync(() => canonical(data.folder)), before);
          expect(tester.takeException(), isNull);
        } finally {
          await cleanup(tester, data.root);
        }
      },
    );
  }
}
