import 'dart:async';

import '../domain/timed_view.dart';

typedef ScheduleWake = Timer Function(Duration delay, void Function() callback);

/// Foreground-only invalidation. It knows nothing about task storage or widgets.
/// The owner calls invalidate after input changes or native clock/zone signals,
/// start on resume/focus, stop on suspension, and dispose on workspace teardown.
class ViewClock<T> {
  ViewClock({
    required this.readTime,
    required this.monotonicNow,
    required this.project,
    required this.onView,
    ScheduleWake? schedule,
    this.watchdog = const Duration(minutes: 1),
    this.jumpTolerance = const Duration(seconds: 1),
  }) : _schedule = schedule ?? Timer.new {
    if (watchdog <= Duration.zero || jumpTolerance < Duration.zero) {
      throw ArgumentError('Invalid clock watchdog configuration.');
    }
  }

  final ViewTime Function() readTime;
  final Duration Function() monotonicNow;
  final ViewProjection<T> project;
  final void Function(TimedView<T> view) onView;
  final ScheduleWake _schedule;
  final Duration watchdog;
  final Duration jumpTolerance;
  Timer? _timer;
  ViewTime? _observed;
  Duration? _elapsed;
  DateTime? _boundary;
  bool _active = false, _disposed = false;
  int _generation = 0;

  void start() {
    if (_disposed) return;
    _active = true;
    invalidate();
  }

  void stop() {
    _active = false;
    _cancel();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  void _cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void invalidate() {
    if (!_active || _disposed) return;
    _cancel();
    final generation = _generation;
    final time = readTime();
    final elapsed = monotonicNow();
    final view = project(time);
    if (view.nextChange != null && !view.nextChange!.isAfter(time.instant)) {
      throw StateError('A view boundary must be strictly in the future.');
    }
    _observed = time;
    _elapsed = elapsed;
    _boundary = view.nextChange?.toUtc();
    onView(view);
    // A callback may replace inputs, pause or dispose this controller.
    if (_active && !_disposed && generation == _generation) _arm();
  }

  void _arm() {
    var delay = watchdog;
    final remaining = _boundary?.difference(readTime().instant);
    if (remaining != null && remaining < delay) {
      delay = remaining.isNegative ? Duration.zero : remaining;
    }
    final generation = _generation;
    _timer = _schedule(delay, () {
      if (!_active || _disposed || generation != _generation) return;
      _timer = null;
      final now = readTime();
      final elapsed = monotonicNow();
      final wallDelta = now.instant.difference(_observed!.instant);
      final steadyDelta = elapsed - _elapsed!;
      final jump = (wallDelta - steadyDelta).abs() > jumpTolerance;
      if (jump ||
          !now.sameZone(_observed!) ||
          (_boundary != null && !now.instant.isBefore(_boundary!))) {
        invalidate();
      } else {
        // No full projection for an ordinary watchdog wake-up.
        _observed = now;
        _elapsed = elapsed;
        _arm();
      }
    });
  }
}
