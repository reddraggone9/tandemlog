// Separate release framework probe on the sealed public realistic workload.
// Fork destination: integration_test/windows_release_widget_viability.dart.
// Framework input/state/frame timings, NOT OS input/presentation/installer gate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' show calloc;
import 'dart:ui' show AppExitResponse, FrameTiming, FramePhase;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import '../tool/windows_widget_qa/probe_cost_trace.dart';

// Explicit framework text-channel stub. The default integration binding keeps
// the engine channel real, so tester.enterText has client -1; RELEASE correctly
// rejects that mismatched client. Register the existing test channel BEFORE
// test initialization. Domain NativeTextEngine/capture/Undo remain production.
class FrameworkInputBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

const initialTitle = 'Benchmark historical task 3';
const editedTitle = 'Benchmark paired title';
void require(bool value, String reason) {
  if (!value) throw StateError(reason); // Explicit checks survive release.
}

const publicFixtureHash =
    '74f0c24ce01a26792ff4d8a1730c36b1aacdf6a918b90df8310a79386753aeb1';
bool ownsForeground() {
  final user32 = ffi.DynamicLibrary.open('user32.dll');
  final foreground = user32
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('GetForegroundWindow');
  final owner = user32
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint32>)
      >('GetWindowThreadProcessId');
  final result = calloc<ffi.Uint32>();
  try {
    owner(foreground(), result);
    return result.value == pid;
  } finally {
    calloc.free(result);
  }
}

class OwnedEngine extends NativeTextEngine {
  OwnedEngine(String library) : super(libraryPath: library);
  bool closed = false;
  @override
  void dispose() {
    super.dispose();
    closed = true;
  }
}

String sha(List<int> bytes) => sha256.convert(bytes).toString();
Future<Map<String, List<int>>> canonical(Directory shared) async {
  final result = <String, List<int>>{};
  await for (final entity in shared.list(followLinks: false)) {
    require(entity is File, 'Unexpected canonical directory/link.');
    final name = entity.uri.pathSegments.last;
    require(
      name == 'tandemlog-space.json' || name.endsWith('.applog'),
      'Unexpected canonical file.',
    );
    result[name] = await (entity as File).readAsBytes();
  }
  require(result.containsKey('tandemlog-space.json'), 'Missing manifest.');
  return result;
}

void prefixes(
  Map<String, List<int>> before,
  Map<String, List<int>> after,
  String ownerFile,
) {
  require(
    before.length == after.length &&
        before.keys.toSet().containsAll(after.keys),
    'Inventory changed.',
  );
  for (final entry in before.entries) {
    final next = after[entry.key]!;
    require(
      next.length >= entry.value.length &&
          sha(next.sublist(0, entry.value.length)) == sha(entry.value),
      'Original prefix changed.',
    );
    if (entry.key != ownerFile) {
      require(sha(next) == sha(entry.value), 'Nonowner file changed.');
    }
  }
}

Map<String, Object?> semantic(Map<String, dynamic> row) => {
  for (final key in [
    'id',
    'title',
    'description',
    'assignee',
    'schedule',
    'tags',
    'tagRefs',
    'completed',
  ])
    key: row[key],
};

