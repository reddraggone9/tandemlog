import 'package:uuid/uuid.dart';
import '../domain/event.dart';
import '../domain/text_actor.dart';
import '../storage/task_store.dart';
import '../text/native_text_engine.dart';

/// Editor-private captured drafts. The store retains live owners for Session
/// Undo; closing this session never disposes those documents.
class TaskTextSession {
  TaskTextSession(this.capture, {this.registerDraftActor}) {
    try {
      for (final entry in capture.fields.entries) {
        final field = entry.value;
        if (entry.key != field.field) {
          throw StateError('Text capture ownership mismatch.');
        }
        _leases[entry.key] = (field.allocation, field.actor);
        _drafts[entry.key] = field.document.captureDraft(
          actorClientId: field.actor,
        );
      }
    } catch (_) {
      for (final draft in _drafts.values) {
        draft.cancel();
      }
      rethrow;
    }
  }
  final TaskTextCapture capture;
  final void Function(String field, String allocation, int actor)?
  registerDraftActor;
  final _drafts = <String, NativeTextDraft>{};
  final _leases = <String, (String, int)>{};
  final _edited = <String>{};
  final _partialPackets = <String, NativeTextPreparedSave>{};
  void _advance() {
    final next = <String, NativeTextDraft>{};
    final leases = <String, (String, int)>{};
    try {
      for (final entry in capture.fields.entries) {
        final allocation = const Uuid().v4();
        final actor = deriveTextActor(
          entry.value.context,
          capture.writer,
          allocation,
        );
        registerDraftActor?.call(entry.key, allocation, actor);
        next[entry.key] = entry.value.document.captureDraft(
          actorClientId: actor,
        );
        leases[entry.key] = (allocation, actor);
      }
    } catch (_) {
      for (final draft in next.values) {
        draft.cancel();
      }
      rethrow;
    }
    for (final draft in _drafts.values) {
      draft.cancel();
    }
    _drafts
      ..clear()
      ..addAll(next);
    _leases
      ..clear()
      ..addAll(leases);
    _prepared = null;
    _edited.clear();
    _partialPackets.clear();
  }

  /// Abandon unsaved private content and start from the current live owner.
  /// Cancelled actor leases are never recycled for different content.
  void restart() {
    if (_closed || _prepared?.receipt != null) {
      throw StateError('Cannot restart a pending or closed session.');
    }
    _prepared?.cancel();
    for (final packet in _partialPackets.values) {
      packet.cancel();
    }
    for (final draft in _drafts.values) {
      draft.cancel();
    }
    _advance();
  }

  TaskTextPreparedSave? _prepared;
  bool _closed = false;
  String text(String field) => _drafts[field]!.capturedText;
  bool get frozen => _prepared != null || _partialPackets.isNotEmpty;
  bool get hasPendingReceipt => _prepared?.receipt != null;
  bool get hasTextChanges => _edited.isNotEmpty;
  void replace(String field, String text, {bool composing = false}) {
    if (_closed || frozen) throw StateError('Text editing session is frozen.');
    final draft =
        _drafts[field] ?? (throw StateError('Uncaptured text field.'));
    draft.setComposing(composing);
    final changed = draft.capturedText != text;
    draft.replaceText(text);
    if (changed) _edited.add(field);
  }

  TaskTextPreparedSave prepare() {
    if (_closed) throw StateError('Text editing session is closed.');
    if (_prepared != null) return _prepared!;
    if (_edited.isEmpty) {
      return TaskTextPreparedSave._(
        capture,
        const {},
        Map.of(_leases),
        _advance,
      );
    }
    if (_drafts.values.any((draft) => draft.isComposing)) {
      throw StateError('Finish composing text before saving.');
    }
    // Keep successful preparations intact if a later field rejects. No private
    // document is consumed until every field has prepared successfully.
    for (final entry in _drafts.entries) {
      if (!_edited.contains(entry.key) ||
          _partialPackets.containsKey(entry.key)) {
        continue;
      }
      _partialPackets[entry.key] = entry.value.prepareSave();
    }
    final packets = <String, NativeTextPreparedSave>{
      for (final entry in _partialPackets.entries)
        if (!(entry.value.update.bytes.length == 2 &&
            entry.value.update.bytes[0] == 0 &&
            entry.value.update.bytes[1] == 0))
          entry.key: entry.value,
    };
    final prepared = TaskTextPreparedSave._(
      capture,
      packets,
      Map.of(_leases),
      _advance,
    );
    if (packets.isEmpty) {
      _advance();
      return prepared;
    }
    return _prepared = prepared;
  }

