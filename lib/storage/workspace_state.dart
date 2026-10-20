import '../food/food_store.dart';
import '../domain/time_zone_policy.dart';
import 'task_store.dart';
import 'workspace_view.dart';

export 'workspace_view.dart' show TaskViewSnapshot, FoodViewSnapshot;

typedef WorkspaceListener = void Function(WorkspaceSnapshot snapshot);

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.generation,
    required this.space,
    required this.location,
    required this.epoch,
    required this.historyRevision,
    required this.timeZonePolicy,
    required this.tasks,
    required this.food,
    required this.health,
  });
  final Object generation;
  final String space, location;
  final String? epoch, historyRevision;
  final TimeZoneNamePolicy timeZonePolicy;
  final TaskViewSnapshot tasks;
  final FoodViewSnapshot? food;
  final WorkspaceHealth health;
}

class WorkspaceHealth {
  const WorkspaceHealth({
    required this.revision,
    required this.sharedFailure,
    required this.taskFailure,
    required this.foodFailure,
    required this.hasPendingSave,
    required this.hasPendingTaskSave,
    required this.hasPendingFoodSave,
    required this.incomplete,
    required this.pendingEffects,
    required this.foodPendingReferences,
    required this.taskTextWriteBlocked,
    required this.clockWarning,
    required this.taskWriteReady,
    required this.foodWriteReady,
  });
  final int revision;
  final Object? sharedFailure, taskFailure, foodFailure;
  final bool hasPendingSave, hasPendingTaskSave, hasPendingFoodSave;
  final bool incomplete, pendingEffects;
  final int foodPendingReferences;
  final String? taskTextWriteBlocked, clockWarning;
  final bool taskWriteReady, foodWriteReady;

  List<Object?> get _values => [
    sharedFailure,
    taskFailure,
    foodFailure,
    hasPendingSave,
    hasPendingTaskSave,
    hasPendingFoodSave,
    incomplete,
    pendingEffects,
    foodPendingReferences,
    taskTextWriteBlocked,
    clockWarning,
    taskWriteReady,
    foodWriteReady,
  ];
}

class WorkspaceRefreshResult {
  const WorkspaceRefreshResult(this.snapshot, this.changed, this.migration);
  final WorkspaceSnapshot snapshot;
  final bool changed;
  final OccurrenceDueMigrationResult? migration;
  Object? get migrationError => migration?.error;
  bool get migrationChanged => migration?.changed ?? false;
}

/// One observable display cohort. Store command admission remains authoritative.
/// Closing detaches observation only; the host owns all store/profile lifetimes.
class WorkspaceState {
  WorkspaceState({required this.tasks, this.food}) {
    final foodStore = food;
    if (foodStore != null &&
        (!identical(tasks.profileDatabase, foodStore.profile) ||
            tasks.space != foodStore.space ||
            tasks.folder.location != foodStore.folder.location ||
            !identical(tasks.unified, foodStore.unified))) {
      throw ArgumentError(
        'Workspace stores must share the same admitted cohort.',
      );
    }
    _current = _capture(null);
    final history = tasks.unified;
    if (history != null) {
      _remove.add(history.listenChanges(_publish));
    } else {
      _remove.add(tasks.listenView(_publish));
      if (foodStore != null) _remove.add(foodStore.listenView(_publish));
    }
  }
  final TaskStore tasks;
  final FoodStore? food;
  final Object _generation = Object();
  final _changes = WorkspaceChanges();
  final _remove = <void Function()>[];
  bool _closed = false;
  late WorkspaceSnapshot _current;

  WorkspaceSnapshot get current => _current;
  WorkspaceHealth get health => _current.health;

  void Function() listen(WorkspaceListener listener) {
    if (_closed) throw StateError('Workspace observation is closed.');
    return _changes.listen(() => listener(_current));
  }

