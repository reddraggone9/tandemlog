"""Native Linux startup: process launch to loaded-frame marker.

Synthetic data only. Does not flush OS page caches or claim device cold boot.
Run from repo with its native Linux release binary built and DISPLAY configured.
"""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import sqlite3
import subprocess
import threading
import time
import uuid

from synthetic_text_fixture import initialize_fixture


STARTUP_DEADLINE_SECONDS = 45


def seed_fixture(root, tasks, library):
    root.mkdir(exist_ok=True)
    folder, profile = root/'shared', root/'profile'
    folder.mkdir(exist_ok=True)
    profile.mkdir(exist_ok=True)
    if any(profile.iterdir()) or any(folder.iterdir()):
        raise RuntimeError('Benchmark requires fresh empty profile/shared directories; existing state retained')
    writer, user = (str(uuid.uuid4()) for _ in range(2))
    (root/'synthetic-workload.json').write_text(json.dumps({
        'synthetic': True, 'version': 1, 'writer': writer, 'user': user,
        'userName': 'Benchmark user', 'profile': str(profile.resolve()),
        'tasks': [{'id': str(uuid.uuid4()), 'title': f'Task {n:04d}',
                   'description': 'Synthetic startup workload'} for n in range(1, tasks+1)]}))
    receipt = initialize_fixture(folder, root, library)
    return folder, profile, receipt


def send_wm_delete_window(window):
    """Ask one validated X11 client to close using the standard ICCCM protocol."""
    import ctypes as c
    if not isinstance(window, int) or not 0 < window < 2**32:
        raise RuntimeError('Invalid owned X11 window')
    class Data(c.Union):
        _fields_ = [('b', c.c_char*20), ('s', c.c_short*10), ('l', c.c_long*5)]
    class ClientMessage(c.Structure):
        _fields_ = [('type', c.c_int), ('serial', c.c_ulong),
                    ('send_event', c.c_int), ('display', c.c_void_p),
                    ('window', c.c_ulong), ('message_type', c.c_ulong),
                    ('format', c.c_int), ('data', Data)]
    class Event(c.Union):
        _fields_ = [('xclient', ClientMessage), ('pad', c.c_long*24)]
    try:
        x = c.CDLL('libX11.so.6')
    except OSError as error:
        raise RuntimeError('Normal close requires the existing GTK X11 library libX11.so.6') from error
    signatures = {
        'XOpenDisplay': ([c.c_char_p], c.c_void_p),
        'XInternAtom': ([c.c_void_p, c.c_char_p, c.c_int], c.c_ulong),
        'XGetWMProtocols': ([c.c_void_p, c.c_ulong, c.POINTER(c.POINTER(c.c_ulong)), c.POINTER(c.c_int)], c.c_int),
        'XFree': ([c.c_void_p], c.c_int),
        'XSendEvent': ([c.c_void_p, c.c_ulong, c.c_int, c.c_long, c.POINTER(Event)], c.c_int),
        'XSync': ([c.c_void_p, c.c_int], c.c_int),
        'XCloseDisplay': ([c.c_void_p], c.c_int),
        'XSetErrorHandler': ([c.c_void_p], c.c_void_p),
    }
    for name, (arguments, result) in signatures.items():
        getattr(x, name).argtypes = arguments
        getattr(x, name).restype = result
    display = x.XOpenDisplay(None)  # The same explicit DISPLAY/XAUTHORITY as discovery.
    if not display:
        raise RuntimeError('Cannot open the measured X11 display for normal close')
    errors = []
    handler_type = c.CFUNCTYPE(c.c_int, c.c_void_p, c.c_void_p)
    handler = handler_type(lambda _display, _event: (errors.append(True), 0)[1])
    previous = x.XSetErrorHandler(c.cast(handler, c.c_void_p))
    try:
        protocols = x.XInternAtom(display, b'WM_PROTOCOLS', 1)
        delete = x.XInternAtom(display, b'WM_DELETE_WINDOW', 1)
        if not protocols or not delete:
            raise RuntimeError('Owned client does not advertise normal window-close atoms')
        supported = c.POINTER(c.c_ulong)()
        count = c.c_int()
        try:
            found = x.XGetWMProtocols(display, window, c.byref(supported), c.byref(count))
            if not found or not 0 < count.value <= 256 or delete not in supported[:count.value]:
                raise RuntimeError('Owned client does not support WM_DELETE_WINDOW')
        finally:
            if supported:
                x.XFree(supported)
        event = Event()
        event.xclient.type = 33  # ClientMessage
        event.xclient.send_event = 1
        event.xclient.display = display
        event.xclient.window = window
        event.xclient.message_type = protocols
        event.xclient.format = 32
        event.xclient.data.l[0] = delete
        event.xclient.data.l[1] = 0  # CurrentTime; no focus or input action.
        sent = x.XSendEvent(display, window, 0, 0, c.byref(event))
        x.XSync(display, 0)
        if not sent or errors:
            raise RuntimeError('X11 server refused the owned normal-close request')
    finally:
        try:
            x.XCloseDisplay(display)
        finally:
            x.XSetErrorHandler(previous)


