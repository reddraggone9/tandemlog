import 'dart:io';
import 'dart:math';
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

/// Checked replacement is a sole-owner compare/check, never a distributed
/// synchronization lock. Callers must durably journal both byte sequences before
/// replacing: a provider can fail after truncation or a partial write.
abstract class CheckedReplaceLogFolder {
  /// Read-only, conservative capability check. This never changes the target or
  /// creates a probe. Success is advisory; actual provider operations can fail.
  Future<void> checkReplacementSupport(String name, int maximumBytes);
  Future<void> replaceOwned(String name, Uint8List expected, Uint8List bytes);
}

/// Explicit recovery is only called after the coordinator checks its durable
/// journal. Unexpected bytes remain blocked; recovery preserves partial evidence.
abstract class RecoverableReplaceLogFolder implements CheckedReplaceLogFolder {
  Future<void> recoverOwned(String name, Uint8List expected, Uint8List bytes);
}

/// Desktop implementation uses atomic local rename, without claiming sync CAS.
abstract class AtomicReplaceLogFolder implements CheckedReplaceLogFolder {}

/// The target may contain expected, replacement, or interrupted replacement
/// bytes when [mayHaveChanged] is true. Only the owner's durable migration
/// journal can decide whether to repair it. Transport never retries implicitly.
class OwnedReplacementFailure extends FolderAccessFailure {
  OwnedReplacementFailure(
    super.message, {
    required this.phase,
    required this.mayHaveChanged,
    super.cause,
  });
  final String phase;
  final bool mayHaveChanged;
}

const maximumOwnedReplacementBytes = 32 * 1024 * 1024;

class LocalLogFolder
    implements
        LogFolder,
        RangeLogFolder,
        BoundedLogFolder,
        AtomicReplaceLogFolder,
        RecoverableReplaceLogFolder {
  @override
  final String location;
  LocalLogFolder(this.location, {LocalDurability? durability})
    : _durability = durability ?? LocalDurability.shared;
  final LocalDurability _durability;
  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) async {
    if (maximumBytes < 0 || maximumBytes > maximumOwnedReplacementBytes) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    final target = file(name);
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw OwnedReplacementFailure(
        'The upgrade target is not a regular file. Restore it before retrying.',
        phase: 'check',
        mayHaveChanged: false,
      );
    }
    await readBounded(name, maximumBytes);
  }

  @override
  Future<void> recoverOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    if (expected.length > maximumOwnedReplacementBytes ||
        bytes.length > maximumOwnedReplacementBytes) {
      throw ArgumentError('Owned replacement exceeds safe byte limits.');
    }
    await checkReplacementSupport(name, maximumOwnedReplacementBytes);
    if (!_sameBytes(
      await readBounded(name, maximumOwnedReplacementBytes),
      expected,
    )) {
      throw OwnedReplacementFailure(
        'The upgrade source changed. Saved recovery bytes were preserved.',
        phase: 'source_changed',
        mayHaveChanged: false,
      );
    }
    final temporaryName = '$name.tmp';
    final temporary = file(temporaryName);
    final temporaryType = await FileSystemEntity.type(
      temporary.path,
      followLinks: false,
    );
    if (temporaryType != FileSystemEntityType.notFound) {
      if (temporaryType != FileSystemEntityType.file) {
        throw OwnedReplacementFailure(
          'An unexpected replacement file remains. Saved recovery bytes were preserved.',
          phase: 'temporary_changed',
          mayHaveChanged: false,
        );
      }
      final partial = await readBounded(
        temporaryName,
        maximumOwnedReplacementBytes,
      );
      if (partial.length > bytes.length ||
          Iterable<int>.generate(
            partial.length,
          ).any((index) => partial[index] != bytes[index])) {
        throw OwnedReplacementFailure(
          'An unexpected replacement file remains. Saved recovery bytes were preserved.',
          phase: 'temporary_changed',
          mayHaveChanged: false,
        );
      }
      final random = Random.secure();
      final nonce = List.generate(
        4,
        (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
      ).join();
      final archiveName = '$name.recovery-$nonce.tmp';
      final archive = file(archiveName);
      try {
        await _durability.createFileDurable(archive, partial);
        if (!_sameBytes(
          await readBounded(archiveName, maximumOwnedReplacementBytes),
          partial,
        )) {
          throw const FormatException('Recovery archive readback differs.');
        }
        // Recheck before removing only this exact, now durably archived prefix.
        if (!_sameBytes(
          await readBounded(temporaryName, maximumOwnedReplacementBytes),
          partial,
        )) {
          throw const FormatException('Recovery temporary bytes changed.');
        }
        await temporary.delete();
        await _durability.syncParentAfterCreate(temporary);
      } catch (error) {
        throw OwnedReplacementFailure(
          'The interrupted replacement could not be archived. Resume recovery; saved recovery bytes were preserved.',
          phase: 'recovery_archive',
          mayHaveChanged: false,
          cause: error,
        );
      }
    }
    await replaceOwned(name, expected, bytes);
  }

  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    if (expected.length > maximumOwnedReplacementBytes ||
        bytes.length > maximumOwnedReplacementBytes) {
      throw ArgumentError('Owned replacement exceeds safe byte limits.');
    }
    await checkReplacementSupport(name, maximumOwnedReplacementBytes);
    final current = await readBounded(name, maximumOwnedReplacementBytes);
    if (!_sameBytes(current, expected)) {
      throw OwnedReplacementFailure(
        'The upgrade source changed. Saved recovery bytes were preserved.',
        phase: 'source_changed',
        mayHaveChanged: false,
      );
    }
    // LocalDurability owns this temporary pathname. Never overwrite recovery
    // evidence left by an earlier interrupted replacement.
    if (await FileSystemEntity.type(
          '${file(name).path}.tmp',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw OwnedReplacementFailure(
        'An interrupted replacement file remains. Resume recovery before retrying.',
        phase: 'temporary_exists',
        mayHaveChanged: false,
      );
    }
    try {
      await _durability.writeAtomicDurable(file(name), bytes);
      final confirmed = await readBounded(name, maximumOwnedReplacementBytes);
      if (!_sameBytes(confirmed, bytes)) {
        throw const FormatException('Replacement readback differs.');
      }
    } catch (error) {
      throw OwnedReplacementFailure(
        'The upgrade write was not confirmed. Resume upgrade recovery; saved recovery bytes were preserved.',
        phase: 'write_or_verify',
        mayHaveChanged: true,
        cause: error,
      );
    }
  }

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

bool _sameBytes(Uint8List a, Uint8List b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
