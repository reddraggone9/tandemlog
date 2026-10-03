import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/platform/view_time_source.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/profile_lock.dart';
import 'package:uuid/uuid.dart';
import 'task_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerDataIntegrityTests();
}

Future<void> _check(WidgetTester tester) async {
  await flows.openSettings(tester);
  final button = find.byKey(const ValueKey('check-data-integrity'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await flows.waitForUi(
    tester,
    () => find
        .byKey(const ValueKey('data-integrity-report'))
        .evaluate()
        .isNotEmpty,
  );
}

String _report(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('data-integrity-report')))
    .data!;

Future<Map<String, String>> _logs(Directory folder) async => {
  for (final file
      in await folder.list().where((f) => f.path.endsWith('.jsonl')).toList())
    file.path: await File(file.path).readAsString(),
};

void registerDataIntegrityTests() {
  testWidgets('integrity action requires an open store', (tester) async {
    final root = await Directory.systemTemp.createTemp('integrity-no-store-');
    try {
      await tester.pumpWidget(TandemlogApp(profilePath: root.path));
      await flows.waitForUi(
        tester,
        () => find.text('Start').evaluate().isNotEmpty,
      );
      await flows.openSettings(tester);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('check-data-integrity')),
            )
            .onPressed,
        isNull,
      );
      expect(await Directory('${root.path}/shared-data').exists(), isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await root.delete(recursive: true);
    }
  });

  testWidgets(
    'manual integrity preserves drafts Search selection and Undo, imports valid growth, and copies diagnostics',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('integrity-ui-');
      final shared = await Directory('${root.path}/shared').create();
      final profile = await Directory('${root.path}/profile').create();
      final writer = await TaskStore.open(
        LocalLogFolder(shared.path),
        '${root.path}/seed',
      );
      final user = const Uuid().v4(), task = const Uuid().v4();
      await writer.command(user, 'user.created', {'name': 'Alex Example'});
      await writer.command(task, 'task.created', {
        'title': 'Reference task',
        'description': '',
        'assignee': user,
        'tags': ['home', 'planning'],
      });
      await File(
        '${profile.path}/settings.json',
      ).writeAsString(jsonEncode({'folder': shared.path, 'user': user}));
      tester.view.physicalSize = const Size(1200, 820);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(
          TandemlogApp(
            profilePath: profile.path,
            timeSourceFactory: (changed) => ViewTimeSource(
              onChanged: changed,
              now: () => DateTime.utc(2026, 10, 3, 12),
              loadZone: () async => 'UTC',
            ),
          ),
        );
        await flows.waitForUi(
          tester,
          () => find.text('Reference task').evaluate().isNotEmpty,
        );
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        await tester.enterText(capture, 'Captured reference');
        await tester.tap(find.byKey(const ValueKey('capture-add')));
        await flows.waitForUi(
          tester,
          () => find.text('Captured reference').evaluate().isNotEmpty,
        );
        await tester.enterText(capture, 'Unsubmitted capture draft');
        await tester.tap(find.byKey(const ValueKey('open-search')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('task-search')),
          'Reference',
        );
        await tester.pumpAndSettle();
        await flows.selectTask(tester, task);
        final dynamic state = tester.state(find.byType(TasksPage));
        final before = await _logs(shared);
        await _check(tester);
        expect(_report(tester), contains('check passed'));
        expect(_report(tester), contains('No new events'));
        expect(_report(tester), contains('not authenticity or remote sync'));
        expect(await _logs(shared), before);
        final copy = find.byKey(const ValueKey('copy-integrity-report'));
        await tester.tap(copy);
        await tester.pumpAndSettle();
        expect(
          (await Clipboard.getData(Clipboard.kTextPlain))!.text,
          _report(tester),
        );
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(capture).controller!.text,
          'Unsubmitted capture draft',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('task-search')))
              .controller!
              .text,
          'Reference',
        );
        expect(state.selectedTasks, contains(task));
        expect(find.byKey(const ValueKey('undo-task-action')), findsOneWidget);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reference task'));
        await tester.pumpAndSettle();
        final title = find.widgetWithText(TextField, 'Title');
        await tester.enterText(title, 'Unsubmitted editor draft');
        state.importer.dispose();
        state.importer = null;
        final incoming = const Uuid().v4();
        await writer.command(incoming, 'task.created', {
          'title': 'Incoming reference',
          'description': '',
          'assignee': user,
        });
        final grown = await _logs(shared);
        await _check(tester);
        expect(
          _report(tester),
          contains('New valid complete events were imported'),
        );
        expect(await _logs(shared), grown);
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(title).controller!.text,
          'Unsubmitted editor draft',
        );
        expect(state.store.hasEntity(incoming), isTrue);
        expect(find.text('Incoming reference'), findsOneWidget);

        final log = File(
          grown.keys.firstWhere(
            (name) => name.endsWith('${writer.writer}.jsonl'),
          ),
        );
        final offset = await log.length();
        final record = '\n'.allMatches(await log.readAsString()).length + 1;
        await log.writeAsString('{"damaged":true}\n', mode: FileMode.append);
        final damaged = await _logs(shared);
        await _check(tester);
        expect(_report(tester), contains('check failed'));
        expect(_report(tester), contains(log.uri.pathSegments.last));
        expect(_report(tester), contains('record $record'));
        expect(_report(tester), contains('byte offset $offset'));
        expect(await _logs(shared), damaged);
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();
        await flows.openSettings(tester);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('check-data-integrity')),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);

        // A manual check waits for existing ingestion. Disposing while it is
        // queued must keep the profile lease until the queue drains and must
        // not verify, display a result, or touch the old widget afterward.
        final gate = Completer<void>();
        state.syncing = gate.future;
        final reads = state.store.readFiles;
        await tester.ensureVisible(
          find.byKey(const ValueKey('check-data-integrity')),
        );
        await tester.tap(find.byKey(const ValueKey('check-data-integrity')));
        await tester.pump();
        expect(state.busy, isTrue);
        await tester.pumpWidget(const SizedBox());
        await expectLater(
          ProfileLock.acquire(profile.path),
          throwsA(isA<ProfileInUse>()),
        );
        gate.complete();
        await tester.pumpAndSettle();
        ProfileLock? lease;
        for (var attempt = 0; attempt < 100 && lease == null; attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
          try {
            lease = await ProfileLock.acquire(profile.path);
          } on ProfileInUse {
            // Shutdown still waits for the serialized store close.
          }
        }
        expect(lease, isNotNull);
        await lease!.close();
        expect(state.store.readFiles, reads);
        expect(tester.takeException(), isNull);
      } finally {
        await writer.close();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await root.delete(recursive: true);
      }
    },
  );
}
