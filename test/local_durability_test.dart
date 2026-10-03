import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/local_durability.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:tandemlog/storage/profile_lock.dart';

class _Calls implements LinuxDurabilityCalls {
  final operations = <String>[];
  final descriptors = <int, String>{};
  final directories = <int>{};
  final files = <String>{};
  final written = <int>[];
  int nextDescriptor = 10;
  @override
  int errno = 0;
  bool failDirectorySync = false;
  bool failFileSync = false;
  bool failClose = false;
  bool failDirectoryOpen = false;
  bool interruptSync = false;
  bool interruptWrite = false;
  int? maxWrite;
  void Function(String)? onDirectorySync;

  @override
  int open(String path, int flags, int mode) {
    final directory = flags & 0x10000 != 0;
    operations.add('open:${directory ? 'directory' : 'file'}:$path:$flags');
    if (directory && failDirectoryOpen) {
      errno = 13;
      return -1;
    }
    if (flags & 0x80 != 0 && !files.add(path)) {
      errno = 17;
      return -1;
    }
    final descriptor = nextDescriptor++;
    descriptors[descriptor] = path;
    if (directory) directories.add(descriptor);
    return descriptor;
  }

  @override
  int write(int descriptor, Pointer<Uint8> bytes, int length) {
    operations.add('write:$descriptor:$length');
    if (interruptWrite) {
      interruptWrite = false;
      errno = 4;
      return -1;
    }
    final size = maxWrite == null || maxWrite! > length ? length : maxWrite!;
    written.addAll(bytes.asTypedList(size));
    return size;
  }

  @override
  int fsync(int descriptor) {
    final directory = directories.contains(descriptor);
    operations.add('fsync:${directory ? 'directory' : 'file'}:$descriptor');
    if (interruptSync) {
      interruptSync = false;
      errno = 4;
      return -1;
    }
    if (directory) onDirectorySync?.call(descriptors[descriptor]!);
    if (directory ? failDirectorySync : failFileSync) {
      errno = 5;
      return -1;
    }
    return 0;
  }

  @override
  int close(int descriptor) {
    operations.add('close:$descriptor');
    if (failClose) {
      errno = 4;
      return -1;
    }
    return 0;
  }
}

