// Synthetic storage benchmark. Run with Dart AOT for release-mode timing.
// Uses only fresh temporary folders, removes only its own fixtures, and prints
// per-operation counts/phases. Never supply a user workspace.
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

class CountFolder implements LogFolder {
  final LocalLogFolder inner;
  int lists = 0, reads = 0, appends = 0, bytes = 0, appendUs = 0;
  CountFolder(this.inner);
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() {
    lists++;
    return inner.list();
  }

  @override
  Future<Uint8List> read(String n) async {
    reads++;
    final b = await inner.read(n);
    bytes += b.length;
    return b;
  }

  @override
  Future<void> create(String n, Uint8List b) => inner.create(n, b);
  @override
  Future<void> append(String n, Uint8List b) async {
    appends++;
    final w = Stopwatch()..start();
    await inner.append(n, b);
    appendUs += w.elapsedMicroseconds;
  }

  void reset() {
    lists = reads = appends = bytes = appendUs = 0;
  }

  String stats() =>
      'list=$lists read=$reads append=$appends readBytes=$bytes appendMs=${appendUs / 1000}';
}

Future<void> main() async {
  final output = <Map<String, dynamic>>[];
  for (final n in [1, 30, 100]) {
    final root = await Directory.systemTemp.createTemp('rc5-perf-');
    await Directory('${root.path}/logs').create();
    final f = CountFolder(LocalLogFolder('${root.path}/logs'));
    final s = await TaskStore.open(f, '${root.path}/private');
    final u = const Uuid().v4();
    await s.command(u, 'user.created', {'name': 'Test'});
    final ids = <String>[];
    f.reset();
    var w = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      ids.add(const Uuid().v4());
    }
    final captureTx = s.cacheTransactions;
    await s.createTasks({for (var i = 0; i < n; i++) ids[i]: 'Task $i'}, u);
    output.add({
      'operation': 'capture',
      'n': n,
      'us': w.elapsedMicroseconds,
      'lists': f.lists,
      'reads': f.reads,
      'appends': f.appends,
      'readBytes': f.bytes,
      'appendUs': f.appendUs,
      'cacheTransactions': s.cacheTransactions - captureTx,
      'lastBatchTiming': s.lastBatchTiming,
    });
    stdout.writeln(
      'capture n=$n ms=${w.elapsedMicroseconds / 1000} ${f.stats()}',
    );
    final anchor = const Uuid().v4();
    await s.command(anchor, 'task.created', {
      'title': 'Anchor',
      'description': '',
      'assignee': u,
    });
    final snapshot = s.taskSnapshot;
    f.reset();
    w = Stopwatch()..start();
    final r = await s.moveBlockBefore(
      ids,
      anchor,
      expectedTaskSnapshot: snapshot,
      canCommit: () => true,
    );
    stdout.writeln(
      'move n=$n ms=${w.elapsedMicroseconds / 1000} ${f.stats()} committed=${r.committedIds.length}',
    );
    output.add({
      'operation': 'move',
      'n': n,
      'us': w.elapsedMicroseconds,
      'lists': f.lists,
      'reads': f.reads,
      'appends': f.appends,
      'readBytes': f.bytes,
      'appendUs': f.appendUs,
      'lastBatchTiming': s.lastBatchTiming,
    });
    final other = const Uuid().v4();
    await s.command(other, 'user.created', {'name': 'Other'});
    for (final op in ['edit', 'tag', 'delete']) {
      final receipts = <OperationReceipt>[];
      final snap = s.taskSnapshot;
      f.reset();
      w = Stopwatch()..start();
      if (op == 'delete') {
        await s.deleteTasks(
          ids,
          expectedTaskSnapshot: snap,
          onPrepared: receipts.add,
        );
      } else {
        await s.bulkEdit(
          ids,
          op == 'edit'
              ? BulkTaskEdit(assignee: other)
              : BulkTaskEdit(addTags: ['review']),
          expectedTaskSnapshot: snap,
          onPrepared: receipts.add,
        );
      }
      stdout.writeln(
        '$op n=$n ms=${w.elapsedMicroseconds / 1000} ${f.stats()}',
      );
      output.add({
        'operation': op,
        'n': n,
        'us': w.elapsedMicroseconds,
        'lists': f.lists,
        'reads': f.reads,
        'appends': f.appends,
        'readBytes': f.bytes,
        'appendUs': f.appendUs,
        'lastBatchTiming': s.lastBatchTiming,
      });
      f.reset();
      w = Stopwatch()..start();
      await s.undoOperations(receipts.map((r) => r.id).toList());
      stdout.writeln(
        'undo-$op n=$n ms=${w.elapsedMicroseconds / 1000} ${f.stats()}',
      );
      output.add({
        'operation': 'undo-$op',
        'n': n,
        'us': w.elapsedMicroseconds,
        'lists': f.lists,
        'reads': f.reads,
        'appends': f.appends,
        'readBytes': f.bytes,
        'appendUs': f.appendUs,
        'lastBatchTiming': s.lastBatchTiming,
      });
    }
    await s.close();
    await root.delete(recursive: true);
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'methodology':
          'Isolated synthetic Linux storage fixture; same process across 1/30/100 tasks; no UI timing; local flush and SQLite FULL',
      'results': output,
    }),
  );
}
