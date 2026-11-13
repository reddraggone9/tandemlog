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
class ReadOnlyLogFolder
    implements LogFolder, BoundedLogFolder, BoundedRangeLogFolder {
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
  // Seek reads let a read session use the history store's fast check.
  @override
  Future<Uint8List?> readFromBounded(
    String name,
    int offset,
    int maximumBytes,
  ) => inner is BoundedRangeLogFolder
      ? (inner as BoundedRangeLogFolder).readFromBounded(
          name,
          offset,
          maximumBytes,
        )
      : Future.value(null);
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
    void Function(String phase)? onPhase,
    bool deferPeerCatchUp = false,
  }) async {
    bool live() => alive?.call() ?? true;
    // Each stage keeps the isolate for a while; a frame of the caller's
    // loading screen may run before the next one starts.
    Future<void> phase(String name) {
      onPhase?.call(name);
      return Future<void>.delayed(Duration.zero);
    }

    UnifiedHistory? unified;
    TaskStore? tasks;
    try {
      final names = await folder.list();
      onPhase?.call('folderList');
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
              deferPeerCatchUp: deferPeerCatchUp,
            );
      await phase('history');
      tasks = await TaskStore.openUnified(unified);
      await phase('tasks');
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
      await phase('food');
      if (!live()) {
        await food.close();
        await tasks.close();
        await unified.close();
        return null;
      }
      Object? migrationError;
      // A deferred app open already admitted this projection; discover any
      // later peer candidates in the caller's mandatory catch-up refresh.
      // Loaded candidates still refresh before each migration write. Ordinary
      // non-deferred/CLI opens retain the full discovery refresh.
      // While known peers remain pending, skip migration until catch-up.
      if (!readOnly && !unified.catchUpPending) {
        final migration = deferPeerCatchUp
            ? await tasks.migrateLoadedOccurrenceDates(canCommit: live)
            : await tasks.migrateOccurrenceDates(canCommit: live);
        migrationError = migration.error;
        onPhase?.call('migration');
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

  /// [sealCache] false is for sessions on a disposable profile copy: the
  /// warm Task cache seal would be discarded with the copy.
  Future<void> close({bool sealCache = true}) async {
    try {
      await food.close();
    } finally {
      try {
        await tasks.close(sealCache: sealCache);
      } finally {
        await history.close();
      }
    }
  }
}
