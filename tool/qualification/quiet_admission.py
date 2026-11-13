#!/usr/bin/python3 -IB
"""Host-quiet admission for a reference qualification (private; not the gate or controller).

Usage: quiet-admission.py OUTPUT.json [--check-once]

Exits 0 and writes OUTPUT.json only after 120 s of continuous quiet. Quiet means: no heavy
build/test/emulator/benchmark process, no active tandemlog/diag/lab unit, CPU PSI "some" avg10
about 0, and 1-minute load < 1. Those two thresholds match all 17 admissions before d8874dea
(PSI 0.00, load <= 0.88); that run's admission passed at PSI 1.46, load 2.49 under the old
load < 3 rule, and the host contention then contaminated it. See FAILURE-DIAGNOSIS.md.
Unreadable or malformed PSI is not quiet. Never lower these checks to get a run admitted.
"""
import datetime
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

PATTERN = ('offline_convert|dartvm|dartaotruntime|flutter_tool|flutter_tester|gen_snapshot|qemu-system|emulator|'
           'Xvfb|gradle|fio|ioping|stress-ng|bonnie|sysbench|cargo|rustc|cc1plus|ninja|tandemlog-cutover-20261027|run_gate.py|benchmark')
# Active transcodes by process name only (idle Jellyfin/Emby daemons merely name ffmpeg in argv).
NAME_PATTERN = 'ffmpeg|ffmpeg-emby|ffprobe|HandBrakeCLI|x265|x264'
UNIT_GLOBS = ['tandemlog-*', 'vex-rc-diag-*', 'vex-*lab*', 'vex-jellyfin-attempt-*', 'vex-jellyfin-clone*']
GRACE = 120
LIMIT = int(os.environ.get('ADMISSION_SECONDS', '3600'))
MAX_CPU_PSI_AVG10 = 0.10  # Reads 0.00 when idle; 0.10 tolerates only rounding-level blips.
MAX_LOAD_1M = 1.0
me = os.getpid()


def procs():
    p = subprocess.run(['pgrep', '-af', PATTERN], capture_output=True, text=True)
    out = []
    for line in p.stdout.splitlines():
        pid = int(line.split(None, 1)[0])
        if pid == me or 'pgrep -af' in line or 'quiet-admission' in line:
            continue
        out.append(line[:240])
    n = subprocess.run(['pgrep', '-l', NAME_PATTERN], capture_output=True, text=True)
    out += ['name:' + line for line in n.stdout.splitlines()]
    return out


def active_units():
    found = []
    for scope in (['systemctl'], ['systemctl', '--user']):
        r = subprocess.run(scope + ['list-units', '--all', '--plain', '--no-legend', '--no-pager', *UNIT_GLOBS],
                           capture_output=True, text=True)
        for line in r.stdout.splitlines():
            f = line.split()
            if len(f) >= 3 and f[2] not in ('inactive', 'failed'):
                found.append(' '.join(scope[1:] + f[:4]))
    return found


def psi():
    return {k: Path(f'/proc/pressure/{k}').read_text().splitlines()[0] for k in ('cpu', 'io')}


def cpu_psi_avg10(line):
    """Return avg10 from a PSI "some" line, or None if the line isn't one."""
    m = re.fullmatch(r'some avg10=(\d+\.\d+) avg60=\d+\.\d+ avg300=\d+\.\d+ total=\d+', line.strip())
    return float(m.group(1)) if m else None


def refusals(state):
    """Why this sample is not quiet; empty means quiet."""
    why = []
    if state['activeUnits']:
        why.append('active units')
    if state['processes']:
        why.append('heavy processes')
    if state['load'][0] >= MAX_LOAD_1M:
        why.append(f"load {state['load'][0]:.2f} >= {MAX_LOAD_1M}")
    avg10 = cpu_psi_avg10(state['psi']['cpu']) if state['psi'] else None
    if avg10 is None:
        why.append('CPU PSI unavailable')
    elif avg10 >= MAX_CPU_PSI_AVG10:
        why.append(f'CPU PSI avg10 {avg10:.2f} >= {MAX_CPU_PSI_AVG10}')
    return why


def sample(start):
    try:
        pressure = psi()
    except (OSError, IndexError):
        pressure = None
    state = {'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'elapsed_s': round(time.monotonic() - start),
             'activeUnits': active_units(), 'processes': procs(), 'load': os.getloadavg(), 'psi': pressure}
    state['userSliceCpuStat'] = Path('/sys/fs/cgroup/user.slice/cpu.stat').read_text()
    state['systemSliceCpuStat'] = Path('/sys/fs/cgroup/system.slice/cpu.stat').read_text()
    state['refusals'] = refusals(state)
    return state


def main(argv):
    output = Path(argv[1])
    start = time.monotonic()
    if '--check-once' in argv[2:]:
        state = sample(start)
        print(json.dumps(state))
        return 0 if not state['refusals'] else 3
    if output.exists():
        print(f'Refusing to overwrite {output}', file=sys.stderr)
        return 2
    quiet = None
    last = None
    while time.monotonic() - start < LIMIT:
        state = sample(start)
        sig = (tuple(state['activeUnits']), tuple(state['processes']), tuple(w.split(' ')[0] for w in state['refusals']))
        if sig != last:
            print(json.dumps(state), flush=True)
            last = sig
        if not state['refusals']:
            if quiet is None:
                quiet = time.monotonic()
                qstart = state['at']
                print('Quiet detected; 120-second continuous grace', flush=True)
            if time.monotonic() - quiet >= GRACE:
                state.update(result='QUIET_AFTER_GRACE', quietSinceUTC=qstart, graceSeconds=GRACE,
                             maxCpuPsiAvg10=MAX_CPU_PSI_AVG10, maxLoad1m=MAX_LOAD_1M)
                with output.open('x') as f:
                    f.write(json.dumps(state, indent=2) + '\n')
                print('QUIET_AFTER_GRACE', flush=True)
                return 0
        else:
            if quiet is not None:
                print('Quiet broken; grace reset ' + json.dumps(state), flush=True)
            quiet = None
        time.sleep(10)
    print('TIMEOUT_NOT_QUIET', flush=True)
    return 3


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
