import '../storage/task_store.dart';
import 'task_text_session.dart';

enum TextSaveStatus { unchanged, saved, savedUndoUnavailable }

class TextSaveResult {
  const TextSaveResult({
    required this.status,
    this.receipt,
    this.currentRow,
    this.undoError,
    this.sessionError,
  });

  final TextSaveStatus status;
  final OperationReceipt? receipt;

  /// The current merged projection after native commit, including remote work.
  /// A missing row means the entity has since been deleted.
  final Map<String, dynamic>? currentRow;
  final Object? undoError;

  /// Native Save succeeded, but renewal of the editor-private draft failed.
  /// The bound preparation remains available to finish renewal on retry.
  final Object? sessionError;
}

/// Publishes one captured native edit together with its observed nontext intent.
/// The session owns unresolved preparation so recreating this command does not
/// change the canonical bytes used by retry.
class TextSaveCommand {
  const TextSaveCommand(this.store, this.session);

  final TaskStore store;
  final TaskTextSession session;

  Future<TextSaveResult> save({
    required Map<String, dynamic> fields,
    required List<String> tags,
    required Map<String, String> observedTagRefs,
    String? expectedSnapshot,
    bool Function()? canCommit,
    void Function(OperationReceipt)? onPrepared,
  }) async {
    if (!session.hasPendingReceipt &&
        (fields.containsKey('title') || fields.containsKey('description'))) {
      throw ArgumentError(
        'Captured text must be saved through its native draft.',
      );
    }
    final prepared = session.prepare();
    final pending = prepared.receipt;
    if (pending != null) {
      // The immutable receipt includes the original fields and tag references.
      // Retry must finish that intent even if today's editor or row has changed.
      if (!store.confirmedOperations([pending]).contains(pending.id)) {
        await store.retryTextOperation(pending);
      }
      return _commit(prepared, pending);
    }
    final tagChanges = calculateTaskTagChanges(tags, observedTagRefs);
    if (prepared.changes.isEmpty) {
      if (fields.isEmpty && tagChanges == null) {
        return const TextSaveResult(status: TextSaveStatus.unchanged);
      }
      OperationReceipt? receipt;
      await store.edit(
        session.capture.entity,
        fields,
        tags: tags,
        observedTagRefs: observedTagRefs,
        expectedTaskSnapshot: expectedSnapshot,
        ignoreSnapshotText: true,
        canCommit: canCommit,
        onPrepared: (value) {
          receipt = value;
          onPrepared?.call(value);
        },
      );
      return TextSaveResult(
        status: TextSaveStatus.saved,
        receipt: receipt,
        currentRow: _currentRow(),
      );
    }

    try {
      await store.editNativeTask(
        session.capture.entity,
        prepared.changes,
        nonText: {...fields, 'tagChanges': ?tagChanges},
        expectedSnapshot: expectedSnapshot,
        canCommit: canCommit,
        onPrepared: (receipt) {
          prepared.bindReceipt(receipt);
          onPrepared?.call(receipt);
        },
      );
    } catch (_) {
      final receipt = prepared.receipt;
      if (receipt == null ||
          !store.confirmedOperations([receipt]).contains(receipt.id)) {
        rethrow;
      }
      // A late failure cannot turn an acknowledged immutable Save into an
      // unsaved edit. Its native commit must still finish below.
    }
    final receipt = prepared.receipt;
    if (receipt == null ||
        !store.confirmedOperations([receipt]).contains(receipt.id)) {
      throw StateError(
        'Native Save lacks its exact canonical acknowledgement.',
      );
    }
    return _commit(prepared, receipt);
  }

  TextSaveResult _commit(
    TaskTextPreparedSave prepared,
    OperationReceipt receipt,
  ) {
    if (!store.confirmedOperations([receipt]).contains(receipt.id)) {
      throw StateError(
        'Native Save lacks its exact canonical acknowledgement.',
      );
    }
    Object? undoError;
    Object? sessionError;
    try {
      prepared.commitReceipt(receipt);
    } catch (error) {
      if (!prepared.committed) rethrow;
      // New draft allocation can fail after all native packets were committed.
      // The canonical Save has still succeeded and must be reported as saved.
      sessionError = error;
    }
    try {
      store.registerTextOperation(receipt, prepared.capture);
    } catch (error) {
      undoError ??= error;
    }
    return TextSaveResult(
      status: undoError == null
          ? TextSaveStatus.saved
          : TextSaveStatus.savedUndoUnavailable,
      receipt: receipt,
      currentRow: _currentRow(),
      undoError: undoError,
      sessionError: sessionError,
    );
  }

  Map<String, dynamic>? _currentRow() {
    for (final row in store.rows) {
      if (row['id'] == session.capture.entity) return Map.unmodifiable(row);
    }
    return null;
  }
}
