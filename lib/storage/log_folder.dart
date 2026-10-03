import 'dart:io';
import 'dart:typed_data';

class LogFileInfo {
  final String name, stamp;

  /// Current observed length, when the provider exposes it. This is an append
  /// hint, not proof that previously admitted bytes remain unchanged.
  final int? size;
  LogFileInfo(this.name, this.stamp, {this.size});
}

/// Human-readable transport failure. Retain the original platform cause for
/// diagnosis without exposing framework wrappers or provider internals in UI.
class FolderAccessFailure implements Exception {
  FolderAccessFailure(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

abstract class LogFolder {
  String get location;
  Future<List<LogFileInfo>> list();
  Future<Uint8List> read(String name);
  Future<void> append(String name, Uint8List bytes);
  Future<void> create(String name, Uint8List bytes);
}

/// Optional actual seek capability. A null result requests a conservative full
/// read; implementations must not read/skip the old prefix to produce a suffix.
abstract class RangeLogFolder {
  Future<Uint8List?> readFrom(String name, int offset);
}

class LocalLogFolder implements LogFolder, RangeLogFolder {
  @override
  final String location;
  LocalLogFolder(this.location);
  File file(String name) {
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
      throw ArgumentError('Unsafe filename');
    }
    return File('$location${Platform.pathSeparator}$name');
  }

  @override
  Future<List<LogFileInfo>> list() async {
    final result = <LogFileInfo>[];
    await for (final entry in Directory(location).list()) {
      if (entry is File) {
        final s = await entry.stat();
        result.add(
          LogFileInfo(
            entry.uri.pathSegments.last,
            '${s.size}:${s.modified.microsecondsSinceEpoch}:${s.changed.microsecondsSinceEpoch}',
            size: s.size,
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<Uint8List> read(String name) => file(name).readAsBytes();
  @override
  Future<Uint8List> readFrom(String name, int offset) async {
    final handle = await file(name).open();
    try {
      final length = await handle.length();
      if (offset < 0 || length < offset) {
        throw FolderAccessFailure(
          'Previously imported log $name was truncated. Restore it before writing.',
        );
      }
      await handle.setPosition(offset);
      final builder = BytesBuilder(copy: false);
      while (true) {
        final chunk = await handle.read(64 * 1024);
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> create(String name, Uint8List bytes) async {
    if (await file(name).exists()) {
      throw StateError('File already exists: $name');
    }
    await file(name).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    final f = await file(name).open(mode: FileMode.append);
    try {
      await f.writeFrom(bytes);
      await f.flush();
    } finally {
      await f.close();
    }
  }
}
