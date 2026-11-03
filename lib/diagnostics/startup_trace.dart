import 'dart:convert';
import 'dart:io';

/// Cold-start phases in milliseconds since the app state started, printed
/// once when the task list first renders: `TANDEMLOG_FIRST_LIST`. The line
/// carries the wall time and, where `/proc` exists (Linux, Android), the
/// process age, so a log reader can line it up with a launch.
class StartupTrace {
  StartupTrace(this.clock);
  final Stopwatch clock;
  final _phases = <String, int>{};

  /// Records [phase] the first time only.
  void mark(String phase) =>
      _phases.putIfAbsent(phase, () => clock.elapsedMilliseconds);

  String line(String marker) {
    final age = processAgeMs();
    return '$marker at=${DateTime.now().toIso8601String()} '
        'ms=${clock.elapsedMilliseconds}'
        '${age == null ? '' : ' process_ms=$age'} '
        'phases=${jsonEncode(_phases)}';
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
