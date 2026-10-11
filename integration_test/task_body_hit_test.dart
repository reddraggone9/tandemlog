import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskBodyHitTests();
}

void registerTaskBodyHitTests() {
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
  final row = tester.getRect(find.byKey(ValueKey('task-row-$id')));
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
  Future<void> Function(Directory data, List<String> ids) inspect,
) async {
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
    await seed.close();
    await File('${profile.path}/settings.json').writeAsString(
      jsonEncode({'folder': data.path, 'user': user, 'appearance': 'dark'}),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 850);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
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
