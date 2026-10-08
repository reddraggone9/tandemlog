import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      'Search keeps Undo and text alignment ${variant.width} x${variant.scale}',
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
          final capture = find.widgetWithText(TextField, 'What needs doing?');
          final add = find.byKey(const ValueKey('capture-add'));
          expect(
            tester.widget(add),
            variant.width == 1200 ? isA<TextButton>() : isA<IconButton>(),
          );
          expect(find.byIcon(Icons.arrow_upward), findsNothing);
          expect(find.byTooltip('Add tasks'), findsOneWidget);
          await tester.enterText(capture, 'Retained capture draft');
          final controller = tester.widget<TextField>(capture).controller!;
          controller.selection = const TextSelection.collapsed(offset: 8);
          final draft = controller.value;
          final undo = find.byKey(const ValueKey('undo-task-action'));
          final undoBefore = tester.getRect(undo);
          final count = find.text('4 open');
          double baseline(Finder finder) {
            final box = tester.renderObject<RenderBox>(finder);
            return box.localToGlobal(Offset.zero).dy +
                box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
          }

          final countBaseline = count.evaluate().isEmpty
              ? null
              : baseline(count);
          final canonical = <String, List<int>>{
            await for (final entry in folder.list())
              entry.path: await File(entry.path).readAsBytes(),
          };
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          expect(tester.getRect(undo), undoBefore);
          final input = find.byKey(const ValueKey('task-search'));
          expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
          if (countBaseline != null && variant.width == 1200) {
            expect(
              baseline(
                find.descendant(of: input, matching: find.byType(EditableText)),
              ),
              closeTo(countBaseline, .5),
            );
          }
          await tester.enterText(input, 'Reference');
          await tester.pumpAndSettle();
          expect(tester.getRect(undo), undoBefore);
          expect(controller.value, draft);
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pumpAndSettle();
          expect(tester.getRect(undo), undoBefore);
          expect(controller.value, draft);
          expect(
            find.byKey(const ValueKey('open-search')).hitTestable(),
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
