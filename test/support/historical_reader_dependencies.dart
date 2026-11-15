import 'dart:io';

/// Resolve the archived manifest and lockfile, not the current writer's package
/// config. In particular, sqlite3 3.9 adds abstract Database members which the
/// unmodified 3.8-era DiagnosticDatabase cannot implement. The old lib/ stays
/// byte-for-byte intact; its own dependencies and native asset build run here.
Future<void> prepareHistoricalReader({
  required String tree,
  required String dart,
  required String driver,
}) async {
  await File(driver).copy('$tree/driver.dart');
  final cache = dart.indexOf('/bin/cache/');
  if (cache < 0) {
    throw StateError('Historical reader requires the pinned Flutter SDK');
  }
  final flutter = '${dart.substring(0, cache)}/bin/flutter';
  final resolve = await Process.run(flutter, [
    'pub',
    'get',
    '--enforce-lockfile',
  ], workingDirectory: tree);
  if (resolve.exitCode != 0) {
    throw StateError(
      'Historical dependencies: ${resolve.stdout}${resolve.stderr}',
    );
  }
  // dart run materializes this historical sqlite package's native asset. Using
  // the current writer's asset would silently mix two dependency environments.
  final probe = await Process.run(dart, [
    'run',
    '--verbosity=error',
    'driver.dart',
    '--probe',
  ], workingDirectory: tree);
  if (probe.exitCode != 0) {
    throw StateError(
      'Historical reader compile: ${probe.stdout}${probe.stderr}',
    );
  }
}
