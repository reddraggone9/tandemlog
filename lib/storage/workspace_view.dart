import 'dart:async';
import 'dart:typed_data';

import '../food/inventory.dart';

/// Display values, independent of store command reads and durable authority.
class TaskViewSnapshot {
  const TaskViewSnapshot._(
    this.revision,
    this.rows,
    this.users,
    this._rowIndices,
  );
  factory TaskViewSnapshot.empty() => const TaskViewSnapshot._(0, [], [], {});
  static TaskViewSnapshot next(
    List<Map<String, dynamic>> rows,
    TaskViewSnapshot previous,
  ) {
    if (workspaceValuesEqual(rows, previous.rows)) return previous;
    final frozen = List<Map<String, dynamic>>.unmodifiable(
      rows.map((row) => freezeWorkspaceValue(row) as Map<String, dynamic>),
    );
    final users = frozen.where((row) => row['kind'] == 'user').toList();
    return TaskViewSnapshot._(
      previous.revision + 1,
      frozen,
      workspaceValuesEqual(users, previous.users)
          ? previous.users
          : List.unmodifiable(users),
      Map.unmodifiable({
        for (var i = 0; i < frozen.length; i++)
          if (frozen[i]['id'] is String) frozen[i]['id'] as String: i,
      }),
    );
  }

  /// Patch a certified projection delta without decoding or freezing its
  /// unchanged rows. An insertion needs the ordered full projection: the
  /// caller must not infer a new row position from event arrival order.
  static TaskViewSnapshot? replacing(
    Map<String, Map<String, dynamic>?> changes,
    TaskViewSnapshot previous,
  ) {
    for (final entry in changes.entries) {
      if (entry.value != null &&
          (entry.value!['id'] != entry.key ||
              !previous._rowIndices.containsKey(entry.key))) {
        return null;
      }
    }
    List<Map<String, dynamic>>? next;
    final removed = <String>{};
    for (final entry in changes.entries) {
      final index = previous._rowIndices[entry.key];
      if (index == null) continue;
      final value = entry.value;
      if (value == null) {
        removed.add(entry.key);
      } else if (!workspaceValuesEqual(value, previous.rows[index])) {
        next ??= previous.rows.toList();
        next[index] = freezeWorkspaceValue(value) as Map<String, dynamic>;
      }
    }
    if (next == null && removed.isEmpty) return previous;
    final rows = List<Map<String, dynamic>>.unmodifiable(
      (next ?? previous.rows).where((row) => !removed.contains(row['id'])),
    );
    final users = rows.where((row) => row['kind'] == 'user').toList();
    return TaskViewSnapshot._(
      previous.revision + 1,
      rows,
      workspaceValuesEqual(users, previous.users)
          ? previous.users
          : List.unmodifiable(users),
      removed.isEmpty
          ? previous._rowIndices
          : Map.unmodifiable({
              for (var i = 0; i < rows.length; i++)
                if (rows[i]['id'] is String) rows[i]['id'] as String: i,
            }),
    );
  }

  final Map<String, int> _rowIndices;
  final int revision;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> users;
}

class FoodViewSnapshot {
  const FoodViewSnapshot._(this.revision, this.state);
  factory FoodViewSnapshot.empty() => FoodViewSnapshot._(0, FoodState([]));
  static FoodViewSnapshot next(FoodState state, FoodViewSnapshot previous) {
    if (identical(state, previous.state) ||
        workspaceValuesEqual(
          state.containers.map((item) => item.toJson()).toList(),
          previous.state.containers.map((item) => item.toJson()).toList(),
        )) {
      return previous;
    }
    return FoodViewSnapshot._(previous.revision + 1, state);
  }

  final int revision;
  final FoodState state;
}

/// Only JSON-like display values and copied unmodifiable byte views escape SQL.
Object? freezeWorkspaceValue(Object? value) {
  if (value is Uint8List) {
    return Uint8List.fromList(value).asUnmodifiableView();
  }
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: freezeWorkspaceValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(freezeWorkspaceValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(freezeWorkspaceValue));
  }
  return value;
}

/// Typed structural comparison; native int64 projection fields stay integers.
bool workspaceValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && workspaceValuesEqual(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!workspaceValuesEqual(a[index], b[index])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length && a.every(b.contains);
  }
  return a.runtimeType == b.runtimeType && a == b;
}

/// Synchronous state observation; observer faults cannot alter durable outcomes.
class WorkspaceChanges {
  final _listeners = <void Function()>{};
  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void notify() {
    for (final listener in _listeners.toList()) {
      if (!_listeners.contains(listener)) continue;
      try {
        listener();
      } catch (error, stack) {
        final zone = Zone.current;
        scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
      }
    }
  }

  void clear() => _listeners.clear();
}
