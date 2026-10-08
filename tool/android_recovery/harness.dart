// TEST ONLY. Never imported by lib/main.dart or a production build target.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/application/text_save_command.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:uuid/uuid.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Six bounded synthetic cases. Retains evidence; never deletes canonical logs.
/// Reopening is an orderly TaskStore/SQLite restart, not Android process death.
Future<Map<String, Object?>> runRecoveryHarness(
  Directory root, {
  LogFolder? sharedFolder,
  String? libraryPath,
  void Function(String)? progress,
}) async {
  if (sharedFolder != null) {
    check((await sharedFolder.list()).isEmpty, 'SAF folder must be empty');
  }
  final engine = NativeTextEngine(libraryPath: libraryPath);
  final results = <Map<String, Object?>>[];
  final watch = Stopwatch()..start();
  try {
    for (final afterWrite in [false, true]) {
      for (final cacheLoss in [null, false, true]) {
        final name = cacheLoss == null
            ? 'save-retry-afterWrite=$afterWrite'
            : 'restart-afterWrite=$afterWrite-cacheLoss=$cacheLoss';
        progress?.call('RUN $name');
        final caseRoot = await Directory(
          '${root.path}/case-${results.length}',
        ).create();
        final local = await Directory('${caseRoot.path}/canonical').create();
        final folder = _FaultFolder(sharedFolder ?? LocalLogFolder(local.path));
        final profile = '${caseRoot.path}/profile';
        TaskStore? store;
        TaskTextSession? session;
        try {
          store = await TaskStore.open(folder, profile, textEngine: engine);
          final writer = store.writer;
          final user = const Uuid().v4(), task = const Uuid().v4();
          await store.command(user, 'user.created', {
            'name': 'Synthetic recovery',
          });
          OperationReceipt receipt;
          if (cacheLoss == null) {
            await store.command(
              task,
              'task.createdWithText',
              _creation(engine, user, 'A', tags: ['old']),
            );
            final capture = await store.captureTaskText(task);
            session = TaskTextSession(
              capture,
              registerDraftActor: (field, allocation, actor) => store!
                  .registerTextDraftActor(capture, field, allocation, actor),
            );
            session.replace('title', 'AX');
            final owner = session.capture.fields['title']!.document;
            final before = owner.fullState.encoded;
            final refs = Map<String, String>.from(
              _row(store, task)['tagRefs'] as Map,
            );
            final command = TextSaveCommand(store, session);
            folder.arm(afterWrite);
            await _unknown(
              () => command.save(
                fields: {
                  'schedule': {'dueDate': '2026-10-07'},
                },
                tags: ['new'],
                observedTagRefs: refs,
              ),
            );
            receipt = session.prepare().receipt!;
            check(
              session.hasPendingReceipt && !session.prepare().committed,
              'uncertain Save retained prepared receipt',
            );
            check(
              owner.fullState.encoded == before,
              'native owner rolled back until acknowledgement',
            );
            var frozen = false;
            try {
              session.replace('title', 'different');
            } on StateError {
              frozen = true;
            }
            check(frozen, 'uncertain draft is frozen');
            final result = await command.save(
              fields: {
                'schedule': {'dueDate': '2030-01-01'},
              },
              tags: ['different'],
              observedTagRefs: {},
              expectedSnapshot: 'invalid',
              canCommit: () => false,
            );
            check(
              result.receipt!.raw == receipt.raw &&
                  result.receipt!.id == receipt.id,
              'retry uses exact bytes and id',
            );
            final row = _row(store, task);
            check(
              row['title'] == 'AX' &&
                  jsonEncode(row['schedule']) == '{"dueDate":"2026-10-07"}' &&
                  jsonEncode(row['tags']) == '["new"]',
              'original text and nontext intent survives retry',
            );
            check(!session.frozen, 'acknowledgement releases draft');
            await _oneCanonical(folder, writer, receipt);
            final undo = await store.undoOperations([receipt.id]);
            check(
              undo.remaining.isEmpty && undo.error == null,
              'selective Undo succeeds',
            );
            final undone = _row(store, task);
            check(
              undone['title'] == 'A' &&
                  jsonEncode(undone['tags']) == '["old"]' &&
                  (undone['schedule'] as Map)['dueDate'] == null,
              'Undo restores text and nontext metadata',
            );
          } else {
            OperationReceipt? prepared;
            folder.arm(afterWrite);
            await _unknown(
              () => store!.command(task, 'task.createdWithText', {
                ..._creation(engine, user, 'Exact retry'),
                'schedule': {'dueDate': '2026-10-07'},
                'tags': ['new'],
              }, onPrepared: (value) => prepared = value),
            );
            receipt = prepared!;
            check(
              store.pendingTextOperations.single.raw == receipt.raw,
              'private pending intent contains exact receipt',
            );
            await store.close();
            store = null;
            if (cacheLoss) {
              for (final suffix in ['', '-wal', '-shm']) {
                final file = File('$profile/cache.sqlite$suffix');
                if (await file.exists()) await file.delete();
              }
            }
            store = await TaskStore.open(folder, profile, textEngine: engine);
            check(
              store.writer == writer,
              'writer identity survives SQLite restart',
            );
            check(
              afterWrite
                  ? store.pendingTextOperations.isEmpty
                  : store.pendingTextOperations.single.raw == receipt.raw,
              'restart reconciles canonical acknowledgement',
            );
            final event = await store.retryTextOperation(receipt);
            check(
              event.canonicalRaw == receipt.raw,
              'restarted retry uses exact bytes',
            );
            check(
              store.pendingTextOperations.isEmpty &&
                  (await Directory(
                    '$profile/text-intents',
                  ).list().toList()).isEmpty,
              'acknowledged private intent removed',
            );
            final row = _row(store, task);
            check(
              row['title'] == 'Exact retry' &&
                  jsonEncode(row['schedule']) == '{"dueDate":"2026-10-07"}' &&
                  jsonEncode(row['tags']) == '["new"]',
              'creation and nontext intent survive restart',
            );
            await _oneCanonical(folder, writer, receipt);
          }
          results.add({
            'case': name,
            'passed': true,
            'writer': writer,
            'receiptId': receipt.id,
            'receiptSha256': sha256
                .convert(utf8.encode(receipt.raw))
                .toString(),
            'canonicalOccurrences': 1,
          });
          progress?.call('PASS $name');
        } catch (error, stack) {
          results.add({
            'case': name,
            'passed': false,
            'error': '$error',
            'stack': '$stack',
          });
          progress?.call('FAIL $name: $error');
        } finally {
          if (session != null && !session.hasPendingReceipt) session.cancel();
          await store?.close();
        }
      }
    }
  } finally {
    engine.dispose();
  }
  final report = <String, Object?>{
    'schema': 1,
    'testOnly': true,
    'platform': Platform.operatingSystem,
    'sourceRevision': const String.fromEnvironment(
      'RECOVERY_SOURCE_REVISION',
      defaultValue: 'unrecorded',
    ),
    'transport': sharedFolder == null
        ? 'app-private-native-files'
        : 'Android-SAF',
    'folder': sharedFolder?.location,
    'root': root.path,
    'elapsedMs': watch.elapsedMilliseconds,
    'cases': results,
    'passed': results.length == 6 && results.every((r) => r['passed'] == true),
    'limits': [
      'Orderly store close/reopen; no process kill or power loss',
      'Synthetic fault surrounds append; no provider-generated I/O failure',
      'No UI editor workflow, remote sync, or notification coverage',
    ],
  };
  await File('${root.path}/report.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  return report;
}

Map<String, dynamic> _row(TaskStore store, String task) =>
    store.rows.singleWhere((row) => row['id'] == task);
Map<String, Object?> _creation(
  NativeTextEngine engine,
  String user,
  String title, {
  List<String>? tags,
}) => {
  'title': title,
  'description': '',
  'assignee': user,
  'tags': ?tags,
  'text': {
    'codec': 'yrs-v1',
    'adapter': 1,
    'seeds': {
      'title': sha256.convert(engine.seedText(title).bytes).toString(),
      'description': sha256.convert(engine.seedText('').bytes).toString(),
    },
  },
};
Future<void> _unknown(Future<Object?> Function() action) async {
  try {
    await action();
  } on FolderAccessFailure {
    return;
  }
  throw StateError('Expected synthetic unknown append outcome');
}

Future<void> _oneCanonical(
  LogFolder folder,
  String writer,
  OperationReceipt receipt,
) async {
  final matching = const LineSplitter()
      .convert(utf8.decode(await folder.read('$writer.jsonl')))
      .where((line) => LogEvent.decode(line).id == receipt.id)
      .toList();
  check(
    matching.length == 1 && matching.single == receipt.raw,
    'exactly one canonical event with unchanged receipt',
  );
}

// Fault injection lives exclusively in this test target.
class _FaultFolder implements LogFolder, RangeLogFolder {
  _FaultFolder(this.inner);
  final LogFolder inner;
  bool _fail = false, _afterWrite = false;
  void arm(bool afterWrite) {
    _fail = true;
    _afterWrite = afterWrite;
  }

  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List?> readFrom(String name, int offset) =>
      inner is RangeLogFolder
      ? (inner as RangeLogFolder).readFrom(name, offset)
      : Future.value(null);
  @override
  Future<void> create(String name, Uint8List bytes) =>
      inner.create(name, bytes);
  @override
  Future<void> append(String name, Uint8List bytes) async {
    if (_fail) {
      _fail = false;
      if (_afterWrite) await inner.append(name, bytes);
      throw FolderAccessFailure('TEST ONLY synthetic unknown append outcome');
    }
    await inner.append(name, bytes);
  }
}
