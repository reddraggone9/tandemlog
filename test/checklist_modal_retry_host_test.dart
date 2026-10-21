import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'section_navigation_host_test.dart' as host;

class _ChecklistSaveFolder extends host.FaultingFolder {
  _ChecklistSaveFolder(super.delegate);
  String? fault;
  final attempts = <List<int>>[];
  @override
  Future<void> append(String name, Uint8List bytes) async {
    attempts.add(List<int>.of(bytes));
    final current = fault;
    fault = null;
    if (current == 'before') {
      throw StateError('Synthetic checklist append blocked');
    }
    await super.append(name, bytes);
    if (current == 'after') {
      throw StateError('Synthetic checklist acknowledgement lost');
    }
  }
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  for (final fault in ['before', 'after', 'changed workspace']) {
    testWidgets(
      'checklist modal Retry Save reconciles $fault without new identities',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 850);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final data = (await tester.runAsync(() => host.fixture()))!;
        final folder = _ChecklistSaveFolder(data.folder);
        String? originalManifest;
        host.HostResources? resources;
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
          expect(find.byType(ChecklistItemEditor), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('checklist-item-title')),
            'Exactly one modal item',
          );
          await tester.enterText(
            find.byKey(const ValueKey('checklist-item-notes')),
            'Retained notes',
          );
          final ownName = '${state.store.writer}.applog';
          final before = (await tester.runAsync(
            () => data.folder.read(ownName),
          ))!;
          final attemptsBefore = folder.attempts.length;
          folder.fault = fault == 'after' ? 'after' : 'before';
          await tester.tap(find.byKey(const ValueKey('checklist-item-save')));
          await host.ready(
            tester,
            () => state.sharedSafetyError != null && state.busy == false,
          );
          final attempted = folder.attempts.last;
          expect(folder.attempts.length, attemptsBefore + 1);
          expect(
            find.byKey(const ValueKey('retry-shared-read')).hitTestable(),
            findsNothing,
            reason:
                'The modal owns input; recovery must be reachable through its own Save.',
          );
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('checklist-item-cancel')),
                )
                .onPressed,
            isNull,
          );
          expect(
            find.byKey(const ValueKey('checklist-item-save')).hitTestable(),
            findsOneWidget,
          );
          final callsBeforeRetry = folder.attempts.length;
          if (fault == 'changed workspace') {
            final manifest = File(
              '${data.folder.location}/tandemlog-space.json',
            );
            originalManifest = await tester.runAsync(manifest.readAsString);
            await tester.runAsync(
              () => manifest.writeAsString('{"v":99}', flush: true),
            );
          }
          await tester.tap(find.byKey(const ValueKey('checklist-item-save')));
          if (fault == 'changed workspace') {
            await host.ready(tester, () => state.busy == false);
            expect(find.byType(ChecklistItemEditor), findsOneWidget);
            expect(folder.attempts.length, callsBeforeRetry);
            expect(
              (await tester.runAsync(() => data.folder.read(ownName)))!,
              before,
            );
            expect(state.sharedSafetyError, isNotNull);
          } else {
            await host.ready(
              tester,
              () => find.byType(ChecklistItemEditor).evaluate().isEmpty,
            );
            expect(state.sharedSafetyError, isNull);
            expect(
              (state.store as TaskStore).checklistItems(parent).single['title'],
              'Exactly one modal item',
            );
            expect((await tester.runAsync(() => data.folder.read(ownName)))!, [
              ...before,
              ...attempted,
            ]);
            expect(
              folder.attempts.length,
              callsBeforeRetry + (fault == 'before' ? 1 : 0),
            );
            if (fault == 'before') expect(folder.attempts.last, attempted);
          }
          expect(tester.takeException(), isNull);
        } finally {
          if (originalManifest != null) {
            await tester.runAsync(
              () => File(
                '${data.folder.location}/tandemlog-space.json',
              ).writeAsString(originalManifest!, flush: true),
            );
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
