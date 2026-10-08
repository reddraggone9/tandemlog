import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _operationBytes = 1024 * 1024;
const _stateBytes = 8 * 1024 * 1024;
const _requestBytes = 12 * 1024 * 1024;
const _responseBytes = 24 * 1024 * 1024;
const _maxActor = 9007199254740991;

/// A native failure is explicit. Transport/worker failures may have an unknown
/// outcome; the canonical receipt/outbox owner must retain exact prepared bytes.
class NativeTextException implements Exception {
  const NativeTextException(
    this.operation,
    this.message, {
    this.outcomeUnknown = false,
  });
  final String operation, message;
  final bool outcomeUnknown;
  @override
  String toString() => 'Native text $operation failed: $message';
}

/// Budgets measure serialized state/session data, not native resident memory.
class NativeTextLimits {
  const NativeTextLimits({
    required this.visibleUtf16,
    this.updateBytes = _operationBytes,
    this.stateBytes = _stateBytes,
    this.sessionBytes = 16 * 1024 * 1024,
    this.retainedBytes = 64 * 1024 * 1024,
    this.admissionUnits = 100000,
  });
  final int visibleUtf16, updateBytes, stateBytes, sessionBytes, retainedBytes;
  final int admissionUnits;
  Map<String, int> toJson() {
    final values = {
      'visibleUtf16': visibleUtf16,
      'updateBytes': updateBytes,
      'stateBytes': stateBytes,
      'sessionBytes': sessionBytes,
      'retainedBytes': retainedBytes,
      'admissionUnits': admissionUnits,
    };
    if (values.values.any((value) => value <= 0 || value > _maxActor) ||
        updateBytes > _operationBytes ||
        stateBytes > _stateBytes ||
        admissionUnits > _stateBytes) {
      throw ArgumentError(
        'Native text budgets must be positive bounded integers; operations <=1 MiB, state <=8 MiB',
      );
    }
    return values;
  }
}

Uint8List _decodeBytes(Object? encoded, int maximum, String kind) {
  if (encoded is! String ||
      encoded.isEmpty ||
      encoded.length % 4 != 0 ||
      encoded.length > ((maximum + 2) ~/ 3) * 4) {
    throw FormatException('$kind must be a bounded canonical Base64 string');
  }
  final bytes = base64Decode(encoded);
  if (bytes.isEmpty ||
      bytes.length > maximum ||
      base64Encode(bytes) != encoded) {
    throw FormatException('$kind must preserve exact canonical Base64 bytes');
  }
  return bytes.asUnmodifiableView();
}

class NativeTextUpdate {
  NativeTextUpdate._(this.encoded, this.bytes);
  factory NativeTextUpdate.parse(Object? encoded) => NativeTextUpdate._(
    encoded is String ? encoded : '',
    _decodeBytes(encoded, _operationBytes, 'Text operation'),
  );
  final String encoded;
  final Uint8List bytes;
}

/// Full state includes buffered operations; it is distinct from a bounded op.
class NativeTextState {
  NativeTextState._(this.encoded, this.bytes);
  factory NativeTextState.parse(Object? encoded) => NativeTextState._(
    encoded is String ? encoded : '',
    _decodeBytes(encoded, _stateBytes, 'Text state'),
  );
  final String encoded;
  final Uint8List bytes;
}

class NativeTextCheckpoint {
  const NativeTextCheckpoint(this.state);
  factory NativeTextCheckpoint.fromJson(Object? value) {
    if (value is! Map || value['schema'] != 1 || value['codec'] != 'yrs-v1') {
      throw const FormatException('Unsupported native text checkpoint');
    }
    return NativeTextCheckpoint(NativeTextState.parse(value['state']));
  }
  final NativeTextState state;
  Map<String, Object> toJson() => {
    'schema': 1,
    'codec': 'yrs-v1',
    'state': state.encoded,
  };
}

class NativeTextSnapshot {
  const NativeTextSnapshot({
    required this.text,
    required this.pending,
    required this.guid,
  });
  final String text, guid;
  final bool pending;
}

