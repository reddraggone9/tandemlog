import 'dart:io';

import 'package:timezone/timezone.dart' as tz;

import '../domain/wall_time.dart';

/// Flutter-free host zone observation, shared by the app and the agent CLI.
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
