import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'section_navigation_host_test.dart' as host;

class _CountingFolder extends host.FaultingFolder {
  _CountingFolder(super.delegate);
  int appends = 0;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    await super.append(name, bytes);
  }
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final editing in [false, true]) {
    testWidgets(
      'checklist ${editing ? "edit" : "create"} Save recovers before preparation without losing the draft',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final data = (await tester.runAsync(() => host.fixture()))!;
        final folder = _CountingFolder(data.folder);
        host.HostResources? resources;
        final bad = File(
          '${data.folder.location}/ebdaae21-9ed4-4718-80b3-ae826bf30a72.applog',
        );
        try {
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: data.profile,
              folderFactory: (_) => folder,
              textEngineFactory: host.createHostTextEngine,
              timeSourceFactory: host.createHostTimeSource,
            ),
          );
          await host.ready(
            tester,
            () => find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          resources = host.hostResources(tester);
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          final parent =
              (state.rows as Iterable).singleWhere(
                    (r) => r['kind'] == 'task',
                  )['id']
                  as String;
          await tester.tap(find.byKey(ValueKey('task-menu-$parent')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add checklist'));
          await host.ready(
            tester,
            () => find
                .byKey(const ValueKey('checklist-add'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.tap(find.byKey(const ValueKey('checklist-add')));
          await host.ready(
            tester,
            () => find.byType(ChecklistItemEditor).evaluate().isNotEmpty,
          );
          if (editing) {
            await tester.enterText(
              find.byKey(const ValueKey('checklist-item-title')),
              'Earlier item',
            );
            await tester.tap(find.byKey(const ValueKey('checklist-item-save')));
            await host.ready(
              tester,
              () => find.byType(ChecklistItemEditor).evaluate().isEmpty,
            );
            await tester.tap(find.text('Earlier item'));
            await host.ready(
              tester,
              () => find.byType(ChecklistItemEditor).evaluate().isNotEmpty,
            );
          }
          await tester.enterText(
            find.byKey(const ValueKey('checklist-item-title')),
            'Recovered modal item',
          );
          await tester.enterText(
            find.byKey(const ValueKey('checklist-item-notes')),
            'Retained preappend notes',
          );
          final own = '${state.store.writer}.applog';
          final before = (await tester.runAsync(() => data.folder.read(own)))!;
          final canonicalBefore = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          final appendBefore = folder.appends;
          await tester.runAsync(
            () => bad.writeAsString('{"v":5}\n', flush: true),
          );
          state.importer.request();
          // Observe the same background common fence as native Android while the modal remains open.
          await host.ready(tester, () => state.sharedSafetyError != null);
          for (var attempt = 0; attempt < 2; attempt++) {
            await tester.tap(find.byKey(const ValueKey('checklist-item-save')));
            await host.ready(
              tester,
              () => !tester
                  .state<ChecklistItemEditorState>(
                    find.byType(ChecklistItemEditor),
                  )
                  .closeBusy,
            );
            expect(state.sharedSafetyError, isNotNull);
            expect(folder.appends, appendBefore);
            expect(
              (await tester.runAsync(() => data.folder.read(own)))!,
              before,
            );
            final editor = tester.widget<ChecklistItemEditor>(
              find.byType(ChecklistItemEditor),
            );
            expect(editor.hasPendingReceipt?.call(), isFalse);
            expect(editor.textSession?.hasPendingReceipt ?? false, isFalse);
            expect(
              find.byKey(const ValueKey('retry-shared-read')).hitTestable(),
              findsNothing,
            );
            expect(
              tester
                  .widget<TextButton>(
                    find.byKey(const ValueKey('checklist-item-cancel')),
                  )
                  .onPressed,
              isNotNull,
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('checklist-item-title')),
                  )
                  .controller!
                  .text,
              'Recovered modal item',
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('checklist-item-notes')),
                  )
                  .controller!
                  .text,
              'Retained preappend notes',
            );
          }
          await tester.runAsync(bad.delete);
          await tester.tap(find.byKey(const ValueKey('checklist-item-save')));
          await host.ready(
            tester,
            () => find.byType(ChecklistItemEditor).evaluate().isEmpty,
          );
          expect(state.sharedSafetyError, isNull);
          final items = (state.store as TaskStore).checklistItems(parent);
          expect(items, hasLength(1));
          expect(items.single['title'], 'Recovered modal item');
          expect(items.single['description'], 'Retained preappend notes');
          expect(folder.appends, appendBefore + 1);
          final after = (await tester.runAsync(() => data.folder.read(own)))!;
          expect(after.take(before.length).toList(), before);
          final suffix = after.sublist(before.length);
          expect(utf8.decode(suffix).split('\n'), hasLength(2));
          expect(suffix.last, 10);
          expect((jsonDecode(utf8.decode(suffix)) as Map)['v'], 5);
          final canonicalAfter = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          expect(canonicalAfter.keys.toSet(), canonicalBefore.keys.toSet());
          for (final name in canonicalBefore.keys.where(
            (name) => name != own,
          )) {
            expect(canonicalAfter[name], canonicalBefore[name]);
          }
          expect(tester.takeException(), isNull);
        } finally {
          if (await tester.runAsync(bad.exists) == true) {
            await tester.runAsync(bad.delete);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          if (resources != null) {
            await host.waitForHostShutdown(tester, resources);
          }
          await tester.runAsync(() => data.root.delete(recursive: true));
        }
      },
    );
  }
}
