import 'dart:async';

/// Foreground import scheduling, not a file transport or background service.
/// Notifications are hints: reconciliation checks stream observations and
/// admits validated new records under the persisted-checkpoint policy.
class ForegroundImporter {
  ForegroundImporter({
    required this.reconcile,
    this.events,
    this.fallback = const Duration(seconds: 15),
    this.debounce = const Duration(milliseconds: 250),
  });
  final Future<void> Function() reconcile;
  final Stream<Object?> Function()? events;
  final Duration fallback, debounce;
  StreamSubscription<Object?>? _subscription;
  Timer? _poll, _debounce;
  bool _active = false, _disposed = false, _running = false, _again = false;
  int _generation = 0;

  void start() {
    if (_active || _disposed) return;
    _active = true;
    _watch();
    _poll = Timer.periodic(fallback, (_) {
      _watch();
      request();
    });
    request();
  }

  void _watch() {
    if (!_active || _subscription != null || events == null) return;
    final generation = _generation;
    try {
      _subscription = events!().listen(
        (_) {
          if (!_active || generation != _generation) return;
          _debounce?.cancel();
          _debounce = Timer(debounce, request);
        },
        onError: (Object _, StackTrace _) {
          if (generation != _generation) return;
          unawaited(_subscription?.cancel());
          _subscription = null;
          request();
        },
        onDone: () {
          if (generation == _generation) _subscription = null;
        },
      );
    } catch (_) {
      // Missing directories/unavailable watcher: reconciliation reports the error,
      // and the bounded foreground fallback attempts to attach again.
    }
  }

  void request() {
    if (!_active || _disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    unawaited(() async {
      try {
        await reconcile();
      } finally {
        _running = false;
        if (_again && _active && !_disposed) {
          _again = false;
          request();
        }
      }
    }());
  }

  void stop() {
    _active = false;
    _generation++;
    _again = false;
    _poll?.cancel();
    _poll = null;
    _debounce?.cancel();
    _debounce = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void dispose() {
    stop();
    _disposed = true;
  }
}
