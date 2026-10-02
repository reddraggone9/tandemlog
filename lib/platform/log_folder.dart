import 'package:flutter/services.dart';
import '../storage/log_folder.dart';
export '../storage/log_folder.dart';

class AndroidLogFolder implements LogFolder {
  static const channel = MethodChannel('tandemlog/folders');
  @override
  final String location;
  AndroidLogFolder(this.location);
  static Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (failure, stack) {
      final String message;
      if (failure.code == 'missing_file') {
        final details = failure.details;
        final name = details is Map ? details['name'] : null;
        final knownName =
            name is String && RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name);
        message = knownName
            ? 'The data folder is missing $name. Restore this file or wait for folder sync, then retry.'
            : 'A file is missing from the data folder. Restore the complete folder or wait for folder sync, then retry.';
      } else if (method == 'pick') {
        message = failure.code == 'busy'
            ? 'The folder picker is already open.'
            : failure.code == 'permission'
            ? 'Folder access could not be kept. Choose the folder again.'
            : 'Could not open the folder picker. Try again.';
      } else if (failure.code == 'permission') {
        message =
            'Access to the data folder was denied. Choose the folder again in Settings, then retry.';
      } else {
        message = method == 'append' || method == 'create'
            ? 'Could not finish saving to the data folder. Check that it is available, then retry.'
            : 'Could not read the data folder. Check that it is available, then retry.';
      }
      Error.throwWithStackTrace(
        FolderAccessFailure(message, cause: failure),
        stack,
      );
    }
  }

  static Future<String?> pick() => _invoke<String>('pick');
  @override
  Future<List<LogFileInfo>> list() async {
    final entries = await _invoke<List<dynamic>>('list', {'tree': location});
    // Providers may report stale timestamps. Force revalidation on Android.
    return entries!.map((e) => LogFileInfo(e['name'] as String, '')).toList();
  }

  @override
  Future<Uint8List> read(String name) async =>
      (await _invoke<Uint8List>('read', {'tree': location, 'name': name}))!;
  @override
  Future<void> append(String name, Uint8List bytes) =>
      _invoke<void>('append', {'tree': location, 'name': name, 'bytes': bytes});
  @override
  Future<void> create(String name, Uint8List bytes) =>
      _invoke<void>('create', {'tree': location, 'name': name, 'bytes': bytes});
}
