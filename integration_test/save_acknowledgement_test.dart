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

/// Simulates a sync-provider atomic replacement after an acknowledged append.
/// Existing committed bytes survive; the new suffix is absent at reconciliation.
class _ReplacingFolder implements LogFolder {
  _ReplacingFolder(this.inner);
  final LocalLogFolder inner;
  bool replaceAfterAppend = false;
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
    final replace = replaceAfterAppend;
    replaceAfterAppend = false;
    final previous = await inner.read(name);
    await inner.append(name, bytes);
    if (!replace) return;
    final temporary = File('$location/replacement.tmp');
    await temporary.writeAsBytes(previous, flush: true);
    await temporary.rename('$location/$name');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerSaveAcknowledgementTests();
}

void registerSaveAcknowledgementTests() {
  testWidgets(
    'provider replacement keeps editor draft until exact save retry',
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
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskEditor(
                task: task,
                panel: true,
                onClose: () => closes++,
                save: (fields, added, removed) async {
                  await store.edit(
                    id,
                    fields,
                    tags: added,
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
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(closes, 1);
        expect(row()['title'], 'Retained draft');
        expect(
          row()['description'],
          'Unsaved details remain available for retry.',
        );
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
}
