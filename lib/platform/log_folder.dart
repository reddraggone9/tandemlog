import 'dart:async';
import 'package:flutter/services.dart';
import '../storage/log_folder.dart';
export '../storage/log_folder.dart';

/// Provider observations, never evidence that canonical contents are unchanged.
class AndroidLogFileInfo extends LogFileInfo {
  AndroidLogFileInfo(
    String name, {
    this.documentId,
    super.size,
    this.modifiedMillis,
  }) : super(name, '');
  final String? documentId;
  final int? modifiedMillis;
}

class AndroidLogFolder implements LogFolder, RangeLogFolder {
  static const channel = MethodChannel('tandemlog/folders');
  static const eventsChannel = EventChannel('tandemlog/folder-events');
  static const _watchMethods = MethodChannel('tandemlog/folder-events');
  static int _nextWatch = 0;
  static int? _activeWatch;
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
    // Provider metadata is an observation, never a trusted content stamp.
    int? knownNumber(Object? value) =>
        value is int && value >= 0 ? value : null;
    return entries!
        .map(
          (e) => AndroidLogFileInfo(
            e['name'] as String,
            documentId:
                e['documentId'] is String &&
                    (e['documentId'] as String).isNotEmpty
                ? e['documentId'] as String
                : null,
            size: knownNumber(e['size']),
            modifiedMillis: knownNumber(e['modifiedMillis']),
          ),
        )
        .toList();
  }

  /// Notifications are hints. An unavailable observer fails this subscription,
  /// allowing ForegroundImporter to retain polling and retry attachment later.
  /// Explicit activation catches missing/unsupported platform implementations;
  /// EventChannel.receiveBroadcastStream reports those through FlutterError.
  Stream<Object?> watch() {
    final token = ++_nextWatch;
    final arguments = <String, Object?>{'tree': location, 'token': token};
    var cancelled = false;
    late StreamController<Object?> controller;
    controller = StreamController<Object?>(
      onListen: () async {
        _activeWatch = token;
        eventsChannel.binaryMessenger.setMessageHandler(eventsChannel.name, (
          reply,
        ) async {
          if (cancelled || _activeWatch != token) return null;
          if (reply == null) {
            unawaited(controller.close());
            return null;
          }
          try {
            final event = eventsChannel.codec.decodeEnvelope(reply);
            if (event is Map &&
                event['tree'] == location &&
                event['token'] == token) {
              controller.add(event);
            }
          } catch (error, stack) {
            controller.addError(error, stack);
          }
          return null;
        });
        try {
          await _watchMethods.invokeMethod<void>('listen', arguments);
        } catch (error, stack) {
          if (!cancelled && _activeWatch == token) {
            controller.addError(error, stack);
          }
        }
      },
      onCancel: () async {
        cancelled = true;
        if (_activeWatch == token) {
          _activeWatch = null;
          eventsChannel.binaryMessenger.setMessageHandler(
            eventsChannel.name,
            null,
          );
        }
        try {
          await _watchMethods.invokeMethod<void>('cancel', arguments);
        } catch (_) {
          // Failed observer teardown cannot disable the independent polling path.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Uint8List> read(String name) async =>
      (await _invoke<Uint8List>('read', {'tree': location, 'name': name}))!;
  @override
  Future<Uint8List?> readFrom(String name, int offset) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    return _invoke<Uint8List>('readFrom', {
      'tree': location,
      'name': name,
      'offset': offset,
    });
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      _invoke<void>('append', {'tree': location, 'name': name, 'bytes': bytes});
  @override
  Future<void> create(String name, Uint8List bytes) =>
      _invoke<void>('create', {'tree': location, 'name': name, 'bytes': bytes});
}
