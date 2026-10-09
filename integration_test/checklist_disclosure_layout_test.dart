import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('disclosure bottom spacing and ink retain compact row geometry', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('disclosure-layout-');
    final shared = await Directory('${root.path}/shared').create();
    final profile = await Directory('${root.path}/profile').create();
    final peer = await openNativeFixtureStore(
      LocalLogFolder(shared.path),
      '${root.path}/peer',
    );
    final user = const Uuid().v4();
    final pairs = [
      (const Uuid().v4(), const Uuid().v4(), true),
      (const Uuid().v4(), const Uuid().v4(), false),
    ];
    final bottomGaps = <(double, double)>[];
    try {
      await peer.command(user, 'user.created', {'name': 'Alex Example'});
      for (final pair in pairs) {
        for (final id in [pair.$1, pair.$2]) {
          await peer.createNativeFixtureTask(id, {
            'title': 'Clean bedroom bathroom',
            'description': id == pair.$2 || pair.$3
                ? 'Tile floor and basin'
                : '',
            'tags': pair.$3 ? ['chore'] : <String>[],
            'assignee': user,
          });
        }
        for (var item = 0; item < 6; item++) {
          await peer.addChecklistItem(pair.$1, 'Item ${item + 1}');
        }
      }
      await File('${profile.path}/settings.json').writeAsString(
        jsonEncode({'folder': shared.path, 'user': user, 'appearance': 'dark'}),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
      for (var wait = 0; wait < 100; wait++) {
        if (_key('task-body-${pairs.first.$1}').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      Future<void> reveal(Finder finder) async {
        await Scrollable.ensureVisible(
          finder.evaluate().single,
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
      }

      double lastTextBottom(Finder body) => find
          .descendant(of: body, matching: find.byType(Text))
          .evaluate()
          .map(
            (element) => tester.getRect(find.byWidget(element.widget)).bottom,
          )
          .reduce((a, b) => a > b ? a : b);

      for (final geometry in [
        (1200.0, 1.0),
        (1200.0, 2.0),
        (390.0, 1.0),
        (390.0, 2.0),
      ]) {
        tester.view.physicalSize = Size(geometry.$1, 1000);
        tester.platformDispatcher.textScaleFactorTestValue = geometry.$2;
        await tester.pumpAndSettle();
        for (final pair in pairs) {
          final ordinaryBody = _key('task-body-${pair.$2}');
          await reveal(ordinaryBody);
          final ordinaryGap =
              tester.getRect(_key('task-row-${pair.$2}')).bottom -
              lastTextBottom(ordinaryBody);
          final body = _key('task-body-${pair.$1}');
          final disclosure = _key('checklist-disclosure-${pair.$1}');
          await reveal(disclosure);
          final count = find.descendant(
            of: disclosure,
            matching: find.byType(Text),
          );
          final countRect = tester.getRect(count);
          final target = tester.getRect(disclosure);
          final row = tester.getRect(_key('task-row-${pair.$1}'));
          final button = tester.widget<TextButton>(disclosure);
          final shape = button.style?.shape?.resolve({});
          final ink = shape!
              .getOuterPath(Offset.zero & target.size)
              .getBounds()
              .shift(target.topLeft);
          expect(
            ink.center.dy,
            closeTo(countRect.center.dy, 0.01),
            reason:
                'Ink surrounds the count without shifting its vertical position.',
          );
          expect(countRect.left - tester.getRect(body).left, closeTo(13, 0.01));
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
          expect(tester.getRect(body).bottom, lessThanOrEqualTo(target.top));
          expect(countRect.top - lastTextBottom(body), closeTo(2, 0.01));
          final viewport = tester.getRect(find.byType(CustomScrollView).last);
          final inset = viewport.width < 600 ? 0.0 : 16.0;
          expect(row.left, closeTo(viewport.left + inset, 0.01));
          expect(row.right, closeTo(viewport.right - inset, 0.01));
          debugPrint(
            'DISCLOSURE_LAYOUT width=${geometry.$1} scale=${geometry.$2} '
            'secondary=${pair.$3} ordinaryBottom=$ordinaryGap '
            'disclosureBottom=${row.bottom - countRect.bottom} '
            'body=${tester.getRect(body)} target=$target count=$countRect '
            'shape=${button.style?.shape?.resolve({})}',
          );
          bottomGaps.add((row.bottom - countRect.bottom, ordinaryGap));
          if (geometry == (1200.0, 1.0) && pair.$3) {
            final press = await tester.startGesture(countRect.center);
            await tester.pump(const Duration(milliseconds: 150));
            await captureNativeFixtureUi(tester, 'disclosure-held-ink');
            await press.cancel();
            await tester.pumpAndSettle();
          }
          await captureNativeFixtureUi(
            tester,
            'disclosure-${geometry.$1.toInt()}-${geometry.$2.toInt()}-${pair.$3}',
          );
          // The ink occupies only the label rectangle. The remaining target
          // still activates the button and must not fall through to row selection.
          await tester.tapAt(Offset(target.right - 2, target.bottom - 2));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          expect(_key('inline-checklist-${pair.$1}'), findsOneWidget);
          await reveal(disclosure);
          final expandedTarget = tester.getRect(disclosure);
          final expandedCount = tester.getRect(count);
          final expandedInk = tester
              .widget<TextButton>(disclosure)
              .style!
              .shape!
              .resolve({})!
              .getOuterPath(Offset.zero & expandedTarget.size)
              .getBounds()
              .shift(expandedTarget.topLeft);
          expect(
            expandedCount.left - tester.getRect(body).left,
            closeTo(13, 0.01),
          );
          expect(expandedCount.top - lastTextBottom(body), closeTo(2, 0.01));
          expect(expandedCount.center.dy, closeTo(expandedInk.center.dy, 0.01));
          expect(
            tester.getRect(body).bottom,
            lessThanOrEqualTo(expandedTarget.top),
          );
          await captureNativeFixtureUi(
            tester,
            'disclosure-expanded-${geometry.$1.toInt()}-${geometry.$2.toInt()}-${pair.$3}',
          );
          await tester.tapAt(
            Offset(expandedTarget.left + 2, expandedTarget.bottom - 2),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          expect(_key('inline-checklist-${pair.$1}'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
      for (final gap in bottomGaps) {
        expect(
          gap.$1,
          closeTo(gap.$2, 0.01),
          reason:
              'Disclosure matches comparable ordinary text bottom clearance.',
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await peer.close();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
  });
}