def request_owned_window_close(proc, xdotool):
    """Send WM_DELETE_WINDOW to one owned visible window; never focus/input."""
    if proc.poll() is not None:
        raise RuntimeError('Measured process exited before a normal window-close request')
    status = Path(f'/proc/{proc.pid}/status').read_text()
    uid = next(line for line in status.splitlines() if line.startswith('Uid:'))
    if any(int(value) != os.getuid() for value in uid.split()[1:]):
        raise RuntimeError('Measured window process UID changed')
    def command(*args):
        try:
            result = subprocess.run([str(xdotool), *args], stdin=subprocess.DEVNULL,
                                    capture_output=True, text=True, timeout=5)
        except FileNotFoundError as error:
            raise RuntimeError('Normal close requires executable xdotool for owned-window discovery: '
                               + str(xdotool)) from error
        if result.returncode:
            raise RuntimeError(f'Owned window close command failed: {args[0]}')
        return result.stdout.strip()
    windows = command('search', '--onlyvisible', '--pid', str(proc.pid)).splitlines()
    if len(windows) != 1 or not windows[0].isdigit() or not 0 < int(windows[0]) < 2**32:
        raise RuntimeError('Normal close requires exactly one owned visible window')
    window = windows[0]
    if command('getwindowpid', window) != str(proc.pid) or proc.poll() is not None:
        raise RuntimeError('Measured window/PID binding changed')
    # Old distro xdotool lacks windowquit; windowclose would destroy the window.
    send_wm_delete_window(int(window))
    return {'method': 'owned-window-WM_DELETE_WINDOW', 'pid': proc.pid,
            'window': window, 'globalFocusOrInput': False}


def finish_process(proc, marker, close_mode, xdotool):
    result = {'requestedMode': close_mode, 'normalExitVerified': False}
    started = time.perf_counter()
    if proc.poll() is None and marker and close_mode == 'normal':
        try:
            result.update(request_owned_window_close(proc, xdotool))
            proc.wait(timeout=15)
            result['normalExitVerified'] = proc.returncode == 0
        except Exception as error:
            result['normalCloseError'] = str(error)
    if proc.poll() is None:
        result['forcedTerminationUsed'] = True
        result['method'] = 'SIGTERM'
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            result['method'] = 'SIGKILL-after-SIGTERM-timeout'
            proc.kill()
            proc.wait(timeout=5)
    result.update(processExit=proc.returncode,
                  elapsedMs=round((time.perf_counter()-started)*1000, 3))
    return result


def inspect_stopped_witness(profile, folder):
    """Presence/hash evidence only; production reuse validates actual bindings."""
    database = profile/'local.sqlite'
    result = {'taskProofPresent': False, 'decodedProofPresent': False,
              'taskProofShapeValid': False, 'decodedPayloadHashMatches': False,
              'productionReuseVerified': False}
    if not database.exists():
        return result
    epoch = json.loads((folder/'tandemlog-space.json').read_text())['epoch']
    key = hashlib.sha256(f'{folder}#app5:{epoch}'.encode()).hexdigest()
    names = [f'app5.task.cache.{key}', f'app5.decoded.proof.{key}',
             f'app5.decoded.payload.{key}']
    with closing(sqlite3.connect(database.resolve().as_uri()+'?mode=ro', uri=True, timeout=0)) as db:
        db.execute('PRAGMA query_only=ON')
        rows = dict(db.execute('SELECT key,value FROM profile_metadata WHERE key IN (?,?,?)', names))
    task, proof, payload = (rows.get(name) for name in names)
    result.update(taskProofPresent=task is not None, decodedProofPresent=proof is not None)
    if task is not None:
        result['taskProofSHA256'] = hashlib.sha256(task.encode()).hexdigest()
        try:
            value = json.loads(task)
            result['taskProofShapeValid'] = (value.get('generation') == 3 and
                value.get('native') is True and all(isinstance(value.get(field), str) and
                re.fullmatch('[0-9a-f]{64}', value[field]) for field in ('manifest','revision','digest')))
        except (ValueError, AttributeError):
            pass
    if payload is not None:
        result['decodedPayloadSHA256'] = hashlib.sha256(payload.encode()).hexdigest()
        result['decodedPayloadHashMatches'] = result['decodedPayloadSHA256'] == proof
    return result