void _actor(int client) {
  if (client < 2 || client > _maxActor) {
    throw ArgumentError.value(client, 'actorClientId', 'Must be 2..2^53-1');
  }
}

void _validateText(String text, int maximum) {
  if (text.length > maximum) {
    throw const FormatException('Text exceeds the visible UTF-16 field limit');
  }
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index == text.length ||
          text.codeUnitAt(index) < 0xdc00 ||
          text.codeUnitAt(index) > 0xdfff) {
        throw const FormatException(
          'Text contains an unpaired UTF-16 surrogate',
        );
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Text contains an unpaired UTF-16 surrogate');
    }
  }
}

String _string(Map<String, dynamic> value, String key, String operation) {
  if (value[key] is! String) {
    throw NativeTextException(
      operation,
      'Response has no string $key',
      outcomeUnknown: true,
    );
  }
  return value[key] as String;
}

/// Owns private UUID handles in the process worker. Loading does not reset it.
/// No canonical writes, environment override, implicit fallback, or DLL unload.
class NativeTextEngine {
  NativeTextEngine({String? libraryPath})
    : _bindings = _NativeBindings.load(libraryPath ?? _defaultLibrary());
  final _NativeBindings _bindings;
  final String ownerId = const Uuid().v4();
  final Set<NativeTextDocument> _documents = {};
  final Set<NativeTextMaterializer> _materializers = {};
  final _inspectionCache = <String, List<int>>{};
  int _inspectionPayloadBytes = 0;
  int get cachedInspectionCount => _inspectionCache.length;
  int get cachedInspectionPayloadBytes => _inspectionPayloadBytes;
  bool _closed = false;
  void _ensureOpen() {
    if (_closed) throw StateError('Native text engine owner is disposed');
  }

  Map<String, dynamic> _call(String operation, Map<String, Object?> data) {
    _ensureOpen();
    return _bindings.call(operation, data);
  }

  NativeTextUpdate seedText(String text) {
    _validateText(text, 10000);
    return NativeTextUpdate.parse(_call('seed', {'text': text})['update']);
  }

  /// Disposable reconstruction has no editor, receipt or Undo ownership.
  NativeTextMaterializer createMaterializer({
    required NativeTextState seed,
    required NativeTextLimits limits,
  }) {
    _ensureOpen();
    if (seed.bytes.length > limits.stateBytes) {
      throw const FormatException('Materializer seed exceeds its state budget');
    }
    final name = const Uuid().v4();
    _call('materializer_new', {
      'name': name,
      'seed': seed.encoded,
      'limits': limits.toJson(),
    });
    final materializer = NativeTextMaterializer._(this, name, limits);
    _materializers.add(materializer);
    return materializer;
  }

  NativeTextDocument createDocument({
    required int actorClientId,
    required NativeTextLimits limits,
    NativeTextUpdate? seed,
  }) => _create('new', actorClientId, limits, {
    if (seed != null) 'seed': seed.encoded,
  });

  NativeTextDocument restoreDocument({
    required int actorClientId,
    required NativeTextLimits limits,
    required NativeTextCheckpoint checkpoint,
  }) {
    if (checkpoint.state.bytes.length > limits.stateBytes) {
      throw const FormatException(
        'Checkpoint exceeds the document state budget',
      );
    }
    return _create('restore', actorClientId, limits, {
      'checkpoint': checkpoint.toJson(),
    });
  }

  NativeTextDocument _create(
    String operation,
    int actor,
    NativeTextLimits limits,
    Map<String, Object?> data,
  ) {
    _ensureOpen();
    _actor(actor);
    final budgets = limits.toJson();
    final name = const Uuid().v4();
    final result = _call(operation, {
      'name': name,
      'client': actor,
      'limits': budgets,
      ...data,
    });
    try {
      final guid = _string(result, 'guid', operation);
      if (guid.isEmpty || result['client'] != actor) {
        throw NativeTextException(
          operation,
          'Native document ownership response mismatch',
        );
      }
      final document = NativeTextDocument._(this, name, guid, actor, limits);
      _documents.add(document);
      return document;
    } catch (_) {
      _call('cancel', {'name': name});
      rethrow;
    }
  }

