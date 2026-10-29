"""Disk-stall resample rule (Lee 2026-10-28). All reports and logs here are synthetic."""
import copy
import json
import shutil
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent / 'performance'
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import disk_stall
import gate_policy
import reference_receipt as receipt
import run_gate
import test_borderline_performance as borderline_tests
import test_reference_performance as reference_tests
from test_reference_performance import ReceiptFixture, write

LABEL = 'food.product.merge.undo'
FAMILY = 'food-products'
# The RC.2 q1 miss: 25.494 ms against the 20 ms maximum, 17.573 ms of it durable append, 7.483 ms CPU.
STALL = {'wall': 25494, 'append': 17573, 'cpu': 7483}
# Ordinary label samples near q1's: the dense-1 maximum sets the growth maximum bound to 8*1.4+5 = 16.2 ms.
ORDINARY = 8000


def ordinary(action):
    return ORDINARY if action == LABEL else 1000


def log_lines(rows, overrides=None, complete=True, label=LABEL, fixture=None):
    """Benchmark-shaped log: every row carries its family and append/CPU diagnostics."""
    overrides = overrides or {}
    lines = []
    for row in rows:
        numbers = overrides.get((row['action'], row['index']), {})
        lines.append({'measurement': 'broad-action', 'family': FAMILY if row['action'] == label else 'other',
                      'action': row['action'], 'index': row['index'], 'warmup': row['warmup'],
                      'microseconds': row['microseconds'],
                      'diagnostics': {'appendCalls': 1, 'appendMicroseconds': numbers.get('append', 400),
                                      'resourcesAvailable': True,
                                      'resourceDeltas': {'cgroup.usage_usec': numbers.get('cpu', 600),
                                                         'cgroup.throttled_usec': 0}}})
    if complete:
        lines.append({'measurement': 'broad-all-pass', **{k: (fixture or {}).get(k) for k in disk_stall.FIXTURE_KEYS}})
    return ''.join(json.dumps(line) + '\n' for line in lines).encode()


class Synthetic:
    """Three passing sizes at 1 ms with one label sample overridden."""

    def __init__(self):
        self.limits = json.loads((TOOLS / 'limits-v1.json').read_text())
        self.limits['sha256'] = receipt.digest(TOOLS / 'limits-v1.json')
        self.specs = run_gate.scaling_specs(self.limits)
        self.contracts = json.loads((TOOLS.parents[1] / 'evidence/rc4-cloud-attribution-20261024/'
                                     'reference-034a57d-pins.json').read_text())['fixtures']
        self.results = {size: {'size': size, 'correctnessPassed': True, 'limitsSHA256': self.limits['sha256'],
                               'observations': [{'action': a, 'index': i, 'warmup': i < 2, 'microseconds': ordinary(a)}
                                                for a in self.limits['actionsBySize'][size] for i in range(7)]}
                        for size in self.limits['actionsBySize']}
        self.diagnostics = {size: {} for size in self.results}

    def stall(self, size='dense-food', index=5, wall=STALL['wall'], append=STALL['append'], cpu=STALL['cpu']):
        for row in self.results[size]['observations']:
            if row['action'] == LABEL and row['index'] == index:
                row['microseconds'] = wall
        self.diagnostics[size][LABEL, index] = {
            'family': FAMILY, 'resourcesAvailable': True, 'appendCalls': 1, 'appendMicroseconds': append,
            'cpuMicroseconds': cpu, 'throttledMicroseconds': 0}
        return self

    def plan(self, already=()):
        return disk_stall.plan(self.results, self.diagnostics, self.limits, self.specs, self.contracts, already)

    def replacement(self, wall=ORDINARY):
        return [{'action': LABEL, 'index': i, 'warmup': i < 2, 'microseconds': ORDINARY if i != 5 else wall}
                for i in range(7)]

    def effective(self, planned, rows):
        effective = disk_stall.apply(self.results, planned, rows, self.limits)
        return disk_stall.evaluate_all(effective, self.limits, self.specs, self.contracts)


def failures(absolute, paired):
    return sorted([s + ':' + f for s, d in absolute.items() for f in d.failures] +
                  [n + ':' + f for n, d in paired.items() for f in d.failures])