def launch(binary, profile, diagnostics, run, *, close_mode="normal", xdotool="xdotool"):
    """Retain combined application stdout/stderr even without a ready marker."""
    start = time.perf_counter()
    proc = None
    marker, marks, lines, pending = None, {}, [], b''
    output_path = diagnostics/f'run-{run}.stdout-stderr.log'
    status_path = diagnostics/f'run-{run}.json'
    status = {'run': run, 'passed': False, 'cleanWitnessVerified': False, 'closeMode': close_mode}
    try:
        with output_path.open('wb') as output:
            proc = subprocess.Popen(
                binary if isinstance(binary, list) else [str(binary)],
                env=dict(os.environ, TANDEMLOG_PROFILE=str(profile),
                                        GSETTINGS_BACKEND='memory'),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
            chunks = queue.Queue()

            def read_output():
                while True:
                    chunk = proc.stdout.read(65536)
                    if not chunk:
                        chunks.put(None)
                        return
                    output.write(chunk)
                    output.flush()
                    chunks.put(chunk)

            reader = threading.Thread(target=read_output, daemon=True)
            reader.start()
            try:
                while time.perf_counter()-start < STARTUP_DEADLINE_SECONDS:
                    try:
                        chunk = chunks.get(timeout=.1)
                    except queue.Empty:
                        continue
                    if chunk is None:
                        break
                    pending += chunk
                    while b'\n' in pending:
                        raw, pending = pending.split(b'\n', 1)
                        line = raw.decode(errors='replace').strip()
                        if line.startswith('TANDEMLOG_'):
                            lines.append(line)
                            if line == 'TANDEMLOG_MAIN':
                                marks['external_main_ms'] = round((time.perf_counter()-start)*1000)
                            if line.startswith('TANDEMLOG_FIRST_FRAME_MS='):
                                marks['external_first_frame_ms'] = round((time.perf_counter()-start)*1000)
                        if 'TANDEMLOG_READY_MS=' in line:
                            marker = line
                    if marker:
                        break
                elapsed = round((time.perf_counter()-start)*1000)
                status.update(external_ms=elapsed, marker=marker, phases=lines, **marks)
            finally:
                status['shutdown'] = finish_process(proc, marker, close_mode, xdotool)
                # The reader retains shutdown output and a final line without LF.
                reader.join(timeout=1)
                proc.stdout.close()
                status['process_exit'] = proc.returncode
        if not marker:
            raise RuntimeError('No loaded-frame marker; see retained application stdout/stderr')
        if close_mode == 'normal' and not status['shutdown']['normalExitVerified']:
            raise RuntimeError('Normal owned window close was not verified; forced cleanup is not a clean-close benchmark')
        return status
    except Exception as error:
        status['error'] = str(error)
        raise
    finally:
        status_path.write_text(json.dumps(status, indent=2)+'\n', encoding='utf-8')


def verify_loaded(profile, folder, tasks, result, warm):
    if not any(line.startswith('TANDEMLOG_ROWS ') for line in result['phases']):
        raise RuntimeError('Ready marker was emitted without a successful model load')
    epoch = json.loads((folder/'tandemlog-space.json').read_text())['epoch']
    key = hashlib.sha256(f'{folder}#app5:{epoch}'.encode()).hexdigest()
    database = profile/'local.sqlite'
    if database.exists():
        table = f'tasks_{key}_views'
    else:
        database, table = profile/'spaces'/key/'cache.sqlite', 'views'
    with closing(sqlite3.connect(database.resolve().as_uri()+'?mode=ro', uri=True, timeout=0)) as db:
        db.execute('PRAGMA query_only=ON')
        projected = [json.loads(row[0]) for row in db.execute(f'SELECT raw FROM {table}')]
    if len(projected) != tasks+1 or sum(row['kind'] == 'task' for row in projected) != tasks:
        raise RuntimeError('Loaded cache does not contain the complete synthetic workload')
    match = re.search(r'FILES_READ=(\d+)$', result['marker'])
    canonical_files = len(list(folder.glob('*.applog')))
    if not match or not canonical_files:
        raise RuntimeError('Ready marker lacks truthful canonical-read attribution')
    reads = int(match[1])
    result.update(canonical_payload_reads=reads, canonical_files=canonical_files)
    # A new process reconstructs/admits canonical physical history. Normal
    # in-process refresh uses ADR7 metadata/suffix reads, while explicit audit
    # still rereads old prefixes. Cache reuse is not zero-read startup.
    if not canonical_files <= reads <= 8*canonical_files:
        raise RuntimeError('Startup canonical admission exceeded its bounded scan stages')

    reuse = None
    for line in result['phases']:
        if line.startswith('TANDEMLOG_STARTUP_CACHE '):
            reuse = json.loads(line.split(' ', 1)[1])
    result['startupCacheCounters'] = reuse
    before = result.get('witnessBeforeLaunch', {})
    task_reused = bool(reuse and reuse.get('warmTaskProjectionReuses', 0) > 0)
    decoded_reused = bool(reuse and reuse.get('decodedCacheReuses', 0) > 0)
    clean_repeat = bool(warm and result.get('previousNormalExitVerified'))
    if clean_repeat and before.get('taskProofShapeValid') and not task_reused:
        raise RuntimeError('Prior sealed Task witness was not actually reused')
    if clean_repeat and before.get('decodedPayloadHashMatches') and not decoded_reused:
        raise RuntimeError('Prior sealed decoded witness was not actually reused')
    result.update(cleanTaskWitnessVerified=clean_repeat and before.get('taskProofShapeValid', False) and task_reused,
                  cleanDecodedWitnessVerified=clean_repeat and before.get('decodedPayloadHashMatches', False) and decoded_reused)
    result['cleanWitnessVerified'] = result['cleanTaskWitnessVerified'] and result['cleanDecodedWitnessVerified']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tasks', type=int, default=2000)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--binary', default='build/linux/x64/release/bundle/tandemlog')
    parser.add_argument('--label', default='tasks')
    parser.add_argument('--workspace', default='/workspace/tandemlog-performance',
                        help='Dedicated disposable benchmark directory; never use a real profile')
    parser.add_argument('--native-library', help='Exact native library for synthetic initialization; defaults to measured Linux bundle')
    parser.add_argument('--diagnostics', help='Retained engineering diagnostics directory, outside publication assets')
    parser.add_argument('--close-mode', choices=['normal', 'terminate'], default='normal',
                        help='Normal owned-window close, or explicitly abrupt SIGTERM trials; SIGTERM never proves a clean witness')
    parser.add_argument('--xdotool', default=shutil.which('xdotool') or 'xdotool',
                        help='xdotool for owned-window discovery; normal close uses existing libX11, no focus/input is sent')
    args = parser.parse_args()
    if args.tasks < 0 or args.runs < 1:
        parser.error('tasks must be nonnegative and runs must be positive')
    root = Path(args.workspace).resolve()
    diagnostics = Path(args.diagnostics) if args.diagnostics else root/'startup-diagnostics'
    diagnostics.mkdir(parents=True, exist_ok=True)
    report = dict(target='Linux x86_64 native / Xvfb', binary=args.binary,
                  tasks=args.tasks, label=args.label, os_page_cache='not flushed', close_mode=args.close_mode, results=[])
    try:
        library = args.native_library or str(Path(args.binary).resolve().parent/'lib/libtandemlog_text.so')
        folder, profile, receipt = seed_fixture(root, args.tasks, library)
        report['fixture'] = receipt
        previous = None
        for i in range(args.runs):
            witness_before = inspect_stopped_witness(profile, folder)
            result = launch(args.binary, profile, diagnostics, i+1,
                            close_mode=args.close_mode, xdotool=args.xdotool)
            result['witnessBeforeLaunch'] = witness_before
            result['previousNormalExitVerified'] = bool(previous and previous['shutdown']['normalExitVerified'])
            report['results'].append(result)
            if not args.label.startswith('minimal'):
                verify_loaded(profile, folder, args.tasks, result, i > 0)
            result['witnessAfterClose'] = inspect_stopped_witness(profile, folder)
            result.update(passed=True, cache='not used' if args.label.startswith('minimal')
                          else ('verified-clean-repeat' if result.get('cleanWitnessVerified') else
                                'first-launch-no-cold-boot-claim' if i == 0 else
                                'repeat-after-normal-close-without-full-reuse-proof' if result['shutdown']['normalExitVerified'] else
                                'repeat-after-SIGTERM-clean-witness-unverified'))
            previous = result
            (diagnostics/f'run-{i+1}.json').write_text(
                json.dumps(result, indent=2)+'\n', encoding='utf-8')
        report['passed'] = True
    except Exception as error:
        report.update(passed=False, error=str(error))
        raise
    finally:
        for name in ('text-seed.stdout.log', 'text-seed.stderr.log'):
            if (root/name).exists():
                (diagnostics/name).write_bytes((root/name).read_bytes())
        diagnostics.joinpath('report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
