import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/log_folder.dart';

class _ListingDirectory implements Directory {
  _ListingDirectory(this.entries);
  final Stream<FileSystemEntity> entries;
  bool? recursiveArgument, followLinksArgument;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    recursiveArgument = recursive;
    followLinksArgument = followLinks;
    return entries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected directory operation: $invocation');
}

class _Metadata implements FileStat {
  _Metadata(int index)
    : size = 100 + index,
      modified = DateTime.fromMicrosecondsSinceEpoch(1000 + index, isUtc: true),
      changed = DateTime.fromMicrosecondsSinceEpoch(2000 + index, isUtc: true);
  @override
  final int size;
  @override
  final DateTime modified, changed;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected metadata field: $invocation');
}

class _Stats {
  final started = <String>[];
  final completions = <String, Completer<FileStat>>{};
  final barriers = <int, Completer<void>>{};
  final synchronousFailures = <String, Object>{};
  int active = 0, maximumActive = 0;

  Future<FileStat> call(String path) {
    started.add(path);
    final failure = synchronousFailures[path];
    if (failure != null) throw failure;
    active++;
    if (active > maximumActive) maximumActive = active;
    final completion = completions[path] = Completer<FileStat>();
    for (final entry in barriers.entries) {
      if (started.length >= entry.key && !entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    return completion.future.whenComplete(() => active--);
  }

  Future<void> untilStarted(int count) {
    if (started.length >= count) return Future.value();
    return (barriers[count] ??= Completer<void>()).future.timeout(
      const Duration(seconds: 2),
    );
  }
}

Future<List<LogFileInfo>> _list(_ListingDirectory directory, _Stats stats) =>
    IOOverrides.runZoned(
      () => LocalLogFolder('synthetic-list-fixture').list(),
      createDirectory: (_) => directory,
      stat: stats.call,
    );

Future<({Object? error, StackTrace? stack})> _observeFailure(
  Future<List<LogFileInfo>> future,
) async {
  try {
    await future;
    return (error: null, stack: null);
  } catch (error, stack) {
    return (error: error, stack: stack);
  }
}

void main() {
  test(
    'empty and non-file-only directories produce no rows or stat calls',
    () async {
      for (final entries in <List<FileSystemEntity>>[
        [],
        [Link('fixture/ignored-link'), Directory('fixture/ignored-directory')],
      ]) {
        final stats = _Stats();
        final result = await _list(
          _ListingDirectory(Stream.fromIterable(entries)),
          stats,
        );
        expect(result, isEmpty);
        expect(stats.started, isEmpty);
        expect(stats.active, 0);
        expect(stats.maximumActive, 0);
      }
    },
  );

  test(
    'at most sixteen stats; unordered completion retains entry order and metadata',
    () async {
      final files = [
        for (var i = 0; i < 40; i++) File('fixture/file-$i.applog'),
      ];
      final directory = _ListingDirectory(
        Stream.fromIterable([
          files[0],
          Link('fixture/ignored-link'),
          ...files.skip(1),
        ]),
      );
      final stats = _Stats();
      final listing = _list(directory, stats);
      await stats.untilStarted(16);
      await Future<void>.value();
      expect(stats.started, hasLength(16));
      expect(stats.maximumActive, 16);
      for (var i = 15; i >= 0; i--) {
        stats.completions[files[i].path]!.complete(_Metadata(i));
      }
      await stats.untilStarted(32);
      expect(stats.maximumActive, 16);
      for (var i = 31; i >= 16; i--) {
        stats.completions[files[i].path]!.complete(_Metadata(i));
      }
      await stats.untilStarted(40);
      for (var i = 39; i >= 32; i--) {
        stats.completions[files[i].path]!.complete(_Metadata(i));
      }
      final result = await listing;
      expect(result.map((row) => row.name), [
        for (var i = 0; i < 40; i++) 'file-$i.applog',
      ]);
      for (var i = 0; i < result.length; i++) {
        expect(result[i].stamp, '${100 + i}:${1000 + i}:${2000 + i}');
        expect(result[i].size, 100 + i);
        expect(result[i].identity, isNull);
      }
      expect(stats.active, 0);
      expect(directory.recursiveArgument, isFalse);
      expect(directory.followLinksArgument, isTrue);
    },
  );

  test(
    'stat errors settle the whole batch and retain first entry error and stack',
    () async {
      final files = [
        for (var i = 0; i < 16; i++) File('fixture/error-$i.applog'),
      ];
      final stats = _Stats();
      final observed = _observeFailure(
        _list(_ListingDirectory(Stream.fromIterable(files)), stats),
      );
      var finished = false;
      unawaited(observed.then((_) => finished = true));
      await stats.untilStarted(16);
      final first = StateError('first listed failure');
      stats.completions[files[5].path]!.completeError(
        StateError('completed first'),
        StackTrace.fromString('later-entry-stack'),
      );
      stats.completions[files[1].path]!.completeError(
        first,
        StackTrace.fromString('first-entry-stack'),
      );
      await Future<void>.value();
      expect(finished, isFalse);
      for (var i = 0; i < 16; i++) {
        if (i != 1 && i != 5) {
          stats.completions[files[i].path]!.complete(_Metadata(i));
        }
      }
      final failure = await observed;
      expect(failure.error, same(first));
      expect(failure.stack.toString(), contains('first-entry-stack'));
      expect(stats.active, 0);
    },
  );

  test(
    'directory stream failure waits for outstanding stats and keeps its stack',
    () async {
      final files = [File('fixture/one'), File('fixture/two')];
      final stream = StreamController<FileSystemEntity>();
      final stats = _Stats();
      final observed = _observeFailure(
        _list(_ListingDirectory(stream.stream), stats),
      );
      final streamError = StateError('directory stream failure');
      stream.add(files[0]);
      stream.add(files[1]);
      stream.addError(
        streamError,
        StackTrace.fromString('directory-stream-stack'),
      );
      await stats.untilStarted(2);
      stats.completions[files[0].path]!.complete(_Metadata(0));
      stats.completions[files[1].path]!.complete(_Metadata(1));
      final failure = await observed;
      expect(failure.error, same(streamError));
      expect(failure.stack.toString(), contains('directory-stream-stack'));
      expect(stats.active, 0);
      await stream.close();
    },
  );

  test(
    'an earlier listed stat failure still precedes a later stream failure',
    () async {
      final files = [File('fixture/first'), File('fixture/second')];
      final stream = StreamController<FileSystemEntity>();
      final stats = _Stats();
      final observed = _observeFailure(
        _list(_ListingDirectory(stream.stream), stats),
      );
      final fileError = StateError('earlier file failure');
      stream.add(files[0]);
      stream.add(files[1]);
      stream.addError(
        StateError('later stream failure'),
        StackTrace.fromString('stream-stack'),
      );
      await stats.untilStarted(2);
      stats.completions[files[1].path]!.complete(_Metadata(1));
      stats.completions[files[0].path]!.completeError(
        fileError,
        StackTrace.fromString('earlier-file-stack'),
      );
      final failure = await observed;
      expect(failure.error, same(fileError));
      expect(failure.stack.toString(), contains('earlier-file-stack'));
      expect(stats.active, 0);
      await stream.close();
    },
  );

  test(
    'synchronous stat failure is observed while later reads are drained',
    () async {
      final files = [File('fixture/synchronous'), File('fixture/pending')];
      final stats = _Stats();
      final expected = StateError('synchronous stat failure');
      stats.synchronousFailures[files[0].path] = expected;
      final observed = _observeFailure(
        _list(_ListingDirectory(Stream.fromIterable(files)), stats),
      );
      await stats.untilStarted(2);
      stats.completions[files[1].path]!.complete(_Metadata(1));
      expect((await observed).error, same(expected));
      expect(stats.active, 0);
    },
  );

  test(
    'real local listing keeps current names, stamps, sizes and directory filtering',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tandemlog-list-batch-',
      );
      try {
        final a = await File('${root.path}/a.applog').writeAsString('a');
        final b = await File('${root.path}/b.json').writeAsString('longer');
        await Directory('${root.path}/ignored-directory').create();
        final expected = {
          for (final f in [a, b]) f.uri.pathSegments.last: await f.stat(),
        };
        final rows = await LocalLogFolder(root.path).list();
        expect(
          rows.map((r) => r.name),
          unorderedEquals(['a.applog', 'b.json']),
        );
        for (final row in rows) {
          final s = expected[row.name]!;
          expect(
            row.stamp,
            '${s.size}:${s.modified.microsecondsSinceEpoch}:${s.changed.microsecondsSinceEpoch}',
          );
          expect(row.size, s.size);
          expect(row.identity, isNull);
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
