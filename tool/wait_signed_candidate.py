"""Read-only, resumable wait/download for one already-dispatched signed candidate.

Never dispatches, retries a build, or publishes. See design/releases.md.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from candidate_source import validate_run


class WaitError(Exception):
    pass


def save(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


@contextmanager
def lock(path):
    with path.open('a+b') as stream:
        try:
            if os.name == 'nt':
                import msvcrt
                stream.seek(0)
                stream.write(b'0')
                stream.flush()
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise WaitError('Another waiter owns this output directory') from error
        try:
            yield
        finally:
            if os.name == 'nt':
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            # Closing the descriptor releases the POSIX lock, even after a crash.


class Waiter:
    def __init__(self, args):
        self.args = args
        self.output = args.output.resolve()
        self.env = os.environ.copy()
        if args.direct_network:
            self.env = {k: v for k, v in self.env.items() if not k.lower().endswith('_proxy')}
        if args.token_file:
            self.env['GH_TOKEN'] = args.token_file.read_text().strip()
        self.deadline = time.monotonic() + args.timeout
        self.state = dict(runId=args.run_id, source=args.source, repository=args.repository,
                          phase='starting', pid=os.getpid())

    def report(self, phase, **fields):
        self.state.update(phase=phase, updatedAt=time.time(), **fields)
        save(self.output / 'wait-status.json', self.state)
        print(json.dumps(self.state), flush=True)

    def remaining(self):
        left = self.deadline - time.monotonic()
        if left <= 0:
            raise WaitError('Wait/download deadline exceeded; recover this same run ID')
        return left

    def gh(self, *arguments):
        try:
            result = subprocess.run(['gh', *map(str, arguments)], capture_output=True,
                                    text=True, env=self.env,
                                    timeout=min(self.args.command_timeout, self.remaining()))
        except subprocess.TimeoutExpired as error:
            raise WaitError('GitHub command timed out; recover this same run ID') from error
        if result.returncode:
            # Do not echo CLI stderr: it can contain signed URLs or credentials.
            raise WaitError(f'GitHub command failed (exit {result.returncode}); '
                            'check gh auth status/network/artifact expiry, then resume this run')
        return result.stdout

    def api(self, suffix):
        return json.loads(self.gh('api', f'repos/{self.args.repository}/actions/runs/{self.args.run_id}{suffix}'))

    def wait(self):
        final = self.output / 'candidate-download'
        identity = {k: self.state[k] for k in ('runId', 'source', 'repository')}
        if final.exists():
            receipt = json.loads((final / 'download-receipt.json').read_text())
            if any(receipt.get(k) != v for k, v in identity.items()):
                raise WaitError('Existing download belongs to a different run/source/repository')
            files = {p.name: digest(p) for p in (final / 'dist').iterdir() if p.is_file()}
            if not files or files != receipt['files']:
                raise WaitError('Existing downloaded files changed; preserve evidence and use fresh output')
            self.report('success', reused=True, files=files)
            return
        while True:
            run = self.api('')
            save(self.output / 'candidate-run.json', run)
            if (str(run['id']) != self.args.run_id or run['head_sha'] != self.args.source
                    or run['event'] != 'workflow_dispatch' or run['head_branch'] != 'main'
                    or run['path'] != '.github/workflows/android-candidate.yml'
                    or run['repository']['full_name'] != self.args.repository
                    or run['head_repository']['full_name'] != self.args.repository):
                raise WaitError('Run ID does not match the requested signed candidate provenance')
            self.report('waiting', runStatus=run['status'], conclusion=run['conclusion'])
            if run['status'] == 'completed':
                if run['conclusion'] != 'success':
                    raise WaitError(f"Candidate completed with conclusion {run['conclusion']}; do not redispatch")
                validate_run(run, self.args.repository)
                break
            time.sleep(min(self.args.poll_interval, self.remaining()))
        self.report('downloading')
        # gh downloads each artifact separately: no implicit merging/clobbering.
        # Promote the entire bundle only after all three downloads and inventory pass.
        with tempfile.TemporaryDirectory(prefix='.download-', dir=self.output) as name:
            stage = Path(name)
            artifacts, dist = stage / 'artifacts', stage / 'dist'
            dist.mkdir()
            files = {}
            for artifact in ('linux', 'windows', 'android-release'):
                self.report('downloading', artifact=artifact)
                target = artifacts / artifact
                self.gh('run', 'download', self.args.run_id, '--repo', self.args.repository,
                        '--name', artifact, '--dir', target)
                members = list(target.rglob('*')) if target.exists() else []
                regular = [p for p in members if p.is_file()]
                if not regular or any(p.is_symlink() for p in members):
                    raise WaitError(f'Empty or unsafe {artifact} artifact')
                for path in regular:
                    if path.name in files:
                        raise WaitError(f'Duplicate artifact filename: {path.name}')
                    shutil.copyfile(path, dist / path.name)
                    files[path.name] = digest(dist / path.name)
            save(stage / 'download-receipt.json', dict(identity, files=files, completedAt=time.time()))
            self.remaining()
            stage.rename(final)
        self.report('success', reused=False, files=files)

    def run(self):
        self.output.mkdir(parents=True, exist_ok=True)
        with lock(self.output / 'wait.lock'):
            try:
                self.report('starting')
                self.wait()
            except BaseException as error:
                # No raw remote text/traceback in logs (including invalid JSON).
                message = str(error) if isinstance(error, WaitError) else type(error).__name__
                self.report('failed', error=message)
                raise WaitError(message) from error


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default='reddraggone9/tandemlog')
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--token-file', type=Path, help='Read token privately in worker, never argv value')
    parser.add_argument('--direct-network', action='store_true', help='Do not inherit proxy variables')
    parser.add_argument('--timeout', type=float, default=7200)
    parser.add_argument('--command-timeout', type=float, default=600)
    parser.add_argument('--poll-interval', type=float, default=60)
    args = parser.parse_args(argv)
    if not re.fullmatch(r'[0-9]+', args.run_id) or not re.fullmatch(r'[0-9a-f]{40}', args.source):
        parser.error('Expected numeric run ID and full lowercase source SHA')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        parser.error('Expected owner/repository')
    if any(not math.isfinite(v) or v <= 0 for v in
           (args.timeout, args.command_timeout, args.poll_interval)):
        parser.error('Timeouts and poll interval must be finite and positive')
    return args


def main(argv=None):
    def interrupted(number, _frame):
        raise WaitError(f'Interrupted by signal {number}; resume this same run ID')
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, interrupted)
    try:
        Waiter(arguments(argv)).run()
        return 0
    except (WaitError, OSError) as error:
        print(f'Candidate wait failed: {error}', file=sys.stderr, flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
