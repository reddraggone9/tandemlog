import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'migration_source.dart';

/// An external, fresh-workspace-only rehearsal. Never opens a live app cache or
/// borrows its writer. Canonical events contain the source map and domain data.
class MigrationBundle {
  final String space, writer;
  final List<LogEvent> events;
  MigrationBundle(this.space, this.writer, this.events);

  factory MigrationBundle.importBytes(
    List<int> bytes, {
    String userName = 'Imported user',
    DateTime? importBatchTime,
  }) {
    final batchTime = DateTime.fromMicrosecondsSinceEpoch(
      (importBatchTime ?? DateTime.now()).microsecondsSinceEpoch,
      isUtc: true,
    );
    final batchTimeText = batchTime.toIso8601String();
    final source = MarkdownSource.parse(bytes);
    if (!_same(source.render(), bytes)) {
      throw StateError(
        'Original source-map byte fidelity failed before import.',
      );
    }
    final digest = sha256.convert(bytes).toString();
    String id(String role) {
      final h = sha256
          .convert(
            utf8.encode(
              'tandemlog-import-v3:$digest:$userName:$batchTimeText:$role',
            ),
          )
          .toString();
      return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
    }

    final space = id('space'),
        writer = id('writer'),
        user = id('user'),
        document = id('document');
    final events = <LogEvent>[];
    void add(String entity, String type, Map<String, dynamic> data) {
      final n = events.length + 1;
      events.add(
        LogEvent.decode(
          LogEvent(
            space,
            writer,
            n,
            EventClock(
              BigInt.from(batchTime.microsecondsSinceEpoch) *
                      BigInt.from(1000) +
                  BigInt.from(n - 1),
            ),
            entity,
            type,
            data,
          ).encode(),
        ),
      );
    }

    add(user, 'user.created', {'name': userName});
    for (var n = 0; n < source.lines.length; n++) {
      final line = source.lines[n];
      if (!line.containsKey('fields')) continue;
      final task = id('line:$n');
      line['taskId'] = task;
      final fields = line['fields'] as Map<String, dynamic>;
      Map<String, dynamic> schedule;
      try {
        if (fields['startTime'] != null && fields['start'] == null) {
          throw const FormatException('Start time requires a start date.');
        }
        schedule = scheduleOf(fields);
      } catch (error) {
        throw FormatException('Line ${n + 1}: $error');
      }
      add(task, 'task.created', {
        'title': fields['title'],
        'description': '',
        'assignee': user,
        'schedule': schedule,
        'tags': (fields['tags'] as List)
            .cast<String>()
            .where((t) => !t.startsWith('#start-time-'))
            .map((t) => t.substring(1))
            .toSet()
            .toList(),
        'import': {'documentId': document, 'line': n + 1},
      });
      if (fields['completed'] == true) {
        add(task, 'task.completed', {
          if (fields['done'] != null) 'completedAt': fields['done'],
        });
      }
    }
    if (events.length == 1) throw const FormatException('No task lines found.');
    add(document, 'import.document', {
      'documentId': document,
      ...source.toJson(),
    });
    final bundle = MigrationBundle(space, writer, events);
    bundle.exportBytes(); // Includes authorized Markdown flag normalization.
    return bundle;
  }

  static Map<String, dynamic> scheduleOf(Map<String, dynamic> f) =>
      TaskSchedule(
        startDate: f['start'] as String?,
        scheduledDate: f['scheduled'] as String?,
        dueDate: f['due'] as String?,
        startTime: f['startTime'] as String?,
        timeZone: null,
        recurrence: f['recurrence'] as String?,
      ).toJson();

