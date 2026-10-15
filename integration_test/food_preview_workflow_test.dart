import 'package:tandemlog/presentation/list_row_surface.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import '../test/food_expiry_guidance_test.dart' show selectFoodView;
import '../tool/food_preview.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('synthetic native flat food remove/restore and Inbox workflow', (
    tester,
  ) async {
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
    final initial = tester
        .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
        .state;
    final riceBefore = initial.active
        .where((e) => e.details.name == 'Rice')
        .toList();
    final removedId = initial.groups
        .singleWhere((g) => g.details.name == 'Rice')
        .containers
        .first
        .id;
    expect(find.text('8 containers'), findsOneWidget);
    expect(find.text('Remaining contents'), findsNothing);
    await tap(tester, find.byTooltip('Remove one Rice container'));
    await tester.pumpAndSettle();
    final after = tester
        .widget<FoodInventoryPage>(find.byType(FoodInventoryPage))
        .state;
    expect(after.active.where((e) => e.details.name == 'Rice'), hasLength(7));
    expect(after.deleted.single.id, removedId);
    expect(
      after.containers.map((e) => e.contents.toJson()).toList(),
      initial.containers.map((e) => e.contents.toJson()).toList(),
    );
    expect(riceBefore, hasLength(8));
    await capture(tester, 'narrow-removed-one');
    await selectFoodView(
      tester,
      FoodView.deleted,
      input: (target) => tap(tester, target),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsOneWidget);
    await capture(tester, 'narrow-deleted');
    await tap(tester, find.byTooltip('Restore one Rice container'));
    await tester.pumpAndSettle();
    expect(find.text('No deleted containers'), findsOneWidget);
    await selectFoodView(
      tester,
      FoodView.retained,
      input: (target) => tap(tester, target),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Chocolate').hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(ListRowSurface, 'Birthday baking'),
      findsOneWidget,
    );
    await capture(tester, 'narrow-retained-flat');
    await selectFoodView(
      tester,
      FoodView.inventory,
      input: (target) => tap(tester, target),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lentils'), findsOneWidget);
    await capture(tester, 'narrow-inbox');
    await tap(tester, find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await capture(tester, 'narrow-editor');
    await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await selectFoodView(
      tester,
      FoodView.inventory,
      input: (target) => tap(tester, target),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 850);
    await tester.pumpAndSettle();
    await capture(tester, 'wide-stock-after-restore');
    await capture(tester, 'wide-stock');
    expect(tester.takeException(), isNull);
  });
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
Future<void> tap(WidgetTester tester, Finder target, {int buttons = 1}) async {
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
  await tester.tap(target, buttons: buttons);
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
