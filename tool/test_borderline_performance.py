"""Lee's 2026-10-27 borderline rule. Bundle reports are synthetic; one test reads retained q9-q11 evidence."""
import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import sys
import unittest
from unittest.mock import patch

from test_reference_performance import ReceiptFixture, write, TOOLS
import gate_policy
from gate_policy import Evaluation, classify_borderline
import run_gate
import reference_receipt as receipt
import owner_override as override
import borderline

SOURCE = 'a' * 64
EVIDENCE = TOOLS.parents[1] / 'evidence/reference-performance'


def growth(large_median, median_bound=20.0, large_max=10.0, max_bound=30.0, action='sync.peerTask.storageAdmission'):
    summary = {action: {'smallMedianMs': 10.0, 'largeMedianMs': large_median, 'medianBoundMs': median_bound,
                        'smallMaximumMs': 9.0, 'largeMaximumMs': large_max, 'maximumBoundMs': max_bound}}
    failed = large_median > median_bound or large_max > max_bound
    return Evaluation('timing-failed' if failed else 'passed', ('scaling:' + action,) if failed else (), summary)


ABSOLUTE = {'dense-1': Evaluation('passed', (), {}), 'dense-2': Evaluation('passed', (), {})}


class BorderlinePolicyTests(unittest.TestCase):
    def classify(self, prior=SOURCE, identity=SOURCE, absolute=None, paired=None):
        return classify_borderline(prior, identity, absolute or ABSOLUTE, paired or {'task-own-history': growth(20.3)})

    def test_pass_is_an_ordinary_pass(self):
        result = self.classify(paired={'task-own-history': growth(19.9)})
        self.assertEqual(result['verdict'], 'passed')
        self.assertEqual(result['borderlineMetrics'], [])

    def test_growth_miss_within_band_on_identical_passed_source_is_borderline(self):
        result = self.classify()
        self.assertEqual(result['verdict'], 'borderline-accepted')
        self.assertEqual(result['borderlineMetrics'], [{
            'label': 'task-own-history:scaling:sync.peerTask.storageAdmission', 'statistic': 'median',
            'measuredMs': 20.3, 'boundMs': 20.0, 'ratioOfBound': 1.015}])
        # The band edge is inclusive and declared once; budgets are not consulted or changed.
        self.assertEqual(gate_policy.BORDERLINE_VARIATION_BAND, 0.05)
        self.assertEqual(self.classify(paired={'task-own-history': growth(21.0)})['verdict'], 'borderline-accepted')

    def test_fail_outside_band(self):
        for paired in [{'task-own-history': growth(21.01)},
                       {'task-own-history': growth(20.3, large_max=31.6)},
                       {'task-own-history': growth(20.3), 'food-own-history': growth(25.0)}]:
            with self.subTest(paired=paired):
                result = self.classify(paired=paired)
                self.assertEqual(result['verdict'], 'failed')
                self.assertIn('outside', result['reason'])

    def test_fail_without_prior_pass(self):
        for prior in (None, ''):
            self.assertEqual(self.classify(prior=prior)['verdict'], 'failed')

    def test_fail_on_different_identity(self):
        result = self.classify(identity='b' * 64)
        self.assertEqual(result['verdict'], 'failed')
        self.assertIn('identity', result['reason'])

    def test_fail_on_correctness(self):
        for absolute, paired in [
                ({**ABSOLUTE, 'dense-2': Evaluation('correctness-failed', ('correctness',), {})}, None),
                (None, {'task-own-history': Evaluation('correctness-failed', ('paired-shape-or-coverage',), {})}),
                (None, {'task-own-history': Evaluation('timing-failed', (), {})}),
                ({}, None)]:
            with self.subTest(absolute=absolute, paired=paired):
                result = classify_borderline(SOURCE, SOURCE, ABSOLUTE if absolute is None else absolute,
                                             paired or {'task-own-history': growth(20.3)})
                self.assertEqual(result['verdict'], 'failed')

    def test_fail_on_absolute_limit(self):
        absolute = {**ABSOLUTE, 'dense-2': Evaluation('timing-failed', ('task.title.save',), {})}
        result = self.classify(absolute=absolute)
        self.assertEqual(result['verdict'], 'failed')
        self.assertIn('absolute', result['reason'])

    def test_retained_q9_q10_q11_evidence(self):
        """q9 passed; q10 missed by 45% (ordinary failure); q11 missed by 1.6% (borderline)."""
        limits = json.loads((TOOLS / 'limits-v1.json').read_text())
        limits['sha256'] = receipt.digest(TOOLS / 'limits-v1.json')
        specs = run_gate.scaling_specs(limits)

        def decisions(path):
            report = json.loads(path.read_text())
            absolute = {a['size']: gate_policy.evaluate(a['result'], limits) for a in report['attempts']}
            contracts = {s: v['contract'] for s, v in report['fixtures'].items()}
            summaries = {s: d.summaries for s, d in absolute.items()}
            return absolute, {name: gate_policy.evaluate_scaling(summaries, spec, contracts) for name, spec in specs.items()}
        q9 = decisions(EVIDENCE / 'current/gate-result.json')
        self.assertTrue(all(d.status == 'passed' for d in [*q9[0].values(), *q9[1].values()]))
        q10 = classify_borderline(SOURCE, SOURCE, *decisions(EVIDENCE / 'owner-override-stable101/prior-gate-result.json'))
        self.assertEqual(q10['verdict'], 'failed')
        self.assertIn('explicitTask.title.undo', q10['reason'])
        q11 = classify_borderline(SOURCE, SOURCE, *decisions(EVIDENCE / 'owner-override-stable101/gate-result.json'))
        self.assertEqual(q11['verdict'], 'borderline-accepted')
        self.assertEqual([(m['label'], m['statistic'], round(m['ratioOfBound'], 4)) for m in q11['borderlineMetrics']],
                         [('task-own-history:scaling:sync.peerTask.whileFood.storageAdmission', 'median', 1.0156)])


