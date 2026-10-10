import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import '../tool/food_preview.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'synthetic native food inspect/remove/restore and Inbox workflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const FoodPreviewApp());
      await tester.pumpAndSettle();
      await capture(tester, 'initial-warmup-not-evidence');
      tester.view.physicalSize = const Size(390, 850);
      await tester.pumpAndSettle();
      await capture(tester, 'narrow-stock');
      await startRecording(tester);
      expect(find.byTooltip('Remove one Rice container'), findsNothing);
      await tap(tester, find.byTooltip('Inspect Rice containers'));
      await tester.pumpAndSettle();
      await capture(tester, 'narrow-inspect');
      final partial = find.byWidgetPredicate(
        (w) =>
            w is Checkbox && w.semanticLabel?.endsWith('⅓ remaining') == true,
      );
      await tester.ensureVisible(partial);
      await tap(tester, partial);
      await tester.pumpAndSettle();
      final remove = find.widgetWithText(TextButton, 'Remove selected (1)');
      await tester.ensureVisible(remove);
      await capture(tester, 'narrow-selected-partial');
      await tap(tester, remove);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
            .state
            .active
            .where((e) => e.details.name == 'Rice'),
        hasLength(7),
      );
      await tap(tester, find.text('Deleted'));
      await tester.pumpAndSettle();
      expect(find.text('⅓ remaining'), findsOneWidget);
      await capture(tester, 'narrow-deleted');
      await tap(tester, find.byTooltip('Restore Rice containers'));
      await tester.pumpAndSettle();
      expect(find.text('No deleted containers'), findsOneWidget);
      await tap(tester, find.text('Retained'));
      await tester.pumpAndSettle();
      expect(find.text('Chocolate').hitTestable(), findsNothing);
      await capture(tester, 'narrow-retained-collapsed');
      await tap(tester, find.widgetWithText(ExpansionTile, 'Birthday baking'));
      await tester.pumpAndSettle();
      await capture(tester, 'narrow-retained-expanded');
      await tap(tester, find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Lentils'), findsOneWidget);
      await capture(tester, 'narrow-inbox');
      await tap(tester, find.byTooltip('Add food'));
      await tester.pumpAndSettle();
      await capture(tester, 'narrow-editor');
      await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Stock'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 850);
      await tester.pumpAndSettle();
      await capture(tester, 'wide-stock-after-restore');
      await tap(tester, find.byTooltip('Collapse Rice containers'));
      await tester.pumpAndSettle();
      await capture(tester, 'wide-stock');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['FOOD_PREVIEW_EVIDENCE'];
  if (directory == null || !Platform.isLinux) return;
  await Directory(directory).create(recursive: true);
  final found = await Process.run('xdotool', [
    'search',
    '--onlyvisible',
    '--name',
    r'^tandemlog$',
  ]);
  expect(found.exitCode, 0);
  final window = found.stdout.toString().trim().split('\n').last;
  final size = tester.view.physicalSize;
  expect(
    (await Process.run('xdotool', [
      'windowsize',
      window,
      '${size.width.round()}',
      '${size.height.round()}',
    ])).exitCode,
    0,
  );
  expect(
    (await Process.run('xdotool', ['windowmove', window, '0', '0'])).exitCode,
    0,
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  expect(
    (await Process.run('import', [
      '-window',
      window,
      '$directory/$name.png',
    ])).exitCode,
    0,
  );
}

// This fixture scripts Flutter taps; the actual X pointer marks each input in
// the native desktop recording. It is not a physical-device touch attestation.
Future<void> tap(WidgetTester tester, Finder target) async {
  if (Platform.isLinux && Platform.environment['FOOD_PREVIEW_RECORD'] == '1') {
    final point = tester.getCenter(target);
    expect(
      (await Process.run('xdotool', [
        'mousemove',
        '${point.dx.round()}',
        '${point.dy.round()}',
      ])).exitCode,
      0,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }
  await tester.tap(target);
}

Future<void> startRecording(WidgetTester tester) async {
  final directory = Platform.environment['FOOD_PREVIEW_EVIDENCE'];
  if (!Platform.isLinux ||
      directory == null ||
      Platform.environment['FOOD_PREVIEW_RECORD'] != '1') {
    return;
  }
  final recording = await Process.start('ffmpeg', [
    '-y',
    '-loglevel',
    'error',
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
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '23',
    '-pix_fmt',
    'yuv420p',
    '$directory/native-linux-scripted-preview.mp4',
  ]);
  final errors = recording.stderr.drain<void>();
  final output = recording.stdout.drain<void>();
  addTearDown(() async {
    recording.stdin.writeln('q');
    await recording.stdin.flush();
    expect(await recording.exitCode, 0);
    await errors;
    await output;
  });
}
