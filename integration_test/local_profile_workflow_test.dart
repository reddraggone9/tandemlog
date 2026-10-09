import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:uuid/uuid.dart';
import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

class _Picker extends FolderActions {
  _Picker(this.selection);
  String selection;
  @override
  bool get requiresPicker => false;
  @override
  Future<String?> pick() async => selection;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'shared profile restores failed switch and persists successful switch after restart',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'profile-native-flow-',
      );
      final first = await Directory('${root.path}/first').create(),
          second = await Directory('${root.path}/second').create();
      final private = await Directory('${root.path}/profile').create();
      final user = const Uuid().v4(),
          task = const Uuid().v4(),
          item = const Uuid().v4();
      for (final target in [(first, 'First'), (second, 'Second')]) {
        final seed = await openNativeFixtureStore(
          LocalLogFolder(target.$1.path),
          '${root.path}/${target.$2}-seed',
        );
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createNativeFixtureTask(task, {
          'title': '${target.$2} retained task',
          'description': '',
          'assignee': user,
        });
        await seed.addChecklistItem(task, 'Shared display state', id: item);
        await seed.close();
      }
      await File('${private.path}/settings.json').writeAsString(
        jsonEncode({'folder': first.path, 'user': user, 'appearance': 'dark'}),
      );
      final picker = _Picker(second.path), boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 850);
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: TandemlogApp(
              profilePath: private.path,
              folderActions: picker,
            ),
          ),
        );
        await flows.waitForUi(
          tester,
          () => find.text('First retained task').evaluate().isNotEmpty,
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final origin = state.store, writer = state.settings.writer;
        expect(origin.profileDatabase, isNotNull);
        expect(File('${private.path}/settings.json').existsSync(), isFalse);
        await tester.tap(find.byKey(ValueKey('checklist-disclosure-$task')));
        await tester.pumpAndSettle();
        expect(state.expandedChecklists, {task});
        await tester.tap(find.byKey(ValueKey('checklist-check-$item')));
        await tester.pumpAndSettle();
        await flows.waitForUi(
          tester,
          () => state.busy == false && state.undoHistory.latest != null,
        );
        expect(state.undoHistory.latest, isNotNull);
        final undo = state.undoHistory.latest;
        state.profileDatabase.database.execute(
          "CREATE TRIGGER reject_settings BEFORE UPDATE ON protected_settings BEGIN SELECT RAISE(ABORT,'synthetic preference failure'); END",
        );
        await flows.openSettings(tester);
        await tester.tap(find.text('Use a different folder'));
        await tester.pumpAndSettle();
        await flows.waitForUi(
          tester,
          () => state.busy == false && state.error != null,
        );
        expect(identical(state.store, origin), isTrue);
        expect(identical(state.watchedStore, origin), isTrue);
        expect(state.expandedChecklists, {task});
        expect(identical(state.undoHistory.latest, undo), isTrue);
        expect(state.settings.folder, first.path);
        expect(find.text('First retained task'), findsOneWidget);
        state.profileDatabase.database.execute('DROP TRIGGER reject_settings');
        await flows.openSettings(tester);
        await tester.tap(find.text('Use a different folder'));
        await tester.pumpAndSettle();
        await flows.waitForUi(
          tester,
          () =>
              state.busy == false &&
              state.store?.folder.location == second.path,
        );
        expect(state.undoHistory.latest, isNull);
        expect(state.expandedChecklists, isEmpty);
        expect(state.settings.writer, writer);
        await tester.pumpAndSettle();
        final evidence = Platform.environment['TANDEMLOG_FLOW_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(evidence).create(recursive: true);
          await File(
            '$evidence/profile-switch-linux-dark.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
        final owner = await LocalProfileDatabase.open(private.path);
        final prefs = LocalSettings(owner.root, profileDatabase: owner);
        await prefs.load();
        expect(prefs.folder, second.path);
        expect(prefs.writer, writer);
        await owner.close();
        expect(
          private.listSync().whereType<File>().map(
            (f) => f.uri.pathSegments.last,
          ),
          ['local.sqlite'],
        );
        await tester.pumpWidget(
          TandemlogApp(profilePath: private.path, folderActions: picker),
        );
        await flows.waitForUi(
          tester,
          () => find.text('Second retained task').evaluate().isNotEmpty,
        );
        expect(
          (tester.state(find.byType(TasksPage)) as dynamic).settings.writer,
          writer,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await root.delete(recursive: true);
      }
    },
  );
}
