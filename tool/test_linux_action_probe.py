import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).parent/'performance/run_linux_action_probe.py'
SPEC = importlib.util.spec_from_file_location('linux_action_probe', MODULE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ActionProbeTests(unittest.TestCase):
    def test_source_pins_reject_mutation_and_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root/'source'
            source.mkdir()
            file = source/'owned'
            file.write_text('source')
            pins = {'owned': probe.sha(file)}
            probe.verify_source(source, pins)
            file.write_text('changed')
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                probe.verify_source(source, pins)
            (root/'outside').write_text('outside')
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                probe.verify_source(source, {'../outside': probe.sha(root/'outside')})

    def test_missing_actions_and_incomplete_intervals_never_pass(self):
        rows = [{'phase': 'action', 'name': name, 'frameworkPostFrameUs': 9,
                 'costs': {'complete': True, 'reconciled': True, 'coverageSumUs': 9}}
                for name in probe.EXPECTED_ACTIONS]
        self.assertEqual(probe.action_proof(rows)[1:], (True, True))
        self.assertEqual(probe.action_proof(rows[:-1])[1], False)
        invalid = json.loads(json.dumps(rows))
        invalid[0]['costs']['complete'] = False
        self.assertEqual(probe.action_proof(invalid)[2], False)
        invalid[0]['costs'].update(complete=True, coverageSumUs=8)
        self.assertEqual(probe.action_proof(invalid)[2], False)
        del invalid[0]['costs']
        self.assertEqual(probe.action_proof(invalid)[2], False)


if __name__ == '__main__':
    unittest.main()