Matcher _failure(String operation, [int? errno]) => isA<FileSystemException>()
    .having((error) => error.message, 'operation', contains(operation))
    .having((error) => error.osError?.errorCode, 'errno', errno ?? anything);

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-durability-');
  });
  tearDown(() => root.delete(recursive: true));

  Future<LocalDurability> forFiles(_Calls calls) async {
    final durability = LocalDurability(linux: true, linuxCalls: calls);
    await durability.ensureDirectoryDurable(root);
    calls.operations.clear();
    calls.descriptors.clear();
    calls.directories.clear();
    calls.nextDescriptor = 10;
    return durability;
  }

  test('exclusive create writes and flushes file before its parent', () async {
    final calls = _Calls()..maxWrite = 2;
    final durability = await forFiles(calls);
    final file = File('${root.path}/manifest.json');
    await durability.createFileDurable(file, utf8.encode('first'));
    expect(utf8.decode(calls.written), 'first');
    expect(calls.operations, [
      'open:file:${file.path}:${1 | 0x40 | 0x80 | 0x80000}',
      'write:10:5',
      'write:10:3',
      'write:10:1',
      'fsync:file:10',
      'close:10',
      'open:directory:${root.path}:${0x10000 | 0x80000}',
      'fsync:directory:11',
      'close:11',
    ]);
    await expectLater(
      durability.createFileDurable(file, utf8.encode('second')),
      throwsA(_failure('open', 17)),
    );
    expect(utf8.decode(calls.written), 'first');
  });

  test('new append barriers and existing stream first-use barrier', () async {
    final calls = _Calls();
    final durability = await forFiles(calls);
    final file = File('${root.path}/writer.jsonl');
    await durability.appendFileDurable(file, [1]);
    expect(
      calls.operations.where((op) => op.startsWith('fsync:directory')),
      hasLength(1),
    );
    calls.operations.clear();
    await durability.appendFileDurable(file, [2]);
    expect(
      calls.operations.where((op) => op.startsWith('fsync:file')),
      hasLength(1),
    );
    expect(
      calls.operations.where((op) => op.startsWith('fsync:directory')),
      isEmpty,
    );
    final reopened = await forFiles(calls);
    calls.operations.clear();
    await reopened.appendFileDurable(file, [3]);
    expect(
      calls.operations.where((op) => op.startsWith('fsync:directory')),
      hasLength(1),
    );
    expect(calls.written, [1, 2, 3]);
  });

  test('interrupted writes and fsync retry; close never retries', () async {
    final calls = _Calls();
    final durability = await forFiles(calls);
    calls
      ..interruptWrite = true
      ..interruptSync = true;
    await durability.createFileDurable(File('${root.path}/a'), [7]);
    expect(calls.written, [7]);
    expect(calls.operations.where((op) => op == 'write:10:1'), hasLength(2));
    expect(calls.operations.where((op) => op == 'fsync:file:10'), hasLength(2));
    calls.failClose = true;
    await expectLater(
      durability.syncParentAfterCreate(File('${root.path}/a')),
      throwsA(_failure('close', 4)),
    );
    expect(calls.operations.where((op) => op == 'close:12'), hasLength(1));
  });

  test(
    'file fsync failure closes descriptor and prevents directory barrier',
    () async {
      final calls = _Calls();
      final durability = await forFiles(calls);
      calls
        ..failFileSync = true
        ..failClose = true;
      await expectLater(
        durability.appendFileDurable(File('${root.path}/a'), [1]),
        throwsA(_failure('file fsync', 5)),
      );
      expect(calls.operations.last, 'close:10');
      expect(
        calls.operations.where((op) => op.startsWith('open:directory')),
        isEmpty,
      );
    },
  );

  test(
    'failed directory open/fsync is visible and append retries barrier',
    () async {
      final calls = _Calls();
      final durability = await forFiles(calls);
      calls.failDirectorySync = true;
      final file = File('${root.path}/a');
      await expectLater(
        durability.appendFileDurable(file, [1]),
        throwsA(_failure('directory fsync', 5)),
      );
      expect(calls.operations.last, 'close:11');
      calls.failDirectorySync = false;
      await durability.appendFileDurable(file, [2]);
      expect(
        calls.operations.where((op) => op.startsWith('fsync:directory')),
        hasLength(2),
      );
      calls.failDirectoryOpen = true;
      await expectLater(
        durability.syncParentAfterCreate(file),
        throwsA(_failure('open', 13)),
      );
    },
  );

  test(
    'mkdir chain flushes each new parent and confirmed directories skip barriers',
    () async {
      final calls = _Calls();
      final durability = LocalDurability(linux: true, linuxCalls: calls);
      await durability.ensureDirectoryDurable(root);
      calls.operations.clear();
      calls.descriptors.clear();
      final nested = Directory('${root.path}/profile/spaces/one');
      await durability.ensureDirectoryDurable(nested);
      expect(calls.descriptors.values, [
        root.path,
        '${root.path}/profile',
        '${root.path}/profile/spaces',
      ]);
      calls.operations.clear();
      await durability.ensureDirectoryDurable(nested);
      expect(calls.operations, isEmpty);
    },
  );

  test(
    'first ensure confirms existing ancestry after interrupted earlier process',
    () async {
      final profile = await Directory(
        '${root.path}/profile/spaces/one',
      ).create(recursive: true);
      final calls = _Calls();
      final durability = LocalDurability(linux: true, linuxCalls: calls);
      await durability.ensureDirectoryDurable(profile);
      final parents = <String>[];
      var ancestor = profile.absolute;
      while (ancestor.parent.path != ancestor.path) {
        ancestor = ancestor.parent;
        parents.add(ancestor.path);
      }
      expect(calls.descriptors.values, parents.reversed);
      calls.operations.clear();
      await durability.ensureDirectoryDurable(profile);
      expect(calls.operations, isEmpty);
    },
  );

  test(
    'failed mkdir barrier retries even though the directory now exists',
    () async {
      final calls = _Calls();
      final durability = LocalDurability(linux: true, linuxCalls: calls);
      await durability.ensureDirectoryDurable(root);
      calls.failDirectorySync = true;
      final profile = Directory('${root.path}/profile');
      await expectLater(
        durability.ensureDirectoryDurable(profile),
        throwsA(_failure('directory fsync', 5)),
      );
      expect(await profile.exists(), isTrue);
      calls.failDirectorySync = false;
      calls.operations.clear();
      await durability.ensureDirectoryDurable(profile);
      expect(
        calls.operations.where((op) => op.startsWith('fsync:directory')),
        hasLength(1),
      );
    },
  );

  test(
    'atomic replacement synchronizes parent after completed rename and preserves failures',
    () async {
      final file = File('${root.path}/settings.json');
      await file.writeAsString('old');
      final calls = _Calls();
      final durability = LocalDurability(linux: true, linuxCalls: calls);
      await durability.ensureDirectoryDurable(root);
      calls
        ..onDirectorySync = (_) {
          expect(file.readAsStringSync(), 'new');
          expect(File('${file.path}.tmp').existsSync(), isFalse);
        }
        ..failDirectorySync = true;
      await expectLater(
        durability.writeAtomicDurable(file, utf8.encode('new')),
        throwsA(_failure('directory fsync', 5)),
      );
      expect(await file.readAsString(), 'new');
      calls.failDirectorySync = false;
      await durability.writeAtomicDurable(file, utf8.encode('new'));
    },
  );

  test(
    'profile lock creates its directory through durability before settings',
    () async {
      final calls = _Calls();
      final durability = LocalDurability(linux: true, linuxCalls: calls);
      await durability.ensureDirectoryDurable(root);
      calls.descriptors.clear();
      final profile = '${root.path}/profile';
      final lock = await ProfileLock.acquire(profile, durability: durability);
      try {
        expect(calls.descriptors.values, [root.path]);
        expect(await File('$profile/settings.json').exists(), isFalse);
        final settings = LocalSettings(profile, durability: durability);
        await settings.load();
        expect(
          calls.descriptors.values.where((path) => path == profile),
          hasLength(3),
        );
        expect(
          await File('$profile/writer-migration.json').readAsString(),
          '{"v":1}',
        );
      } finally {
        await lock.close();
      }
    },
  );

  test(
    'failed settings replacement retains its saved identity on retry',
    () async {
      final calls = _Calls();
      final durability = await forFiles(calls);
      final settings = LocalSettings(root.path, durability: durability);
      calls.failDirectorySync = true;
      await expectLater(
        settings.load(),
        throwsA(_failure('directory fsync', 5)),
      );
      expect(() => settings.writer, throwsStateError);
      final saved =
          jsonDecode(await File('${root.path}/settings.json').readAsString())
              as Map;
      expect(
        await File('${root.path}/writer-migration.json').exists(),
        isFalse,
      );
      calls.failDirectorySync = false;
      await settings.load();
      expect(settings.writer, saved['writer']);
      expect(
        await File('${root.path}/writer-migration.json').readAsString(),
        '{"v":1}',
      );
    },
  );

  test(
    'marker rename sync failure is confirmed on the next settings load',
    () async {
      final calls = _Calls();
      final durability = await forFiles(calls);
      final settings = LocalSettings(root.path, durability: durability);
      var syncs = 0;
      calls.onDirectorySync = (_) {
        if (++syncs == 2) calls.failDirectorySync = true;
      };
      await expectLater(
        settings.load(),
        throwsA(_failure('directory fsync', 5)),
      );
      final writer = settings.writer;
      expect(await File('${root.path}/writer-migration.json').exists(), isTrue);
      calls
        ..onDirectorySync = null
        ..failDirectorySync = false;
      final before = calls.operations.length;
      await settings.load();
      expect(settings.writer, writer);
      expect(
        calls.operations
            .skip(before)
            .where((op) => op.startsWith('fsync:directory')),
        hasLength(1),
      );
    },
  );

  test(
    'other platforms retain file flushing without calling Linux APIs',
    () async {
      final calls = _Calls();
      final durability = LocalDurability(linux: false, linuxCalls: calls);
      final file = File('${root.path}/a');
      await durability.createFileDurable(file, [1]);
      await durability.appendFileDurable(file, [2]);
      expect(await file.readAsBytes(), [1, 2]);
      await expectLater(
        durability.createFileDurable(file, [3]),
        throwsA(isA<FileSystemException>()),
      );
      await durability.writeAtomicDurable(file, [4]);
      expect(await file.readAsBytes(), [4]);
      expect(calls.operations, isEmpty);
    },
  );

  test(
    'real Linux FFI smoke: manifest creation, append, replacement and missing-directory error',
    () async {
      final durability = LocalDurability();
      final folder = LocalLogFolder(root.path, durability: durability);
      await folder.create('manifest.json', Uint8List.fromList([1]));
      await expectLater(
        folder.create('manifest.json', Uint8List.fromList([2])),
        throwsA(_failure('open', 17)),
      );
      expect(await folder.read('manifest.json'), [1]);
      final results = await Future.wait([
        for (final value in [8, 9])
          folder
              .create('race.json', Uint8List.fromList([value]))
              .then(
                (_) => true,
                onError: (Object error) {
                  expect(error, _failure('open', 17));
                  return false;
                },
              ),
      ]);
      expect(results.where((created) => created), hasLength(1));
      expect(await folder.read('race.json'), [results.first ? 8 : 9]);
      await folder.append('writer.jsonl', Uint8List.fromList([3]));
      await folder.append('writer.jsonl', Uint8List.fromList([4]));
      expect(await folder.read('writer.jsonl'), [3, 4]);
      final nested = File('${root.path}/profile/inner/settings.json');
      await durability.writeAtomicDurable(nested, utf8.encode('saved'));
      expect(await nested.readAsString(), 'saved');
      await expectLater(
        durability.syncParentAfterCreate(File('${root.path}/absent/a')),
        throwsA(_failure('open', 2)),
      );
    },
    skip: !Platform.isLinux,
  );
}