class BorderlineBundleFixture(ReceiptFixture):
    def setUp(self):
        super().setUp()
        self.failed_request = {**copy.deepcopy(self.request), 'requestId': '5' * 32, 'issuedAtUTC': '2026-10-25T01:00:00Z'}
        self.failed = copy.deepcopy(self.report)
        self.failed.update(startedAtUTC='2026-10-25T01:00:01Z', finishedAtUTC='2026-10-25T01:20:00Z',
                           correctnessAccepted=False, releaseGateAccepted=False, error=receipt.TIMING_FAILURE)
        for key in ('timingLimitsPassed', 'measurementCompleted', 'allPinsMatch'):
            del self.failed[key]
        self.failed['referenceBinding'].update(requestId=self.failed_request['requestId'],
                                              requestSHA256=receipt.canonical_digest(self.failed_request))
        self.failed_cleanup = {**self.cleanup, 'requestId': self.failed_request['requestId'],
                               'verifiedCompletionCapture': False, 'errors': list(override.FAILED_WORKLOAD_CLEANUP_ERRORS),
                               'completedAtUTC': '2026-10-25T01:20:05Z', 'deadlineUTC': '2026-10-25T01:45:00Z'}
        self.spec = run_gate.scaling_specs(self.limits)['task-own-history']
        self.action = self.growth_action()
        self.slow_growth(1.02)
        self.root = self.repo / borderline.DIRECTORY

    def growth_action(self):
        budgets = self.limits['actionsBySize'][self.spec['largeSize']]
        for action, rule in sorted(self.spec['rules'].items()):
            budget = min(budgets[action]['medianMs'], budgets[action]['maxMs'])
            if (rule['maxMedianRatio'] + rule['medianAdditiveMs']) * 1.2 < budget:
                return action
        raise AssertionError('No growth-only synthetic action')

    def slow_growth(self, ratio, action=None, size=None):
        """Large-size median at `ratio` of its growth bound, with every absolute budget still met."""
        action = action or self.action
        rule = self.spec['rules'][action]
        bound = 1.0 * rule['maxMedianRatio'] + rule['medianAdditiveMs']
        attempt = next(a for a in self.failed['attempts'] if a['size'] == (size or self.spec['largeSize']))
        for row in attempt['result']['observations']:
            if row['action'] == action:
                row['microseconds'] = int(bound * ratio * 1000)
        self.recompute()

    def recompute(self):
        limits = {**self.limits, 'sha256': self.host['limitsSHA256']}
        summaries = {}
        for item in self.failed['attempts']:
            decision = gate_policy.evaluate(item['result'], limits)
            item.update(status=decision.status, failures=list(decision.failures), summaries=decision.summaries)
            summaries[item['size']] = decision.summaries
        contracts = {s: v['contract'] for s, v in self.failed['fixtures'].items()}
        for item in self.failed['pairedScalingAttempts']:
            decision = gate_policy.evaluate_scaling(summaries, run_gate.scaling_specs(self.limits)[item['comparison']], contracts)
            item.update(status=decision.status, failures=list(decision.failures), comparisons=decision.summaries)

    def run_directory(self):
        run = self.repo.parent / (self.repo.name + '-failed-run')
        if run.exists():
            shutil.rmtree(run)
        self.addCleanup(shutil.rmtree, run, ignore_errors=True)
        for path in self.bundle.rglob('*'):
            if path.is_file() and (path.suffix == '.log' or path.name == 'fixture.json'):
                target = run / path.relative_to(self.bundle)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
        write(run / 'gate-result.json', self.failed)
        write(run.with_suffix('.request.json'), self.failed_request)
        write(run.with_suffix('.cleanup.json'), self.failed_cleanup)
        self.addCleanup(run.with_suffix('.request.json').unlink, missing_ok=True)
        self.addCleanup(run.with_suffix('.cleanup.json').unlink, missing_ok=True)
        return run

    def seal(self):
        if self.root.exists():
            shutil.rmtree(self.root)
        run = self.run_directory()
        command = ['borderline.py', 'seal', '--repo', str(self.repo), '--request', str(run.with_suffix('.request.json')),
                   '--run', str(run), '--cleanup', str(run.with_suffix('.cleanup.json')), '--output', str(self.root)]
        with patch.object(sys, 'argv', command), contextlib.redirect_stdout(io.StringIO()):
            borderline.main()
        return receipt.read(self.root / borderline.RECORD)

    def verify(self):
        return borderline.verify_borderline(self.repo, self.root)

    def rewrite(self, name, change):
        value = receipt.read(self.root / name)
        change(value)
        write(self.root / name, value)
        record = receipt.read(self.root / borderline.RECORD)
        record['files'][name] = receipt.digest(self.root / name)
        write(self.root / borderline.RECORD, record)


