import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:uuid/uuid.dart';

import 'bulk_apply_semantics_test.dart' as media;
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerBulkFailureVisibilityTests();
}

Future<Map<String, String>> canonicalHashes(Directory folder) async => {
  await for (final file in folder.list())
    if (file is File && file.path.endsWith('.jsonl'))
      file.path: sha256.convert(await file.readAsBytes()).toString(),
};

void registerBulkFailureVisibilityTests() {
  for (final variant in const [
    (
      name: 'desktop-dark',
      width: 1200.0,
      height: 850.0,
      scale: 1.0,
      dark: true,
      keyboard: 0.0,
      android: false,
    ),
    (
      name: 'narrow-dark',
      width: 390.0,
      height: 820.0,
      scale: 1.0,
      dark: true,
      keyboard: 0.0,
      android: false,
    ),
    (
      name: 'narrow-light-200-ime',
      width: 390.0,
      height: 820.0,
      scale: 2.0,
      dark: false,
      keyboard: 280.0,
      android: false,
    ),
    (
      name: 'small-dark-200-ime',
      width: 360.0,
      height: 640.0,
      scale: 2.0,
      dark: true,
      keyboard: 280.0,
      android: false,
    ),
    (
      name: 'android-small-dark-200-ime',
      width: 320.0,
      height: 640.0,
      scale: 2.0,
      dark: true,
      keyboard: 280.0,
      android: true,
    ),
  ]) {
    testWidgets('native stale bulk failure stays visible ${variant.name}', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp(
        'bulk-failure-visible-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final peer = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4();
      final ids = [const Uuid().v4(), const Uuid().v4()];
      await peer.command(user, 'user.created', {'name': 'Alex Example'});
      for (var index = 0; index < ids.length; index++) {
        await peer.createNativeFixtureTask(ids[index], {
          'title': 'Bulk fixture ${index + 1}',
          'description': '',
          'assignee': user,
          'schedule': <String, dynamic>{},
        });
      }
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      Process? recording;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = variant.android
            ? TargetPlatform.android
            : previousPlatform;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, variant.height);
        tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
        tester.platformDispatcher.platformBrightnessTestValue = variant.dark
            ? Brightness.dark
            : Brightness.light;
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (changed) => ViewTimeSource(
              onChanged: changed,
              now: () => DateTime.utc(2026, 10, 8, 12),
              loadZone: () async => 'UTC',
            ),
          ),
        );
        await flows.waitForUi(
          tester,
          () => find.text('Bulk fixture 1').evaluate().isNotEmpty,
        );
        await flows.selectTask(tester, ids[0]);
        await flows.selectTask(tester, ids[1], control: false);
        if (find.byType(BulkTaskEditor).evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('edit-selected-tasks')));
          await tester.pumpAndSettle();
        }
        final editor = find.byType(BulkTaskEditor);
        expect(editor, findsOneWidget);
        tester.view.viewInsets = FakeViewPadding(bottom: variant.keyboard);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('dueMaxDays'));
        await tester.ensureVisible(field);
        await tester.enterText(field, '12');
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 1,
        );
        await tester.pump();
        final draft = controller.value;
        final scrollable = find
            .descendant(of: editor, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        if (variant.name == 'android-small-dark-200-ime') {
          recording = await media.startBulkRecording(
            caption:
                'Linux GTK debug workingtree70 - scripted touch - 320x640 200pct simulated IME',
          );
        }
        await captureNativeFixtureUi(
          tester,
          'bulk-failure-${variant.name}-before-save',
        );
        await peer.editNativeFixtureTask(ids.first, {
          'description': 'Updated elsewhere',
        });
        await tester.pumpAndSettle();
        final before = await canonicalHashes(folder);
        await media.pointAndPause(tester, find.text('Save changes'), recording);
        await tester.tap(find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () => find.textContaining('changed').evaluate().isNotEmpty,
        );
        await captureNativeFixtureUi(
          tester,
          'bulk-failure-${variant.name}-after-rejection',
        );
        final warning = find.textContaining('changed').last;
        expect(
          warning.hitTestable(at: const Alignment(0, -.99)),
          findsOneWidget,
        );
        final afterFirstSave = position.pixels;
        final focus = FocusManager.instance.primaryFocus;
        expect(controller.value, draft);
        expect(find.text('Edit 2 tasks'), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(find.text('Save changes').hitTestable(), findsOneWidget);
        if (!tester.widget<BulkTaskEditor>(editor).panel) {
          final notice = find.byKey(const ValueKey('bulk-save-failure'));
          final rect = tester.getRect(notice);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(
            rect.bottom,
            lessThanOrEqualTo(variant.height - variant.keyboard),
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(tester.getRect(find.text('Cancel')).top),
          );
        }
        if (variant.name.endsWith('small-dark-200-ime')) {
          // Failure feedback must not leave the form with a zero viewport.
          expect(position.viewportDimension, greaterThanOrEqualTo(48));
          final notice = find.byKey(const ValueKey('bulk-save-failure'));
          await media.pointAndPause(tester, notice, recording);
          await tester.drag(notice, const Offset(0, -120));
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: warning, matching: find.byType(RichText)).last,
          );
          final message = tester.widget<Text>(warning).data!;
          final tail = message.lastIndexOf('try again.');
          expect(tail, greaterThanOrEqualTo(0));
          final visible = tester.getRect(notice);
          final origin = paragraph.localToGlobal(Offset.zero);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: tail, extentOffset: message.length),
          );
          expect(boxes, isNotEmpty);
          final warningScroll = tester
              .state<ScrollableState>(
                find
                    .descendant(of: notice, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          stdout.writeln(
            'BULK_WARNING_GEOMETRY ${variant.name} '
            'viewport=$visible paragraph=${tester.getRect(warning)} '
            'pixels=${warningScroll.pixels} max=${warningScroll.maxScrollExtent} '
            'body=${position.viewportDimension} tail=$boxes',
          );
          await captureNativeFixtureUi(
            tester,
            'bulk-failure-${variant.name}-after-warning-drag',
          );
          for (final box in boxes) {
            final rect = box.toRect().shift(origin);
            expect(rect.top, greaterThanOrEqualTo(visible.top - .5));
            expect(rect.bottom, lessThanOrEqualTo(visible.bottom + .5));
          }
        }
        await captureNativeFixtureUi(
          tester,
          'bulk-failure-${variant.name}-rejected',
        );
        await media.pointAndPause(tester, find.text('Save changes'), recording);
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(position.pixels, afterFirstSave);
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(controller.value, draft);
        expect(await canonicalHashes(folder), before);
        await peer.refresh();
        expect(
          peer.rows.singleWhere((row) => row['id'] == ids.first)['description'],
          'Updated elsewhere',
        );
        for (final id in ids) {
          expect(
            (peer.rows.singleWhere((row) => row['id'] == id)['schedule']
                as Map)['dueMaxDays'],
            isNull,
          );
        }
        await media.pointAndPause(tester, find.text('Cancel'), recording);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await media.pointAndPause(tester, find.text('Discard'), recording);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(BulkTaskEditor), findsNothing);
        expect(await canonicalHashes(folder), before);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
        await media.stopBulkRecording(recording);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        await peer.close();
        // Synthetic fixtures are retained; no live user data is accessed.
      }
    });
  }
}
