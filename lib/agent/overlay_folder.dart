import 'dart:io';
import 'dart:typed_data';

import '../storage/log_folder.dart';

/// Copy-on-write view of a workspace for dry runs: reads fall through to the
/// real folder, and the first write to a file copies it into [scratch] (a
/// private directory) before changing only the copy. Other writers'
/// histories are never copied, so a dry run costs the files it touches.
///
/// [location] stays the real folder's, so the profile copy's warm cache and
/// workspace binding apply and the dry run does not replay history cold.
class OverlayLogFolder extends LocalLogFolder {
  OverlayLogFolder(this.scratch, super.location);
  final String scratch;

  File _shadow(String name) {
    _base(name);
    return File('$scratch${Platform.pathSeparator}$name');
  }

  File _base(String name) => super.file(name); // validates the name

  @override
  File file(String name) {
    final shadow = _shadow(name);
    final base = _base(name);
    return shadow.existsSync() || !base.existsSync() ? shadow : base;
  }

  Future<void> _materialize(String name) async {
    if (!await _shadow(name).exists() && await _base(name).exists()) {
      await _base(name).copy(_shadow(name).path);
    }
  }

  @override
  Future<List<LogFileInfo>> list() async {
    final shadow = await LocalLogFolder(scratch).list();
    final names = {for (final f in shadow) f.name};
    return [
      ...shadow,
      for (final f in await super.list())
        if (!names.contains(f.name)) f,
    ];
  }

  @override
  Future<void> create(String name, Uint8List bytes) async {
    await _materialize(name);
    return super.create(name, bytes);
  }

  @override
  Future<void> append(String name, Uint8List bytes) async {
    await _materialize(name);
    return super.append(name, bytes);
  }

  @override
  Future<void> truncateOwnedTail(
    String name,
    Uint8List expected,
    int keepBytes,
  ) async {
    await _materialize(name);
    return super.truncateOwnedTail(name, expected, keepBytes);
  }

  @override
  Future<void> replaceOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    await _materialize(name);
    return super.replaceOwned(name, expected, bytes);
  }

  @override
  Future<void> recoverOwned(
    String name,
    Uint8List expected,
    Uint8List bytes,
  ) async {
    await _materialize(name);
    // Recovery may archive and remove the interrupted atomic-write temporary.
    // It must never obtain that file through the read-through base fallback.
    await _materialize('$name.tmp');
    return super.recoverOwned(name, expected, bytes);
  }
}