class BorderlineBundleTests(BorderlineBundleFixture):
    def test_borderline_accepted_queues_a_follow_up_without_changing_budgets(self):
        record = self.seal()
        label = 'task-own-history:scaling:' + self.action
        result = self.verify()
        self.assertEqual(result['state'], borderline.STATE)
        self.assertIs(result['referencePerformanceQualified'], True)
        self.assertEqual(result['qualificationRequestId'], self.request['requestId'])
        self.assertEqual(result['borderlineRequestId'], self.failed_request['requestId'])
        self.assertEqual([m['label'] for m in result['borderlineMetrics']], [label])
        self.assertEqual(record['followUp'], {'status': 'queued', 'action': borderline.FOLLOW_UP, 'metrics': [label]})
        self.assertEqual(record['verdict'], 'borderline-accepted')
        self.assertIs(record['budgetsChanged'], False)
        self.assertEqual(record['limitsSHA256'], self.host['limitsSHA256'])
        self.assertEqual(receipt.digest(self.tools / 'limits-v1.json'), self.host['limitsSHA256'])

    def test_fail_outside_band(self):
        self.slow_growth(1.06)
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.seal()

    def test_fail_without_prior_pass(self):
        self.seal()
        shutil.rmtree(self.bundle)
        with self.assertRaises(ValueError):
            self.verify()

    def test_fail_when_prior_pass_does_not_precede_the_failed_run(self):
        self.failed_request['issuedAtUTC'] = '2026-10-25T00:00:01Z'
        self.failed.update(startedAtUTC='2026-10-25T00:00:01Z')
        self.failed['referenceBinding']['requestSHA256'] = receipt.canonical_digest(self.failed_request)
        with self.assertRaisesRegex(ValueError, 'earlier passing'):
            self.seal()

    def test_fail_on_different_identity(self):
        self.seal()
        (self.repo / 'lib/a.dart').write_text('const a = 2;\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'stale'):
            self.verify()
        # A failure recorded for other source cannot borrow this pass either.
        (self.repo / 'lib/a.dart').write_text('const a = 1;\n')
        self.commit()
        self.verify()
        other = receipt.source_identity(self.repo, receipt.IDENTITY_V1)
        self.failed_request['relevantSource'] = other
        self.failed['referenceBinding'].update(requestSHA256=receipt.canonical_digest(self.failed_request),
                                              relevantSourceSHA256=other['sha256'])
        with self.assertRaisesRegex(ValueError, 'different relevant-source identity'):
            self.seal()

    def test_fail_on_correctness(self):
        attempt = self.failed['attempts'][0]
        attempt['result']['correctnessPassed'] = False
        self.recompute()
        with self.assertRaisesRegex(ValueError, 'correctness'):
            self.seal()

    def test_fail_on_absolute_limit(self):
        size = self.spec['smallSize']
        budget = self.limits['actionsBySize'][size][self.action]['maxMs']
        attempt = next(a for a in self.failed['attempts'] if a['size'] == size)
        for row in attempt['result']['observations']:
            if row['action'] == self.action and not row['warmup']:
                row['microseconds'] = int(budget * 1000) + 1000
        self.recompute()
        self.assertEqual(attempt['status'], 'timing-failed')
        with self.assertRaisesRegex(ValueError, 'absolute'):
            self.seal()

    def test_record_cannot_be_edited_after_sealing(self):
        self.seal()
        for change in [lambda r: r['followUp'].update(status='done'),
                       lambda r: r.update(variationBand=0.5),
                       lambda r: r['borderlineMetrics'].clear(),
                       lambda r: r.update(budgetsChanged=True)]:
            original = receipt.read(self.root / borderline.RECORD)
            change(original)
            write(self.root / borderline.RECORD, original)
            with self.assertRaises(ValueError):
                self.verify()
            self.seal()
        self.rewrite('gate-result.json', lambda r: r.update(finishedAtUTC='2026-10-25T01:20:01Z'))
        with self.assertRaises(ValueError):
            self.verify()

    def test_verify_cli_reports_the_queued_follow_up(self):
        self.seal()
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(self.repo)]), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            receipt.main()
        self.assertEqual(json.loads(stdout.getvalue())['state'], borderline.STATE)
        self.assertIn('follow-up queued', stderr.getvalue())
        self.assertIn(self.action, stderr.getvalue())

    def test_verify_cli_fails_closed_on_a_rejected_borderline_bundle(self):
        self.seal()
        (self.root / 'compile.log').write_bytes(b'changed')
        with patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(self.repo)]), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(ValueError):
                receipt.main()


class OwnerOverrideScopeTests(unittest.TestCase):
    def test_override_only_routes_verification_for_its_own_release(self):
        from test_owner_override import OwnerOverrideTests
        fixture = OwnerOverrideTests(methodName='test_exact_failure_is_accepted_for_one_release_but_never_qualified')
        self.addCleanup(fixture.doCleanups)
        fixture.setUp()
        target = fixture.repo / receipt.OWNER_OVERRIDE
        if target != fixture.root:
            shutil.copytree(fixture.root, target)
        (fixture.repo / 'pubspec.yaml').write_text('name: tandemlog\nversion: 2026.10.8-rc.1+102\n')
        fixture.commit()
        with patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(fixture.repo)]), \
                patch.object(override, 'POLICY', fixture.policy), contextlib.redirect_stdout(io.StringIO()):
            # The ordinary qualification verifier runs (and here finds stale source), not the override.
            with self.assertRaisesRegex(ValueError, 'stale/mismatched'):
                receipt.main()


if __name__ == '__main__':
    unittest.main()
