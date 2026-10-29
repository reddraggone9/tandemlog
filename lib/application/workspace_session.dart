import 'dart:typed_data';

import '../food/food_store.dart';
import '../storage/local_profile_database.dart';
import '../storage/log_folder.dart';
import '../storage/task_store.dart';
import '../storage/unified_history.dart';
import '../text/native_text_engine.dart';

/// Raised when a read-only session would have to write canonical bytes, such
/// as joining an unknown installation or confirming a pending operation.
class ReadOnlyWorkspaceWrite implements Exception {
  const ReadOnlyWorkspaceWrite(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Refuses every canonical mutation. Reads cannot join, clean an owned tail or
/// confirm an outbox; any such attempt fails closed before touching the folder.
class ReadOnlyLogFolder implements LogFolder, BoundedLogFolder {
  ReadOnlyLogFolder(this.inner) : assert(inner is BoundedLogFolder);
  final LogFolder inner;
  static const _refusal = ReadOnlyWorkspaceWrite(
    'This read would change shared history. Run a write command first.',
  );
  @override
  String get location => inner.location;
  @override
  Future<List<LogFileInfo>> list() => inner.list();
  @override
  Future<Uint8List> read(String name) => inner.read(name);
  @override
  Future<Uint8List> readBounded(String name, int maximumBytes) =>
      (inner as BoundedLogFolder).readBounded(name, maximumBytes);
  @override
  Future<void> append(String name, Uint8List bytes) => Future.error(_refusal);
  @override
  Future<void> create(String name, Uint8List bytes) => Future.error(_refusal);
}

/// The open sequence shared by the app and the agent CLI: history → Tasks →
/// shared text → Food → open-time maintenance. [alive] lets a caller abandon a
/// half-open session (the app checks `mounted`); abandoned stores are closed.
class WorkspaceSession {
  WorkspaceSession._(
    this.history,
    this.tasks,
    this.food,
    this.occurrenceMigrationError,
  );
  final UnifiedHistory history;
  final TaskStore tasks;
  final FoodStore food;

  /// Failure of the open-time occurrence-date migration, if any. The
  /// workspace remains usable; the app shows it beside the task list.
  final Object? occurrenceMigrationError;

  bool get hasPendingOperation =>
      history.hasPending || tasks.pendingTextOperations.isNotEmpty;

  /// Returns null when [alive] turned false; nothing is left open then.
  ///
  /// A [readOnly] session never creates a workspace, never initializes shared
  /// text and skips the occurrence-date migration; its folder must refuse
  /// writes (see [ReadOnlyLogFolder]) so nothing else can append either.
  static Future<WorkspaceSession?> open(
    LogFolder folder, {
    required LocalProfileDatabase profile,
    required String writer,
    required NativeTextEngine textEngine,
    bool readOnly = false,
    bool Function()? alive,
  }) async {
    bool live() => alive?.call() ?? true;
    UnifiedHistory? unified;
    TaskStore? tasks;
    try {
      final names = await folder.list();
      if (names.isEmpty && readOnly) {
        throw const ReadOnlyWorkspaceWrite(
          'The workspace folder is empty. Initialize it first.',
        );
      }
      unified = names.isEmpty
          ? await UnifiedHistory.create(
              folder,
              profile: profile,
              writer: writer,
              textEngine: textEngine,
            )
          : await UnifiedHistory.open(
              folder,
              profile: profile,
              writer: writer,
              textEngine: textEngine,
            );
      tasks = await TaskStore.openUnified(unified);
      if (!readOnly &&
          !tasks.sharedTextInitialized &&
          unified.snapshot.tasks.isEmpty) {
        await tasks.initializeSharedText();
      }
    } catch (_) {
      await tasks?.close();
      await unified?.close();
      rethrow;
    }
    FoodStore? food;
    try {
      if (!live()) {
        await tasks.close();
        await unified.close();
        return null;
      }
      if (folder is! BoundedLogFolder) {
        throw const FoodHistoryFailure(
          'This folder cannot enforce safe Food reads. Tasks remain available.',
        );
      }
      food = await FoodStore.openUnified(unified);
      if (!live()) {
        await food.close();
        await tasks.close();
        await unified.close();
        return null;
      }
      Object? migrationError;
      if (!readOnly) {
        final migration = await tasks.migrateOccurrenceDates(canCommit: live);
        migrationError = migration.error;
        if (!live()) {
          await food.close();
          await tasks.close();
          await unified.close();
          return null;
        }
      }
      return WorkspaceSession._(unified, tasks, food, migrationError);
    } catch (_) {
      await food?.close();
      await tasks.close();
      await unified.close();
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await food.close();
    } finally {
      try {
        await tasks.close();
      } finally {
        await history.close();
      }
    }
  }
}
