import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/presentation/sticky_task_group.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerHeaderSelectionTests();
}

void registerHeaderSelectionTests() {
  for (final variant in const [
    (width: 390.0, scale: 1.0, theme: 'light'),
    (width: 320.0, scale: 2.0, theme: 'dark'),
  ]) {
    testWidgets(
      'combined header and stationary selection ${variant.width} x${variant.scale}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('header-selection-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final writer = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/writer',
        );
        final user = const Uuid().v4();
        final ids = List.generate(70, (_) => const Uuid().v4());
        try {
          await writer.command(user, 'user.created', {
            'name': 'Alexandria Example Household',
          });
          for (var i = 0; i < ids.length; i++) {
            await writer.createNativeFixtureTask(ids[i], {
              'title': 'Reference task ${i + 1}',
              'description': '',
              'assignee': user,
              'schedule': {'dueDate': '2026-10-01'},
              'tags': ['reference'],
            });
          }
          await File('${profile.path}/settings.json').writeAsString(
            jsonEncode({
              'folder': folder.path,
              'user': user,
              'appearance': variant.theme,
            }),
          );
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(variant.width, 820);
          tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              folderActions: flows.TestFolders(android: true),
              timeSourceFactory: (changed) => ViewTimeSource(
                onChanged: changed,
                now: () => DateTime.utc(2026, 10, 3, 12),
                loadZone: () async => 'UTC',
              ),
            ),
          );
          await flows.waitForUi(
            tester,
            () => find.text('Reference task 1').evaluate().isNotEmpty,
          );
          Future<Map<String, String>> contents() async => {
            await for (final e in folder.list())
              if (e is File) e.path: base64Encode(await e.readAsBytes()),
          };
          final before = await contents();
          final capture = find.widgetWithText(TextField, 'What needs doing?');
          await tester.enterText(
            capture,
            'First draft\nSecond draft\nThird draft\nFourth draft',
          );
          final controller = tester.widget<TextField>(capture).controller!;
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 12,
          );
          final draft = controller.value;
          // Simulated native window metrics are separate from Android runtime
          // evidence: keyboard opening/closing must retain the entire draft.
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(controller.value, draft);
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(controller.value, draft);
          final viewport = find.byType(CustomScrollView).first;
          final scrollable = find
              .descendant(of: viewport, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          Finder body(int i) => find.byKey(ValueKey('task-body-${ids[i]}'));
          // This is setup for stationary selection, not a fling-speed test.
          // Wrapped titles/metadata change row height at narrow/large-text
          // sizes. Seek the lazy row using the actual viewport and extent,
          // rather than a fixed drag count that can expire before it is built.
          var seekSteps = 0;
          while (body(35).evaluate().isEmpty) {
            expect(
              seekSteps,
              lessThan(ids.length * 8),
              reason: 'Seeking Task 36 exceeded the finite fixture budget.',
            );
            final next = (position.pixels + position.viewportDimension / 2)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
            expect(
              next,
              greaterThan(position.pixels),
              reason: 'Task 36 was not built by the end of the task list.',
            );
            position.jumpTo(next);
            await tester.pumpAndSettle();
            seekSteps++;
          }
          await tester.ensureVisible(body(35));
          await tester.pumpAndSettle();
          expect(body(35), findsOneWidget);
          expect(body(35).hitTestable(), findsOneWidget);
          debugPrint(
            'HEADER_SELECTION_SEEK ${jsonEncode({'width': variant.width, 'text_scale': variant.scale, 'steps': seekSteps, 'viewport_height': position.viewportDimension, 'offset': position.pixels, 'max_extent': position.maxScrollExtent, 'row_height': tester.getSize(body(35)).height})}',
          );
          final rowBefore = tester.getRect(body(35));
          final viewBefore = tester.getRect(viewport);
          final headerBefore = tester.getRect(
            find.byKey(const ValueKey('task-header')),
          );
          final slotBefore = tester.getRect(
            find.byKey(const ValueKey('task-entry-area')),
          );
          final scrollBefore = position.pixels;
          await tester.longPress(body(35));
          await tester.pumpAndSettle();
          expect(tester.getRect(body(35)), rowBefore);
          expect(tester.getRect(viewport), viewBefore);
          expect(
            tester.getRect(find.byKey(const ValueKey('task-header'))),
            headerBefore,
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('task-entry-area'))),
            slotBefore,
          );
          expect(position.pixels, scrollBefore);
          expect(find.byType(TaskEditor), findsNothing);
          expect(controller.value, draft);
          expect(find.text('1 selected'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('task-filter')).hitTestable(),
            findsOneWidget,
          );
          final sticky = find.byType(StickyTaskGroupHeading).first;
          final heading = tester.widget<StickyTaskGroupHeading>(sticky);
          expect(
            tester.getRect(find.byKey(heading.headingKey!)).top,
            closeTo(viewBefore.top, .1),
          );
          // Keyboard movement/range and toggling back to one remain in selection,
          // without opening a modal or stealing the list's space.
          final focus = tester
              .widget<Focus>(
                find
                    .ancestor(
                      of: body(35),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is Focus &&
                            widget.focusNode?.debugLabel == 'Reference task 36',
                      ),
                    )
                    .first,
              )
              .focusNode!;
          focus.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(find.text('2 selected'), findsOneWidget);
          await tester.tap(body(36));
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);
          expect(find.byType(TaskEditor), findsNothing);
          expect(tester.getRect(viewport), viewBefore);
          await tester.tap(body(35));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('compact-selection-actions')),
            findsNothing,
          );
          expect(tester.getRect(body(35)), rowBefore);
          expect(controller.value, draft);
          // Selection survives opening/closing Filter. Changing filters/search
          // still deliberately clears it under the existing behavior.
          await tester.longPress(body(35));
          await tester.pumpAndSettle();
          await flows.openFilters(tester);
          await tester.tap(find.text('Done').last);
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);
          final undoBeforeSearch = tester.getRect(
            find.byKey(const ValueKey('undo-task-action')),
          );
          await tester.tap(find.byKey(const ValueKey('open-search')));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('undo-task-action'))),
            undoBeforeSearch,
          );
          expect(
            find.byKey(const ValueKey('compact-selection-actions')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('task-search')),
            'Reference task 36',
          );
          await tester.pumpAndSettle();
          await tester.longPress(body(35));
          await tester.pumpAndSettle();
          expect(find.text('1 selected'), findsOneWidget);
          final searchingGeometry = tester.getRect(viewport);
          await tester.tap(find.byKey(const ValueKey('clear-selected-tasks')));
          await tester.pumpAndSettle();
          expect(tester.getRect(viewport), searchingGeometry);
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('undo-task-action'))),
            undoBeforeSearch,
          );
          // Breakpoint changes retain the draft; wide selection uses its existing
          // side editor and the top toolbar remains the same height.
          tester.view.physicalSize = const Size(1200, 820);
          await tester.pumpAndSettle();
          position.jumpTo(0);
          await tester.pumpAndSettle();
          final wideHeader = tester.getRect(
            find.byKey(const ValueKey('task-header')),
          );
          await tester.longPress(body(0));
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsOneWidget);
          expect(
            tester.getRect(find.byKey(const ValueKey('task-header'))),
            wideHeader,
          );
          expect(controller.value, draft);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await flows.openSettings(tester);
          expect(find.text('Settings'), findsWidgets);
          await tester.tap(find.text('Done').last);
          await tester.pumpAndSettle();
          expect(await contents(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await writer.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
