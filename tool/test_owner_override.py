"""Owner acceptance of one retained timing-only failure. All reports here are synthetic."""
import contextlib
import copy
import io
import json
import os
import shutil
import subprocess
import sys
import unittest
from unittest.mock import patch

from test_reference_performance import ReceiptFixture, write, TOOLS
import gate_policy
import run_gate
import reference_receipt as receipt
import owner_override as override

POSIX_MODES = os.name != 'nt'


class OwnerOverrideFixture(ReceiptFixture):
    def setUp(self):
        super().setUp()
        (self.repo / 'pubspec.yaml').write_text('name: tandemlog\nversion: 2026.10.7+101\n')
        self.commit()
        self.rebind()
        self.fail_growth()
        self.prior()
        self.base_revision = self.head()
        self.marker = self.tools / 'policy_marker.py'
        self.marker.write_text('# reviewed policy-only marker\n')
        self.commit()
        self.policy = {'release': '2026.10.7+101', 'sourceRevision': self.base_revision,
                       'relevantSourceSHA256': self.identity['sha256'], 'requestId': self.request['requestId'],
                       'priorRequestId': self.prior_request['requestId'], 'limitsSHA256': self.host['limitsSHA256'],
                       'acceptedFailures': self.labels, 'allowedDelta': ['tool/performance/policy_marker.py']}
        self.cleanup.update(verifiedCompletionCapture=False, errors=list(override.FAILED_WORKLOAD_CLEANUP_ERRORS))
        self.root = self.repo / 'evidence/reference-performance/owner-override-stable101'
        self.record = None
        self.publish()

    def rebind(self):
        """The stable101 override is pinned to the original (v1) relevant-source identity."""
        super().rebind(receipt.IDENTITY_V1)

    def recompute(self, report):
        limits = {**self.limits, 'sha256': self.host['limitsSHA256']}
        summaries = {}
        for item in report['attempts']:
            decision = gate_policy.evaluate(item['result'], limits)
            item.update(status=decision.status, failures=list(decision.failures), summaries=decision.summaries)
            summaries[item['size']] = decision.summaries
        contracts = {s: v['contract'] for s, v in report['fixtures'].items()}
        for item in report['pairedScalingAttempts']:
            decision = gate_policy.evaluate_scaling(summaries, run_gate.scaling_specs(self.limits)[item['comparison']], contracts)
            item.update(status=decision.status, failures=list(decision.failures), comparisons=decision.summaries)
        return override.failing_labels(report)

    def slow(self, report, action, size, microseconds):
        for row in next(a for a in report['attempts'] if a['size'] == size)['result']['observations']:
            if row['action'] == action:
                row['microseconds'] = microseconds

    def growth_only_action(self, skip=()):
        """An action whose large-size growth can fail while its absolute budget still passes."""
        spec = run_gate.scaling_specs(self.limits)['task-own-history']
        budgets = self.limits['actionsBySize'][spec['largeSize']]
        for action, rule in sorted(spec['rules'].items()):
            value = max(rule['maxMedianRatio'] + rule['medianAdditiveMs'],
                        rule['maxMaximumRatio'] + rule['maximumAdditiveMs']) + 0.5
            if action not in skip and value < min(budgets[action]['medianMs'], budgets[action]['maxMs']):
                return action, spec['largeSize'], int(value * 1000)
        raise AssertionError('No growth-only synthetic action')

    def fail_growth(self):
        self.action, size, value = self.growth_only_action()
        self.slow(self.report, self.action, size, value)
        self.labels = self.recompute(self.report)
        self.assertEqual(self.labels, ['task-own-history:scaling:' + self.action])
        for key in ('timingLimitsPassed', 'measurementCompleted', 'allPinsMatch'):
            del self.report[key]
        self.report.update(correctnessAccepted=False, releaseGateAccepted=False, error=receipt.TIMING_FAILURE)

    def prior(self):
        self.prior_request = {**copy.deepcopy(self.request), 'requestId': '3' * 32, 'issuedAtUTC': '2026-10-24T00:00:00Z'}
        self.prior_report = copy.deepcopy(self.report)
        self.prior_report.update(startedAtUTC='2026-10-24T00:00:01Z', finishedAtUTC='2026-10-24T00:10:00Z')
        self.prior_report['referenceBinding'].update(requestId=self.prior_request['requestId'],
                                                    requestSHA256=receipt.canonical_digest(self.prior_request))
        self.prior_path = self.repo / 'evidence/synthetic-prior-gate-result.json'
        write(self.prior_path, self.prior_report)
        diagnostic = {'schemaVersion': 1, 'kind': 'reference-failure-diagnostic-v1',
                      'priorRequestId': self.prior_request['requestId'], 'relevantSourceSHA256': self.identity['sha256'],
                      'reproduced': False, 'recordedAtUTC': '2026-10-24T02:00:00Z',
                      'runs': [{'role': 'diagnostic', 'qualifying': False, 'resultSHA256': 'd' * 64,
                                'startedAtUTC': '2026-10-24T01:00:00Z', 'finishedAtUTC': '2026-10-24T01:30:00Z',
                                'checkedFailures': list(self.labels), 'reproducedFailures': []}]}
        self.authorization = receipt.official_rerun(self.repo, self.request, self.prior_request, self.prior_report,
                                                    receipt.digest(self.prior_path), diagnostic)
        self.prior_path.unlink()

    def publish(self, record=None):
        if self.root.exists():
            shutil.rmtree(self.root)
        shutil.copytree(self.bundle, self.root, ignore=shutil.ignore_patterns('qualification.json'))
        write(self.root / 'request.json', self.request)
        write(self.root / 'gate-result.json', self.report)
        write(self.root / 'cleanup.json', self.cleanup)
        write(self.root / receipt.PRIOR_RESULT, self.prior_report)
        write(self.root / receipt.AUTHORIZATION, self.authorization)
        files = {p.relative_to(self.root).as_posix(): receipt.digest(p) for p in self.root.rglob('*') if p.is_file()}
        measured = {}
        for item in self.report['pairedScalingAttempts']:
            measured.update({item['comparison'] + ':' + f: item['comparisons'][f.removeprefix('scaling:')]
                             for f in item['failures'] if item['status'] == 'timing-failed'})
        base = receipt.committed_identity(self.repo, self.base_revision, receipt.IDENTITY_V1)
        current = receipt.source_identity(self.repo, receipt.IDENTITY_V1)
        value = {'schemaVersion': 1, 'kind': 'reference-performance-owner-override-v1', 'state': override.STATE,
                 'referencePerformanceQualified': False, 'release': '2026.10.7+101',
                 'sourceRevision': self.base_revision, 'relevantSourceSHA256': self.identity['sha256'],
                 'requestId': self.request['requestId'], 'requestSHA256': receipt.canonical_digest(self.request),
                 'resultSHA256': files['gate-result.json'], 'priorRequestId': self.prior_request['requestId'],
                 'priorResultSHA256': files[receipt.PRIOR_RESULT], 'limitsSHA256': self.host['limitsSHA256'],
                 'budgetsChanged': False, 'acceptedFailures': self.labels, 'acceptedMeasurements': measured,
                 'owner': {'name': 'Lee', 'role': 'release owner', 'acceptedAtUTC': '2026-10-25T01:00:00Z'},
                 'scope': 'synthetic', 'files': files,
                 'permittedDelta': {p: v for p, v in current['files'].items() if base['files'].get(p) != v}}
        value.update(record or {})
        self.record = value
        write(self.root / override.RECORD, value)

    def verify(self, policy=None):
        return override.verify_override(self.repo, self.root, policy or self.policy)

    def refused(self, pattern=None):
        with self.assertRaisesRegex(ValueError, pattern or ''):
            self.verify()


