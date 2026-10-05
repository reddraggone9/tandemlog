import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/profile_lock.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerInboxFlowTests();
}

void registerInboxFlowTests() {
  testWidgets(
    'second instance does not read or write preferences and Retry acquires released lease',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('profile-ui-');
      final holder = await ProfileLock.acquire(root.path);
      try {
        await tester.pumpWidget(TandemlogApp(profilePath: root.path));
        await flows.waitForUi(
          tester,
          () => find.textContaining('already open').evaluate().isNotEmpty,
        );
        expect(await File('${root.path}/settings.json').exists(), isFalse);
        expect(await Directory('${root.path}/shared-data').exists(), isFalse);
        await holder.close();
        await tester.tap(find.text('Retry'));
        await flows.waitForUi(
          tester,
          () =>
              find.text('Start').evaluate().isNotEmpty &&
              find.textContaining('already open').evaluate().isEmpty,
        );
        expect(await File('${root.path}/settings.json').exists(), isTrue);
        expect(await Directory('${root.path}/shared-data').exists(), isFalse);
      } finally {
        await holder.close();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final released = await ProfileLock.acquire(root.path);
        await released.close();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'interrupted startup releases installation lease after pending work',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('profile-interrupt-');
      await tester.pumpWidget(TandemlogApp(profilePath: root.path));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      ProfileLock? released;
      for (var attempt = 0; attempt < 100 && released == null; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        try {
          released = await ProfileLock.acquire(root.path);
        } on ProfileInUse {
          /* shutdown is still pending */
        }
      }
      expect(released, isNotNull);
      await released!.close();
      await root.delete(recursive: true);
    },
  );
  testWidgets('Inbox capture cancel edit Undo and history remain coherent', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('inbox-flow-');
    final shared = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final writer = await openNativeFixtureStore(
      LocalLogFolder(shared.path),
      '${root.path}/seed',
    );
    final user = const Uuid().v4();
    await writer.command(user, 'user.created', {'name': 'Alex Example'});
    await writer.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Dated reference',
      'description': '',
      'assignee': user,
      'schedule': {'dueDate': '2026-10-03'},
    });
    await writer.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Organized reference',
      'description': 'A useful note',
      'assignee': user,
    });
    await writer.close();
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': shared.path, 'user': user}));
    tester.view.physicalSize = const Size(1000, 820);
    tester.view.devicePixelRatio = 1;
    try {
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: profile.path,
          timeSourceFactory: (changed) => ViewTimeSource(
            onChanged: changed,
            now: () => DateTime.utc(2026, 10, 3, 12),
            loadZone: () async => 'UTC',
          ),
        ),
      );
      await flows.waitForUi(
        tester,
        () => find.text('Dated reference').evaluate().isNotEmpty,
      );
      expect(find.text('Inbox'), findsNothing);
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      await tester.enterText(capture, 'Raw reference');
      await tester.tap(find.byKey(const ValueKey('capture-add')));
      await flows.waitForUi(
        tester,
        () => find.text('Inbox').evaluate().isNotEmpty,
      );
      expect(
        tester.getTopLeft(find.text('Raw reference')).dy,
        lessThan(tester.getTopLeft(find.text('Dated reference')).dy),
      );
      await tester.tap(find.text('Raw reference'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      await tester.tap(find.text('Raw reference'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Edited reference',
      );
      await tester.tap(find.text('Save changes'));
      await flows.waitForUi(
        tester,
        () =>
            find.text('Edited reference').evaluate().isNotEmpty &&
            find.text('Inbox').evaluate().isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('undo-task-action')));
      await flows.waitForUi(
        tester,
        () =>
            find.text('Raw reference').evaluate().isNotEmpty &&
            find.text('Inbox').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Complete Raw reference'));
      await flows.waitForUi(
        tester,
        () => find.text('Raw reference').evaluate().isEmpty,
      );
      expect(find.text('Inbox'), findsNothing);
      await flows.openFilters(tester);
      await flows.chooseFilter(tester, 'Completed');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Raw reference'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
      await tester.tap(find.byTooltip('Reopen Raw reference'));
      await tester.pumpAndSettle();
      await flows.openFilters(tester);
      await flows.chooseFilter(tester, 'Open');
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('Inbox'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await root.delete(recursive: true);
    }
  });
}
