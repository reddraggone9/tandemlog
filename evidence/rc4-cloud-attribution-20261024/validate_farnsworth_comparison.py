"""Read-only validator for the pinned e23 diagnostic comparison, not acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def preflight(source, pins):
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != pins['sourceSHA']:
        raise ValueError('Measurement copy must be exact detached e23 source')
    subprocess.run(['git', '-C', str(source), 'diff', '--exit-code'], check=True)
    for name, expected in pins['sourceFiles'].items():
        if digest(source / name) != expected:
            raise ValueError(f'Source pin mismatch: {name}')
    flutter = shutil.which('flutter')
    if not flutter:
        raise ValueError('Reviewed Linux Flutter must be in PATH')
    sdk = Path(flutter).parent / 'cache/dart-sdk'
    for path, expected in ((sdk / 'bin/dart', pins['dartSHA256']),
                           (sdk / 'bin/utils/gen_snapshot', pins['genSnapshotSHA256']),
                           (Path(os.environ['TANDEMLOG_TEXT_LIBRARY']), pins['nativeSHA256']),
                           (source / '.dart_tool/lib/libsqlite3.so', pins['sqliteSHA256'])):
        if digest(path) != expected:
            raise ValueError(f'Tool/library pin mismatch: {path.name}')


def validate_report(report, pins):
    flags = {'measurementCompleted': True, 'allPinsMatch': True,
             'measureOnly': True, 'releaseGateAccepted': False,
             'costDiagnosticsEnabled': False}
    if any(report.get(k) is not v for k, v in flags.items()) or report.get('rerunsUsed') != 0:
        raise ValueError('Missing complete uninstrumented diagnostic-only report')
    if report.get('resourceBounds') != pins['resourceBounds']:
        raise ValueError('Actual resource bounds differ from the hosted comparison')
    if report.get('sourceRewrites') != [] or report.get('shimAllowlist') != []:
        raise ValueError('Measured source has rewrites or shims')
    actual = report['sourcePins']
    if len(actual) != len(pins['sourceFiles']):
        raise ValueError('Source inventory differs')
    for relative, expected in pins['sourceFiles'].items():
        matches = [value for name, value in actual.items() if name.endswith('/' + relative)]
        if matches != [expected]:
            raise ValueError(f'Recorded source mismatch: {relative}')
    hashes = set(report['toolPins'].values())
    if not {pins[k] for k in ('dartSHA256', 'nativeSHA256', 'sqliteSHA256', 'limitsSHA256')} <= hashes:
        raise ValueError('Recorded tool/library/limit pins differ')
    if pins['genSnapshotSHA256'] not in set(report['compiledSourceAndDependencyPins'].values()):
        raise ValueError('Code generator pin differs')
    fixtures = {name: {k: v for k, v in item['contract'].items() if k != 'workspace'}
                for name, item in report['fixtures'].items()}
    if fixtures != pins['fixtures']:
        raise ValueError('Canonical fixture bytes or non-path contract differ')
    attempts = report['attempts']
    if len(attempts) != 3 or {a['size'] for a in attempts} != set(pins['fixtures']):
        raise ValueError('Missing complete three-shape attempt inventory')
    for attempt in attempts:
        if attempt['result']['correctnessPassed'] is not True or len(attempt['summaries']) != 232:
            raise ValueError('Missing correctness or registered metrics')
        if any(len(s['allSamplesMs']) != 5 or len(s['warmupSamplesMs']) != 2
               for s in attempt['summaries'].values()):
            raise ValueError('Measured/warmup samples differ')
    return {'comparisonDataComplete': True, 'releaseGateAccepted': False,
            'absoluteFailures': sum(len(a['failures']) for a in attempts),
            'pairedFailures': sum(len(p['failures']) for p in report['pairedScalingAttempts'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['preflight', 'report'])
    parser.add_argument('target', type=Path)
    parser.add_argument('pins', type=Path)
    args = parser.parse_args()
    pins = json.loads(args.pins.read_text())
    if args.mode == 'preflight':
        preflight(args.target.resolve(), pins)
        print('Exact source/tool preflight verified; no benchmark launched')
    else:
        print(json.dumps(validate_report(json.loads(args.target.read_text()), pins)))


if __name__ == '__main__':
    main()
