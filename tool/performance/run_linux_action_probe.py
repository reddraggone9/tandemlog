"""Bounded, synthetic-only release framework diagnostics on an owned X display.

Build integration_test/linux_release_action_costs.dart in a separate source tree
first. This runner never builds, installs, publishes or changes the input Desktop.
It requires that diagnostic entrypoint's compiled sentinel and closes only the
child it created. Results never establish a release/UI/presentation gate pass.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from measure_startup import finish_process

EXPECTED_ACTIONS = ['task-open', 'title-save', 'title-undo', 'task-complete',
                    'completion-undo', 'food-section', 'food-open', 'food-save', 'food-undo']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_source(source, pins):
    if not isinstance(pins, dict) or not pins or len(pins) > 10000:
        raise RuntimeError('Bounded source pin inventory required')
    for name, expected in pins.items():
        path = source/name
        if (path.is_symlink() or not path.is_file()
                or not path.resolve().is_relative_to(source.resolve())
                or sha(path) != expected):
            raise RuntimeError('QA source input changed: ' + name)


def action_proof(records):
    actions = [r for r in records if r.get('phase') == 'action']
    try:
        complete = bool(actions) and all(
            r['costs']['complete'] is True and r['costs']['reconciled'] is True
            and r['costs']['coverageSumUs'] == r['frameworkPostFrameUs']
            for r in actions)
    except (KeyError, TypeError):
        complete = False
    return actions, ([r.get('name') for r in actions] == EXPECTED_ACTIONS), complete


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--source-pins', required=True, type=Path)
    parser.add_argument('--shape', required=True, choices=['1320', '2640', 'food:2640'])
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--capture', action='store_true', help='Capture own X display outside action timers')
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux only; use an isolated owned X display')
    source = args.source.resolve(strict=True)
    bundle = source/'build/linux/x64/release/bundle'
    binary = bundle/'tandemlog'
    if not binary.is_file() or b'TANDEMLOG_COST_PROBE_DONE' not in (bundle/'lib/libapp.so').read_bytes():
        raise RuntimeError('Separate release diagnostic entrypoint required; ordinary app refused')
    pins = json.loads(args.source_pins.read_text())
    verify_source(source, pins)
    root = args.output.absolute()
    control = root.with_name(root.name+'-controller')
    if root.exists() or root.is_symlink() or control.exists() or control.is_symlink():
        raise RuntimeError('Fresh disposable application/controller outputs required')
    control.mkdir()
    (control/'controller-source.py').write_bytes(Path(__file__).read_bytes())
    (control/'source-pins.json').write_bytes(args.source_pins.read_bytes())
    payload = {str(p.relative_to(bundle)): sha(p) for p in bundle.rglob('*') if p.is_file()}
    env = dict(os.environ, TANDEMLOG_TEXT_LIBRARY=str(bundle/'lib/libtandemlog_text.so'),
               TANDEMLOG_COST_FIXTURE=args.shape, TANDEMLOG_COST_RUN_ROOT=str(root),
               TANDEMLOG_COST_CAPTURE='1' if args.capture else '0',
               TANDEMLOG_PROFILE=str(root/'unused-guard-profile'),
               LIBGL_ALWAYS_SOFTWARE='1', GSETTINGS_BACKEND='memory')
    status = {'shape': args.shape, 'controllerSHA256': sha(Path(__file__)),
              'sourcePinsSHA256': sha(args.source_pins), 'bundlePins': payload,
              'scope': 'Linux release framework/API diagnostics on cloud Xvfb; no OS input or hardware presentation acceptance',
              'sourceToBinaryBuildAttestation': False,
              'releaseGateAccepted': False, 'nativeVisibleResponseAccepted': False}
    child = None
    done = False
    error = None
    captured = set()
    records = []
    try:
        with (control/'stdout-stderr.log').open('wb') as out:
            child = subprocess.Popen([str(binary)], env=env, stdout=out, stderr=subprocess.STDOUT)
            start = time.monotonic()
            while time.monotonic()-start < 110:
                log = root/'actions.jsonl'
                if log.exists():
                    if log.stat().st_size > 8*1024*1024:
                        raise RuntimeError('Bounded diagnostic log exceeded')
                    records = []
                    for line in log.read_text().splitlines():
                        try:
                            records.append(json.loads(line))
                        except ValueError:
                            continue  # The child can be appending its last line.
                    for record in records:
                        if record.get('phase') == 'inspection-ready' and record['stage'] not in captured:
                            stage = record['stage']
                            if not args.capture or stage not in ('tasks', 'food'):
                                raise RuntimeError('Unknown capture stage')
                            subprocess.run(['import', '-window', 'root', str(control/(stage+'.png'))],
                                           check=True, timeout=10)
                            (root/(stage+'.arm')).write_text('owned-controller\n')
                            captured.add(stage)
                    finished = [r for r in records if r.get('phase') == 'suite-finished']
                    if finished:
                        done = finished[-1]['passed'] is True
                        if not done:
                            raise RuntimeError('Framework diagnostic suite failed')
                        break
                if child.poll() is not None:
                    raise RuntimeError('Probe exited before suite marker')
                time.sleep(.05)
            else:
                raise RuntimeError('Bounded action-probe deadline exceeded')
    except BaseException as exc:
        error = repr(exc)
    finally:
        if child is not None:
            status['shutdown'] = finish_process(child, done, 'normal', 'xdotool')
        try:
            verify_source(source, pins)
            if payload != {str(p.relative_to(bundle)): sha(p) for p in bundle.rglob('*') if p.is_file()}:
                raise RuntimeError('QA bundle changed during probe')
        except BaseException as exc:
            error = error or repr(exc)
        actions, sequence, complete = action_proof(records)
        verified = [r for r in records if r.get('phase') == 'verified']
        status.update(error=error, actions=actions, captured=sorted(captured),
                      functionalPass=error is None and done and bool(verified) and sequence
                      and status.get('shutdown', {}).get('normalExitVerified') is True,
                      allPartitionsComplete=complete,
                      frameworkBoundary100msMisses=[r['name'] for r in actions
                                                   if r.get('objectiveExceededAtThisFrameworkBoundary') is True])
        (control/'result.json').write_text(json.dumps(status, indent=2)+'\n')
        print(json.dumps({k: v for k, v in status.items() if k not in ('actions', 'bundlePins')}, indent=2))
    return 0 if status['functionalPass'] and status['allPartitionsComplete'] else 1


if __name__ == '__main__':
    sys.exit(main())
