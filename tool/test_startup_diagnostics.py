"""Early process failures retain evidence; readiness still requires the model."""
from pathlib import Path
from contextlib import closing
import json
import hashlib
import sqlite3
import sys
import tempfile
import unittest
import os
import subprocess
from unittest.mock import patch

from measure_startup import launch, verify_loaded, inspect_stopped_witness, STARTUP_DEADLINE_SECONDS


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

    def test_loaded_marker_requires_complete_rows_and_bounded_truthful_admission_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root/'shared'
            profile = root/'profile'
            profile.mkdir()
            folder.mkdir()
            epoch='22222222-2222-4222-8222-222222222222'
            (folder/'tandemlog-space.json').write_text(json.dumps({'v':5,'epoch':epoch}))
            (folder/'11111111-1111-4111-8111-111111111111.applog').write_bytes(b'synthetic count sentinel')
            table = 'tasks_'+hashlib.sha256(f'{folder}#app5:{epoch}'.encode()).hexdigest()+'_views'
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
            verify_loaded(profile, folder, 1, result, True)
            self.assertEqual(result['canonical_payload_reads'], 1)
            for reads in (0,9):
                result['marker'] = f'TANDEMLOG_READY_MS=4 FILES_READ={reads}'
                with self.assertRaisesRegex(RuntimeError, 'bounded scan stages'):
                    verify_loaded(profile, folder, 1, result, True)

    def test_sigterm_repeat_is_explicitly_not_a_clean_native_close(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = [sys.executable, '-c',
                       'import time; print("TANDEMLOG_READY_MS=1 FILES_READ=1", flush=True); time.sleep(30)']
            result = launch(command, root/'profile', root, 1, close_mode='terminate')
            self.assertEqual(result['shutdown']['method'], 'SIGTERM')
            self.assertFalse(result['shutdown']['normalExitVerified'])
            self.assertFalse(result['cleanWitnessVerified'])

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Owned PID/UID window protocol is Linux-only')
    def test_normal_close_uses_exact_owned_pid_windowquit_without_focus_or_signal(self):
        # Fake manager commands exercise scope/cleanup, not actual GTK acceptance.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); stop = root/'stop'
            program = ('from pathlib import Path; import time; '
                       'print("TANDEMLOG_READY_MS=1 FILES_READ=1", flush=True); '
                       f'stop=Path({str(stop)!r}); '
                       'exec("while not stop.exists(): time.sleep(.01)")')
            commands = []; pid = None
            def manager(args, **kwargs):
                nonlocal pid
                commands.append(args[1:])
                if args[1] == 'search':
                    pid = args[-1]; output = '4194305\n'
                elif args[1] == 'getwindowpid':
                    output = pid+'\n'
                elif args[1] == 'windowquit':
                    stop.write_text('close acknowledged'); output = ''
                else:
                    raise AssertionError('Unexpected manager/input command')
                return subprocess.CompletedProcess(args, 0, output, '')
            with patch('measure_startup.subprocess.run', side_effect=manager):
                result = launch([sys.executable, '-c', program], root/'profile', root, 1,
                                close_mode='normal', xdotool='/synthetic/xdotool')
            self.assertTrue(result['shutdown']['normalExitVerified'])
            self.assertEqual(result['process_exit'], 0)
            self.assertFalse(result['shutdown']['globalFocusOrInput'])
            self.assertNotIn('forcedTerminationUsed', result['shutdown'])
            self.assertEqual([command[0] for command in commands], ['search','getwindowpid','windowquit'])

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Owned PID/UID window protocol is Linux-only')
    def test_foreign_window_binding_refuses_windowquit_and_retains_failed_forced_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); commands = []
            def manager(args, **kwargs):
                commands.append(args[1])
                output = '4194305\n' if args[1] == 'search' else '0\n'
                return subprocess.CompletedProcess(args, 0, output, '')
            with patch('measure_startup.subprocess.run', side_effect=manager):
                with self.assertRaisesRegex(RuntimeError, 'Normal owned window close was not verified'):
                    launch([sys.executable, '-c',
                            'import time; print("TANDEMLOG_READY_MS=1 FILES_READ=1", flush=True); time.sleep(30)'],
                           root/'profile', root, 1, close_mode='normal', xdotool='/synthetic/xdotool')
            status = json.loads((root/'run-1.json').read_text())
            self.assertFalse(status['shutdown']['normalExitVerified'])
            self.assertEqual(status['shutdown']['method'], 'SIGTERM')
            self.assertIn('binding changed', status['shutdown']['normalCloseError'])
            self.assertNotIn('windowquit', commands)

    def test_stopped_proof_presence_and_hash_do_not_claim_production_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); profile=root/'profile'; shared=root/'shared'
            profile.mkdir(); shared.mkdir(); epoch='22222222-2222-4222-8222-222222222222'
            (shared/'tandemlog-space.json').write_text(json.dumps({'epoch': epoch}))
            key=hashlib.sha256(f'{shared}#app5:{epoch}'.encode()).hexdigest()
            payload='synthetic opaque decoded payload'; proof=hashlib.sha256(payload.encode()).hexdigest()
            task=json.dumps({'generation':3,'native':True,'manifest':'a'*64,'revision':'b'*64,'digest':'c'*64})
            with closing(sqlite3.connect(profile/'local.sqlite')) as db, db:
                db.execute('CREATE TABLE profile_metadata(key TEXT PRIMARY KEY,value TEXT)')
                for name,value in [(f'app5.task.cache.{key}',task),(f'app5.decoded.proof.{key}',proof),
                                   (f'app5.decoded.payload.{key}',payload)]:
                    db.execute('INSERT INTO profile_metadata VALUES (?,?)',(name,value))
            before=(profile/'local.sqlite').read_bytes()
            observed=inspect_stopped_witness(profile,shared)
            self.assertTrue(observed['taskProofShapeValid'])
            self.assertTrue(observed['decodedPayloadHashMatches'])
            self.assertFalse(observed['productionReuseVerified'])
            self.assertEqual((profile/'local.sqlite').read_bytes(),before)



if __name__ == '__main__':
    unittest.main()