class DiskStallPolicyTests(unittest.TestCase):
    def test_stall_attributed_miss_is_resampled_once_and_a_clean_resample_passes(self):
        case = Synthetic().stall()
        planned, unattributed = case.plan()
        self.assertEqual(unattributed, [])
        self.assertEqual(len(planned), 1)
        item = planned[0]
        self.assertEqual((item['size'], item['action'], item['family']), ('dense-food', LABEL, FAMILY))
        self.assertEqual({m['label'] for m in item['missed']},
                         {'dense-food:' + LABEL, 'food-own-history:scaling:' + LABEL})
        self.assertEqual(item['samples'], [{'index': 5, 'family': FAMILY, 'wallMicroseconds': 25494,
                                            'resourcesAvailable': True, 'appendCalls': 1,
                                            'appendMicroseconds': 17573, 'cpuMicroseconds': 7483,
                                            'throttledMicroseconds': 0, 'withoutAppendMicroseconds': 7921}])
        self.assertEqual(failures(*case.effective(planned, [case.replacement()])), [])
        # Budgets are read, never changed.
        self.assertEqual(case.limits['actionsBySize']['dense-food'][LABEL], {'medianMs': 15, 'maxMs': 20})

    def test_cpu_attributed_miss_is_an_ordinary_failure(self):
        case = Synthetic().stall(cpu=21000)
        planned, unattributed = case.plan()
        self.assertEqual(planned, [])
        self.assertIn('dense-food:' + LABEL, unattributed)

    def test_cpu_must_fit_the_tightest_missed_bound(self):
        # 18 ms CPU fits the 20 ms absolute maximum but not the 16.2 ms growth maximum.
        case = Synthetic().stall(cpu=18000)
        self.assertEqual(case.plan()[0], [])

    def test_append_that_does_not_account_for_the_overrun_follows_existing_rules(self):
        for append in (5000, 0, None):
            with self.subTest(append=append):
                case = Synthetic().stall(append=append)
                planned, unattributed = case.plan()
                self.assertEqual(planned, [])
                self.assertTrue(unattributed)

    def test_missing_or_unavailable_diagnostics_are_not_attributed(self):
        case = Synthetic().stall()
        case.diagnostics['dense-food'][LABEL, 5]['resourcesAvailable'] = False
        self.assertEqual(case.plan()[0], [])
        case = Synthetic().stall()
        del case.diagnostics['dense-food'][LABEL, 5]
        self.assertEqual(case.plan()[0], [])

    def test_every_sample_over_the_bound_must_be_attributed(self):
        case = Synthetic().stall(index=5).stall(index=6, cpu=25000)
        self.assertEqual(case.plan()[0], [])
        both = Synthetic().stall(index=5).stall(index=6)
        planned, _ = both.plan()
        self.assertEqual([s['index'] for s in planned[0]['samples']], [5, 6])

    def test_any_unattributed_label_means_no_resample(self):
        case = Synthetic().stall()
        for row in case.results['dense-1']['observations']:
            if row['action'] == 'task.title.save' and row['index'] == 4:
                row['microseconds'] = 90000
        planned, unattributed = case.plan()
        self.assertEqual(planned, [])
        self.assertIn('dense-1:task.title.save', unattributed)

    def test_a_resample_that_misses_again_is_an_ordinary_failure_and_never_resampled_again(self):
        case = Synthetic().stall()
        planned, _ = case.plan()
        self.assertIn('dense-food:' + LABEL, failures(*case.effective(planned, [case.replacement(wall=24000)])))
        self.assertEqual(case.plan(already=[['dense-food', LABEL]]), ([], ['dense-food:' + LABEL,
                                                                          'food-own-history:scaling:' + LABEL]))

    def test_resample_must_replace_the_whole_label(self):
        case = Synthetic().stall()
        planned, _ = case.plan()
        for rows in ([], case.replacement()[:6], [dict(r, action='other') for r in case.replacement()]):
            with self.subTest(rows=len(rows)):
                with self.assertRaises(ValueError):
                    case.effective(planned, [rows])
        with self.assertRaises(ValueError):
            case.effective(planned, [])

    def test_passing_attempt_needs_no_resample(self):
        self.assertEqual(Synthetic().plan(), ([], []))


