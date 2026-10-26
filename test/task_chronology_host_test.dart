import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:uuid/uuid.dart';
import '../integration_test/native_text_fixtures.dart';
import 'section_navigation_host_test.dart' as host;
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;
import 'support/ux_capture.dart';

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  setUpAll(() async {
    await loadSdkRoboto();
    await loadUxIcons();
  });
  testWidgets(
    'native-backed host shows tomorrow timed task in Today and completion dates in search',
    (tester) async {
      final data = (await tester.runAsync(() async {
        final data = await host.fixture();
        final seed = await openNativeFixtureStore(
          data.folder,
          '${data.root.path}/chronology',
          nativeLibraryPath: host.nativeHostLibraryPath,
        );
        try {
          await seed.createNativeFixtureTask(const Uuid().v4(), {
            'title': 'Timed tomorrow',
            'description': '',
            'assignee': data.user,
            'schedule': {'dueDate': '2026-10-13', 'dueTime': '10:00'},
          });
          await seed.createNativeFixtureTask(const Uuid().v4(), {
            'title': 'Untimed tomorrow',
            'description': '',
            'assignee': data.user,
            'schedule': {'dueDate': '2026-10-13'},
          });
          final done = const Uuid().v4();
          await seed.createNativeFixtureTask(done, {
            'title': 'Completed history',
            'description': '',
            'assignee': data.user,
            'schedule': {'dueDate': '2099-01-01'},
          });
          await seed.complete(
            done,
            localZoneId: 'UTC',
            completionInstant: DateTime.utc(2026, 10, 11),
          );
        } finally {
          await seed.close();
        }
        return data;
      }))!;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('ux-root'),
          child: TandemlogApp(
            profilePath: data.profile,
            textEngineFactory: host.createHostTextEngine,
            timeSourceFactory: host.createHostTimeSource,
          ),
        ),
      );
      await host.ready(
        tester,
        () => find.text('Timed tomorrow').evaluate().isNotEmpty,
      );
      final resources = host.hostResources(tester);
      try {
        expect(find.text('Today'), findsOneWidget);
        expect(find.textContaining('Due 2026-10-13 10:00'), findsOneWidget);
        expect(find.text('Tuesday · 2026-10-13'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Today')).dy,
          lessThan(tester.getTopLeft(find.text('Timed tomorrow')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Timed tomorrow')).dy,
          lessThan(tester.getTopLeft(find.text('Tuesday · 2026-10-13')).dy),
        );
        await captureUx(tester, 'task-today-800');
        await tester.enterText(
          find.byKey(const ValueKey('task-search')),
          'Completed history',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Completed 2026-10-11'), findsOneWidget);
        expect(find.text('Sunday · 2026-10-11'), findsOneWidget);
        expect(find.textContaining('2099'), findsNothing);
        await captureUx(tester, 'task-completed-search-800');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
}
