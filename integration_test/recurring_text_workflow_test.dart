import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerRecurringTextWorkflowTests();
}

void registerRecurringTextWorkflowTests() {
  testWidgets(
    'native recurring completion creates one editable inherited successor with receipt Undo',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'recurring-text-native-',
      );
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      // No library override: fixture and app both load the production bundle.
      final peer = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/peer',
      );
      final user = const Uuid().v4(), parent = const Uuid().v4();
      final child = const Uuid().v5(parent, 'successor');
      try {
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        await peer.createNativeFixtureTask(parent, {
          'title': 'AB',
          'description': 'AB notes',
          'assignee': user,
          'schedule': {
            'dueDate': '2026-10-01',
            'recurrence': 'every week when done',
          },
        });
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (onChanged) => ViewTimeSource(
              onChanged: onChanged,
              loadZone: () async => 'UTC',
              now: () => DateTime.utc(2026, 10, 2, 12),
            ),
          ),
        );
        final parentCheck = find.descendant(
          of: find.byKey(ValueKey('task-row-$parent')),
          matching: find.byType(Checkbox),
        );
        await flows.waitForUi(tester, () => parentCheck.evaluate().isNotEmpty);
        await captureNativeFixtureUi(
          tester,
          'recurring-native-before-completion',
        );
        await tester.tap(parentCheck);
        await flows.waitForUi(
          tester,
          () => find.byKey(ValueKey('task-row-$child')).evaluate().isNotEmpty,
        );
        await peer.refresh();
        expect(peer.rows.where((row) => row['id'] == child), hasLength(1));
        expect(
          peer.rows.singleWhere((row) => row['id'] == parent)['completed'],
          isTrue,
        );
        final inherited = peer.rows.singleWhere((row) => row['id'] == child);
        expect(inherited['title'], 'AB');
        expect(inherited['description'], 'AB notes');
        final completions = peer.db.select(
          "SELECT raw FROM events WHERE json_extract(raw,'\$.type')='task.completedWithText'",
        );
        expect(completions, hasLength(1));
        final completion =
            jsonDecode(completions.single['raw'] as String) as Map;
        expect((completion['data'] as Map)['successor']['id'], child);
        final parentFields = peer.db.select(
          'SELECT field,context FROM text_fields WHERE entity=?',
          [parent],
        );
        final childFields = peer.db.select(
          'SELECT field,context FROM text_fields WHERE entity=?',
          [child],
        );
        expect(childFields, hasLength(2));
        for (final field in ['title', 'description']) {
          expect(
            childFields.singleWhere((row) => row['field'] == field)['context'],
            isNot(
              parentFields.singleWhere(
                (row) => row['field'] == field,
              )['context'],
            ),
          );
        }
        await flows.selectTask(tester, child, control: false);
        final title = find.byKey(const ValueKey('title'));
        expect(tester.widget<TextField>(title).enabled, isTrue);
        expect(tester.widget<TextField>(title).controller!.text, 'AB');
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('description')))
              .controller!
              .text,
          'AB notes',
        );
        await tester.enterText(title, 'AXB');
        await captureNativeFixtureUi(
          tester,
          'recurring-native-successor-private-edit',
        );
        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await flows.waitForUi(
          tester,
          () =>
              find.text('Save changes').evaluate().isEmpty &&
              find
                  .descendant(
                    of: find.byKey(ValueKey('task-row-$child')),
                    matching: find.text('AXB'),
                  )
                  .evaluate()
                  .isNotEmpty,
        );
        await peer.refresh();
        expect(
          peer.rows.singleWhere((row) => row['id'] == child)['title'],
          'AXB',
        );
        expect(
          peer.db.select(
            "SELECT id FROM events WHERE entity=? AND json_extract(raw,'\$.type')='task.textEdited'",
            [child],
          ),
          hasLength(1),
        );
        final undo = find.byKey(const ValueKey('undo-task-action'));
        await tester.ensureVisible(undo);
        await tester.tap(undo);
        await flows.waitForUi(
          tester,
          () => find.text('AXB').evaluate().isEmpty,
        );
        await peer.refresh();
        expect(
          peer.rows.singleWhere((row) => row['id'] == child)['title'],
          'AB',
        );
        expect(
          peer.rows.singleWhere((row) => row['id'] == child)['description'],
          'AB notes',
        );
        expect(
          peer.rows.singleWhere((row) => row['id'] == parent)['completed'],
          isTrue,
        );
        expect(peer.rows.where((row) => row['id'] == child), hasLength(1));
        expect(
          peer.db.select(
            "SELECT id FROM events WHERE entity=? AND json_extract(raw,'\$.type')='task.textEditUndone'",
            [child],
          ),
          hasLength(1),
        );
        await captureNativeFixtureUi(
          tester,
          'recurring-native-successor-after-undo',
        );
        final capture = await peer.captureTaskText(child);
        expect(capture.fields['title']!.document.read().text, 'AB');
        expect(capture.fields['description']!.document.read().text, 'AB notes');
        peer.releaseTextCapture(capture);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await peer.close();
        await root.delete(recursive: true);
      }
    },
  );
}
