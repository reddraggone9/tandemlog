import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/current_operation.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/unified_record.dart';
import 'package:uuid/uuid.dart';
import '../integration_test/native_text_fixtures.dart';

const _rule = 'every 2 months on the 2nd Tuesday';
const _legacy = 'every 3 months on the 1st friday';
final _library = Platform.environment['TANDEMLOG_TEXT_LIBRARY'];

class _FaultFolder extends LocalLogFolder {
  _FaultFolder(super.location);
  int? keep;
  @override
  Future<void> append(String name, Uint8List bytes) async {
    final count = keep;
    keep = null;
    if (count == null) return super.append(name, bytes);
    if (count > 0) {
      await super.append(
        name,
        Uint8List.fromList(bytes.take(math.min(count, bytes.length)).toList()),
      );
    }
    throw const FileSystemException('Synthetic uncertain r4 append');
  }
}

Map<String, dynamic> _task(String user, String rule) => {
  'title': 'Repeat',
  'description': '',
  'assignee': user,
  'schedule': {'dueDate': '2030-05-14', 'recurrence': rule},
};

Future<List<LogEvent>> _taskEvents(LogFolder folder, String writer) async =>
    LineSplitter.split(utf8.decode(await folder.read('$writer.applog')))
        .map(UnifiedRecord.decode)
        .expand((action) => action.effects)
        .map((effect) => effect.task)
        .whereType<LogEvent>()
        .toList();