  NativeTextDraft captureDraft(
    NativeTextDocument source, {
    required int actorClientId,
  }) {
    _ensureOpen();
    source._ensureLocalReady();
    _actor(actorClientId);
    if (!identical(source._engine, this)) {
      throw StateError('Document belongs to a different engine owner');
    }
    final name = const Uuid().v4();
    final result = _call('draft', {
      'name': name,
      'source': source.handleId,
      'client': actorClientId,
    });
    try {
      final guid = _string(result, 'guid', 'draft');
      if (guid.isEmpty || result['client'] != actorClientId) {
        throw const NativeTextException(
          'draft',
          'Native draft ownership response mismatch',
        );
      }
      final text = _string(_call('read', {'name': name}), 'text', 'read');
      _validateText(text, source.limits.visibleUtf16);
      final draft = NativeTextDraft._(source, name, guid, actorClientId, text);
      source._drafts.add(draft);
      return draft;
    } catch (_) {
      _call('cancel', {'name': name});
      rethrow;
    }
  }

  List<int> inspect(NativeTextUpdate update, {int admissionUnits = 100000}) {
    _ensureOpen();
    if (admissionUnits <= 0 || admissionUnits > _stateBytes) {
      throw ArgumentError.value(admissionUnits, 'admissionUnits');
    }
    // Inspection is a stateless function of exact immutable bytes and budget.
    // Contextual actor ownership is still validated separately on every use.
    final key = '$admissionUnits:${update.encoded}';
    final remembered = _inspectionCache.remove(key);
    if (remembered != null) {
      _inspectionCache[key] = remembered;
      return remembered;
    }
    final response = _call('inspect', {
      'update': update.encoded,
      'admissionUnits': admissionUnits,
    });
    final actors = response['structActors'];
    if (actors is! List ||
        actors.any(
          (actor) => actor is! int || actor < 1 || actor > _maxActor,
        )) {
      throw const NativeTextException(
        'inspect',
        'Invalid native struct actor response',
      );
    }
    final result = actors.cast<int>();
    if (result.toSet().length != result.length ||
        List.generate(
          result.length - (result.isEmpty ? 0 : 1),
          (index) => result[index] < result[index + 1],
        ).contains(false)) {
      throw const NativeTextException(
        'inspect',
        'Native struct actors are not sorted and unique',
      );
    }
    final verified = List<int>.unmodifiable(result);
    final bytes = key.length * 2 + verified.length * 8;
    const budget = 8 * 1024 * 1024;
    if (bytes <= budget) {
      while (_inspectionCache.isNotEmpty &&
          (_inspectionCache.length >= 1024 ||
              _inspectionPayloadBytes + bytes > budget)) {
        final oldest = _inspectionCache.keys.first;
        final previous = _inspectionCache.remove(oldest)!;
        _inspectionPayloadBytes -= oldest.length * 2 + previous.length * 8;
      }
      _inspectionCache[key] = verified;
      _inspectionPayloadBytes += bytes;
    }
    return verified;
  }

  void dispose() {
    if (_closed) return;
    _inspectionCache.clear();
    _inspectionPayloadBytes = 0;
    Object? failure;
    for (final materializer in _materializers.toList()) {
      try {
        materializer.close();
      } catch (error) {
        failure ??= error;
      }
    }
    for (final document in _documents.toList()) {
      try {
        document.dispose();
      } catch (error) {
        failure ??= error;
      }
    }
    _closed = true;
    if (failure != null) throw failure;
  }
}

class NativeMaterializedText {
  const NativeMaterializedText(this.text, this.pending);
  final String text;
  final bool pending;
}