  List<int> exportBytes() {
    validateStreams();
    final documents = events.where((e) => e.type == 'import.document').toList();
    if (documents.length != 1) {
      throw const FormatException('Expected exactly one import document.');
    }
    final document = documents.single;
    final source = MarkdownSource.fromJson(
      jsonDecode(jsonEncode(document.data)) as Map<String, dynamic>,
    );
    final imported = <String>{};
    for (final line in source.lines) {
      if (!line.containsKey('fields')) continue;
      final taskId = line['taskId'] as String;
      if (!imported.add(taskId)) {
        throw const FormatException('Duplicate source task reference.');
      }
      final taskEvents = events.where((e) => e.entity == taskId).toList();
      final actual = project(taskEvents);
      if (actual == null || actual['kind'] != 'task') {
        throw const FormatException('Missing imported task.');
      }
      final f = line['fields'] as Map<String, dynamic>;
      final provenance = actual['import'];
      if (provenance is! Map ||
          provenance['documentId'] != document.entity ||
          provenance['line'] != source.lines.indexOf(line) + 1) {
        throw const FormatException(
          'Imported task/document reference mismatch.',
        );
      }
      final expectedTags =
          (f['tags'] as List)
              .cast<String>()
              .where((t) => !t.startsWith('#start-time-'))
              .map((t) => t.substring(1))
              .toSet()
              .toList()
            ..sort();
      final actualTags = (actual['tags'] as List).cast<String>().toList()
        ..sort();
      final completionDates = taskEvents
          .where((e) => e.type == 'task.completed')
          .map((e) => e.data['completedAt'])
          .toList();
      // This tool promises an unchanged-import round trip, not an edited-note
      // serializer. Reject divergence explicitly rather than emit stale source.
      if (actual['title'] != f['title'] ||
          actual['description'] != '' ||
          actual['completed'] != f['completed'] ||
          jsonEncode(actualTags) != jsonEncode(expectedTags) ||
          jsonEncode(actual['schedule']) != jsonEncode(scheduleOf(f)) ||
          (f['completed'] == true &&
              (completionDates.length != 1 ||
                  completionDates.single != f['done'])) ||
          taskEvents.any(
            (e) => !['task.created', 'task.completed'].contains(e.type),
          )) {
        throw const FormatException(
          'Task changed since import; unchanged-source exporter refuses stale output.',
        );
      }
      // Regenerate every semantic slot from independently replayed state. Title
      // segments must concatenate to the replayed title; formatting is separate.
      if ((f['titlePieces'] as List).join(' ') != actual['title']) {
        throw const FormatException('Title source map mismatch.');
      }
      final schedule = actual['schedule'] as Map;
      f['title'] = actual['title'];
      f['completed'] = actual['completed'];
      f['tags'] = actualTags.map((t) => '#$t').toList();
      if (f.containsKey('startTime')) f['startTime'] = schedule['startTime'];
      for (final pair in {
        'start': 'startDate',
        'scheduled': 'scheduledDate',
        'due': 'dueDate',
        'recurrence': 'recurrence',
      }.entries) {
        if (f.containsKey(pair.key)) f[pair.key] = schedule[pair.value];
      }
      if (f.containsKey('done') && f['completed'] == true) {
        f['done'] = completionDates.single;
      }
      if (f['completed'] == false &&
          f['recurrence'] != null &&
          (f['completionAction'] as String?)?.toLowerCase() != 'delete') {
        final hadAction = f.containsKey('completionAction');
        f['completionAction'] = 'delete';
        if (!hadAction) {
          final parts = (line['parts'] as List).cast<Map<String, dynamic>>();
          Map<String, dynamic>? trailing;
          if (parts.isNotEmpty &&
              parts.last['literal'] is String &&
              RegExp(r'^\s+$').hasMatch(parts.last['literal'] as String)) {
            trailing = parts.removeLast();
          }
          parts.addAll([
            {'literal': ' 🏁 '},
            {'field': 'completionAction'},
          ]);
          if (trailing != null) parts.add(trailing);
          line['parts'] = parts;
        }
      }
    }
    final createdTasks = events
        .where((e) => e.type == 'task.created')
        .map((e) => e.entity)
        .toSet();
    if (createdTasks.length != imported.length ||
        !createdTasks.containsAll(imported)) {
      throw const FormatException('Tasks added or missing since import.');
    }
    final ordered = events.where((e) => e.type == 'task.created').toList()
      ..sort((a, b) {
        final c = a.clock.compareTo(b.clock);
        return c != 0 ? c : a.writer.compareTo(b.writer);
      });
    if (jsonEncode(ordered.map((e) => e.entity).toList()) !=
        jsonEncode(imported.toList())) {
      throw const FormatException(
        'Imported order does not match canonical creation order.',
      );
    }
    if (events.any((e) => e.type == 'task.moved')) {
      throw const FormatException('Order changed since import.');
    }
    final restored = source.render();
    final reparsed = MarkdownSource.parse(restored);
    final expectedFields = source.lines
        .where((l) => l.containsKey('fields'))
        .map((l) => l['fields'] as Map<String, dynamic>)
        .toList();
    final actualFields = reparsed.lines
        .where((l) => l.containsKey('fields'))
        .map((l) => l['fields'] as Map<String, dynamic>)
        .toList();
    if (expectedFields.length != actualFields.length) {
      throw const FormatException(
        'Rendered source task inventory differs from replay.',
      );
    }
    for (var i = 0; i < expectedFields.length; i++) {
      final expected = Map<String, dynamic>.from(expectedFields[i]);
      final actual = Map<String, dynamic>.from(actualFields[i]);
      // Tags are a membership set in the domain; lexical duplicate occurrences
      // are separately checked by the strict source-map slot validator.
      List<String> ordinaryTags(Map<String, dynamic> f) =>
          (f['tags'] as List)
              .cast<String>()
              .where((t) => !t.startsWith('#start-time-'))
              .toSet()
              .toList()
            ..sort();
      expected['tags'] = ordinaryTags(expected);
      actual['tags'] = ordinaryTags(actual);
      bool sameFields(Map<String, dynamic> a, Map<String, dynamic> b) =>
          a.length == b.length &&
          a.keys.every((key) => jsonEncode(a[key]) == jsonEncode(b[key]));
      if (!sameFields(expected, actual)) {
        throw FormatException(
          'Rendered semantics differ from replay on task ${i + 1}.',
        );
      }
    }
    return restored;
  }

