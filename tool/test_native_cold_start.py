import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / 'performance'))
import native_cold_start as gate  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


FOOD = {'activeContainers': 522, 'groups': 483, 'products': 551, 'purchases': 34}


def result(samples, clean=True, food=FOOD, **overrides):
    budget = gate.read_budget(REPO)
    value = {'case': gate.CASE, 'budgetMs': budget['medianMs'], 'shape': budget['shape'],
             'fixture': {'workload': 'mixed-v2', 'food': FOOD},
             'strictFirstLaunch': {'processMs': 2900, 'food': FOOD},
             'warmStarts': [{'processMs': ms, 'cleanWitnessVerified': clean, 'food': food} for ms in samples]}
    value.update(overrides)
    return budget, value


class NativeColdStartTest(unittest.TestCase):
    def test_committed_budget_is_lees_one_second_median(self):
        budget = gate.read_budget(REPO)
        self.assertEqual(budget['medianMs'], 1000)
        self.assertEqual(budget['shape']['tasks'], 2000)
        self.assertEqual(budget['shape']['warmStarts'], 5)

    def test_budget_shape_requires_mixed_food_history(self):
        budget = gate.read_budget(REPO)
        history = budget['shape']['history']
        self.assertGreaterEqual(history['peers'], 1)
        self.assertGreater(history['foodAdds'], 0)
        with tempfile.TemporaryDirectory() as tmp:
            for shape in ({'tasks': 2000, 'warmStarts': 5},
                          {**budget['shape'], 'history': {**history, 'foodAdds': 0}},
                          {**budget['shape'], 'history': {**history, 'peers': 0}}):
                (Path(tmp) / 'tool/performance').mkdir(parents=True, exist_ok=True)
                (Path(tmp) / gate.BUDGET).write_text(json.dumps({**budget, 'shape': shape}))
                with self.assertRaises(gate.GateError):
                    gate.read_budget(tmp)

    def test_food_line_is_read_once_and_must_match_fixture(self):
        log = ('TANDEMLOG_FIRST_LIST at=x ms=1 process_ms=2 phases={}\n'
               'TANDEMLOG_FOOD {"activeContainers":522,"groups":483,"products":551,"purchases":34}\n')
        self.assertEqual(gate.food_loaded(log), FOOD)
        with self.assertRaises(gate.GateError):
            gate.food_loaded('TANDEMLOG_FIRST_LIST at=x ms=1 process_ms=2 phases={}\n')
        with self.assertRaises(gate.GateError):
            gate.judge(*result([500] * 5, food={**FOOD, 'activeContainers': 0}))
        budget, value = result([500] * 5)
        value['fixture'] = {'workload': 'mixed-v2', 'food': {**FOOD, 'purchases': 0}}
        with self.assertRaises(gate.GateError):
            gate.judge(budget, value)
        budget, value = result([500] * 5)
        del value['fixture']['workload']
        with self.assertRaises(gate.GateError):
            gate.judge(budget, value)

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

    def test_verify_uses_registered_host_schema_without_unpinning_hardware(self):
        host = gate.profile(REPO)
        actual = {**host['environment'], 'kernel': 'recorded-kernel', 'python': 'recorded-python'}
        _, value = result([500] * 5, relevantSource={}, sourceRevision='synthetic',
                          hostProfileSHA256=gate.digest(REPO / gate.PROFILE), host=actual)
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(gate, 'recorded_identity', return_value=({}, {})):
            file = Path(tmp) / 'result.json'
            file.write_text(json.dumps(value))
            self.assertTrue(gate.verify(REPO, file)['passed'])
            for changed in ({**actual, 'cpuModel': 'other'},
                            {k: v for k, v in actual.items() if k != 'kernel'}):
                file.write_text(json.dumps({**value, 'host': changed}))
                with self.assertRaises((gate.GateError, ValueError)):
                    gate.verify(REPO, file)
            file.write_text(json.dumps(value))
            v1 = {**host, 'schemaVersion': 1, 'environment': {**actual, 'kernel': 'pinned-kernel'}}
            with patch.object(gate, 'profile', return_value=v1):
                with self.assertRaises((gate.GateError, ValueError)):
                    gate.verify(REPO, file)

    def test_verify_refuses_a_result_for_other_source(self):
        committed = json.loads((REPO / gate.RESULT).read_text())
        files = committed['relevantSource']['files']
        name = sorted(files)[0]
        committed['relevantSource']['files'] = {**files, name: '0' * 64}
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'result.json'
            file.write_text(json.dumps(committed))
            with self.assertRaises((gate.GateError, ValueError)):
                gate.verify(REPO, file)


if __name__ == '__main__':
    unittest.main()