/// Quarantined on failure. Only immutable original packets may reconstruct it;
/// it cannot capture a draft or acquire character Undo ownership.
class NativeTextMaterializer {
  NativeTextMaterializer._(this._engine, this._name, this.limits);
  final NativeTextEngine _engine;
  final String _name;
  final NativeTextLimits limits;
  bool _closed = false;
  Map<String, dynamic> _call(
    String op, [
    Map<String, Object?> data = const {},
  ]) {
    if (_closed) throw StateError('Native materializer is closed');
    return _engine._call(op, {'name': _name, ...data});
  }

  NativeMaterializedText _snapshot(Map<String, dynamic> result) {
    final text = _string(result, 'text', 'materializer_read');
    _validateText(text, limits.visibleUtf16);
    if (result['pending'] is! bool) {
      throw const FormatException('Invalid native materializer pending flag');
    }
    return NativeMaterializedText(text, result['pending'] as bool);
  }

  NativeMaterializedText read() => _snapshot(_call('materializer_read'));
  NativeTextState get fullState =>
      NativeTextState.parse(_call('materializer_state')['update']);
  NativeMaterializedText apply(NativeTextUpdate update) {
    try {
      if (update.bytes.length > limits.updateBytes) {
        throw const FormatException('Materializer update exceeds its budget');
      }
      return _snapshot(_call('materializer_apply', {'update': update.encoded}));
    } catch (_) {
      // The native layer removes failed candidates. Cancellation also covers
      // a response/transport validation failure after successful integration.
      try {
        close();
      } catch (_) {
        /* Original failure remains authoritative. */
      }
      rethrow;
    }
  }

  void close() {
    if (_closed) return;
    try {
      _call('materializer_cancel');
    } on NativeTextException catch (error) {
      if (!error.message.contains('unknown materializer')) rethrow;
    } finally {
      _closed = true;
      _engine._materializers.remove(this);
    }
  }
}

class NativeTextDocument {
  NativeTextDocument._(
    this._engine,
    this.handleId,
    this.guid,
    this.actorClientId,
    this.limits,
  );
  final NativeTextEngine _engine;
  final String handleId, guid;
  final int actorClientId;
  final NativeTextLimits limits;
  final Set<NativeTextDraft> _drafts = {};
  NativeTextPreparedUndo? _preparedUndo;
  bool _closed = false;
  bool get isClosed => _closed;
  void _ensureOpen() {
    _engine._ensureOpen();
    if (_closed) {
      throw StateError('Native text document generation is disposed');
    }
  }

  void _ensureLocalReady() {
    _ensureOpen();
    if (_preparedUndo?._pending ?? false) {
      throw StateError('Prepared Undo awaits its receipt or cancellation');
    }
  }

  Map<String, dynamic> _call(
    String operation, [
    Map<String, Object?> data = const {},
  ]) {
    _ensureOpen();
    return _engine._call(operation, {'name': handleId, ...data});
  }

  NativeTextSnapshot _snapshot(Map<String, dynamic> result) {
    final text = _string(result, 'text', 'read');
    try {
      _validateText(text, limits.visibleUtf16);
    } on FormatException catch (error) {
      throw NativeTextException(
        'read',
        'Invalid bounded native text: $error',
        outcomeUnknown: true,
      );
    }
    if (result['pending'] is! bool ||
        (result.containsKey('guid') && result['guid'] != guid) ||
        (result.containsKey('client') && result['client'] != actorClientId)) {
      throw const NativeTextException(
        'read',
        'Native snapshot ownership or pending flag mismatch',
        outcomeUnknown: true,
      );
    }
    return NativeTextSnapshot(
      text: text,
      pending: result['pending'] as bool,
      guid: guid,
    );
  }

  NativeTextSnapshot read() => _snapshot(_call('read'));
  NativeTextState get fullState =>
      NativeTextState.parse(_call('state')['update']);
  NativeTextCheckpoint checkpoint() =>
      NativeTextCheckpoint.fromJson(_call('checkpoint')['checkpoint']);
  NativeTextSnapshot applyRemote(NativeTextUpdate update) {
    if (update.bytes.length > limits.updateBytes) {
      throw const FormatException(
        'Operation exceeds the document update budget',
      );
    }
    return _snapshot(_call('apply', {'update': update.encoded}));
  }

