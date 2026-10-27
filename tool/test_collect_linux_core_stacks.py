from pathlib import Path
import tempfile
import sys
import unittest
from collect_linux_core_stacks import core_metadata, owned_cores, stack_metadata


class CoreScopeTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux sparse core accounting')
    def test_large_sparse_address_space_keeps_disk_and_hash_reads_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            core = Path(temporary)/'core.123'
            with core.open('wb') as stream:
                stream.write(b'Synthetic core metadata')
                stream.seek(1024*1024*1024)
                stream.write(b'x')
            metadata = core_metadata(core)
            self.assertGreater(metadata['bytes'], 512*1024*1024)
            self.assertLess(metadata['allocatedBytes'], 512*1024*1024)
            self.assertEqual(metadata['hashReadBytes'], 64*1024)
            self.assertIsNone(metadata['sha256'])
            self.assertIn('whole sparse core not scanned', metadata['hashScope'])

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
