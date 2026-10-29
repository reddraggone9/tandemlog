import 'dart:io';
import 'dart:typed_data';

import '../storage/log_folder.dart';

/// Copy-on-write view of a workspace for dry runs: reads fall through to the
/// real folder, and the first write to a file copies it into [location] (a
/// private scratch directory) before changing only the copy. Other writers'
/// histories are never copied, so a dry run costs the files it touches.
class OverlayLogFolder extends LocalLogFolder {
  OverlayLogFolder(super.location, this.base);
  final String base;

  File _shadow(String name) => super.file(name); // validates the name
  File _base(String name) => File('$base${Platform.pathSeparator}$name');

  @override
  File file(String name) {
    final shadow = _shadow(name);
    return shadow.existsSync() || !_base(name).existsSync()
        ? shadow
        : _base(name);
  }

  Future<void> _materialize(String name) async {
    if (!await _shadow(name).exists() && await _base(name).exists()) {
      await _base(name).copy(_shadow(name).path);
    }
  }

  @override
  Future<List<LogFileInfo>> list() async {
    final shadow = await super.list();
    final names = {for (final f in shadow) f.name};
    return [
      ...shadow,
      for (final f in await LocalLogFolder(base).list())
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
    return super.recoverOwned(name, expected, bytes);
  }
}
