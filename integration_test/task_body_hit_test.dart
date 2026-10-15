import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskBodyHitTests();
}

void registerTaskBodyHitTests() {
  for (final sample in [
    (320.0, 1.0, false),
    (1200.0, 1.0, false),
    (320.0, 2.0, true),
    (1200.0, 1.0, true),
  ]) {
    testWidgets(
      'Task body ink spans main row ${sample.$1} x${sample.$2} expanded:${sample.$3}',
      (tester) async {
        await _withInbox(tester, sample.$1, sample.$2, (data, ids) async {
          final before = await _records(data);
          final id = ids.first;
          if (sample.$3) {
            await tester.tap(find.byKey(ValueKey('checklist-disclosure-$id')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(ValueKey('inline-checklist-$id')),
              findsOneWidget,
            );
          }
          final row = tester.getRect(
            find
                .ancestor(
                  of: find.byKey(ValueKey('task-body-$id')),
                  matching: find.byType(ListTile),
                )
                .first,
          );
          final body = tester.getRect(find.byKey(ValueKey('task-body-$id')));
          final points = [
            Offset(row.left + 3, row.top + 3),
            Offset(row.right - 3, row.top + 3),
            sample.$3
                ? tester.getTopLeft(
                        find.byKey(ValueKey('inline-checklist-$id')),
                      ) +
                      const Offset(3, 6)
                : Offset(row.left + 3, row.bottom + 3),
            body.center,
          ];
          expect(points.first.dx, lessThan(body.left));
          expect(points[1].dx, greaterThan(body.right));
          final ink = tester.widget<InkWell>(
            find.byKey(ValueKey('task-body-$id')),
          );
          final box = tester.renderObject<RenderBox>(
            find.byKey(ValueKey('task-body-$id')),
          );
          debugPrint(
            'BODY_INK_BOUNDS=${ink.runtimeType} ${ink.getRectCallback(box)?.call()}',
          );
          final baseline = await _pixels(tester, points);
          final press = await tester.startGesture(body.center);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump(const Duration(milliseconds: 80));
          final pressed = await _pixels(tester, points);
          debugPrint('BODY_INK_PIXELS baseline=$baseline pressed=$pressed');
          expect(
            pressed[3],
            isNot(baseline[3]),
            reason: 'The sampled native frame contains active body feedback.',
          );
          await _captureBodyInkFrame(
            tester,
            'task-body-ink-${sample.$1.toInt()}-${sample.$2}x-expanded-${sample.$3}',
          );
          expect(
            pressed[0],
            isNot(baseline[0]),
            reason: 'Body feedback reaches the main row leading edge.',
          );
          expect(
            pressed[1],
            isNot(baseline[1]),
            reason: 'Body feedback reaches the main row trailing edge.',
          );
          expect(
            pressed[2],
            baseline[2],
            reason:
                'Body ink stays outside the divider/checklist below the main row.',
          );
          await press.up();
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(await _records(data), before);
        }, checklist: sample.$3);
      },
    );
  }
  testWidgets(
    'stationary Task drag handle click and long press do not open or select',
    (tester) async {
      await _withInbox(tester, 390, 1, (data, ids) async {
        final before = await _records(data);
        final handle = find.descendant(
          of: find.byKey(ValueKey('task-row-${ids.first}')),
          matching: find.byType(Draggable<String>),
        );
        await tester.tap(handle);
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.text('1 selected'), findsNothing);
        final hold = await tester.startGesture(tester.getCenter(handle));
        await tester.pump(
          kLongPressTimeout + const Duration(milliseconds: 100),
        );
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.text('1 selected'), findsNothing);
        expect(await _records(data), before);
      });
    },
  );
  for (final sample in [
    (320.0, 1.0),
    (390.0, 1.0),
    (1200.0, 1.0),
    (320.0, 2.0),
  ]) {
    testWidgets(
      'short Inbox task opens from blank row middle ${sample.$1} x${sample.$2}',
      (tester) async {
        await _withInbox(tester, sample.$1, sample.$2, (data, ids) async {
          final before = await _records(data);
          // Establish that opening the same task on its glyph works. Tapping a
          // task-body finder alone can miss an undersized hit target.
          await tester.tap(find.byKey(ValueKey('task-title-${ids.first}')));
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          final point = _blankMiddle(tester, ids.first);
          await captureNativeFixtureUi(
            tester,
            'task-inbox-middle-${sample.$1.toInt()}-${sample.$2}x',
          );
          await tester.tapAt(point);
          await tester.pumpAndSettle();
          expect(
            find.byType(TaskEditor),
            findsOneWidget,
            reason:
                'The blank title-column middle must open the same Inbox task.',
          );
          expect(
            tester
                .widget<TextField>(find.widgetWithText(TextField, 'Title'))
                .controller!
                .text,
            'Tap',
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(await _records(data), before);
          expect(find.text('Inbox'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }

  testWidgets('Inbox blank middle selects while row actions remain separate', (
    tester,
  ) async {
    await _withInbox(tester, 390, 1, (data, ids) async {
      final before = await _records(data);
      // Row controls must keep their own gesture ownership when the body fills
      // the available title column. Menu opening does not open the editor.
      await tester.tap(find.byKey(ValueKey('task-menu-${ids.first}')));
      await tester.pumpAndSettle();
      expect(find.text('Add checklist'), findsOneWidget);
      expect(find.byType(TaskEditor), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await _records(data), before);

      final gesture = await tester.startGesture(
        _blankMiddle(tester, ids.first),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(TaskEditor), findsNothing);
      await tester.tapAt(_blankMiddle(tester, ids.last));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-selected-tasks')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsNothing);
      expect(await _records(data), before);

      await tester.tap(find.byTooltip('Complete Tap'));
      await waitForUi(
        tester,
        () => find.byKey(ValueKey('task-row-${ids.first}')).evaluate().isEmpty,
      );
      expect(find.byType(TaskEditor), findsNothing);
      await tester.tap(find.byKey(const ValueKey('undo-task-action')));
      await waitForUi(
        tester,
        () =>
            find.byKey(ValueKey('task-row-${ids.first}')).evaluate().isNotEmpty,
      );

      // A real handle drag still reorders, rather than invoking the body tap.
      final handle = find.descendant(
        of: find.byKey(ValueKey('task-row-${ids.first}')),
        matching: find.byType(Draggable<String>),
      );
      bool firstAboveLast() =>
          tester
              .getTopLeft(find.byKey(ValueKey('task-title-${ids.first}')))
              .dy <
          tester.getTopLeft(find.byKey(ValueKey('task-title-${ids.last}'))).dy;
      final initiallyAbove = firstAboveLast();
      final drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(-24, 0));
      await tester.pump();
      final target = tester.getRect(
        find.byKey(ValueKey('task-drop-${ids.last}')),
      );
      await drag.moveTo(
        Offset(
          target.center.dx,
          initiallyAbove ? target.bottom - 4 : target.top + 4,
        ),
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditor), findsNothing);
      expect(firstAboveLast(), isNot(initiallyAbove));
      expect(tester.takeException(), isNull);
    });
  });
}

Offset _blankMiddle(WidgetTester tester, String id) {
  final row = tester.getRect(
    find
        .ancestor(
          of: find.byKey(ValueKey('task-body-$id')),
          matching: find.byType(ListTile),
        )
        .first,
  );
  final title = tester.getRect(find.byKey(ValueKey('task-title-$id')));
  final menu = tester.getRect(find.byKey(ValueKey('task-menu-$id')));
  final body = tester.getRect(find.byKey(ValueKey('task-body-$id')));
  final point = Offset(row.center.dx, body.center.dy);
  expect(point.dx, greaterThan(title.right + 8));
  expect(point.dx, lessThan(menu.left));
  debugPrint(
    'TASK_INBOX_HIT_GEOMETRY=${jsonEncode({
      'row': [row.left, row.top, row.width, row.height],
      'body': [body.left, body.top, body.width, body.height],
      'title': [title.left, title.top, title.width, title.height],
      'tap': [point.dx, point.dy],
    })}',
  );
  return point;
}

Future<Map<String, List<int>>> _records(Directory data) async => {
  await for (final entry in data.list())
    if (entry is File && entry.path.endsWith('.jsonl'))
      entry.path: await entry.readAsBytes(),
};

Future<void> _withInbox(
  WidgetTester tester,
  double width,
  double scale,
  Future<void> Function(Directory data, List<String> ids) inspect, {
  bool checklist = false,
}) async {
  final root = await Directory.systemTemp.createTemp(
    'task-body-hit-synthetic-',
  );
  final data = await Directory('${root.path}/data').create();
  final profile = await Directory('${root.path}/profile').create();
  final user = const Uuid().v4();
  final ids = List.generate(2, (_) => const Uuid().v4());
  final seed = await openNativeFixtureStore(
    LocalLogFolder(data.path),
    '${root.path}/seed',
  );
  try {
    await seed.command(user, 'user.created', {'name': 'Synthetic household'});
    for (var i = 0; i < ids.length; i++) {
      await seed.createNativeFixtureTask(ids[i], {
        'title': i == 0 ? 'Tap' : 'Tea',
        'description': '',
        'assignee': user,
      });
    }
    if (checklist) {
      await seed.addChecklistItem(ids.first, 'Synthetic inline note');
    }
    await seed.close();
    await File('${profile.path}/settings.json').writeAsString(
      jsonEncode({'folder': data.path, 'user': user, 'appearance': 'dark'}),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 850);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('body-ink-scene'),
        child: TandemlogApp(profilePath: profile.path),
      ),
    );
    await waitForUi(
      tester,
      () => find.byKey(ValueKey('task-row-${ids.first}')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    await inspect(data, ids);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await seed.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await root.delete(recursive: true);
  }
}

Future<List<int>> _pixels(WidgetTester tester, List<Offset> points) async {
  final scene = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('body-ink-scene')),
  );
  return (await tester.runAsync(() async {
    final image = await scene.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points)
          data.getUint32(
            (point.dy.floor() * image.width + point.dx.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _captureBodyInkFrame(WidgetTester tester, String name) async {
  final directory = Platform.environment['TANDEMLOG_NATIVE_QA_SCREENSHOTS'];
  if (directory == null) return;
  final scene = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('body-ink-scene')),
  );
  await tester.runAsync(() async {
    final image = await scene.toImage(pixelRatio: 1);
    try {
      await Directory(directory).create(recursive: true);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
