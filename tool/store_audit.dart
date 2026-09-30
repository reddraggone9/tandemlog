import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';

/// Run the actual production store against an existing folder without giving it
/// any canonical write capability. Every output stays in a fresh private folder.
Future<Map<String, dynamic>> auditStore(
  String canonicalPath,
  String outputPath, {
  Future<void> Function(TaskStore)? closeStore,
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
    store = await TaskStore.open(folder, cachePath);
    final initialRows = store.rows;
    final initialEncoding = jsonEncode(initialRows);
    final firstReads = store.readFiles;
    final space = store.space;
    final warning = store.clockWarning;
    final eventCount =
        store.db.select('SELECT COUNT(*) AS n FROM events').single['n'] as int;
    await close(store);
    store = null;
    store = await TaskStore.open(folder, cachePath);
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
  if (args.length != 2) {
    stderr.writeln(
      'Usage: tandemlog-store-audit EXISTING_CANONICAL_FOLDER NEW_PRIVATE_OUTPUT_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  try {
    // Aggregate output contains no task titles, descriptions, tags or source text.
    stdout.writeln(jsonEncode(await auditStore(args[0], args[1])));
  } catch (error) {
    stderr.writeln('Audit failed: $error');
    exitCode = 1;
  }
}
