#!/usr/bin/env python3
"""Bounded public-synthetic fsync metadata diagnostic; never a timing gate."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / 'performance'))
import run_gate

TRACE_BYTES = 64 * 1024 * 1024
TRACE_FILES = 512
RUN_SECONDS = 1200
CALL = re.compile(
    r'^(\d+\.\d+)\s+(fsync|fdatasync)\((\d+)(?:<([^>]*)>)?\)'
    r'\s+=\s+(-?\d+).*?<(\d+\.\d+)>$')


def trace_inventory(root):
    files = list(root.iterdir())
    if len(files) > TRACE_FILES:
        raise RuntimeError('Diagnostic trace file-count bound exceeded')
    if any(p.is_symlink() or not p.is_file() for p in files):
        raise RuntimeError('Diagnostic traces must be regular owned files')
    if sum(p.stat().st_size for p in files) > TRACE_BYTES:
        raise RuntimeError('Diagnostic aggregate trace byte bound exceeded')
    return sorted(files)


def summarize(root):
    count = failed = incomplete = 0
    total_us = 0
    longest = []
    longest_workload = []
    classes = {}
    for path in trace_inventory(root):
        with path.open() as stream:
            for line in stream:
                match = CALL.match(line.rstrip())
                if not match:
                    if 'fsync(' in line or 'fdatasync(' in line or 'resumed>' in line:
                        incomplete += 1
                    continue
                start, operation, descriptor, target, result, seconds = match.groups()
                duration = round(float(seconds) * 1_000_000)
                target = target or ''
                name = target.removesuffix(' (deleted)')
                category = ('canonicalLog' if name.endswith(('.applog', '.operations'))
                            else 'sqlite' if re.search(r'\.sqlite(?:-wal|-journal)?$', name)
                            else 'otherFileOrDirectory')
                stage = ('workloadOrReplay' if re.search(r'/dense-(?:1|2|food)-attempt-\d+/', name)
                         else 'fixtureGeneration' if '/fixture-dense-' in name
                         else 'compileControllerOrOther')
                count += 1
                failed += int(result) < 0
                total_us += duration
                classes[category] = classes.get(category, 0) + 1
                longest.append({'traceFile': path.name, 'startEpochSeconds': start,
                                'operation': operation, 'descriptor': int(descriptor),
                                'path': target, 'class': category, 'stageHint': stage,
                                'result': int(result), 'elapsedUs': duration})
                if stage == 'workloadOrReplay':
                    longest_workload.append(longest[-1])
                    longest_workload.sort(key=lambda row: row['elapsedUs'], reverse=True)
                    del longest_workload[20:]
                longest.sort(key=lambda row: row['elapsedUs'], reverse=True)
                del longest[20:]
    return {'calls': count, 'failedCalls': failed,
            'unparsedSyscallLines': incomplete, 'classes': classes,
            'sumInclusiveElapsedUs': total_us, 'longest': longest,
            'longestWorkloadOrReplay': longest_workload,
            'captureIncludes': ['AOT compilation', 'fixture generation',
                                'workloads', 'replay and cleanup'],
            'qualification': 'Syscall wall includes scheduling and ptrace overhead; '
                             'calls may overlap. Not exclusive kernel service time. '
                             'No exact action-sample attribution is claimed.'}


def capture(command, log, traces, *, seconds=RUN_SECONDS):
    child = None
    reason = None
    started = time.monotonic()
    try:
        with log.open('xb') as stream:
            child = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                     start_new_session=True)
            while child.poll() is None:
                try:
                    trace_inventory(traces)
                    if time.monotonic() - started > seconds:
                        raise RuntimeError('Diagnostic process deadline exceeded')
                except RuntimeError as error:
                    reason = str(error)
                    break
                time.sleep(.25)
        if reason:
            run_gate.stop_owned_group(child)
        return {'exitCode': child.wait(), 'seconds': time.monotonic() - started,
                'childPID': child.pid, 'limitFailure': reason}
    finally:
        if child is not None:
            run_gate.stop_owned_group(child)
        # Nested benchmark sessions are additionally owned by the required
        # systemd control group; the shell verifies its stop/absence afterwards.


def validate_measurement(measurement):
    attempts = measurement.get('attempts', [])
    if not (measurement.get('measureOnly') is True
            and measurement.get('costDiagnosticsEnabled') is True
            and measurement.get('allPinsMatch') is True
            and measurement.get('measurementCompleted') is True
            and measurement.get('releaseGateAccepted') is False
            and measurement.get('rerunsUsed') == 0
            and len(attempts) == 3
            and {a.get('size') for a in attempts} == {'dense-1', 'dense-2', 'dense-food'}
            and all(a.get('result', {}).get('correctnessPassed') is True for a in attempts)):
        raise RuntimeError('Missing sealed all-shape diagnostic correctness')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('repo', 'dart', 'native-library', 'sqlite-library', 'output'):
        parser.add_argument('--' + option, required=True, type=Path)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(mode=0o700, exist_ok=False)
    report = {'diagnosticOnly': True, 'releaseGateAccepted': False,
              'sourceRewrites': [], 'syscallFilter': ['fsync', 'fdatasync'],
              'limits': {'seconds': RUN_SECONDS, 'traceBytes': TRACE_BYTES,
                         'traceFiles': TRACE_FILES}, 'diagnosticComplete': False}
    status = 1
    try:
        bounds = run_gate.actual_resource_bounds()
        report['resourceBounds'] = bounds
        run_gate.require_release_bounds(bounds)
        repo = args.repo.resolve()
        tools = repo / 'tool/performance'
        pins = run_gate.source_pins(repo, tools)
        report['sourcePins'] = pins
        report['diagnosticToolSHA256'] = run_gate.digest(__file__)
        report['straceSHA256'] = run_gate.digest('/usr/bin/strace')
        report['environment'] = run_gate.runtime_environment()
        traces = root / 'syscalls'
        traces.mkdir(mode=0o700)
        command = ['/usr/bin/strace', '-ff', '-ttt', '-T', '-yy',
                   '-e', 'trace=fsync,fdatasync', '-o', str(traces / 'fsync'),
                   sys.executable, str(tools / 'run_gate.py'),
                   '--repo', str(repo), '--dart', str(args.dart.resolve()),
                   '--native-library', str(args.native_library.resolve()),
                   '--sqlite-library', str(args.sqlite_library.resolve()),
                   '--output', str(root / 'measurement'),
                   '--measure-only', '--diagnose-costs']
        execution = capture(command, root / 'controller.log', traces)
        report['execution'] = execution
        report['syscalls'] = summarize(traces)
        if execution['exitCode'] or execution['limitFailure']:
            raise RuntimeError('Instrumented execution failed; original exit retained')
        if report['syscalls']['unparsedSyscallLines'] or not report['syscalls']['calls']:
            raise RuntimeError('Syscall capture is incomplete or empty')
        measurement = json.loads((root / 'measurement/gate-result.json').read_text())
        validate_measurement(measurement)
        if pins != run_gate.source_pins(repo, tools):
            raise RuntimeError('Diagnostic source changed')
        report['diagnosticComplete'] = True
        status = 0
    except BaseException as error:
        report['error'] = f'{type(error).__name__}: {error}'
    finally:
        run_gate.write_new(root / 'io-result.json', report)
    return status


if __name__ == '__main__':
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt('Diagnostic interrupted; owned service cleanup required')
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
