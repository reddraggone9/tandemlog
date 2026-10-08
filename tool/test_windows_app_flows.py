import tempfile
import hashlib
import io
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

import windows_app_flows
from windows_app_flows import SCOPES, command, configure_console, hashes, library_environment, result


class WindowsAppFlowReceipts(unittest.TestCase):
    def test_utf8_command_log_can_print_through_initial_cp1252_console(self):
        raw = '[√] Windows toolchain ready\n[!] Android toolchain missing\n'.encode('utf-8')
        console_bytes = io.BytesIO()
        console = io.TextIOWrapper(console_bytes, encoding='cp1252', errors='strict')
        def start(_args, **kwargs):
            kwargs['stdout'].write(raw)
            return Mock(wait=Mock(return_value=0))
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / 'doctor.txt'
            with patch.object(windows_app_flows.sys, 'stdout', console), \
                 patch.object(windows_app_flows.subprocess, 'Popen', side_effect=start):
                configure_console()
                code, _ = command(['fake-flutter', 'doctor', '-v'], log, {}, timeout=60)
            self.assertEqual(code, 0)
            self.assertEqual(log.read_bytes(), raw)
            self.assertIn('[√] Windows toolchain ready', console_bytes.getvalue().decode('utf-8'))
        console.detach()

    def test_unicode_error_reporting_handles_initial_cp1252_stderr(self):
        error_bytes = io.BytesIO()
        errors = io.TextIOWrapper(error_bytes, encoding='cp1252', errors='strict')
        with patch.object(windows_app_flows.sys, 'stderr', errors):
            configure_console()
            print('Synthetic diagnostic path: résumé/√.txt', file=windows_app_flows.sys.stderr, flush=True)
        self.assertEqual(error_bytes.getvalue().decode('utf-8'), 'Synthetic diagnostic path: résumé/√.txt\n')
        errors.detach()

    def test_console_configuration_accepts_unicode_stringio_captures(self):
        console, errors = io.StringIO(), io.StringIO()
        with patch.object(windows_app_flows.sys, 'stdout', console), \
             patch.object(windows_app_flows.sys, 'stderr', errors):
            configure_console()
            print('√', flush=True)
            print('√', file=windows_app_flows.sys.stderr, flush=True)
        self.assertEqual(console.getvalue(), '√\n')
        self.assertEqual(errors.getvalue(), '√\n')

    def test_exact_scope_counts(self):
        self.assertEqual([scope[1] for scope in SCOPES], [3, 2, 7, 4, 2, 3, 1])
        self.assertEqual(sum(scope[1] for scope in SCOPES), 22)
        self.assertEqual(len({scope[0] for scope in SCOPES}), 7)
        self.assertEqual(SCOPES[-1][2], (
            '--plain-name', 'workspace search preserves filters drafts and completion sections',
        ))

    def test_no_false_pass_on_zero_skipped_failed_or_incomplete_output(self):
        success = ('TANDEMLOG_FIRST_FRAME_MS=445\nTANDEMLOG_READY_MS=1121 FILES_READ=1\n'
                   '\x1b[32m00:19 +2: (tearDownAll)\x1b[0m\r00:19 +2: All tests passed!\n')
        self.assertTrue(result(success, 2, 0)['passed'])
        for text, expected, code in (
            (success, 7, 0), (success, 2, 1),
            ('00:01 +0: All tests passed!', 2, 0),
            ('00:01 +2 ~1: All tests passed!', 2, 0),
            ('00:01 +2 -1: All tests passed!', 2, 0),
            ('00:01 +2: Native window could not start', 2, 0),
            ('Unable to find a Windows desktop device', 2, 1),
        ):
            with self.subTest(text=text, expected=expected, code=code):
                self.assertFalse(result(text, expected, code)['passed'])

    def test_native_app_startup_cannot_be_replaced_by_a_success_banner(self):
        banner = '00:19 +2: All tests passed!\n'
        for ready in ('TANDEMLOG_READY_MS=120 FILES_READ=1\n',
                      'TANDEMLOG_ONBOARDING_READY_MS=120\n'):
            self.assertTrue(result('TANDEMLOG_FIRST_FRAME_MS=5\n' + ready + banner, 2, 0)['passed'])
        for markers in ('', 'TANDEMLOG_FIRST_FRAME_MS=5\n', 'TANDEMLOG_READY_MS=120\n',
                        'TANDEMLOG_FIRST_FRAME_MS=wrong\nTANDEMLOG_READY_MS=120\n',
                        'TANDEMLOG_FIRST_FRAME_MS=5\nTANDEMLOG_READY_MS=wrong\n'):
            with self.subTest(markers=markers):
                self.assertFalse(result(markers + banner, 2, 0)['passed'])

    def test_hashes_require_native_app_and_do_not_collect_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = root / 'Debug'
            bundle.mkdir()
            (root / 'synthetic-profile.json').write_text('private fixture settings')
            required = ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                        'data/icudtl.dat', 'data/flutter_assets/kernel_blob.bin')
            for name in required:
                with self.assertRaisesRegex(ValueError, 'Missing debug payload'):
                    hashes(bundle)
                (bundle / name).parent.mkdir(parents=True, exist_ok=True)
                (bundle / name).write_bytes(name.encode())
            collected = hashes(bundle)
            self.assertEqual(set(collected), set(required))
            self.assertTrue(all(len(item['sha256']) == 64 for item in collected.values()))

    def test_library_variable_hash_is_recorded_without_claiming_app_override(self):
        self.assertEqual(library_environment({}), {'value': None, 'used_by_app_entrypoints': False})
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'explicit.dll'
            entry = library_environment({'TANDEMLOG_TEXT_LIBRARY': str(path)})
            self.assertIn('read_error', entry)
            path.write_bytes(b'Native override fixture')
            entry = library_environment({'TANDEMLOG_TEXT_LIBRARY': str(path)})
            self.assertEqual(entry['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(entry['bytes'], path.stat().st_size)
            self.assertFalse(entry['used_by_app_entrypoints'])

    def test_zero_byte_runtime_payload_cannot_pass_presence_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            bundle = Path(temporary)
            required = ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                        'data/icudtl.dat', 'data/flutter_assets/kernel_blob.bin')
            for name in required:
                path = bundle / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'Nonempty runtime fixture')
            for name in required:
                with self.subTest(name=name):
                    path = bundle / name
                    original = path.read_bytes()
                    path.write_bytes(b'')
                    try:
                        with self.assertRaisesRegex(ValueError, 'Empty debug payload'):
                            hashes(bundle)
                    finally:
                        path.write_bytes(original)


if __name__ == '__main__':
    unittest.main()