  void validateStreams() {
    final byWriter = <String, List<LogEvent>>{};
    for (final event in events) {
      LogEvent.decode(event.encode());
      if (event.space != space) {
        throw const FormatException('Mismatched event space.');
      }
      byWriter.putIfAbsent(event.writer, () => []).add(event);
    }
    for (final stream in byWriter.values) {
      stream.sort((a, b) => a.sequence.compareTo(b.sequence));
      EventClock? previousClock;
      for (var n = 0; n < stream.length; n++) {
        if (stream[n].sequence != n + 1 ||
            (previousClock != null &&
                stream[n].clock.compareTo(previousClock) <= 0)) {
          throw const FormatException(
            'Missing, duplicate, or unordered writer event.',
          );
        }
        previousClock = stream[n].clock;
      }
    }
  }

  MarkdownSource get originalSource => MarkdownSource.fromJson(
    jsonDecode(
          jsonEncode(
            events.singleWhere((e) => e.type == 'import.document').data,
          ),
        )
        as Map<String, dynamic>,
  );

  int get markdownFlagNormalizations => originalSource.lines.where((line) {
    final f = line['fields'];
    return f is Map &&
        f['completed'] == false &&
        f['recurrence'] != null &&
        (f['completionAction'] as String?)?.toLowerCase() != 'delete';
  }).length;

  Map<String, dynamic> get fidelity => {
    'sourceByteExact': _same(originalSource.render(), exportBytes()),
    'markdownFlagNormalizations': markdownFlagNormalizations,
    'sourceDeleteMappedToAppKeep': originalSource.lines.where((line) {
      final f = line['fields'];
      return f is Map &&
          (f['completionAction'] as String?)?.toLowerCase() == 'delete';
    }).length,
    'appCompletionPolicy': 'keep-history',
  };

  Map<String, dynamic> get inventory {
    final schedules = events
        .where((e) => e.type == 'task.created')
        .map((e) => e.data['schedule'] as Map<String, dynamic>)
        .toList();
    final ruleCounts = <String, int>{};
    for (final schedule in schedules) {
      final rule = schedule['recurrence'] as String?;
      if (rule != null) ruleCounts[rule] = (ruleCounts[rule] ?? 0) + 1;
    }
    return {
      'recurrences': ruleCounts.values.fold<int>(0, (a, b) => a + b),
      'distinctRecurrenceForms': ruleCounts.length,
      'recurrenceForms': ruleCounts,
      'dateFields': {
        for (final field in ['startDate', 'scheduledDate', 'dueDate'])
          field: schedules.where((schedule) => schedule[field] != null).length,
      },
      'timeFields': {
        for (final field in ['startTime', 'scheduledTime', 'dueTime'])
          field: schedules.where((schedule) => schedule[field] != null).length,
      },
    };
  }

  Map<String, dynamic> auditRecurrence(String completionDate) {
    final completionDay = parseCivilDate(completionDate);
    // Establish this is still the unchanged source import before producing an
    // audit. No completion commands or successor events are appended.
    exportBytes();
    final rows = events.where((e) => e.type == 'task.created').toList()
      ..sort((a, b) {
        final c = a.clock.compareTo(b.clock);
        return c != 0 ? c : a.writer.compareTo(b.writer);
      });
    final entries = <Map<String, dynamic>>[];
    for (final event in rows) {
      final schedule = TaskSchedule.fromJson(
        event.data['schedule'] as Map<String, dynamic>,
      );
      if (schedule.recurrence == null) continue;
      entries.add({
        'id': event.entity,
        'rule': schedule.recurrence,
        'startDate': schedule.startDate,
        'scheduledDate': schedule.scheduledDate,
        'dueDate': schedule.dueDate,
        'sourceLine': (event.data['import'] as Map)['line'],
        'historicallyCompleted': events.any(
          (e) => e.entity == event.entity && e.type == 'task.completed',
        ),
        'next': {
          for (final entry in schedule.next(completionDay).toJson().entries)
            if (['startDate', 'scheduledDate', 'dueDate'].contains(entry.key))
              entry.key: entry.value,
        },
      });
    }
    return {
      'auditVersion': 1,
      'completion': completionDate,
      ...inventory,
      'cases': entries,
      'scope':
          'Read-only predictions from shared task domain; includes historical completed rows; no successors created.',
    };
  }

