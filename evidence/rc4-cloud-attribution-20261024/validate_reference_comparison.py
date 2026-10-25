"""Read-only current-source reference checks; never grants release acceptance."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
CONFIG_KEYS = {'project/.dart_tool/package_config.json',
               'staged/.dart_tool/package_config.json'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def object_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def only(items):
    values = list(items)
    if len(values) != 1:
        raise ValueError('Expected one unambiguous path binding')
    return values[0]


def inventory(report):
    """Rename installation roots only; retain every relative path and byte hash."""
    project = only(p[:-len('tool/performance/run_gate.py')]
                   for p in report['sourcePins'] if p.endswith('/tool/performance/run_gate.py'))
    staged = only(p[:-len('.dart_tool/package_config.json')]
                  for p in report['toolPins'] if p.endswith('/.dart_tool/package_config.json'))
    flutter = only(p[:-len('bin/cache/dart-sdk/bin/dart')]
                   for p in report['toolPins'] if p.endswith('/bin/cache/dart-sdk/bin/dart'))

    def rename(path):
        for prefix, label in ((staged, 'staged/'), (project, 'project/'),
                              (flutter, 'flutter/')):
            if path.startswith(prefix):
                return label + path[len(prefix):]
        marker = '/hosted/pub.dev/'
        if path.count(marker) == 1:
            return 'pub/' + path.split(marker)[1]
        raise ValueError(f'Unrecognized compiled path: {path}')

    normalized = {}
    for path, value in report['compiledSourceAndDependencyPins'].items():
        key = rename(path)
        if key in normalized:
            raise ValueError(f'Compiled path collision: {key}')
        normalized[key] = value
    if not CONFIG_KEYS <= set(normalized):
        raise ValueError('Missing original or staged package configuration')
    return {'count': len(normalized),
            'contentSHA256': object_digest({k: v for k, v in normalized.items()
                                           if k not in CONFIG_KEYS}),
            'packageConfigurationHashes': {k: normalized[k] for k in sorted(CONFIG_KEYS)},
            'importClosureSHA256': object_digest(sorted(rename(p) for p in report['projectImportClosure'])),
            'compiledFileSealsSHA256': object_digest(report['compiledFileSeals'])}


def verify_inventory(report, pins):
    actual = inventory(report)
    for key in ('count', 'contentSHA256', 'importClosureSHA256', 'compiledFileSealsSHA256'):
        if actual[key] != pins['compiledInventory'][key]:
            raise ValueError(f'Compiled inventory mismatch: {key}')
    return actual


def preflight(source, pins):
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != pins['sourceSHA']:
        raise ValueError('Measurement copy must be the exact pinned product commit')
    if subprocess.run(['git', '-C', str(source), 'symbolic-ref', '-q', 'HEAD'],
                      stdout=subprocess.DEVNULL).returncode != 1:
        raise ValueError('Measurement copy must have a detached HEAD')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain',
                                '--untracked-files=no'], text=True).strip():
        raise ValueError('Measurement copy has tracked or staged changes')
    for name, expected in pins['sourceFiles'].items():
        if digest(source / name) != expected:
            raise ValueError(f'Source pin mismatch: {name}')
    flutter = shutil.which('flutter')
    if not flutter:
        raise ValueError('Reviewed Linux Flutter must be in PATH')
    sdk = Path(flutter).resolve().parent / 'cache/dart-sdk'
    for path, expected in ((sdk / 'bin/dart', pins['dartSHA256']),
                           (sdk / 'bin/utils/gen_snapshot', pins['genSnapshotSHA256']),
                           (Path(os.environ['TANDEMLOG_TEXT_LIBRARY']), pins['nativeSHA256']),
                           (source / '.dart_tool/lib/libsqlite3.so', pins['sqliteSHA256'])):
        if digest(path) != expected:
            raise ValueError(f'Tool/library pin mismatch: {path.name}')


def validate_report(report, pins, source):
    flags = {'measurementCompleted': True, 'allPinsMatch': True,
             'measureOnly': True, 'releaseGateAccepted': False,
             'costDiagnosticsEnabled': False}
    if (any(report.get(k) is not v for k, v in flags.items()) or
            report.get('rerunsUsed') != 0 or report.get('error')):
        raise ValueError('Missing complete uninstrumented diagnostic-only report')
    if report.get('resourceBounds') != pins['resourceBounds']:
        raise ValueError('Actual resource bounds differ from the hosted comparison')
    if report.get('sourceRewrites') != [] or report.get('shimAllowlist') != []:
        raise ValueError('Measured source has rewrites or shims')
    actual = report['sourcePins']
    if len(actual) != len(pins['sourceFiles']):
        raise ValueError('Source inventory differs')
    for relative, expected in pins['sourceFiles'].items():
        if [v for name, v in actual.items() if name.endswith('/' + relative)] != [expected]:
            raise ValueError(f'Recorded source mismatch: {relative}')
    hashes = set(report['toolPins'].values())
    if not {pins[k] for k in ('dartSHA256', 'nativeSHA256', 'sqliteSHA256', 'limitsSHA256')} <= hashes:
        raise ValueError('Recorded tool/library/limit pins differ')
    compiled = verify_inventory(report, pins)
    fixtures = {name: {k: v for k, v in item['contract'].items() if k != 'workspace'}
                for name, item in report['fixtures'].items()}
    if fixtures != pins['fixtures']:
        raise ValueError('Canonical fixture bytes or non-path contract differ')
    attempts = report['attempts']
    if len(attempts) != 3 or {a['size'] for a in attempts} != set(pins['fixtures']):
        raise ValueError('Missing complete three-shape attempt inventory')
    limits_path = source / 'tool/performance/limits-v1.json'
    policy_path = source / 'tool/performance/gate_policy.py'
    if (digest(limits_path) != pins['limitsSHA256'] or
            digest(policy_path) != pins['sourceFiles']['tool/performance/gate_policy.py']):
        raise ValueError('Evaluation policy or limits differ')
    spec = importlib.util.spec_from_file_location('reference_gate_policy', policy_path)
    policy = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = policy
    spec.loader.exec_module(policy)
    limits = json.loads(limits_path.read_text())
    limits['sha256'] = pins['limitsSHA256']
    summaries = {}
    for attempt in attempts:
        execution = attempt['execution']
        if attempt['attempt'] != 0 or execution['exitCode'] != 0 or execution['childAbsent'] is not True:
            raise ValueError('Incomplete execution or repeated timing attempt')
        decision = policy.evaluate(attempt['result'], limits)
        if (decision.status == 'correctness-failed' or decision.status != attempt['status'] or
                list(decision.failures) != attempt['failures'] or decision.summaries != attempt['summaries']):
            raise ValueError('Absolute evaluation, coverage or sample ordering differs')
        summaries[attempt['size']] = decision.summaries
    comparisons = {'task-own-history': limits['pairedScaling'], **limits['additionalPairedScaling']}
    recorded = report['pairedScalingAttempts']
    if len(recorded) != len(comparisons) or {r['comparison'] for r in recorded} != set(comparisons):
        raise ValueError('Paired evaluation inventory differs')
    for item in recorded:
        rule = comparisons[item['comparison']]
        decision = policy.evaluate_scaling(summaries, rule, fixtures)
        if (item['attempt'] != 0 or decision.status == 'correctness-failed' or
                item['smallSize'] != rule['smallSize'] or item['largeSize'] != rule['largeSize'] or
                decision.status != item['status'] or list(decision.failures) != item['failures'] or
                decision.summaries != item['comparisons']):
            raise ValueError('Paired evaluation differs')
    return {'comparisonDataComplete': True, 'releaseGateAccepted': False,
            'absoluteFailures': sum(len(a['failures']) for a in attempts),
            'pairedFailures': sum(len(p['failures']) for p in recorded),
            'compiledInventory': compiled,
            'packageConfigurationPathOnlyReviewRequired': True,
            'qualification': 'Review both local package configurations before proceeding; byte differences are reported, never silently accepted as path-only.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['preflight', 'report'])
    parser.add_argument('target', type=Path)
    parser.add_argument('pins', type=Path)
    parser.add_argument('--source', type=Path,
                        help='Exact immutable source copy, required for report policy checks')
    args = parser.parse_args()
    pins = json.loads(args.pins.read_text())
    if args.mode == 'preflight':
        preflight(args.target.resolve(), pins)
        print('Exact detached source/tool preflight verified; no benchmark launched')
    else:
        if args.source is None:
            parser.error('report requires --source')
        preflight(args.source.resolve(), pins)
        print(json.dumps(validate_report(json.loads(args.target.read_text()), pins, args.source.resolve()), indent=2))


if __name__ == '__main__':
    main()
