"""Lee's 2026-10-31 gate rule. All reports, logs and children here are synthetic."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent / 'performance'
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gate_policy
import reference_receipt as receipt
import run_gate
import test_reference_performance as reference_tests
from test_reference_performance import ReceiptFixture, family_of, write

# Slow enough to miss dense-food's 50 ms median and every growth bound from a 1 ms small side.
ACTION = 'task.title.save'
OTHER = 'task.notes.save'
FAMILY = family_of(ACTION)
SLOW = 60000
FAST = 1000


def log_bytes(rows, fixture=None, family=None):
    lines = [{'measurement': 'broad-action', **row} for row in rows]
    lines.append({'measurement': 'broad-all-pass', 'rerunFamily': family,
                  **{key: (fixture or {}).get(key) for key in run_gate.FIXTURE_KEYS}})
    return ''.join(json.dumps(line) + '\n' for line in lines).encode()


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.limits = json.loads((TOOLS / 'limits-v1.json').read_text())
        self.limits['sha256'] = 'sealed'
        self.specs = run_gate.scaling_specs(self.limits)
        self.families = {size: {action: family_of(action) for action in actions}
                         for size, actions in self.limits['actionsBySize'].items()}
        self.passed = gate_policy.Evaluation('passed', (), {})
        self.absolute = {size: self.passed for size in self.limits['actionsBySize']}
        self.paired = {name: self.passed for name in self.specs}

    def test_passing_first_pass_plans_nothing(self):
        self.assertEqual(gate_policy.first_pass_failures(self.absolute, self.paired), [])
        self.assertEqual(gate_policy.rerun_plan(self.absolute, self.paired, self.specs, self.families), [])

    def test_absolute_miss_reruns_only_its_shape_family(self):
        self.absolute['dense-2'] = gate_policy.Evaluation('timing-failed', (ACTION,), {ACTION: {'sampleMs': 60}})
        self.assertEqual(gate_policy.rerun_plan(self.absolute, self.paired, self.specs, self.families),
                         [('dense-2', FAMILY)])

    def test_growth_miss_reruns_both_sides_and_shares_a_process(self):
        self.paired['food-own-history'] = gate_policy.Evaluation('timing-failed', ('scaling:' + ACTION,), {})
        self.assertEqual(gate_policy.rerun_plan(self.absolute, self.paired, self.specs, self.families),
                         [('dense-1', FAMILY), ('dense-food', FAMILY)])
        self.paired['task-own-history'] = gate_policy.Evaluation('timing-failed', ('scaling:' + OTHER,), {})
        self.assertEqual(gate_policy.rerun_plan(self.absolute, self.paired, self.specs, self.families),
                         [('dense-1', FAMILY), ('dense-2', FAMILY), ('dense-food', FAMILY)])

    def judge(self, values):
        reruns = {size: {a: v for a, v in values.get(size, {}).items()} for size in values}
        return gate_policy.judge_reruns(self.absolute, self.paired, reruns, self.limits, self.specs)

    def test_growth_is_judged_from_rerun_values_on_both_sides(self):
        rule = self.specs['food-own-history']['rules'][ACTION]
        first = {'smallSampleMs': 1.0, 'largeSampleMs': 60.0, 'boundMs': gate_policy.growth_bound(1.0, rule)}
        self.paired['food-own-history'] = gate_policy.Evaluation('timing-failed', ('scaling:' + ACTION,), {ACTION: first})
        # The rerun small side alone lifts the bound over the same large value: it must be used.
        verdict = self.judge({'dense-1': {ACTION: 40.0}, 'dense-food': {ACTION: 40.0}})
        self.assertEqual(verdict['confirmedFailures'], [])
        [item] = verdict['judgments']
        self.assertEqual(item['firstPass'], first)
        self.assertEqual(item['rerun'], {'smallSampleMs': 40.0, 'largeSampleMs': 40.0,
                                         'boundMs': gate_policy.growth_bound(40.0, rule)})
        # The rerun large side must be used too: a fast small side with a slow large side confirms.
        self.assertEqual(self.judge({'dense-1': {ACTION: 1.0}, 'dense-food': {ACTION: 40.0}})['confirmedFailures'],
                         ['food-own-history:scaling:' + ACTION])

    def test_different_label_slow_only_in_rerun_is_recorded_not_judged(self):
        first = {ACTION: {'sampleMs': 60.0}}
        self.absolute['dense-food'] = gate_policy.Evaluation('timing-failed', (ACTION,), first)
        verdict = self.judge({'dense-food': {ACTION: 1.0, OTHER: 900.0}})
        self.assertEqual(verdict['confirmedFailures'], [])
        self.assertEqual([item['label'] for item in verdict['judgments']], ['dense-food:' + ACTION])
        self.assertEqual([item['label'] for item in verdict['notJudgedOverBound']], ['dense-food:' + OTHER])

    def test_rerun_rows_must_be_exactly_one_unwarmed_sample_per_family_action(self):
        row = {'action': ACTION, 'family': FAMILY, 'index': 0, 'warmup': False, 'microseconds': 5}
        self.assertTrue(gate_policy.valid_rerun_rows([row], FAMILY, [ACTION]))
        for rows in ([], [row, row], [{**row, 'warmup': True}], [{**row, 'index': 1}], [{**row, 'family': 'x'}],
                     [{**row, 'microseconds': True}], [{**row, 'action': OTHER}]):
            self.assertFalse(gate_policy.valid_rerun_rows(rows, FAMILY, [ACTION]))

    def test_harness_constants_match_the_rule(self):
        source = (TOOLS / 'benchmark.dart').read_text()
        self.assertIn('const benchmarkWarmups = 0, benchmarkSamples = 1;', source)
        self.assertEqual((self.limits['gateRule'], self.limits['warmups'], self.limits['samples']),
                         (gate_policy.GATE_RULE, 0, 1))

    def test_every_first_pass_row_needs_a_named_family(self):
        rows = {'dense-1': {'observations': [{'action': ACTION, 'family': None}]}}
        with self.assertRaisesRegex(ValueError, 'family'):
            gate_policy.observation_families(rows)


@unittest.skipUnless(sys.platform.startswith('linux'), 'Synthetic orchestration exercises the Linux-only AOT runner')
class RunnerTests(unittest.TestCase):
    """run_gate.main end to end: the rule needs nothing but the one invocation."""

    def run_gate(self, first=None, rerun=None, mode=('--reference-request',), child_failure=None):
        fixture = reference_tests.ReferenceReceiptTests(methodName='test_fresh_complete_source_bound_receipt_passes')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        repo, tools = fixture.repo, fixture.tools
        write(repo / '.dart_tool/package_config.json', {'configVersion': 2, 'packages': [
            {'name': 'tandemlog', 'rootUri': repo.as_uri() + '/', 'packageUri': 'lib/', 'languageVersion': '3.13'}]})
        sdk = repo / 'sdk/bin/cache/dart-sdk'
        for name in ('bin/dart', 'bin/utils/gen_snapshot', 'lib/_internal/vm_platform_strong.dill'):
            path = sdk / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'synthetic tool input')
        for name in ('native.so', 'sqlite.so'):
            (repo / name).write_bytes(b'synthetic library input')
        request = repo / 'request.json'
        write(request, fixture.request)
        output = repo / 'output'
        command = ['run_gate.py', '--repo', str(repo), '--dart', str(sdk / 'bin/dart'),
                   '--native-library', str(repo / 'native.so'), '--sqlite-library', str(repo / 'sqlite.so'),
                   '--output', str(output), '--expected-limits-sha256', receipt.digest(tools / 'limits-v1.json')]
        command += ['--reference-request', str(request)] if mode == ('--reference-request',) else list(mode)
        first, rerun = first or {}, rerun or {}
        measured = {a['size']: copy.deepcopy(a['result']['observations']) for a in fixture.report['attempts']}
        calls = []

        def child(args, log, env, timeout):
            calls.append(args)
            exit_code = 0
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
                rows = [{**row, 'microseconds': first.get((size, row['action']), FAST)} for row in measured[size]]
                log.write_bytes(log_bytes(rows))
                exit_code = 1 if child_failure == 'first-pass' else 0
            else:
                self.assertEqual(args[1], 'rerun-family')
                family = args[-1]
                size = Path(args[2]).name.removeprefix('rerun-').removesuffix('-' + family)
                self.assertFalse(Path(args[2]).exists(), 'A rerun needs a fresh output')
                rows = [{**row, 'microseconds': rerun.get((size, row['action']), FAST)}
                        for row in measured[size] if row['family'] == family]
                contract = json.loads(Path(args[4]).read_text())
                if child_failure == 'rerun-coverage':
                    rows = rows[:-1]
                if child_failure == 'rerun-fixture':
                    contract = {}
                log.write_bytes(log_bytes(rows, contract, family))
                exit_code = 1 if child_failure == 'rerun-exit' else 0
            return {'exitCode': exit_code, 'childAbsent': True, 'childGroupAbsent': True,
                    'logSHA256': receipt.digest(log), 'noise': {}}

        context = {'requestId': fixture.request['requestId'], 'synthetic': True}
        with patch.object(sys, 'argv', command), patch.object(run_gate, '__file__', str(tools / 'run_gate.py')), \
                patch.object(run_gate, 'run_child', side_effect=child), \
                patch.object(run_gate, 'request_context', return_value=context), \
                patch.object(run_gate, 'check_reference_toolchain'), \
                patch.object(run_gate, 'reference_profile'), \
                patch('builtins.input', side_effect=AssertionError('The rule needs no manual step')), \
                patch.object(run_gate, 'actual_resource_bounds', return_value=fixture.bounds):
            status = run_gate.main()
        fixture.child_calls = calls
        reruns = [c for c in calls if c[1] == 'rerun-family']
        return status, json.loads((output / 'gate-result.json').read_text()), reruns, output, fixture

    def test_clean_first_pass_takes_no_rerun(self):
        status, report, reruns, _, _ = self.run_gate()
        self.assertEqual(status, 0, report.get('error'))
        self.assertTrue(report['releaseGateAccepted'])
        self.assertEqual((reruns, report['firstPassFailureCount'], report['reruns']), ([], 0, []))

    def test_single_miss_then_rerun_pass_is_accepted_automatically_and_reported(self):
        status, report, reruns, output, _ = self.run_gate(first={('dense-food', ACTION): SLOW})
        self.assertEqual(status, 0, report.get('error'))
        self.assertTrue(report['releaseGateAccepted'] and report['timingLimitsPassed'])
        self.assertEqual(len(reruns), 2)  # dense-food's own miss and its growth pair's small side.
        labels = ['dense-food:' + ACTION, 'food-own-history:scaling:' + ACTION]
        self.assertEqual(report['firstPassFailures'], labels)
        self.assertEqual(report['firstPassFailureCount'], 2)
        self.assertEqual(report['confirmedFailures'], [])
        absolute = next(j for j in report['rerunJudgments'] if j['label'] == labels[0])
        self.assertEqual((absolute['firstPassMs'], absolute['rerunMs'], absolute['failedAgain']), (60.0, 1.0, False))
        # Every first-pass value stays where it was.
        food = next(a for a in report['attempts'] if a['size'] == 'dense-food')
        self.assertEqual(food['failures'], [ACTION])
        self.assertEqual(food['summaries'][ACTION], {'sampleMs': 60.0})
        self.assertEqual([(r['size'], r['family']) for r in report['reruns']], [('dense-1', FAMILY), ('dense-food', FAMILY)])
        for record in report['reruns']:
            self.assertTrue((output / run_gate.rerun_log_name(record['size'], record['family'])).is_file())
            self.assertTrue(record['observations'])

    def test_same_label_failing_twice_is_rejected_with_every_value_retained(self):
        status, report, _, _, _ = self.run_gate(first={('dense-food', ACTION): SLOW}, rerun={('dense-food', ACTION): SLOW})
        self.assertEqual(status, 1)
        self.assertFalse(report['releaseGateAccepted'])
        self.assertNotIn('timingLimitsPassed', report)
        self.assertIn('Same label failed', report['error'])
        self.assertEqual(report['confirmedFailures'], ['dense-food:' + ACTION, 'food-own-history:scaling:' + ACTION])
        self.assertEqual([j['failedAgain'] for j in report['rerunJudgments']], [True, True])
        self.assertTrue(all(r['observations'] for r in report['reruns']))

    def test_different_label_slow_only_in_rerun_is_recorded_not_judged(self):
        status, report, _, _, _ = self.run_gate(first={('dense-food', ACTION): SLOW},
                                                rerun={('dense-food', OTHER): SLOW})
        self.assertEqual(status, 0, report.get('error'))
        self.assertEqual(report['confirmedFailures'], [])
        recorded = {item['label'] for item in report['notJudgedOverBound']}
        self.assertIn('dense-food:' + OTHER, recorded)
        self.assertNotIn('dense-food:' + OTHER, {j['label'] for j in report['rerunJudgments']})

    def test_growth_miss_reruns_the_pair_and_judges_rerun_values(self):
        # 20 ms passes dense-2's 50 ms absolute budget but misses growth from a 1 ms small side.
        first = {('dense-2', ACTION): 20000}
        status, report, reruns, _, _ = self.run_gate(first=first, rerun={('dense-1', ACTION): 20000, ('dense-2', ACTION): 20000})
        self.assertEqual(status, 0, report.get('error'))
        self.assertEqual(sorted(call[-1] for call in reruns), [FAMILY, FAMILY])
        [item] = report['rerunJudgments']
        self.assertEqual(item['label'], 'task-own-history:scaling:' + ACTION)
        self.assertEqual(item['firstPass']['smallSampleMs'], 1.0)
        self.assertEqual((item['rerun']['smallSampleMs'], item['rerun']['largeSampleMs'], item['failedAgain']), (20.0, 20.0, False))
        status, report, _, _, _ = self.run_gate(first=first, rerun={('dense-2', ACTION): 20000})
        self.assertEqual(status, 1)
        self.assertEqual(report['confirmedFailures'], ['task-own-history:scaling:' + ACTION])

    def test_correctness_failure_is_terminal_with_no_rerun(self):
        status, report, reruns, _, fixture = self.run_gate(first={('dense-food', ACTION): SLOW}, child_failure='first-pass')
        self.assertEqual(status, 1)
        self.assertEqual(reruns, [])
        self.assertEqual(len(report['attempts']), 1)
        self.assertEqual(sum(c[1] == 'run' for c in fixture.child_calls), 1)
        self.assertIn('terminal, no rerun', report['error'])
        self.assertNotIn('firstPassFailures', report)

    def test_rerun_correctness_coverage_or_shape_failure_is_terminal(self):
        for failure in ('rerun-exit', 'rerun-coverage', 'rerun-fixture'):
            with self.subTest(failure=failure):
                status, report, reruns, _, _ = self.run_gate(first={('dense-food', ACTION): SLOW}, child_failure=failure)
                self.assertEqual(status, 1)
                self.assertEqual(len(reruns), 1)
                self.assertIn('Rerun correctness/coverage failed', report['error'])
                self.assertFalse(report['releaseGateAccepted'])

    def test_hosted_and_measure_only_never_rerun(self):
        for flag in ('--hosted-advisory', '--measure-only'):
            with self.subTest(flag=flag):
                status, report, reruns, _, _ = self.run_gate(first={('dense-food', ACTION): SLOW}, mode=(flag,))
                self.assertEqual(status, 0, report.get('error'))
                self.assertEqual(reruns, [])
                self.assertEqual(report['firstPassFailureCount'], 2)
                self.assertFalse(report['timingLimitsPassed'])
                self.assertFalse(report['releaseGateAccepted'])


class ReceiptTests(ReceiptFixture):
    """The verifier recomputes the rule from retained samples and logs."""

    def miss(self, size, action, first=SLOW, rerun=FAST):
        """Rewrite the report as run_gate would for one first-pass absolute miss."""
        limits = {**self.limits, 'sha256': self.host['limitsSHA256']}
        attempt = next(a for a in self.report['attempts'] if a['size'] == size)
        for row in attempt['result']['observations']:
            if row['action'] == action:
                row['microseconds'] = first
        self.recompute(limits)
        specs = run_gate.scaling_specs(self.limits)
        results = {a['size']: a['result'] for a in self.report['attempts']}
        absolute = {a['size']: gate_policy.evaluate(a['result'], limits) for a in self.report['attempts']}
        summaries = {s: d.summaries for s, d in absolute.items()}
        contracts = {s: v['contract'] for s, v in self.report['fixtures'].items()}
        paired = {n: gate_policy.evaluate_scaling(summaries, spec, contracts) for n, spec in specs.items()}
        families = gate_policy.observation_families(results)
        self.report['firstPassFailures'] = gate_policy.first_pass_failures(absolute, paired)
        self.report['firstPassFailureCount'] = len(self.report['firstPassFailures'])
        self.report['reruns'] = []
        values = {}
        for run_size, family in gate_policy.rerun_plan(absolute, paired, specs, families):
            rows = [{'action': a, 'family': family, 'index': 0, 'warmup': False,
                     'microseconds': rerun if run_size == size and a == action else FAST}
                    for a, f in families[run_size].items() if f == family]
            log = self.bundle / run_gate.rerun_log_name(run_size, family)
            log.write_bytes(log_bytes(rows, self.report['fixtures'][run_size]['contract'], family))
            self.report['reruns'].append({'size': run_size, 'family': family, 'observations': rows,
                                          'fixtureManifestSHA256': self.report['fixtures'][run_size]['manifestSHA256'],
                                          'execution': {'exitCode': 0, 'childAbsent': True, 'childGroupAbsent': True,
                                                        'logSHA256': receipt.digest(log), 'noise': {}}})
            values.setdefault(run_size, {}).update({r['action']: r['microseconds'] / 1000 for r in rows})
        verdict = gate_policy.judge_reruns(absolute, paired, values, limits, specs)
        self.report.update(rerunJudgments=verdict['judgments'], notJudgedOverBound=verdict['notJudgedOverBound'],
                           confirmedFailures=verdict['confirmedFailures'])
        self.refresh()

    def recompute(self, limits):
        summaries = {}
        for item in self.report['attempts']:
            decision = gate_policy.evaluate(item['result'], limits)
            item.update(status=decision.status, failures=list(decision.failures), summaries=decision.summaries)
            summaries[item['size']] = decision.summaries
            self.write_first_pass_log(item)
        contracts = {s: v['contract'] for s, v in self.report['fixtures'].items()}
        for item in self.report['pairedScalingAttempts']:
            decision = gate_policy.evaluate_scaling(summaries, run_gate.scaling_specs(self.limits)[item['comparison']], contracts)
            item.update(status=decision.status, failures=list(decision.failures), comparisons=decision.summaries)

    def test_valid_hashes_cannot_hide_first_pass_log_defects(self):
        attempt = self.report['attempts'][0]
        log = self.bundle / (attempt['size'] + '-attempt-0.log')
        original = log.read_bytes()
        events = [json.loads(line) for line in original.splitlines()]
        changes = {
            'empty': lambda e: [],
            'absent': lambda e: e[-1:],
            'partial': lambda e: e[1:],
            'duplicate': lambda e: [e[0], *e],
            'no-completion': lambda e: e[:-1],
            'duplicate-completion': lambda e: [*e, e[-1]],
            'completion-before-measurements': lambda e: [e[-1], *e[:-1]],
            'timing': lambda e: [{**e[0], 'microseconds': SLOW}, *e[1:]],
            'family': lambda e: [{**e[0], 'family': 'rewritten'}, *e[1:]],
            'action': lambda e: [{**e[0], 'action': 'wrong'}, *e[1:]],
            'index': lambda e: [{**e[0], 'index': 1}, *e[1:]],
            'warmup': lambda e: [{**e[0], 'warmup': True}, *e[1:]],
            'missing-sampling': lambda e: [*e[:-1], {k: v for k, v in e[-1].items() if k != 'samples'}],
        }
        for key, value in [('samples', 5), ('warmups', 2), ('rerunFamily', FAMILY),
                           ('fixtureSchemaVersion', 99), ('baseHistoricalRecords', 999),
                           ('actualPhysicalRecords', 999), ('growthKind', 'wrong'),
                           ('families', 999), ('costDiagnosticsEnabled', True), ('samples', True)]:
            changes['completion-' + key + str(value)] = lambda e, k=key, v=value: [*e[:-1], {**e[-1], k: v}]
        for name, change in changes.items():
            with self.subTest(name=name):
                log.write_text(''.join(json.dumps(event) + '\n' for event in change(copy.deepcopy(events))))
                attempt['execution']['logSHA256'] = receipt.digest(log)
                self.refresh()  # All raw hashes AND the regenerated bundle inventory are valid.
                with self.assertRaises(ValueError):
                    self.verify()
        log.write_bytes(original)
        attempt['execution']['logSHA256'] = receipt.digest(log)
        self.refresh()
        self.assertTrue(self.verify()['referencePerformanceQualified'])

    def test_every_first_pass_size_is_bound_to_its_log(self):
        for attempt in self.report['attempts']:
            with self.subTest(size=attempt['size']):
                log = self.bundle / (attempt['size'] + '-attempt-0.log')
                original = log.read_bytes()
                events = [json.loads(line) for line in original.splitlines()]
                events[0]['microseconds'] = SLOW
                log.write_text(''.join(json.dumps(event) + '\n' for event in events))
                attempt['execution']['logSHA256'] = receipt.digest(log)
                self.refresh()
                with self.assertRaisesRegex(ValueError, 'First-pass observations'):
                    self.verify()
                log.write_bytes(original)
                attempt['execution']['logSHA256'] = receipt.digest(log)
        self.refresh()

    def test_report_family_rewrite_and_omitted_plan_cannot_hide_raw_miss(self):
        self.miss('dense-food', ACTION)
        for row in self.report['attempts'][-1]['result']['observations']:
            if row['action'] == ACTION:
                row.update(family='rewritten', microseconds=FAST)
        # Copied absolute/growth decisions and plan are internally consistent,
        # but their input is no longer the retained raw first pass.
        logs = {p: p.read_bytes() for p in self.bundle.glob('*-attempt-0.log')}
        hashes = [a['execution']['logSHA256'] for a in self.report['attempts']]
        self.recompute({**self.limits, 'sha256': self.host['limitsSHA256']})
        for p, data in logs.items():
            p.write_bytes(data)
        for a, h in zip(self.report['attempts'], hashes):
            a['execution']['logSHA256'] = h
        self.report.update(firstPassFailures=[], firstPassFailureCount=0, reruns=[],
                           rerunJudgments=[], notJudgedOverBound=[], confirmedFailures=[])
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'First-pass observations'):
            self.verify()

    def test_double_failure_to_pass_attack_is_rejected_before_export(self):
        self.miss('dense-food', ACTION, rerun=SLOW)
        with self.assertRaisesRegex(ValueError, 'Same label failed'):
            self.verify()
        logs = {p: p.read_bytes() for p in self.bundle.glob('*-attempt-0.log')}
        hashes = [a['execution']['logSHA256'] for a in self.report['attempts']]
        for a in self.report['attempts']:
            for row in a['result']['observations']:
                row['microseconds'] = FAST
        self.recompute({**self.limits, 'sha256': self.host['limitsSHA256']})
        for p, data in logs.items():
            p.write_bytes(data)
        for a, h in zip(self.report['attempts'], hashes):
            a['execution']['logSHA256'] = h
        for record in self.report['reruns']:
            (self.bundle / run_gate.rerun_log_name(record['size'], record['family'])).unlink()
        self.report.update(firstPassFailures=[], firstPassFailureCount=0, reruns=[],
                           rerunJudgments=[], notJudgedOverBound=[], confirmedFailures=[])
        self.refresh()
        self.assertEqual(hashes, [receipt.digest(self.bundle / (a['size'] + '-attempt-0.log'))
                                  for a in self.report['attempts']])
        with self.assertRaisesRegex(ValueError, 'First-pass observations'):
            self.verify()
        output = self.repo / 'rejected-export'
        command = ['reference_receipt.py', 'seal', '--repo', str(self.repo),
                   '--request', str(self.bundle / 'request.json'), '--cleanup', str(self.bundle / 'cleanup.json'),
                   '--run', str(self.bundle), '--output', str(output)]
        with patch.object(sys, 'argv', command), self.assertRaisesRegex(ValueError, 'First-pass observations'):
            receipt.main()
        self.assertFalse(output.exists(), 'Invalid logs must be refused before any export')

    def test_miss_then_clean_rerun_qualifies_and_reports_the_first_pass(self):
        self.miss('dense-food', ACTION)
        result = self.verify()
        self.assertTrue(result['referencePerformanceQualified'])
        self.assertEqual(result['firstPassFailureCount'], 2)
        self.assertEqual(result['firstPassFailures'][0], 'dense-food:' + ACTION)
        self.assertEqual(result['rerunJudgments'][0]['rerunMs'], 1.0)

    def test_verify_cli_warns_about_first_pass_misses(self):
        self.miss('dense-food', ACTION)
        errors = reference_tests.io.StringIO()
        output = reference_tests.io.StringIO()
        with patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(self.repo)]), \
                reference_tests.contextlib.redirect_stderr(errors), reference_tests.contextlib.redirect_stdout(output):
            receipt.main()
        self.assertIn('first-pass misses', errors.getvalue())
        self.assertIn('dense-food:' + ACTION, errors.getvalue())
        self.assertEqual(json.loads(output.getvalue())['firstPassFailureCount'], 2)

    def test_double_failure_cannot_qualify(self):
        self.miss('dense-food', ACTION, rerun=SLOW)
        with self.assertRaisesRegex(ValueError, 'Same label failed'):
            self.verify()

    def test_first_pass_miss_without_its_rerun_cannot_qualify(self):
        self.miss('dense-food', ACTION)
        self.report.update(reruns=[], rerunJudgments=[], notJudgedOverBound=[])
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'Reruns differ'):
            self.verify()

    def test_recorded_judgment_or_count_cannot_differ_from_the_samples(self):
        self.miss('dense-food', ACTION, rerun=SLOW)
        original = copy.deepcopy(self.report)
        for change, reason in [(lambda r: r.update(confirmedFailures=[]), 'Rerun judgments differ'),
                               (lambda r: r['rerunJudgments'][0].update(failedAgain=False), 'Rerun judgments differ'),
                               (lambda r: r.update(firstPassFailureCount=0), 'First-pass failures differ'),
                               (lambda r: r.update(firstPassFailures=[]), 'First-pass failures differ')]:
            self.report = copy.deepcopy(original); change(self.report); self.refresh()
            with self.subTest(reason=reason), self.assertRaisesRegex(ValueError, reason):
                self.verify()

    def test_rerun_samples_must_match_their_log_and_fixture(self):
        self.miss('dense-food', ACTION)
        original = copy.deepcopy(self.report)
        self.report['reruns'][0]['observations'][0]['microseconds'] = 2
        self.refresh()
        with self.assertRaises(ValueError):
            self.verify()
        self.report = copy.deepcopy(original)
        self.report['reruns'][0]['fixtureManifestSHA256'] = 'a' * 64
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'different fixture'):
            self.verify()
        self.report = copy.deepcopy(original)
        self.report['reruns'][0]['execution']['childGroupAbsent'] = False
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'Incomplete rerun'):
            self.verify()
        self.report = copy.deepcopy(original)
        log = self.bundle / run_gate.rerun_log_name(original['reruns'][0]['size'], original['reruns'][0]['family'])
        log.write_bytes(log.read_bytes() + b'\n')
        self.report['reruns'][0]['execution']['logSHA256'] = 'b' * 64
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'rerun log'):
            self.verify()

    def test_result_from_an_older_rule_cannot_qualify(self):
        self.report['gateRule'] = 'two-warmups-five-samples'
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'current gate rule'):
            self.verify()

    def test_seal_copies_rerun_logs_into_the_bundle(self):
        self.assertEqual(receipt.rerun_log_names({'reruns': [{'size': 'dense-1', 'family': 'food-products'}]}),
                         ['rerun-dense-1-food-products.log'])


if __name__ == '__main__':
    unittest.main()
