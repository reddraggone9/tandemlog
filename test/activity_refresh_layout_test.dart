import 'dart:io';
import 'dart:convert';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/activity_log.dart';
import 'package:tandemlog/storage/unified_history.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';
import 'support/ux_capture.dart';
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() => activityRefreshLayoutTests();

void activityRefreshLayoutTests({
  bool native = false,
  Future<void> Function(WidgetTester, String) capture = captureUx,
}) {
  if (!native) {
    setUpAll(() async {
      await loadSdkRoboto();
      await loadUxIcons();
    });
  }
  for (final size in [
    const Size(390, 640),
    const Size(320, 640),
    const Size(640, 360),
  ]) {
    for (final failed in [false, true]) {
      for (final brightness in Brightness.values) {
        testWidgets('Activity size=$size scale=2 failed=$failed $brightness', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('qreview-activity-'),
          ))!;
          final profile = (await tester.runAsync(
            () => LocalProfileDatabase.open('${root.path}/profile'),
          ))!;
          await tester.runAsync(() => LocalSettings.initialize(profile));
          final settings = LocalSettings(
            '${root.path}/profile',
            profileDatabase: profile,
          );
          await tester.runAsync(() => settings.load());
          final folder = (await tester.runAsync(
            () => Directory('${root.path}/shared').create(),
          ))!;
          final history = (await tester.runAsync(
            () => UnifiedHistory.create(
              LocalLogFolder(folder.path),
              profile: profile,
              writer: settings.writer,
            ),
          ))!;
          await tester.runAsync(
            () => history.renameDevice('Synthetic review device'),
          );
          Future<Map<String, String>> canonicalBytes() async => {
            await for (final file in folder.list())
              if (file is File)
                file.path: base64Encode(await file.readAsBytes()),
          };
          final before = await tester.runAsync(canonicalBytes);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() async {
              await history.close();
              await profile.close();
              await root.delete(recursive: true);
            });
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: tandemlogTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: RepaintBoundary(
                  key: const ValueKey('ux-root'),
                  child: child!,
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => ActivityLogDialog(history: history),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          if (failed) {
            history.reportQueueFailure(StateError('synthetic'));
            await tester.pumpAndSettle();
          }
          final name =
              'activity-${size.width.round()}x${size.height.round()}-${brightness.name}-$failed';
          await capture(tester, '$name-banner');
          expect(tester.takeException(), isNull);
          final list = find.byKey(const ValueKey('activity-list'));
          expect(
            tester.getSize(list).height,
            greaterThan(40),
            reason: 'History needs a usable scroll viewport',
          );
          expect(
            find.text('Recorded by device; active user not recorded.'),
            findsOneWidget,
          );
          if (failed) {
            final error = find.byKey(const ValueKey('activity-refresh-error'));
            expect(error, findsOneWidget);
            await tester.ensureVisible(error);
            await tester.pumpAndSettle();
            final viewport = tester.getRect(list);
            final copy = tester.getRect(error);
            expect(copy.top, greaterThanOrEqualTo(viewport.top - 1));
            expect(
              copy.bottom,
              lessThanOrEqualTo(viewport.bottom + 1),
              reason: 'The whole refresh failure must be readable by scrolling',
            );
            await capture(tester, '$name-error');
          }
          // Retained history may start below readable copy; it must be reachable by
          // touch scrolling, not merely present in the widget tree.
          await tester.scrollUntilVisible(
            find.textContaining('Device renamed'),
            80,
            scrollable: find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            ),
            maxScrolls: 20,
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Device renamed').hitTestable(),
            findsOneWidget,
          );
          await capture(tester, '$name-row');
          await tester.tap(find.textContaining('Device renamed'));
          await tester.pumpAndSettle();
          expect(find.text('Activity details'), findsOneWidget);
          await capture(tester, '$name-details');
          expect(tester.takeException(), isNull);
          expect(await tester.runAsync(canonicalBytes), before);
        });
      }
    }
  }
}
