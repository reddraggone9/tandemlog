#!/usr/bin/python3
"""SOURCE-ONLY PREPARATION. Default plan is read-only; launch is one-shot.

Requires existing sudo management access, python3 -I -B, immutable lab source,
reviewed fresh request and fresh external output. Does not prepare source/request,
seal evidence, retry, alter controller, or install services. Reads and saves terminal
owned-unit results before resetting its own failed units.
Output is the CONTROLLER invocation directory; harness output is OUTPUT/run.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
# -I intentionally omits the script directory. Only load this checked-in helper.
__import__("sys").path.insert(0, str(Path(__file__).resolve().parent))
from unit_cleanup import reset_owned
import select
import signal
import subprocess
import sys
import time

CONTROLLER = None
CONTROLLER_HASH = 'f5e6262ee5c4665e1a5cf3b30728165f21651471b33eea79150c8090d78a8645'
PRESSURE_HASH = 'f67076216c21ae898dd0728132bbbfe388af307b8734c056f0ab5d05b7797e10'
CLEAN = {'HOME': '/root', 'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'PYTHONDONTWRITEBYTECODE': '1'}
PATH_KEYS = ('repo', 'request', 'output', 'dart', 'native_library', 'sqlite_library')
CAP = 64*1024**2
CGROUP_ROOT = Path('/sys/fs/cgroup/system.slice')


def start_ticks(c, pid):
    # A process exiting between open and read raises ESRCH; that is absence, like ENOENT.
    try:
        return c.proc_start(pid)
    except ProcessLookupError:
        return None


def cgroup_members(base):
    # Monitoring tolerates members and child groups that vanish mid-walk; a
    # surviving group whose procs cannot be read still fails.
    members = []
    if base.exists():
        for p in base.rglob('cgroup.procs'):
            try:
                members += p.read_text().split()
            except (FileNotFoundError, ProcessLookupError, OSError) as exc:
                if p.parent.exists() and not isinstance(exc, (FileNotFoundError, ProcessLookupError)):
                    raise
    return members


def need(ok, why):
    if not ok:
        raise RuntimeError(why)


def load_controller():
    import hashlib
    need(os.geteuid() == 0 and sys.flags.isolated and sys.dont_write_bytecode,
         'Use sudo -n env -i ... /usr/bin/python3 -I -B')
    for p, digest in ((CONTROLLER, CONTROLLER_HASH),
                      (CONTROLLER.with_name('memory_pressure_policy_v2.py'), PRESSURE_HASH)):
        need(all(not q.is_symlink() for q in (p, *p.parents)), 'Linked controller input')
        need(hashlib.sha256(p.read_bytes()).hexdigest() == digest, 'Reviewed controller/pressure bytes changed')
    spec = importlib.util.spec_from_file_location('reviewed_r7', CONTROLLER)
    c = importlib.util.module_from_spec(spec)
    # Verified bytes; no import cache or product source executed as root.
    exec(compile(CONTROLLER.read_bytes(), str(CONTROLLER), 'exec'), c.__dict__)
    c.manager_identity()
    return c


def argv_for(args, mode):
    argv = ['/usr/bin/python3', '-I', '-B', str(CONTROLLER), mode]
    for key in PATH_KEYS:
        argv += ['--'+key.replace('_', '-'), str(getattr(args, key))]
    return argv


def manager_command(args, manager):
    return ['/usr/bin/systemd-run', '--unit='+manager, '--wait', '--pipe',
            '--service-type=exec', '--uid=0', '--gid=0',
            '--property=MemoryMax=128M', '--property=MemorySwapMax=0',
            '--property=CPUQuota=100%', '--property=TasksMax=32',
            '--property=RuntimeMaxSec=1500', '--property=TimeoutStopSec=1',
            '--property=KillMode=control-group', '--property=OOMPolicy=kill',
            '--property=StartLimitIntervalSec=infinity', '--property=StartLimitBurst=1',
            '--property=Restart=no', '/usr/bin/env', '-i',
            *[k+'='+v for k, v in CLEAN.items()], *argv_for(args, 'run')]


def prepare(c, args):
    repo, request, value, host, paths = c.request_inputs(args)
    output = c.lab_path(args.output, False)
    evidence = c.lab_path(str(output)+'.executor', False)
    marker = c.lab_path(str(request)+'.executor-claimed.json', False)
    need(output.parent.is_dir() and output.parent.stat().st_uid == 1002, 'Output parent must belong to existing lab UID1002')
    for p in (output, evidence, marker, request.with_name(request.name+'.claimed.json')):
        need(not p.exists() and not p.is_symlink(), 'Never reuse output/evidence/claimed request: '+str(p))
        need(not p.is_relative_to(repo), 'All controls/evidence must be outside immutable source')
    manager, workload = c.names(value['requestId'])
    units = {u: c.unit_fields(u, timeout=2) for u in (manager, workload)}
    need(all(v['LoadState'] == 'not-found' and c.inactive(v) for v in units.values()),
         'Fresh exact nonce units required; never reset/restart existing units')
    # Read-only preflight fingerprints the existing parent. R7 creates its
    # fresh output, then independently fingerprints that actual mount identity.
    context = c.context(repo, request, output.parent, paths)
    c.verify_arc_accounting()
    need(not c.busy_processes(), 'Competing build/test/app/emulator load; coordinate, never kill it')
    plan = {'requestId': value['requestId'], 'sourceRevision': value['sourceRevision'],
            'controllerSHA256': c.digest(CONTROLLER), 'pressureSHA256': PRESSURE_HASH,
            'requestSHA256': c.digest(request), 'hostProfileSHA256': value['hostProfileSHA256'],
            'context': context, 'output': str(output), 'harnessOutput': str(output/'run'),
            'executorEvidence': str(evidence), 'oneShotMarker': str(marker),
            'managerUnit': manager, 'workloadUnit': workload, 'initialUnits': units,
            'managerCommand': manager_command(args, manager),
            'finalizeCommand': argv_for(args, 'finalize'),
            'heartbeatIntervalSeconds': 10, 'executionSeconds': 1500, 'sharedCleanupSeconds': 20,
            'deadlineSource': 'PID1 ActiveEnterTimestampMonotonic; never launcher startup',
            'noExternalRetry': True, 'sealsAutomatically': False,
            'launcherSHA256': c.digest(Path(__file__))}
    return value, output, evidence, marker, plan


class Executor:
    def __init__(self, c, args, prepared):
        self.c, self.args = c, args
        self.value, self.output, self.evidence, self.marker, self.plan = prepared
        self.units = (self.plan['managerUnit'], self.plan['workloadUnit'])
        self.errors, self.processes, self.samples = [], {}, 0
        self.last_fields = {}
        self.activation, self.cancelled, self.client = None, None, None
        self.original_client_exit, self.finalize_exit = None, None
        self.attempt = None

    def record(self, name, value):
        self.c.write(self.evidence/name, {'atUTC': self.c.utc().isoformat(), **value})

    def on_signal(self, sig, _frame):
        self.cancelled = 'Executor cancellation signal '+str(sig)

    def snapshot(self, role, timeout=2):
        # Original terminal fields precede potentially vanished cgroup reads.
        self.samples += 1
        need(self.samples <= 2048, 'Independent snapshot cap')
        fields, errors, groups = {}, [], {}
        for unit in self.units:
            try:
                fields[unit] = self.c.unit_fields(unit, timeout=timeout)
            except BaseException as exc:
                errors.append(unit+' STATUS '+repr(exc))
        self.last_fields = dict(fields)
        self.record('status-'+str(self.samples).zfill(4)+'.json',
                    {'role': role, 'monotonic': time.monotonic(), 'units': fields, 'errors': errors})
        for unit in self.units:
            try:
                base = CGROUP_ROOT/unit
                members = cgroup_members(base)
                for pid in members:
                    tick = start_ticks(self.c, int(pid))
                    if tick is not None:
                        self.processes[pid] = tick
                groups[unit] = {'exists': base.exists(), 'members': members}
            except BaseException as exc:
                errors.append(unit+' CGROUP '+repr(exc))
        self.record('groups-'+str(self.samples).zfill(4)+'.json',
                    {'role': role, 'monotonic': time.monotonic(), 'groups': groups, 'errors': errors})
        need(not errors, 'Independent readback failed: '+repr(errors))
        return fields, groups

    def witness_manager(self, before):
        unit = self.units[0]
        f = before[unit]
        if not (f.get('ActiveState') == 'active' and f.get('SubState') == 'running'
                and f.get('MainPID', '').isdigit() and int(f['MainPID']) > 0
                and f.get('ActiveEnterTimestampMonotonic', '').isdigit()
                and int(f['ActiveEnterTimestampMonotonic']) > 0):
            return False
        pid = int(f['MainPID'])
        tick = start_ticks(self.c, pid)
        sample = {'before': f, 'pid': pid, 'startTicksBefore': tick}
        try:
            sample['argv'] = Path('/proc', str(pid), 'cmdline').read_bytes().rstrip(b'\0').decode().split('\0')
            sample['cgroup'] = Path('/proc', str(pid), 'cgroup').read_text().strip()
            sample['exe'] = os.readlink('/proc/'+str(pid)+'/exe')
            after = self.c.unit_fields(unit, timeout=2)
            sample['after'] = after
            sample['startTicksAfter'] = start_ticks(self.c, pid)
            sample['bounds'] = self.c.bounds_at(Path('/sys/fs/cgroup/system.slice')/unit)
        finally:
            self.record('manager-startup-witness.json', sample)
        need(tick is not None and sample['startTicksAfter'] == tick and
             f['MainPID'] == after['MainPID'] and after['ActiveState'] == 'active' and
             after['SubState'] == 'running' and
             f['ActiveEnterTimestampMonotonic'] == after['ActiveEnterTimestampMonotonic'],
             'Manager exited/changed during witness; no inferred normal exit')
        need(sample['argv'] == argv_for(self.args, 'run') and
             sample['exe'] == str(Path('/usr/bin/python3').resolve()) and
             sample['cgroup'] == '0::/system.slice/'+unit and
             f['ControlGroup'] == after['ControlGroup'] == '/system.slice/'+unit,
             'Exact manager argv/executable/cgroup differs')
        need(sample['bounds'] == self.c.MANAGER_BOUNDS, 'Actual manager caps differ')
        need(all(after.get(k) == v for k, v in {
            'RuntimeMaxUSec': '25min', 'TimeoutStopUSec': '1s', 'StartLimitBurst': '1',
            'StartLimitIntervalUSec': 'infinity', 'Restart': 'no',
            'KillMode': 'control-group', 'OOMPolicy': 'kill'}.items()), 'Manager lifecycle differs')
        self.activation = int(f['ActiveEnterTimestampMonotonic'])/1e6
        need(self.attempt <= self.activation <= time.monotonic(), 'Missing/future/reused PID1 activation')
        self.processes[str(pid)] = tick
        self.record('original-activation.json', {'activationMonotonic': self.activation,
                    'workloadDeadlineMonotonic': self.activation+1500,
                    'cleanupDeadlineMonotonic': self.activation+1520})
        return True

    def heartbeat(self):
        need(self.client is not None, 'Missing manager client')
        if self.client.poll() is not None:
            return False
        ready = select.select([], [self.client.stdin], [], 0)[1]
        need(bool(ready), 'Heartbeat pipe blocked; do not accumulate queued heartbeats')
        try:
            need(os.write(self.client.stdin.fileno(), b'heartbeat\n') == 10, 'Incomplete heartbeat')
        except BrokenPipeError:
            # Normal manager exit can race the next heartbeat. Its ORIGINAL
            # client exit, not a guessed success, is still required below.
            return False
        return True

    def run_manager(self):
        with (self.evidence/'manager-client.log').open('xb') as log:
            os.fchown(log.fileno(), 1002, 1002)
            need(self.cancelled is None, self.cancelled)
            self.attempt = time.monotonic()
            self.client = subprocess.Popen(self.plan['managerCommand'], stdin=subprocess.PIPE,
                         stdout=log, stderr=subprocess.STDOUT, env=CLEAN, start_new_session=True)
            os.set_blocking(self.client.stdin.fileno(), False)
            self.record('client-launched.json', {'pid': self.client.pid,
                        'startTicks': start_ticks(self.c, self.client.pid), 'launchAttemptMonotonic': self.attempt})
            next_heartbeat, next_snapshot = self.attempt, self.attempt
            while self.client.poll() is None:
                now = time.monotonic()
                need(self.cancelled is None, self.cancelled)
                if self.activation is None:
                    need(now < self.attempt+10, 'Manager admission deadline; never relaunch uncertain work')
                else:
                    need(now < self.activation+1500, 'Original PID1 25-minute execution bound')
                need(os.fstat(log.fileno()).st_size <= CAP, 'Manager client log cap')
                if now >= next_heartbeat:
                    if not self.heartbeat():
                        break
                    next_heartbeat = time.monotonic()+10
                if now >= next_snapshot:
                    fields, _ = self.snapshot('running')
                    if self.activation is None:
                        self.witness_manager(fields)
                    next_snapshot = time.monotonic()+(10 if self.activation is not None else .2)
                time.sleep(.1)
            self.original_client_exit = self.client.wait(timeout=2)
            self.record('original-client-exit.json', {'exit': self.original_client_exit,
                        'monotonic': time.monotonic(), 'originalActivation': self.activation})
            need(self.activation is not None, 'Client exited without verified live manager admission')
            need(self.original_client_exit == 0, 'Original manager client failed; preserve evidence')

    def close_heartbeat(self):
        if self.client and self.client.stdin and not self.client.stdin.closed:
            self.client.stdin.close()

    def cleanup(self):
        # One shared reverse-order stop transaction, NEVER another 20s per unit.
        # Read/write failures must not bypass the exact-unit stop attempt.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)
        try:
            self.close_heartbeat()
        except BaseException as exc:
            self.errors.append('HEARTBEAT CLOSE '+repr(exc))
        start = time.monotonic()
        original_end = self.activation+1520 if self.activation is not None else (self.attempt or start)+1520
        stop_end = min(original_end, start+20)
        try:
            self.record('cleanup-window.json', {'stopStartedMonotonic': start,
                        'sharedStopDeadlineMonotonic': stop_end,
                        'originalActivation': self.activation,
                        'unknownActivationFailsQualification': self.activation is None})
        except BaseException as exc:
            self.errors.append('CLEANUP RECORD '+repr(exc))
        # Reap the original launch client BEFORE declaring absent units settled.
        # A StartTransientUnit already sent to PID1 may be accepted after a
        # cancellation/readback. Unknown admission therefore reconciles the exact
        # nonce units through the shared cleanup window, not just its first read.
        unresolved_admission = self.activation is None
        if self.client is not None and self.client.poll() is None:
            self.errors.append('CLIENT cancelled during unresolved/failed invocation')
            try:
                os.killpg(self.client.pid, signal.SIGTERM)
            except BaseException as exc:
                self.errors.append('CLIENT TERM '+repr(exc))
            try:
                self.original_client_exit = self.client.wait(timeout=min(1, max(.05, stop_end-time.monotonic())))
            except BaseException as exc:
                self.errors.append('CLIENT TERM REAP '+repr(exc))
            if self.client.poll() is None:
                try:
                    os.killpg(self.client.pid, signal.SIGKILL)
                except BaseException as exc:
                    self.errors.append('CLIENT KILL '+repr(exc))
                try:
                    self.original_client_exit = self.client.wait(timeout=min(1, max(.05, stop_end-time.monotonic())))
                except BaseException as exc:
                    self.errors.append('CLIENT KILL REAP '+repr(exc))
            try:
                self.record('original-client-exit.json', {'exit': self.original_client_exit,
                            'monotonic': time.monotonic(), 'originalActivation': self.activation,
                            'afterCancellation': True})
            except BaseException as exc:
                self.errors.append('CLIENT EXIT RECORD '+repr(exc))
        fields, groups = {}, {}
        while True:
            need(time.monotonic() < stop_end, 'Shared 19+1s cleanup window exhausted')
            try:
                fields, groups = self.snapshot('cleanup-reconcile', timeout=min(1, max(.05, (stop_end-time.monotonic())/4)))
            except BaseException as exc:
                fields, groups = {}, {}
                self.errors.append('CLEANUP READBACK '+repr(exc))
            targets = [u for u in self.units if u not in fields or not self.c.inactive(fields[u])]
            if targets:
                try:
                    left = stop_end-time.monotonic()
                    need(left > .2, 'No original time for exact-unit stop')
                    result = self.c.command(['/usr/bin/systemctl', 'stop', '--no-block', *targets],
                                            timeout=min(1, left), env=CLEAN)
                    self.record('stop-request-'+str(self.samples).zfill(4)+'.json', {'targets': targets, 'output': result})
                except BaseException as exc:
                    self.errors.append('EXACT STOP '+repr(exc))
            settled = (set(fields) == set(self.units) and set(groups) == set(self.units) and
                       all(self.c.inactive(fields[u]) for u in self.units) and
                       not any(g['members'] for g in groups.values()))
            if settled and (not unresolved_admission or time.monotonic() >= stop_end-.02):
                break
            need(time.monotonic() < stop_end-.01, 'Shared 19+1s cleanup window exhausted')
            time.sleep(min(.1, max(.001, stop_end-time.monotonic()-.015)))

    def finalize(self):
        need(self.activation is not None, 'No actual original activation: finalize cannot qualify')
        need(self.client is not None and self.client.poll() is not None, 'Manager client has not exited')
        need(self.c.inactive(self.c.unit_fields(self.units[0], timeout=2)),
             'Finalize requires independent manager inactive/MainPID0 readback')
        need(self.output.is_dir(), 'No invocation directory to finalize')
        for name in ('cleanup.json', 'final-status-readback.json'):
            need(not (self.output/name).exists(), 'Never rerun/overwrite failed or uncertain finalize')
        # R7 metadata helpers have 15s command + at most 2s reap bounds.
        # Leave 18s for an orphaned metadata helper if finalize is killed.
        remaining = self.activation+1520-time.monotonic()
        timeout = min(60, remaining-18)
        need(timeout > 0, 'Insufficient original deadline for bounded finalize; retain failure')
        self.record('finalize-attempt.json', {'argv': self.plan['finalizeCommand'],
                    'timeoutSeconds': timeout, 'originalCleanupDeadlineMonotonic': self.activation+1520})
        with (self.evidence/'finalize.log').open('xb') as log:
            os.fchown(log.fileno(), 1002, 1002)
            child = subprocess.Popen(self.plan['finalizeCommand'], stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=subprocess.STDOUT, env=CLEAN, start_new_session=True)
            try:
                self.finalize_exit = child.wait(timeout=timeout)
            except BaseException:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=1)
                raise
        self.record('finalize-exit.json', {'exit': self.finalize_exit})
        need(self.finalize_exit == 0, 'R7 finalize refused qualification; never overwrite its cleanup.json')

    def independent_final(self):
        fields, groups = self.snapshot('independent-final')
        remaining = [pid for pid, tick in self.processes.items()
                     if start_ticks(self.c, int(pid)) == tick]
        passed = (all(self.c.inactive(f) for f in fields.values()) and
                  not any(g['members'] for g in groups.values()) and not remaining and
                  self.activation is not None and time.monotonic() <= self.activation+1520)
        self.record('independent-final.json', {'units': fields, 'groups': groups,
                    'remainingExactProcesses': remaining, 'monotonic': time.monotonic(),
                    'originalActivation': self.activation, 'checksPassed': passed})
        need(passed, 'Independent exact unit/process/cgroup/deadline verification failed')
        cleanup = self.c.read(self.output/'cleanup.json')
        need(cleanup['requestId'] == self.value['requestId'] and
             cleanup['controllerSHA256'] == CONTROLLER_HASH, 'R7 cleanup binding differs')
        need(all(cleanup.get(k) is True for k in ('ownedUnitsInactive', 'ownedProcessesAbsent',
             'inputPinsUnchanged', 'withinDeadline', 'verifiedCompletionCapture')) and
             cleanup.get('resourceCaptureBoundary') == 'work-complete/pre-exit' and
             cleanup.get('activeProcesses') == 0 and cleanup.get('errors') == [] and
             type(cleanup.get('workloadSwapBytes')) is int and cleanup['workloadSwapBytes'] == 0 and
             type(cleanup.get('oomKills')) is int and cleanup['oomKills'] == 0,
             'R7 cleanup is failed/incomplete, not qualifying evidence')
        self.record('cleanup-mapping.json', {'mapping': 'IDENTITY: original R7 finalize output; no invented fields',
                    'cleanup': str(self.output/'cleanup.json'), 'sha256': self.c.digest(self.output/'cleanup.json')})

    def execute(self):
        self.c.owned_dir(self.evidence)
        self.c.write(self.marker, {'requestId': self.value['requestId'],
                     'output': str(self.output), 'atUTC': self.c.utc().isoformat(),
                     'note': 'One launch attempt only, including unobserved admission; never reuse'})
        self.record('admission-intent.json', self.plan)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, self.on_signal)
        try:
            self.run_manager()
        except BaseException as exc:
            self.errors.append('MANAGER '+repr(exc))
        # Independent phases stay unconditional: failed stop must not erase status
        # or prevent a feasible, separately bounded finalize/readback attempt.
        for label, action in (('CLEANUP', self.cleanup), ('FINALIZE', self.finalize),
                              ('INDEPENDENT', self.independent_final)):
            try:
                action()
            except BaseException as exc:
                self.errors.append(label+' '+repr(exc))
        if self.client is not None and self.client.poll() is None:
            # Only this known unreaped subprocess group; failure is retained.
            self.errors.append('CLIENT required SIGKILL; original manager result not accepted')
            os.killpg(self.client.pid, signal.SIGKILL)
            self.client.wait(timeout=1)
        self.record('executor-result.json', {'errors': self.errors,
                    'originalClientExit': self.original_client_exit, 'finalizeExit': self.finalize_exit,
                    'controllerSHA256': CONTROLLER_HASH, 'sourceRevision': self.value['sourceRevision'],
                    'cleanup': str(self.output/'cleanup.json'),
                    'readyForParentEvidenceReviewOnly': not self.errors,
                    'qualificationAccepted': False, 'sealed': False})
        try:
            reset_owned(self.units, self.evidence/'unit-results-before-reset.json')
        except BaseException as exc:
            self.errors.append('UNIT RESET '+repr(exc))
            self.record('unit-reset-error.json', {'error': repr(exc)})
        need(not self.errors, 'One-shot invocation failed; retain complete evidence: '+repr(self.errors))
        print(json.dumps({'reviewRequired': True, 'evidence': str(self.evidence),
                          'cleanup': str(self.output/'cleanup.json'), 'run': str(self.output/'run')}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'launch'))
    parser.add_argument('--controller', required=True, type=Path)
    parser.add_argument('--controller-sha256', required=True)
    for key in PATH_KEYS:
        parser.add_argument('--'+key.replace('_', '-'), required=True, type=Path)
    args = parser.parse_args()
    global CONTROLLER, CONTROLLER_HASH
    CONTROLLER = args.controller.resolve()
    CONTROLLER_HASH = args.controller_sha256
    c = load_controller()
    prepared = prepare(c, args)
    if args.mode == 'plan':
        print(json.dumps(prepared[-1], indent=2))
    else:
        Executor(c, args, prepared).execute()


if __name__ == '__main__':
    main()
