import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/sticky_task_group.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerStickyTaskGroupTests();
}

void registerStickyTaskGroupTests() {
  testWidgets('sticky date groups retain drafts, selection and safe edge drops', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('sticky-groups-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await openNativeFixtureStore(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4();
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    final ids = <String>[];
    for (var i = 0; i < 62; i++) {
      final id = const Uuid().v4();
      ids.add(id);
      await writer.createNativeFixtureTask(id, {
        'title': 'Reference task ${i + 1}',
        'description': '',
        'assignee': user,
        'schedule': i < 30
            ? {'dueDate': '2026-10-01'}
            : i < 32
            ? {'dueDate': '2026-10-02'}
            : {},
      });
      // These undated fixtures are organized Someday tasks. Raw captures now
      // precede dated groups in Inbox, which is covered by inbox_flow_test.
      if (i >= 32) {
        await writer.editNativeFixtureTask(id, {
          'title': 'Reference task ${i + 1}',
        });
      }
    }
    await writer.command(ids.last, 'task.completed', {});
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    Future<Map<String, String>> logs() async => {
      await for (final entry in folder.list())
        if (entry is File) entry.path: base64Encode(await entry.readAsBytes()),
    };
    final before = await logs();
    try {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (changed) => ViewTimeSource(
            onChanged: changed,
            now: () => DateTime.utc(2026, 10, 2, 12),
            loadZone: () async => 'UTC',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = find.byType(CustomScrollView).first;
      final scrollable = find
          .descendant(of: viewport, matching: find.byType(Scrollable))
          .first;
      ScrollPosition position() =>
          tester.state<ScrollableState>(scrollable).position;
      Finder heading(String label) {
        final widget = tester.widget<StickyTaskGroupHeading>(
          find.byWidgetPredicate(
            (w) => w is StickyTaskGroupHeading && w.title == label,
          ),
        );
        return find.byKey(widget.headingKey!);
      }

      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.enterText(capture, 'Preserved capture draft');
      final body = find.byKey(ValueKey('task-body-${ids[1]}'));
      await tester.tap(body);
      await tester.pumpAndSettle();
      final notes = find.widgetWithText(TextField, 'Notes');
      await tester.enterText(notes, 'Preserved side editor draft');
      position().jumpTo(500);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(heading('Thursday · 2026-10-01')).top,
        closeTo(tester.getRect(viewport).top, .1),
      );
      expect(
        tester.widget<TextField>(notes).controller!.text,
        'Preserved side editor draft',
      );
      // Save neither buffer; deliberate cancellation returns to the list.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      if (find.text('Discard').evaluate().isNotEmpty) {
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
      }
      position().jumpTo(0);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(ValueKey('task-body-${ids[1]}')));
      await tester.pumpAndSettle();
      final bar = find.byKey(const ValueKey('compact-selection-actions'));
      expect(bar, findsOneWidget);
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        position().jumpTo(500);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(heading('Thursday · 2026-10-01')).top,
          closeTo(tester.getRect(viewport).top, .1),
        );
        expect(
          tester.getRect(viewport).top,
          greaterThanOrEqualTo(tester.getRect(bar).bottom),
        );
        expect(find.text('1 selected'), findsOneWidget);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      position().jumpTo(0);
      await tester.pumpAndSettle();
      // An unselected peer cannot be dragged while selection is active.
      await tester.tap(find.byKey(const ValueKey('clear-selected-tasks')));
      await tester.pumpAndSettle();
      final handle = find.descendant(
        of: find.byKey(ValueKey('task-row-${ids[5]}')),
        matching: find.byType(Draggable<String>),
      );
      await tester.scrollUntilVisible(handle, 100, scrollable: scrollable);
      await tester.pumpAndSettle();
      position().jumpTo(900);
      await tester.pumpAndSettle();
      final visibleHandle = find.descendant(
        of: find.byKey(ValueKey('task-row-${ids[18]}')),
        matching: find.byType(Draggable<String>),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(visibleHandle),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      final start = position().pixels;
      final headingRect = tester.getRect(heading('Thursday · 2026-10-01'));
      await gesture.moveTo(headingRect.center);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        position().pixels,
        lessThan(start),
        reason: 'Pinned heading retains top edge scrolling.',
      );
      expect(
        tester
            .getRect(heading('Thursday · 2026-10-01'))
            .contains(headingRect.center),
        isTrue,
        reason:
            'Release still occurs over the pinned heading after edge scrolling.',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        await logs(),
        before,
        reason: 'Dropping on a heading never targets an obscured row.',
      );
      await tester.scrollUntilVisible(
        find.text('Friday · 2026-10-02'),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final nextRect = tester.getRect(heading('Friday · 2026-10-02'));
      final viewportTop = tester.getRect(viewport).top;
      position().jumpTo(
        position().pixels + nextRect.top - viewportTop - nextRect.height / 2,
      );
      await tester.pumpAndSettle();
      final previousRect = tester.getRect(heading('Thursday · 2026-10-01'));
      final pushedRect = tester.getRect(heading('Friday · 2026-10-02'));
      expect(previousRect.top, lessThan(viewportTop));
      expect(previousRect.bottom, closeTo(pushedRect.top, .1));
      await tester.scrollUntilVisible(
        find.text('Someday'),
        100,
        scrollable: scrollable,
      );
      position().jumpTo(position().maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(heading('Someday')).top,
        closeTo(tester.getRect(viewport).top, .1),
      );
      position().jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Preserved capture draft',
      );
      await tester.tap(find.byTooltip('Search all tasks (Ctrl+F)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'Reference task 6',
      );
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Someday'), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'no matching reference',
      );
      await tester.pumpAndSettle();
      expect(find.byType(StickyTaskGroupHeading), findsNothing);
      expect(find.text('No tasks match your search'), findsOneWidget);
      expect(await logs(), before);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await writer.close();
      await root.delete(recursive: true);
    }
  });
}