  /// Apply only after the caller confirms the exact canonical receipt. This
  /// tracks one local Undo item on a dedicated operation owner.
  NativeTextSnapshot applyLocalReceipt(NativeTextUpdate update) {
    _ensureLocalReady();
    if (update.bytes.length > limits.updateBytes) {
      throw const FormatException(
        'Operation exceeds the document update budget',
      );
    }
    return _snapshot(_call('apply_local', {'update': update.encoded}));
  }

  /// Retain this acknowledged Save as a separately named Undo item in the
  /// session owner. Repeated exact registration is idempotent.
  NativeTextSnapshot applyOwnedReceipt(
    NativeTextUpdate update, {
    required String operationId,
  }) {
    _ensureLocalReady();
    if (update.bytes.length > limits.updateBytes) {
      throw const FormatException(
        'Operation exceeds the document update budget',
      );
    }
    return _snapshot(
      _call('apply_owned', {
        'operation': operationId,
        'update': update.encoded,
      }),
    );
  }

  NativeTextDraft captureDraft({required int actorClientId}) =>
      _engine.captureDraft(this, actorClientId: actorClientId);
  NativeTextPreparedUndo prepareUndo() {
    _ensureOpen();
    final result = _call('prepare_undo');
    if (result['changed'] != true) {
      throw const NativeTextException(
        'prepare_undo',
        'Native Undo did not prepare an effective change',
      );
    }
    return _retainPreparedUndo(result, 'prepare_undo');
  }

  /// Prepare only the named acknowledged operation. An ineffective item
  /// prepares an empty compensation, preserving every other Undo item.
  NativeTextPreparedUndo prepareOperationUndo({required String operationId}) {
    _ensureOpen();
    final result = _call('prepare_operation_undo', {'operation': operationId});
    if (result['changed'] != true) {
      throw const NativeTextException(
        'prepare_operation_undo',
        'Native operation Undo was not prepared',
      );
    }
    return _retainPreparedUndo(result, 'prepare_operation_undo');
  }

  NativeTextPreparedUndo _retainPreparedUndo(
    Map<String, dynamic> result,
    String operation,
  ) {
    final token = _string(result, 'token', operation);
    final update = NativeTextUpdate.parse(result['update']);
    if (_preparedUndo?._pending ?? false) {
      if (_preparedUndo!.token != token ||
          _preparedUndo!.update.encoded != update.encoded) {
        throw NativeTextException(
          operation,
          'Pending Undo identity or immutable bytes changed',
          outcomeUnknown: true,
        );
      }
      return _preparedUndo!;
    }
    return _preparedUndo = NativeTextPreparedUndo._(this, token, update);
  }

  void dispose() {
    if (_closed) return;
    Object? failure;
    for (final draft in _drafts.toList()) {
      try {
        draft.cancel();
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      _preparedUndo?.cancel();
    } catch (error) {
      failure ??= error;
    }
    try {
      _call('cancel');
    } catch (error) {
      failure ??= error;
    }
    _closed = true;
    _engine._documents.remove(this);
    if (failure != null) throw failure;
  }
}

class NativeTextDraft {
  NativeTextDraft._(
    this.source,
    this.handleId,
    this.guid,
    this.actorClientId,
    this._capturedText,
  );
  final NativeTextDocument source;
  final String handleId, guid;
  final int actorClientId;
  String _capturedText;
  bool _closed = false, _composing = false;
  NativeTextPreparedSave? _prepared;
  String get capturedText => _capturedText;
  bool get isClosed => _closed;
  bool get isComposing => _composing;
  void _ensureOpen() {
    source._ensureOpen();
    if (_closed) throw StateError('Captured native draft is closed');
  }

  void _ensureEditable() {
    _ensureOpen();
    if (_prepared != null) {
      throw StateError(
        'Captured native draft is frozen for receipt-gated Save',
      );
    }
  }

  Map<String, dynamic> _call(
    String operation, [
    Map<String, Object?> data = const {},
  ]) {
    _ensureOpen();
    return source._engine._call(operation, {'name': handleId, ...data});
  }