void main() {
  final skip = _library == null
      ? 'Requires the production text engine.'
      : false;
  late Directory root;
  late _FaultFolder folder;
  late TaskStore store;
  late String user;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('r4-writer-');
    folder = _FaultFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    store = await openNativeFixtureStore(
      folder,
      '${root.path}/profile',
      nativeLibraryPath: _library,
    );
    user = const Uuid().v4();
    await store.command(user, 'user.created', {'name': 'Synthetic'});
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  Future<LogEvent> complete(String id) => store.complete(
    id,
    completionInstant: DateTime.utc(2030, 5, 14, 12),
    localZoneId: 'UTC',
  );

  test(
    'revision follows the rule: expanded is 4, supported rules keep their own',
    () async {
      final legacy = const Uuid().v4(), expanded = const Uuid().v4();
      expect(
        (await store.createNativeFixtureTask(
          legacy,
          _task(user, _legacy),
        )).operationRevision,
        1,
      );
      expect(
        (await store.createNativeFixtureTask(
          expanded,
          _task(user, _rule),
        )).operationRevision,
        4,
      );
      expect(
        (await store.command(legacy, 'task.edited', {
          'schedule': {'dueDate': '2030-06-07', 'recurrence': _legacy},
        })).operationRevision,
        1,
      );
      expect((await complete(legacy)).operationRevision, 3);
      final done = await complete(expanded);
      expect(done.type, 'task.completedWithText');
      expect(done.operationRevision, 4);
      // The stored rule keeps its exact bytes, on the parent and successor.
      expect(done.data['successor']['schedule']['recurrence'], _rule);
    },
    skip: skip,
  );

  test(
    'bulk edit to an expanded rule writes r4 for every target and nothing on no-op',
    () async {
      final ids = [const Uuid().v4(), const Uuid().v4()];
      for (final id in ids) {
        await store.createNativeFixtureTask(id, _task(user, _legacy));
      }
      final before = await folder.read('${store.writer}.applog');
      final empty = await store.bulkEdit(
        ids,
        BulkTaskEdit(),
        expectedTaskSnapshot: store.taskSnapshot,
      );
      expect(empty.committedIds, isEmpty);
      expect(await folder.read('${store.writer}.applog'), before);
      final result = await store.bulkEdit(
        ids,
        BulkTaskEdit(schedulePatch: const {'recurrence': _rule}),
        expectedTaskSnapshot: store.taskSnapshot,
      );
      expect(result.committedIds.toSet(), ids.toSet());
      final edits = (await _taskEvents(
        folder,
        store.writer,
      )).where((e) => e.type == 'task.edited').toList();
      expect(edits, hasLength(2));
      expect(edits.map((e) => e.operationRevision).toSet(), {4});
    },
    skip: skip,
  );

  test(
    'retained completion needs r4 from the parent rule alone and carries no schedule',
    () async {
      final id = const Uuid().v4(), child = const Uuid().v5(id, 'successor');
      await store.createNativeFixtureTask(id, _task(user, _rule));
      final first = await complete(id);
      await store.command(child, 'task.edited', {
        'schedule': {'dueDate': '2030-08-20', 'recurrence': _rule},
      });
      await store.reopen(id, [first.id]);
      final again = await complete(id);
      expect(again.type, 'task.completedKeepingSuccessor');
      expect(again.operationRevision, 4);
      expect(again.data, isNot(contains('successor')));
      // The independently edited date survives; nothing is recomputed.
      expect(
        store.rows.singleWhere((r) => r['id'] == child)['schedule']['dueDate'],
        '2030-08-20',
      );
    },
    skip: skip,
  );

  test(
    'checklist completion writes r4 and copies items to the successor',
    () async {
      final id = const Uuid().v4();
      await store.createNativeFixtureTask(id, _task(user, _rule));
      await store.addChecklistItem(id, 'Synthetic item');
      final done = await complete(id);
      expect(done.type, 'task.completedWithChecklist');
      expect(done.operationRevision, 4);
    },
    skip: skip,
  );

  test('snapshot completion writes r4 with an exact instant', () async {
    // Only a store without the text engine has no documents to inherit.
    await store.close();
    await root.delete(recursive: true);
    root = await Directory.systemTemp.createTemp('r4-writer-');
    folder = _FaultFolder(
      (await Directory('${root.path}/shared').create()).path,
    );
    store = await TaskStore.open(folder, '${root.path}/profile');
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    final id = const Uuid().v4();
    await store.command(id, 'task.created', _task(user, _rule));
    final done = await complete(id);
    expect(done.type, 'task.completed');
    expect(done.operationRevision, 4);
    expect(done.data['completedInstant'], '2030-05-14T12:00:00.000000Z');
    expect(done.data, isNot(contains('completedAt')));
  }, skip: skip);

  for (final keep in [0, 37, 1000000]) {
    for (final restart in [false, true]) {
      test(
        'uncertain r4 append keeps exact bytes, $keep bytes landed, restart=$restart',
        () async {
          final id = const Uuid().v4();
          await store.createNativeFixtureTask(id, _task(user, _rule));
          OperationReceipt? receipt;
          folder.keep = keep;
          await expectLater(
            store.complete(
              id,
              completionInstant: DateTime.utc(2030, 5, 14, 12),
              localZoneId: 'UTC',
              onPrepared: (value) => receipt = value,
            ),
            throwsA(anything),
          );
          expect(receipt, isNotNull);
          final raw = receipt!.raw;
          expect(LogEvent.decode(raw).operationRevision, 4);
          if (restart) {
            await store.close();
            store = await openNativeFixtureStore(
              folder,
              '${root.path}/profile',
              nativeLibraryPath: _library,
            );
            expect(store.visibleTaskRow(id)!['completed'], keep == 1000000);
            expect(store.pendingTextOperations, isEmpty);
            if (keep != 1000000) {
              // Restart never replays; new intent is a new r4 operation.
              final fresh = await complete(id);
              expect(fresh.operationRevision, 4);
            }
          } else {
            final saved = await store.retryTextOperation(receipt!);
            expect(saved.encode(), raw);
            final completions = (await _taskEvents(
              folder,
              store.writer,
            )).where((e) => isTaskCompletion(e.type)).toList();
            expect(completions, hasLength(1));
            expect(completions.single.encode(), raw);
            expect(completions.single.operationRevision, 4);
          }
          final before = jsonEncode(store.rows);
          await store.close();
          store = await openNativeFixtureStore(
            folder,
            '${root.path}/profile',
            nativeLibraryPath: _library,
          );
          expect(jsonEncode(store.rows), before);
        },
        skip: skip,
      );
    }
  }

  test(
    'new reader refuses an expanded rule smuggled under old revisions, and malformed r4 stays a schedule error',
    () async {
      final op = CurrentOperation(
        module: 'tasks',
        space: store.space,
        author: store.writer,
        writer: store.writer,
        sequence: 1,
        clock: '1',
        subject: const Uuid().v4(),
        family: 'task.create',
        revision: 1,
        value: {'values': _task(user, _rule)},
        predecessor: eventGenesisHash(store.space, store.writer),
      );
      for (final revision in [1, 2]) {
        expect(
          () => LogEvent.decode(
            CurrentOperation(
              module: op.module,
              space: op.space,
              author: op.author,
              writer: op.writer,
              sequence: op.sequence,
              clock: op.clock,
              subject: op.subject,
              family: op.family,
              revision: revision,
              value: op.value,
              predecessor: op.predecessor,
            ).encode(),
          ),
          throwsA(
            isA<FormatFailure>().having(
              (e) => e.toString(),
              'message',
              contains('Update the app'),
            ),
          ),
        );
      }
      final malformed = CurrentOperation(
        module: op.module,
        space: op.space,
        author: op.author,
        writer: op.writer,
        sequence: op.sequence,
        clock: op.clock,
        subject: op.subject,
        family: op.family,
        revision: 4,
        value: {'values': _task(user, 'every full moon')},
        predecessor: op.predecessor,
      );
      expect(
        () => LogEvent.decode(malformed.encode()),
        throwsA(
          isA<FormatFailure>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('Unsupported recurrence'),
              isNot(contains('Update the app')),
            ),
          ),
        ),
      );
    },
    skip: skip,
  );
}
