import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/presentation/checklist_panel.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

class _WorkspacePicker extends FolderActions {
  _WorkspacePicker(this.selection);
  String selection;
  int picks = 0;
  @override
  bool get requiresPicker => false;
  @override
  Future<String?> pick() async {
    picks++;
    return selection;
  }

  @override
  Future<bool> canOpen(String location) async => false;
}

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<Map<String, String>> _canonicalBytes(LogFolder folder) async => {
  for (final file in await folder.list())
    file.name: base64Encode(await folder.read(file.name)),
};

Future<void> _switchWorkspace(
  WidgetTester tester,
  _WorkspacePicker picker,
  String location,
  String parentTitle,
) async {
  picker.selection = location;
  final before = picker.picks;
  await flows.openSettings(tester);
  await _tap(tester, find.text('Use a different folder'));
  await flows.waitForUi(tester, () {
    final state = tester.state(find.byType(TasksPage)) as dynamic;
    return state.store?.folder.location == location &&
        state.busy == false &&
        find.text(parentTitle).evaluate().isNotEmpty;
  });
  expect(picker.picks, before + 1);
  expect(find.text('Settings'), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerInlineChecklistWorkspaceTests();
}

void registerInlineChecklistWorkspaceTests() {
  testWidgets(
    'workspace switch rejects old checklist and menu callbacks with colliding IDs',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'inline-checklist-workspace-',
      );
      final firstDirectory = await Directory('${root.path}/first').create();
      final secondDirectory = await Directory('${root.path}/second').create();
      final profile = await Directory('${root.path}/profile').create();
      final firstFolder = LocalLogFolder(firstDirectory.path);
      final secondFolder = LocalLogFolder(secondDirectory.path);
      final firstPeer = await openNativeFixtureStore(
        firstFolder,
        '${root.path}/first-peer',
      );
      final secondPeer = await openNativeFixtureStore(
        secondFolder,
        '${root.path}/second-peer',
      );
      final user = const Uuid().v4(), parent = const Uuid().v4();
      final item = const Uuid().v4(), anchor = const Uuid().v4();
      final picker = _WorkspacePicker(secondDirectory.path);
      try {
        for (final space in [(firstPeer, 'First'), (secondPeer, 'Second')]) {
          await space.$1.command(user, 'user.created', {
            'name': 'Synthetic workspace user',
          });
          await space.$1.createNativeFixtureTask(parent, {
            'title': '${space.$2} space parent',
            'description': '',
            'assignee': user,
          });
          await space.$1.addChecklistItem(
            parent,
            '${space.$2} space item',
            id: item,
          );
          await space.$1.addChecklistItem(
            parent,
            '${space.$2} space anchor',
            id: anchor,
          );
        }
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': firstDirectory.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderActions: picker),
        );
        await flows.waitForUi(
          tester,
          () => find.text('First space parent').evaluate().isNotEmpty,
        );
        expect(_key('inline-checklist-$parent'), findsNothing);
        await _tap(tester, _key('checklist-disclosure-$parent'));
        final panel = tester.widget<ChecklistPanel>(
          find.descendant(
            of: _key('inline-checklist-$parent'),
            matching: find.byType(ChecklistPanel),
          ),
        );
        final oldOrigin = panel.origin;
        final oldItem = Map<String, dynamic>.from(
          panel.items.singleWhere((row) => row['id'] == item),
        );
        final oldMenu = tester
            .widget<IconButton>(_key('task-menu-$parent'))
            .onPressed!;
        final firstBefore = await _canonicalBytes(firstFolder);
        final secondBefore = await _canonicalBytes(secondFolder);
        expect(panel.items.map((row) => row['id']), [item, anchor]);

        await _switchWorkspace(
          tester,
          picker,
          secondDirectory.path,
          'Second space parent',
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        expect(identical(state.store, oldOrigin), isFalse);
        expect(_key('checklist-disclosure-$parent'), findsOneWidget);
        expect(_key('inline-checklist-$parent'), findsNothing);

        // Each operation would target a real entity if admitted by ID alone.
        // The move is to the end, so it would change the two-item order.
        final staleCallbacks = <(String, Function, List<Object?>)>[
          ('Add', panel.onAdd, []),
          ('Edit', panel.onEdit, [oldItem]),
          ('Toggle', panel.onToggle, [oldItem, true]),
          ('Move', panel.onMove, [oldItem, null]),
          ('Delete', panel.onDelete, [oldItem]),
          ('Row menu', oldMenu, []),
        ];
        for (final stale in staleCallbacks) {
          final failures = <Object>[];
          var finished = false;
          final result = Function.apply(stale.$2, stale.$3);
          if (result is Future) {
            result.then<void>(
              (_) => finished = true,
              onError: (Object error, StackTrace stack) {
                failures.add(error);
                finished = true;
              },
            );
          } else {
            finished = true;
          }
          for (var attempt = 0; attempt < 20 && !finished; attempt++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            finished,
            isTrue,
            reason: '${stale.$1} must return harmlessly',
          );
          expect(
            failures,
            isEmpty,
            reason: '${stale.$1} used a closed workspace',
          );
          expect(tester.takeException(), isNull, reason: stale.$1);
          expect(
            find.byType(ChecklistItemEditor),
            findsNothing,
            reason: stale.$1,
          );
          expect(find.byType(TaskEditor), findsNothing, reason: stale.$1);
          expect(
            find.byType(PopupMenuItem<String>),
            findsNothing,
            reason: stale.$1,
          );
          expect(
            find.text('Delete checklist item?'),
            findsNothing,
            reason: stale.$1,
          );
          expect(find.text('Delete task?'), findsNothing, reason: stale.$1);
          expect(state.error, isNull, reason: stale.$1);
          expect(
            _key('inline-checklist-$parent'),
            findsNothing,
            reason: stale.$1,
          );
          expect(
            await _canonicalBytes(firstFolder),
            firstBefore,
            reason: stale.$1,
          );
          expect(
            await _canonicalBytes(secondFolder),
            secondBefore,
            reason: stale.$1,
          );
        }

        await _switchWorkspace(
          tester,
          picker,
          firstDirectory.path,
          'First space parent',
        );
        expect(_key('inline-checklist-$parent'), findsOneWidget);
        expect(_key('checklist-check-$item'), findsOneWidget);
        final restored = tester.widget<ChecklistPanel>(
          find.byType(ChecklistPanel),
        );
        expect(identical(restored.origin, oldOrigin), isFalse);
        expect(
          restored.items.singleWhere((row) => row['id'] == item)['completed'],
          isFalse,
        );
        expect(restored.items.map((row) => row['id']), [item, anchor]);
        expect(await _canonicalBytes(firstFolder), firstBefore);
        expect(await _canonicalBytes(secondFolder), secondBefore);
        expect(tester.takeException(), isNull);
        expect(state.error, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await firstPeer.close();
        await secondPeer.close();
        // All data is synthetic and confined to this test's temporary root.
        await root.delete(recursive: true);
      }
    },
  );
}