  void setComposing(bool active) {
    _ensureEditable();
    if (active == _composing) return;
    _call('composition', {'active': active});
    _composing = active;
  }

  void replaceText(String next) {
    _ensureEditable();
    _validateText(next, source.limits.visibleUtf16);
    if (next == _capturedText) return;
    // Diff only against this captured private buffer, never received live text.
    var prefix = 0;
    while (prefix < _capturedText.length &&
        prefix < next.length &&
        _capturedText.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    while (!_boundary(_capturedText, prefix) || !_boundary(next, prefix)) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < _capturedText.length - prefix &&
        suffix < next.length - prefix &&
        _capturedText.codeUnitAt(_capturedText.length - 1 - suffix) ==
            next.codeUnitAt(next.length - 1 - suffix)) {
      suffix++;
    }
    while (!_boundary(_capturedText, _capturedText.length - suffix) ||
        !_boundary(next, next.length - suffix)) {
      suffix--;
    }
    final response = _call('edit', {
      'index': prefix,
      'delete': _capturedText.length - prefix - suffix,
      'insert': next.substring(prefix, next.length - suffix),
    });
    if (response['text'] != next) {
      throw const NativeTextException(
        'edit',
        'Native captured edit response differs',
        outcomeUnknown: true,
      );
    }
    _capturedText = next;
  }

  NativeTextPreparedSave prepareSave({NativeTextDocument? target}) {
    _ensureOpen();
    source._ensureLocalReady();
    if (target != null && !identical(target, source)) {
      throw StateError('Draft target is not its captured source owner');
    }
    if (_composing) {
      throw StateError('Finish IME composition before preparing Save');
    }
    if (_prepared != null) return _prepared!;
    final response = _call('prepare', {'target': source.handleId});
    return _prepared = NativeTextPreparedSave._(
      this,
      NativeTextUpdate.parse(response['update']),
    );
  }

  void cancel() {
    if (_closed) return;
    _call('cancel');
    _closed = true;
    source._drafts.remove(this);
  }
}

bool _boundary(String text, int offset) =>
    offset == 0 ||
    offset == text.length ||
    !(text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);

class NativeTextPreparedSave {
  NativeTextPreparedSave._(this._draft, this.update);
  final NativeTextDraft _draft;
  final NativeTextUpdate update;
  NativeTextSnapshot? _committed;
  bool _outcomeUnknown = false;
  bool get outcomeUnknown => _outcomeUnknown;
  NativeTextSnapshot commit({required NativeTextUpdate receiptUpdate}) {
    if (receiptUpdate.encoded != update.encoded) {
      throw StateError('Save receipt does not match the exact prepared bytes');
    }
    _draft.source._ensureOpen();
    if (_committed != null) {
      _draft.cancel();
      return _committed!;
    }
    _draft._ensureOpen();
    _draft.source._ensureLocalReady();
    try {
      final response = _draft.source._call('apply_local', {
        'update': update.encoded,
      });
      _committed = _draft.source._snapshot(response);
      _draft.cancel();
      _outcomeUnknown = false;
      return _committed!;
    } on NativeTextException catch (error) {
      _outcomeUnknown = error.outcomeUnknown;
      rethrow;
    }
  }

  void cancel() => _draft.cancel();
}

class NativeTextPreparedUndo {
  NativeTextPreparedUndo._(this._document, this.token, this.update);
  final NativeTextDocument _document;
  final String token;
  final NativeTextUpdate update;
  NativeTextSnapshot? _committed;
  bool _cancelled = false;
  bool _outcomeUnknown = false;
  bool get outcomeUnknown => _outcomeUnknown;
  bool get _pending => !_cancelled && _committed == null;
  NativeTextSnapshot commit({required NativeTextUpdate receiptUpdate}) {
    if (receiptUpdate.encoded != update.encoded) {
      throw StateError('Undo receipt does not match the exact prepared bytes');
    }
    _document._ensureOpen();
    if (_cancelled) throw StateError('Prepared Undo was cancelled');
    if (_committed != null) return _committed!;
    try {
      final response = _document._call('commit_undo', {
        'token': token,
        'receipt': {'update': update.encoded},
      });
      _committed = _document._snapshot(response);
      _outcomeUnknown = false;
      return _committed!;
    } on NativeTextException catch (error) {
      _outcomeUnknown = error.outcomeUnknown;
      rethrow;
    }
  }

