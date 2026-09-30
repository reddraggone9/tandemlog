import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';
import '../tool/migration.dart';

MigrationBundle fixture(String source) => MigrationBundle.importBytes(
  utf8.encode(source),
  importBatchTime: DateTime.utc(2026, 10, 1, 12),
);
void append(
  MigrationBundle b,
  String entity,
  String type,
  Map<String, dynamic> data,
) {
  b.events.add(
    LogEvent.decode(
      LogEvent(
        b.space,
        b.writer,
        b.events.length + 1,
        EventClock(b.events.last.clock.value + BigInt.one),
        entity,
        type,
        data,
      ).encode(),
    ),
  );
}

void main() {
  test(
    'scalar clock and deterministic identities; no formatting provenance events',
    () {
      final b = fixture('- [x] Example ✅ 2020-01-02\n');
      expect(b.log, fixture('- [x] Example ✅ 2020-01-02\n').log);
      final base =
          BigInt.from(DateTime.utc(2026, 10, 1, 12).microsecondsSinceEpoch) *
          BigInt.from(1000);
      expect(
        b.events.map((e) => e.clock.value).toList(),
        List.generate(b.events.length, (i) => base + BigInt.from(i)),
      );
      expect(b.events.map((e) => e.type), [
        'user.created',
        'task.created',
        'task.completed',
      ]);
      expect(b.events.every((e) => !e.data.containsKey('import')), isTrue);
      expect(b.log, isNot(contains('titlePieces')));
      expect(b.importAnalysis['sourceByteExact'], true);
      for (final value in [
        1,
        {'wallMs': 1, 'logical': 0},
      ]) {
        expect(
          () => LogEvent.decode(
            jsonEncode(b.events.first.toJson()..['clock'] = value),
          ),
          throwsA(isA<FormatFailure>()),
        );
      }
    },
  );

  test(
    'canonical UTF8 LF formatting preserves internal title whitespace and opaque links',
    () {
      final source =
          '\uFEFF\r\n+ [X]  Read  [[Example#anchor|alias]] and [link](https://example.org/#x) #z #A #z ✅ 2026-09-30\r\n';
      final b = fixture(source);
      expect(
        utf8.decode(b.exportBytes()),
        '- [x] Read  [[Example#anchor|alias]] and [link](https://example.org/#x) #A #z ✅ 2026-09-30\n',
      );
      expect(b.importAnalysis['sourceByteExact'], false);
      expect(b.importAnalysis['blankLinesNormalized'], 1);
      expect(b.log, isNot(contains('encoding')));
      expect(b.log, isNot(contains('completionAction')));
      // Reload from only standard logs; neither source bytes nor transient report.
      final reloaded = MigrationBundle(
        b.space,
        b.writer,
        b.log.trim().split('\n').map(LogEvent.decode).toList(),
      );
      expect(reloaded.exportBytes(), b.exportBytes());
    },
  );

  test(
    'all 37 rules retain domain schedule and open-repeat delete serialization',
    () {
      final source = [
        for (final rule in observedRecurrences)
          '- [ ] Example #start-time-0930 🔁 $rule 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03',
      ].join('\n');
      final b = fixture(source);
      expect(b.tasks, hasLength(37));
      expect(b.inventory['distinctRecurrenceForms'], 37);
      expect(b.tasks.first['tags'], isEmpty);
      expect(
        b.tasks.first['schedule'],
        TaskSchedule(
          startDate: '2026-10-01',
          scheduledDate: '2026-10-02',
          dueDate: '2026-10-03',
          startTime: '09:30',
          recurrence: observedRecurrences.first,
        ).toJson(),
      );
      expect(
        RegExp('🏁 delete').allMatches(utf8.decode(b.exportBytes())),
        hasLength(37),
      );
    },
  );

  test(
    'synthetic inventory and recurrence oracle audit independently project all source rows',
    () {
      final source =
          '${[for (var i = 0; i < 220; i++) '- [${i < 3 || i >= 213 ? 'x' : ' '}] Example ${i + 1}'
                '${i < 99 ? ' 🔁 ${observedRecurrences[i % 37]}' : ''}'
                '${i >= 3 && i < 99 ? ' 🏁 delete' : ''}'
                '${i < 99 ? ' 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03' : ''}'
                '${i < 3 || i >= 213 ? ' ✅ 2026-09-30' : ''}'].join('\n')}\n';
      final b = fixture(source);
      expect(b.tasks, hasLength(220));
      expect(b.report['completed'], 10);
      expect(b.importAnalysis['sourceByteExact'], true);
      expect(b.importAnalysis['sourceDeleteMappedToAppKeep'], 96);
      final before = b.log;
      final audit = b.auditRecurrence('2026-10-20');
      expect(audit['recurrences'], 99);
      expect(audit['distinctRecurrenceForms'], 37);
      final cases = audit['cases'] as List;
      expect(
        cases.where((c) => c['historicallyCompleted'] == true),
        hasLength(3),
      );
      expect(cases.first['next'], {
        'startDate': '2026-10-19',
        'scheduledDate': null,
        'dueDate': '2026-10-21',
      });
      expect(jsonEncode(audit), isNot(contains('Example')));
      expect(b.log, before);
    },
  );

  test(
    'keep/delete metadata is adapted, not persisted; completed history stays',
    () {
      final b = fixture(
        '- [ ] Open 🔁 every day 🏁 KEEP 📅 2026-10-03\n'
        '- [x] History 🔁 every day 🏁 delete 📅 2026-10-03 ✅ 2026-09-30\n',
      );
      expect(
        utf8.decode(b.exportBytes()),
        '- [ ] Open 🔁 every day 🏁 delete 📅 2026-10-03\n'
        '- [x] History 🔁 every day 📅 2026-10-03 ✅ 2026-09-30\n',
      );
      expect(b.importAnalysis['sourceDeleteMappedToAppKeep'], 1);
      expect(b.importAnalysis['markdownDeleteFlagsAddedOrChanged'], 1);
      expect(b.events.where((e) => e.type == 'task.completed'), hasLength(1));
      expect(b.log, isNot(contains('🏁')));
    },
  );

  test(
    'edited title tags schedule manual order completion and reopen export current state',
    () {
      final b = fixture('- [ ] First\n- [ ] Second\n');
      final first = b.tasks[0]['id'] as String,
          second = b.tasks[1]['id'] as String;
      append(b, first, 'task.edited', {
        'title': 'Renamed  [[link]]',
        'schedule': TaskSchedule(dueDate: '2026-11-02').toJson(),
      });
      append(b, first, 'task.tagsChanged', {
        'add': ['new'],
        'remove': <String>[],
      });
      append(b, second, 'task.moved', {'before': first});
      append(b, second, 'task.completed', {'completedAt': '2026-10-02'});
      final completion = b.events.last.id;
      expect(
        utf8.decode(b.exportBytes()),
        '- [x] Second ✅ 2026-10-02\n- [ ] Renamed  [[link]] #new 📅 2026-11-02\n',
      );
      append(b, second, 'task.completionUndone', {'completion': completion});
      expect(utf8.decode(b.exportBytes()), startsWith('- [ ] Second\n'));
    },
  );

  test(
    'derived recurrence successors and their edits use production projection/order',
    () {
      final b = fixture('- [ ] Repeat 🔁 every week 📅 2026-10-03\n');
      final task = b.tasks.single, id = task['id'] as String;
      final successor = const Uuid().v5(id, 'successor');
      append(b, id, 'task.completed', {
        'completedAt': '2026-10-20',
        'successor': {
          'id': successor,
          'title': 'Repeat',
          'description': '',
          'assignee': task['assignee'],
          'schedule': TaskSchedule(
            dueDate: '2026-10-10',
            recurrence: 'every week',
          ).toJson(),
          'tags': <String>[],
        },
      });
      append(b, successor, 'task.edited', {'title': 'Next occurrence'});
      expect(
        utf8.decode(b.exportBytes()),
        '- [ ] Next occurrence 🔁 every week 🏁 delete 📅 2026-10-10\n'
        '- [x] Repeat 🔁 every week 📅 2026-10-03 ✅ 2026-10-20\n',
      );
    },
  );

  test(
    'unsupported fields and precise timestamps fail without silent loss',
    () {
      for (final change in [
        {'description': 'Important notes'},
        {
          'schedule': TaskSchedule(
            dueDate: '2026-10-03',
            dueTime: '17:00',
          ).toJson(),
        },
        {
          'schedule': TaskSchedule(
            scheduledDate: '2026-10-03',
            scheduledTime: '17:00',
          ).toJson(),
        },
        {
          'schedule': TaskSchedule(
            startDate: '2026-10-03',
            startTime: '09:00',
            timeZone: 'America/Chicago',
          ).toJson(),
        },
        {'title': 'Text #would-be-metadata'},
      ]) {
        final b = fixture('- [ ] Example\n');
        append(b, b.tasks.single['id'] as String, 'task.edited', change);
        expect(b.exportBytes, throwsA(anything));
      }
      for (final time in ['2026-10-02T00:00:00.000Z', '2026-10-02T12:30:00Z']) {
        final b = fixture('- [ ] Example\n');
        append(b, b.tasks.single['id'] as String, 'task.completed', {
          'completedAt': time,
        });
        expect(b.exportBytes, throwsFormatException);
      }
    },
  );

  test('multiple assignees cannot silently flatten to one Markdown user', () {
    final b = fixture('- [ ] First\n- [ ] Second\n');
    b.events.where((e) => e.type == 'task.created').last.data['assignee'] =
        '11111111-1111-4111-8111-111111111111';
    append(b, '11111111-1111-4111-8111-111111111111', 'user.created', {
      'name': 'Other',
    });
    expect(b.exportBytes, throwsFormatException);
  });

  test(
    'unsupported source content/metadata and missing dates fail with no import',
    () {
      for (final source in [
        '# Meaningful heading\n- [ ] Task',
        '- [ ] Task\n  note',
        '- [/] Example',
        '- [ ] Example #start-time-0930',
        '- [ ] Example 🏁 archive',
        '- [ ] Example 🔁 every day except Sunday 📅 2026-10-03',
        '- [ ] Example 📅 2026-02-30',
      ]) {
        expect(() => fixture(source), throwsA(anything), reason: source);
      }
    },
  );

  test('missing/duplicate stream events and old provenance cannot export', () {
    final b = fixture('- [ ] Example\n');
    expect(
      () =>
          MigrationBundle(b.space, b.writer, b.events.sublist(1)).exportBytes(),
      throwsFormatException,
    );
    expect(
      () => MigrationBundle(b.space, b.writer, [
        ...b.events,
        b.events.last,
      ]).exportBytes(),
      throwsFormatException,
    );
    final old = b.events.last.toJson();
    (old['data'] as Map)['import'] = {'documentId': b.space, 'line': 1};
    expect(
      () => LogEvent.decode(jsonEncode(old)),
      throwsA(isA<FormatFailure>()),
    );
  });
  test('complete export refuses unresolved and cross-entity dependencies', () {
    final missing = '11111111-1111-4111-8111-111111111111';
    final orphan = fixture('- [ ] Example\n');
    append(orphan, missing, 'task.edited', {'title': 'Orphan'});
    expect(orphan.exportBytes, throwsFormatException);
    final undo = fixture('- [ ] First\n- [ ] Second\n');
    final ids = undo.tasks.map((t) => t['id'] as String).toList();
    append(undo, ids.first, 'task.completed', {'completedAt': '2026-10-02'});
    final completion = undo.events.last.id;
    append(undo, ids.last, 'task.completionUndone', {'completion': completion});
    expect(undo.exportBytes, throwsFormatException);
    final move = fixture('- [ ] Example\n');
    append(move, move.tasks.single['id'] as String, 'task.moved', {
      'before': missing,
    });
    expect(move.exportBytes, throwsFormatException);
    final tags = fixture('- [ ] Example\n');
    append(tags, tags.tasks.single['id'] as String, 'task.tagsChanged', {
      'add': <String>[],
      'remove': ['$missing:1:0'],
    });
    expect(tags.exportBytes, throwsFormatException);
  });

  test(
    'shared projection rejects task operations on users and duplicate creations',
    () {
      final userEdit = fixture('- [ ] Example\n');
      append(userEdit, userEdit.events.first.entity, 'task.edited', {
        'title': 'Invalid',
      });
      expect(userEdit.exportBytes, throwsA(isA<FormatFailure>()));
      final duplicate = fixture('- [ ] Example\n');
      final created = duplicate.events.last;
      append(
        duplicate,
        created.entity,
        'task.created',
        Map<String, dynamic>.from(created.data),
      );
      expect(duplicate.exportBytes, throwsA(isA<FormatFailure>()));
    },
  );

  test(
    'CLI refuses overwrites and round-trips a fresh staging destination',
    () async {
      final temp = Directory.systemTemp.createTempSync('tandemlog-migration-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final source = File('${temp.path}/source.md')
        ..writeAsStringSync('- [ ] Example #demo\r\n');
      final executable = Platform.resolvedExecutable.replaceAll(r'\', '/');
      final cacheIndex = executable.indexOf('/bin/cache/');
      final flutterRoot =
          Platform.environment['FLUTTER_ROOT'] ??
          (cacheIndex >= 0
              ? executable.substring(0, cacheIndex)
              : throw StateError('Set FLUTTER_ROOT for migration CLI tests.'));
      final dart =
          '$flutterRoot/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
      Future<ProcessResult> run(List<String> args) =>
          Process.run(dart, ['run', 'tool/migration.dart', ...args]);
      final stage = '${temp.path}/stage';
      var result = await run(['dry-run', source.path, stage]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      result = await run(['dry-run', source.path, stage]);
      expect(result.exitCode, 1);
      result = await run(['export', stage, '$stage/forbidden.md']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('outside the canonical'));
      expect(File('$stage/forbidden.md').existsSync(), isFalse);
      result = await run([
        'audit-recurrence',
        stage,
        '2026-10-20',
        '$stage/forbidden.jsonl',
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('outside the canonical'));
      final store = await TaskStore.open(
        LocalLogFolder(stage),
        '${temp.path}/private',
      );
      try {
        final imported = store.rows
            .where((row) => row['kind'] == 'task')
            .toList();
        expect(imported, hasLength(1));
        expect(imported.single['title'], 'Example');
        expect(imported.single['tags'], ['demo']);
      } finally {
        await store.close();
      }
      final reopened = await TaskStore.open(
        LocalLogFolder(stage),
        '${temp.path}/private',
      );
      try {
        expect(reopened.readFiles, 0);
      } finally {
        await reopened.close();
      }
      result = await run(['export', stage, '${temp.path}/out.md']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        File('${temp.path}/out.md').readAsStringSync(),
        '- [ ] Example #demo\n',
      );
      result = await run(['export', stage, source.path]);
      expect(result.exitCode, 1);
      expect(source.readAsStringSync(), '- [ ] Example #demo\r\n');
      result = await run([
        'audit-recurrence',
        stage,
        '2026-10-20',
        '${temp.path}/audit.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        (jsonDecode(File('${temp.path}/audit.json').readAsStringSync())
            as Map)['cases'],
        isEmpty,
      );
      result = await run([
        'audit-recurrence',
        stage,
        '2026-10-20',
        '${temp.path}/audit.json',
      ]);
      expect(result.exitCode, 1);
      final log = Directory(stage).listSync().whereType<File>().singleWhere(
        (f) => f.path.endsWith('.jsonl'),
      );
      log.renameSync('$stage/conflict.jsonl');
      result = await run(['export', stage, '${temp.path}/conflict.md']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('filename'));
      if (!Platform.isWindows) {
        File('$stage/conflict.jsonl').renameSync(log.path);
        Link('$stage/linked.jsonl').createSync(log.path);
        result = await run(['export', stage, '${temp.path}/linked.md']);
        expect(result.exitCode, 1);
        expect(result.stderr, contains('regular files'));
      }
    },
  );
}
