import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from start_candidate_wait import command
from wait_signed_candidate import Waiter, WaitError, arguments, lock

SHA = 'a' * 40
REPO = 'reddraggone9/tandemlog'


def run_value(**changes):
    value = dict(id=123, head_sha=SHA, event='workflow_dispatch', head_branch='main',
                 path='.github/workflows/android-candidate.yml', status='completed', conclusion='success',
                 repository=dict(full_name=REPO), head_repository=dict(full_name=REPO))
    value.update(changes)
    return value


class CandidateWait(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.args = arguments(['--run-id', '123', '--source', SHA, '--output', str(self.root),
                               '--poll-interval', '.01', '--timeout', '2'])

    def waiter(self, runs=None, download=None):
        waiter = Waiter(self.args)
        iterator = iter(runs or [run_value()])
        waiter.api = lambda suffix: next(iterator)
        calls = []

        def gh(*args):
            calls.append(args)
            target = Path(args[-1])
            target.mkdir(parents=True)
            (target / (args[args.index('--name') + 1] + '.bin')).write_bytes(b'exact-bytes')
            return ''
        waiter.gh = download or gh
        waiter.calls = calls
        return waiter

    def phase(self):
        return json.loads((self.root / 'wait-status.json').read_text())['phase']

    def test_wait_completion_download_and_idempotent_resume(self):
        waiter = self.waiter([run_value(status='in_progress', conclusion=None), run_value()])
        waiter.run()
        self.assertEqual(self.phase(), 'success')
        self.assertEqual(len(waiter.calls), 3)
        for call in waiter.calls:
            self.assertEqual(call[:3], ('run', 'download', '123'))
        receipt = json.loads((self.root / 'candidate-download/download-receipt.json').read_text())
        self.assertEqual(set(receipt['files']), {'linux.bin', 'windows.bin', 'android-release.bin'})
        resumed = self.waiter()
        resumed.api = lambda _: self.fail('Completed download must not need GitHub')
        resumed.run()
        self.assertEqual(resumed.calls, [])

    def test_failure_conclusions_never_download(self):
        for conclusion in ('failure', 'cancelled', 'timed_out', 'skipped'):
            waiter = self.waiter([run_value(conclusion=conclusion)])
            with self.assertRaises(WaitError):
                waiter.run()
            self.assertEqual(waiter.calls, [])
            self.assertEqual(self.phase(), 'failed')

    def test_wrong_source_workflow_branch_repository_and_run_fail_closed(self):
        for changes in (dict(head_sha='b'*40), dict(path='other.yml'), dict(head_branch='dev'),
                        dict(repository=dict(full_name='other/repo')), dict(id=456),
                        dict(event='push'), dict(head_repository=dict(full_name='other/repo'))):
            waiter = self.waiter([run_value(**changes)])
            with self.assertRaises(WaitError):
                waiter.run()
            self.assertEqual(waiter.calls, [])

    def test_download_failure_not_promoted_and_same_run_recoverable(self):
        def bad(*_):
            raise WaitError('download failed')
        with self.assertRaises(WaitError):
            self.waiter(download=bad).run()
        self.assertFalse((self.root / 'candidate-download').exists())
        self.assertEqual(list(self.root.glob('.download-*')), [])
        self.waiter().run()
        self.assertEqual(self.phase(), 'success')

    def test_partial_download_failure_is_not_promoted(self):
        calls = []
        def partial(*args):
            calls.append(args)
            if len(calls) == 2:
                raise WaitError('windows download failed')
            target = Path(args[-1]); target.mkdir(parents=True)
            (target / 'linux.bin').write_bytes(b'bytes')
        with self.assertRaisesRegex(WaitError, 'windows download failed'):
            self.waiter(download=partial).run()
        self.assertFalse((self.root / 'candidate-download').exists())
        self.assertEqual(list(self.root.glob('.download-*')), [])
        self.waiter().run()
        self.assertEqual(self.phase(), 'success')

    @unittest.skipUnless(os.name == 'posix', 'POSIX symlink fixture')
    def test_symlink_artifact_is_not_promoted(self):
        outside = self.root / 'outside'; outside.write_bytes(b'not an artifact')
        def unsafe(*args):
            target = Path(args[-1]); target.mkdir(parents=True)
            (target / 'symlink').symlink_to(outside)
        with self.assertRaisesRegex(WaitError, 'unsafe'):
            self.waiter(download=unsafe).run()
        self.assertFalse((self.root / 'candidate-download').exists())

    def test_empty_and_duplicate_artifacts_fail(self):
        for empty in (True, False):
            def download(*args):
                target = Path(args[-1]); target.mkdir(parents=True)
                if not empty:
                    (target / 'collision').write_text('x')
            with self.assertRaises(WaitError):
                self.waiter(download=download).run()
            self.assertFalse((self.root / 'candidate-download').exists())

    def test_existing_receipt_checks_source_and_bytes(self):
        self.waiter().run()
        self.args.source = 'b'*40
        with self.assertRaisesRegex(WaitError, 'different run/source'):
            self.waiter().run()
        self.args.source = SHA
        (self.root / 'candidate-download/dist/linux.bin').write_bytes(b'corrupt')
        with self.assertRaisesRegex(WaitError, 'files changed'):
            self.waiter().run()

    def test_overall_deadline_records_failure(self):
        waiter = self.waiter([run_value(status='in_progress', conclusion=None)])
        waiter.deadline = time.monotonic() - 1
        with self.assertRaisesRegex(WaitError, 'deadline'):
            waiter.run()
        self.assertEqual(self.phase(), 'failed')

    def test_cli_error_is_actionable_but_not_credential_stderr(self):
        waiter = Waiter(self.args)
        with patch('wait_signed_candidate.subprocess.run', return_value=
                   subprocess.CompletedProcess([], 4, '', 'SECRET signed URL')):
            with self.assertRaisesRegex(WaitError, 'exit 4') as error:
                waiter.run()
        self.assertNotIn('SECRET', str(error.exception))
        self.assertNotIn('SECRET', (self.root / 'wait-status.json').read_text())

    def test_command_timeout_and_invalid_json_report_terminal_failure(self):
        for response in (subprocess.TimeoutExpired('gh', 1),
                         subprocess.CompletedProcess([], 0, 'invalid JSON SECRET', '')):
            kwargs = dict(side_effect=response) if isinstance(response, Exception) else dict(return_value=response)
            with patch('wait_signed_candidate.subprocess.run', **kwargs):
                with self.assertRaises(WaitError):
                    Waiter(self.args).run()
            self.assertEqual(self.phase(), 'failed')
            self.assertNotIn('SECRET', (self.root / 'wait-status.json').read_text())

    def test_manager_launch_has_independent_owner_and_outer_margin(self):
        self.args.token_file = self.root / 'private-token'
        self.args.direct_network = True
        unit, cmd = command(self.args)
        self.assertIn('--user', cmd)
        self.assertIn('--property=RuntimeMaxSec=32.0', cmd)
        self.assertIn('--property=KillMode=control-group', cmd)
        self.assertIn('--property=RemainAfterExit=yes', cmd)
        self.assertIn('--token-file', cmd)
        self.assertEqual(command(self.args)[0], unit)
        self.assertNotIn('--collect', cmd)  # terminal unit result remains queryable

    def test_argument_validation(self):
        for extra in (['--timeout', 'nan'], ['--poll-interval', '0'], ['--run-id', 'x'],
                      ['--source', 'short'], ['--repository', 'bad']):
            with self.assertRaises(SystemExit):
                arguments(['--run-id', '123', '--source', SHA, '--output', str(self.root), *extra])

    @unittest.skipUnless(os.name == 'posix', 'POSIX lifecycle integration')
    def test_lock_conflict_and_recovery(self):
        with lock(self.root / 'wait.lock'):
            with self.assertRaisesRegex(WaitError, 'Another waiter'):
                self.waiter().run()
        self.waiter().run()
        self.assertEqual(self.phase(), 'success')

    @unittest.skipUnless(os.name == 'posix', 'POSIX signal integration')
    def test_sigterm_during_real_sleep_writes_failure_and_nonzero(self):
        fake = self.root / 'bin'; fake.mkdir()
        gh = fake / 'gh'
        gh.write_text('#!' + sys.executable + '\nprint(' + repr(json.dumps(run_value(status='in_progress', conclusion=None))) + ')\n')
        gh.chmod(0o700)
        env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ['PATH'])
        with (self.root / 'cli.log').open('w') as log:
            child = subprocess.Popen([sys.executable, str(Path(__file__).with_name('wait_signed_candidate.py')),
                                      '--run-id', '123', '--source', SHA, '--output', str(self.root),
                                      '--poll-interval', '60'], env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    try:
                        if self.phase() == 'waiting':
                            break
                    except (FileNotFoundError, json.JSONDecodeError):
                        pass
                    time.sleep(.02)
                self.assertEqual(self.phase(), 'waiting')
                child.send_signal(signal.SIGTERM)
                self.assertEqual(child.wait(timeout=5), 1)
                self.assertEqual(self.phase(), 'failed')
                self.assertIn('signal 15', (self.root / 'wait-status.json').read_text())
            finally:
                if child.poll() is None:
                    child.kill(); child.wait()


if __name__ == '__main__':
    unittest.main()