@unittest.skipUnless(sys.platform.startswith('linux'), 'Synthetic orchestration exercises the Linux-only AOT runner')
class ReferenceRunnerTests(unittest.TestCase):
    """run_gate.main in enforcing reference mode with synthetic children and logs."""

    def run_reference(self, stall, resample_wall=ORDINARY):
        fixture = reference_tests.ReferenceReceiptTests(methodName='test_fresh_complete_source_bound_receipt_passes')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        repo, tools = fixture.repo, fixture.tools
        for name in ('limits-v1.json', 'coverage-v1.json'):
            (tools / name).write_bytes((TOOLS / name).read_bytes())
        write(repo / '.dart_tool/package_config.json', {'configVersion': 2, 'packages': [
            {'name': 'tandemlog', 'rootUri': repo.as_uri() + '/', 'packageUri': 'lib/', 'languageVersion': '3.13'}]})
        sdk = repo / 'sdk/bin/cache/dart-sdk'
        for name in ('bin/dart', 'bin/utils/gen_snapshot', 'lib/_internal/vm_platform_strong.dill'):
            path = sdk / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'synthetic tool input')
        for name in ('native.so', 'sqlite.so'):
            (repo / name).write_bytes(b'synthetic library input')
        request = repo / 'request.json'
        write(request, fixture.request)
        output = repo / 'reference-output'
        command = ['run_gate.py', '--repo', str(repo), '--dart', str(sdk / 'bin/dart'),
                   '--native-library', str(repo / 'native.so'), '--sqlite-library', str(repo / 'sqlite.so'),
                   '--output', str(output), '--expected-limits-sha256', receipt.digest(tools / 'limits-v1.json'),
                   '--reference-request', str(request)]
        measured = {a['size']: copy.deepcopy(a['result']['observations']) for a in fixture.report['attempts']}
        for rows in measured.values():
            for row in rows:
                row['microseconds'] = ordinary(row['action'])
        overrides = {}
        if stall:
            for row in measured['dense-food']:
                if row['action'] == LABEL and row['index'] == 5:
                    row['microseconds'] = STALL['wall']
            overrides[LABEL, 5] = stall
        calls = []

        def child(args, log, env, timeout):
            calls.append(args[1])
            if args[1] == 'compile':
                (output / 'benchmark').write_bytes(b'synthetic executable marker')
                log.write_bytes(b'synthetic compile\n')
            elif args[1] == 'generate':
                folder = Path(args[2]); size = folder.name.removeprefix('fixture-')
                contract = copy.deepcopy(fixture.report['fixtures'][size]['contract'])
                workspace = folder / 'workspace'; workspace.mkdir(parents=True)
                (workspace / 'test.applog').write_bytes(b'synthetic fixture marker')
                contract.update(workspace=str(workspace), files={'test.applog': receipt.digest(workspace / 'test.applog')})
                write(folder / 'fixture.json', contract)
                log.write_bytes(b'synthetic generation\n')
            elif args[1] == 'run':
                size = Path(args[2]).name.split('-attempt-')[0]
                log.write_bytes(log_lines(measured[size], overrides if size == 'dense-food' else None))
            else:
                self.assertEqual(args[1:2] + args[-1:], ['resample', FAMILY])
                rows = [{'action': LABEL, 'index': i, 'warmup': i < 2,
                         'microseconds': ORDINARY if i != 5 else resample_wall} for i in range(7)]
                contract = json.loads(Path(args[4]).read_text())
                log.write_bytes(log_lines(rows, fixture=contract))
            return {'exitCode': 0, 'childAbsent': True, 'childGroupAbsent': True,
                    'logSHA256': receipt.digest(log), 'noise': {}}

        context = {'requestId': fixture.request['requestId'], 'synthetic': True}
        with patch.object(sys, 'argv', command), patch.object(run_gate, '__file__', str(tools / 'run_gate.py')), \
                patch.object(run_gate, 'run_child', side_effect=child), \
                patch.object(run_gate, 'request_context', return_value=context), \
                patch.object(run_gate, 'check_reference_toolchain'), \
                patch.object(run_gate, 'reference_profile'), \
                patch.object(run_gate, 'actual_resource_bounds', return_value=fixture.bounds):
            status = run_gate.main()
        return status, json.loads((output / 'gate-result.json').read_text()), calls

    def test_stall_attributed_miss_resamples_once_and_passes_with_numbers_recorded(self):
        status, report, calls = self.run_reference({'append': STALL['append'], 'cpu': STALL['cpu']})
        self.assertEqual(status, 0, report.get('error'))
        self.assertTrue(report['releaseGateAccepted'])
        self.assertTrue(report['timingLimitsPassed'])
        self.assertEqual(report['rerunsUsed'], 0)
        self.assertEqual(calls.count('resample'), 1)
        [record] = report['diskStallResamples']
        [item] = record['resamples']
        self.assertEqual(item['samples'][0]['appendMicroseconds'], 17573)
        self.assertEqual(item['samples'][0]['cpuMicroseconds'], 7483)
        self.assertEqual(item['samples'][0]['withoutAppendMicroseconds'], 7921)
        # Original samples and their failure stay in the receipt.
        food = next(a for a in report['attempts'] if a['size'] == 'dense-food')
        self.assertEqual(food['failures'], [LABEL])
        self.assertEqual(record['absolute']['dense-food']['failures'], [])

    def test_cpu_attributed_miss_fails_without_resample(self):
        status, report, calls = self.run_reference({'append': STALL['append'], 'cpu': 21000})
        self.assertEqual(status, 1)
        self.assertEqual(report['error'], receipt.TIMING_FAILURE)
        self.assertNotIn('resample', calls)
        self.assertEqual(report['diskStallResamples'], [])

    def test_second_miss_is_an_ordinary_failure(self):
        status, report, calls = self.run_reference({'append': STALL['append'], 'cpu': STALL['cpu']}, resample_wall=24000)
        self.assertEqual(status, 1)
        self.assertEqual(report['error'], receipt.TIMING_FAILURE)
        self.assertEqual(calls.count('resample'), 1)
        self.assertFalse(report['releaseGateAccepted'])
        self.assertIn(LABEL, report['diskStallResamples'][0]['absolute']['dense-food']['failures'])

    def test_unattributed_miss_follows_existing_rules(self):
        status, report, calls = self.run_reference({'append': 1000, 'cpu': STALL['cpu']})
        self.assertEqual(status, 1)
        self.assertEqual(report['error'], receipt.TIMING_FAILURE)
        self.assertNotIn('resample', calls)
        self.assertEqual(report['rerunsUsed'], 0)

    def test_passing_reference_run_takes_no_resample(self):
        status, report, calls = self.run_reference(None)
        self.assertEqual(status, 0, report.get('error'))
        self.assertNotIn('resample', calls)
        self.assertEqual(report['diskStallResamples'], [])


