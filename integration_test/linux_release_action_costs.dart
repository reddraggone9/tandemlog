// Diagnostic release entrypoint, never an installer or acceptance gate.
// Framework input/post-frame acknowledgments on actual Linux; no OS-input or
// compositor presentation claim. Inputs are generated public synthetic data.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse, FrameTiming;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_editor.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/food_store.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_completion_checkbox.dart';
import 'package:tandemlog/presentation/list_row_surface.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_manifest.dart' show bytesDigest;

import '../tool/performance/cost_trace.dart';
import '../tool/performance/synthetic_fixture.dart';
import 'windows_release_widget_viability.dart'
    show
        FrameworkInputBinding,
        OwnedEngine,
        canonical,
        prefixes,
        require,
        semantic;

void main() {
  require(Platform.isLinux && kReleaseMode, 'Linux release diagnostics only.');
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'] ?? '';
  require(File(library).existsSync(), 'Pinned native library required.');
  final specification =
      Platform.environment['TANDEMLOG_COST_FIXTURE'] ?? '1320';
  final shape = parseSyntheticFixtureSpec(specification);
  require(shape.baseRecords != 60, 'Realistic history shape required.');
  final path = Platform.environment['TANDEMLOG_COST_RUN_ROOT'] ?? '';
  require(
    path.isNotEmpty &&
        Directory(path).absolute.path == path &&
        FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.notFound,
    'Fresh absolute disposable output required.',
  );
  Directory(path).createSync();
  final log = File('$path/actions.jsonl');
  final clock = Stopwatch()..start();
  final trace = ProbeCostTrace(
    () => clock.elapsedMicroseconds,
    profileHookAttachment: 'after app startup; fixture generation excluded',
  );
  void emit(String phase, Map<String, Object?> data) => log.writeAsStringSync(
    '${jsonEncode({'phase': phase, 'shape': specification, 'pid': pid, 'release': kReleaseMode, 'platform': Platform.operatingSystem, 'osInputMeasured': false, 'presentationMeasured': false, 'releaseGateAccepted': false, ...data})}\n',
    mode: FileMode.append,
  );
  final binding = FrameworkInputBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.defaultTestTimeout = const Timeout(Duration(seconds: 110));
  unawaited(
    binding.allTestsPassed.future.then((passed) {
      emit('suite-finished', {'passed': passed});
      // The external owned-process controller sends WM_DELETE_WINDOW only after
      // this marker, checks actual exit and retains failure/timeout diagnostics.
      stdout.writeln('TANDEMLOG_COST_PROBE_DONE=$passed');
    }),
  );
  testWidgets(
    'Task and Food release action costs on a generated sealed history',
    (tester) async {
      dynamic host;
      OwnedEngine? engine;
      final frames = <Map<String, int>>[];
      var droppedFrames = 0;
      var timingAttached = true;
      void onFrames(List<FrameTiming> batch) {
        for (final frame in batch) {
          if (frames.length >= 512) {
            droppedFrames++;
            continue;
          }
          frames.add({
            'deliveredAtProbeUs': trace.now(),
            'buildUs': frame.buildDuration.inMicroseconds,
            'rasterUs': frame.rasterDuration.inMicroseconds,
            'totalSpanUs': frame.totalSpan.inMicroseconds,
          });
        }
      }

      SchedulerBinding.instance.addTimingsCallback(onFrames);
      Future<void> wait(bool Function() ready, String label) async {
        final deadline = clock.elapsed + const Duration(seconds: 20);
        while (!ready()) {
          require(clock.elapsed < deadline, 'Timed out: $label');
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }

      Future<void> inspect(String stage) async {
        if (Platform.environment['TANDEMLOG_COST_CAPTURE'] != '1') return;
        emit('inspection-ready', {'stage': stage});
        final marker = File('$path/$stage.arm');
        await wait(() => marker.existsSync(), '$stage capture');
        require(
          FileSystemEntity.typeSync(marker.path, followLinks: false) ==
                  FileSystemEntityType.file &&
              marker.lengthSync() <= 1024,
          'Invalid capture arm.',
        );
      }

      Future<void> tap(
        String name,
        Finder finder,
        bool Function() ready,
      ) async {
        require(finder.evaluate().length == 1, 'Unique $name target required.');
        if (finder.hitTestable().evaluate().length != 1) {
          await Scrollable.ensureVisible(
            finder.evaluate().single,
            alignment: .5,
          );
          await tester.pump();
        }
        require(
          finder.hitTestable().evaluate().length == 1,
          'Not hit-testable: $name',
        );
        final start = trace.now();
        await tester.tap(finder);
        final returned = trace.now();
        await wait(ready, name);
        final stateReady = trace.now();
        final frame = Completer<void>();
        SchedulerBinding.instance.addPostFrameCallback((_) => frame.complete());
        SchedulerBinding.instance.scheduleFrame();
        await frame.future.timeout(const Duration(seconds: 5));
        final end = trace.now();
        trace.action(name, start, end);
        emit('action', {
          'name': name,
          'inputReturnUs': returned - start,
          'stateReadyUs': stateReady - start,
          'frameworkPostFrameUs': end - start,
          'ordinaryVisibleResponseObjectiveUs': 100000,
          'objectiveExceededAtThisFrameworkBoundary': end - start >= 100000,
          'costs': trace.partition(start, end),
          'pollingForcesFrames': false,
        });
      }

      try {
        final fixture = await buildSyntheticFixture(
          Directory('$path/fixture'),
          shape.baseRecords,
          nativeLibrary: library,
          growthKind: shape.growthKind,
        );
        final shared = Directory(fixture['workspace'] as String);
        final profilePath = '$path/app-profile';
        final setup = await LocalProfileDatabase.open(profilePath);
        try {
          await LocalSettings.initialize(setup);
          setup.transaction(
            () => setup.database.execute(
              'UPDATE protected_settings SET writer=?,raw=? WHERE singleton=1',
              [
                fixture['writer'],
                utf8.encode(
                  jsonEncode({
                    'writer': fixture['writer'],
                    'folder': shared.path,
                    'user': fixture['user'],
                    'appearance': 'light',
                    'lastSection': 'tasks',
                  }),
                ),
              ],
            ),
          );
        } finally {
          await setup.close();
        }
        final originalBytes = await canonical(shared);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profilePath,
            textEngineFactory: () => engine = OwnedEngine(library),
            folderFactory: (path) => ProbeLocalLogFolder(path, trace),
          ),
        );
        final task = benchmarkId('task:1320:3');
        await wait(() {
          if (find.byType(TasksPage).evaluate().isEmpty) return false;
          host = tester.state(find.byType(TasksPage)) as dynamic;
          return host.store != null &&
              host.error == null &&
              host.sharedSafetyError == null &&
              !host.busy &&
              find.text('Benchmark historical task 3').evaluate().length == 1;
        }, 'startup');
        final store = host.store;
        final history = store.unified;
        final beforeTask = semantic(
          Map<String, dynamic>.from(store.visibleTaskRow(task)),
        );
        final sequence = history.physicalSequence as int;
        host.profileDatabase.diagnosticObserver = ProbeProfileDiagnostics(
          trace,
        );
        engine!.diagnosticObserver = ProbeProfileDiagnostics(trace);
        trace.reset();
        emit('startup-ready', {
          'fixture': fixture,
          'initialSequence': sequence,
          'logicalWidth':
              tester.view.physicalSize.width / tester.view.devicePixelRatio,
          'logicalHeight':
              tester.view.physicalSize.height / tester.view.devicePixelRatio,
          'fixtureGenerationInThisProcessBeforeMount': true,
        });
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        await inspect('tasks');
        await tap(
          'task-open',
          find.text('Benchmark historical task 3'),
          () => find.byType(TaskEditor).evaluate().length == 1,
        );
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Benchmark paired title',
        );
        await tester.pump();
        await tap(
          'title-save',
          find.text('Save changes'),
          () =>
              !host.busy &&
              find.byType(TaskEditor).evaluate().isEmpty &&
              store.visibleTaskRow(task)['title'] == 'Benchmark paired title' &&
              history.physicalSequence == sequence + 1,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tap(
          'title-undo',
          find.byKey(const ValueKey('undo-task-action')),
          () =>
              !host.busy &&
              store.visibleTaskRow(task)['title'] == beforeTask['title'] &&
              history.physicalSequence == sequence + 2,
        );
        final checkbox = find.descendant(
          of: find.byKey(ValueKey('task-row-$task')),
          matching: find.byType(TaskCompletionCheckbox),
        );
        await tap(
          'task-complete',
          checkbox,
          () =>
              !host.busy &&
              store.visibleTaskRow(task)['completed'] == true &&
              history.physicalSequence == sequence + 3,
        );
        await tap(
          'completion-undo',
          find.byKey(const ValueKey('undo-task-action')),
          () =>
              !host.busy &&
              store.visibleTaskRow(task)['completed'] == false &&
              history.physicalSequence == sequence + 4,
        );
        require(
          jsonEncode(
                semantic(Map<String, dynamic>.from(store.visibleTaskRow(task))),
              ) ==
              jsonEncode(beforeTask),
          'Task semantics did not restore.',
        );
        await tester.tap(find.byKey(const ValueKey('section-menu')));
        await tester.pumpAndSettle();
        await tap(
          'food-section',
          find.byKey(const ValueKey('module-food')),
          () =>
              find.byType(FoodInventoryPage).evaluate().isNotEmpty &&
              host.foodStore != null &&
              !host.busy,
        );
        final food = host.foodStore;
        final foodId = benchmarkId('food:1320:1000');
        String foodState() => jsonEncode(
          food.state.containers.map((dynamic c) => c.toJson()).toList(),
        );
        final beforeFood = foodState();
        final originalBrand = food.state.containers
            .singleWhere((dynamic c) => c.id == foodId)
            .details
            .brand;
        await tester.enterText(
          find.byKey(const ValueKey('food-search')),
          'Benchmark food 1000',
        );
        await tester.pumpAndSettle();
        await tap(
          'food-open',
          find.descendant(
            of: find.widgetWithText(ListRowSurface, 'Benchmark food 1000'),
            matching: find.text('Benchmark food 1000'),
          ),
          () => find.byType(FoodEditor).evaluate().length == 1,
        );
        final brand = find.descendant(
          of: find.byType(FoodEditor),
          matching: find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Brand',
          ),
        );
        await tester.enterText(brand, 'Benchmark paired brand');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tap(
          'food-save',
          find.byKey(const ValueKey('food-save-action')),
          () =>
              !host.busy &&
              food.state.containers
                      .singleWhere((dynamic c) => c.id == foodId)
                      .details
                      .brand ==
                  'Benchmark paired brand' &&
              history.physicalSequence == sequence + 5,
        );
        await tap(
          'food-undo',
          find.byKey(const ValueKey('undo-food-action')),
          () =>
              !host.busy &&
              food.state.containers
                      .singleWhere((dynamic c) => c.id == foodId)
                      .details
                      .brand ==
                  originalBrand &&
              history.physicalSequence == sequence + 6,
        );
        require(foodState() == beforeFood, 'Food semantics did not restore.');
        require(
          trace.droppedSpans == 0 &&
              engine!.diagnosticCallbackFailures == 0 &&
              host.profileDatabase.diagnosticCallbackFailures == 0,
          'Incomplete action diagnostics.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await inspect('food');
        emit('raw-costs', trace.report());
        emit('frame-timings', {
          'frames': frames,
          'dropped': droppedFrames,
          'engineDurationsAreSeparateFromProbeClockDeliveryTimes': true,
        });
        require(droppedFrames == 0, 'Frame diagnostic bound exceeded.');
        SchedulerBinding.instance.removeTimingsCallback(onFrames);
        timingAttached = false;
        require(
          await host.didRequestAppExit() == AppExitResponse.exit &&
              engine!.closed,
          'Product resources did not close normally.',
        );
        prefixes(
          originalBytes,
          await canonical(shared),
          '${fixture['writer']}.applog',
        );
        final beforeAudit = await canonical(shared);
        final auditEngine = OwnedEngine(library);
        TaskStore? audit;
        FoodStore? auditFood;
        try {
          audit = await TaskStore.open(
            LocalLogFolder(shared.path),
            profilePath,
            textEngine: auditEngine,
          );
          await audit.verifyHistory();
          auditFood = await FoodStore.openUnified(audit.unified!);
          require(
            jsonEncode(semantic(audit.visibleTaskRow(task)!)) ==
                jsonEncode(beforeTask),
            'Full replay Task state differs.',
          );
          require(
            jsonEncode(
                  auditFood.state.containers.map((c) => c.toJson()).toList(),
                ) ==
                beforeFood,
            'Full replay Food state differs.',
          );
        } finally {
          await auditFood?.close();
          await audit?.close();
          auditEngine.dispose();
        }
        final afterAudit = await canonical(shared);
        require(
          beforeAudit.length == afterAudit.length &&
              beforeAudit.entries.every(
                (entry) =>
                    bytesDigest(entry.value) ==
                    bytesDigest(afterAudit[entry.key]!),
              ),
          'Full replay changed canonical bytes.',
        );
        emit('verified', {
          'typedActionCount': 6,
          'taskAndFoodStateRestored': true,
          'prefixesPreserved': true,
          'normalProductResourceClose': true,
          'fullReplayReturnedWithUnchangedCanonicalBytes': true,
          'nativeWindowExitStillRequiresController': true,
        });
      } catch (error, stack) {
        emit('failed', {
          'error': error.toString(),
          'stack': stack.toString(),
          'hostError': host?.error,
          'sharedSafetyError': host?.sharedSafetyError,
        });
        rethrow;
      } finally {
        if (timingAttached) {
          SchedulerBinding.instance.removeTimingsCallback(onFrames);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        emit('teardown', {'nativeDisposed': engine?.closed});
      }
    },
  );
}
