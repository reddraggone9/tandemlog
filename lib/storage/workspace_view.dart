import 'dart:async';
import 'dart:typed_data';

import '../food/inventory.dart';

/// Display values, independent of store command reads and durable authority.
class TaskViewSnapshot {
  const TaskViewSnapshot._(this.revision, this.rows, this.users);
  factory TaskViewSnapshot.empty() => const TaskViewSnapshot._(0, [], []);
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
    );
  }

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
