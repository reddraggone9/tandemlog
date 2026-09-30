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
    'import HLC batch time is explicit, stable and distinct from source history',
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
      expect(
        first.events.every(
          (e) => e.clock.wallMs == time.millisecondsSinceEpoch,
        ),
        isTrue,
      );
      expect(
        first.events.map((e) => e.clock.logical).toList(),
        List.generate(first.events.length, (i) => i),
      );
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
          '- [ ]  Read [[Example#section|alias]] and [reference](https://example.org/#anchor) #Area/tag #Area/tag 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03 🔁 every week when done  \n'
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
          '- [ ] Example #start-time-0930 🔁 $rule 🛫 2026-10-01 ⏳ 2026-10-02 📅 2026-10-03',
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

  test(
    'sanitized 220 tasks / 99 repeats / 10 completed independently replay',
    () {
      final source = [
        for (var i = 0; i < 220; i++)
          '- [${i < 10 ? 'x' : ' '}] Example ${i + 1} #fixture${i % 24}'
              '${i < 99 ? ' 🔁 ${observedRecurrences[i % 37]} 📅 2026-10-03' : ''}'
              '${i < 10 ? ' ✅ 2026-09-30' : ''}',
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
      expect(
        tasks.where((t) => (t!['schedule'] as Map)['recurrence'] != null),
        hasLength(99),
      );
      expect(utf8.decode(bundle.exportBytes()), source);
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
      final dart =
          '${Platform.environment['FLUTTER_ROOT'] ?? '/workspace/toolchains/flutter'}/bin/dart';
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
