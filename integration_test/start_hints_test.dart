import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerStartHintTests();
}

void registerStartHintTests() {
  testWidgets('future start hints update idle, search and resumed local time', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('start-hints-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await openNativeFixtureStore(
      LocalLogFolder(folder.path),
      '${root.path}/writer',
    );
    final user = const Uuid().v4(), ids = <String, String>{};
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    Future<void> add(
      String title,
      Map<String, dynamic> schedule, {
      bool done = false,
    }) async {
      final id = ids[title] = const Uuid().v4();
      await writer.createNativeFixtureTask(id, {
        'title': title,
        'description': '',
        'assignee': user,
        'schedule': schedule,
      });
      if (done) await writer.command(id, 'task.completed', {});
    }

    await add('Later today', {'startDate': '2026-10-02', 'startTime': '17:00'});
    await add('Later date', {'startDate': '2026-10-05', 'startTime': '17:00'});
    await add('Date only', {'startDate': '2026-10-05'});
    await add('Pinned task', {
      'startDate': '2026-10-05',
      'startTime': '17:00',
      'timeZone': 'UTC',
    });
    await add('Past start', {
      'startDate': '2026-10-01',
      'startTime': '17:00',
      'dueDate': '2026-10-01',
      'dueMinDays': 0,
    });
    await add('Retained history', {
      'startDate': '2026-10-05',
      'startTime': '17:00',
    }, done: true);
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    Future<Map<String, String>> logs() async => {
      await for (final file in folder.list())
        if (file is File) file.path: base64Encode(await file.readAsBytes()),
    };
    final before = await logs();
    var base = DateTime.utc(2026, 10, 2, 12), zone = 'UTC';
    final elapsed = Stopwatch();
    late ViewTimeSource source;
    Finder metadata(String title) =>
        find.byKey(ValueKey('task-metadata-${ids[title]}'));
    String details(String title) => metadata(title).evaluate().isEmpty
        ? ''
        : tester
              .widget<Text>(metadata(title))
              .data!
              .split(' · ')
              .where((part) => part.startsWith('Starts '))
              .join(' · ');
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (changed) => source = ViewTimeSource(
            onChanged: changed,
            loadZone: () async => zone,
            now: () => base.add(elapsed.elapsed),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Later today'), findsNothing);
      expect(details('Past start'), '');
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.enterText(capture, 'Preserved hint-check draft');
      await flows.filterChoice(tester, 'Show upcoming');
      expect(details('Later today'), 'Starts 17:00');
      expect(details('Later date'), 'Starts Oct 5 17:00');
      expect(details('Date only'), 'Starts Oct 5');
      base = DateTime.utc(2026, 10, 2, 16, 59, 57);
      elapsed
        ..reset()
        ..start();
      source.onChanged();
      await tester.pumpAndSettle();
      expect(details('Later today'), 'Starts 17:00');
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      await tester.pumpAndSettle();
      expect(details('Later today'), '');
      expect(
        tester.widget<TextField>(capture).controller!.text,
        'Preserved hint-check draft',
      );
      base = DateTime.utc(2026, 10, 4, 23, 59, 57);
      elapsed.reset();
      source.onChanged();
      await tester.pumpAndSettle();
      expect(details('Later date'), 'Starts Oct 5 17:00');
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      await tester.pumpAndSettle();
      expect(details('Later date'), 'Starts 17:00');
      expect(details('Date only'), '');
      elapsed.stop();
      base = DateTime.utc(2026, 10, 2, 12);
      elapsed.reset();
      source.onChanged();
      await tester.pumpAndSettle();
      await flows.filterChoice(tester, 'Show upcoming');
      expect(find.text('Later date'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'Later date',
      );
      await tester.pumpAndSettle();
      expect(details('Later date'), 'Starts Oct 5 17:00');
      base = DateTime.utc(2026, 10, 5, 16);
      zone = 'America/New_York';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(details('Later date'), 'Starts 17:00');
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'Pinned task',
      );
      await tester.pumpAndSettle();
      expect(details('Pinned task'), 'Starts 13:00');
      await tester.enterText(
        find.byKey(const ValueKey('task-search')),
        'Retained history',
      );
      await tester.pumpAndSettle();
      expect(details('Retained history'), '');
      expect(await logs(), before);
      expect(tester.takeException(), isNull);
    } finally {
      elapsed.stop();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await writer.close();
      await root.delete(recursive: true);
    }
  });
}