class OwnerOverrideTests(OwnerOverrideFixture):
    def test_exact_failure_is_accepted_for_one_release_but_never_qualified(self):
        result = self.verify()
        self.assertEqual(result['state'], 'OWNER_OVERRIDE_ACCEPTED_NOT_QUALIFIED')
        self.assertIs(result['referencePerformanceQualified'], False)
        self.assertIs(result['qualificationFailed'], True)
        self.assertEqual(result['ownerAcceptedFailures'], self.labels)
        self.assertEqual(result['permittedDeltaPaths'], ['tool/performance/policy_marker.py'])
        with self.assertRaises(ValueError):
            receipt.validate_report(self.repo, self.report, self.request, self.host)

    def test_verify_cli_reports_the_override_and_never_a_pass(self):
        target = self.repo / receipt.OWNER_OVERRIDE
        self.assertEqual(target, self.root)
        out, err = io.StringIO(), io.StringIO()
        with patch.object(override, 'POLICY', self.policy), \
                patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(self.repo)]), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            receipt.main()
        self.assertEqual(json.loads(out.getvalue())['state'], override.STATE)
        self.assertIn('NOT qualified', err.getvalue())
        with patch.object(sys, 'argv', ['reference_receipt.py', 'verify', '--repo', str(self.repo)]), \
                contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(ValueError, 'exact release policy'):
            receipt.main()

    def test_other_version_or_release_policy_refuses(self):
        self.publish({'release': '2026.10.8+102'})
        self.refused('exact release policy: release')
        self.publish()
        with self.assertRaisesRegex(ValueError, 'exact release policy: release'):
            self.verify({**self.policy, 'release': '2026.10.7+100'})
        head = self.head()
        (self.repo / 'pubspec.yaml').write_text('name: tandemlog\nversion: 2026.10.8+102\n')
        self.commit(); self.publish()
        self.refused('applies only to 2026.10.7\\+101')
        subprocess.run(['git', '-C', str(self.repo), 'reset', '-q', '--hard', head], check=True)
        (self.repo / 'pubspec.yaml').write_text('name: tandemlog\nversion: 2026.10.7+101\n# rebuilt\n')
        self.commit(); self.publish()
        self.refused('outside the reviewed override policy files: pubspec.yaml')

    def test_product_bytes_mode_removal_or_dirty_source_refuse(self):
        for change, pattern in [
                (lambda: (self.repo / 'lib/a.dart').write_text('const a = 2;\n'), 'outside the reviewed.*lib/a.dart'),
                (lambda: (self.repo / 'lib/b.dart').write_text('const b = 1;\n'), 'outside the reviewed.*lib/b.dart'),
                (lambda: (self.tools / 'limits-v1.json').write_text('{}\n'), 'limits differ'),
                (lambda: (self.tools / 'benchmark.dart').unlink(), 'file removed'),
                # Windows checkouts have no executable bit, so mode pins are exercised on POSIX only.
                *([(lambda: (self.repo / 'lib/a.dart').chmod(0o755), 'outside the reviewed.*lib/a.dart')]
                  if POSIX_MODES else [])]:
            with self.subTest(pattern=pattern):
                head = self.head()
                change(); subprocess.run(['git', '-C', str(self.repo), 'add', '-A'], check=True); self.commit()
                self.publish()
                self.refused(pattern)
                subprocess.run(['git', '-C', str(self.repo), 'reset', '-q', '--hard', head], check=True)
                self.publish(); self.verify()
        (self.repo / 'lib/a.dart').write_text('dirty\n')
        self.refused('dirty or untracked')

    def test_reviewed_policy_file_bytes_and_modes_are_pinned(self):
        self.marker.write_text('# changed after review\n'); self.commit()
        self.refused('Reviewed policy-file bytes/modes differ')
        self.publish(); self.verify()
        if POSIX_MODES:
            self.marker.chmod(0o755); self.commit()
            self.refused('Reviewed policy-file bytes/modes differ')
        self.publish({'permittedDelta': {}})
        self.refused('Reviewed policy-file')

    def test_success_state_or_budget_cannot_be_manufactured(self):
        original = copy.deepcopy(self.report)
        for change in [lambda r: r.update(correctnessAccepted=True), lambda r: r.update(timingLimitsPassed=False),
                       lambda r: r.update(releaseGateAccepted=True), lambda r: r.update(measurementCompleted=True),
                       lambda r: r.update(error='Correctness/coverage failed; retry prohibited'),
                       lambda r: r.update(timingRole='hosted-advisory'), lambda r: r.update(measureOnly=True)]:
            self.report = copy.deepcopy(original); change(self.report); self.publish()
            with self.subTest(report=self.report.get('error')):
                self.refused()
        self.report = original
        for change in [{'state': 'QUALIFIED'}, {'referencePerformanceQualified': True}, {'budgetsChanged': True},
                       {'limitsSHA256': '0' * 64}, {'extra': True}]:
            self.publish(change)
            with self.subTest(record=change):
                self.refused()

    def test_timing_tamper_or_other_failure_set_refuses(self):
        original = copy.deepcopy(self.report)
        self.slow(self.report, self.action, self.report['pairedScalingAttempts'][0]['largeSize'], 1000)
        self.publish()
        self.refused('Absolute correctness/coverage/summary differs')
        self.recompute(self.report); self.publish()
        self.refused('Failure labels differ')
        self.report = copy.deepcopy(original)
        other, size, value = self.growth_only_action(skip={self.action})
        self.slow(self.report, other, size, value)
        self.recompute(self.report); self.publish()
        self.refused('owner-accepted failures')
        self.report = copy.deepcopy(original)
        self.publish({'acceptedMeasurements': {self.labels[0]: {'largeMedianMs': 1}}})
        self.refused('Accepted measurement differs')
        self.publish({'acceptedFailures': self.labels + ['dense-1:task.title.save']})
        self.refused('exact release policy: acceptedFailures')

    def test_absolute_failure_is_not_the_accepted_failure(self):
        size = 'dense-1'
        budget = self.limits['actionsBySize'][size]['task.title.save']
        self.slow(self.report, 'task.title.save', size, int(budget['maxMs'] * 1000) + 1000)
        self.recompute(self.report); self.publish()
        self.refused()

    def test_correctness_execution_or_fixture_tamper_refuses(self):
        original = copy.deepcopy(self.report)
        for number, (change, consistent) in enumerate([
                (lambda r: r['attempts'][0]['result'].update(correctnessPassed=False), True),
                (lambda r: r['attempts'][0]['result']['observations'].pop(), True),
                (lambda r: r['attempts'][0]['execution'].update(exitCode=1), False),
                (lambda r: r['attempts'][0]['execution'].update(childGroupAbsent=False), False),
                (lambda r: r['fixtures']['dense-2']['generation'].update(exitCode=1), False),
                (lambda r: r['compile'].update(childAbsent=False), False),
                (lambda r: r['attempts'][1]['binding'].update(binary='c' * 64), False),
                (lambda r: r.update(rerunsUsed=1), False)]):
            self.report = copy.deepcopy(original); change(self.report)
            if consistent:
                self.recompute(self.report)
            self.publish()
            with self.subTest(change=number):
                self.refused()
        self.report = copy.deepcopy(original)
        self.publish()
        fixture = self.root / 'fixture-dense-2/fixture.json'
        contract = receipt.read(fixture); contract['currentStateSHA256'] = 'f' * 64
        write(fixture, contract)
        self.refused('member changed')
        self.report['fixtures']['dense-2']['contract'] = contract
        write(self.bundle / 'fixture-dense-2/fixture.json', contract)
        self.report['fixtures']['dense-2']['manifestSHA256'] = receipt.digest(self.bundle / 'fixture-dense-2/fixture.json')
        for attempt in self.report['attempts']:
            attempt['binding']['fixtures']['dense-2'] = self.report['fixtures']['dense-2']['manifestSHA256']
        self.publish()
        self.refused('Growth correctness')

    def test_cleanup_errors_beyond_the_failed_workload_refuse(self):
        original = copy.deepcopy(self.cleanup)
        for key, value in [('errors', override.FAILED_WORKLOAD_CLEANUP_ERRORS + ['unit still active']), ('errors', []),
                           ('ownedProcessesAbsent', False), ('oomKills', 1), ('verifiedCompletionCapture', True),
                           ('completedAtUTC', '2026-10-25T00:30:00Z')]:
            self.cleanup = {**copy.deepcopy(original), key: value}; self.publish()
            with self.subTest(key=key):
                self.refused()
        self.cleanup = original
        self.publish({'owner': {'name': 'Lee', 'role': 'release owner', 'acceptedAtUTC': '2026-10-25T00:00:02Z'}})
        self.refused('must follow')

    def test_official_rerun_prior_failure_and_inventory_are_bound(self):
        self.prior_report['attempts'][0]['execution']['exitCode'] = 1
        self.publish()
        self.refused('cannot be rerun')
        self.prior_report['attempts'][0]['execution']['exitCode'] = 0
        self.authorization = {**self.authorization, 'ordinal': 3}; self.publish()
        self.refused('limit exceeded')
        self.authorization['ordinal'] = 2; self.publish(); self.verify()
        (self.root / 'extra.json').write_text('{}\n')
        self.refused('inventory differs')
        self.publish()
        (self.root / 'compile.log').write_bytes(b'changed')
        self.refused('member changed')


if __name__ == '__main__':
    unittest.main()
