import unittest
from diagnose_linux_close import inferior_pid, outcome


class NativeCloseDiagnosticsTests(unittest.TestCase):
    def test_inferior_identity_requires_single_explicit_positive_marker(self):
        self.assertEqual(inferior_pid('noise\nTANDEMLOG_GDB_PID=123\n'), 123)
        for text in ['', 'TANDEMLOG_GDB_PID=0\n',
                     'TANDEMLOG_GDB_PID=12\nTANDEMLOG_GDB_PID=13\n']:
            with self.assertRaises(RuntimeError):
                inferior_pid(text)

    def test_native_crash_cannot_be_hidden_by_normal_marker(self):
        normal = '[Inferior 1 (process 123) exited normally]'
        self.assertEqual(outcome(normal), 'normal-exit')
        self.assertEqual(outcome('exited with code 01'), 'unverified')
        for name in ['SEGV', 'ABRT', 'BUS', 'ILL', 'FPE']:
            self.assertEqual(outcome(normal+'\nThread 1 received signal SIG'+name),
                             'native-crash')


if __name__ == '__main__':
    unittest.main()
