import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';

class _ControlledCompletionFolder implements LogFolder, BoundedLogFolder {
  _ControlledCompletionFolder(this.inner);
  final LocalLogFolder inner;
  Completer<void>? appendStarted, releaseAppend;
  bool failAppend = false;
  int appends = 0;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final file in await inner.list()) LogFileInfo(file.name, ''),
  ];
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      inner.readBounded(name, maximumBytes);
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appends++;
    appendStarted?.complete();
    await releaseAppend?.future;
    if (failAppend) throw StateError('Synthetic completion append failure.');
    await inner.append(name, bytes);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Expected completion UI state was not ready.',
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCompletionConfirmationProgressTests();
}

void registerCompletionConfirmationProgressTests() {
  for (final outcome in ['cancel', 'barrier', 'escape', 'confirm', 'failure']) {
    testWidgets('completion consent progress and admission: $outcome', (
      tester,
    ) async {
      final root = await Directory.systemTemp.createTemp('completion-consent-');
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final inner = LocalLogFolder(shared.path);
      final folder = _ControlledCompletionFolder(inner);
      final peer = await openNativeFixtureStore(inner, '${root.path}/peer');
      final user = const Uuid().v4(), parent = const Uuid().v4();
      try {
        await peer.command(user, 'user.created', {'name': 'Alex Example'});
        await peer.createNativeFixtureTask(parent, {
          'title': 'Synthetic completion task',
          'description': '',
          'assignee': user,
        });
        for (var item = 1; item <= 6; item++) {
          await peer.addChecklistItem(parent, 'Unchecked item $item');
        }
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': shared.path,
            'user': user,
            'appearance': 'dark',
          }),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            folderFactory: (_) => folder,
            timeSourceFactory: (changed) => ViewTimeSource(
              onChanged: changed,
              loadZone: () async => 'UTC',
              now: () => DateTime.utc(2026, 10, 8, 12),
            ),
          ),
        );
        Finder checkbox() => find.descendant(
          of: find.byKey(ValueKey('task-row-$parent')),
          matching: find.byType(Checkbox),
        );
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        await _until(tester, () => checkbox().evaluate().isNotEmpty);
        final before = {
          for (final file in await inner.list())
            file.name: base64Encode(await inner.read(file.name)),
        };
        final complete = tester.widget<Checkbox>(checkbox()).onChanged!;
        complete(true);
        complete(true);
        await _until(
          tester,
          () => find.text('Unfinished checklist items').evaluate().isNotEmpty,
        );
        if (outcome == 'cancel') {
          await captureNativeFixtureUi(
            tester,
            'completion-consent-waiting',
            waitingForConsent: true,
          );
        }
        expect(find.text('Unfinished checklist items'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          state.busy,
          true,
          reason: 'Consent still owns the operation guard.',
        );
        complete(true);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Unfinished checklist items'), findsOneWidget);
        expect(folder.appends, 0);
        final lateConfirm = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Complete anyway'),
            )
            .onPressed!;
        if (outcome == 'cancel') {
          final cancel = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
              .onPressed!;
          cancel();
          cancel();
        } else if (outcome == 'barrier') {
          await tester.tapAt(const Offset(5, 5));
        } else if (outcome == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          // A newly observed item requires another decision. No append may
          // occur on the first consent, and the second dialog must also be idle.
          await peer.addChecklistItem(parent, 'Incoming unchecked item');
          await tester.tap(find.text('Complete anyway'));
          await _until(
            tester,
            () => find
                .textContaining('7 items are still unchecked')
                .evaluate()
                .isNotEmpty,
          );
          expect(folder.appends, 0);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          folder.appendStarted = Completer<void>();
          folder.releaseAppend = Completer<void>();
          folder.failAppend = outcome == 'failure';
          final confirm = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Complete anyway'),
              )
              .onPressed!;
          confirm();
          confirm();
          await _until(tester, () => folder.appendStarted!.isCompleted);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(state.busy, true);
          complete(true);
          complete(true);
          await tester.pump(const Duration(milliseconds: 300));
          expect(folder.appends, 1);
          if (outcome == 'confirm') {
            await captureNativeFixtureUi(
              tester,
              'completion-consent-writing',
              waitingForConsent: true,
            );
          }
          folder.releaseAppend!.complete();
        }
        await _until(
          tester,
          () =>
              state.busy == false &&
              find.text('Unfinished checklist items').evaluate().isEmpty,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Unfinished checklist items'), findsNothing);
        await peer.refresh();
        expect(peer.currentTextRow(parent)!['completed'], outcome == 'confirm');
        if (outcome == 'confirm') {
          expect(folder.appends, 1);
          expect(find.text('Completed 1 task.'), findsOneWidget);
        } else if (outcome == 'failure') {
          expect(folder.appends, 1);
          expect(
            find.textContaining('Synthetic completion append failure.'),
            findsOneWidget,
          );
        } else {
          expect(folder.appends, 0);
          // A callback retained across barrier/Escape/Cancel must not pop the
          // task page after its own dialog has gone away.
          lateConfirm();
          await tester.pump();
          expect(find.byType(TasksPage), findsOneWidget);
          expect({
            for (final file in await inner.list())
              file.name: base64Encode(await inner.read(file.name)),
          }, before);
          expect(find.text('Completed 1 task.'), findsNothing);
          // Cancellation releases admission: a subsequent click opens one
          // fresh warning, rather than a queued completion or a stuck guard.
          complete(true);
          await _until(
            tester,
            () => find.text('Unfinished checklist items').evaluate().isNotEmpty,
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await _until(tester, () => state.busy == false);
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (folder.releaseAppend != null &&
            !folder.releaseAppend!.isCompleted) {
          folder.releaseAppend!.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await peer.close();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      }
    });
  }
}
