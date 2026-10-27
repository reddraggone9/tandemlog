"""Diagnostic-only public synthetic normal-close reproduction under GDB.

No timing acceptance, fixture import or force-close substitution. Run on an
owned X display after the ordinary release bundle has been built. Every outcome
is retained; stop at the first crash/error, with at most three fresh processes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from measure_startup import request_owned_window_close, seed_fixture


def inferior_pid(text):
    values = re.findall(r'^TANDEMLOG_GDB_PID=(\d+)$', text, re.MULTILINE)
    if len(values) != 1 or int(values[0]) <= 1:
        raise RuntimeError('Exactly one GDB-owned inferior PID required')
    return int(values[0])


def outcome(text):
    if re.search(r'received signal SIG(SEGV|ABRT|BUS|ILL|FPE)', text):
        return 'native-crash'
    if re.search(r'\[Inferior \d+ .* exited normally\]', text):
        return 'normal-exit'
    return 'unverified'


def process_identity(pid):
    try:
        status = Path(f'/proc/{pid}/status').read_text()
        values = dict(line.split(':', 1) for line in status.splitlines() if ':' in line)
        if any(int(v) != os.getuid() for v in values['Uid'].split()):
            raise RuntimeError('Owned debugger process UID changed')
        # starttime prevents signaling a reused PID after the debugger exits.
        start = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]
        return start, values['State'].strip().startswith('Z'), int(values['PPid'])
    except FileNotFoundError:
        return None


def stop_owned(debugger, pid, start):
    def live():
        identity = process_identity(pid) if pid is not None else None
        return identity is not None and identity[0] == start and not identity[1]
    forced = False
    if live():
        forced = True
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if debugger.poll() is None:
        debugger.terminate()
        try:
            debugger.wait(timeout=5)
        except subprocess.TimeoutExpired:
            debugger.kill()
            debugger.wait(timeout=5)
    if live():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        deadline = time.monotonic()+5
        while live() and time.monotonic() < deadline:
            time.sleep(.05)
    return {'forcedCleanupUsed': forced,
            'debuggerStopped': debugger.poll() is not None,
            'inferiorOwnershipProven': pid is not None and start is not None,
            'inferiorStopped': not live() if pid is not None and start is not None else None}


def reproduce(repo, root, gdb, data_directory):
    binary = repo/'build/linux/x64/release/bundle/tandemlog'
    library = binary.parent/'lib/libtandemlog_text.so'
    folder, profile, receipt = seed_fixture(root/'fixture', 10, str(library))
    (root/'fixture-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    command = [str(gdb), '--nx', '--batch']
    if data_directory:
        command.append('--data-directory='+str(data_directory))
    for instruction in ['set pagination off', 'set debuginfod enabled off',
                        'set startup-with-shell off',
                        'handle SIGPIPE nostop noprint pass',
                        'handle SIGUSR1 nostop noprint pass',
                        'handle SIGUSR2 nostop noprint pass', 'starti',
                        'python print("TANDEMLOG_GDB_PID="+str(gdb.selected_inferior().pid))',
                        'continue', 'info program', 'thread apply all bt',
                        'info sharedlibrary']:
        command.extend(['-ex', instruction])
    command.extend(['--args', str(binary)])
    log = root/'gdb.log'
    result = {'diagnosticOnly': True, 'acceptance': False, 'command': command}
    pid, start = None, None
    with log.open('w') as output:
        debugger = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT,
                                    start_new_session=True,
                                    env=dict(os.environ, TANDEMLOG_PROFILE=str(profile),
                                             GSETTINGS_BACKEND='memory'))
        try:
            deadline = time.monotonic()+45
            while time.monotonic() < deadline:
                if log.stat().st_size > 8*1024*1024:
                    raise RuntimeError('Bounded debugger log exceeded')
                text = log.read_text(errors='replace')
                if pid is None and 'TANDEMLOG_GDB_PID=' in text:
                    pid = inferior_pid(text)
                    identity = process_identity(pid)
                    if identity is None or identity[2] != debugger.pid:
                        raise RuntimeError('Inferior is not a live child of the owned debugger')
                    start = identity[0]
                    result['inferiorPID'] = pid
                if 'TANDEMLOG_READY_MS=' in text:
                    break
                if debugger.poll() is not None:
                    raise RuntimeError('Debugger exited before application readiness')
                time.sleep(.05)
            else:
                raise RuntimeError('Bounded debugger startup deadline exceeded')
            if pid is None:
                raise RuntimeError('Missing inferior ownership proof')

            class OwnedInferior:
                def __init__(self):
                    self.pid = pid
                def poll(self):
                    identity = process_identity(pid)
                    return None if identity and identity[0] == start and not identity[1] else 0

            result['close'] = request_owned_window_close(OwnedInferior(), 'xdotool')
            debugger.wait(timeout=25)
            result['outcome'] = outcome(log.read_text(errors='replace'))
            result['debuggerExit'] = debugger.returncode
        except Exception as error:
            result['error'] = repr(error)
            result['outcome'] = outcome(log.read_text(errors='replace'))
        finally:
            result['cleanup'] = stop_owned(debugger, pid, start)
    result['normalCloseObserved'] = (result.get('outcome') == 'normal-exit'
                                    and 'close' in result and 'error' not in result
                                    and not result['cleanup']['forcedCleanupUsed'])
    (root/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--attempts', type=int, choices=[1, 2, 3], default=3)
    parser.add_argument('--gdb', type=Path, default=Path('/usr/bin/gdb'))
    parser.add_argument('--gdb-data-directory', type=Path)
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux only; requires an isolated owned X display')
    root = args.output.absolute()
    root.mkdir(parents=False, exist_ok=False)
    repo = Path(__file__).resolve().parents[1]
    bundle = repo/'build/linux/x64/release/bundle'
    pins = {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in bundle.rglob('*') if p.is_file()}
    if not pins or not (bundle/'tandemlog').is_file():
        raise RuntimeError('Built ordinary release bundle required')
    report = {'diagnosticOnly': True, 'acceptance': False,
              'sourceRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'],
                                                       cwd=repo, text=True).strip(),
              'bundlePins': pins, 'maximumFreshProcesses': args.attempts,
              'performanceGateRerun': False, 'results': []}
    try:
        for number in range(1, args.attempts+1):
            run = root/('process-'+str(number))
            run.mkdir()
            result = reproduce(repo, run, args.gdb, args.gdb_data_directory)
            report['results'].append(result)
            if not result['normalCloseObserved']:
                break
        current = {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in bundle.rglob('*') if p.is_file()}
        report['bundleUnchanged'] = pins == current
        report['diagnosticCompleted'] = (pins == current and bool(report['results'])
                                         and all(r['normalCloseObserved'] for r in report['results']))
    except Exception as error:
        report['error'] = repr(error)
    finally:
        (root/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'bundlePins'}, indent=2))
    return 0 if report.get('diagnosticCompleted') else 1


if __name__ == '__main__':
    sys.exit(main())
