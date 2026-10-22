import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';
import 'package:sqlite3/sqlite3.dart';

import 'current_history_fixture.dart';

void main() {
  test(
    'dense native history reuses validation while Save, Undo and completion stay atomic',
    () async {
      final root = await Directory.systemTemp.createTemp('task-latency-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        final user = const Uuid().v4();
        await store.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        final titles = {
          for (var i = 0; i < 600; i++)
            const Uuid().v4(): 'Synthetic household task $i',
        };
        expect((await store.createTasks(titles, user)).succeeded, isTrue);
        // A later-sorted peer makes local reservation order differ from physical
        // scan order. Both describe the same complete semantic history.
        const peer = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        await folder.create(
          '$peer.applog',
          peerBytesFor(
            store,
            LogEvent(
              store.space,
              peer,
              1,
              EventClock(store.unified!.maximumClock!.value + BigInt.one),
              const Uuid().v4(),
              'user.created',
              {'name': 'Synthetic peer'},
            ),
          ),
        );
        await store.refresh();
        final history = store.unified!;
        final task = titles.keys.first;
        final canonicalBefore = await folder.read('${store.writer}.applog');
        final decodedBefore = history.decodedRecords;
        final validationsBefore = history.semanticValidationRuns;
        final readsBefore = history.readFiles;
        final capture = await store.captureTaskText(task);
        expect(history.readFiles, greaterThan(readsBefore));
        expect(history.decodedRecords, decodedBefore);
        expect(history.semanticValidationRuns, validationsBefore);
        final field = capture.fields['title']!;
        final draft = field.document.captureDraft(actorClientId: field.actor)
          ..replaceText('Edited synthetic household task');
        final prepared = draft.prepareSave();
        OperationReceipt? saved;
        var sequence = history.physicalSequence;
        await store.editNativeTask(task, {
          'title': {
            'context': field.context,
            'allocation': field.allocation,
            'actor': field.actor,
            'update': prepared.update.encoded,
          },
        }, onPrepared: (receipt) => saved = receipt);
        prepared.commit(receiptUpdate: prepared.update);
        store.registerTextOperation(saved!, capture);
        draft.cancel();
        expect(history.physicalSequence, ++sequence);
        expect(
          history.semanticValidationRuns - validationsBefore,
          1,
          reason:
              'Reservation and readback must reuse the same exact semantic proof.',
        );
        expect(history.decodedRecords - decodedBefore, 1);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          'Edited synthetic household task',
        );
        var validations = history.semanticValidationRuns;
        expect((await store.undoOperations([saved!.id])).error, isNull);
        expect(history.physicalSequence, ++sequence);
        expect(history.semanticValidationRuns - validations, 1);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['title'],
          titles[task],
        );
        validations = history.semanticValidationRuns;
        OperationReceipt? completed;
        await store.complete(
          task,
          completionDay: DateTime(2026, 10, 22),
          onPrepared: (receipt) => completed = receipt,
        );
        expect(history.physicalSequence, ++sequence);
        expect(history.semanticValidationRuns - validations, 1);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['completed'],
          isTrue,
        );
        expect((await store.undoOperations([completed!.id])).error, isNull);
        expect(history.physicalSequence, ++sequence);
        expect(
          store.rows.singleWhere((r) => r['id'] == task)['completed'],
          isFalse,
        );
        store.releaseTextCapture(capture);
        final canonicalAfter = await folder.read('${store.writer}.applog');
        expect(canonicalAfter.take(canonicalBefore.length), canonicalBefore);
        final rows = jsonEncode(store.rows);
        await store.close();
        store = await TaskStore.open(
          folder,
          '${root.path}/profile',
          textEngine: engine,
        );
        expect(jsonEncode(store.rows), rows);
        expect(await folder.read('${store.writer}.applog'), canonicalAfter);
      } finally {
        await store?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'warm decode cache still detects changed prefixes and invalid complete records',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'task-latency-integrity-',
      );
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      final store = await TaskStore.open(folder, '${root.path}/profile');
      try {
        await store.command(const Uuid().v4(), 'user.created', {
          'name': 'Synthetic',
        });
        await store.refresh();
        final history = store.unified!;
        final path = File('${folder.location}/${store.writer}.applog');
        final original = await path.readAsBytes();
        final decoded = history.decodedRecords;
        await store.refresh();
        expect(history.decodedRecords, decoded);
        final previous = history.snapshot;
        final changed = Uint8List.fromList(original);
        changed[changed.indexOf(83)] = 84;
        await path.writeAsBytes(changed, flush: true);
        await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
        expect(history.snapshot, previous);
        await path.writeAsBytes(original, flush: true);
        await store.refresh();
        final good = history.snapshot;
        await folder.append(
          '${store.writer}.applog',
          Uint8List.fromList(utf8.encode('{"unknown":true}\n')),
        );
        await expectLater(store.refresh(), throwsA(isA<FormatFailure>()));
        expect(history.snapshot, good);
        expect(history.hasPending, isFalse);
        await path.writeAsBytes(original, flush: true);
        await store.refresh();
        expect(await path.readAsBytes(), original);
        expect(
          () => history.snapshot.tasks.first.data['name'] = 'Mutated',
          throwsUnsupportedError,
        );
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'old malformed semantic cache rebuilds before expression indexes open',
    () async {
      final root = await Directory.systemTemp.createTemp('task-latency-cache-');
      final folder = LocalLogFolder(
        (await Directory('${root.path}/shared').create()).path,
      );
      TaskStore? store;
      try {
        store = await TaskStore.open(folder, '${root.path}/profile');
        final person = const Uuid().v4();
        await store.command(person, 'user.created', {'name': 'Synthetic'});
        final expected = jsonEncode(store.rows);
        final table = store.tables.events;
        final name = '${store.writer}.applog';
        final canonical = await folder.read(name);
        await store.close();
        store = null;
        final db = sqlite3.open('${root.path}/profile/local.sqlite');
        try {
          // Simulate a disposable malformed row produced by an older build,
          // which did not have these expression indexes.
          for (final suffix in ['entity', 'successor', 'type_parent']) {
            db.execute('DROP INDEX IF EXISTS ${table}_$suffix');
          }
          db.execute('UPDATE $table SET semantic=? WHERE entity=?', [
            '{',
            person,
          ]);
        } finally {
          db.close();
        }
        store = await TaskStore.open(folder, '${root.path}/profile');
        expect(jsonEncode(store.rows), expected);
        expect(await folder.read(name), canonical);
      } finally {
        await store?.close();
        await root.delete(recursive: true);
      }
    },
  );
}
