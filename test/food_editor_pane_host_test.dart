import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/food/food_page.dart';
import 'package:tandemlog/food/inventory.dart';
import 'package:tandemlog/platform/android_section_navigation.dart';
import 'package:tandemlog/storage/local_settings.dart';

import 'section_navigation_host_test.dart' as support;

void main() {
  support.nativeHostLibraryPath =
      Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  const channel = MethodChannel('tandemlog/food-pane-host-test');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> shortcut(WidgetTester tester, int id) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('openSection', {'id': id, 'section': 'tasks'}),
          ),
          (_) => done.complete(),
        );
    await done.future;
    await tester.pump();
  }

  for (final width in [650.0, 1200.0]) {
    for (final overlay in ['close decision', 'calendar', 'filters']) {
      if (width < 900 && overlay == 'filters') continue;
      for (final discard in [false, true]) {
        testWidgets(
          '$width $overlay coalesces shortcut and ${discard ? 'Discard' : 'Keep editing'}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final data = (await tester.runAsync(
              () => support.fixture(section: AppSection.food),
            ))!;
            try {
              final before = (await tester.runAsync(
                () => support.canonical(data.folder),
              ))!;
              await tester.pumpWidget(
                TandemlogApp(
                  textEngineFactory: support.createHostTextEngine,
                  timeSourceFactory: support.createHostTimeSource,
                  profilePath: data.profile,
                  sectionNavigation: AndroidSectionNavigation(channel: channel),
                ),
              );
              await support.ready(
                tester,
                () => find.byType(FoodInventoryPage).evaluate().isNotEmpty,
              );
              final host = tester.state(find.byType(TasksPage)) as dynamic;
              await tester.tap(find.byTooltip('Add food'));
              await tester.pumpAndSettle();
              final name = find.widgetWithText(TextField, 'Food name');
              await tester.enterText(name, 'Synthetic pane host draft');
              if (overlay == 'close decision') {
                await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
                await tester.pumpAndSettle();
              } else if (overlay == 'calendar') {
                await tester.tap(find.byTooltip('Choose Expiration'));
                await tester.pumpAndSettle();
              } else {
                final page = tester.state<FoodInventoryPageState>(
                  find.byType(FoodInventoryPage),
                );
                await tester.tap(find.byKey(const ValueKey('food-filter')));
                await tester.pumpAndSettle();
                await tester.tap(
                  find
                      .byWidgetPredicate(
                        (w) => w is PopupMenuItem<FoodView> && w.onTap != null,
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(page.closeBusy, isTrue);
              }
              await shortcut(tester, 1);
              await shortcut(tester, 2);
              if (overlay != 'close decision') {
                expect(find.text('Discard food changes?'), findsNothing);
                if (overlay == 'calendar') {
                  await tester.tap(find.text('Cancel').last);
                } else {
                  await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
                }
              }
              await support.ready(
                tester,
                () => find.text('Discard food changes?').evaluate().isNotEmpty,
              );
              expect(find.text('Discard food changes?'), findsOneWidget);
              await tester.tap(find.text(discard ? 'Discard' : 'Keep editing'));
              await support.ready(
                tester,
                () => host.sectionWork == null && host.busy == false,
              );
              expect(find.text('Discard food changes?'), findsNothing);
              expect(host.foodVisible, !discard);
              expect(
                host.settings.lastSection,
                discard ? AppSection.tasks : AppSection.food,
              );
              if (!discard) {
                expect(
                  tester.widget<TextField>(name).controller!.text,
                  'Synthetic pane host draft',
                );
              }
              expect(
                await tester.runAsync(() => support.canonical(data.folder)),
                before,
              );
              expect(tester.takeException(), isNull);
            } finally {
              final resources = support.hostResources(tester);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              await support.waitForHostShutdown(tester, resources);
              await tester.runAsync(() => data.root.delete(recursive: true));
            }
          },
        );
      }
    }
  }
}
