import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Native Linux operations, separated only to exercise syscall failure paths.
abstract interface class LinuxDurabilityCalls {
  int open(String path, int flags, int mode);
  int write(int descriptor, Pointer<Uint8> bytes, int length);
  int fsync(int descriptor);
  int close(int descriptor);
  int get errno;
}

/// Linux file and directory barriers. Other platforms retain native file flush
/// behavior; this helper does not claim a directory durability barrier there.
class LocalDurability {
  static final shared = LocalDurability();
  LocalDurability({bool? linux, LinuxDurabilityCalls? linuxCalls})
    : _linux = linux ?? Platform.isLinux,
      _calls = linuxCalls;

  final bool _linux;
  LinuxDurabilityCalls? _calls;
  LinuxDurabilityCalls get _native => _calls ??= _LibcDurabilityCalls();
  final Set<String> _pendingDirectoryEntries = {};
  final Set<String> _ensuredDirectories = {};
  final Set<String> _syncedLogParents = {};

  // Linux asm-generic flags, shared by supported x86 and arm64 Linux builds.
  static const _writeOnly = 1;
  static const _create = 0x40;
  static const _exclusive = 0x80;
  static const _append = 0x400;
  static const _directory = 0x10000;
  static const _closeOnExec = 0x80000;
  static const _interrupted = 4;
  static const _exists = 17;

  Future<Directory> ensureDirectoryDurable(Directory directory) async {
    if (!_linux) return directory.create(recursive: true);
    final absolute = directory.absolute;
    if (_ensuredDirectories.contains(absolute.path) &&
        await absolute.exists()) {
      return directory;
    }
    final parent = absolute.parent;
    if (parent.path != absolute.path) {
      // A visible directory may come from an earlier process interrupted after
      // mkdir but before its parent barrier. Confirm ancestry once per process,
      // including existing ancestors; routine later calls skip these barriers.
      await ensureDirectoryDurable(parent);
      if (!await absolute.exists()) await absolute.create();
      await syncParentAfterCreate(absolute);
    }
    _ensuredDirectories.add(absolute.path);
    return directory;
  }

  /// Call after a new directory entry or rename into this entity's parent.
  Future<void> syncParentAfterCreate(FileSystemEntity entity) async {
    if (_linux) _syncDirectory(entity.absolute.parent.path);
    _pendingDirectoryEntries.remove(entity.absolute.path);
  }

  Future<void> writeAtomicDurable(File destination, List<int> bytes) async {
    await ensureDirectoryDurable(destination.parent);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
    await syncParentAfterCreate(destination);
  }

  /// Reserve and write through one exclusive Linux descriptor, so concurrent
  /// manifest creators cannot overwrite the winner between exists and open.
  Future<void> createFileDurable(File destination, List<int> bytes) async {
    await ensureDirectoryDurable(destination.parent);
    if (_linux) {
      final descriptor = _open(
        destination.path,
        _writeOnly | _create | _exclusive | _closeOnExec,
      );
      _pendingDirectoryEntries.add(destination.absolute.path);
      _writeAndFlush(descriptor, destination.path, bytes);
    } else {
      await destination.create(exclusive: true);
      await destination.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    }
    await syncParentAfterCreate(destination);
  }

  Future<void> appendFileDurable(File destination, List<int> bytes) async {
    await ensureDirectoryDurable(destination.parent);
    if (!_linux) {
      await destination.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      return;
    }
    var descriptor = _openRaw(
      destination.path,
      _writeOnly | _append | _create | _exclusive | _closeOnExec,
    );
    if (descriptor < 0) {
      if (_native.errno != _exists) {
        throw _failure('open append', destination.path);
      }
      descriptor = _open(destination.path, _writeOnly | _append | _closeOnExec);
    } else {
      _pendingDirectoryEntries.add(destination.absolute.path);
    }
    _writeAndFlush(descriptor, destination.path, bytes);
    // One barrier for an existing stream on first use also completes a create
    // interrupted by process death before its directory barrier. No history
    // bytes are read, and later appends need only the file barrier.
    final path = destination.absolute.path;
    if (!_syncedLogParents.contains(path) ||
        _pendingDirectoryEntries.contains(path)) {
      await syncParentAfterCreate(destination);
      _syncedLogParents.add(path);
    }
  }

  int _openRaw(String path, int flags) {
    int descriptor;
    do {
      descriptor = _native.open(path, flags, 0x1b6); // 0666, before umask.
    } while (descriptor < 0 && _native.errno == _interrupted);
    return descriptor;
  }

  int _open(String path, int flags) {
    final descriptor = _openRaw(path, flags);
    if (descriptor < 0) throw _failure('open', path);
    return descriptor;
  }

