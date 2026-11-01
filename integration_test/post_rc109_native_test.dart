import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/form_validation.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'profile_fixture.dart';
import 'task_flow_test.dart' show waitForUi;

// F1 in the real GTK window against a real second installation. The host test
// covers its branches; this shows what the user actually sees. When
// TANDEMLOG_COLD_OPEN_SEED is set the workspace stays behind, closed cleanly,
// for tool-driven cold launches of a release bundle.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('F1 draft survives unrelated change, then asks to review', (
    tester,
  ) async {
    final keep = Platform.environment['TANDEMLOG_COLD_OPEN_SEED'];
    final root = keep == null
        ? await Directory.systemTemp.createTemp('post-rc109-native-')
        : await Directory(keep).create(recursive: true);
    final data = await Directory('${root.path}/data').create();
    final profile = '${root.path}/profile';
    final folder = LocalLogFolder(data.path);
    final peer = await openNativeFixtureStore(folder, '${root.path}/peer');
    final user = const Uuid().v4();
    await peer.command(user, 'user.created', {'name': 'Synthetic Alex'});
    final first = const Uuid().v4(),
        second = const Uuid().v4(),
        unrelated = const Uuid().v4();
    for (final (id, title) in [
      (first, 'First selected target'),
      (second, 'Second selected target'),
      (unrelated, 'Unrelated task'),
    ]) {
      await peer.createNativeFixtureTask(id, {
        'title': title,
        'description': '',
        'assignee': user,
        'schedule': {'dueDate': '2026-11-20'},
      });
    }
    await seedNativeProfile(profile, {
      'folder': data.path,
      'user': user,
      'appearance': 'dark',
    });
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    await tester.pumpWidget(TandemlogApp(profilePath: profile));
    await waitForUi(
      tester,
      () => find.text('Second selected target').evaluate().isNotEmpty,
    );
    final host = tester.state(find.byType(TasksPage)) as dynamic;
    Future<void> peerEdits(String id, String due) async {
      await tester.runAsync(() async {
        await peer.command(id, 'task.edited', {
          'schedule': {'dueDate': due},
        });
        await (host.store as TaskStore).refresh();
      });
      host.importer.request();
      await tester.pump();
    }

    await tester.longPress(find.text('First selected target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second selected target'));
    await tester.pumpAndSettle();
    expect(find.text('Edit 2 tasks'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('dueDate')), '2026-12-05');
    await tester.pumpAndSettle();
    await captureNativeFixtureUi(tester, 'f1-1-draft');

    await peerEdits(unrelated, '2026-11-21');
    await waitForUi(
      tester,
      () => host.bulkSnapshot == (host.store as TaskStore).taskSnapshot,
    );
    expect(host.bulkConflict, isFalse);
    expect(find.text('Edit 2 tasks'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('dueDate')))
          .controller!
          .text,
      '2026-12-05',
    );
    await captureNativeFixtureUi(tester, 'f1-2-unrelated-kept-draft');

    await peerEdits(second, '2026-11-22');
    await waitForUi(tester, () => host.bulkConflict == true);
    await tester.pumpAndSettle();
    expect(find.text('Review selection'), findsOneWidget);
    expect(find.text('Edit 2 tasks'), findsNothing);
    expect(
      tester
          .widget<ValidationActionButton>(
            find.byKey(const ValueKey('task-save-action')),
          )
          .enabled,
      isFalse,
    );
    await captureNativeFixtureUi(tester, 'f1-3-target-changed');

    await tester.tap(find.text('Review current selection'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await captureNativeFixtureUi(tester, 'f1-4-review-dialog');

    await tester.tap(find.text('Discard'));
    await waitForUi(
      tester,
      () =>
          host.bulkConflict == false &&
          find.text('Edit 2 tasks').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await captureNativeFixtureUi(tester, 'f1-5-reopened-current');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await peer.close();
      if (keep == null) await root.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