void main() {
  require(
    Platform.isWindows && kReleaseMode,
    'Only Windows RELEASE viability is supported.',
  );
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'] ?? '';
  require(
    library.isNotEmpty && File(library).existsSync(),
    'Exact pinned real native DLL required.',
  );
  final runName = Platform.environment['TANDEMLOG_WINDOWS_WIDGET_RUN'] ?? '';
  require(
    RegExp(r'^windows-widget-viability-[a-zA-Z0-9-]{16,80}$').hasMatch(runName),
    'Fresh opaque owned run name required.',
  );
  final root = Directory('${Directory.systemTemp.path}/$runName');
  require(
    FileSystemEntity.typeSync(root.path, followLinks: false) ==
        FileSystemEntityType.notFound,
    'Existing run root refused.',
  );
  root.createSync();
  final log = File('${root.path}/probe.jsonl');
  final watch = Stopwatch()..start();
  final costTrace =
      Platform.environment['TANDEMLOG_WINDOWS_WIDGET_COSTS'] == '1'
      ? ProbeCostTrace(() => watch.elapsedMicroseconds)
      : null;
  void emit(String phase, Map<String, Object?> data) {
    log.writeAsStringSync(
      '${jsonEncode({'phase': phase, 'elapsedUs': watch.elapsedMicroseconds, 'release': kReleaseMode, 'pid': pid, ...data})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  emit('bootstrap', {
    'syntheticOnly': true,
    'providerCostTracingEnabled': costTrace != null,
    'nativeSHA256': sha(File(library).readAsBytesSync()),
    'osInputMeasured': false,
    'presentationMeasured': false,
    'frameworkTextChannelMocked': true,
    'artifactQualification': 'integration entrypoint, not installer',
  });
  final binding = FrameworkInputBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  binding.defaultTestTimeout = const Timeout(Duration(seconds: 110));
  unawaited(
    binding.allTestsPassed.future.then(
      (passed) => emit('suite-finished', {
        'passed': passed,
        'ownedNativeWindowNormalCloseStillRequired': true,
      }),
    ),
  );
  testWidgets('one release native Save and closed-editor Undo', (tester) async {
    final frames = <Map<String, Object?>>[];
    void onFrames(List<FrameTiming> batch) {
      for (final frame in batch) {
        frames.add({
          'deliveredAtProbeUs': watch.elapsedMicroseconds,
          'engineBuildStartUs': frame.timestampInMicroseconds(
            FramePhase.buildStart,
          ),
          'engineRasterFinishUs': frame.timestampInMicroseconds(
            FramePhase.rasterFinish,
          ),
          'buildUs': frame.buildDuration.inMicroseconds,
          'rasterUs': frame.rasterDuration.inMicroseconds,
          'totalSpanUs': frame.totalSpan.inMicroseconds,
        });
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onFrames);
    final shared = await Directory('${root.path}/shared').create();
    final profile = '${root.path}/profile';
    LocalProfileDatabase? profileDb;
    OwnedEngine? appEngine;
    dynamic host, connection;
    var normal = false;
    Future<void> wait(bool Function() ready, String label) async {
      final limit = watch.elapsed + const Duration(seconds: 20);
      while (!ready()) {
        require(watch.elapsed < limit, 'Timed out: $label');
        // Fully-live binding plus explicit pump/poll overhead, not a gate.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await tester.pump();
      }
    }

    Future<void> tap(String name, Finder finder, bool Function() ready) async {
      require(
        finder.evaluate().length == 1 &&
            finder.hitTestable().evaluate().length == 1,
        'Ambiguous/not hit-testable: $name',
      );
      final foregroundRequired =
          Platform.environment['TANDEMLOG_WINDOWS_WIDGET_FOREGROUND'] == '1';
      require(
        !foregroundRequired || ownsForeground(),
        'Probe lost foreground before $name.',
      );
      final start = watch.elapsedMicroseconds, frameStart = frames.length;
      await tester.tap(finder);
      final returned = watch.elapsedMicroseconds;
      await wait(ready, name);
      final observed = watch.elapsedMicroseconds;
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => done.complete());
      await tester.pump();
      await done.future.timeout(const Duration(seconds: 10));
      require(
        !foregroundRequired || ownsForeground(),
        'Probe lost foreground after $name.',
      );
      final finished = watch.elapsedMicroseconds;
      costTrace?.action(name, start, finished);
      emit('action', {
        'foregroundRequired': foregroundRequired,
        'name': name,
        'startUs': start,
        'inputReturnedUs': returned - start,
        'stateObservedUs': observed - start,
        'postFrameObservedUs': finished - start,
        'nestedCumulativeNotExclusive': true,
        'pollRequestedUs': 1000,
        'pumpObserverOverheadIncluded': true,
        'frameDeliverySliceFrom': frameStart,
        'frameDeliverySliceTo': frames.length,
      });
    }

    try {
      final fixturePath =
          Platform.environment['TANDEMLOG_WINDOWS_WIDGET_FIXTURE'] ?? '';
      require(fixturePath.isNotEmpty, 'Explicit public fixture required.');
      final fixture = Directory(fixturePath);
      final contractBytes = await File(
        '${fixture.path}/ui-fixture-original.json',
      ).readAsBytes();
      require(
        sha(contractBytes) == publicFixtureHash,
        'Public fixture contract differs.',
      );
      final contract =
          jsonDecode(utf8.decode(contractBytes)) as Map<String, dynamic>;
      require(
        contract['syntheticOnly'] == true &&
            contract['baselinePhysicalRecords'] == 1325,
        'Public realistic workload required.',
      );
      final expected = contract['files'] as Map<String, dynamic>;
      final input = await canonical(Directory('${fixture.path}/workspace'));
      require(
        input.length == 4 && input.keys.toSet().containsAll(expected.keys),
        'Public canonical inventory differs.',
      );
      for (final entry in input.entries) {
        require(
          sha(entry.value) == expected[entry.key],
          'Public canonical bytes differ.',
        );
        await File(
          '${shared.path}/${entry.key}',
        ).writeAsBytes(entry.value, flush: true);
      }
      final user = contract['user'] as String,
          task = contract['taskId'] as String;
      final fixtureWriter =
          (contract['writers'] as Map<String, dynamic>)['a'] as String;
      final setupProfile = await LocalProfileDatabase.open(profile);
      profileDb = setupProfile;
      await LocalSettings.initialize(setupProfile);
      // Synthetic identity only: preserve the fixture's already enrolled writer.
      // No TaskStore/enrollment is opened before measuring the app's cold cache.
      await setupProfile.serialize(() async {
        setupProfile.transaction(
          () => setupProfile.database.execute(
            'UPDATE protected_settings SET writer=?,raw=? WHERE singleton=1',
            [
              fixtureWriter,
              utf8.encode(
                jsonEncode({
                  'writer': fixtureWriter,
                  'folder': shared.path,
                  'user': user,
                  'appearance': 'light',
                  'lastSection': 'tasks',
                }),
              ),
            ],
          ),
        );
      });
      final settings = LocalSettings(profile, profileDatabase: setupProfile);
      await settings.load();
      final writer = settings.writer;
      require(writer == fixtureWriter, 'Synthetic writer binding differs.');
      await setupProfile.close();
      profileDb = null;
      final before = await canonical(shared);
      final foregroundRequired =
          Platform.environment['TANDEMLOG_WINDOWS_WIDGET_FOREGROUND'] == '1';
      final armPath =
          Platform.environment['TANDEMLOG_WINDOWS_WIDGET_ARM'] ?? '';
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('Preparing public synthetic probe'),
        ),
      );
      if (foregroundRequired) {
        require(armPath.isNotEmpty, 'Foreground controller arm path required.');
        final armFile = File(armPath);
        require(
          await armFile.parent.resolveSymbolicLinks() ==
              await root.resolveSymbolicLinks(),
          'Foreground arm must be inside this owned run.',
        );
        emit('awaiting-foreground-arm', {'run': runName});
        await wait(
          () => File(armPath).existsSync(),
          'foreground controller arm',
        );
        require(
          FileSystemEntity.typeSync(armPath, followLinks: false) ==
                  FileSystemEntityType.file &&
              await armFile.length() <= 4096,
          'Invalid foreground arm file.',
        );
        final arm =
            jsonDecode(await armFile.readAsString()) as Map<String, dynamic>;
        require(
          arm['run'] == runName &&
              arm['foreground'] == true &&
              ownsForeground(),
          'Foreground ownership not established.',
        );
      }
      Future<void> stageArm(String suffix, String stage) async {
        final marker = File('$armPath.$suffix');
        await wait(() => marker.existsSync(), 'owned $stage arm');
        require(
          await marker.parent.resolveSymbolicLinks() ==
                  await root.resolveSymbolicLinks() &&
              FileSystemEntity.typeSync(marker.path, followLinks: false) ==
                  FileSystemEntityType.file &&
              await marker.length() <= 4096,
          'Invalid owned stage arm.',
        );
        final data =
            jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
        require(
          data['run'] == runName && data['stage'] == stage && ownsForeground(),
          'Stage arm binding/foreground differs.',
        );
      }

      final mountStartedUs = watch.elapsedMicroseconds;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile,
          textEngineFactory: () => appEngine = OwnedEngine(library),
          folderFactory: (path) => costTrace == null
              ? LocalLogFolder(path)
              : ProbeLocalLogFolder(path, costTrace),
        ),
      );
      await wait(() {
        if (find.byType(TasksPage).evaluate().isEmpty) return false;
        host = tester.state(find.byType(TasksPage)) as dynamic;
        return host.store != null &&
            !host.busy &&
            find.text(initialTitle).evaluate().length == 1;
      }, 'real startup');
      connection = host.profileDatabase.database;
      final original = semantic(
        Map<String, dynamic>.from(
          host.store.rows.singleWhere((dynamic row) => row['id'] == task),
        ),
      );
      final history = host.store.unified as UnifiedHistory;
      require(
        history.snapshot.records.length == 1325,
        'Startup changed the sealed history or used the wrong workload.',
      );
      final logicalWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final logicalHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      require(
        !foregroundRequired ||
            ((logicalWidth - 1280).abs() <= 1 &&
                (logicalHeight - 860).abs() <= 1),
        'Foreground comparison viewport must be 1280x860 logical pixels.',
      );
      final base = history.physicalSequence;
      emit('startup-ready', {
        'fixtureProjectionRows': host.store.rows.length,
        'fixtureCanonicalRecords': history.snapshot.records.length,
        'fixtureContractSHA256': publicFixtureHash,
        'selectedTask': task,
        'appMountToStateReadyUs': watch.elapsedMicroseconds - mountStartedUs,
        'processStartupExcluded': true,
        'logicalWidth': logicalWidth,
        'logicalHeight': logicalHeight,
        'devicePixelRatio': tester.view.devicePixelRatio,
        'foregroundRequired': foregroundRequired,
        'baselinePhysicalSequence': base,
        'appProjectionCachePrimedByHarness': false,
      });
      if (foregroundRequired) {
        emit('awaiting-action-arm', {'run': runName});
        await stageArm('ready', 'action');
        require(ownsForeground(), 'Lost foreground before measured actions.');
      }
      await tap(
        'task-open',
        find.text(initialTitle),
        () => find.byType(TaskEditor).evaluate().length == 1,
      );
      // Framework text-channel injection excludes native keyboard/IME. The
      // real capture, native actor/session and production Save stay untouched.
      await tester.enterText(find.byKey(const ValueKey('title')), editedTitle);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('title')),
          matching: find.byType(EditableText),
        ),
      );
      require(
        editable.controller.text == editedTitle,
        'Framework text injection was not accepted before Save.',
      );
      await tap(
        'title-save',
        find.text('Save changes'),
        () =>
            find.byType(TaskEditor).evaluate().isEmpty &&
            !host.busy &&
            history.physicalSequence == base + 1 &&
            host.store.rows.singleWhere(
                  (dynamic row) => row['id'] == task,
                )['title'] ==
                editedTitle,
      );
      require(host.undoHistory.latest != null, 'Saved Undo owner missing.');
      require(find.byType(TaskEditor).evaluate().isEmpty, 'Editor still open.');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tap(
        'closed-editor-title-undo',
        find.byKey(const ValueKey('undo-task-action')),
        () =>
            !host.busy &&
            history.physicalSequence == base + 2 &&
            host.store.rows.singleWhere(
                  (dynamic row) => row['id'] == task,
                )['title'] ==
                initialTitle,
      );
      require(host.undoHistory.latest == null, 'Undo entry not consumed.');
      final suffix = history.snapshot.recordsByWriter[writer]!
          .where((record) => record.sequence > base)
          .toList();
      require(
        suffix.length == 2 &&
            suffix.every((record) => record.effects.length == 1),
        'Expected two atomic records.',
      );
      final save = suffix[0].effects.single.task;
      final undo = suffix[1].effects.single.task;
      require(
        save != null &&
            undo != null &&
            save.entity == task &&
            undo.entity == task &&
            save.type == 'task.textEdited' &&
            undo.type == 'task.textEditUndone' &&
            undo.data['operation'] == save.id,
        'Native Save/Undo type/target/reference mismatch.',
      );
      require(
        jsonEncode(
              semantic(
                Map<String, dynamic>.from(
                  host.store.rows.singleWhere(
                    (dynamic row) => row['id'] == task,
                  ),
                ),
              ),
            ) ==
            jsonEncode(original),
        'Task semantics did not restore.',
      );
      if (foregroundRequired) {
        emit('awaiting-inspection-arm', {'run': runName});
        await stageArm('inspected', 'inspection');
        require(ownsForeground(), 'Lost foreground before normal shutdown.');
      }
      require(
        await host.didRequestAppExit() == AppExitResponse.exit,
        'Normal product exit canceled.',
      );
      normal = true;
      require(
        appEngine != null && appEngine!.closed,
        'Native owner still open.',
      );
      var dbClosed = false;
      try {
        connection.select('SELECT 1');
      } on StateError catch (error) {
        dbClosed = error.message == 'This database has already been closed';
      }
      require(dbClosed, 'App profile connection still open.');
      final after = await canonical(shared);
      prefixes(before, after, '$writer.applog');
      final auditEngine = OwnedEngine(library);
      TaskStore? audit;
      try {
        // Full audit is AFTER normal close, on this disposable profile only.
        audit = await TaskStore.open(
          LocalLogFolder(shared.path),
          profile,
          textEngine: auditEngine,
        );
        await audit
            .verifyHistory(); // Return value means changed, not accepted.
        require(
          jsonEncode(
                semantic(
                  Map<String, dynamic>.from(
                    audit.rows.singleWhere((row) => row['id'] == task),
                  ),
                ),
              ) ==
              jsonEncode(original),
          'Full audit state differs.',
        );
      } finally {
        await audit?.close();
        auditEngine.dispose();
      }
      final audited = await canonical(shared);
      require(
        after.length == audited.length &&
            after.entries.every(
              (entry) => sha(entry.value) == sha(audited[entry.key]!),
            ),
        'Audit changed canonical.',
      );
      if (costTrace != null) {
        emit('provider-cost-trace', costTrace.report());
        require(
          costTrace.droppedSpans == 0,
          'Provider diagnostic overflow; action results remain preserved.',
        );
      }
      emit('normal-resources-closed', {
        'nativeDisposed': appEngine!.closed,
        'profileDatabaseClosed': dbClosed,
        'typedActionCount': 2,
        'fullAuditReturned': true,
        'prefixesPreserved': true,
        'nonownerUnchanged': true,
        'taskSemanticStateRestored': true,
        'frames': frames,
        'controllerMustVerifyOwnedWindowNormalExit': true,
      });
    } catch (failure, stack) {
      emit('failed', {'error': failure.toString(), 'stack': stack.toString()});
      rethrow;
    } finally {
      SchedulerBinding.instance.removeTimingsCallback(onFrames);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await profileDb?.close();
      emit('target-teardown', {
        'normalShutdownAccepted': normal,
        'appNativeDisposed': appEngine?.closed,
        'privateRootRetained': true,
      });
    }
  });
}