  String get log => '${events.map((e) => e.encode()).join('\n')}\n';
  Map<String, dynamic> get report => {
    'format': protocolVersion,
    'importBatchTime': DateTime.fromMicrosecondsSinceEpoch(
      (events.firstWhere((e) => e.sequence == 1).clock.value ~/
              BigInt.from(1000))
          .toInt(),
      isUtc: true,
    ).toIso8601String(),
    'tasks': events.where((e) => e.type == 'task.created').length,
    'completed': events.where((e) => e.type == 'task.completed').length,
    ...inventory,
    'semanticReplay': 'passed',
    ...fidelity,
    'scope':
        'Fresh staging only; UTF-8; unchanged import export; no live data touched.',
  };
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

DateTime _parseBatchTime(String text) {
  final value = DateTime.tryParse(text);
  if (value == null ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
      ).hasMatch(text)) {
    throw const FormatException(
      'Import batch time must be an explicit UTC ISO timestamp with at most microsecond precision.',
    );
  }
  return value;
}

Future<void> main(List<String> args) async {
  try {
    if (args.length < 3 ||
        !['dry-run', 'export', 'audit-recurrence'].contains(args[0]) ||
        (args.isNotEmpty &&
            args[0] == 'audit-recurrence' &&
            args.length != 4)) {
      throw const FormatException(
        'Usage: dart run tool/migration.dart dry-run SOURCE.md NEW_STAGING_DIR [USER_NAME] [IMPORT_BATCH_UTC]\n       dart run tool/migration.dart export STAGING_DIR NEW_OUTPUT.md\n       dart run tool/migration.dart audit-recurrence STAGING_DIR COMPLETION_YYYY-MM-DD NEW_OUTPUT.json',
      );
    }
    if (args[0] == 'dry-run') {
      final sourceFile = File(args[1]);
      final bytes = await sourceFile.readAsBytes();
      final bundle = MigrationBundle.importBytes(
        bytes,
        userName: args.length > 3 ? args[3] : 'Imported user',
        importBatchTime: args.length > 4 ? _parseBatchTime(args[4]) : null,
      );
      final target = Directory(args[2]);
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FormatException(
          'Destination already exists. Choose a new staging directory; nothing overwritten.',
        );
      }
      if (!_same(bytes, await sourceFile.readAsBytes())) {
        throw const FormatException('Source changed during import.');
      }
      // Each output is created exclusively: retries never overwrite any file.
      // The manifest is last: interrupted staging is not an app workspace.
      await target.create();
      final logFile = File('${target.path}/${bundle.writer}.jsonl');
      await logFile.create(exclusive: true);
      await logFile.writeAsString(bundle.log, flush: true);
      final manifestFile = File('${target.path}/tandemlog-space.json');
      await manifestFile.create(exclusive: true);
      await manifestFile.writeAsString(
        jsonEncode({'v': protocolVersion, 'id': bundle.space}),
        flush: true,
      );
      stdout.writeln(jsonEncode(bundle.report));
    } else {
      final root = Directory(args[1]);
      final manifest =
          jsonDecode(
                await File('${root.path}/tandemlog-space.json').readAsString(),
              )
              as Map;
      if (manifest['v'] != protocolVersion) {
        throw const FormatException('Unsupported manifest.');
      }
      final events = <LogEvent>[];
      await for (final entry in root.list(followLinks: false)) {
        if (entry is File && entry.path.endsWith('.jsonl')) {
          final raw = await entry.readAsString();
          if (!raw.endsWith('\n')) {
            throw const FormatException('Incomplete log.');
          }
          for (final line in const LineSplitter().convert(raw)) {
            final event = LogEvent.decode(line);
            final filename = entry.uri.pathSegments.last;
            if (filename != '${event.writer}.jsonl') {
              throw const FormatException(
                'Log filename does not match its writer.',
              );
            }
            events.add(event);
          }
        }
      }
      if (events.any((e) => e.space != manifest['id'])) {
        throw const FormatException('Mismatched workspace.');
      }
      final bundle = MigrationBundle(manifest['id'] as String, '', events);
      final audit = args[0] == 'audit-recurrence';
      final bytes = audit
          ? utf8.encode(
              '${const JsonEncoder.withIndent('  ').convert(bundle.auditRecurrence(args[2]))}\n',
            )
          : bundle.exportBytes();
      final file = File(args[audit ? 3 : 2]);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FormatException('Output exists; nothing overwritten.');
      }
      await file.create(exclusive: true);
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln(
        audit
            ? 'Read-only recurrence audit written; canonical source unchanged.'
            : 'Exported Markdown; semantic replay validated; flag normalizations=${bundle.markdownFlagNormalizations}; sourceByteExact=${bundle.fidelity['sourceByteExact']}.',
      );
    }
  } catch (e) {
    stderr.writeln('Migration stopped: $e');
    exitCode = 1;
  }
}
