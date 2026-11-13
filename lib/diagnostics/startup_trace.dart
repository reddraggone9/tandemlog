import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cold-start phases in milliseconds since the app state started, printed
/// once when the task list first renders: `TANDEMLOG_FIRST_LIST`. The line
/// carries the wall time and, where `/proc` exists (Linux, Android), the
/// process age, so a log reader can line it up with a launch.
///
/// [watchStalls] also reports how long the UI isolate went without returning
/// to its event loop: no frame can be built during such a stretch, so the
/// startup progress bar stands still. `stall_ms` is the longest stretch and
/// `stalls` lists each one of at least [stallFloorMs] as `[start, length]`.
class StartupTrace {
  StartupTrace(this.clock);
  final Stopwatch clock;
  final _phases = <String, int>{};

  /// Include gaps near the 120 Hz frame budget, not just visible freezes.
  static const stallFloorMs = 8;
  final _stalls = <List<int>>[];
  Timer? _heartbeat;
  int _lastBeat = 0, _longestStall = 0;

  /// Starts a 1 ms heartbeat on the calling isolate; [line] ends it.
  void watchStalls() {
    if (_heartbeat != null) return;
    _lastBeat = clock.elapsedMilliseconds;
    _heartbeat = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => _beat(),
    );
  }

  void _beat() {
    final now = clock.elapsedMilliseconds, gap = now - _lastBeat;
    if (gap > _longestStall) _longestStall = gap;
    if (gap >= stallFloorMs) _stalls.add([_lastBeat, gap]);
    _lastBeat = now;
  }

  void dispose() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Records [phase] the first time only.
  void mark(String phase) =>
      _phases.putIfAbsent(phase, () => clock.elapsedMilliseconds);

  String line(String marker) {
    final age = processAgeMs();
    final watched = _heartbeat != null;
    if (watched) {
      // The stretch that ends at this call counts too.
      _beat();
      dispose();
    }
    return '$marker at=${DateTime.now().toIso8601String()} '
        'ms=${clock.elapsedMilliseconds}'
        '${age == null ? '' : ' process_ms=$age'} '
        'phases=${jsonEncode(_phases)}'
        '${watched ? ' stall_ms=$_longestStall stalls=${jsonEncode(_stalls)}' : ''}';
  }

  /// Milliseconds since this process started, or null when unknown.
  static int? processAgeMs() {
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      // Fields after the parenthesized command name; starttime is field 22.
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      final startTicks = int.parse(fields[19]);
      final uptime = double.parse(
        File('/proc/uptime').readAsStringSync().split(' ').first,
      );
      // Linux and Android use 100 clock ticks per second.
      return (uptime * 1000 - startTicks * 10).round();
    } catch (_) {
      return null;
    }
  }
}
