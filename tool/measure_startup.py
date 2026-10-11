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
    space, writer, user = (str(uuid.uuid4()) for _ in range(3))
    (folder/'tandemlog-space.json').write_text(json.dumps({'v': 3, 'id': space}))
    events = []
    batch_ns = time.time_ns()
    previous = hashlib.sha256(f'tandemlog:genesis:v3\n{space}\n{writer}\n'.encode()).hexdigest()
    for n in range(tasks+1):
        entity = user if n == 0 else str(uuid.uuid4())
        data = {'name': 'Benchmark user'} if n == 0 else {
            'title': f'Task {n:04d}', 'description': 'Synthetic startup workload', 'assignee': user}
        # Preserve the original scalar workload and fixed v3 envelope ordering.
        record = dict(v=3, space=space, writer=writer, seq=n+1,
                      clock=str(batch_ns+n), entity=entity,
                      type='user.created' if n == 0 else 'task.created',
                      data=dict(sorted(data.items())), previousHash=previous)
        unsigned = json.dumps(record, ensure_ascii=False, separators=(',', ':'))
        record['hash'] = hashlib.sha256(('tandemlog:event:v3\n'+unsigned).encode()).hexdigest()
        previous = record['hash']
        events.append(json.dumps(record, ensure_ascii=False, separators=(',', ':')))
    (folder/f'{writer}.jsonl').write_bytes(('\n'.join(events)+'\n').encode('utf-8'))
    receipt = initialize_fixture(folder, root, library)
    (profile/'settings.json').write_text(json.dumps({'folder': str(folder), 'user': user}))
    return folder, profile, receipt


def launch(binary, profile, diagnostics, run):
    """Retain combined application stdout/stderr even without a ready marker."""
    start = time.perf_counter()
    proc = None
    marker, marks, lines, pending = None, {}, [], b''
    output_path = diagnostics/f'run-{run}.stdout-stderr.log'
    status_path = diagnostics/f'run-{run}.json'
    status = {'run': run, 'passed': False}
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
                if proc.poll() is None:
                    proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                # The reader retains shutdown output and a final line without LF.
                reader.join(timeout=1)
                proc.stdout.close()
                status['process_exit'] = proc.returncode
        if not marker:
            raise RuntimeError('No loaded-frame marker; see retained application stdout/stderr')
        return status
    except Exception as error:
        status['error'] = str(error)
        raise
    finally:
        status_path.write_text(json.dumps(status, indent=2)+'\n', encoding='utf-8')


def verify_loaded(profile, folder, tasks, result, warm):
    if not any(line.startswith('TANDEMLOG_ROWS ') for line in result['phases']):
        raise RuntimeError('Ready marker was emitted without a successful model load')
    key = hashlib.sha256(str(folder).encode()).hexdigest()
    database = profile/'local.sqlite'
    if database.exists():
        table = f'tasks_{key}_views'
    else:
        database, table = profile/'spaces'/key/'cache.sqlite', 'views'
    with closing(sqlite3.connect(str(database), timeout=0)) as db:
        db.execute('PRAGMA locking_mode=EXCLUSIVE')
        projected = [json.loads(row[0]) for row in db.execute(f'SELECT raw FROM {table}')]
    if len(projected) != tasks+1 or sum(row['kind'] == 'task' for row in projected) != tasks:
        raise RuntimeError('Loaded cache does not contain the complete synthetic workload')
    if warm and not result['marker'].endswith('FILES_READ=0'):
        raise RuntimeError('Warm cache unexpectedly replayed canonical log contents')


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
    args = parser.parse_args()
    if args.tasks < 0 or args.runs < 1:
        parser.error('tasks must be nonnegative and runs must be positive')
    root = Path(args.workspace)
    diagnostics = Path(args.diagnostics) if args.diagnostics else root/'startup-diagnostics'
    diagnostics.mkdir(parents=True, exist_ok=True)
    report = dict(target='Linux x86_64 native / Xvfb', binary=args.binary,
                  tasks=args.tasks, label=args.label, os_page_cache='not flushed', results=[])
    try:
        library = args.native_library or str(Path(args.binary).resolve().parent/'lib/libtandemlog_text.so')
        folder, profile, receipt = seed_fixture(root, args.tasks, library)
        report['fixture'] = receipt
        for i in range(args.runs):
            result = launch(args.binary, profile, diagnostics, i+1)
            report['results'].append(result)
            if not args.label.startswith('minimal'):
                verify_loaded(profile, folder, args.tasks, result, i > 0)
            result.update(passed=True, cache='not used' if args.label.startswith('minimal')
                          else ('rebuild' if i == 0 else 'warm'))
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