class DiskStallReceiptTests(ReceiptFixture):
    def stall_receipt(self, cpu=STALL['cpu'], resample_wall=ORDINARY):
        case = Synthetic().stall(cpu=cpu)
        case.limits['sha256'] = self.host['limitsSHA256']
        for attempt in self.report['attempts']:
            attempt['result']['observations'] = case.results[attempt['size']]['observations']
            decision = gate_policy.evaluate(attempt['result'], case.limits)
            attempt.update(status=decision.status, failures=list(decision.failures), summaries=decision.summaries)
            log = self.bundle / (attempt['size'] + '-attempt-0.log')
            log.write_bytes(log_lines(attempt['result']['observations'],
                                      {(LABEL, 5): {'append': STALL['append'], 'cpu': cpu}}
                                      if attempt['size'] == 'dense-food' else None))
            attempt['execution'] = dict(attempt['execution'], logSHA256=receipt.digest(log))
        food = next(a for a in self.report['attempts'] if a['size'] == 'dense-food')
        summaries = {a['size']: a['summaries'] for a in self.report['attempts']}
        contracts = {s: v['contract'] for s, v in self.report['fixtures'].items()}
        for pair in self.report['pairedScalingAttempts']:
            d = gate_policy.evaluate_scaling(summaries, case.specs[pair['comparison']], contracts)
            pair.update(status=d.status, failures=list(d.failures), comparisons=d.summaries)
        originals = {a['size']: a['result'] for a in self.report['attempts']}
        diagnostics = {s: disk_stall.action_diagnostics(self.bundle / (s + '-attempt-0.log')) for s in originals}
        planned, _ = disk_stall.plan(originals, diagnostics, case.limits, case.specs, contracts)
        if not planned:  # A forged claim: record what the rule would have refused.
            planned = [{'policy': disk_stall.POLICY, 'size': 'dense-food', 'action': LABEL, 'family': FAMILY,
                        'missed': [], 'samples': []}]
        rows = case.replacement(wall=resample_wall)
        (self.bundle / 'disk-stall-resample-0-0.log').write_bytes(
            log_lines(rows, fixture=self.report['fixtures']['dense-food']['contract']))
        effective = disk_stall.apply(originals, planned, [rows], case.limits)
        absolute, pairs = disk_stall.evaluate_all(effective, case.limits, case.specs, contracts)
        self.report['diskStallResamples'] = [{
            'attempt': 0, 'policy': disk_stall.POLICY, 'resamples': planned, 'replacements': [rows],
            'fixtures': [self.report['fixtures']['dense-food']['manifestSHA256']],
            'executions': [{'exitCode': 0, 'childAbsent': True, 'childGroupAbsent': True, 'noise': {},
                            'logSHA256': receipt.digest(self.bundle / 'disk-stall-resample-0-0.log')}],
            'absolute': {s: {'status': d.status, 'failures': list(d.failures), 'summaries': d.summaries}
                         for s, d in absolute.items()},
            'paired': {n: {'status': d.status, 'failures': list(d.failures), 'comparisons': d.summaries}
                       for n, d in pairs.items()}}]
        self.refresh()

    def test_resampled_stall_qualifies_with_original_failure_retained(self):
        self.stall_receipt()
        self.assertTrue(self.verify()['referencePerformanceQualified'])
        food = next(a for a in self.report['attempts'] if a['size'] == 'dense-food')
        self.assertEqual(food['failures'], [LABEL])

    def test_original_failure_without_resample_still_fails(self):
        self.stall_receipt()
        del self.report['diskStallResamples']
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'limit failed'):
            self.verify()

    def test_cpu_attributed_resample_claim_is_refused(self):
        self.stall_receipt(cpu=21000)
        with self.assertRaisesRegex(ValueError, 'not attributed'):
            self.verify()

    def test_recorded_numbers_must_match_the_attempt_log(self):
        self.stall_receipt()
        self.report['diskStallResamples'][0]['resamples'][0]['samples'][0]['cpuMicroseconds'] = 7000
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'differs from the attempt log|not attributed'):
            self.verify()

    def test_replacement_must_match_its_log(self):
        self.stall_receipt()
        (self.bundle / 'disk-stall-resample-0-0.log').write_bytes(
            log_lines(Synthetic().replacement(wall=7000), fixture=self.report['fixtures']['dense-food']['contract']))
        self.report['diskStallResamples'][0]['executions'][0]['logSHA256'] = receipt.digest(
            self.bundle / 'disk-stall-resample-0-0.log')
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'differs from its log'):
            self.verify()

    def test_resample_must_run_on_the_label_fixture(self):
        self.stall_receipt()
        self.report['diskStallResamples'][0]['fixtures'] = [self.report['fixtures']['dense-1']['manifestSHA256']]
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'different fixture'):
            self.verify()
        self.stall_receipt()
        (self.bundle / 'disk-stall-resample-0-0.log').write_bytes(
            log_lines(Synthetic().replacement(), fixture=self.report['fixtures']['dense-1']['contract']))
        self.report['diskStallResamples'][0]['executions'][0]['logSHA256'] = receipt.digest(
            self.bundle / 'disk-stall-resample-0-0.log')
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'differs from its log'):
            self.verify()

    def test_second_miss_cannot_qualify_and_is_an_ordinary_rerunnable_failure(self):
        self.stall_receipt(resample_wall=24000)
        with self.assertRaisesRegex(ValueError, 'limit failed'):
            self.verify()
        report = dict(self.report, releaseGateAccepted=False, timingLimitsPassed=False, error=receipt.TIMING_FAILURE)
        self.assertEqual(receipt.failed_qualification_failures(self.request, report),
                         ['dense-food:' + LABEL, 'food-own-history:scaling:' + LABEL])



