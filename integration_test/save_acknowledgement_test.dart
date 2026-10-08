import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'native_text_fixtures.dart';

/// Simulates a sync-provider atomic replacement after an acknowledged append.
/// Existing committed bytes survive; the new suffix is absent at reconciliation.
class _ReplacingFolder implements LogFolder {
  _ReplacingFolder(this.inner);
  final LocalLogFolder inner;
  bool replaceAfterAppend = false;
  int appendCalls = 0;
  String? droppedName;
  Uint8List? droppedSuffix;
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() async => [
    for (final file in await inner.list()) LogFileInfo(file.name, ''),
  ];
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    appendCalls++;
    final replace = replaceAfterAppend;
    replaceAfterAppend = false;
    final previous = await inner.read(name);
    await inner.append(name, bytes);
    if (!replace) return;
    droppedName = name;
    droppedSuffix = Uint8List.fromList(bytes);
    final temporary = File('$location/replacement.tmp');
    await temporary.writeAsBytes(previous, flush: true);
    await temporary.rename('$location/$name');
  }

  Future<void> restoreDroppedSuffix() =>
      inner.append(droppedName!, droppedSuffix!);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerSaveAcknowledgementTests();
}

void registerSaveAcknowledgementTests() {
  testWidgets(
    'legacy v3 provider replacement blocks retry until exact pending history recovery',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('save-ack-native-');
      final folder = _ReplacingFolder(
        LocalLogFolder((await Directory('${root.path}/shared').create()).path),
      );
      final store = await TaskStore.open(folder, '${root.path}/private');
      var closes = 0;
      try {
        await folder.create('${store.writer}.jsonl', Uint8List(0));
        final user = const Uuid().v4(), id = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Alex Example'});
        await store.command(id, 'task.created', {
          'title': 'Original task',
          'description': 'Original notes',
          'assignee': user,
        });
        final before = await folder.read('${store.writer}.jsonl');
        Map<String, dynamic> row() =>
            store.rows.firstWhere((r) => r['id'] == id);
        final task = row();
        Widget editor(Map<String, dynamic> task) => MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              key: UniqueKey(),
              task: task,
              panel: true,
              onClose: () => closes++,
              save: (fields, added, removed) async {
                await store.edit(id, fields, tags: added, observedTagRefs: {});
              },
            ),
          ),
        );
        await tester.pumpWidget(editor(task));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Retained draft',
        );
        await tester.enterText(
          find.byKey(const ValueKey('description')),
          'Unsaved details remain available for retry.',
        );
        folder.replaceAfterAppend = true;
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(closes, 0);
        expect(find.textContaining('could be confirmed'), findsOneWidget);
        for (final entry in {
          'title': 'Retained draft',
          'description': 'Unsaved details remain available for retry.',
        }.entries) {
          final field = tester.widget<TextField>(
            find.byKey(ValueKey(entry.key)),
          );
          expect(field.controller!.text, entry.value);
          expect(field.enabled, isTrue);
        }
        expect(row()['title'], 'Original task');
        expect(await folder.read('${store.writer}.jsonl'), before);
        final appendCalls = folder.appendCalls;
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(closes, 0);
        expect(
          find.textContaining('earlier append is unresolved'),
          findsOneWidget,
        );
        expect(folder.appendCalls, appendCalls);
        expect(await folder.read('${store.writer}.jsonl'), before);
        expect(row()['title'], 'Original task');
        for (final entry in {
          'title': 'Retained draft',
          'description': 'Unsaved details remain available for retry.',
        }.entries) {
          expect(
            tester
                .widget<TextField>(find.byKey(ValueKey(entry.key)))
                .controller!
                .text,
            entry.value,
          );
        }

        // The provider restores the bytes of the original attempted append,
        // including its original event ID, clock and chain hash. A retry must
        // never manufacture another payload at that reserved writer sequence.
        expect(folder.droppedName, '${store.writer}.jsonl');
        expect(folder.droppedSuffix, isNotNull);
        await folder.restoreDroppedSuffix();
        final recovered = await folder.read('${store.writer}.jsonl');
        expect(recovered, [...before, ...folder.droppedSuffix!]);
        expect(await store.refresh(), isTrue);
        expect(row()['title'], 'Retained draft');
        expect(
          row()['description'],
          'Unsaved details remain available for retry.',
        );
        // This standalone editor deliberately lacks the production prepared
        // receipt/snapshot guard. Review the recovered task instead of issuing
        // another edit from its retained draft.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(closes, 1);
        await tester.pumpWidget(editor(row()));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('title')))
              .controller!
              .text,
          'Retained draft',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('description')))
              .controller!
              .text,
          'Unsaved details remain available for retry.',
        );
        expect(await folder.read('${store.writer}.jsonl'), recovered);
        expect(folder.appendCalls, appendCalls);
        final events = utf8
            .decode(await folder.read('${store.writer}.jsonl'))
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map);
        expect(
          events.where((event) => event['type'] == 'task.edited').length,
          1,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native provider replacement freezes draft and retries the exact canonical receipt',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('native-save-ack-ui-');
      final folder = _ReplacingFolder(
        LocalLogFolder((await Directory('${root.path}/shared').create()).path),
      );
      final store = await openNativeFixtureStore(
        folder,
        '${root.path}/private',
      );
      TaskTextSession? session;
      var closes = 0;
      try {
        await folder.create('${store.writer}.jsonl', Uint8List(0));
        final user = const Uuid().v4(), id = const Uuid().v4();
        await store.command(user, 'user.created', {'name': 'Synthetic'});
        await store.createNativeFixtureTask(id, {
          'title': 'Original task',
          'description': 'Original notes',
          'assignee': user,
        });
        final task = store.rows.singleWhere((row) => row['id'] == id);
        final capture = await store.captureTaskText(id);
        session = TaskTextSession(
          capture,
          registerDraftActor: (field, allocation, actor) =>
              store.registerTextDraftActor(capture, field, allocation, actor),
        );
        final command = TextSaveCommand(store, session);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskEditor(
                task: task,
                panel: true,
                textSession: session,
                onClose: () => closes++,
                save: (fields, added, removed) async {
                  await command.save(
                    fields: fields,
                    tags: [],
                    observedTagRefs: {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('title')),
          'Retained native draft',
        );
        await tester.enterText(
          find.byKey(const ValueKey('description')),
          'Retained native notes',
        );
        final before = await folder.read('${store.writer}.jsonl');
        folder.replaceAfterAppend = true;
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        final prepared = session.prepare(), receipt = prepared.receipt!;
        expect(prepared.committed, isFalse);
        expect(session.hasPendingReceipt, isTrue);
        expect(closes, 0);
        expect(await folder.read('${store.writer}.jsonl'), before);
        expect(
          store.rows.singleWhere((row) => row['id'] == id)['title'],
          'Original task',
        );
        for (final entry in {
          'title': 'Retained native draft',
          'description': 'Retained native notes',
        }.entries) {
          final field = tester.widget<TextField>(
            find.byKey(ValueKey(entry.key)),
          );
          expect(field.controller!.text, entry.value);
          expect(field.enabled, isFalse);
        }
        expect(find.text('Retry Save'), findsOneWidget);
        final cancel = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Cancel'),
        );
        expect(cancel.onPressed, isNull);
        final attempted = folder.droppedSuffix!;
        expect(utf8.decode(attempted), '${receipt.raw}\n');
        await tester.tap(find.text('Retry Save'));
        await tester.pumpAndSettle();
        expect(session.hasPendingReceipt, isFalse);
        expect(prepared.committed, isTrue);
        expect(await folder.read('${store.writer}.jsonl'), [
          ...before,
          ...attempted,
        ]);
        expect(store.confirmedOperations([receipt]), {receipt.id});
        expect(
          store.rows.singleWhere((row) => row['id'] == id)['title'],
          'Retained native draft',
        );
        final events = const LineSplitter()
            .convert(utf8.decode(await folder.read('${store.writer}.jsonl')))
            .map((line) => jsonDecode(line) as Map);
        expect(
          events.where((event) => event['type'] == 'task.textEdited'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        if (session != null && !session.hasPendingReceipt) {
          session.cancel();
          store.releaseTextCapture(session.capture);
        }
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
}
