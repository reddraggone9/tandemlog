import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'profile_fixture.dart';
import 'task_flow_test.dart' show filterChoice, waitForUi;
import 'food_preview_workflow_test.dart' as pixels;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [390.0, 1200.0]) {
    for (final theme in ['light', 'dark']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'completion chronology and in-dialog month grid $width $theme ${scale}x',
          (tester) async {
            final root = await Directory.systemTemp.createTemp('ux-feedback-');
            final folder = await Directory('${root.path}/shared').create();
            final profile = await Directory('${root.path}/profile').create();
            final seed = await openNativeFixtureStore(
              LocalLogFolder(folder.path),
              '${root.path}/seed',
            );
            final user = const Uuid().v4();
            await seed.command(user, 'user.created', {'name': 'Alex Example'});
            for (final (title, instant) in [
              ('Buy envelopes', DateTime.utc(2026, 10, 27, 0, 30)),
              ('Water plants', DateTime.utc(2026, 10, 26, 23, 30)),
              ('Check smoke alarms', DateTime.utc(2026, 10, 25, 12)),
            ]) {
              final id = const Uuid().v4();
              await seed.createNativeFixtureTask(id, {
                'title': title,
                'description': '',
                'assignee': user,
                'schedule': {'dueDate': '2099-01-01'},
                'tags': ['home'],
              });
              await seed.complete(
                id,
                completionInstant: instant,
                localZoneId: 'UTC',
              );
            }
            await seed.close();
            await seedNativeProfile(profile.path, {
              'folder': folder.path,
              'user': user,
              'appearance': theme,
            });
            tester.view.physicalSize = Size(width, 850);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            final suffix = '${width.toInt()}-$theme-${scale.toInt()}00';
            var converted = false;
            Future<void> capture(String screen) async {
              final name = '$screen-$suffix';
              if (Platform.isAndroid) {
                if (!converted) {
                  await binding.convertFlutterSurfaceToImage();
                  converted = true;
                  await tester.pumpAndSettle();
                }
                final bytes = await binding.takeScreenshot(name);
                final output = Directory(
                  '${Directory.systemTemp.path}/ux-feedback-media',
                );
                await output.create(recursive: true);
                await File('${output.path}/$name.png').writeAsBytes(bytes);
                // Retain screenshots in app-private cache for owner-context adb run-as.
                debugPrint('UX_SCREENSHOT=${output.path}/$name.png');
              } else {
                await captureNativeFixtureUi(tester, name);
              }
            }

            try {
              await tester.pumpWidget(
                TandemlogApp(
                  profilePath: profile.path,
                  folderFactory: LocalLogFolder.new,
                  timeSourceFactory: (changed) => ViewTimeSource(
                    onChanged: changed,
                    loadZone: () async => 'America/Chicago',
                    now: () => DateTime.utc(2026, 10, 27, 12),
                  ),
                ),
              );
              await waitForUi(
                tester,
                () => find
                    .byKey(const ValueKey('task-filter'))
                    .evaluate()
                    .isNotEmpty,
              );
              if (width == 390 && theme == 'dark' && scale == 1) {
                await pixels.startRecording(tester);
              }
              await filterChoice(tester, 'Completed');
              await waitForUi(
                tester,
                () => find.text('Buy envelopes').evaluate().isNotEmpty,
              );
              expect(find.text('Monday · 2026-10-26'), findsOneWidget);
              expect(find.textContaining('Completed 2026-'), findsNothing);
              expect(
                tester.getTopLeft(find.text('Buy envelopes')).dy,
                lessThan(tester.getTopLeft(find.text('Water plants')).dy),
              );
              expect(find.textContaining('2099'), findsNothing);
              await capture('completed');
              final search = find.byKey(const ValueKey('task-search'));
              await tester.enterText(search, 'Water plants');
              await tester.pumpAndSettle();
              expect(
                find.textContaining('Completed 2026-10-26'),
                findsOneWidget,
              );
              await capture('search');
              // Shared picker is the exact production Tasks/Food component, not
              // a second product implementation or Flutter SDK fork.
              await tester.pumpWidget(const SizedBox());
              final controller = TextEditingController(text: '2028-02-29');
              await tester.pumpWidget(
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    brightness: theme == 'dark'
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                  home: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(24),
                      child: CivilDateInput(
                        controller: controller,
                        label: 'Expiration',
                      ),
                    ),
                  ),
                ),
              );
              await pixels.tap(tester, find.byTooltip('Choose Expiration'));
              await tester.pumpAndSettle();
              await pixels.tap(tester, find.text('Month / year'));
              await tester.pumpAndSettle();
              expect(find.byType(Dialog), findsOneWidget);
              expect(find.byType(CalendarDatePicker), findsNothing);
              await capture('month-grid');
              await pixels.tap(tester, find.text('2028'));
              await tester.pumpAndSettle();
              expect(find.byType(YearPicker), findsOneWidget);
              await capture('year-grid');
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(find.byType(CalendarDatePicker), findsOneWidget);
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(find.byType(CivilDatePickerDialog), findsNothing);
              expect(controller.text, '2028-02-29');
              await tester.pumpWidget(const SizedBox());
              controller.dispose();
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox());
              await tester.runAsync(() => root.delete(recursive: true));
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              tester.platformDispatcher.clearTextScaleFactorTestValue();
            }
          },
        );
      }
    }
  }
}
