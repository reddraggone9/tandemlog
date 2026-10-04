import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskPrecisionTests();
}

void registerTaskPrecisionTests() {
  testWidgets(
    'same-day precision sorts, constrains dragging and retains historical title',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('task-precision-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(), ids = <String, String>{};
      await writer.command(user, 'user.created', {'name': 'Alex Example'});
      Future<void> add(String title, Map<String, dynamic> schedule) async {
        final id = ids[title] = const Uuid().v4();
        await writer.command(id, 'task.created', {
          'title': title,
          'description': '',
          'assignee': user,
          'schedule': schedule,
        });
      }

      await add('Date-only first', {'dueDate': '2026-10-04'});
      await add('Late exact time', {
        'dueDate': '2026-10-04',
        'dueTime': '23:59',
      });
      await add('Date-only second', {'dueDate': '2026-10-04'});
      await add('Midnight first', {
        'dueDate': '2026-10-04',
        'dueTime': '00:00',
      });
      await add('Midnight second', {
        'dueDate': '2026-10-04',
        'dueTime': '00:00',
      });
      const historical = 'Historical title\nwith a retained second line';
      await add(historical, {});
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': folder.path, 'user': user}));
      Future<Map<String, String>> logs() async => {
        await for (final file in folder.list())
          if (file is File) file.path: base64Encode(await file.readAsBytes()),
      };
      Finder target(String title) =>
          find.byKey(ValueKey('task-drop-${ids[title]}'));
      Finder handle(String title) => find.descendant(
        of: target(title),
        matching: find.byType(Draggable<String>),
      );
      Future<void> drag(String from, String to, {bool invalid = false}) async {
        final gesture = await tester.startGesture(
          tester.getCenter(handle(from)),
        );
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        final bounds = tester.getRect(target(to));
        await gesture.moveTo(Offset(bounds.center.dx, bounds.bottom - 8));
        await tester.pump();
        if (invalid) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label ==
                      'Cannot reorder here: different group, date or time, or the list changed.',
            ),
            findsOneWidget,
          );
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
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
        await tester.pumpAndSettle();
        void ordered(List<String> titles) {
          for (var i = 1; i < titles.length; i++) {
            expect(
              tester.getRect(target(titles[i - 1])).top,
              lessThan(tester.getRect(target(titles[i])).top),
            );
          }
        }

        ordered([
          'Midnight first',
          'Midnight second',
          'Late exact time',
          'Date-only first',
          'Date-only second',
        ]);
        final beforeInvalid = await logs();
        await drag('Midnight second', 'Date-only first', invalid: true);
        expect(await logs(), beforeInvalid);
        await drag('Date-only first', 'Date-only second');
        ordered([
          'Midnight first',
          'Midnight second',
          'Late exact time',
          'Date-only second',
          'Date-only first',
        ]);
        await writer.refresh();
        final beforeEditor = await logs();
        await flows.selectTask(tester, ids[historical]!, control: false);
        final title = find.byKey(const ValueKey('title'));
        expect(tester.widget<TextField>(title).controller!.text, historical);
        final notes = find.byKey(const ValueKey('description'));
        await tester.ensureVisible(notes);
        await tester.enterText(
          notes,
          'Edited notes keep historical title semantics.',
        );
        await tester.tap(find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () => find.text('Save changes').evaluate().isEmpty,
        );
        await writer.refresh();
        final retained = writer.rows.singleWhere(
          (row) => row['id'] == ids[historical],
        );
        expect(retained['title'], historical);
        expect(
          retained['description'],
          'Edited notes keep historical title semantics.',
        );
        for (final old in beforeEditor.entries.where(
          (entry) => entry.key.endsWith('.jsonl'),
        )) {
          expect(
            base64Encode(
              (await File(
                old.key,
              ).readAsBytes()).take(base64Decode(old.value).length).toList(),
            ),
            old.value,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await writer.close();
        await root.delete(recursive: true);
      }
    },
  );
}
