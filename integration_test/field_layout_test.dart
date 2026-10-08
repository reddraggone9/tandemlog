import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFieldLayoutTests();
}

void registerFieldLayoutTests() {
  for (final variant in const [
    (width: 1200.0, scale: 1.0, theme: 'dark'),
    (width: 390.0, scale: 1.0, theme: 'dark'),
    (width: 390.0, scale: 2.0, theme: 'light'),
  ]) {
    testWidgets('native field spacing ${variant.width}/${variant.scale}', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('field-layout-');
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final peer = await openNativeFixtureStore(
        LocalLogFolder(shared.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4(), task = const Uuid().v4();
      Future<Map<String, String>> canonical() async => {
        await for (final file in shared.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      try {
        await peer.command(user, 'user.created', {'name': 'Lee'});
        await peer.createNativeFixtureTask(task, {
          'title': 'Plan the weekend',
          'description': '',
          'assignee': user,
          'schedule': {'dueMinDays': 0},
        });
        await peer.edit(task, {}, tags: ['backlog'], observedTagRefs: {});
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': variant.theme,
          }),
        );
        final before = await canonical();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, 850);
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
        await flows.waitForUi(
          tester,
          () => find.byKey(ValueKey('task-row-$task')).evaluate().isNotEmpty,
        );
        await flows.selectTask(tester, task, control: false);
        final minimum = find.byKey(const ValueKey('dueMinDays'));
        await tester.ensureVisible(minimum);
        await tester.pumpAndSettle();
        final explanation = find.text(
          'Days from today; affects listing order, not the deadline.',
        );
        final label = find.descendant(
          of: minimum,
          matching: find.text('Minimum days'),
        );
        expect(
          tester.getRect(label).top - tester.getRect(explanation).bottom,
          greaterThanOrEqualTo(8),
        );
        expect(tester.widget<TextField>(minimum).controller!.text, '0');
        final suffix =
            '${variant.width.toInt()}-${variant.theme}-${variant.scale.toInt() * 100}';
        await captureNativeFixtureUi(tester, 'bounds-$suffix');
        final cancel = find.text('Cancel').last;
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await flows.openFilters(tester);
        final search = find.byKey(const ValueKey('tag-search'));
        final anchor = find.byKey(const ValueKey('tag-autocomplete'));
        final gaps = <double>[];
        for (final selected in [false, true]) {
          if (selected) await flows.chooseFilter(tester, '#backlog');
          await tester.ensureVisible(search);
          await tester.tap(search);
          await tester.pumpAndSettle();
          await tester.enterText(search, '');
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          final render = tester
              .state<EditableTextState>(
                find.descendant(
                  of: search,
                  matching: find.byType(EditableText),
                ),
              )
              .renderEditable;
          final controller = tester.widget<TextField>(search).controller!;
          final caret = render
              .getLocalRectForCaret(controller.selection.extent)
              .shift(render.localToGlobal(Offset.zero));
          final gap = tester.getRect(anchor).bottom - caret.bottom;
          gaps.add(gap);
          expect(gap, inInclusiveRange(0, 16));
          await captureNativeFixtureUi(
            tester,
            'tags-${selected ? 'selected' : 'empty'}-$suffix',
          );
          if (selected) {
            expect(
              find.byKey(const ValueKey('selected-tag-backlog')),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Clear tag filters'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('selected-tag-backlog')),
              findsNothing,
            );
          }
        }
        expect((gaps.first - gaps.last).abs(), lessThanOrEqualTo(1));
        expect(
          await canonical(),
          before,
          reason: 'spacing and filtering must not write task history',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await peer.close();
        await root.delete(recursive: true);
      }
    });
  }
}
