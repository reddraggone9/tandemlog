import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

/// Fixture peers use the same production adapter as the running application.
/// An engine-less peer cannot observe required native canonical event types.
Future<TaskStore> openNativeFixtureStore(
  LogFolder folder,
  String privatePath, {
  DateTime Function()? now,
}) async {
  final engine = NativeTextEngine();
  addTearDown(engine.dispose);
  return TaskStore.open(folder, privatePath, textEngine: engine, now: now);
}

extension NativeTaskFixtures on TaskStore {
  /// Historical v3 recurrence stays unactivated in this fixture to cover old
  /// scalar compatibility independently of the additive native contract.
  Future<LogEvent> createHistoricalRecurrenceFixtureTask(
    String entity,
    Map<String, dynamic> data,
  ) => command(entity, 'task.created', data);

  /// New upgraded tasks have their own immutable text basis and work offline.
  Future<LogEvent> createNativeFixtureTask(
    String entity,
    Map<String, dynamic> data,
  ) => command(entity, 'task.createdWithText', {
    ...data,
    'text': {
      'codec': 'yrs-v1',
      'adapter': 1,
      'seeds': {
        for (final field in ['title', 'description'])
          field: sha256
              .convert(textEngine!.seedText(data[field] as String? ?? '').bytes)
              .toString(),
      },
    },
  });

  /// Incoming fixture text retains character intent through a real capture.
  /// Metadata-only edits keep the existing observed OR-set tag semantics.
  Future<void> editNativeFixtureTask(
    String entity,
    Map<String, dynamic> data,
  ) async {
    if (!data.containsKey('title') && !data.containsKey('description')) {
      await command(entity, 'task.edited', data);
      return;
    }
    final capture = await captureTaskText(entity);
    final session = TaskTextSession(
      capture,
      registerDraftActor: (field, allocation, actor) =>
          registerTextDraftActor(capture, field, allocation, actor),
    );
    try {
      for (final field in ['title', 'description']) {
        if (data.containsKey(field)) {
          session.replace(field, data[field] as String);
        }
      }
      final row = rows.singleWhere((row) => row['id'] == entity);
      final fields = Map<String, dynamic>.from(data)
        ..remove('title')
        ..remove('description');
      final result = await TextSaveCommand(this, session).save(
        fields: fields,
        tags: List<String>.from(row['tags'] as List),
        observedTagRefs: Map<String, String>.from(row['tagRefs'] as Map),
      );
      if (result.status == TextSaveStatus.unchanged) {
        // Existing fixture setup explicitly triages an unchanged raw capture.
        // Use the same ordinary metadata command available to production.
        await edit(
          entity,
          {'assignee': row['assignee']},
          tags: List<String>.from(row['tags'] as List),
          observedTagRefs: Map<String, String>.from(row['tagRefs'] as Map),
        );
      }
      if (result.undoError != null || result.sessionError != null) {
        throw StateError(
          'Native fixture Save could not retain its session ownership.',
        );
      }
    } finally {
      session.cancel();
      releaseTextCapture(capture);
    }
  }
}

/// Optional real GTK screenshots for an affected native integration run.
Future<void> captureNativeFixtureUi(WidgetTester tester, String name) async {
  final directory = Platform.environment['TANDEMLOG_NATIVE_QA_SCREENSHOTS'];
  if (directory == null || !Platform.isLinux) return;
  await Directory(directory).create(recursive: true);
  final found = await Process.run('xdotool', [
    'search',
    '--onlyvisible',
    '--name',
    r'^tandemlog$',
  ]);
  expect(found.exitCode, 0);
  final window = (found.stdout as String).trim().split('\n').last;
  await Process.run('xdotool', ['windowmove', window, '0', '0']);
  await Process.run('xdotool', [
    'windowsize',
    window,
    tester.view.physicalSize.width.round().toString(),
    tester.view.physicalSize.height.round().toString(),
  ]);
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  final captured = await Process.run('import', [
    '-window',
    window,
    '$directory/$name.png',
  ]);
  expect(captured.exitCode, 0);
}
