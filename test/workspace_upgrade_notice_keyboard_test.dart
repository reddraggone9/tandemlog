import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';

import 'section_navigation_host_test.dart' as host;
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

class _FailingUpgradeNoticePicker extends FolderActions {
  int calls = 0;

  @override
  bool get requiresPicker => true;

  @override
  Future<String?> pick() async {
    calls++;
    throw StateError('Could not open the folder picker. Try again.');
  }

  @override
  Future<bool> canOpen(String location) async => false;
}

void main() {
  setUpAll(loadSdkRoboto);
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;

  for (final appearance in [Appearance.light, Appearance.dark]) {
    testWidgets(
      'upgrade notice yields to retained picker diagnostic after discard at 320dp 200% ${appearance.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewPadding();
          tester.view.resetPadding();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          debugDefaultTargetPlatformOverride = null;
        });
        final data = (await tester.runAsync(host.fixture))!;
        try {
          await tester.runAsync(() async {
            final profile = await LocalProfileDatabase.open(data.profile);
            try {
              final settings = LocalSettings(
                data.profile,
                profileDatabase: profile,
              );
              await settings.load();
              settings.appearance = appearance;
              await settings.save();
            } finally {
              await profile.close();
            }
          });
          final picker = _FailingUpgradeNoticePicker();
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: data.profile,
              folderActions: picker,
              textEngineFactory: host.createHostTextEngine,
              timeSourceFactory: host.createHostTimeSource,
            ),
          );
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          await host.ready(
            tester,
            () => state.store != null && state.busy == false,
          );
          final notice = find.byKey(
            const ValueKey('workspace-upgrade-available'),
          );
          expect(notice, findsOneWidget);
          final before = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;

          final directSettings = find.byTooltip('Settings');
          if (directSettings.evaluate().isNotEmpty) {
            await tester.tap(directSettings);
          } else {
            await tester.tap(find.byKey(const ValueKey('identity-menu')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Settings').last);
          }
          await tester.pumpAndSettle();
          expect(find.text('Upgrade shared workspace…'), findsOneWidget);
          final choose = find.widgetWithText(
            TextButton,
            'Use a different folder',
          );
          await tester.ensureVisible(choose);
          await tester.tap(choose);
          await host.ready(
            tester,
            () => state.error != null && state.choosingFolder == false,
          );
          expect(picker.calls, 1);
          expect(state.error, contains('Could not open the folder picker'));

          await tester.tap(find.text('Synthetic section task'));
          final title = find.byKey(const ValueKey('title'));
          await host.ready(tester, () => title.evaluate().isNotEmpty);
          await tester.enterText(title, 'Synthetic unsaved keyboard draft');
          tester.view.padding = const FakeViewPadding(top: 24);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(
            find.byKey(const ValueKey('action-error-scroll')),
            findsOneWidget,
          );

          final cancel = find.widgetWithText(TextButton, 'Cancel');
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.text('Unsaved changes'), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'Discard'));
          await tester.pumpAndSettle();

          // This closing-editor frame still has the captured Android IME inset.
          // Its real retained diagnostic must fit alongside the ordinary toolbar.
          expect(tester.view.viewInsets.bottom, 280);
          expect(find.byType(TaskEditor), findsNothing);
          expect(find.text('Unsaved changes'), findsNothing);
          expect(state.error, contains('Could not open the folder picker'));
          expect(
            find.byKey(const ValueKey('action-error-scroll')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(notice, findsNothing);
          expect(
            await tester.runAsync(() => host.canonical(data.folder)),
            before,
          );

          tester.view.resetViewInsets();
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          await tester.pumpAndSettle();
          expect(notice, findsOneWidget);
          expect(notice.hitTestable(), findsOneWidget);
          expect(state.error, contains('Could not open the folder picker'));
          expect(tester.takeException(), isNull);
          expect(
            await tester.runAsync(() => host.canonical(data.folder)),
            before,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
          if (find.byType(TasksPage).evaluate().isNotEmpty) {
            final resources = host.hostResources(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await host.waitForHostShutdown(tester, resources);
          }
          await tester.runAsync(() => data.root.delete(recursive: true));
        }
      },
    );
  }
}
