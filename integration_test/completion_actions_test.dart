import 'profile_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

/// A bounded common-history read failure must stop both modules while the
/// saved recurrence and its Undo remain intact.
class _HeldFoodReadFolder implements LogFolder, BoundedLogFolder {
  _HeldFoodReadFolder(this.inner);
  final LocalLogFolder inner;
  String? failedTaskFile;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => readBounded(name, 32 * 1024 * 1024);

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (name == failedTaskFile) {
      throw FileSystemException(
        'Synthetic common-history provider read failure before reopening. '
        'The saved completion and recurrence remain unchanged while this '
        'long diagnostic is inspected with Tab, arrows and Page Down. '
        'Restore access to the exact current history before retrying admission. '
        'No other module may write around this failure. '
        'The prior completed task, successor and Undo are preserved.',
        name,
      );
    }
    return inner.readBounded(name, maximumBytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      inner.append(name, bytes);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCompletionActionTests();
}

void registerCompletionActionTests() {
  testWidgets(
    'historical v3 recurrence compatibility: checked completion, failed reopen and Undo',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('completion-native-');
      final folder = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final transport = _HeldFoodReadFolder(LocalLogFolder(folder.path));
      final writer = await openNativeFixtureStore(
        LocalLogFolder(folder.path),
        '${root.path}/writer',
      );
      final user = const Uuid().v4(),
          plain = const Uuid().v4(),
          repeat = const Uuid().v4();
      try {
        await writer.command(user, 'user.created', {'name': 'Alex Example'});
        for (final id in [plain, repeat]) {
          await (id == repeat
              ? writer.createHistoricalRecurrenceFixtureTask
              : writer.createNativeFixtureTask)(id, {
            'title': id == plain ? 'Buy envelopes' : 'Water plants',
            'description': '',
            'assignee': user,
            'schedule': {
              'dueDate': '2026-10-01',
              if (id == repeat) 'recurrence': 'every week when done',
            },
          });
        }
        await writer.complete(
          plain,
          localZoneId: 'UTC',
          completionInstant: DateTime.utc(2026, 10, 2),
        );
        await seedNativeProfile(profile.path, {
          'folder': folder.path,
          'user': user,
          'appearance': 'dark',
        });
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            folderFactory: (_) => transport,
            timeSourceFactory: (onChanged) => ViewTimeSource(
              onChanged: onChanged,
              loadZone: () async => 'UTC',
              now: () => DateTime.utc(2026, 10, 2, 12),
            ),
          ),
        );
        Finder check(String id) => find.descendant(
          of: find.byKey(ValueKey('task-row-$id')),
          matching: find.byType(Checkbox),
        );
        Finder vector(String id) => find.descendant(
          of: find.byKey(ValueKey('task-row-$id')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.size == const Size(18, 26),
          ),
        );
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        await captureNativeFixtureUi(tester, 'completion-warmup-not-evidence');
        expect(vector(repeat), findsOneWidget);
        await tester.tap(check(repeat));
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        await flows.filterChoice(tester, 'Completed');
        for (final id in [plain, repeat]) {
          expect(tester.widget<Checkbox>(check(id)).value, isTrue);
          expect(tester.widget<Checkbox>(check(id)).side, isNull);
          expect(tester.getSize(check(id)), const Size(48, 48));
          expect(vector(id), findsNothing);
        }
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();
        final canonical = {
          await for (final file in folder.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        };
        final manifest = File('${folder.path}/tandemlog-space.json');
        final saved = await manifest.rename(
          '${root.path}/manifest-backup.json',
        );
        await tester.tap(check(repeat));
        await flows.waitForUi(
          tester,
          () => find.text('Workspace requires recovery').evaluate().isNotEmpty,
        );
        final dynamic host = tester.state(find.byType(TasksPage));
        expect(host.sharedSafetyError, isNotNull);
        expect(check(repeat).hitTestable(), findsNothing);
        expect(find.text('Task reopened; next occurrence kept.'), findsNothing);
        expect(
          {
            await for (final file in folder.list())
              if (file is File)
                file.path: base64Encode(await file.readAsBytes()),
          },
          {
            for (final entry in canonical.entries)
              if (entry.key != manifest.path) entry.key: entry.value,
          },
        );
        await saved.rename(manifest.path);
        await tester.tap(find.byKey(const ValueKey('retry-shared-read')));
        await flows.waitForUi(tester, () => host.sharedSafetyError == null);
        expect({
          await for (final file in folder.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        }, canonical);
        expect(tester.widget<Checkbox>(check(repeat)).value, isTrue);

        // The same common failure blocks both modules. Inspect the shared
        // diagnostic with real keyboard traversal before admission-only Retry.
        final failedTaskFile = '${writer.writer}.applog';
        transport.failedTaskFile = failedTaskFile;
        await tester.tap(check(repeat));
        await flows.waitForUi(
          tester,
          () => find.textContaining(failedTaskFile).evaluate().isNotEmpty,
        );
        expect(find.text('Task reopened; next occurrence kept.'), findsNothing);
        final errorScroll = find.byKey(
          const ValueKey('shared-recovery-error-scroll'),
        );
        expect(
          tester.getSize(errorScroll).height,
          lessThan(tester.view.physicalSize.height),
        );
        final errorText = find.descendant(
          of: find.byKey(const ValueKey('shared-recovery-error-details')),
          matching: find.byType(Text),
        );
        expect(tester.widget<Text>(errorText).data, contains(failedTaskFile));
        final scrollState = tester.state<ScrollableState>(
          find.descendant(of: errorScroll, matching: find.byType(Scrollable)),
        );
        expect(scrollState.position.maxScrollExtent, greaterThan(0));
        // Traverse real controls; no requestFocus shortcut for error details.
        bool detailsFocused() =>
            Focus.of(tester.element(errorText)).hasPrimaryFocus;
        for (var step = 0; step < 30 && !detailsFocused(); step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(
          detailsFocused(),
          isTrue,
          reason: 'Error details reachable by Tab',
        );
        scrollState.position.jumpTo(0);
        await tester.pumpAndSettle();
        await captureNativeFixtureUi(tester, 'completion-failed-reopen');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, greaterThan(0));
        expect(detailsFocused(), isTrue);
        await captureNativeFixtureUi(tester, 'completion-error-scrolled');
        for (
          var page = 0;
          page < 20 &&
              scrollState.position.pixels <
                  scrollState.position.maxScrollExtent;
          page++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
          await tester.pumpAndSettle();
        }
        expect(
          scrollState.position.pixels,
          scrollState.position.maxScrollExtent,
        );
        expect(detailsFocused(), isTrue);
        await captureNativeFixtureUi(tester, 'completion-error-end');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          scrollState.position.pixels,
          lessThan(scrollState.position.maxScrollExtent),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(
          detailsFocused(),
          isFalse,
          reason: 'Shift+Tab leaves error details',
        );
        transport.failedTaskFile = null;
        await flows.recoverSharedReadForTest(tester);
        expect(host.sharedSafetyError, isNull);
        await flows.waitForUi(
          tester,
          () => find.textContaining(failedTaskFile).evaluate().isEmpty,
        );
        expect({
          await for (final file in folder.list())
            if (file is File) file.path: base64Encode(await file.readAsBytes()),
        }, canonical);
        expect(tester.widget<Checkbox>(check(repeat)).value, isTrue);
        await tester.tap(check(repeat));
        await flows.waitForUi(
          tester,
          () => find
              .text('Task reopened; next occurrence kept.')
              .evaluate()
              .isNotEmpty,
        );
        await flows.filterChoice(tester, 'Open');
        expect(tester.widget<Checkbox>(check(repeat)).value, isFalse);
        expect(vector(repeat), findsOneWidget);
        await writer.refresh();
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 3);
        // Checkbox Reopen retains the successor. Undo reopening restores
        // completion; true Undo completion retracts its untouched successor.
        final undo = find.byKey(const ValueKey('undo-task-action'));
        await tester.tap(undo);
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        await tester.tap(undo);
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        await writer.refresh();
        expect(
          writer.rows.firstWhere((r) => r['id'] == repeat)['completed'],
          false,
        );
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 2);
        expect(
          find.textContaining('Untouched next occurrence retracted.'),
          findsOneWidget,
        );
        await tester.tap(check(repeat));
        await flows.waitForUi(tester, () => check(repeat).evaluate().isEmpty);
        final next = const Uuid().v5(repeat, 'successor');
        // The legacy creation is retained; the initialized successor is edited
        // through its captured native field rather than an uncovered scalar edit.
        await writer.editNativeFixtureTask(next, {
          'title': 'Water balcony plants',
        });
        await flows.waitForUi(
          tester,
          () => find.text('Water balcony plants').evaluate().isNotEmpty,
        );
        await tester.tap(undo);
        await flows.waitForUi(
          tester,
          () => check(repeat).evaluate().isNotEmpty,
        );
        expect(
          find.textContaining(
            'Next occurrence kept to preserve other changes.',
          ),
          findsOneWidget,
        );
        expect(find.text('Water balcony plants'), findsOneWidget);
        await writer.refresh();
        expect(writer.rows.where((r) => r['kind'] == 'task').length, 3);
        await captureNativeFixtureUi(tester, 'completion-final');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await writer.close();
        await root.delete(recursive: true);
      }
    },
  );
}
