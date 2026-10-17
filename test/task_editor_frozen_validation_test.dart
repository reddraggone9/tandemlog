import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

void main() {
  final library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];
  testWidgets(
    'Task frozen Retry preserves captured callback fields and native packet despite invalid controllers',
    (tester) async {
      final engine = NativeTextEngine(libraryPath: library);
      addTearDown(engine.dispose);
      const id = '00000000-0000-4000-8000-000000000081';
      final owners = <String, TaskTextFieldCapture>{};
      for (final field in ['title', 'description']) {
        final actor = field == 'title' ? 801 : 803;
        owners[field] = TaskTextFieldCapture(
          field: field,
          context: (field == 'title' ? 'a' : 'b') * 64,
          allocation: id,
          actor: actor + 1,
          undoActor: actor,
          undoAllocation: id,
          document: engine.createDocument(
            actorClientId: actor,
            limits: NativeTextLimits(
              visibleUtf16: field == 'title' ? 500 : 10000,
            ),
            seed: engine.seedText(field == 'title' ? 'Original' : ''),
          ),
        );
      }
      final session = TaskTextSession(TaskTextCapture(id, owners, writer: id));
      addTearDown(session.cancel);
      var calls = 0, closed = 0;
      String? capturedArgs, receiptRaw;
      TaskTextPreparedSave? capturedPacket;
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskEditor(
              panel: true,
              task: {
                'id': id,
                'title': 'Original',
                'description': '',
                'assignee': 'a',
                'tags': ['old'],
                'tagRefs': {'ref': 'old'},
                'schedule': {'dueDate': '2026-10-20'},
              },
              textSession: session,
              onClose: () => closed++,
              save: (fields, add, remove) async {
                calls++;
                final args = jsonEncode([fields, add, remove]);
                final prepared = session.prepare();
                if (session.hasPendingReceipt) {
                  expect(args, capturedArgs);
                  expect(identical(prepared, capturedPacket), isTrue);
                  expect(prepared.receipt!.raw, receiptRaw);
                  prepared.commitReceipt(prepared.receipt!);
                  return;
                }
                capturedArgs = args;
                capturedPacket = prepared;
                expect(fields.containsKey('title'), isFalse);
                expect((fields['schedule'] as Map)['dueTime'], '10:00');
                expect(
                  () => fields['assignee'] = 'changed',
                  throwsUnsupportedError,
                );
                expect(
                  () => (fields['schedule'] as Map)['dueTime'] = '11:00',
                  throwsUnsupportedError,
                );
                expect(add, ['new']);
                expect(remove, isEmpty);
                final event = LogEvent(
                  id,
                  id,
                  1,
                  EventClock(BigInt.one),
                  id,
                  'task.textEdited',
                  {'changes': prepared.changes},
                );
                final receipt = OperationReceipt(event.id, event.encode(), id);
                receiptRaw = receipt.raw;
                prepared.bindReceipt(receipt);
                throw StateError('Synthetic append outcome unknown');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder input(String key) => find.byKey(ValueKey(key));
      Future<void> edit(String key, String text) async {
        await tester.ensureVisible(input(key));
        await tester.enterText(input(key), text);
        await tester.pump();
      }

      await edit('title', 'Captured title');
      await edit('dueTime', '10:00');
      await edit('tags', 'new');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(session.hasPendingReceipt, isTrue);
      expect(closed, 0);
      for (final entry in {
        'dueDate': 'not a date',
        'dueTime': '-1',
        'timeZone': 'Imaginary/Zone',
        'recurrence': 'invalid rule',
        'dueMinDays': '2.5',
      }.entries) {
        tester.widget<TextField>(input(entry.key)).controller!.text =
            entry.value;
      }
      tester
          .widget<TextField>(input('title'))
          .controller!
          .value = const TextEditingValue(
        text: 'Uncommitted\nreplacement',
        composing: TextRange(start: 0, end: 11),
      );
      tester
          .widget<TextField>(input('tags'))
          .controller!
          .value = const TextEditingValue(
        text: '#',
        composing: TextRange(start: 0, end: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry Save'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry Save'));
      await tester.tap(find.text('Retry Save'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(closed, 1);
      expect(session.hasPendingReceipt, isFalse);
      expect(owners['title']!.document.read().text, 'Captured title');
      expect(
        tester.widget<TextField>(input('title')).controller!.text,
        'Captured title',
      );
      expect(
        tester.widget<TextField>(input('dueDate')).controller!.text,
        '2026-10-20',
      );
      expect(
        tester.widget<TextField>(input('dueTime')).controller!.text,
        '10:00',
      );
      expect(tester.widget<TextField>(input('timeZone')).controller!.text, '');
      expect(
        tester.widget<TextField>(input('recurrence')).controller!.text,
        '',
      );
      expect(
        tester.widget<TextField>(input('dueMinDays')).controller!.text,
        '',
      );
      expect(tester.widget<TextField>(input('tags')).controller!.text, '');
      expect(tester.takeException(), isNull);
    },
    skip: library == null,
  );
}
