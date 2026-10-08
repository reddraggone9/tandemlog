import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;
import 'bulk_apply_semantics_test.dart' show pointAndPause, stopBulkRecording;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTagInputWorkflowTests();
}

Future<Process?> _recordTags() async {
  final output = Platform.environment['TANDEMLOG_TAG_QA_VIDEO'];
  if (output == null || !Platform.isLinux) return null;
  await File(output).parent.create(recursive: true);
  expect(
    (await Process.run('xsetroot', ['-cursor_name', 'left_ptr'])).exitCode,
    0,
  );
  final process = await Process.start('ffmpeg', [
    '-y',
    '-f',
    'x11grab',
    '-draw_mouse',
    '1',
    '-framerate',
    '15',
    '-video_size',
    '1200x850',
    '-i',
    Platform.environment['DISPLAY']!,
    '-vf',
    'drawtext=text=Linux GTK debug - scripted tag editing and filtering:x=10:y=825:fontsize=14:fontcolor=white',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-crf',
    '26',
    '-pix_fmt',
    'yuv420p',
    output,
  ]);
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
  return process;
}

void registerTagInputWorkflowTests() {
  for (final variant in const [
    (name: 'desktop-dark', width: 1200.0, scale: 1.0, theme: 'dark'),
    (name: 'narrow-dark', width: 390.0, scale: 1.0, theme: 'dark'),
    (name: 'narrow-light-200', width: 390.0, scale: 2.0, theme: 'light'),
  ]) {
    testWidgets('shared tag editing and filtering ${variant.name}', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('shared-tag-flow-');
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final peer = await openNativeFixtureStore(
        LocalLogFolder(shared.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4();
      final first = const Uuid().v4(), second = const Uuid().v4();
      final completed = const Uuid().v4();
      Future<Map<String, String>> canonical() async => {
        await for (final file in shared.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      Future<void> tap(Finder control, Process? recording) async {
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        await pointAndPause(tester, control, recording);
        await tester.tap(control);
        await tester.pumpAndSettle();
      }

      Future<void> type(String key, String text, Process? recording) async {
        final field = find.byKey(ValueKey(key));
        await tap(field, recording);
        await tester.enterText(field, text);
        await tester.pumpAndSettle();
      }

      Map<String, dynamic> row(String id) =>
          peer.rows.singleWhere((row) => row['id'] == id);
      Process? recording;
      try {
        await peer.command(user, 'user.created', {'name': 'Lee'});
        for (final entry in [
          (first, 'Plan weekend'),
          (second, 'Review supplies'),
          (completed, 'Finished reference'),
        ]) {
          await peer.createNativeFixtureTask(entry.$1, {
            'title': entry.$2,
            'description': '',
            'assignee': user,
          });
        }
        await peer.edit(first, {}, tags: ['Home Office'], observedTagRefs: {});
        await peer.edit(second, {}, tags: ['Planning'], observedTagRefs: {});
        await peer.edit(
          completed,
          {},
          tags: ['ArchivedOnly'],
          observedTagRefs: {},
        );
        await peer.command(completed, 'task.completed', {});
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': variant.theme,
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, 850);
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.byKey(ValueKey('task-row-$first')).evaluate().isNotEmpty,
        );
        await flows.selectTask(tester, first, control: false);
        await tester.ensureVisible(find.byKey(const ValueKey('tags')));
        await captureNativeFixtureUi(tester, 'editor-selected-${variant.name}');
        if (variant.name == 'desktop-dark') recording = await _recordTags();
        final beforeCancel = await canonical();
        await type('tags', 'Archived', recording);
        final archivedOption = find.byKey(
          const ValueKey('tag-option-ArchivedOnly'),
        );
        expect(
          archivedOption,
          findsOneWidget,
          reason: 'completed task inventory is available in the editor',
        );
        await captureNativeFixtureUi(tester, 'editor-options-${variant.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tap(find.text('Cancel').last, recording);
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tap(find.widgetWithText(TextButton, 'Cancel').last, recording);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tags')))
              .controller!
              .text,
          'Archived',
        );
        await tap(find.text('Cancel').last, recording);
        await tap(find.text('Discard').last, recording);
        expect(await canonical(), beforeCancel);

        await flows.selectTask(tester, first, control: false);
        await type('tags', 'plan', recording);
        await tap(find.byKey(const ValueKey('tag-option-Planning')), recording);
        expect(
          find.byKey(const ValueKey('selected-tag-Home Office')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('selected-tag-Planning')),
          findsOneWidget,
        );
        await type('tags', '#Fresh', recording);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await captureNativeFixtureUi(tester, 'editor-draft-${variant.name}');
        await tap(find.text('Save changes').last, recording);
        await flows.waitForUi(
          tester,
          () => find.byType(TaskEditor).evaluate().isEmpty,
        );
        await peer.refresh();
        expect(Set<String>.from(row(first)['tags']), {
          'Home Office',
          'Planning',
          'Fresh',
        });

        await flows.selectTask(tester, first, control: false, longPress: true);
        await flows.selectTask(tester, second, control: false);
        expect(find.byType(BulkTaskEditor), findsOneWidget);
        await type('addTags', 'Shared', recording);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await type('removeTags', 'Home', recording);
        await tap(
          find.byKey(const ValueKey('tag-option-Home Office')),
          recording,
        );
        await captureNativeFixtureUi(tester, 'bulk-draft-${variant.name}');
        await tap(find.text('Apply changes').last, recording);
        await flows.waitForUi(
          tester,
          () => find.byType(BulkTaskEditor).evaluate().isEmpty,
        );
        await peer.refresh();
        expect(Set<String>.from(row(first)['tags']), {
          'Planning',
          'Fresh',
          'Shared',
        });
        expect(Set<String>.from(row(second)['tags']), {'Planning', 'Shared'});

        final beforeFilter = await canonical();
        await flows.openFilters(tester);
        await flows.chooseFilter(tester, '#Fresh');
        await tap(find.byKey(const ValueKey('tag-search')), recording);
        await captureNativeFixtureUi(tester, 'filter-selected-${variant.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tap(find.text('Done').last, recording);
        expect(find.byKey(ValueKey('task-row-$first')), findsOneWidget);
        expect(find.byKey(ValueKey('task-row-$second')), findsNothing);
        await flows.openFilters(tester);
        await flows.chooseFilter(tester, '#Shared');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tap(find.text('Done').last, recording);
        expect(find.byKey(ValueKey('task-row-$first')), findsOneWidget);
        expect(
          find.byKey(ValueKey('task-row-$second')),
          findsOneWidget,
          reason: 'selected filters match any exact tag',
        );
        expect(
          await canonical(),
          beforeFilter,
          reason: 'filter selection must not append canonical records',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await stopBulkRecording(recording);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await peer.close();
        await root.delete(recursive: true);
      }
    });
  }
}
