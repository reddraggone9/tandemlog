// Focused diagnostic only: never produces a qualification receipt.
// Reuses the exact benchmark scenarios, including correctness/replay checks.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'benchmark.dart' as benchmark;
import 'synthetic_fixture.dart' show fixtureSchemaVersion;

Future<void> main(List<String> args) async {
  benchmark.require(
    args.length == 2,
    'Usage: food_tail_diagnostic NEW_OUTPUT_ROOT SYNTHETIC_FIXTURE_MANIFEST',
  );
  final root = Directory(args[0]);
  benchmark.require(
    root.path == root.absolute.path && !await root.exists(),
    'Refuse nonabsolute/existing diagnostic output',
  );
  final fixture = Map<String, dynamic>.from(
    jsonDecode(await File(args[1]).readAsString()) as Map,
  );
  benchmark.require(
    fixture['schemaVersion'] == fixtureSchemaVersion &&
        fixture['syntheticOnly'] == true &&
        [1320, 2640].contains(fixture['baseHistoricalRecords']),
    'Require existing dense synthetic fixture contract',
  );
  benchmark.require(
    Platform.environment['TANDEMLOG_TEXT_LIBRARY']?.isNotEmpty == true,
    'Pinned native library required',
  );
  await root.create(recursive: true);
  final config = <String, dynamic>{
    'authorizedRuntimeReady': true,
    'runRoot': '${root.path}/workloads',
    'sealedWorkspacePath': fixture['workspace'],
    'sealedFiles': fixture['files'],
    'fixtureWriter': fixture['writer'],
    'fixtureBaseIdentity': 1320,
    'diagnosticCosts': true,
  };
  // Keep each family's setup and action ordering unchanged. The broader suite's
  // process/heap history is intentionally absent; these are not replacement
  // acceptance samples and cannot retrospectively attribute the failed run.
  await benchmark.scenario(
    config,
    'food-historical',
    (audit) => benchmark.foodCommands(audit, historical: true),
  );
  await benchmark.scenario(
    config,
    'converted-food-confirmed',
    benchmark.convertedConfirmedFood,
  );
  print(
    jsonEncode({
      'measurement': 'focused-food-diagnostic-complete',
      'releaseGateAccepted': false,
      'timingRole': 'diagnostic-only',
      'costDiagnosticsEnabled': true,
      'families': 2,
      'warmups': benchmark.benchmarkWarmups,
      'samples': benchmark.benchmarkSamples,
      'fixtureManifest': args[1],
      'scope': 'AOT storage/application; no UI; reduced process/heap history',
    }),
  );
}
