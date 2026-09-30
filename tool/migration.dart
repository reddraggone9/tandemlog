import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/projection.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'migration_source.dart';

/// External fresh-workspace importer and domain-only Markdown serializer.
/// Source syntax exists only transiently during parsing, never in canonical logs.
class MigrationBundle {
  final String space, writer;
  final List<LogEvent> events;
  final Map<String, dynamic> importAnalysis;
  MigrationBundle(
    this.space,
    this.writer,
    this.events, {
    this.importAnalysis = const {},
  });

  factory MigrationBundle.importBytes(
    List<int> bytes, {
    String userName = 'Imported user',
    DateTime? importBatchTime,
  }) {
    final batch = (importBatchTime ?? DateTime.now()).toUtc();
    final source = MarkdownSource.parse(bytes);
    final digest = sha256.convert(bytes).toString();
    String id(String role) => const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      'tandemlog-import-v5:$digest:$userName:${batch.toIso8601String()}:$role',
    );

    final space = id('space'), writer = id('writer'), user = id('user');
    final events = <LogEvent>[];
    void add(String entity, String type, Map<String, dynamic> data) {
      final seq = events.length + 1;
      events.add(
        LogEvent.decode(
          LogEvent(
            space,
            writer,
            seq,
            EventClock(
              BigInt.from(batch.microsecondsSinceEpoch) * BigInt.from(1000) +
                  BigInt.from(seq - 1),
            ),
            entity,
            type,
            data,
          ).encode(),
        ),
      );
    }

