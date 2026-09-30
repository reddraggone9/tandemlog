import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/timed_view.dart';
import '../domain/wall_time.dart';

/// Foreground platform observation; never reads or writes task storage.
/// Unknown zone identities remain explicit errors rather than UTC guesses.
class ViewTimeSource {
  ViewTimeSource({
    required this.onChanged,
    MethodChannel? channel,
    Future<String> Function()? loadZone,
    DateTime Function()? now,
    this.fallbackInterval = const Duration(minutes: 1),
  }) : _channel = channel ?? const MethodChannel('tandemlog/time'),
       _loadZone = loadZone,
       _now = now ?? DateTime.now {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && _active) await _refresh(force: true);
    });
  }

  final void Function() onChanged;
  final MethodChannel _channel;
  final Future<String> Function()? _loadZone;
  final DateTime Function() _now;
  final Duration fallbackInterval;
  String? _zone;
  String? error;
  bool _active = false, _disposed = false;
  int _generation = 0, _request = 0;
  Timer? _fallback;
  StreamSubscription<FileSystemEvent>? _watch;
  bool get ready => _zone != null && error == null;

  ViewTime readTime() {
    if (!ready) throw StateError(error ?? 'Local time zone is loading.');
    final instant = _now().toUtc();
    return ViewTime(
      instant: instant,
      localZoneId: _zone!,
      localOffset: tz.TZDateTime.from(
        instant,
        timeZoneLocation(_zone!),
      ).timeZoneOffset,
    );
  }

  void start() {
    if (_disposed || _active) return;
    _active = true;
    _zone = null;
    error = null;
    _generation++;
    unawaited(_native('start'));
    unawaited(_refresh(force: true));
    _fallback = Timer.periodic(fallbackInterval, (_) => unawaited(_refresh()));
    if (Platform.isLinux && _loadZone == null) {
      try {
        // Watch the parent so atomic replacement does not detach the watch.
        _watch = Directory('/etc').watch().listen((event) {
          if (event.path.endsWith('/localtime') ||
              event.path.endsWith('/timezone')) {
            unawaited(_refresh());
          }
        }, onError: (_) {}); // periodic recovery remains active
      } on FileSystemException {
        /* periodic recovery remains active */
      }
    }
  }

  void stop() {
    _active = false;
    _generation++;
    _fallback?.cancel();
    _fallback = null;
    unawaited(_watch?.cancel());
    _watch = null;
    unawaited(_native('stop'));
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _native(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      /* tests or unsupported host: fallback only */
    } on PlatformException {
      /* foreground fallback remains active */
    }
  }

  Future<void> _refresh({bool force = false}) async {
    final generation = _generation;
    final request = ++_request;
    final previousZone = _zone, previousError = error;
    try {
      final zone = await (_loadZone?.call() ?? _platformZone());
      timeZoneLocation(zone); // validates against the same rules as projection
      if (!_active ||
          _disposed ||
          generation != _generation ||
          request != _request) {
        return;
      }
      _zone = zone;
      error = null;
    } catch (_) {
      if (!_active ||
          _disposed ||
          generation != _generation ||
          request != _request) {
        return;
      }
      error =
          'Cannot determine this device’s time zone. Check system date and time settings.';
    }
    if (force || previousZone != _zone || previousError != error) onChanged();
  }

  Future<String> _platformZone() async {
    final String zone;
    final int offsetSeconds;
    if (Platform.isLinux) {
      zone = await readLinuxZone();
      offsetSeconds = DateTime.now().timeZoneOffset.inSeconds;
    } else {
      final observed = await _channel.invokeMapMethod<String, dynamic>('zone');
      if (observed?['id'] is! String || observed?['offsetSeconds'] is! int) {
        throw StateError('Missing native time zone observation.');
      }
      zone = observed!['id'] as String;
      offsetSeconds = observed['offsetSeconds'] as int;
    }
    validateLocalOffset(
      zone,
      DateTime.now().toUtc(),
      Duration(seconds: offsetSeconds),
    );
    return zone;
  }
}

Future<String> readLinuxZone({
  Map<String, String>? environment,
  String etcPath = '/etc',
  String zoneInfoPath = '/usr/share/zoneinfo',
}) async {
  final configured = (environment ?? Platform.environment)['TZ'];
  if (configured != null && configured.isNotEmpty) {
    final value = configured.startsWith(':')
        ? configured.substring(1)
        : configured;
    if (!value.startsWith('/')) return value;
    final resolved = await File(value).resolveSymbolicLinks();
    final marker = '/zoneinfo/';
    if (resolved.contains(marker)) return resolved.split(marker).last;
    throw StateError('TZ path has no IANA identity.');
  }
  final resolved = await File('$etcPath/localtime').resolveSymbolicLinks();
  if (resolved.contains('/zoneinfo/')) return resolved.split('/zoneinfo/').last;
  final name = (await File('$etcPath/timezone').readAsString()).trim();
  if (name.isEmpty || name.startsWith('/') || name.split('/').contains('..')) {
    throw StateError('Missing IANA timezone.');
  }
  // A copied localtime file has no identity. Trust the distro's identity file
  // only when its named zone is exactly the file the system actually uses.
  final localBytes = await File('$etcPath/localtime').readAsBytes();
  final zoneBytes = await File('$zoneInfoPath/$name').readAsBytes();
  if (localBytes.length != zoneBytes.length) {
    throw StateError('Inconsistent system zone files.');
  }
  for (var i = 0; i < localBytes.length; i++) {
    if (localBytes[i] != zoneBytes[i]) {
      throw StateError('Inconsistent system zone files.');
    }
  }
  return name;
}

/// Refuse OS configurations that disagree with the mapped IANA rules instead
/// of silently applying DST or a fixed offset that the device does not use.
void validateLocalOffset(String zone, DateTime instant, Duration nativeOffset) {
  final mapped = tz.TZDateTime.from(
    instant,
    timeZoneLocation(zone),
  ).timeZoneOffset;
  if (mapped != nativeOffset) {
    throw StateError(
      'System time-zone offset differs from supported IANA rules.',
    );
  }
}