  /// Kept live by the store even after the private editor has closed.
  TaskTextOwnerUndo prepareUndo(String field) {
    final owner =
        capture.fields[field] ?? (throw StateError('Uncaptured text field.'));
    final packet = owner.document.prepareUndo();
    return TaskTextOwnerUndo(owner, packet);
  }

  void cancel() {
    if (_closed) return;
    if (_prepared?.receipt != null && !_prepared!.committed) {
      throw StateError('Resolve the pending durable text save before closing.');
    }
    _prepared?.cancel();
    for (final packet in _partialPackets.values) {
      packet.cancel();
    }
    for (final draft in _drafts.values) {
      draft.cancel();
    }
    _closed = true;
  }
}

class TaskTextPreparedSave {
  TaskTextPreparedSave._(
    this.capture,
    this._packets,
    Map<String, (String, int)> leases,
    this._advance,
  ) : preCommitCheckpoints = Map.unmodifiable({
        for (final field in _packets.keys)
          field: capture.fields[field]!.document.checkpoint(),
      }),
      changes = Map.unmodifiable({
        for (final entry in _packets.entries)
          entry.key: Map<String, dynamic>.unmodifiable({
            'context': capture.fields[entry.key]!.context,
            'allocation': leases[entry.key]!.$1,
            'actor': leases[entry.key]!.$2,
            'update': entry.value.update.encoded,
          }),
      });
  final TaskTextCapture capture;
  final Map<String, NativeTextPreparedSave> _packets;
  final Map<String, Map<String, dynamic>> changes;
  final Map<String, NativeTextCheckpoint> preCommitCheckpoints;
  Set<String> get changedFields => Set.unmodifiable(changes.keys);
  OperationReceipt? _receipt;
  OperationReceipt? get receipt => _receipt;
  bool committed = false;
  bool _advanced = false;
  final void Function() _advance;
  void bindReceipt(OperationReceipt receipt) {
    if (changes.isEmpty) {
      throw StateError('No native text changes to acknowledge.');
    }
    final event = LogEvent.decode(receipt.raw);
    if (event.id != receipt.id ||
        event.entity != capture.entity ||
        receipt.entity != capture.entity ||
        event.type != 'task.textEdited' ||
        canonicalDataJson(event.data['changes']) !=
            canonicalDataJson(changes)) {
      throw StateError(
        'Durable text receipt does not match the prepared save.',
      );
    }
    if (_receipt != null &&
        (_receipt!.raw != receipt.raw || _receipt!.id != receipt.id)) {
      throw StateError('Prepared save already belongs to another receipt.');
    }
    _receipt = receipt;
  }

  /// Caller must first confirm these exact bytes in canonical storage.
  void commitReceipt(OperationReceipt receipt) {
    bindReceipt(receipt);
    if (!committed) {
      for (final packet in _packets.values) {
        packet.commit(receiptUpdate: packet.update);
      }
      committed = true;
    }
    if (!_advanced) {
      _advance();
      _advanced = true;
    }
  }

  void cancel() {
    if (_receipt != null && !committed) {
      throw StateError('Durable save outcome is unresolved.');
    }
    if (committed) return;
    for (final packet in _packets.values) {
      packet.cancel();
    }
  }
}

/// Retains the fixed live document identity; never uses an editor Save lease.
class TaskTextOwnerUndo {
  TaskTextOwnerUndo(this.owner, this.packet);
  final TaskTextFieldCapture owner;
  final NativeTextPreparedUndo packet;
  Map<String, dynamic> get change => Map.unmodifiable({
    'context': owner.context,
    'allocation': owner.undoAllocation,
    'actor': owner.undoActor,
    'update': packet.update.encoded,
  });
}