  WorkspaceSnapshot _capture(WorkspaceSnapshot? previous) {
    final history = tasks.unified;
    final foodStore = food;
    final sharedPending = history?.viewHasPending ?? false;
    final taskPending = history == null
        ? tasks.viewHasPendingSave
        : sharedPending;
    final foodPending = history == null
        ? (foodStore?.hasPreparedAppend ?? false)
        : sharedPending;
    final taskFailure = history == null ? tasks.viewFailure : null;
    final rawFoodFailure = history == null ? foodStore?.viewFailure : null;
    final sharedFailure =
        history?.safetyFailure ??
        tasks.viewSharedFailure ??
        (rawFoodFailure != null && rawFoodFailure is! FoodHistoryFailure
            ? rawFoodFailure
            : null);
    final foodFailure = rawFoodFailure is FoodHistoryFailure
        ? rawFoodFailure
        : null;
    final incomplete = history?.snapshot.incomplete ?? false;
    final pendingEffects = history?.snapshot.pendingEffects ?? false;
    final pending = taskPending || foodPending;
    final foodReferences = foodStore?.pendingReferences ?? 0;
    final candidate = WorkspaceHealth(
      revision: (previous?.health.revision ?? -1) + 1,
      sharedFailure: sharedFailure,
      taskFailure: taskFailure,
      foodFailure: foodFailure,
      hasPendingSave: pending,
      hasPendingTaskSave: taskPending,
      hasPendingFoodSave: foodPending,
      incomplete: incomplete,
      pendingEffects: pendingEffects,
      foodPendingReferences: foodReferences,
      taskTextWriteBlocked: tasks.textWriteBlocked,
      clockWarning: tasks.clockWarning,
      taskWriteReady:
          sharedFailure == null &&
          taskFailure == null &&
          !taskPending &&
          !incomplete &&
          !pendingEffects,
      foodWriteReady:
          foodStore != null &&
          sharedFailure == null &&
          foodFailure == null &&
          !foodPending &&
          !incomplete &&
          !pendingEffects &&
          foodReferences == 0,
    );
    final health =
        previous != null &&
            workspaceValuesEqual(candidate._values, previous.health._values)
        ? previous.health
        : candidate;
    final taskView = tasks.currentView;
    final foodView = foodStore?.currentView;
    final revision = history?.snapshot.revision;
    if (previous != null &&
        identical(previous.tasks, taskView) &&
        identical(previous.food, foodView) &&
        identical(previous.health, health) &&
        previous.historyRevision == revision &&
        previous.timeZonePolicy == tasks.timeZonePolicy) {
      return previous;
    }
    return WorkspaceSnapshot(
      generation: _generation,
      space: tasks.space,
      location: tasks.folder.location,
      epoch: history?.manifest.epoch,
      historyRevision: revision,
      timeZonePolicy: tasks.timeZonePolicy,
      tasks: taskView,
      food: foodView,
      health: health,
    );
  }

  void _publish() {
    if (_closed) return;
    final candidate = _capture(_current);
    if (identical(candidate, _current)) return;
    _current = candidate;
    _changes.notify();
  }

  Future<WorkspaceRefreshResult> refresh({
    bool migrateOccurrenceDates = false,
    bool Function()? canMigrate,
  }) async {
    if (_closed) throw StateError('Workspace observation is closed.');
    final before = _current;
    OccurrenceDueMigrationResult? migration;
    Object? taskError;
    StackTrace? taskStack;
    try {
      try {
        final result = await tasks.refreshForWorkspace(
          migrateOccurrenceDates: migrateOccurrenceDates,
          canCommit: canMigrate,
        );
        if (migrateOccurrenceDates) migration = result;
      } catch (error, stack) {
        if (tasks.unified != null) rethrow;
        taskError = error;
        taskStack = stack;
      }
      if (tasks.unified == null && food != null) {
        try {
          await food!.refresh();
        } catch (error) {
          // A legacy Task failure must not starve independently valid Food.
          // Its read also classifies shared manifest/profile faults.
          if (error is! FoodHistoryFailure && taskError == null) rethrow;
        }
      }
    } finally {
      _publish();
    }
    if (taskError != null) Error.throwWithStackTrace(taskError, taskStack!);
    return WorkspaceRefreshResult(
      _current,
      !identical(before, _current),
      migration,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final remove in _remove) {
      remove();
    }
    _remove.clear();
    _changes.clear();
  }
}
