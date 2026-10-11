"""Early process failures retain evidence; readiness still requires the model."""
from pathlib import Path
from contextlib import closing
import json
import hashlib
import sqlite3
import sys
import tempfile
import unittest

from measure_startup import launch, verify_loaded, STARTUP_DEADLINE_SECONDS


class StartupDiagnostics(unittest.TestCase):
    def test_early_native_failure_retains_stdout_stderr_and_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = [sys.executable, '-c',
                       'import sys; print("synthetic stdout", flush=True); '
                       'print("synthetic stderr", file=sys.stderr, flush=True); '
                       'sys.exit(23)']
            with self.assertRaisesRegex(RuntimeError, 'No loaded-frame marker'):
                launch(command, root/'profile', root, 1)
            output = (root/'run-1.stdout-stderr.log').read_text()
            status = json.loads((root/'run-1.json').read_text())
            self.assertIn('synthetic stdout', output)
            self.assertIn('synthetic stderr', output)
            self.assertFalse(status['passed'])
            self.assertIsNone(status['marker'])
            self.assertIn('error', status)
            self.assertEqual(status['process_exit'], 23)
            self.assertEqual(STARTUP_DEADLINE_SECONDS, 45)

    def test_loaded_marker_does_not_accept_missing_rows_or_replayed_warm_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'shared'
            profile = root/'profile'
            profile.mkdir()
            table = 'tasks_'+hashlib.sha256(str(folder).encode()).hexdigest()+'_views'
            with closing(sqlite3.connect(profile/'local.sqlite')) as db, db:
                db.execute(f'CREATE TABLE {table}(raw TEXT)')
                for kind in ('user', 'task'):
                    db.execute(f'INSERT INTO {table} VALUES (?)', (json.dumps({'kind': kind}),))
            result = {'marker': 'TANDEMLOG_READY_MS=4 FILES_READ=1', 'phases': []}
            with self.assertRaisesRegex(RuntimeError, 'successful model load'):
                verify_loaded(profile, folder, 1, result, False)
            result['phases'] = ['TANDEMLOG_ROWS {"query_ms":1}']
            with self.assertRaisesRegex(RuntimeError, 'complete synthetic workload'):
                verify_loaded(profile, folder, 2, result, False)
            with self.assertRaisesRegex(RuntimeError, 'Warm cache'):
                verify_loaded(profile, folder, 1, result, True)
            result['marker'] = 'TANDEMLOG_READY_MS=4 FILES_READ=0'
            verify_loaded(profile, folder, 1, result, True)


if __name__ == '__main__':
    unittest.main()
