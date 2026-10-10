import 'dart:io';
import 'dart:typed_data';

import 'local_durability.dart';

/// Only the newly introduced Food canonical family is module-scoped. Existing
/// task/manifest and unclassified conflict names retain their released policy.
bool isFoodConflictName(String name) =>
    RegExp(
      r'^food-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.',
    ).hasMatch(name) &&
    name.contains('sync-conflict') &&
    name.contains('.foodlog') &&
    !name.endsWith('.jsonl');

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

/// Enforce the caller's byte bound while reading, including unknown lengths.
abstract class BoundedLogFolder {
  Future<Uint8List> readBounded(String name, int maximumBytes);
}

class LocalLogFolder implements LogFolder, RangeLogFolder, BoundedLogFolder {
  @override
  final String location;
  LocalLogFolder(this.location, {LocalDurability? durability})
    : _durability = durability ?? LocalDurability.shared;
  final LocalDurability _durability;
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
  Future<Uint8List> readBounded(String name, int maximumBytes) async {
    if (maximumBytes < 0) throw ArgumentError.value(maximumBytes);
    final handle = await file(name).open();
    try {
      if (await handle.length() > maximumBytes) {
        throw const FormatException('Input exceeds safe read limits.');
      }
      final bytes = BytesBuilder(copy: false);
      while (true) {
        final chunk = await handle.read(64 * 1024);
        if (chunk.isEmpty) break;
        if (bytes.length + chunk.length > maximumBytes) {
          throw const FormatException('Input exceeds safe read limits.');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      await handle.close();
    }
  }

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
    await _durability.createFileDurable(file(name), bytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    await _durability.appendFileDurable(file(name), bytes);
  }
}
