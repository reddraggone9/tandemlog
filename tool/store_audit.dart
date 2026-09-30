import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/schedule.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

/// Run the actual production store against an existing folder without giving it
/// any canonical write capability. Every output stays in a fresh private folder.
Future<Map<String, dynamic>> auditStore(
  String canonicalPath,
  String outputPath, {
  Future<void> Function(TaskStore)? closeStore,
  DateTime? exerciseCompletionDay,
}) async {
  final close = closeStore ?? (TaskStore value) => value.close();
  final canonical = Directory(
    await Directory(canonicalPath).resolveSymbolicLinks(),
  );
  final requestedOutput = Directory.fromUri(
    Directory(outputPath).absolute.uri.normalizePath(),
  );
  if (await FileSystemEntity.type(requestedOutput.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError(
      'Audit output must be a new directory; existing output is never reused.',
    );
  }
  final parent = await requestedOutput.parent.resolveSymbolicLinks();
  final leaf = requestedOutput.uri.pathSegments
      .where((part) => part.isNotEmpty)
      .last;
  final output = Directory('$parent${Platform.pathSeparator}$leaf');
  if (auditOutputIsInsideCanonical(
    canonical.path,
    output.path,
    windows: Platform.isWindows,
  )) {
    throw StateError('Audit output must be outside the canonical folder.');
  }
  final folder = ReadOnlyAuditFolder(LocalLogFolder(canonical.path));
  final before = await hashFolder(folder);
  if (!before.containsKey('tandemlog-space.json')) {
    throw StateError(
      'An existing workspace manifest is required; audit never initializes a space.',
    );
  }
  await output.create();
  final cachePath = '${output.path}${Platform.pathSeparator}cache';
  TaskStore? store;
  Map<String, dynamic>? failure;
  try {
    if (Platform.isLinux || Platform.isMacOS) {
      final permissions = await Process.run('/bin/chmod', ['700', output.path]);
      if (permissions.exitCode != 0) {
        throw StateError('Cannot restrict audit output directory permissions.');
      }
    }
    LogFolder activeFolder = folder;
    if (exerciseCompletionDay != null) {
      final copyPath = '${output.path}/exercise-canonical';
      await Directory(copyPath).create();
      final copied = LocalLogFolder(copyPath);
      for (final name in before.keys) {
        await copied.create(name, await folder.read(name));
      }
      if (jsonEncode(await hashFolder(copied)) != jsonEncode(before)) {
        throw StateError('Source changed while copying rehearsal data.');
      }
      activeFolder = copied;
    }
    store = await TaskStore.open(activeFolder, cachePath);
    Map<String, dynamic>? exercise;
    if (exerciseCompletionDay != null) {
      final parent = store.rows.firstWhere(
        (row) =>
            row['kind'] == 'task' &&
            row['completed'] == false &&
            (row['schedule'] as Map?)?['recurrence'] != null,
        orElse: () =>
            throw StateError('No open recurring task available for rehearsal.'),
      );
      final parentId = parent['id'] as String;
      final nextId = const Uuid().v5(parentId, 'successor');
      if (store.rows.any((row) => row['id'] == nextId)) {
        throw StateError(
          'Selected task already has a successor; choose fresh imported staging.',
        );
      }
      final expectedSchedule = TaskSchedule.fromJson(
        Map<String, dynamic>.from(parent['schedule'] as Map),
      ).next(exerciseCompletionDay).toJson();
      final count = store.rows.length;
      await store.complete(parentId, completionDay: exerciseCompletionDay);
      final next = store.rows.where((row) => row['id'] == nextId).toList();
      if (next.length != 1 ||
          store.rows.length != count + 1 ||
          store.rows.firstWhere((row) => row['id'] == parentId)['completed'] !=
              true ||
          next.single['completed'] != false ||
          jsonEncode(next.single['schedule']) != jsonEncode(expectedSchedule) ||
          next.single['title'] != parent['title'] ||
          next.single['description'] != parent['description'] ||
          next.single['assignee'] != parent['assignee'] ||
          jsonEncode(next.single['tags']) != jsonEncode(parent['tags'])) {
        throw StateError(
          'Production completion did not retain history and create the expected single successor.',
        );
      }
      final ids = store.rows.map((row) => row['id']).toList();
      if (ids.indexOf(nextId) != ids.indexOf(parentId) - 1) {
        throw StateError(
          'Production successor was not placed immediately before its parent.',
        );
      }
      exercise = {
        'copiedCanonicalOnly': true,
        'parentCompleted': true,
        'singleSuccessor': true,
        'successorScheduleMatches': true,
        'successorBeforeParent': true,
      };
    }
    final initialRows = store.rows;
    final initialEncoding = jsonEncode(initialRows);
    final firstReads = store.readFiles;
    final space = store.space;
    final warning = store.clockWarning;
    final eventCount =
        store.db.select('SELECT COUNT(*) AS n FROM events').single['n'] as int;
    await close(store);
    store = null;
    store = await TaskStore.open(activeFolder, cachePath);
    final reopenedRows = store.rows;
    if (jsonEncode(reopenedRows) != initialEncoding) {
      throw StateError(
        'Production cache reopen changed the projected semantic rows.',
      );
    }
    if (store.readFiles != 0) {
      throw StateError(
        'Unchanged cache reopen unexpectedly reread canonical logs.',
      );
    }
    final reopenReads = store.readFiles;
    await close(store);
    store = null;
    final after = await hashFolder(folder);
    if (jsonEncode(after) != jsonEncode(before)) {
      throw StateError(
        'Canonical files changed during audit. Quiesce the sync provider and retry in a new output directory.',
      );
    }
    final tasks = initialRows.where((row) => row['kind'] == 'task').toList();
    final report = <String, dynamic>{
      'ok': true,
      'recurrenceExercise': ?exercise,
      'canonicalUnchanged': true,
      'cacheReopenIdentical': true,
      'firstLogReads': firstReads,
      'reopenLogReads': reopenReads,
      'canonicalFiles': before.length,
      'events': eventCount,
      'tasks': tasks.length,
      'openTasks': tasks.where((row) => row['completed'] == false).length,
      'completedTasks': tasks.where((row) => row['completed'] == true).length,
      'users': initialRows.where((row) => row['kind'] == 'user').length,
      'clockWarning': warning,
    };
    final encoder = const JsonEncoder.withIndent('  ');
    await File('${output.path}/semantic.json').writeAsString(
      encoder.convert({'space': space, 'rows': initialRows}),
      flush: true,
    );
    await File('${output.path}/canonical-hashes.json').writeAsString(
      encoder.convert({'before': before, 'after': after}),
      flush: true,
    );
    await File(
      '${output.path}/report.json',
    ).writeAsString(encoder.convert(report), flush: true);
    return report;
  } catch (error) {
    failure = {'ok': false, 'error': error.toString()};
    rethrow;
  } finally {
    Object? cleanupError;
    StackTrace? cleanupTrace;
    try {
      if (store != null) await close(store);
    } catch (error, trace) {
      cleanupError = error;
      cleanupTrace = trace;
    } finally {
      final originalFailure = failure != null;
      if (cleanupError != null) {
        failure ??= {'ok': false, 'error': cleanupError.toString()};
        failure['cleanupError'] = cleanupError.toString();
      }
      if (failure != null) {
        // Always attempt integrity evidence, even if closing the cache fails.
        try {
          final after = await hashFolder(folder);
          failure['canonicalUnchanged'] =
              jsonEncode(after) == jsonEncode(before);
          await File('${output.path}/canonical-hashes.json').writeAsString(
            jsonEncode({'before': before, 'after': after}),
            flush: true,
          );
        } catch (_) {
          failure['canonicalUnchanged'] = false;
        }
        try {
          await File(
            '${output.path}/report.json',
          ).writeAsString(jsonEncode(failure), flush: true);
        } catch (_) {
          /* Preserve the original error if output storage also fails. */
        }
      }
      if (!originalFailure && cleanupError != null) {
        Error.throwWithStackTrace(cleanupError, cleanupTrace!);
      }
    }
  }
}

/// Inputs have already been resolved/normalized by the filesystem. Windows
/// paths are case-insensitive; separator normalization also handles UNC roots.
bool auditOutputIsInsideCanonical(
  String canonical,
  String output, {
  required bool windows,
}) {
  String normalize(String value) {
    if (windows) value = value.replaceAll('\\', '/').toLowerCase();
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  final root = normalize(canonical), candidate = normalize(output);
  return candidate == root || candidate.startsWith('$root/');
}

class ReadOnlyAuditFolder implements LogFolder {
  ReadOnlyAuditFolder(this.source);
  final LocalLogFolder source;
  @override
  String get location => source.location;
  @override
  Future<List<LogFileInfo>> list() async {
    await for (final entry in Directory(location).list(followLinks: false)) {
      if (entry is Link) {
        throw StateError('Canonical audit refuses symbolic-link entries.');
      }
    }
    return source.list();
  }

  @override
  Future<Uint8List> read(String name) => source.read(name);
  @override
  Future<void> append(String name, Uint8List bytes) => Future.error(
    StateError('Audit transport cannot append canonical files.'),
  );
  @override
  Future<void> create(String name, Uint8List bytes) => Future.error(
    StateError('Audit transport cannot create canonical files.'),
  );
}

Future<Map<String, String>> hashFolder(LogFolder folder) async {
  final files = await folder.list();
  files.sort((a, b) => a.name.compareTo(b.name));
  final hashes = <String, String>{};
  for (final file in files) {
    hashes[file.name] = sha256.convert(await folder.read(file.name)).toString();
  }
  return hashes;
}

Future<void> main(List<String> args) async {
  final exerciseMode = args.isNotEmpty && args.first == '--exercise-recurrence';
  if ((!exerciseMode && args.length != 2) ||
      (exerciseMode && args.length != 4)) {
    stderr.writeln(
      'Usage: tandemlog-store-audit [--exercise-recurrence] EXISTING_CANONICAL_FOLDER NEW_PRIVATE_OUTPUT_DIRECTORY [COMPLETION_YYYY-MM-DD]',
    );
    exitCode = 64;
    return;
  }
  try {
    // Aggregate output contains no task titles, descriptions, tags or source text.
    DateTime? day;
    if (exerciseMode) {
      final value = args[3];
      day = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          day == null ||
          day.toIso8601String().substring(0, 10) != value) {
        throw const FormatException(
          'Completion must be a valid YYYY-MM-DD civil date.',
        );
      }
    }
    stdout.writeln(
      jsonEncode(
        await auditStore(
          args[exerciseMode ? 1 : 0],
          args[exerciseMode ? 2 : 1],
          exerciseCompletionDay: day,
        ),
      ),
    );
  } catch (error) {
    stderr.writeln('Audit failed: $error');
    exitCode = 1;
  }
}