  void cancel() {
    if (!_pending) return;
    _document._call('cancel_prepared_undo', {'token': token});
    _cancelled = true;
  }
}

String _defaultLibrary() {
  if (Platform.isAndroid) return 'libtandemlog_text.so';
  final directory = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isLinux) return '$directory/lib/libtandemlog_text.so';
  if (Platform.isWindows) return '$directory/tandemlog_text.dll';
  throw const NativeTextException(
    'load',
    'Native text platform is unsupported',
  );
}

class _NativeBindings {
  _NativeBindings(this.library) {
    allocate = library
        .lookupFunction<
          Pointer<Uint8> Function(UintPtr),
          Pointer<Uint8> Function(int)
        >('tandemlog_text_alloc');
    releaseInput = library
        .lookupFunction<
          Void Function(Pointer<Uint8>, UintPtr),
          void Function(Pointer<Uint8>, int)
        >('tandemlog_text_release_input');
    request = library
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Uint8>),
          Pointer<Uint8> Function(Pointer<Uint8>)
        >('tandemlog_text_json');
    release = library
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('tandemlog_text_free');
  }
  static final Map<String, _NativeBindings> _retained = {};
  static _NativeBindings load(String path) {
    try {
      return _retained.putIfAbsent(
        path,
        () => _NativeBindings(DynamicLibrary.open(path)),
      );
    } catch (error) {
      throw NativeTextException('load', error.toString());
    }
  }

  final DynamicLibrary library;
  late final Pointer<Uint8> Function(int) allocate;
  late final void Function(Pointer<Uint8>, int) releaseInput;
  late final Pointer<Uint8> Function(Pointer<Uint8>) request;
  late final void Function(Pointer<Uint8>) release;
  Map<String, dynamic> call(String operation, Map<String, Object?> data) {
    final bytes = utf8.encode(jsonEncode({'op': operation, ...data}));
    if (bytes.length + 1 > _requestBytes) {
      throw const FormatException(
        'Native text request exceeds 12 MiB frame limit',
      );
    }
    final input = allocate(bytes.length + 1);
    if (input == nullptr) {
      throw NativeTextException(operation, 'Native input allocation rejected');
    }
    Pointer<Uint8> output;
    try {
      input.asTypedList(bytes.length + 1)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      output = request(input);
    } finally {
      releaseInput(input, bytes.length + 1);
    }
    if (output == nullptr) {
      throw NativeTextException(
        operation,
        'Native response is null',
        outcomeUnknown: true,
      );
    }
    try {
      var length = 0;
      while (length < _responseBytes && output[length] != 0) {
        length++;
      }
      if (length == _responseBytes) {
        throw NativeTextException(
          operation,
          'Native response exceeds 24 MiB limit',
          outcomeUnknown: true,
        );
      }
      final value = jsonDecode(utf8.decode(output.asTypedList(length)));
      if (value is! Map<String, dynamic>) {
        throw NativeTextException(
          operation,
          'Native response is not an object',
          outcomeUnknown: true,
        );
      }
      if (value.containsKey('error')) {
        final error = value['error'];
        if (error is! String) {
          throw NativeTextException(
            operation,
            'Malformed native error',
            outcomeUnknown: true,
          );
        }
        throw NativeTextException(
          operation,
          error,
          outcomeUnknown:
              error.contains('outcome unknown') ||
              error.contains('quarantined'),
        );
      }
      return value;
    } on FormatException catch (error) {
      throw NativeTextException(
        operation,
        'Invalid native JSON response: $error',
        outcomeUnknown: true,
      );
    } finally {
      release(output);
    }
  }
}
