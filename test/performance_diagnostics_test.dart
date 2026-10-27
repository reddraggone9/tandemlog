import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_durability.dart';
import '../tool/performance/operation_diagnostics.dart';

class _DurabilityOwner extends LocalDurability {
  final calls = <(String, Object, Object?)>[];
  Object? failure;
  @override
  Future<Directory> ensureDirectoryDurable(Directory directory) async {
    calls.add(('ensure', directory, null));
    return directory;
  }

  @override
  Future<void> syncParentAfterCreate(FileSystemEntity entity) async {
    calls.add(('parent', entity, null));
  }

  @override
  Future<void> writeAtomicDurable(File file, List<int> bytes) async {
    calls.add(('atomic', file, bytes));
  }

  @override
  Future<void> createFileDurable(File file, List<int> bytes) async {
    calls.add(('create', file, bytes));
  }

  @override
  Future<void> appendFileDurable(File file, List<int> bytes) async {
    calls.add(('append', file, bytes));
    if (failure != null) throw failure!;
  }
}

void main() {
  test(
    'diagnosis delegates every durability operation to the same owner',
    () async {
      final owner = _DurabilityOwner();
      final measured = BenchmarkDurabilityDiagnostics(owner);
      final directory = Directory('unused-diagnostic-directory');
      final file = File('unused-diagnostic-file');
      final bytes = <int>[1, 2, 3];
      expect(
        identical(await measured.ensureDirectoryDurable(directory), directory),
        isTrue,
      );
      await measured.syncParentAfterCreate(file);
      await measured.writeAtomicDurable(file, bytes);
      await measured.createFileDurable(file, bytes);
      await measured.appendFileDurable(file, bytes);
      expect(owner.calls.map((call) => call.$1), [
        'ensure',
        'parent',
        'atomic',
        'create',
        'append',
      ]);
      expect(identical(owner.calls.first.$2, directory), isTrue);
      for (final call in owner.calls.skip(1)) {
        expect(identical(call.$2, file), isTrue);
      }
      for (final call in owner.calls.skip(2)) {
        expect(identical(call.$3, bytes), isTrue);
      }
      expect(measured.appendCalls, 1);
      expect(measured.appendMicroseconds, greaterThanOrEqualTo(0));
    },
  );

  test(
    'failed durability remains failed and its attempt is recorded',
    () async {
      final owner = _DurabilityOwner();
      final measured = BenchmarkDurabilityDiagnostics(owner);
      final failure = FileSystemException('unconfirmed append');
      owner.failure = failure;
      await expectLater(
        measured.appendFileDurable(File('unused'), [4]),
        throwsA(same(failure)),
      );
      expect(owner.calls.single.$1, 'append');
      expect(measured.appendCalls, 1);
    },
  );

  test(
    'optional resource probes report counters without requiring a platform',
    () {
      final counters = benchmarkResourceCounters();
      expect(counters.values, everyElement(greaterThanOrEqualTo(0)));
      expect(
        counters.keys,
        everyElement(anyOf(startsWith('cgroup.'), startsWith('processIo.'))),
      );
      if (!Platform.isLinux) expect(counters, isEmpty);
    },
  );
}
