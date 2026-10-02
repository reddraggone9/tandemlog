import 'dart:io';
import 'dart:typed_data';

class LogFileInfo {
  final String name, stamp;
  LogFileInfo(this.name, this.stamp);
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

class LocalLogFolder implements LogFolder {
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
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<Uint8List> read(String name) => file(name).readAsBytes();
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
