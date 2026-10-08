import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerBulkApplySemanticsTests();
}

void registerBulkApplySemanticsTests() {
  for (final variant in const [
    (name: 'desktop-dark', width: 1200.0, scale: 1.0, dark: true),
    (name: 'narrow-light-200', width: 390.0, scale: 2.0, dark: false),
  ]) {
    testWidgets(
      'native bulk named apply persists only Due time ${variant.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final root = await Directory.systemTemp.createTemp('bulk-apply-named-');
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
            'schedule': {
              'dueDate': index == 0 ? '2026-10-02' : '2026-10-03',
              'dueTime': index == 0 ? '12:30' : '13:45',
              'recurrence': 'every week when done',
              'timeZone': 'UTC',
            },
          });
        }
        await File(
          '${profile.path}/settings.json',
        ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(variant.width, 850);
          tester.platformDispatcher.textScaleFactorTestValue = variant.scale;
          tester.platformDispatcher.platformBrightnessTestValue = variant.dark
              ? Brightness.dark
              : Brightness.light;
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: profile.path,
              timeSourceFactory: (changed) => ViewTimeSource(
                onChanged: changed,
                now: () => DateTime.utc(2026, 10, 4, 12),
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
          expect(find.byType(BulkTaskEditor), findsOneWidget);
          final dueTime = find.byWidgetPredicate(
            (widget) =>
                widget is Checkbox && widget.semanticLabel == 'Apply Due time',
          );
          expect(dueTime, findsOneWidget);
          await tester.ensureVisible(dueTime);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(dueTime).getSemanticsData().label,
            'Apply Due time',
          );
          await captureNativeFixtureUi(
            tester,
            'bulk-${variant.name}-date-controls',
          );
          final node = tester.getSemantics(dueTime);
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isTrue);
          expect(
            tester
                .widgetList<Checkbox>(
                  find.descendant(
                    of: find.byType(BulkTaskEditor),
                    matching: find.byType(Checkbox),
                  ),
                )
                .where((checkbox) => checkbox.value == true)
                .map((checkbox) => checkbox.semanticLabel),
            ['Apply Due time'],
          );
          final paint = find
              .descendant(of: dueTime, matching: find.byType(CustomPaint))
              .first;
          Focus.of(tester.element(paint)).requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isFalse);
          await tester.tap(dueTime);
          await tester.pumpAndSettle();
          expect(tester.widget<Checkbox>(dueTime).value, isTrue);
          await tester.ensureVisible(find.byKey(const ValueKey('addTags')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('addTags')),
            'reviewed',
          );
          final assignee = find.byWidgetPredicate(
            (widget) =>
                widget is Checkbox && widget.semanticLabel == 'Apply Assignee',
          );
          await tester.ensureVisible(assignee);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(assignee).getSemanticsData().label,
            'Apply Assignee',
          );
          expect(tester.widget<Checkbox>(assignee).value, isFalse);
          await captureNativeFixtureUi(
            tester,
            'bulk-${variant.name}-tags-assignee',
          );
          await tester.ensureVisible(find.text('Save changes'));
          await tester.tap(find.text('Save changes'));
          await flows.waitForUi(
            tester,
            () => find.byType(BulkTaskEditor).evaluate().isEmpty,
          );
          await peer.refresh();
          for (var index = 0; index < ids.length; index++) {
            final row = peer.rows.singleWhere((row) => row['id'] == ids[index]);
            expect(row['schedule'], {
              'dueDate': index == 0 ? '2026-10-02' : '2026-10-03',
              'recurrence': 'every week when done',
              'timeZone': 'UTC',
            });
            expect(row['assignee'], user);
            expect(row['title'], 'Bulk fixture ${index + 1}');
            expect(row['tags'], ['reviewed']);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
          await peer.close();
          // Retain every synthetic fixture for diagnosis; never touch user data.
          semantics.dispose();
        }
      },
    );
  }
}
