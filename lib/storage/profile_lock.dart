import 'dart:io';

class ProfileInUse implements Exception {
  const ProfileInUse(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An OS-backed, nonblocking lease. The process guard also covers POSIX locks,
/// which otherwise allow a second acquisition by the same process.
class ProfileLock {
  ProfileLock._(this._key, this._file);
  static final Set<String> _held = {};
  final String _key;
  final RandomAccessFile _file;
  Future<void>? _closing;

  static Future<ProfileLock> acquire(
    String root, {
    String fileName = 'profile.lock',
    String message =
        'This profile is already open in another TandemLog instance. Close that instance, then try again.',
  }) async {
    final directory = await Directory(root).create(recursive: true);
    final canonicalRoot = await directory.resolveSymbolicLinks();
    final key = '$canonicalRoot/$fileName';
    if (!_held.add(key)) throw ProfileInUse(message);
    RandomAccessFile? file;
    try {
      file = await File(key).open(mode: FileMode.append);
      try {
        await file.lock(FileLock.exclusive);
      } on FileSystemException {
        throw ProfileInUse(message);
      }
      return ProfileLock._(key, file);
    } catch (_) {
      try {
        await file?.close();
      } finally {
        _held.remove(key);
      }
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _release();

  Future<void> _release() async {
    try {
      await _file.close();
    } finally {
      _held.remove(_key);
    }
  }
}
