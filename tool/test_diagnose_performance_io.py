import importlib.util
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

PATH = Path(__file__).parent / 'diagnose_performance_io.py'
SPEC = importlib.util.spec_from_file_location('io_diagnostic', PATH)
diag = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag)


class IoDiagnosticTests(unittest.TestCase):
    def test_measurement_cannot_be_acceptance_or_omit_growth_correctness(self):
        valid = {'measureOnly': True, 'costDiagnosticsEnabled': True,
                 'allPinsMatch': True, 'measurementCompleted': True,
                 'releaseGateAccepted': False, 'rerunsUsed': 0,
                 'attempts': [{'size': name, 'result': {'correctnessPassed': True}}
                              for name in ('dense-1', 'dense-2', 'dense-food')]}
        diag.validate_measurement(valid)
        for key in ('measureOnly', 'costDiagnosticsEnabled', 'allPinsMatch',
                    'measurementCompleted', 'releaseGateAccepted'):
            invalid = copy.deepcopy(valid)
            invalid[key] = not valid[key]
            with self.assertRaisesRegex(RuntimeError, 'sealed all-shape'):
                diag.validate_measurement(invalid)
        for field, value in (('size', 'dense-1'), ('result', {'correctnessPassed': False})):
            invalid = copy.deepcopy(valid)
            invalid['attempts'][2][field] = value
            with self.assertRaisesRegex(RuntimeError, 'sealed all-shape'):
                diag.validate_measurement(invalid)

    def test_resource_refusal_records_failure_without_starting_child(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'output'
            args = ['diagnostic']
            for name in ('repo', 'dart', 'native-library', 'sqlite-library'):
                args.extend(['--' + name, directory])
            args.extend(['--output', str(output)])
            with mock.patch.object(sys, 'argv', args), \
                 mock.patch.object(diag.run_gate, 'actual_resource_bounds', return_value={}), \
                 mock.patch.object(diag.run_gate, 'require_release_bounds', side_effect=RuntimeError('Wrong resource bounds')), \
                 mock.patch.object(diag, 'capture') as capture:
                self.assertEqual(diag.main(), 1)
                capture.assert_not_called()
            report = json.loads((output / 'io-result.json').read_text())
            self.assertFalse(report['releaseGateAccepted'])
            self.assertFalse(report['diagnosticComplete'])
            self.assertIn('Wrong resource bounds', report['error'])

    def test_parse_metadata_failure_overlap_and_incomplete_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'fsync.1').write_text(
                '1790000000.100000 fsync(8</tmp/synthetic/writer.applog>) = 0 <0.144235>\n'
                '1790000000.300000 fsync(9</tmp/synthetic/local.sqlite-wal>) = -1 EIO (Input/output error) <0.000400>\n'
                '+++ exited with 0 +++\n')
            (root / 'fsync.2').write_text(
                '1790000000.100010 fdatasync(3</tmp/dense-food-attempt-0/synthetic>) = 0 <0.002000>\n'
                '1790000000.400000 fsync(4 <unfinished ...>\n')
            r = diag.summarize(root)
            self.assertEqual((r['calls'], r['failedCalls'], r['unparsedSyscallLines']), (3, 1, 1))
            self.assertEqual(r['sumInclusiveElapsedUs'], 146635)
            self.assertEqual(r['longest'][0]['elapsedUs'], 144235)
            self.assertEqual(r['classes'], {'canonicalLog': 1, 'sqlite': 1, 'otherFileOrDirectory': 1})
            self.assertEqual(r['longestWorkloadOrReplay'][0]['elapsedUs'], 2000)
            self.assertIn('No exact action-sample', r['qualification'])

    def test_trace_bounds_and_symlinks_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'a').write_text('1234')
            with mock.patch.object(diag, 'TRACE_BYTES', 3):
                with self.assertRaisesRegex(RuntimeError, 'byte bound'):
                    diag.summarize(root)
            with mock.patch.object(diag, 'TRACE_FILES', 0):
                with self.assertRaisesRegex(RuntimeError, 'file-count bound'):
                    diag.summarize(root)
            if sys.platform.startswith('linux'):
                (root / 'link').symlink_to(root / 'a')
                with self.assertRaisesRegex(RuntimeError, 'regular owned'):
                    diag.summarize(root)

    def test_deadline_stops_owned_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traces = root / 'traces'
            traces.mkdir()
            r = diag.capture([sys.executable, '-c', 'import time; time.sleep(30)'],
                             root / 'capture.log', traces, seconds=.05)
            self.assertNotEqual(r['exitCode'], 0)
            self.assertIn('deadline', r['limitFailure'])
            self.assertFalse(Path('/proc', str(r['childPID'])).exists())

    def test_failed_command_preserves_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traces = root / 'traces'
            traces.mkdir()
            r = diag.capture([sys.executable, '-c', 'raise SystemExit(23)'],
                             root / 'capture.log', traces, seconds=5)
            self.assertEqual(r['exitCode'], 23)
            self.assertIsNone(r['limitFailure'])

    def test_trace_limit_stops_owned_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            traces = root / 'traces'
            traces.mkdir()
            (traces / 'large').write_text('1234')
            with mock.patch.object(diag, 'TRACE_BYTES', 3):
                r = diag.capture([sys.executable, '-c', 'import time; time.sleep(30)'],
                                 root / 'capture.log', traces, seconds=5)
            self.assertNotEqual(r['exitCode'], 0)
            self.assertIn('byte bound', r['limitFailure'])
            self.assertFalse(Path('/proc', str(r['childPID'])).exists())