class DiskStallBorderlineTests(borderline_tests.BorderlineBundleFixture):
    """Borderline judges the post-resample decision, never the replaced original samples."""

    def run_directory(self):
        run = super().run_directory()
        for name, data in self.extra_logs.items():
            (run / name).write_bytes(data)
        return run

    def stall_failed_run(self, original_ratio, resample_ratio):
        self.slow_growth(0.1)
        label = self.slow_absolute(original_ratio)
        size = self.spec['smallSize']
        bound = self.limits['actionsBySize'][size][self.action]['maxMs'] * 1000
        attempt = next(a for a in self.failed['attempts'] if a['size'] == size)
        slow = next(r for r in attempt['result']['observations'] if r['action'] == self.action and not r['warmup'])
        overrides = {(self.action, slow['index']): {'append': slow['microseconds'] - int(bound / 2),
                                                    'cpu': int(bound / 4)}}
        staging = self.repo.parent / (self.repo.name + '-stall-logs')
        staging.mkdir(exist_ok=True)
        self.addCleanup(shutil.rmtree, staging, ignore_errors=True)
        log = staging / (size + '-attempt-0.log')
        log.write_bytes(log_lines(attempt['result']['observations'], overrides, label=self.action))
        attempt['execution'] = dict(attempt['execution'], logSHA256=receipt.digest(log))
        limits = {**self.limits, 'sha256': self.host['limitsSHA256']}
        specs = run_gate.scaling_specs(self.limits)
        contracts = {s: v['contract'] for s, v in self.failed['fixtures'].items()}
        originals = {a['size']: a['result'] for a in self.failed['attempts']}
        planned, unattributed = disk_stall.plan(
            originals, {size: disk_stall.action_diagnostics(log)}, limits, specs, contracts)
        self.assertEqual(unattributed, [])
        rows = [dict(r, microseconds=round(bound * resample_ratio) if r['index'] == slow['index'] else r['microseconds'])
                for r in attempt['result']['observations'] if r['action'] == self.action]
        resample_log = staging / 'disk-stall-resample-0-0.log'
        resample_log.write_bytes(log_lines(rows, label=self.action, fixture=contracts[size]))
        self.extra_logs = {p.name: p.read_bytes() for p in (log, resample_log)}
        effective = disk_stall.apply(originals, planned, [rows], limits)
        absolute, pairs = disk_stall.evaluate_all(effective, limits, specs, contracts)
        self.failed['diskStallResamples'] = [{
            'attempt': 0, 'policy': disk_stall.POLICY, 'resamples': planned, 'replacements': [rows],
            'fixtures': [self.failed['fixtures'][size]['manifestSHA256']],
            'executions': [{'exitCode': 0, 'childAbsent': True, 'childGroupAbsent': True, 'noise': {},
                            'logSHA256': receipt.digest(resample_log)}],
            'absolute': {s: {'status': d.status, 'failures': list(d.failures), 'summaries': d.summaries}
                         for s, d in absolute.items()},
            'paired': {n: {'status': d.status, 'failures': list(d.failures), 'comparisons': d.summaries}
                       for n, d in pairs.items()}}]
        return label

    def test_resample_far_over_its_bound_is_not_borderline_even_if_the_original_was(self):
        self.stall_failed_run(1.04, 1.5)
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.seal()

    def test_borderline_judges_the_resample_and_keeps_its_log(self):
        label = self.stall_failed_run(1.5, 1.04)
        self.seal()
        result = self.verify()
        self.assertEqual([(m['label'], m['ratioOfBound']) for m in result['borderlineMetrics']], [(label, 1.04)])
        self.assertTrue((self.root / 'disk-stall-resample-0-0.log').is_file())

if __name__ == '__main__':
    unittest.main()