    add(user, 'user.created', {'name': userName});
    final expected = <Map<String, dynamic>>[];
    var deleteToKeep = 0, addedFlags = 0, nonTaskLines = 0;
    for (var n = 0; n < source.lines.length; n++) {
      final line = source.lines[n];
      if (!line.containsKey('fields')) {
        if ((line['literal'] as String).trim().isNotEmpty) {
          throw FormatException(
            'Line ${n + 1}: Non-task source content is not representable; import stopped rather than dropping it.',
          );
        }
        nonTaskLines++;
        continue;
      }
      final fields = line['fields'] as Map<String, dynamic>;
      try {
        final task = id('line:$n');
        final schedule = scheduleOf(fields);
        if (fields['done'] != null && fields['completed'] != true) {
          throw const FormatException(
            'An open source task has a completion date.',
          );
        }
        final tags = ordinaryTags(fields);
        add(task, 'task.created', {
          'title': fields['title'],
          'description': '',
          'assignee': user,
          'schedule': schedule,
          'tags': tags,
        });
        if (fields['completed'] == true) {
          add(task, 'task.completed', {
            if (fields['done'] != null) 'completedAt': fields['done'],
          });
        }
        expected.add(sourceSemantics(fields));
        final action = (fields['completionAction'] as String?)?.toLowerCase();
        if (action == 'delete') deleteToKeep++;
        if (fields['completed'] == false &&
            fields['recurrence'] != null &&
            action != 'delete') {
          addedFlags++;
        }
      } catch (error) {
        throw FormatException('Line ${n + 1}: $error');
      }
    }
    if (expected.isEmpty) throw const FormatException('No task lines found.');
    final bundle = MigrationBundle(space, writer, events);
    final rows = bundle.tasks;
    if (jsonEncode(rows.map(taskSemantics).toList()) != jsonEncode(expected)) {
      throw const FormatException(
        'Imported task semantics/order differ from source.',
      );
    }
    final output = bundle.exportBytes();
    return MigrationBundle(
      space,
      writer,
      events,
      importAnalysis: {
        'importBatchTime': batch.toIso8601String(),
        'sourceByteExact': _same(bytes, output),
        'sourceSemanticReplay': 'passed',
        'sourceDeleteMappedToAppKeep': deleteToKeep,
        'markdownDeleteFlagsAddedOrChanged': addedFlags,
        'blankLinesNormalized': nonTaskLines,
        'formatPolicy':
            'Canonical Markdown; original formatting is not retained.',
      },
    );
  }

  static List<String> ordinaryTags(Map<String, dynamic> fields) =>
      (fields['tags'] as List)
          .cast<String>()
          .where((t) => !t.startsWith('#start-time-'))
          .map((t) => t.substring(1))
          .toSet()
          .toList()
        ..sort();

  static Map<String, dynamic> scheduleOf(Map<String, dynamic> f) =>
      TaskSchedule(
        startDate: f['start'] as String?,
        scheduledDate: f['scheduled'] as String?,
        dueDate: f['due'] as String?,
        startTime: f['startTime'] as String?,
        recurrence: f['recurrence'] as String?,
      ).toJson();

  static Map<String, dynamic> sourceSemantics(Map<String, dynamic> f) => {
    'title': f['title'],
    'description': '',
    'tags': ordinaryTags(f),
    'schedule': scheduleOf(f),
    'completed': f['completed'],
    'doneDate': f['done'],
  };

  static String? doneDate(Map<String, dynamic> task) {
    if (task['completed'] != true || task['completedAt'] == null) return null;
    final value = task['completedAt'] as String;
    if (value.length == 10) {
      parseCivilDate(value);
      return value;
    }
    throw const FormatException(
      'Markdown done dates cannot preserve a precise completion timestamp; only date-only completion is exportable.',
    );
  }

  static Map<String, dynamic> taskSemantics(Map<String, dynamic> task) => {
    'title': task['title'],
    'description': task['description'],
    'tags': (task['tags'] as List).cast<String>().toSet().toList()..sort(),
    'schedule': TaskSchedule.fromJson(
      task['schedule'] as Map<String, dynamic>,
    ).toJson(),
    'completed': task['completed'],
    'doneDate': doneDate(task),
  };

  List<Map<String, dynamic>> get tasks {
    validateStreams();
    final rows = projectWorkspace(events);
    _validateCompleteReferences(rows);
    return rows.where((row) => row['kind'] == 'task').toList();
  }

  void _validateCompleteReferences(List<Map<String, dynamic>> rows) {
    final entities = {for (final row in rows) row['id'] as String: row};
    final ids = {for (final event in events) event.id: event};
    for (final row in rows.where((r) => r['kind'] == 'task')) {
      if (entities[row['assignee']]?['kind'] != 'user') {
        throw const FormatException(
          'Missing or invalid task assignee; export requires complete history.',
        );
      }
    }
    for (final event in events) {
      if (!entities.containsKey(event.entity)) {
        throw const FormatException(
          'Unresolved entity dependency; export requires complete history.',
        );
      }
      if (event.type == 'task.completionUndone') {
        final target = ids[event.data['completion']];
        if (target == null ||
            target.type != 'task.completed' ||
            target.entity != event.entity ||
            target.clock >= event.clock) {
          throw const FormatException(
            'Missing or invalid completion reference.',
          );
        }
      }
      if (event.type == 'task.moved' &&
          event.data['before'] != null &&
          entities[event.data['before']]?['kind'] != 'task') {
        throw const FormatException('Missing or invalid task order anchor.');
      }
      final changes = event.type == 'task.tagsChanged'
          ? event.data
          : event.data['tagChanges'];
      if (changes == null) continue;
      for (final token in (changes['remove'] as List).cast<String>()) {
        final parts = token.split(':');
        final target = ids['${parts[0]}:${parts[1]}'];
        if (target != null) {
          final additions = target.type == 'task.created'
              ? target.data['tags'] as List? ?? []
              : target.type == 'task.tagsChanged'
              ? target.data['add'] as List
              : (target.data['tagChanges'] as Map?)?['add'] as List?;
          final index = int.parse(parts[2]);
          if (target.entity != event.entity ||
              target.clock >= event.clock ||
              additions == null ||
              index >= additions.length) {
            throw const FormatException('Invalid observed tag reference.');
          }
        } else {
          final seeds = events.where((candidate) {
            final successor = candidate.data['successor'];
            return successor is Map &&
                successor['id'] == event.entity &&
                candidate.clock < event.clock &&
                (successor['tags'] as List? ?? []).any(
                  (tag) =>
                      '${const Uuid().v5(event.entity, 'tag:$tag')}:1:0' ==
                      token,
                );
          });
          if (seeds.isEmpty) {
            throw const FormatException(
              'Missing derived tag dependency; export requires complete history.',
            );
          }
        }
      }
    }
  }

  List<int> exportBytes() {
    final rows = tasks;
    if (rows.map((t) => t['assignee']).toSet().length > 1) {
      throw const FormatException(
        'Markdown export cannot preserve multiple assignees; select a single-user workspace.',
      );
    }
    final output = StringBuffer();
    for (final task in rows) {
      final schedule = TaskSchedule.fromJson(
        task['schedule'] as Map<String, dynamic>,
      );
      if (task['description'] != '') {
        throw const FormatException(
          'Markdown export does not yet represent task notes.',
        );
      }
      if (schedule.scheduledTime != null ||
          schedule.dueTime != null ||
          schedule.timeZone != null) {
        throw const FormatException(
          'Markdown export cannot represent precise scheduled/due times or a pinned time zone.',
        );
      }
      final tokens = <String>[
        '- [${task['completed'] == true ? 'x' : ' '}]',
        task['title'] as String,
      ];
      final tags = (task['tags'] as List).cast<String>().toList()..sort();
      for (final tag in tags) {
        if (!RegExp(r'^[^\s#]+$').hasMatch(tag) ||
            tag.startsWith('start-time-')) {
          throw const FormatException(
            'An app tag is not representable as an ordinary Markdown tag.',
          );
        }
        tokens.add('#$tag');
      }
      if (schedule.startTime != null) {
        tokens.add('#start-time-${schedule.startTime!.replaceAll(':', '')}');
      }
      if (schedule.recurrence != null) tokens.add('🔁 ${schedule.recurrence}');
      if (schedule.recurrence != null && task['completed'] != true) {
        tokens.add('🏁 delete');
      }
      if (schedule.startDate != null) tokens.add('🛫 ${schedule.startDate}');
      if (schedule.scheduledDate != null) {
        tokens.add('⏳ ${schedule.scheduledDate}');
      }
      if (schedule.dueDate != null) tokens.add('📅 ${schedule.dueDate}');
      final done = doneDate(task);
      if (done != null) tokens.add('✅ $done');
      output.writeln(tokens.join(' '));
    }
    final bytes = utf8.encode(output.toString());
    final parsed = MarkdownSource.parse(bytes);
    if (parsed.lines.any((l) => !l.containsKey('fields'))) {
      throw const FormatException(
        'Exported task content became non-task Markdown.',
      );
    }
    final actual = parsed.lines
        .map((l) => sourceSemantics(l['fields'] as Map<String, dynamic>))
        .toList();
    final expected = rows.map(taskSemantics).toList();
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw const FormatException(
        'Exported Markdown cannot represent current task semantics exactly.',
      );
    }
    return bytes;
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
      EventClock? previous;
      for (var i = 0; i < stream.length; i++) {
        if (stream[i].sequence != i + 1 ||
            (previous != null && stream[i].clock <= previous)) {
          throw const FormatException(
            'Missing, duplicate, or unordered writer event.',
          );
        }
        previous = stream[i].clock;
      }
    }
  }

  Map<String, dynamic> get inventory {
    final schedules = tasks
        .map((t) => t['schedule'] as Map<String, dynamic>)
        .toList();
    final rules = <String, int>{};
    for (final schedule in schedules) {
      final rule = schedule['recurrence'] as String?;
      if (rule != null) rules[rule] = (rules[rule] ?? 0) + 1;
    }
    return {
      'recurrences': rules.values.fold<int>(0, (a, b) => a + b),
      'distinctRecurrenceForms': rules.length,
      'recurrenceForms': rules,
      'dateFields': {
        for (final field in ['startDate', 'scheduledDate', 'dueDate'])
          field: schedules.where((s) => s[field] != null).length,
      },
      'timeFields': {
        for (final field in ['startTime', 'scheduledTime', 'dueTime'])
          field: schedules.where((s) => s[field] != null).length,
      },
    };
  }

  Map<String, dynamic> auditRecurrence(String completionDate) {
    final day = parseCivilDate(completionDate);
    final rows = tasks;
    final cases = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final schedule = TaskSchedule.fromJson(
        row['schedule'] as Map<String, dynamic>,
      );
      if (schedule.recurrence == null) continue;
      cases.add({
        'id': row['id'],
        'position': i + 1,
        'rule': schedule.recurrence,
        'startDate': schedule.startDate,
        'scheduledDate': schedule.scheduledDate,
        'dueDate': schedule.dueDate,
        'historicallyCompleted': row['completed'],
        'next': {
          for (final e in schedule.next(day).toJson().entries)
            if (['startDate', 'scheduledDate', 'dueDate'].contains(e.key))
              e.key: e.value,
        },
      });
    }
    return {
      'auditVersion': 2,
      'completion': completionDate,
      ...inventory,
      'cases': cases,
      'scope':
          'Read-only current-domain predictions; positions are canonical order, not original source lines.',
    };
  }

  String get log => '${events.map((e) => e.encode()).join('\n')}\n';
  Map<String, dynamic> get report => {
    'format': protocolVersion,
    'tasks': tasks.length,
    'completed': tasks.where((t) => t['completed'] == true).length,
    ...inventory,
    ...importAnalysis,
    'appCompletionPolicy': 'keep-history',
    'canonicalFormattingProvenance': false,
    'assigneeIds': tasks.map((t) => t['assignee']).toSet().toList(),
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
      if (await FileSystemEntity.type(
            '${root.path}/tandemlog-space.json',
            followLinks: false,
          ) !=
          FileSystemEntityType.file) {
        throw const FormatException(
          'Manifest must be a regular file, not a link.',
        );
      }
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
        if (entry.path.endsWith('.jsonl') && entry is! File) {
          throw const FormatException(
            'Canonical logs must be regular files, not links or directories.',
          );
        }
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
      String pathKey(String value) {
        final normalized = value
            .replaceAll(r'\', '/')
            .replaceAll(RegExp(r'/+$'), '');
        return Platform.isWindows ? normalized.toLowerCase() : normalized;
      }

      final canonicalRoot = pathKey(await root.resolveSymbolicLinks());
      final outputParent = pathKey(
        await file.absolute.parent.resolveSymbolicLinks(),
      );
      if (outputParent == canonicalRoot ||
          outputParent.startsWith('$canonicalRoot/')) {
        throw const FormatException(
          'Export/audit output must be outside the canonical data folder.',
        );
      }

      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FormatException('Output exists; nothing overwritten.');
      }
      await file.create(exclusive: true);
      await file.writeAsBytes(bytes, flush: true);
      stdout.writeln(
        audit
            ? 'Read-only recurrence audit written; canonical source unchanged.'
            : 'Exported canonical Markdown from current domain state; semantic reparse validated. Original formatting is not retained. Assignee mapping (not encoded in Markdown): ${bundle.tasks.map((t) => t['assignee']).toSet().join(', ')}.',
      );
    }
  } catch (e) {
    stderr.writeln('Migration stopped: $e');
    exitCode = 1;
  }
}
