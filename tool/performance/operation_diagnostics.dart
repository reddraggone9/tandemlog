import 'dart:io';

import 'package:tandemlog/storage/local_durability.dart';

/// Additive diagnostics only. Every operation delegates to the same production
/// durability owner, preserving its directory/stream bookkeeping and barriers.
class BenchmarkDurabilityDiagnostics extends LocalDurability {
  BenchmarkDurabilityDiagnostics(this.delegate);
  final LocalDurability delegate;
  int appendCalls = 0, appendMicroseconds = 0;
  @override
  Future<Directory> ensureDirectoryDurable(Directory directory) =>
      delegate.ensureDirectoryDurable(directory);
  @override
  Future<void> syncParentAfterCreate(FileSystemEntity entity) =>
      delegate.syncParentAfterCreate(entity);
  @override
  Future<void> writeAtomicDurable(File file, List<int> bytes) =>
      delegate.writeAtomicDurable(file, bytes);
  @override
  Future<void> createFileDurable(File file, List<int> bytes) =>
      delegate.createFileDurable(file, bytes);
  @override
  Future<void> appendFileDurable(File file, List<int> bytes) async {
    final watch = Stopwatch()..start();
    try {
      await delegate.appendFileDurable(file, bytes);
    } finally {
      appendCalls++;
      appendMicroseconds += watch.elapsedMicroseconds;
    }
  }
}

/// Brackets (rather than partitions) the timed action. Probes run outside its
/// stopwatch and include their own small counter-reading interval. Cgroup CPU
/// includes the benchmark's threads and waiting controller, not sibling services.
/// Process I/O counts are not provider calls or fsync timings.
Map<String, int> benchmarkResourceCounters() {
  if (!Platform.isLinux) return const {};
  final result = <String, int>{};
  void read(String path, String prefix) {
    try {
      for (final line in File(path).readAsLinesSync()) {
        final fields = line.replaceAll(':', ' ').trim().split(RegExp(r'\s+'));
        if (fields.length == 2) {
          final value = int.tryParse(fields[1]);
          if (value != null) result['$prefix${fields[0]}'] = value;
        }
      }
    } on FileSystemException {
      // Optional diagnosis may be unavailable; absence is explicit in output.
    }
  }

  try {
    final line = File(
      '/proc/self/cgroup',
    ).readAsLinesSync().firstWhere((line) => line.startsWith('0::'));
    final path = line.substring(3);
    if (path.startsWith('/') && !path.split('/').contains('..')) {
      read('/sys/fs/cgroup$path/cpu.stat', 'cgroup.');
    }
  } on FileSystemException {
    // The release runner separately enforces actual cgroup resource bounds.
  } on StateError {
    // No unified cgroup on this diagnostic platform.
  }
  read('/proc/self/io', 'processIo.');
  return result;
}
