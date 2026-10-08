import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/text/recurring_text.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';

Future<OperationReceipt> _save(
  TaskStore store,
  String entity,
  Map<String, String> replacements,
) async {
  final capture = await store.captureTaskText(entity);
  final prepared = <String, NativeTextPreparedSave>{};
  final changes = <String, dynamic>{};
  OperationReceipt? receipt;
  try {
    for (final entry in replacements.entries) {
      final field = capture.fields[entry.key]!;
      final draft = field.document.captureDraft(actorClientId: field.actor)
        ..replaceText(entry.value);
      final save = draft.prepareSave();
      prepared[entry.key] = save;
      changes[entry.key] = {
        'context': field.context,
        'allocation': field.allocation,
        'actor': field.actor,
        'update': save.update.encoded,
      };
    }
    await store.editNativeTask(entity, changes, onPrepared: (r) => receipt = r);
    for (final save in prepared.values) {
      save.commit(receiptUpdate: save.update);
    }
    store.registerTextOperation(receipt!, capture);
    return receipt!;
  } finally {
    store.releaseTextCapture(capture);
  }
}

Map<String, dynamic> _row(TaskStore store, String id) =>
    store.rows.singleWhere((r) => r['id'] == id);

void main() {
  test(
    'offline recurring peers retain child edits drafts Undo and exact cold replay',
    () async {
      final root = await Directory.systemTemp.createTemp('recurring-store-');
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      TaskStore? a, b, c;
      try {
        final ad = await Directory('${root.path}/a').create(),
            bd = await Directory('${root.path}/b').create();
        final ap = '${root.path}/pa', bp = '${root.path}/pb';
        a = await TaskStore.open(
          LocalLogFolder(ad.path),
          ap,
          textEngine: engine,
        );
        final user = const Uuid().v4(),
            parent = const Uuid().v4(),
            child = const Uuid().v5(parent, 'successor');
        await a.command(user, 'user.created', {'name': 'Synthetic'});
        await a.command(parent, 'task.createdWithText', {
          'title': 'AB',
          'description': 'ab',
          'assignee': user,
          'schedule': {'dueDate': '2030-05-10', 'recurrence': 'every day'},
          'text': {
            'codec': 'yrs-v1',
            'adapter': 1,
            'seeds': {
              'title': sha256.convert(engine.seedText('AB').bytes).toString(),
              'description': sha256
                  .convert(engine.seedText('ab').bytes)
                  .toString(),
            },
          },
        });
        for (final file in await LocalLogFolder(ad.path).list()) {
          await File('${ad.path}/${file.name}').copy('${bd.path}/${file.name}');
        }
        await File(
          '${ad.path}/tandemlog-space.json',
        ).copy('${bd.path}/tandemlog-space.json');
        b = await TaskStore.open(
          LocalLogFolder(bd.path),
          bp,
          textEngine: engine,
        );
        await _save(a, parent, {'title': 'AXB', 'description': 'axb'});
        await _save(b, parent, {'title': 'ABY', 'description': 'aby'});
        OperationReceipt? completionA;
        await a.complete(
          parent,
          completionDay: DateTime(2030, 5, 10),
          onPrepared: (r) => completionA = r,
        );
        final prefix = await _save(a, child, {
          'title': 'Next: AXB',
          'description': 'Next: axb',
        });
        final capture = await a.captureTaskText(child),
            title = capture.fields['title']!;
        final draft = title.document.captureDraft(actorClientId: title.actor)
          ..replaceText('Private draft');
        final context = title.context;
        final cd = await Directory('${root.path}/c').create();
        await File(
          '${ad.path}/tandemlog-space.json',
        ).copy('${cd.path}/tandemlog-space.json');
        c = await TaskStore.open(
          LocalLogFolder(cd.path),
          '${root.path}/pc',
          textEngine: engine,
        );
        await c.command(const Uuid().v4(), 'user.created', {
          'name': 'Delayed proof writer',
        });
        await File(
          '${cd.path}/${c.writer}.jsonl',
        ).copy('${bd.path}/${c.writer}.jsonl');
        await b.refresh();
        await b.complete(parent, completionDay: DateTime(2030, 5, 10));
        await File(
          '${bd.path}/${b.writer}.jsonl',
        ).copy('${ad.path}/${b.writer}.jsonl');
        await a.refresh();
        expect(_row(a, child)['textUnavailable'], isA<String>());
        expect(_row(a, child)['textInheritancePending'], isTrue);
        expect(title.document.read().text, 'Next: AXB');
        expect(draft.capturedText, 'Private draft');
        expect(title.context, context);
        final localLog = File('${ad.path}/${a.writer}.jsonl');
        final beforePendingCommand = await localLog.readAsBytes();
        final pendingFailure = anyOf(
          isA<TextInheritancePending>(),
          isA<FormatFailure>(),
        );
        await expectLater(a.captureTaskText(child), throwsA(pendingFailure));
        var preparedWhilePending = false;
        await expectLater(
          a.editNativeTask(
            child,
            Map<String, dynamic>.from(
              LogEvent.decode(prefix.raw).data['changes'] as Map,
            ),
            onPrepared: (_) => preparedWhilePending = true,
          ),
          throwsA(pendingFailure),
        );
        expect(preparedWhilePending, isFalse);
        expect(await localLog.readAsBytes(), beforePendingCommand);
        expect(a.pendingTextOperations, isEmpty);
        await File(
          '${cd.path}/${c.writer}.jsonl',
        ).copy('${ad.path}/${c.writer}.jsonl');
        await a.refresh();
        expect(_row(a, child).containsKey('textUnavailable'), isFalse);
        expect(_row(a, child).containsKey('textInheritancePending'), isFalse);
        expect(a.rows.where((r) => r['id'] == child), hasLength(1));
        expect(_row(a, child)['title'], 'Next: AXBY');
        expect(_row(a, child)['description'], 'Next: axby');
        expect(
          a.db.select(
            'SELECT context FROM text_fields WHERE entity=? AND field=?',
            [child, 'title'],
          ).single['context'],
          context,
        );
        final parentContext = a.db.select(
          'SELECT context FROM text_fields WHERE entity=? AND field=?',
          [parent, 'title'],
        ).single['context'];
        expect(
          a.db.select(
            'SELECT 1 FROM text_actors WHERE writer=? AND context=?',
            [b.writer, parentContext],
          ),
          isNotEmpty,
        );
        expect(
          a.db.select(
            'SELECT 1 FROM text_actors WHERE writer=? AND context=?',
            [b.writer, context],
          ),
          isEmpty,
        );
        expect(title.context, context);
        expect(title.document.isClosed, isFalse);
        expect(draft.capturedText, 'Private draft');
        expect(title.document.read().text, 'Next: AXBY');
        draft.cancel();
        a.releaseTextCapture(capture);
        final undo = await a.undoOperations([prefix.id]);
        expect(undo.remaining, isEmpty);
        expect(undo.undone, [prefix.id]);
        expect(_row(a, child)['title'], 'AXBY');
        expect(_row(a, child)['description'], 'axby');
        final completionUndo = await a.undoOperations([completionA!.id]);
        expect(completionUndo.remaining, isEmpty);
        expect(_row(a, child)['title'], 'AXBY');
        await _save(a, parent, {'title': 'Future parent'});
        expect(_row(a, child)['title'], 'AXBY');
        final rows = a.taskSnapshot;
        final states = a.db
            .select(
              'SELECT field,context,state_hash,frontier FROM text_fields WHERE entity=? ORDER BY field',
              [child],
            )
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final logs = <String, List<int>>{};
        for (final file in await LocalLogFolder(ad.path).list()) {
          logs[file.name] = await File('${ad.path}/${file.name}').readAsBytes();
        }
        await a.close();
        a = await TaskStore.open(
          LocalLogFolder(ad.path),
          ap,
          textEngine: engine,
        );
        expect(a.readFiles, 0);
        expect(a.taskSnapshot, rows);
        await a.close();
        await File('$ap/cache.sqlite').delete();
        a = await TaskStore.open(
          LocalLogFolder(ad.path),
          ap,
          textEngine: engine,
        );
        expect(a.taskSnapshot, rows);
        expect(
          a.db
              .select(
                'SELECT field,context,state_hash,frontier FROM text_fields WHERE entity=? ORDER BY field',
                [child],
              )
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
          states,
        );
        for (final entry in logs.entries) {
          expect(
            await File('${ad.path}/${entry.key}').readAsBytes(),
            entry.value,
          );
        }
      } finally {
        await a?.close();
        await b?.close();
        await c?.close();
        engine.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
        ? 'Actual native library required'
        : false,
  );
}
