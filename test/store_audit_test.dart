import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import '../tool/store_audit.dart' as audit;

void main() {
  late Directory root;
  late LocalLogFolder folder;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('store-audit-test');
    final canonical = await Directory('${root.path}/canonical').create();
    folder = LocalLogFolder(canonical.path);
    final store = await TaskStore.open(folder, '${root.path}/fixture-cache');
    try {
      final user = const Uuid().v4(), task = const Uuid().v4();
      await store.command(user, 'user.created', {'name': 'Fixture person'});
      await store.command(task, 'task.created', {
        'title': 'Synthetic monthly review',
        'description': 'Only sanitized test data',
        'assignee': user,
        'tags': ['#fixture'],
        'schedule': {
          'startDate': '2026-10-01',
          'dueDate': '2026-10-03',
          'recurrence': 'every month',
        },
      });
      await store.complete(task, completionDay: DateTime.utc(2026, 10, 20));
    } finally {
      await store.close();
    }
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'recurrence exercise writes only its private copy and reopens exact result',
    () async {
      final before = await audit.hashFolder(folder);
      final output = '${root.path}/exercise';
      final report = await audit.auditStore(
        folder.location,
        output,
        exerciseCompletionDay: DateTime.utc(2026, 11, 20),
      );
      expect(report['recurrenceExercise'], {
        'copiedCanonicalOnly': true,
        'parentCompleted': true,
        'singleSuccessor': true,
        'successorScheduleMatches': true,
        'successorBeforeParent': true,
      });
      expect(report['tasks'], 3);
      expect(report['completedTasks'], 2);
      expect(report['cacheReopenIdentical'], true);
      expect(report['reopenLogReads'], 0);
      expect(await audit.hashFolder(folder), before);
      expect(
        await audit.hashFolder(LocalLogFolder('$output/exercise-canonical')),
        isNot(before),
      );
      await expectLater(
        audit.auditStore(
          folder.location,
          output,
          exerciseCompletionDay: DateTime.utc(2026, 11, 20),
        ),
        throwsStateError,
      );
      await expectLater(
        audit.auditStore(
          folder.location,
          '${folder.location}/exercise',
          exerciseCompletionDay: DateTime.utc(2026, 11, 20),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'actual production store audit preserves canonical bytes and reopens cached views',
    () async {
      final before = await audit.hashFolder(folder);
      final output = '${root.path}/audit-output';
      final report = await audit.auditStore(folder.location, output);
      expect(report['ok'], true);
      expect(report['canonicalUnchanged'], true);
      expect(report['cacheReopenIdentical'], true);
      expect(report['firstLogReads'], 1);
      expect(report['reopenLogReads'], 0);
      expect(report['tasks'], 2);
      expect(report['openTasks'], 1);
      expect(report['completedTasks'], 1);
      expect(await audit.hashFolder(folder), before);
      final snapshot =
          jsonDecode(await File('$output/semantic.json').readAsString()) as Map;
      expect(
        (snapshot['rows'] as List).where((row) => row['kind'] == 'task'),
        hasLength(2),
      );
      expect(
        (snapshot['rows'] as List).every(
          (row) => ['user', 'task'].contains(row['kind']),
        ),
        isTrue,
      );
      expect(jsonEncode(snapshot), isNot(contains('provenance')));
      expect(jsonEncode(snapshot), isNot(contains('import.document')));
      expect(jsonEncode(report), isNot(contains('Synthetic monthly review')));
      if (Platform.isLinux) {
        expect((await Directory(output).stat()).mode & 0x1ff, 0x1c0);
      }
    },
  );
  test(
    'audit refuses output reuse, canonical-contained output and missing manifests',
    () async {
      final output = await Directory('${root.path}/existing').create();
      await expectLater(
        audit.auditStore(folder.location, output.path),
        throwsStateError,
      );
      await expectLater(
        audit.auditStore(folder.location, '${folder.location}/forbidden'),
        throwsStateError,
      );
      expect(await Directory('${folder.location}/forbidden').exists(), false);
      final empty = await Directory('${root.path}/empty').create();
      await expectLater(
        audit.auditStore(empty.path, '${root.path}/missing-output'),
        throwsStateError,
      );
      expect(await empty.list().toList(), isEmpty);
      expect(await Directory('${root.path}/missing-output').exists(), false);
    },
  );
  test(
    'audit transport has no canonical create or append capability',
    () async {
      final readonly = audit.ReadOnlyAuditFolder(folder);
      final before = await audit.hashFolder(folder);
      await expectLater(
        readonly.create('new.jsonl', Uint8List(0)),
        throwsStateError,
      );
      await expectLater(
        readonly.append('new.jsonl', Uint8List(0)),
        throwsStateError,
      );
      expect(await audit.hashFolder(folder), before);
    },
  );
  test(
    'Windows containment is case-insensitive and respects path boundaries',
    () {
      expect(
        audit.auditOutputIsInsideCanonical(
          r'C:\Data\Tasks',
          r'c:\data\tasks\audit',
          windows: true,
        ),
        true,
      );
      expect(
        audit.auditOutputIsInsideCanonical(
          r'C:\Data\Tasks',
          r'C:\Data\TasksOther',
          windows: true,
        ),
        false,
      );
      expect(
        audit.auditOutputIsInsideCanonical(
          r'\\Server\Share\Tasks',
          r'\\server\share\tasks\audit',
          windows: true,
        ),
        true,
      );
    },
  );
  test(
    'close failure preserves the original error and still checks canonical hashes',
    () async {
      final output = '${root.path}/close-failure';
      final before = await audit.hashFolder(folder);
      var closes = 0;
      await expectLater(
        audit.auditStore(
          folder.location,
          output,
          closeStore: (store) async {
            await store.close();
            closes++;
            throw StateError(
              closes == 1 ? 'primary close failure' : 'cleanup close failure',
            );
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'primary close failure',
          ),
        ),
      );
      final report =
          jsonDecode(await File('$output/report.json').readAsString()) as Map;
      expect(report['ok'], false);
      expect(report['canonicalUnchanged'], true);
      expect(report['error'], contains('primary close failure'));
      expect(report['cleanupError'], contains('cleanup close failure'));
      expect(await audit.hashFolder(folder), before);
      expect(await File('$output/canonical-hashes.json').exists(), true);
    },
  );
}
