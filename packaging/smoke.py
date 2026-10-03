"""Installed native app QA on disposable synthetic state; no real user data.

Use --seed once, --phase after-install/after-upgrade/after-reinstall to assert
loaded SQLite projections and canonical hash continuity. GUI process existence
alone is deliberately insufficient. Works with an installed EXE or flatpak run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import sqlite3
import subprocess
import threading
import tempfile
import time
import uuid


def hashes(folder):
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.iterdir() if p.is_file()}


def flatpak_instances(executable):
    output = subprocess.check_output([executable, 'ps', '--columns=instance'], text=True)
    return {line.strip() for line in output.splitlines() if line.strip().isdigit()}


def stop_flatpak_instance(executable, instance_file):
    # The ID is supplied by this exact flatpak run through its inherited FD.
    # Never kill by application ID: another launch could belong to someone else.
    instance_file.seek(0)
    instance = instance_file.read().decode('ascii').strip()
    if not instance.isdigit():
        raise RuntimeError('Flatpak did not report the exact launched instance ID')
    if instance in flatpak_instances(executable):
        subprocess.run([executable, 'kill', instance], check=True, capture_output=True, text=True)
    deadline = time.monotonic()+15
    while instance in flatpak_instances(executable):
        if time.monotonic() >= deadline:
            raise RuntimeError('Synthetic Flatpak instance survived cleanup: '+instance)
        time.sleep(.1)
    return instance


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--workspace', required=True)
    parser.add_argument('--report', required=True)
    parser.add_argument('--profile')
    parser.add_argument('--folder')
    parser.add_argument('--default-profile', action='store_true', help='Let installed launcher choose its native profile')
    parser.add_argument('--phase', required=True)
    parser.add_argument('--seed', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    root = Path(args.workspace).resolve()
    root.mkdir(parents=True, exist_ok=True)
    profile = Path(args.profile).resolve() if args.profile else root/'profile'
    folder = Path(args.folder).resolve() if args.folder else root/'shared'
    if args.seed:
        if profile.exists() or folder.exists():
            raise RuntimeError('Refusing to overwrite an existing QA fixture')
        profile.mkdir(parents=True)
        folder.mkdir()
        space, writer, user, task = (str(uuid.uuid4()) for _ in range(4))
        (folder/'tandemlog-space.json').write_text(json.dumps({'v': 2, 'id': space}))
        events = []
        for seq, entity, kind, data in (
                (1, user, 'user.created', {'name': 'Installer QA user'}),
                (2, task, 'task.created', {'title': 'Installer retained task',
                                         'description': 'Synthetic state only', 'assignee': user})):
            events.append(json.dumps(dict(v=2, space=space, writer=writer, seq=seq,
                                          clock=str(time.time_ns()+seq), entity=entity,
                                          type=kind, data=data)))
        (folder/f'{writer}.jsonl').write_text('\n'.join(events)+'\n')
        # Lifecycle replacement tests start with current preferences. Legacy
        # settings legitimately gain a writer during their separately tested
        # migration; arbitrary preference changes must still fail this gate.
        installation_writer = str(uuid.uuid4())
        (profile/'settings.json').write_text(json.dumps({
            'folder': str(folder), 'user': user, 'appearance': 'system',
            'writer': installation_writer}))
        (root/'expected.json').write_text(json.dumps({'canonical': hashes(folder),
                                                    'settings': hashes(profile)['settings.json']}))
    expected = json.loads((root/'expected.json').read_text())
    if hashes(folder) != expected['canonical']:
        raise RuntimeError('Canonical data changed during installer lifecycle')
    if hashlib.sha256((profile/'settings.json').read_bytes()).hexdigest() != expected['settings']:
        raise RuntimeError('Profile settings changed during installer lifecycle')
    cache = profile/'spaces'/hashlib.sha256(str(folder).encode()).hexdigest()/'cache.sqlite'
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if command:
        # Force this installed process to reconstruct the projection; stale cache
        # from an earlier lifecycle phase cannot satisfy the launch assertion.
        for suffix in ('', '-wal', '-shm'):
            Path(str(cache)+suffix).unlink(missing_ok=True)
        env = dict(os.environ, GSETTINGS_BACKEND='memory')
        if args.default_profile:
            env.pop('TANDEMLOG_PROFILE', None)
        else:
            env['TANDEMLOG_PROFILE'] = str(profile)
        instance_file = None
        process_options = {}
        if os.name != 'nt' and Path(command[0]).name == 'flatpak' and command[1:2] == ['run']:
            instance_file = tempfile.TemporaryFile(mode='w+b', dir=root)
            descriptor = instance_file.fileno()
            command = command[:2]+['--die-with-parent', f'--instance-id-fd={descriptor}']+command[2:]
            process_options['pass_fds'] = (descriptor,)
        proc = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
                                **process_options)
        lines = queue.Queue()
        def reader():
            for line in proc.stdout:
                lines.put(line.rstrip())
        threading.Thread(target=reader, daemon=True).start()
        output, ready = [], False
        deadline = time.monotonic()+60
        try:
            while time.monotonic() < deadline:
                try:
                    line = lines.get(timeout=.2)
                    output.append(line)
                    if 'TANDEMLOG_READY_MS=' in line:
                        ready = True
                        break
                except queue.Empty:
                    if proc.poll() is not None:
                        break
                if os.name == 'nt' and cache.exists():
                    # Windows GUI subsystem stdout is not reliably redirected.
                    # Require its own visible top-level native window AND loaded cache.
                    import ctypes
                    found = []
                    ctypes.windll.user32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
                    ctypes.windll.user32.IsWindowVisible.argtypes = [ctypes.c_void_p]
                    ctypes.windll.user32.EnumWindows.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
                    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
                    def inspect_window(hwnd, _):
                        pid = ctypes.c_ulong()
                        ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                        if pid.value == proc.pid and ctypes.windll.user32.IsWindowVisible(hwnd):
                            found.append(hwnd)
                        return True
                    ctypes.windll.user32.EnumWindows(callback_type(inspect_window), 0)
                    try:
                        with sqlite3.connect(f'file:{cache.as_posix()}?mode=ro', uri=True) as db:
                            count = db.execute('SELECT count(*) FROM views').fetchone()[0]
                        if found and count == 2:
                            ready = True
                            output.append('WINDOWS_VISIBLE_NATIVE_WINDOW_AND_LOADED_CACHE')
                            break
                    except sqlite3.Error:
                        pass
        finally:
            try:
                if instance_file is not None:
                    stopped_instance = stop_flatpak_instance(command[0], instance_file)
                    output.append('FLATPAK_INSTANCE_STOPPED='+stopped_instance)
            finally:
                if instance_file is not None:
                    instance_file.close()
                if proc.poll() is None:
                    proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        if not ready or (os.name != 'nt' and not any(line.startswith('TANDEMLOG_ROWS ') for line in output)):
            raise RuntimeError('Installed app failed to load synthetic tasks: '+'\n'.join(output))
        with sqlite3.connect(f'file:{cache.as_posix()}?mode=ro', uri=True) as db:
            views = [json.loads(row[0]) for row in db.execute('SELECT raw FROM views')]
        if len(views) != 2 or sum(row['kind'] == 'task' for row in views) != 1:
            raise RuntimeError('Installed application did not retain complete synthetic projection')
        if hashes(folder) != expected['canonical']:
            raise RuntimeError('Launch altered canonical source fixture')
    else:
        output = []
    report = Path(args.report)
    data = json.loads(report.read_text()) if report.exists() else {'phases': []}
    data['phases'].append({'phase': args.phase, 'passed': True,
                           'loaded_projection': bool(command),
                           'sandbox_stopped': any(x.startswith('FLATPAK_INSTANCE_STOPPED=') for x in output), 'markers': [x for x in output if x.startswith('TANDEMLOG_')]})
    report.write_text(json.dumps(data, indent=2)+'\n')


if __name__ == '__main__':
    main()
