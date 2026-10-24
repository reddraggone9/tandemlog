from pathlib import Path
import tempfile
import unittest
from collect_linux_core_stacks import owned_cores, stack_metadata


class CoreScopeTests(unittest.TestCase):
    def test_missing_or_invalid_core_cannot_claim_a_native_stack(self):
        self.assertFalse(stack_metadata('not a core dump\n#0 unrelated')['stackCaptured'])
        self.assertFalse(stack_metadata('Program terminated with signal SIGSEGV.\nNo stack.')['stackCaptured'])
        self.assertEqual(stack_metadata('Program terminated with signal SIGSEGV.\n#0  0x123 in crash ()'),
                         {'nativeSignal': 'SIGSEGV', 'stackCaptured': True})

    def test_only_two_regular_pid_named_cores_are_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(owned_cores(root, {123, 124, 125}), [])
            first = root/'core.123'
            first.write_bytes(b'public synthetic stand-in')
            self.assertEqual(owned_cores(root, {123}), [first])
            with self.assertRaisesRegex(RuntimeError, 'not certified'):
                owned_cores(root, {124})
            bad = root/'unexpected'
            bad.write_bytes(b'not a core')
            with self.assertRaisesRegex(RuntimeError, 'Unexpected'):
                owned_cores(root, {123, 124, 125})
            bad.unlink()
            (root/'core.124').write_bytes(b'next')
            (root/'core.125').write_bytes(b'excess')
            with self.assertRaisesRegex(RuntimeError, 'At most two'):
                owned_cores(root, {123, 124, 125})


if __name__ == '__main__':
    unittest.main()
