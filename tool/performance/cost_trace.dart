import 'dart:io';
import 'dart:typed_data';

import 'package:tandemlog/storage/local_durability.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/log_folder.dart';

/// Diagnostic intervals, not kernel-I/O service time or causal async parents.
/// All timestamps share the probe's monotonic clock; overlaps remain explicit.
class ProbeCostTrace {
  ProbeCostTrace(this.now, {this.profileHookAttachment = 'caller-defined'});
  final int Function() now;
  final String profileHookAttachment;
  final spans = <Map<String, Object?>>[];
  final actions = <Map<String, Object?>>[];
  static const maximumSpans = 4096;
  int droppedSpans = 0;
  void reset() {
    spans.clear();
    actions.clear();
    droppedSpans = 0;
  }

  /// Partitions the same elapsed interval with a fixed overlap precedence.
  /// This is interval coverage, not a claim about causal asynchronous parents.
  /// In particular, queued connection work can belong to an earlier action.
  Map<String, Object?> partition(int start, int end) {
    if (end < start) throw ArgumentError('Negative diagnostic interval.');
    const categories = [
      'sqliteApi',
      'nativeApi',
      'durabilityApi',
      'providerApi',
      'queueWait',
      'semanticValidationOther',
      'transactionBodyOther',
      'transactionOther',
      'historyRefreshOther',
      'unclassified',
    ];
    String category(String operation) {
      if (operation.startsWith('sqlite.api.') ||
          {
            'sqlite.begin',
            'sqlite.commit',
            'sqlite.rollback',
          }.contains(operation)) {
        return 'sqliteApi';
      }
      if (operation.startsWith('durability.')) return 'durabilityApi';
      if (operation.startsWith('native.api.')) return 'nativeApi';
      if (operation.startsWith('provider.')) return 'providerApi';
      if (operation == 'profile.queueWait') return 'queueWait';
      if (operation == 'history.semanticValidation') {
        return 'semanticValidationOther';
      }
      if (operation == 'sqlite.body') return 'transactionBodyOther';
      if (operation.startsWith('sqlite.')) return 'transactionOther';
      if (operation == 'history.refresh') return 'historyRefreshOther';
      return 'unclassified';
    }

    final edges = <int, Map<String, int>>{};
    final operations = <String, Map<String, int>>{};
    for (final span in spans) {
      final a = span['startUs'] as int, b = span['endUs'] as int;
      if (b < a) throw StateError('Negative diagnostic span.');
      if (b <= start || a >= end) continue;
      final left = a < start ? start : a, right = b > end ? end : b;
      final operation = span['operation'] as String;
      final item = operations.putIfAbsent(
        operation,
        () => {'calls': 0, 'inclusiveUs': 0, 'failedCalls': 0},
      );
      item['calls'] = item['calls']! + 1;
      item['inclusiveUs'] = item['inclusiveUs']! + right - left;
      if (span['succeeded'] == false) {
        item['failedCalls'] = item['failedCalls']! + 1;
      }
      final key = category(operation);
      for (final edge in [(left, 1), (right, -1)]) {
        final changes = edges.putIfAbsent(edge.$1, () => {});
        changes[key] = (changes[key] ?? 0) + edge.$2;
      }
    }
    edges.putIfAbsent(start, () => {});
    edges.putIfAbsent(end, () => {});
    final active = <String, int>{};
    final exclusive = {for (final c in categories) c: 0};
    var previous = start;
    for (final point in edges.keys.toList()..sort()) {
      final key = categories.firstWhere(
        (c) => (active[c] ?? 0) > 0,
        orElse: () => 'unclassified',
      );
      exclusive[key] = exclusive[key]! + point - previous;
      for (final change in edges[point]!.entries) {
        active[change.key] = (active[change.key] ?? 0) + change.value;
      }
      previous = point;
    }
    final total = exclusive.values.fold<int>(0, (a, b) => a + b);
    return {
      'complete': droppedSpans == 0,
      'totalUs': end - start,
      'exclusiveCoverageUs': exclusive,
      'coverageSumUs': total,
      'reconciled': total == end - start,
      'overlapPrecedence': categories,
      'causalParentAttributionClaimed': false,
      'operations': operations,
      'inclusiveOperationTotalsMustNotBeSummed': true,
    };
  }

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
      record({
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

  void record(Map<String, Object?> span) {
    if (spans.length >= maximumSpans) {
      droppedSpans++;
    } else {
      spans.add(span);
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
    'sqliteTraceUnavailable': 'Pinned SQLite uses SQLITE_OMIT_TRACE',
    'sqliteApiWallIncludesBindingAndResultDecoding': true,
    'sqliteApiCountsAreNotEngineStatementCounts': true,
    'nativeApiWallIncludesJSONFFIAndNativeWork': true,
    'sqliteBodyIncludesDartWork': true,
    'profileHookAttachment': profileHookAttachment,
    'notMeasured': [
      'Dart validation/allocation outside instrumented API boundaries',
      'SQLite per-statement duration and row counts',
      'SQLite raw/cursor stepping and direct native SQL',
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
  ProbeLocalLogFolder(super.location, this.trace, {LocalDurability? durability})
    : super(
        durability: _ProbeDurability(
          durability ?? LocalDurability.shared,
          trace,
        ),
      );
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

class _ProfileTraceToken {
  _ProfileTraceToken(this.operation, this.start);
  final String operation;
  final int start;
}

class ProbeProfileDiagnostics implements ProfileDiagnosticObserver {
  ProbeProfileDiagnostics(this.trace);
  final ProbeCostTrace trace;
  @override
  Object start(String operation) => _ProfileTraceToken(operation, trace.now());
  @override
  void finish(Object token, bool succeeded) {
    final t = token as _ProfileTraceToken;
    trace.record({
      'operation': t.operation,
      'startUs': t.start,
      'endUs': trace.now(),
      'succeeded': succeeded,
    });
  }
}
