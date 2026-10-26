"""Early process failures retain evidence; readiness still requires the model."""
from pathlib import Path, PureWindowsPath
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

from measure_startup import launch, verify_loaded, inspect_stopped_witness, send_wm_delete_window, STARTUP_DEADLINE_SECONDS


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
    def test_normal_close_uses_exact_owned_pid_standard_protocol_without_focus_or_signal(self):
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
                else:
                    raise AssertionError('Unexpected manager/input command')
                return subprocess.CompletedProcess(args, 0, output, '')
            with patch('measure_startup.subprocess.run', side_effect=manager), patch(
                    'measure_startup.send_wm_delete_window', side_effect=lambda window: stop.write_text('close acknowledged')) as close:
                result = launch([sys.executable, '-c', program], root/'profile', root, 1,
                                close_mode='normal', xdotool='/synthetic/xdotool')
            self.assertTrue(result['shutdown']['normalExitVerified'])
            self.assertEqual(result['process_exit'], 0)
            self.assertFalse(result['shutdown']['globalFocusOrInput'])
            self.assertNotIn('forcedTerminationUsed', result['shutdown'])
            self.assertEqual([command[0] for command in commands], ['search','getwindowpid'])
            close.assert_called_once_with(4194305)

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

    def test_linux_ci_declares_owned_window_discovery_dependency(self):
        workflow = Path(__file__).resolve().parent.parent/'.github/workflows/validate.yml'
        install = next(line for line in workflow.read_text().splitlines()
                       if 'apt-get install -y' in line)
        self.assertIn('xdotool', install.split('apt-get install -y', 1)[1].split())

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Owned PID/UID window protocol is Linux-only')
    def test_missing_discovery_tool_retains_failure_and_forced_cleanup_not_clean_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); missing = root/'missing-xdotool'
            with self.assertRaisesRegex(RuntimeError, 'Normal owned window close was not verified'):
                launch([sys.executable, '-c',
                        'import time; print("TANDEMLOG_READY_MS=1 FILES_READ=1", flush=True); time.sleep(30)'],
                       root/'profile', root, 1, close_mode='normal', xdotool=missing)
            status = json.loads((root/'run-1.json').read_text())
            self.assertFalse(status['shutdown']['normalExitVerified'])
            self.assertFalse(status['cleanWitnessVerified'])
            self.assertEqual(status['shutdown']['method'], 'SIGTERM')
            self.assertIn('Normal close requires executable xdotool for owned-window discovery',
                          status['shutdown']['normalCloseError'])
            self.assertEqual(status['process_exit'], -15)

    def test_standard_x11_close_exact_event_support_and_error_paths(self):
        # Fake Xlib checks exact wire intent, not actual GTK acceptance.
        import ctypes as c
        from unittest.mock import Mock
        class Xlib:
            def __init__(self, supported=True, reject=False):
                self.atoms=(c.c_ulong*1)(202 if supported else 999)
                self.XOpenDisplay=Mock(return_value=123)
                self.XInternAtom=Mock(side_effect=lambda display,name,existing: 101 if name==b'WM_PROTOCOLS' else 202)
                def protocols(display,window,array,count):
                    c.cast(array,c.POINTER(c.POINTER(c.c_ulong)))[0]=c.cast(self.atoms,c.POINTER(c.c_ulong))
                    c.cast(count,c.POINTER(c.c_int))[0]=1
                    return 1
                self.XGetWMProtocols=Mock(side_effect=protocols)
                self.XFree=Mock(return_value=0)
                self.XSendEvent=Mock(return_value=0 if reject else 1)
                self.XSync=Mock(return_value=0)
                self.XCloseDisplay=Mock(return_value=0)
                self.XSetErrorHandler=Mock(return_value=None)
        lib=Xlib()
        with patch('ctypes.CDLL',return_value=lib):send_wm_delete_window(4194305)
        display,window,propagate,mask,event = lib.XSendEvent.call_args.args
        message=event._obj.xclient
        self.assertEqual((display,window,propagate,mask),(123,4194305,0,0))
        self.assertEqual((message.type,message.window,message.message_type,message.format),(33,4194305,101,32))
        self.assertEqual(list(message.data.l),[202,0,0,0,0])
        lib.XFree.assert_called_once();lib.XCloseDisplay.assert_called_once_with(123)
        self.assertEqual(lib.XSetErrorHandler.call_count,2)
        for supported,reject,error in [(False,False,'does not support WM_DELETE_WINDOW'),(True,True,'server refused')]:
            lib=Xlib(supported,reject)
            with patch('ctypes.CDLL',return_value=lib),self.assertRaisesRegex(RuntimeError,error):
                send_wm_delete_window(4194305)
            if not supported:lib.XSendEvent.assert_not_called()
            lib.XCloseDisplay.assert_called_once_with(123)
            self.assertEqual(lib.XSetErrorHandler.call_count,2)
        lib=Xlib();lib.XOpenDisplay.return_value=None
        with patch('ctypes.CDLL',return_value=lib),self.assertRaisesRegex(RuntimeError,'Cannot open'):
            send_wm_delete_window(4194305)
        lib.XSendEvent.assert_not_called()

    def test_stopped_proof_presence_and_hash_do_not_claim_production_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); profile=root/'profile'; shared=root/'shared'
            profile.mkdir(); shared.mkdir(); epoch='22222222-2222-4222-8222-222222222222'
            (shared/'tandemlog-space.json').write_text(json.dumps({'epoch': epoch}))
            key=hashlib.sha256(f'{shared}#app5:{epoch}'.encode()).hexdigest()
            decoded_key='app5.location.'+hashlib.sha256(str(shared).encode()).hexdigest()
            payload='synthetic opaque decoded payload'; proof=hashlib.sha256(payload.encode()).hexdigest()
            task=json.dumps({'generation':4,'native':True,'manifest':'a'*64,'revision':'b'*64,'digest':'c'*64})
            with closing(sqlite3.connect(profile/'local.sqlite')) as db, db:
                db.execute('CREATE TABLE profile_metadata(key TEXT PRIMARY KEY,value TEXT)')
                for name,value in [(f'app5.task.cache.{key}',task),(f'app5.decoded.proof.{decoded_key}',proof),
                                   (f'app5.decoded.payload.{decoded_key}',payload)]:
                    db.execute('INSERT INTO profile_metadata VALUES (?,?)',(name,value))
            before=(profile/'local.sqlite').read_bytes()
            observed=inspect_stopped_witness(profile,shared)
            self.assertTrue(observed['taskProofShapeValid'])
            self.assertTrue(observed['decodedPayloadHashMatches'])
            self.assertFalse(observed['productionReuseVerified'])
            self.assertEqual((profile/'local.sqlite').read_bytes(),before)




    def test_stopped_witness_hashes_explicit_location_verbatim(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); profile=root/'profile'; shared=root/'shared'
            profile.mkdir(); shared.mkdir(); epoch='22222222-2222-4222-8222-222222222222'
            (shared/'tandemlog-space.json').write_text(json.dumps({'epoch':epoch}))
            location=r'R:\synthetic\shared/data'
            self.assertNotEqual(str(PureWindowsPath(location)),location)
            key=hashlib.sha256(f'{location}#app5:{epoch}'.encode()).hexdigest()
            decoded_key='app5.location.'+hashlib.sha256(location.encode()).hexdigest()
            payload='opaque synthetic decoded payload'
            task=json.dumps({'generation':4,'native':True,'manifest':'a'*64,'revision':'b'*64,'digest':'c'*64})
            with closing(sqlite3.connect(profile/'local.sqlite')) as db,db:
                db.execute('CREATE TABLE profile_metadata(key TEXT PRIMARY KEY,value TEXT)')
                db.executemany('INSERT INTO profile_metadata VALUES (?,?)',[
                    (f'app5.task.cache.{key}',task),
                    (f'app5.decoded.proof.{decoded_key}',hashlib.sha256(payload.encode()).hexdigest()),
                    (f'app5.decoded.payload.{decoded_key}',payload)])
            before=(profile/'local.sqlite').read_bytes()
            normalized=inspect_stopped_witness(profile,shared)
            self.assertFalse(normalized['taskProofPresent'])
            self.assertFalse(normalized['decodedProofPresent'])
            normalized_spelling=inspect_stopped_witness(
                profile,shared,folder_location=str(PureWindowsPath(location)))
            self.assertFalse(normalized_spelling['taskProofPresent'])
            self.assertFalse(normalized_spelling['decodedProofPresent'])
            observed=inspect_stopped_witness(profile,shared,folder_location=location)
            self.assertTrue(observed['taskProofShapeValid'])
            self.assertTrue(observed['decodedPayloadHashMatches'])
            self.assertFalse(observed['productionReuseVerified'])
            self.assertEqual((profile/'local.sqlite').read_bytes(),before)

if __name__ == '__main__':
    unittest.main()
