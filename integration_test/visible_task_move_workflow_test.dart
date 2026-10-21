import 'profile_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' show waitForUi, selectTask, clearSelection;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerVisibleTaskMoveWorkflowTests();
}

void registerVisibleTaskMoveWorkflowTests() {
  for (final multiple in [false, true]) {
    testWidgets(
      'visible no-op preserves canonical bytes and prior Undo block:$multiple',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'visible-noop-synthetic-',
        );
        final data = await Directory('${root.path}/data').create();
        final profile = await Directory('${root.path}/profile').create();
        final peer = await openNativeFixtureStore(
          LocalLogFolder(data.path),
          '${root.path}/peer',
        );
        final user = const Uuid().v4(), other = const Uuid().v4();
        final a = const Uuid().v4(),
            s1 = const Uuid().v4(),
            s2 = const Uuid().v4(),
            b = const Uuid().v4();
        final h1 = const Uuid().v4(),
            h2 = const Uuid().v4(),
            h3 = const Uuid().v4();
        final initial = [a, h1, s1, if (multiple) s2, h2, b, h3];
        try {
          await peer.command(user, 'user.created', {
            'name': 'Synthetic visible household',
          });
          await peer.command(other, 'user.created', {
            'name': 'Synthetic hidden household',
          });
          for (final id in initial) {
            await peer.createNativeFixtureTask(id, {
              'title': 'Synthetic row ${initial.indexOf(id)}',
              'description': '',
              'assignee': [h1, h2, h3].contains(id) ? other : user,
              'schedule': {'dueDate': '2026-10-15'},
            });
          }
          for (final id in initial) {
            await peer.moveBefore(id, null);
          }
          await seedNativeProfile(profile.path, {
            'folder': data.path,
            'user': user,
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 900);
          await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
          Finder row(String id) => find.byKey(ValueKey('task-drop-$id'));
          await waitForUi(tester, () => row(b).evaluate().isNotEmpty);
          await tester.pumpAndSettle();
          Future<List<String>> order() async {
            await peer.refresh();
            return peer.rows
                .where((r) => r['kind'] == 'task')
                .map((r) => r['id'] as String)
                .toList();
          }

          Future<Map<String, String>> bytes() async => {
            await for (final f in data.list())
              if (f is File) f.path: base64Encode(await f.readAsBytes()),
          };
          Future<void> drag(String from, String target, bool after) async {
            final handle = find.descendant(
              of: row(from),
              matching: find.byType(Draggable<String>),
            );
            final gesture = await tester.startGesture(tester.getCenter(handle));
            await gesture.moveBy(const Offset(-20, 0));
            await tester.pump();
            final rect = tester.getRect(row(target));
            await gesture.moveTo(
              Offset(rect.right - 48, after ? rect.bottom - 4 : rect.top + 4),
            );
            await tester.pump();
            await gesture.up();
            await tester.pumpAndSettle();
          }

          // A real move seeds Undo. No-op drops must not replace that action.
          await drag(b, a, false);
          expect(await order(), [b, a, h1, s1, if (multiple) s2, h2, h3]);
          final before = await bytes();
          if (multiple) {
            // Reverse selection order must not reverse the moving block.
            await selectTask(tester, s2);
            await selectTask(tester, s1);
            await tester.pumpAndSettle();
          }
          // Both halves of the gap between a and the final moving block preserve
          // visible order while old global anchors would relocate hidden rows.
          await drag(s1, a, true);
          expect(await bytes(), before);
          expect(await order(), [b, a, h1, s1, if (multiple) s2, h2, h3]);
          if (multiple) {
            await tester.tap(clearSelection());
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const ValueKey('undo-task-action')));
          await tester.pumpAndSettle();
          expect(await order(), initial);
          if (multiple) {
            await selectTask(tester, s2);
            await selectTask(tester, s1);
          }
          // At the visible bucket end, insert directly after b and before h3.
          // This also exercises actual multi-command writes and block Undo.
          await drag(s1, b, true);
          expect(await order(), [a, h1, h2, b, s1, if (multiple) s2, h3]);
          if (multiple) {
            await tester.tap(clearSelection());
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const ValueKey('undo-task-action')));
          await tester.pumpAndSettle();
          expect(await order(), initial);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await peer.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await root.delete(recursive: true);
        }
      },
    );
  }
  testWidgets(
    'serialized drag rejects clock-only change to inferred next visible anchor',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'visible-anchor-clock-synthetic-',
      );
      final data = await Directory('${root.path}/data').create();
      final profile = await Directory('${root.path}/profile').create();
      final peer = await openNativeFixtureStore(
        LocalLogFolder(data.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4();
      final ids = List.generate(4, (_) => const Uuid().v4());
      var now = DateTime.utc(2026, 10, 15, 23, 59);
      try {
        await peer.command(user, 'user.created', {
          'name': 'Synthetic clock household',
        });
        for (var i = 0; i < ids.length; i++) {
          await peer.createNativeFixtureTask(ids[i], {
            'title': 'Synthetic clock row $i',
            'description': '',
            'assignee': user,
            'schedule': i == 2
                ? {'dueDate': '2099-01-01', 'dueMaxDays': 1}
                : {'dueDate': '2026-10-16'},
          });
        }
        for (final id in ids) {
          await peer.moveBefore(id, null);
        }
        await seedNativeProfile(profile.path, {
          'folder': data.path,
          'user': user,
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (onChanged) => ViewTimeSource(
              onChanged: onChanged,
              loadZone: () async => 'UTC',
              now: () => now,
            ),
          ),
        );
        Finder row(int i) => find.byKey(ValueKey('task-drop-${ids[i]}'));
        await waitForUi(tester, () => row(3).evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        final before = {
          await for (final f in data.list())
            if (f is File) f.path: base64Encode(await f.readAsBytes()),
        };
        final handle = find.descendant(
          of: row(0),
          matching: find.byType(Draggable<String>),
        );
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        final rect = tester.getRect(row(1));
        await gesture.moveTo(Offset(rect.right - 48, rect.bottom - 4));
        await tester.pump();
        // No timer notification: source and pointer target remain in their fixed
        // bucket, but inferred next anchor moves to tomorrow's relative bound.
        now = DateTime.utc(2026, 10, 16, 0, 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect({
          await for (final f in data.list())
            if (f is File) f.path: base64Encode(await f.readAsBytes()),
        }, before);
        expect(
          find.text('The task list changed. Try moving the task again.'),
          findsOneWidget,
        );
        await peer.refresh();
        expect(
          peer.rows
              .where((r) => r['kind'] == 'task')
              .map((r) => r['id'])
              .toList(),
          ids,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await peer.close();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await root.delete(recursive: true);
      }
    },
  );
}
