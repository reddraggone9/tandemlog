// SOURCE-ONLY UNCOMPILED VIABILITY DRAFT; no user profile/live workspace.
// Fork destination: integration_test/windows_release_widget_viability.dart.
// Framework input/state/frame timings, NOT OS input/presentation/installer gate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart' show NativeTaskFixtures;

// Explicit framework text-channel stub. The default integration binding keeps
// the engine channel real, so tester.enterText has client -1; RELEASE correctly
// rejects that mismatched client. Register the existing test channel BEFORE
// test initialization. Domain NativeTextEngine/capture/Undo remain production.
class FrameworkInputBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

const initialTitle = 'Public Windows viability task';
const editedTitle = 'Public Windows viability task edited';
void require(bool value, String reason) {
  if (!value) throw StateError(reason); // Explicit checks survive release.
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
  void emit(String phase, Map<String, Object?> data) {
    log.writeAsStringSync(
      '${jsonEncode({'phase': phase, 'elapsedUs': watch.elapsedMicroseconds, 'release': kReleaseMode, 'pid': pid, ...data})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  emit('bootstrap', {
    'syntheticOnly': true,
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
    final user = const Uuid().v4(), task = const Uuid().v4();
    final seedEngine = OwnedEngine(library);
    TaskStore? seed;
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
      final start = watch.elapsedMicroseconds, frameStart = frames.length;
      await tester.tap(finder);
      final returned = watch.elapsedMicroseconds;
      await wait(ready, name);
      final observed = watch.elapsedMicroseconds;
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => done.complete());
      await tester.pump();
      await done.future.timeout(const Duration(seconds: 10));
      emit('action', {
        'name': name,
        'startUs': start,
        'inputReturnedUs': returned - start,
        'stateObservedUs': observed - start,
        'postFrameObservedUs': watch.elapsedMicroseconds - start,
        'nestedCumulativeNotExclusive': true,
        'pollRequestedUs': 1000,
        'pumpObserverOverheadIncluded': true,
        'frameDeliverySliceFrom': frameStart,
        'frameDeliverySliceTo': frames.length,
      });
    }

    try {
      seed = await TaskStore.open(
        LocalLogFolder(shared.path),
        '${root.path}/seed-profile',
        textEngine: seedEngine,
      );
      await seed.command(user, 'user.created', {
        'name': 'Public viability user',
      });
      await seed.createNativeFixtureTask(task, {
        'title': initialTitle,
        'description': 'Preserved native notes',
        'assignee': user,
      });
      await seed.close();
      seed = null;
      seedEngine.dispose();
      profileDb = await LocalProfileDatabase.open(profile);
      await LocalSettings.initialize(profileDb);
      final settings = LocalSettings(profile, profileDatabase: profileDb);
      await settings.load();
      settings.folder = shared.path;
      settings.user = user;
      await settings.save();
      final writer = settings.writer;
      final enrollEngine = OwnedEngine(library);
      UnifiedHistory? enrollment;
      try {
        enrollment = await UnifiedHistory.open(
          LocalLogFolder(shared.path),
          profile: profileDb,
          writer: writer,
          textEngine: enrollEngine,
        );
      } finally {
        await enrollment?.close();
        enrollEngine.dispose();
      }
      await profileDb.close();
      profileDb = null;
      final before = await canonical(shared);
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile,
          textEngineFactory: () => appEngine = OwnedEngine(library),
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
      final base = history.physicalSequence;
      emit('startup-ready', {
        'fixtureTasks': 1,
        'baselinePhysicalSequence': base,
        'appProjectionCachePrimedByHarness': false,
      });
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
      await seed?.close();
      if (!seedEngine.closed) seedEngine.dispose();
      await profileDb?.close();
      emit('target-teardown', {
        'normalShutdownAccepted': normal,
        'appNativeDisposed': appEngine?.closed,
        'privateRootRetained': true,
      });
    }
  });
}
