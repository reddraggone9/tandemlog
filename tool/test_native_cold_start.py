import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / 'performance'))
import native_cold_start as gate  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


def result(samples, clean=True, **overrides):
    budget = gate.read_budget(REPO)
    value = {'case': gate.CASE, 'budgetMs': budget['medianMs'], 'shape': budget['shape'],
             'strictFirstLaunch': {'processMs': 2900},
             'warmStarts': [{'processMs': ms, 'cleanWitnessVerified': clean} for ms in samples]}
    value.update(overrides)
    return budget, value


class NativeColdStartTest(unittest.TestCase):
    def test_committed_budget_is_lees_one_second_median(self):
        budget = gate.read_budget(REPO)
        self.assertEqual(budget['medianMs'], 1000)
        self.assertEqual(budget['shape'], {'tasks': 2000, 'warmStarts': 5})

    def test_first_list_reads_process_age(self):
        log = ('TANDEMLOG_READY_MS=1700 FILES_READ=3\n'
               'TANDEMLOG_FIRST_LIST at=2026-11-05T09:00:00.000 ms=1702 process_ms=2104 phases={"bound":1650}\n')
        self.assertEqual(gate.first_list(log), (1702, 2104))
        with self.assertRaises(gate.GateError):
            gate.first_list('TANDEMLOG_READY_MS=1700 FILES_READ=3\n')

    def test_median_is_recomputed_and_judged(self):
        budget, value = result([900, 1200, 950, 990, 2000], passed=True)
        decision = gate.judge(budget, value)
        self.assertEqual(decision['medianMs'], 990)
        self.assertTrue(decision['passed'])
        budget, value = result([2000, 2100, 1900, 1001, 999])
        decision = gate.judge(budget, value)
        self.assertEqual(decision['medianMs'], 1900)
        self.assertFalse(decision['passed'])

    def test_refuses_unsealed_starts_other_shapes_and_short_runs(self):
        with self.assertRaises(gate.GateError):
            gate.judge(*result([500] * 5, clean=False))
        with self.assertRaises(gate.GateError):
            gate.judge(*result([500] * 4))
        budget, value = result([500] * 5)
        value['shape'] = {'tasks': 10, 'warmStarts': 5}
        with self.assertRaises(gate.GateError):
            gate.judge(budget, value)
        budget, value = result([500] * 5, budgetMs=5000)
        with self.assertRaises(gate.GateError):
            gate.judge(budget, value)

    def test_verify_fails_without_a_result_or_source_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(gate.GateError):
                gate.verify(REPO, Path(tmp) / 'missing.json')
            file = Path(tmp) / 'result.json'
            file.write_text(json.dumps(result([500] * 5)[1]))
            with self.assertRaises(gate.GateError):
                gate.verify(REPO, file)


if __name__ == '__main__':
    unittest.main()
