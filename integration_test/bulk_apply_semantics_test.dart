import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerBulkApplySemanticsTests();
}

// Optional capture of the actual GTK workflow. Input remains the test's
// semantics/touch/key actions; the real X11 pointer identifies the control.
Future<Process?> startBulkRecording({
  String caption = 'Linux GTK debug - scripted semantics/touch/Space workflow',
}) async {
  final output = Platform.environment['TANDEMLOG_BULK_QA_VIDEO'];
  if (output == null || !Platform.isLinux) return null;
  await File(output).parent.create(recursive: true);
  final cursor = await Process.run('xsetroot', ['-cursor_name', 'left_ptr']);
  expect(cursor.exitCode, 0);
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
    'drawtext=text=$caption:x=10:y=825:fontsize=14:fontcolor=white',
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

Future<void> pointAndPause(
  WidgetTester tester,
  Finder control,
  Process? recording,
) async {
  if (recording == null) return;
  final point = tester.getCenter(control);
  final pointed = await Process.run('xdotool', [
    'mousemove',
    point.dx.round().toString(),
    point.dy.round().toString(),
  ]);
  expect(pointed.exitCode, 0);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 900)),
  );
}

Future<void> stopBulkRecording(Process? recording) async {
  if (recording == null) return;
  recording.stdin.writeln('q');
  await recording.stdin.flush();
  expect(await recording.exitCode, 0);
}

void registerBulkApplySemanticsTests() {
  for (final variant in const [
    (name: 'desktop-dark', width: 1200.0, scale: 1.0, dark: true),
    (name: 'narrow-light-200', width: 390.0, scale: 2.0, dark: false),
  ]) {
    testWidgets(
      'native bulk named apply persists only Due time ${variant.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final root = await Directory.systemTemp.createTemp('bulk-apply-named-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final peer = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/peer',
        );
        final user = const Uuid().v4();
        final ids = [const Uuid().v4(), const Uuid().v4()];
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        for (var index = 0; index < ids.length; index++) {
          await peer.createNativeFixtureTask(ids[index], {
            'title': 'Bulk fixture ${index + 1}',
            'description': '',
            'assignee': user,
            'schedule': {
              for (final key in TaskSchedule.keys) key: null,
              'dueDate': index == 0 ? '2026-10-02' : '2026-10-03',
              'dueTime': index == 0 ? '12:30' : '13:45',
              'recurrence': 'every week when done',
              'timeZone': 'UTC',
            },
          });
        }
        await File(
          '${profile.path}/settings.json',
        ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
        final originalSchedules = {
          for (final row in peer.rows.where((row) => ids.contains(row['id'])))
            row['id']: Map<String, dynamic>.from(row['schedule'] as Map),
        };
        Process? recording;
        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(variant.width, 850);
          tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
          tester.platformDispatcher.platformBrightnessTestValue = variant.dark
              ? Brightness.dark
              : Brightness.light;
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              timeSourceFactory: (changed) => ViewTimeSource(
                onChanged: changed,
                now: () => DateTime.utc(2026, 10, 4, 12),
                loadZone: () async => 'UTC',
              ),
            ),
          );
          await flows.waitForUi(
            tester,
            () => find.text('Bulk fixture 1').evaluate().isNotEmpty,
          );
          await flows.selectTask(tester, ids[0]);
          await flows.selectTask(tester, ids[1], control: false);
          if (find.byType(BulkTaskEditor).evaluate().isEmpty) {
            await tester.tap(find.byKey(const ValueKey('edit-selected-tasks')));
            await tester.pumpAndSettle();
          }
          expect(find.byType(BulkTaskEditor), findsOneWidget);
          await tester.ensureVisible(find.byKey(const ValueKey('startDate')));
          await tester.pumpAndSettle();
          await captureNativeFixtureUi(
            tester,
            'bulk-${variant.name}-date-controls',
          );
          if (variant.name == 'desktop-dark') {
            recording = await startBulkRecording();
          }
          final dueTime = find.byWidgetPredicate(
            (widget) =>
                widget is Checkbox && widget.semanticLabel == 'Apply Due time',
          );
          expect(dueTime, findsOneWidget);
          await tester.ensureVisible(dueTime);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(dueTime).getSemanticsData().label,
            'Apply Due time',
          );
          await pointAndPause(tester, dueTime, recording);
          final node = tester.getSemantics(dueTime);
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isTrue);
          await pointAndPause(tester, dueTime, recording);
          expect(
            tester
                .widgetList<Checkbox>(
                  find.descendant(
                    of: find.byType(BulkTaskEditor),
                    matching: find.byType(Checkbox),
                  ),
                )
                .where((checkbox) => checkbox.value == true)
                .map((checkbox) => checkbox.semanticLabel),
            ['Apply Due time'],
          );
          final paint = find
              .descendant(of: dueTime, matching: find.byType(CustomPaint))
              .first;
          Focus.of(tester.element(paint)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isFalse);
          await pointAndPause(tester, dueTime, recording);
          await tester.tap(dueTime);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isTrue);
          await tester.ensureVisible(find.byKey(const ValueKey('addTags')));
          await tester.pumpAndSettle();
          await pointAndPause(
            tester,
            find.byKey(const ValueKey('addTags')),
            recording,
          );
          await tester.enterText(
            find.byKey(const ValueKey('addTags')),
            'reviewed',
          );
          final assignee = find.byWidgetPredicate(
            (widget) =>
                widget is Checkbox && widget.semanticLabel == 'Apply Assignee',
          );
          await tester.ensureVisible(assignee);
          await tester.pumpAndSettle();
          await pointAndPause(tester, assignee, recording);
          expect(
            tester.getSemantics(assignee).getSemanticsData().label,
            'Apply Assignee',
          );
          expect(tester.widget<Checkbox>(assignee).value, isFalse);
          await captureNativeFixtureUi(
            tester,
            'bulk-${variant.name}-tags-assignee',
          );
          await tester.ensureVisible(find.text('Save changes'));
          await pointAndPause(tester, find.text('Save changes'), recording);
          await tester.tap(find.text('Save changes'));
          await flows.waitForUi(
            tester,
            () => find.byType(BulkTaskEditor).evaluate().isEmpty,
          );
          await peer.refresh();
          for (var index = 0; index < ids.length; index++) {
            final row = peer.rows.singleWhere((row) => row['id'] == ids[index]);
            expect(row['schedule'], {
              ...originalSchedules[ids[index]]!,
              'dueTime': null,
            });
            expect(row['assignee'], user);
            expect(row['title'], 'Bulk fixture ${index + 1}');
            expect(row['tags'], ['reviewed']);
          }
          await pointAndPause(
            tester,
            find.byKey(const ValueKey('task-filter')),
            recording,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await stopBulkRecording(recording);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
          await peer.close();
          // Retain every synthetic fixture for diagnosis; never touch user data.
          semantics.dispose();
        }
      },
    );
  }
}