  void _syncDirectory(String path) {
    final descriptor = _open(path, _directory | _closeOnExec);
    Object? failure;
    try {
      _sync(descriptor, path, 'directory fsync');
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      _close(descriptor, path, failure);
    }
  }

  void _writeAndFlush(int descriptor, String path, List<int> bytes) {
    Pointer<Uint8>? buffer;
    Object? failure;
    try {
      if (bytes.isNotEmpty) {
        buffer = malloc<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        var offset = 0;
        while (offset < bytes.length) {
          final written = _native.write(
            descriptor,
            buffer + offset,
            bytes.length - offset,
          );
          if (written < 0 && _native.errno == _interrupted) continue;
          if (written < 0) throw _failure('write', path);
          if (written == 0) {
            throw FileSystemException('Linux write made no progress', path);
          }
          offset += written;
        }
      }
      _sync(descriptor, path, 'file fsync');
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      if (buffer != null) malloc.free(buffer);
      _close(descriptor, path, failure);
    }
  }

  void _sync(int descriptor, String path, String operation) {
    int result;
    do {
      result = _native.fsync(descriptor);
    } while (result < 0 && _native.errno == _interrupted);
    if (result < 0) throw _failure(operation, path);
  }

  void _close(int descriptor, String path, Object? priorFailure) {
    // Linux releases the descriptor even when close reports EINTR; retrying
    // could close an unrelated descriptor. Preserve the first syscall failure.
    if (_native.close(descriptor) < 0 && priorFailure == null) {
      throw _failure('close', path);
    }
  }

  FileSystemException _failure(String operation, String path) {
    final errno = _native.errno;
    return FileSystemException(
      'Linux $operation failed; persistence was not confirmed',
      path,
      OSError('errno $errno', errno),
    );
  }
}

Future<Directory> ensureDirectoryDurable(Directory directory) =>
    LocalDurability.shared.ensureDirectoryDurable(directory);
Future<void> syncParentAfterCreate(FileSystemEntity entity) =>
    LocalDurability.shared.syncParentAfterCreate(entity);
Future<void> writeAtomicDurable(File destination, List<int> bytes) =>
    LocalDurability.shared.writeAtomicDurable(destination, bytes);
Future<void> createFileDurable(File destination, List<int> bytes) =>
    LocalDurability.shared.createFileDurable(destination, bytes);
Future<void> appendFileDurable(File destination, List<int> bytes) =>
    LocalDurability.shared.appendFileDurable(destination, bytes);

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>);
typedef _OpenDart = int Function(Pointer<Utf8>, int, int);
typedef _WriteNative = IntPtr Function(Int32, Pointer<Uint8>, UintPtr);
typedef _WriteDart = int Function(int, Pointer<Uint8>, int);
typedef _DescriptorNative = Int32 Function(Int32);
typedef _DescriptorDart = int Function(int);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();

class _LibcDurabilityCalls implements LinuxDurabilityCalls {
  _LibcDurabilityCalls() {
    if (!Platform.isLinux ||
        !{
          Abi.linuxX64,
          Abi.linuxIA32,
          Abi.linuxArm64,
        }.contains(Abi.current())) {
      throw UnsupportedError('Linux durability is unsupported on this ABI.');
    }
  }
  final _library = DynamicLibrary.process();
  late final _open = _library.lookupFunction<_OpenNative, _OpenDart>('open');
  late final _write = _library.lookupFunction<_WriteNative, _WriteDart>(
    'write',
  );
  late final _fsync = _library
      .lookupFunction<_DescriptorNative, _DescriptorDart>('fsync');
  late final _close = _library
      .lookupFunction<_DescriptorNative, _DescriptorDart>('close');
  late final _errno = _library.lookupFunction<_ErrnoNative, _ErrnoDart>(
    '__errno_location',
  );
  int _lastErrno = 0;

  @override
  int open(String path, int flags, int mode) {
    final encoded = path.toNativeUtf8();
    try {
      final result = _open(encoded, flags, mode);
      _lastErrno = _errno().value;
      return result;
    } finally {
      malloc.free(encoded);
    }
  }

  @override
  int write(int descriptor, Pointer<Uint8> bytes, int length) {
    final result = _write(descriptor, bytes, length);
    _lastErrno = _errno().value;
    return result;
  }

  @override
  int fsync(int descriptor) {
    final result = _fsync(descriptor);
    _lastErrno = _errno().value;
    return result;
  }

  @override
  int close(int descriptor) {
    final result = _close(descriptor);
    _lastErrno = _errno().value;
    return result;
  }

  @override
  int get errno => _lastErrno;
}
