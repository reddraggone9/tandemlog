import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;
import 'package:tandemlog/storage/task_store.dart';
import 'package:uuid/uuid.dart';

import '../integration_test/native_text_fixtures.dart';

class ProbeFolder extends LocalLogFolder {
  ProbeFolder(super.location);
  bool armed = false;
  String mode = 'valid';
  final entered = <String>[];
  final release = Completer<void>();
  final overlap = Completer<void>();
  final firstSettled = Completer<void>();
  int active = 0, peak = 0;
  bool strictWhileActive = false;

  @override
  Future<Uint8List?> readFromBounded(
    String name,
    int offset,
    int maximumBytes,
  ) async {
    if (!armed || !name.endsWith('.applog')) {
      return super.readFromBounded(name, offset, maximumBytes);
    }
    entered.add(name);
    active++;
    if (active > peak) peak = active;
    if (active > 1 && !overlap.isCompleted) overlap.complete();
    final first = entered.length == 1;
    try {
      // The first failure finishes while the other independent probes remain
      // blocked. Strict fallback must not race those outstanding provider reads.
      if (!first || mode == 'valid') await release.future;
      if (first && mode == 'error') throw FolderAccessFailure('probe failure');
      final bytes = await super.readFromBounded(name, offset, maximumBytes);
      if (first && mode == 'mismatch') return Uint8List(bytes!.length);
      return bytes;
    } finally {
      active--;
      if (first) firstSettled.complete();
    }
  }

  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) {
    if (armed && name.endsWith('.applog') && active > 0) {
      strictWhileActive = true;
    }
    return super.readBounded(name, maximumBytes);
  }
}

void main() {
  for (final mode in ['valid', 'mismatch', 'error', 'corrupt']) {
    test('parallel seal probes drain before $mode restore/fallback', () async {
      final root = await Directory.systemTemp.createTemp('parallel-restore-');
      addTearDown(() => root.delete(recursive: true));
      final folder = ProbeFolder(
        (await Directory('${root.path}/logs').create()).path,
      );
      Future<TaskStore> open(String profile) => openNativeFixtureStore(
        folder,
        profile,
        nativeLibraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final a = await open('${root.path}/a');
      final b = await open('${root.path}/b');
      final c = await open('${root.path}/c');
      await a.refresh();
      final reused = a.unified!.snapshot.records.length;
      // Preserve the same installation identity and all protected store heads.
      final copy = await Directory('${root.path}/copy').create();
      await for (final entry in Directory('${root.path}/a').list()) {
        if (entry is File) {
          await entry.copy('${copy.path}/${entry.uri.pathSegments.last}');
        }
      }
      await a.close(sealCache: false);
      // Append a genuine peer record after A's sealed head.
      final person = const Uuid().v4();
      await b.command(person, 'user.created', {'name': 'Appended peer'});
      await b.close();
      await c.close();
      if (mode == 'corrupt') {
        final file = File('${folder.location}/${c.unified!.writer}.applog');
        final bytes = await file.readAsBytes();
        // Change an exact sealed last record without changing its length.
        bytes[bytes.length - 4] = bytes[bytes.length - 4] == 97 ? 98 : 97;
        await file.writeAsBytes(bytes, flush: true);
      }
      folder
        ..armed = true
        ..mode = mode;
      final pending = open(copy.path);
      try {
        await folder.overlap.future.timeout(const Duration(seconds: 2));
        expect(folder.peak, greaterThan(1));
        expect(folder.peak, lessThanOrEqualTo(4));
        if (mode == 'mismatch' || mode == 'error') {
          await folder.firstSettled.future;
          await Future<void>.delayed(Duration.zero);
          expect(folder.active, greaterThan(0));
        }
        expect(folder.strictWhileActive, isFalse);
      } finally {
        folder.release.complete();
      }
      if (mode == 'corrupt') {
        await expectLater(pending, throwsA(isA<FormatFailure>()));
        expect(folder.active, 0);
        expect(folder.strictWhileActive, isFalse);
        return;
      }
      final warm = await pending;
      expect(folder.active, 0);
      expect(folder.strictWhileActive, isFalse);
      expect(
        warm.unified!.snapshot.records.any(
          (r) => r.effects.any((e) => e.task?.entity == person),
        ),
        isTrue,
      );
      expect(warm.unified!.decodedCacheReuses, mode == 'valid' ? reused : 0);
      await warm.close(sealCache: false);
    });
  }
}
