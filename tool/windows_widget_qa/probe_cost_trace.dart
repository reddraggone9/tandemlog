import 'dart:io';
import 'dart:typed_data';

import 'package:tandemlog/storage/local_durability.dart';
import 'package:tandemlog/storage/log_folder.dart';

/// Diagnostic intervals, not kernel-I/O service time or causal async parents.
/// All timestamps share the probe's monotonic clock; overlaps remain explicit.
class ProbeCostTrace {
  ProbeCostTrace(this.now);
  final int Function() now;
  final spans = <Map<String, Object?>>[];
  final actions = <Map<String, Object?>>[];
  static const maximumSpans = 4096;
  int droppedSpans = 0;
  Future<T> measure<T>(
    String operation,
    Future<T> Function() work, {
    String? file,
    int? offset,
    int? limit,
    int? inputBytes,
  }) async {
    final start = now();
    Object? result;
    var succeeded = false;
    try {
      final value = await work();
      result = value;
      succeeded = true;
      return value;
    } finally {
      final end = now();
      if (spans.length >= maximumSpans) {
        droppedSpans++;
      } else {
        spans.add({
          'operation': operation,
          'startUs': start,
          'endUs': end,
          'succeeded': succeeded,
          'file': file,
          'offset': offset,
          'maximumBytes': limit,
          'inputBytes': inputBytes,
          if (result is Uint8List) 'returnedBytes': result.length,
          if (result is List<LogFileInfo>) 'returnedFiles': result.length,
        });
      }
    }
  }

  void action(String name, int start, int end) =>
      actions.add({'name': name, 'startUs': start, 'endUs': end});

  Map<String, Object?> report() => {
    'complete': droppedSpans == 0,
    'droppedSpans': droppedSpans,
    'actions': actions,
    'spans': spans,
    'timestampsShareProbeClock': true,
    'inclusiveOverlappingIntervalsDoNotSum': true,
    'providerAwaitIsNotKernelServiceTime': true,
    'causalParentAttributionClaimed': false,
    'notMeasured': [
      'in-memory/native validation and allocation',
      'SQLite statements/transactions/commit',
      'separate write versus durability barrier',
      'direct tail-truncate flush and metadata syscalls',
      'render/compositor and scheduler attribution',
    ],
  };
}

/// Subclassing preserves every production range/replacement/tail capability.
/// Only direct read/list entrypoints are timed; readFrom delegates to the
/// overridden readFromBounded once, avoiding an extra counted read wrapper.
class ProbeLocalLogFolder extends LocalLogFolder {
  ProbeLocalLogFolder(super.location, this.trace)
    : super(durability: _ProbeDurability(LocalDurability.shared, trace));
  final ProbeCostTrace trace;
  @override
  Future<List<LogFileInfo>> list() =>
      trace.measure('provider.list', super.list);
  @override
  Future<Uint8List> read(String name) =>
      trace.measure('provider.read', () => super.read(name), file: name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) => trace.measure(
    'provider.readBounded',
    () => super.readBounded(name, maximumBytes),
    file: name,
    limit: maximumBytes,
  );
  @override
  Future<Uint8List?> readFromBounded(
    String name,
    int offset,
    int maximumBytes,
  ) => trace.measure(
    'provider.readFromBounded',
    () => super.readFromBounded(name, offset, maximumBytes),
    file: name,
    offset: offset,
    limit: maximumBytes,
  );
}

class _ProbeDurability extends LocalDurability {
  _ProbeDurability(this.delegate, this.trace);
  final LocalDurability delegate;
  final ProbeCostTrace trace;
  @override
  Future<Directory> ensureDirectoryDurable(Directory directory) =>
      delegate.ensureDirectoryDurable(directory);
  @override
  Future<void> syncParentAfterCreate(FileSystemEntity entity) =>
      delegate.syncParentAfterCreate(entity);
  @override
  Future<void> writeAtomicDurable(File file, List<int> bytes) => trace.measure(
    'durability.atomicWrite+barrier',
    () => delegate.writeAtomicDurable(file, bytes),
    inputBytes: bytes.length,
  );
  @override
  Future<void> createFileDurable(File file, List<int> bytes) => trace.measure(
    'durability.create+barrier',
    () => delegate.createFileDurable(file, bytes),
    inputBytes: bytes.length,
  );
  @override
  Future<void> appendFileDurable(File file, List<int> bytes) => trace.measure(
    'durability.append+barrier',
    () => delegate.appendFileDurable(file, bytes),
    inputBytes: bytes.length,
  );
}
