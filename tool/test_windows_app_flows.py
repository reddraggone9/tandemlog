import tempfile
from pathlib import Path
import unittest

from windows_app_flows import SCOPES, hashes, result


class WindowsAppFlowReceipts(unittest.TestCase):
    def test_exact_scope_counts(self):
        self.assertEqual([scope[1] for scope in SCOPES], [2, 7, 4, 2, 3, 1])
        self.assertEqual(sum(scope[1] for scope in SCOPES), 19)
        self.assertEqual(len({scope[0] for scope in SCOPES}), 6)
        self.assertEqual(SCOPES[-1][2], (
            '--plain-name', 'workspace search preserves filters drafts and completion sections',
        ))

    def test_no_false_pass_on_zero_skipped_failed_or_incomplete_output(self):
        success = '\x1b[32m00:19 +2: (tearDownAll)\x1b[0m\r00:19 +2: All tests passed!\n'
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

    def test_hashes_require_native_app_and_do_not_collect_profiles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = root / 'Debug'
            bundle.mkdir()
            (root / 'synthetic-profile.json').write_text('private fixture settings')
            for name in ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll'):
                with self.assertRaisesRegex(ValueError, 'Missing debug payload'):
                    hashes(bundle)
                (bundle / name).write_bytes(name.encode())
            collected = hashes(bundle)
            self.assertEqual(set(collected), {'tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll'})
            self.assertTrue(all(len(item['sha256']) == 64 for item in collected.values()))


if __name__ == '__main__':
    unittest.main()
