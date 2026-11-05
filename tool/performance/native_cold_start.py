"""Native cold start to first list: the `native.coldStart.firstList` gate case.

`measure` runs the Linux release bundle under the caller's X display on a fresh
synthetic workspace: one strict first launch (reported, not budgeted), then warm
repeat starts, each after a verified normal close that sealed the warm proofs.
A sample is `process_ms` from the app's own `TANDEMLOG_FIRST_LIST` line: process
start to the first frame that shows the task list. The result binds the relevant
source identity, so a source change needs a fresh measurement.

`verify` is the required check: the committed result must match the current
relevant source, its median is recomputed from the samples, and that median must
be within the committed budget. Missing, stale or over budget fails.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import sys

TOOL = Path(__file__).resolve().parent
sys.path[:0] = [str(TOOL), str(TOOL.parent)]

from reference_receipt import recorded_identity, source_identity  # noqa: E402

BUDGET = 'tool/performance/native-cold-start-v1.json'
RESULT = 'evidence/native-cold-start/current/result.json'
CASE = 'native.coldStart.firstList'
FIRST_LIST = re.compile(r'^TANDEMLOG_FIRST_LIST at=\S+ ms=(\d+) process_ms=(\d+) ', re.M)


class GateError(Exception):
    pass


def need(condition, message):
    if not condition:
        raise GateError(message)


def read_budget(repo):
    budget = json.loads((Path(repo) / BUDGET).read_text())
    need(budget.get('case') == CASE and type(budget.get('medianMs')) is int and budget['medianMs'] > 0,
         'Native cold-start budget file is malformed')
    shape = budget.get('shape', {})
    need(type(shape.get('tasks')) is int and type(shape.get('warmStarts')) is int and shape['warmStarts'] >= 3,
         'Native cold-start shape is malformed')
    return budget


def first_list(log_text):
    """(ms since app state start, ms since process start) from one run's output."""
    found = FIRST_LIST.findall(log_text)
    need(len(found) == 1, 'Run output needs exactly one TANDEMLOG_FIRST_LIST line')
    return int(found[0][0]), int(found[0][1])


def judge(budget, result):
    """Recompute the decision from the retained samples; never trust `passed`."""
    need(result.get('case') == CASE, 'Result is for another case')
    need(result.get('budgetMs') == budget['medianMs'] and result.get('shape') == budget['shape'],
         'Result was measured under another budget or shape')
    warm = result.get('warmStarts')
    need(isinstance(warm, list) and len(warm) == budget['shape']['warmStarts'], 'Warm start count differs')
    for run in warm:
        need(type(run.get('processMs')) is int and run['processMs'] > 0, 'Warm sample is missing')
        need(run.get('cleanWitnessVerified') is True, 'A warm start did not reuse the sealed warm proofs')
    median = statistics.median(run['processMs'] for run in warm)
    return {'case': CASE, 'medianMs': median, 'budgetMs': budget['medianMs'],
            'passed': median <= budget['medianMs'],
            'samplesMs': [run['processMs'] for run in warm],
            'strictFirstLaunchMs': result.get('strictFirstLaunch', {}).get('processMs')}


def verify(repo, path=None):
    repo = Path(repo)
    file = Path(path) if path else repo / RESULT
    need(file.is_file(), f'No native cold-start result at {RESULT}; measure this source on the reference host')
    result = json.loads(file.read_text())
    need(isinstance(result.get('relevantSource'), dict) and isinstance(result.get('sourceRevision'), str),
         'Native cold-start result has no source binding')
    current, committed = recorded_identity(repo, result.get('relevantSource'), result.get('sourceRevision'))
    need(result.get('relevantSource') == current == committed,
         'Native cold-start result is for other source; measure this source')
    decision = judge(read_budget(repo), result)
    need(decision['passed'], f"{CASE}: median {decision['medianMs']} ms over the {decision['budgetMs']} ms budget "
                             f"(samples {decision['samplesMs']})")
    return decision


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def measure(repo, binary, workspace, output, xdotool):
    import subprocess
    from measure_startup import inspect_stopped_witness, launch, seed_fixture, verify_loaded
    repo, root = Path(repo).resolve(), Path(workspace).resolve()
    budget = read_budget(repo)
    tasks, warm_starts = budget['shape']['tasks'], budget['shape']['warmStarts']
    diagnostics = root / 'diagnostics'
    diagnostics.mkdir(parents=True, exist_ok=True)
    library = str(Path(binary).resolve().parent / 'lib/libtandemlog_text.so')
    folder, profile, receipt = seed_fixture(root, tasks, library)
    runs, previous = [], None
    for i in range(warm_starts + 1):
        before = inspect_stopped_witness(profile, folder)
        status = launch(binary, profile, diagnostics, i + 1, xdotool=xdotool)
        status['witnessBeforeLaunch'] = before
        status['previousNormalExitVerified'] = bool(previous and previous['shutdown']['normalExitVerified'])
        verify_loaded(profile, folder, tasks, status, i > 0)
        log = (diagnostics / f'run-{i + 1}.stdout-stderr.log').read_text(errors='replace')
        app_ms, process_ms = first_list(log)
        runs.append({'run': i + 1, 'processMs': process_ms, 'appMs': app_ms,
                     'externalMs': status.get('external_ms'),
                     'cleanWitnessVerified': status.get('cleanWitnessVerified', False)})
        previous = status
    result = {'schemaVersion': 1, 'case': CASE, 'budgetMs': budget['medianMs'], 'shape': budget['shape'],
              'sourceRevision': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
              'relevantSource': source_identity(repo), 'binarySHA256': digest(binary),
              'platform': budget['platform'], 'fixture': receipt,
              'strictFirstLaunch': runs[0], 'warmStarts': runs[1:]}
    result['decision'] = judge(budget, result)
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    Path(output).write_text(json.dumps(result, indent=2) + '\n')
    return result['decision']


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('mode', choices=('measure', 'verify'))
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--binary', type=Path, help='measure: the release bundle executable')
    parser.add_argument('--workspace', type=Path, help='measure: fresh disposable directory; never a real profile')
    parser.add_argument('--output', type=Path, help='measure: result file to write')
    parser.add_argument('--result', type=Path, help='verify: result file (default: the committed evidence)')
    parser.add_argument('--xdotool', default='xdotool')
    args = parser.parse_args()
    try:
        if args.mode == 'measure':
            need(args.binary and args.workspace and args.output, 'measure needs --binary, --workspace and --output')
            need(not args.workspace.exists(), 'measure needs a fresh workspace')
            decision = measure(args.repo, args.binary, args.workspace, args.output, args.xdotool)
        else:
            decision = verify(args.repo, args.result)
    except (GateError, ValueError) as error:
        print(f'::error title=Native cold start::{error}', file=sys.stderr)
        sys.exit(1)
    print(json.dumps(decision, indent=2))
    if not decision['passed']:
        sys.exit(1)


if __name__ == '__main__':
    main()
