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
  registerDateTimeRowTests();
}

void registerDateTimeRowTests() {
  testWidgets('optional time rows preserve precision, zone and drafts', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('date-time-rows-');
    final folder = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final seed = await openNativeFixtureStore(
      LocalLogFolder(folder.path),
      '${root.path}/seed',
    );
    final user = const Uuid().v4(), id = const Uuid().v4();
    await seed.command(user, 'user.created', {'name': 'Alex Example'});
    await seed.createNativeFixtureTask(id, {
      'title': 'Plan reference meeting',
      'description': '',
      'assignee': user,
      'schedule': {
        'startDate': '2026-10-03',
        'startTime': '09:30',
        'dueDate': '2026-10-04',
        'timeZone': 'UTC',
      },
    });
    await File(
      '${profile.path}/settings.json',
    ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
    Future<Map<String, String>> canonical() async => {
      await for (final file in folder.list())
        if (file is File) file.path: base64Encode(await file.readAsBytes()),
    };
    final before = await canonical();
    try {
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
        () => find.text('Plan reference meeting').evaluate().isNotEmpty,
      );
      for (final variant in const [
        (width: 1200.0, scale: 1.0, brightness: Brightness.light),
        (width: 1200.0, scale: 2.0, brightness: Brightness.dark),
        (width: 390.0, scale: 1.0, brightness: Brightness.dark),
        (width: 320.0, scale: 2.0, brightness: Brightness.light),
      ]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, 820);
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        tester.platformDispatcher.platformBrightnessTestValue =
            variant.brightness;
        await tester.pumpAndSettle();
        await flows.selectTask(tester, id, control: false);
        final dueDate = find.byKey(const ValueKey('dueDate'));
        final dueTime = find.byKey(const ValueKey('dueTime'));
        await tester.ensureVisible(dueTime);
        await tester.pumpAndSettle();
        expect(dueTime, findsOneWidget);
        expect(tester.widget<TextField>(dueTime).controller!.text, isEmpty);
        expect(tester.getSize(dueTime).height, greaterThanOrEqualTo(48));
        final sideBySide = variant.scale == 1;
        expect(
          tester.getTopLeft(dueTime).dy,
          sideBySide
              ? closeTo(tester.getTopLeft(dueDate).dy, .5)
              : greaterThan(tester.getTopLeft(dueDate).dy),
        );
        await tester.tap(dueTime);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(dueTime).focusNode!.hasFocus, isTrue);
        await tester.enterText(dueTime, '00:00');
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(dueDate).controller!.text,
          '2026-10-04',
        );
        if (variant.width < 400) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          await tester.ensureVisible(dueTime);
          await tester.pumpAndSettle();
          expect(tester.getRect(dueTime).bottom, lessThanOrEqualTo(560));
        }
        await tester.tap(find.byTooltip('Clear Due time'));
        await tester.pumpAndSettle();
        expect(dueTime, findsOneWidget);
        expect(tester.widget<TextField>(dueTime).controller!.text, isEmpty);
        expect(
          tester.widget<TextField>(dueDate).controller!.text,
          '2026-10-04',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('startTime')))
              .controller!
              .text,
          '09:30',
        );
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        final cancel = find.text('Cancel').last;
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
        expect(await canonical(), before);
        expect(tester.takeException(), isNull);
      }
      await flows.selectTask(tester, id, control: false);
      final dueTime = find.byKey(const ValueKey('dueTime'));
      await tester.ensureVisible(dueTime);
      await tester.tap(dueTime);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dueTime')), '00:00');
      await tester.pumpAndSettle();
      final save = find.text('Save changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await flows.waitForUi(tester, () => save.evaluate().isEmpty);
      await seed.refresh();
      final schedule = seed.rows.singleWhere(
        (row) => row['id'] == id,
      )['schedule'];
      expect(schedule['dueDate'], '2026-10-04');
      expect(schedule['dueTime'], '00:00');
      expect(schedule['startTime'], '09:30');
      expect(schedule['timeZone'], 'UTC');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await seed.close();
      await root.delete(recursive: true);
    }
  });
}
