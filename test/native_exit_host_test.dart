import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/presentation/section_menu.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'section_navigation_host_test.dart' as host;

class CountedEngine extends host.ObservedNativeEngine {
  int closes = 0;
  bool failAfterClose = false;
  @override
  void dispose() {
    closes++;
    super.dispose();
    if (failAfterClose) throw StateError('Synthetic post-dispose failure');
  }
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  late List<CountedEngine> engines;
  NativeTextEngine engine() {
    final value = CountedEngine();
    engines.add(value);
    return value;
  }

  setUp(() => engines = []);
  Future<void> start(
    WidgetTester tester,
    String profile, {
    LogFolder? folder,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: profile,
        folderFactory: folder == null ? null : (_) => folder,
        textEngineFactory: engine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    await host.ready(tester, () {
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      return state.store != null && state.busy == false;
    });
  }

  Future<AppExitResponse> exit(WidgetTester tester, dynamic state) async {
    AppExitResponse? result;
    final future = (state.didRequestAppExit() as Future<AppExitResponse>).then(
      (value) => result = value,
    );
    await host.ready(tester, () => result != null, settle: false);
    await future;
    return result!;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  void resetView(WidgetTester tester) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets(
    'normal exit without unmount seals cache, releases lease, and actual reopen reuses proof once',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      // Keep an equivalent spelling that Python Path normalizes on every OS.
      final rawFolder = LocalLogFolder('${data.folder.location}/.');
      host.HostResources? resources;
      try {
        await start(tester, data.profile, folder: rawFolder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        resources = host.hostResources(tester);
        final anchorIndex =
            '${(state.store as TaskStore).tables.events}_type_before';
        final before = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        expect(await exit(tester, state), AppExitResponse.exit);
        expect(
          find.byType(TasksPage),
          findsOneWidget,
          reason:
              'The native exit observer must close resources without Flutter unmounting.',
        );
        expect(engines.single.closes, 1);
        await host.waitForHostShutdown(tester, resources);
        final witness = (await tester.runAsync(() async {
          final profile = await LocalProfileDatabase.open(data.profile);
          try {
            // Simulate a closed cache created before the additive query index.
            // The content witness remains valid; warm attach must install it.
            profile.database.execute('DROP INDEX $anchorIndex');
            expect(
              profile.database.select(
                "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
                [anchorIndex],
              ),
              isEmpty,
            );
            return profile.database
                .select('SELECT key,value FROM profile_metadata')
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
          } finally {
            await profile.close();
          }
        }))!;
        expect(
          witness.where(
            (row) => (row['key'] as String).startsWith('app5.task.cache.'),
          ),
          hasLength(1),
        );
        expect(
          witness.where(
            (row) => (row['key'] as String).startsWith('app5.decoded.proof.'),
          ),
          hasLength(1),
        );
        expect(
          jsonDecode(
            witness.singleWhere(
                  (row) =>
                      (row['key'] as String).startsWith('app5.task.cache.'),
                )['value']
                as String,
          )['generation'],
          3,
        );
        // Probe the actual production-created keys in the stopped database,
        // rather than a Python fake fixture repeating the helper's key formula.
        final probe = (await tester.runAsync(() async {
          final result = await Process.run(
            Platform.isWindows ? 'python' : 'python3',
            [
              '-c',
              'import json,sys; from pathlib import Path; sys.path.insert(0,"tool"); '
                  'from measure_startup import inspect_stopped_witness; '
                  'p=Path(sys.argv[1]); f=Path(sys.argv[2]); '
                  'value=inspect_stopped_witness(p,f,folder_location=sys.argv[2]); '
                  'value["normalizedTaskProofPresent"]=inspect_stopped_witness(p,f)["taskProofPresent"]; '
                  'print(json.dumps(value))',
              data.profile,
              rawFolder.location,
            ],
            workingDirectory: Directory.current.path,
          ).timeout(const Duration(seconds: 10));
          expect(result.exitCode, 0, reason: result.stderr.toString());
          return jsonDecode(result.stdout as String) as Map<String, dynamic>;
        }))!;
        expect(probe['normalizedTaskProofPresent'], isFalse);
        expect(probe['taskProofShapeValid'], isTrue);
        expect(probe['decodedProofPresent'], isTrue);
        expect(probe['decodedPayloadHashMatches'], isTrue);
        expect(probe['productionReuseVerified'], isFalse);
        expect(await exit(tester, state), AppExitResponse.exit);
        await unmount(tester);
        expect(
          engines.first.closes,
          1,
          reason: 'dispose joins the same already completed shutdown.',
        );
        await start(tester, data.profile, folder: rawFolder);
        final reopened = tester.state(find.byType(TasksPage)) as dynamic;
        final tasks = reopened.store as TaskStore;
        expect(tasks.warmProjectionReuses, 1);
        expect(
          tasks.db.select(
            "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
            [anchorIndex],
          ),
          hasLength(1),
        );
        expect(tasks.unified!.decodedCacheReuses, greaterThan(0));
        expect(
          (await tester.runAsync(() => host.canonical(data.folder)))!,
          before,
        );
        resources = host.hostResources(tester);
        expect(await exit(tester, reopened), AppExitResponse.exit);
        await unmount(tester);
        await host.waitForHostShutdown(tester, resources);
        expect(engines.map((value) => value.closes), [1, 1]);
        expect(tester.takeException(), isNull);
      } finally {
        await unmount(tester);
        if (resources != null) {
          await host.waitForHostShutdown(tester, resources);
        }
        resetView(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'accepted concurrent exit and dispose wait for actual held importer work and close once',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      final folder = host.FaultingFolder(data.folder);
      host.HostResources? resources;
      Completer<void>? held;
      try {
        await start(tester, data.profile, folder: folder);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        resources = host.hostResources(tester);
        final switchSection = tester
            .widget<SectionMenu>(find.byType(SectionMenu))
            .onSelected!;
        await host.ready(tester, () => state.syncing == null);
        held = folder.heldRead = Completer<void>();
        state.importer.request();
        await host.ready(
          tester,
          () => folder.reading && state.syncing != null,
          settle: false,
        );
        AppExitResponse? response;
        final first = state.didRequestAppExit() as Future<AppExitResponse>;
        final second = state.didRequestAppExit() as Future<AppExitResponse>;
        expect(identical(first, second), isTrue);
        unawaited(first.then((value) => response = value));
        await host.ready(
          tester,
          () => find.byKey(const ValueKey('app-closing')).evaluate().isNotEmpty,
          settle: false,
        );
        expect(response, isNull);
        expect(engines.single.closes, 0);
        expect(find.byKey(const ValueKey('app-closing')), findsOneWidget);
        final revision = state.sectionRevision;
        switchSection(true);
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(state.sectionRevision, revision);
        expect(state.requestedSection, isNull);
        await unmount(tester);
        expect(
          engines.single.closes,
          0,
          reason: 'Disposal cannot overtake in-flight native/profile work.',
        );
        held.complete();
        await host.ready(tester, () => response != null, settle: false);
        expect(await first, AppExitResponse.exit);
        expect(await second, AppExitResponse.exit);
        await host.waitForHostShutdown(tester, resources);
        expect(engines.single.closes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (held != null && !held.isCompleted) held.complete();
        await unmount(tester);
        if (resources != null) {
          await host.waitForHostShutdown(tester, resources);
        }
        resetView(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'busy startup and canceled dirty-draft exit do not begin shutdown; a subsequent Save still works',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      final folder = host.FaultingFolder(data.folder);
      final held = folder.heldRead = Completer<void>();
      host.HostResources? resources;
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 800);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: data.profile,
            folderFactory: (_) => folder,
            textEngineFactory: engine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        );
        await host.ready(tester, () => folder.reading, settle: false);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(await state.didRequestAppExit(), AppExitResponse.cancel);
        expect(engines.single.closes, 0);
        held.complete();
        await host.ready(
          tester,
          () => state.store != null && state.busy == false,
        );
        resources = host.hostResources(tester);
        await tester.tap(find.text('Synthetic section task'));
        final notes = find.byKey(const ValueKey('description'));
        await host.ready(tester, () => notes.evaluate().isNotEmpty);
        await tester.enterText(
          notes,
          'Synthetic draft survives canceled close',
        );
        AppExitResponse? result;
        final request = (state.didRequestAppExit() as Future<AppExitResponse>)
            .then((value) => result = value);
        await host.ready(
          tester,
          () => find.text('Unsaved changes').evaluate().isNotEmpty,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await host.ready(tester, () => result != null);
        await request;
        expect(result, AppExitResponse.cancel);
        expect(engines.single.closes, 0);
        expect(resources.database.select('SELECT 1').single.values.single, 1);
        expect(
          tester.widget<TextField>(notes).controller!.text,
          'Synthetic draft survives canceled close',
        );
        expect(find.byKey(const ValueKey('app-closing')), findsNothing);
        await tester.tap(find.text('Save changes'));
        await host.ready(
          tester,
          () =>
              find.byType(TaskEditor).evaluate().isEmpty && state.busy == false,
        );
        expect(
          (state.store as TaskStore).rows.singleWhere(
            (row) => row['kind'] == 'task',
          )['description'],
          'Synthetic draft survives canceled close',
        );
        expect(await exit(tester, state), AppExitResponse.exit);
        await unmount(tester);
        await host.waitForHostShutdown(tester, resources);
        expect(engines.single.closes, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!held.isCompleted) held.complete();
        await unmount(tester);
        if (resources != null) {
          await host.waitForHostShutdown(tester, resources);
        }
        resetView(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );

  testWidgets(
    'cleanup failure is reported once, remaining lease closes, and repeated exit explicitly exits',
    (tester) async {
      final data = (await tester.runAsync(host.fixture))!;
      host.HostResources? resources;
      final failures = <FlutterErrorDetails>[];
      final originalHandler = FlutterError.onError;
      try {
        await start(tester, data.profile);
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        resources = host.hostResources(tester);
        engines.single.failAfterClose = true;
        FlutterError.onError = failures.add;
        expect(await exit(tester, state), AppExitResponse.exit);
        expect(await exit(tester, state), AppExitResponse.exit);
        expect(find.byKey(const ValueKey('app-closing')), findsOneWidget);
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() async {
          final profile = await LocalProfileDatabase.open(data.profile);
          await profile.close();
        });
        await unmount(tester);
        expect(engines.single.closes, 1);
        expect(failures, hasLength(1));
        expect(
          failures.single.exception.toString(),
          contains('Synthetic post-dispose failure'),
        );
      } finally {
        await unmount(tester);
        if (resources != null) {
          await host.waitForHostShutdown(tester, resources);
        }
        FlutterError.onError = originalHandler;
        resetView(tester);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
}
