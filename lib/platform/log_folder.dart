import 'package:flutter/services.dart';
import '../storage/log_folder.dart';
export '../storage/log_folder.dart';

class AndroidLogFolder implements LogFolder {
  static const channel = MethodChannel('tandemlog/folders');
  @override
  final String location;
  AndroidLogFolder(this.location);
  static Future<String?> pick() => channel.invokeMethod<String>('pick');
  @override
  Future<List<LogFileInfo>> list() async {
    final entries = await channel.invokeListMethod<dynamic>('list', {
      'tree': location,
    });
    // Providers may report stale timestamps. Force revalidation on Android.
    return entries!.map((e) => LogFileInfo(e['name'] as String, '')).toList();
  }

  @override
  Future<Uint8List> read(String name) async => (await channel
      .invokeMethod<Uint8List>('read', {'tree': location, 'name': name}))!;
  @override
  Future<void> append(String name, Uint8List bytes) => channel.invokeMethod(
    'append',
    {'tree': location, 'name': name, 'bytes': bytes},
  );
  @override
  Future<void> create(String name, Uint8List bytes) => channel.invokeMethod(
    'create',
    {'tree': location, 'name': name, 'bytes': bytes},
  );
}
