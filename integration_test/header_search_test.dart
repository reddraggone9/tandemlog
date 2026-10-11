import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void registerHeaderSearchTests() {
  for (final variant in const [
    (width: 1200.0, scale: 1.0, theme: 'light'),
    (width: 1200.0, scale: 2.0, theme: 'dark'),
    (width: 390.0, scale: 1.0, theme: 'dark'),
    (width: 320.0, scale: 2.0, theme: 'light'),
  ]) {
    testWidgets(
      'Search and Add keep toolbar geometry ${variant.width} x${variant.scale}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('header-search-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/seed',
        );
        final user = const Uuid().v4();
        await seed.command(user, 'user.created', {
          'name': 'Alexandria Example Household',
        });
        await seed.createTasks({
          for (var i = 0; i < 4; i++) const Uuid().v4(): 'Reference $i',
        }, user);
        await seed.close();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': variant.theme,
          }),
        );
        tester.view.physicalSize = Size(variant.width, 820);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
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
            () => find.text('Reference 0').evaluate().isNotEmpty,
          );
          final input = find.byKey(const ValueKey('task-search'));
          expect(input, findsOneWidget);
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
          final toolbar = find.byKey(const ValueKey('task-header'));
          final headerBefore = tester.getRect(toolbar);
          final undo = find.byKey(const ValueKey('undo-task-action'));
          final undoBefore = tester.getRect(undo);
          final entry = tester.getRect(
            find.byKey(const ValueKey('task-entry-area')),
          );
          final inputRect = tester.getRect(input);
          expect(inputRect.width, closeTo(entry.width - 32, 1));
          expect(inputRect.top, greaterThanOrEqualTo(headerBefore.bottom));
          final action = find.byKey(const ValueKey('open-capture'));
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
          final canonical = <String, List<int>>{
            await for (final entry in folder.list())
              entry.path: await File(entry.path).readAsBytes(),
          };
          await tester.enterText(input, 'Reference');
          await tester.pumpAndSettle();
          await flows.openCaptureForTest(tester);
          final capture = find.widgetWithText(TextField, 'What needs doing?');
          expect(input, findsNothing);
          expect(tester.getRect(toolbar), headerBefore);
          expect(tester.getRect(undo), undoBefore);
          final add = find.byKey(const ValueKey('capture-add'));
          expect(
            tester.widget(add),
            variant.width == 1200 ? isA<TextButton>() : isA<IconButton>(),
          );
          expect(find.byIcon(Icons.arrow_upward), findsNothing);
          await tester.enterText(capture, 'Discarded capture draft');
          final controller = tester.widget<TextField>(capture).controller!;
          await flows.openSearchForTest(tester);
          expect(controller.text, isEmpty);
          expect(capture, findsNothing);
          expect(tester.widget<TextField>(input).controller!.text, isEmpty);
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          expect(tester.getRect(toolbar), headerBefore);
          expect(tester.getRect(undo), undoBefore);
          await tester.enterText(input, 'Reference');
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pumpAndSettle();
          expect(tester.getRect(toolbar), headerBefore);
          expect(tester.getRect(undo), undoBefore);
          expect(tester.widget<TextField>(input).controller!.text, isEmpty);
          expect(
            find.byKey(const ValueKey('open-capture')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          for (final entry in canonical.entries) {
            expect(await File(entry.key).readAsBytes(), entry.value);
          }
          expect(await folder.list().length, canonical.length);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
