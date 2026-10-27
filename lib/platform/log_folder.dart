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
  }) : super(
         name,
         documentId != null && modifiedMillis != null && modifiedMillis > 0
             ? '$documentId:$modifiedMillis:$size'
             : '',
         identity: documentId,
       );
  final String? documentId;
  final int? modifiedMillis;
}

class AndroidLogFolder
    implements
        LogFolder,
        RangeLogFolder,
        BoundedRangeLogFolder,
        BoundedLogFolder,
        CheckedReplaceLogFolder,
        TailTruncateLogFolder {
  static const channel = MethodChannel('tandemlog/folders');
  static const eventsChannel = EventChannel('tandemlog/folder-events');
  static const _watchMethods = MethodChannel('tandemlog/folder-events');
  static int _nextWatch = 0;
  static int? _activeWatch;
  @override
  final String location;
  AndroidLogFolder(this.location);
  static String _duplicateFileMessage(Object? name) =>
      name is String && RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)
      ? 'The data folder contains duplicate files named $name. Resolve the duplicate names before retrying. No file was selected.'
      : 'The data folder contains duplicate names for its task data files. Resolve the duplicate names before retrying. No file was selected.';
  static Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (failure, stack) {
      if (failure.code == 'replacement_failed') {
        final details = failure.details;
        final phase = details is Map ? details['phase'] : null;
        final mayHaveChanged =
            details is! Map || details['mayHaveChanged'] != false;
        final permissionDenied =
            details is Map && details['permissionDenied'] == true;
        final message = permissionDenied
            ? 'Access to the data folder was denied. Choose the same folder again in Settings, then resume upgrade recovery; saved recovery bytes were preserved.'
            : phase == 'source_changed'
            ? 'The upgrade source changed. Saved recovery bytes were preserved.'
            : phase == 'unsupported'
            ? 'This folder provider cannot safely replace the workspace manifest. Choose a supported folder before upgrading.'
            : mayHaveChanged
            ? 'The upgrade write was not confirmed. Resume upgrade recovery; saved recovery bytes were preserved.'
            : 'The folder could not prepare the upgrade. Check folder access, then resume; saved recovery bytes were preserved.';
        Error.throwWithStackTrace(
          OwnedReplacementFailure(
            message,
            phase: phase is String ? phase : 'unknown',
            mayHaveChanged: mayHaveChanged,
            cause: failure,
          ),
          stack,
        );
      }
      final String message;
      if (failure.code == 'duplicate_file') {
        final details = failure.details;
        message = _duplicateFileMessage(
          details is Map ? details['name'] : null,
        );
      } else if (failure.code == 'missing_file') {
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
            : failure.code == 'folder_mismatch'
            ? 'Choose the same workspace folder to restore access. Access to a different folder was not kept.'
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

  /// Native compares before retaining the chosen grant. The host must still
  /// compare the returned location before reading any workspace bytes.
  static Future<String?> restoreAccess(String expectedLocation) {
    final uri = Uri.tryParse(expectedLocation);
    if (uri == null || uri.scheme != 'content' || uri.authority.isEmpty) {
      return Future.error(
        ArgumentError.value(expectedLocation, 'expectedLocation'),
      );
    }
    return _invoke<String>('pick', {'expectedTree': expectedLocation});
  }

  @override
  Future<List<LogFileInfo>> list() async {
    final entries = await _invoke<List<dynamic>>('list', {'tree': location});
    // Do not let cached ingestion collapse ambiguous provider entries into a
    // set of names and skip them. Native lookups also reject these duplicates
    // before choosing a document for a direct read, append or create.
    final canonicalNames = <String>{};
    for (final entry in entries!) {
      final name = entry['name'] as String;
      if ((name == 'tandemlog-space.json' ||
              name.endsWith('.jsonl') ||
              name.endsWith('.applog')) &&
          !canonicalNames.add(name)) {
        throw FolderAccessFailure(_duplicateFileMessage(name));
      }
    }
    // Provider metadata is an observation, never a trusted content stamp.
    int? knownNumber(Object? value) =>
        value is int && value >= 0 ? value : null;
    return entries
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
  Future<void> truncateOwnedTail(
    String name,
    Uint8List expected,
    int keepBytes,
  ) => _invoke<void>('truncateOwnedTail', {
    'tree': location,
    'name': name,
    'expected': expected,
    'keepBytes': keepBytes,
  });

  @override
  Future<Uint8List> read(String name) async =>
      (await _invoke<Uint8List>('read', {'tree': location, 'name': name}))!;
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) async {
    if (maximumBytes < 0 || maximumBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    return (await _invoke<Uint8List>('read', {
      'tree': location,
      'name': name,
      'maximumBytes': maximumBytes,
    }))!;
  }

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
  Future<Uint8List?> readFromBounded(
    String name,
    int offset,
    int maximumBytes,
  ) async {
    if (offset < 0 || maximumBytes < 0 || maximumBytes > 32 * 1024 * 1024) {
      throw ArgumentError('Invalid bounded range.');
    }
    return _invoke<Uint8List>('readFrom', {
      'tree': location,
      'name': name,
      'offset': offset,
      'maximumBytes': maximumBytes,
    });
  }

  @override
  Future<void> checkReplacementSupport(String name, int maximumBytes) async {
    if (maximumBytes < 0 || maximumBytes > maximumOwnedReplacementBytes) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
    await _invoke<void>('checkReplacementSupport', {
      'tree': location,
      'name': name,
      'maximumBytes': maximumBytes,
    });
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
    await _invoke<void>('replaceOwned', {
      'tree': location,
      'name': name,
      'expected': expected,
      'bytes': bytes,
    });
  }

  @override
  Future<void> append(String name, Uint8List bytes) =>
      _invoke<void>('append', {'tree': location, 'name': name, 'bytes': bytes});
  @override
  Future<void> create(String name, Uint8List bytes) =>
      _invoke<void>('create', {'tree': location, 'name': name, 'bytes': bytes});
}
