import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/platform/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/domain/import_provenance.dart';
import '../tool/migration.dart';
import '../tool/migration_source.dart';

MigrationBundle _fixtureImport(List<int> bytes) => MigrationBundle.importBytes(
  bytes,
  importBatchTime: DateTime.utc(2026, 10, 1, 12),
);

void main() {
  test(
    'import scalar nanosecond batch time is explicit, stable and distinct from source history',
    () {
      final source = utf8.encode('- [x] Example ✅ 2020-01-02');
      final time = DateTime.utc(2026, 10, 1, 12);
      final first = MigrationBundle.importBytes(source, importBatchTime: time);
      final again = MigrationBundle.importBytes(source, importBatchTime: time);
      final later = MigrationBundle.importBytes(
        source,
        importBatchTime: time.add(const Duration(milliseconds: 1)),
      );
      expect(first.log, again.log);
      expect(first.writer, isNot(later.writer));
      final base = BigInt.from(time.microsecondsSinceEpoch) * BigInt.from(1000);
      expect(
        first.events.map((e) => e.clock.value).toList(),
        List.generate(first.events.length, (i) => base + BigInt.from(i)),
      );
      expect(first.events.every((e) => e.toJson()['clock'] is String), isTrue);
      expect(
        first.events
            .singleWhere((e) => e.type == 'task.completed')
            .data['completedAt'],
        '2020-01-02',
      );
      final legacy = first.events.first.toJson()..['clock'] = 1;
      expect(
        () => LogEvent.decode(jsonEncode(legacy)),
        throwsA(isA<FormatFailure>()),
      );
      legacy['clock'] = {'wallMs': time.millisecondsSinceEpoch, 'logical': 0};
      expect(
        () => LogEvent.decode(jsonEncode(legacy)),
        throwsA(isA<FormatFailure>()),
      );
    },
  );

  test(
    'export reparses rendered literals instead of trusting provenance fields',
    () {
      final bundle = _fixtureImport(utf8.encode('- [ ] Example'));
      final doc = bundle.events.singleWhere((e) => e.type == 'import.document');
      final parts = ((doc.data['lines'] as List).first['parts'] as List);
      parts[2]['literal'] = '] Injected title ';
      expect(bundle.exportBytes, throwsFormatException);
    },
  );

  test(
    'UTF8 BOM mixed line endings, opaque links, duplicate tags and title fragments round trip',
    () {
      final bytes = [
        239,
        187,
        191,
        ...utf8.encode(
          '# Example\r\n\r\n'
          '- [ ]  Read [[Example#section|alias]] and [reference](https://example.org/#anchor) #Area/tag #Area/tag 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03 🔁 every week when done 🏁 delete  \n'
          '+ [X]\tExample #tag with trailing title ✅ 2026-09-30\r'
          '- [ ] Same title\n- [ ] Same title',
        ),
      ];
      final bundle = _fixtureImport(bytes);
      expect(bundle.exportBytes(), bytes);
      final tasks = bundle.events
          .where((e) => e.type == 'task.created')
          .toList();
      expect(tasks, hasLength(4));
      expect(tasks[0].data['tags'], ['Area/tag']);
      expect(tasks[0].data['title'], contains('https://example.org/#anchor'));
      expect(tasks[2].entity, isNot(tasks[3].entity));
      expect(_fixtureImport(bytes).log, bundle.log);
      expect(
        bundle.events.where((e) => e.type == 'task.completed').single.data,
        {'completedAt': '2026-09-30'},
      );
    },
  );

  test(
    'all 37 source recurrence forms produce valid shared-domain schedules',
    () {
      expect(observedRecurrences, hasLength(37));
      final source = [
        for (final rule in observedRecurrences)
          '- [ ] Example #start-time-0930 🔁 $rule 🏁 delete 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03',
      ].join('\r\n');
      final bundle = _fixtureImport(utf8.encode(source));
      expect(utf8.decode(bundle.exportBytes()), source);
      final tasks = bundle.events
          .where((e) => e.type == 'task.created')
          .toList();
      expect(tasks, hasLength(37));
      expect(tasks.first.data['tags'], isEmpty);
      expect(tasks.first.data['schedule'], {
        'startDate': '2026-10-01',
        'scheduledDate': '2026-10-02',
        'dueDate': '2026-10-03',
        'startTime': '09:30',
        'scheduledTime': null,
        'dueTime': null,
        'timeZone': null,
        'recurrence': observedRecurrences.first,
      });
    },
  );

  test(
    'missing start date for time reports source line; completed import never advances repeat',
    () {
      expect(
        () => _fixtureImport(
          utf8.encode(
            '- [x] Example #start-time-0815 📅 2026-09-29 ✅ 2026-09-30',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Line 1'),
          ),
        ),
      );
      final source =
          '- [x] Example #start-time-0815 🛫 2026-09-28 📅 2026-09-29 ✅ 2026-09-30 🔁 every day';
      final bundle = _fixtureImport(utf8.encode(source));
      expect(
        bundle.events
            .singleWhere((e) => e.type == 'task.completed')
            .data
            .containsKey('successor'),
        isFalse,
      );
      expect(utf8.decode(bundle.exportBytes()), source);
    },
  );

  test('sanitized 220 tasks / 99 repeats / 10 completed independently replay', () {
    final source = [
      for (var i = 0; i < 220; i++)
        '- [${i < 3 || i >= 213 ? 'x' : ' '}] Example ${i + 1} #fixture${i % 24}'
            '${i < 99 ? ' 🔁 ${observedRecurrences[i % 37]} 📅 2026-10-03' : ''}'
            '${i >= 3 && i < 99 ? ' 🏁 delete' : ''}'
            '${i < 3 || i >= 213 ? ' ✅ 2026-09-30' : ''}',
    ].join('\n');
    final bundle = _fixtureImport(utf8.encode(source));
    final taskEvents = <String, List<LogEvent>>{};
    for (final event in bundle.events.where(
      (e) => e.type.startsWith('task.'),
    )) {
      taskEvents.putIfAbsent(event.entity, () => []).add(event);
    }
    final tasks = taskEvents.values.map(project).toList();
    expect(tasks, hasLength(220));
    expect(tasks.where((t) => t!['completed'] == true), hasLength(10));
    expect(bundle.fidelity, {
      'sourceByteExact': true,
      'markdownFlagNormalizations': 0,
      'sourceDeleteMappedToAppKeep': 96,
      'appCompletionPolicy': 'keep-history',
    });
    expect(
      tasks.where((t) => (t!['schedule'] as Map)['recurrence'] != null),
      hasLength(99),
    );
    expect(utf8.decode(bundle.exportBytes()), source);
  });

  test(
    'completion flags preserve provenance, keep app history, and normalize only open repeats',
    () {
      final source =
          '- [ ] Open repeat 🔁 every day 🏁 KEEP 📅 2026-10-03  \r\n'
          '- [ ] Missing flag 🔁 every week 📅 2026-10-03\n'
          '- [x] History 🔁 every month 📅 2026-10-03 ✅ 2026-09-30\n'
          '- [ ] Ordinary 🏁 KEEP\n'
          '- [ ] Already delete 🔁 every day 🏁 DELETE 📅 2026-10-03';
      final bundle = _fixtureImport(utf8.encode(source));
      final output = utf8.decode(bundle.exportBytes());
      expect(
        output,
        '- [ ] Open repeat 🔁 every day 🏁 delete 📅 2026-10-03  \r\n'
        '- [ ] Missing flag 🔁 every week 📅 2026-10-03 🏁 delete\n'
        '- [x] History 🔁 every month 📅 2026-10-03 ✅ 2026-09-30\n'
        '- [ ] Ordinary 🏁 KEEP\n'
        '- [ ] Already delete 🔁 every day 🏁 DELETE 📅 2026-10-03',
      );
      expect(bundle.fidelity, {
        'sourceByteExact': false,
        'markdownFlagNormalizations': 2,
        'sourceDeleteMappedToAppKeep': 1,
        'appCompletionPolicy': 'keep-history',
      });
      expect(bundle.originalSource.render(), utf8.encode(source));
      final tasks = bundle.events
          .where((e) => e.type == 'task.created')
          .toList();
      expect(tasks.first.data['title'], 'Open repeat');
      expect(
        tasks.every((e) => !e.data.containsKey('completionAction')),
        isTrue,
      );
      expect(
        bundle.events.where((e) => e.type == 'task.completed'),
        hasLength(1),
      );
      for (final invalid in ['archive', 'delete forever', 'keep 🏁 keep']) {
        expect(
          () => _fixtureImport(utf8.encode('- [ ] Example 🏁 $invalid')),
          throwsA(anything),
        );
      }
    },
  );

  test(
    'read-only recurrence audit covers all 99 cases/37 forms without title disclosure or writes',
    () {
      final source = [
        for (var i = 0; i < 220; i++)
          '- [${i < 3 || i >= 213 ? 'x' : ' '}] Sanitized title ${i + 1}'
              '${i < 99 ? ' 🔁 ${observedRecurrences[i % 37]} 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03' : ''}'
              '${i >= 3 && i < 99 ? ' 🏁 delete' : ''}'
              '${i < 3 || i >= 213 ? ' ✅ 2026-09-30' : ''}',
      ].join('\n');
      final bundle = _fixtureImport(utf8.encode(source));
      final before = bundle.log;
      final audit = bundle.auditRecurrence('2026-10-20');
      expect(audit['completion'], '2026-10-20');
      expect(audit['recurrences'], 99);
      expect(audit['distinctRecurrenceForms'], 37);
      expect(audit['dateFields'], {
        'startDate': 99,
        'scheduledDate': 99,
        'dueDate': 99,
      });
      expect(audit['timeFields'], {
        'startTime': 0,
        'scheduledTime': 0,
        'dueTime': 0,
      });
      final cases = audit['cases'] as List;
      expect(cases, hasLength(99));
      expect(
        cases.where((c) => c['historicallyCompleted'] == true),
        hasLength(3),
      );
      expect(cases.first['next'], {
        'startDate': '2026-10-19',
        'scheduledDate': null,
        'dueDate': '2026-10-21',
      });
      expect(jsonEncode(audit), isNot(contains('Sanitized title')));
      expect(bundle.log, before);
      expect(bundle.exportBytes(), utf8.encode(source));
    },
  );

  test('unknown or malformed metadata is a visible blocker', () {
    for (final source in [
      '- [/] Example',
      '- [ ] Example 📅 2026-02-30',
      '- [ ] Example 🔁 every fortnight 📅 2026-10-03',
      '- [ ] Example 🔁 every day except Sunday 📅 2026-10-03',
      '- [ ] Example #start-time-2500',
      '- [ ] Example 📅 2026-10-01 📅 2026-10-02',
      '- [ ] Example ⏫',
      '- [ ] Example [[broken',
    ]) {
      expect(
        () => _fixtureImport(utf8.encode(source)),
        throwsA(anything),
        reason: source,
      );
    }
    expect(() => MarkdownSource.parse([255]), throwsFormatException);
  });

  test(
    'import leaves due/scheduled times absent and exporter rejects newly precise times',
    () {
      final source = utf8.encode(
        '- [ ] Example 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03',
      );
      for (final field in ['scheduledTime', 'dueTime']) {
        final bundle = _fixtureImport(source);
        final task = bundle.events.singleWhere((e) => e.type == 'task.created');
        final schedule = task.data['schedule'] as Map<String, dynamic>;
        expect(schedule.containsKey(field), isTrue);
        expect(schedule[field], isNull);
        expect(bundle.exportBytes(), source);
        schedule[field] = '17:30';
        // The edited schedule is valid in the app but cannot be represented by
        // this unchanged-source export contract; refuse instead of dropping time.
        TaskSchedule.fromJson(schedule);
        expect(bundle.exportBytes, throwsFormatException);
      }
    },
  );

  test('domain divergence cannot be hidden by source provenance', () {
    final bundle = _fixtureImport(
      utf8.encode('- [ ] Example #tag 📅 2026-10-03'),
    );
    final task = bundle.events.singleWhere((e) => e.type == 'task.created');
    task.data['title'] = 'Different';
    expect(bundle.exportBytes, throwsFormatException);
  });

  test('missing/duplicate events and altered creation order fail export', () {
    final bundle = _fixtureImport(utf8.encode('- [ ] First\n- [ ] Second'));
    expect(
      () => MigrationBundle(bundle.space, bundle.writer, [
        ...bundle.events,
        bundle.events[1],
      ]).exportBytes(),
      throwsFormatException,
    );
    expect(
      () => MigrationBundle(
        bundle.space,
        bundle.writer,
        bundle.events.sublist(1),
      ).exportBytes(),
      throwsFormatException,
    );
  });

  test(
    'closed provenance validation rejects malformed slots and unknown nested fields',
    () {
      final bundle = _fixtureImport(
        utf8.encode(
          '- [ ] Example #start-time-0930 🛫 2026-10-01 📅 2026-10-03',
        ),
      );
      Map<String, dynamic> data() =>
          jsonDecode(
                jsonEncode(
                  bundle.events
                      .singleWhere((e) => e.type == 'import.document')
                      .data,
                ),
              )
              as Map<String, dynamic>;
      validateImportDocument(data());
      final unknown = data();
      (unknown['lines'] as List).first['extra'] = 1;
      expect(() => validateImportDocument(unknown), throwsFormatException);
      final badSlot = data();
      ((badSlot['lines'] as List).first['parts'] as List).add({
        'field': 'title',
        'piece': 50,
      });
      expect(() => validateImportDocument(badSlot), throwsFormatException);
      final mismatch = data();
      (mismatch['lines'] as List).first['fields']['startTime'] = '10:30';
      expect(() => validateImportDocument(mismatch), throwsFormatException);
      expect(
        () => validateTaskImport({'documentId': bundle.space, 'line': 0}),
        throwsFormatException,
      );
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
        File('${temp.path}/out.md').readAsBytesSync(),
        source.readAsBytesSync(),
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
    },
  );
}
