"""Prospective policy/receipt regressions. All benchmark reports here are synthetic."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import contextlib
import io
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent / 'performance'
sys.path.insert(0, str(TOOLS))
import gate_policy
import run_gate
import reference_receipt as receipt


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + '\n')


class AdvisoryPolicyTests(unittest.TestCase):
    def test_only_timing_can_be_advisory(self):
        yes = gate_policy.Evaluation('passed', (), {})
        timing = gate_policy.Evaluation('timing-failed', ('save',), {})
        bad = gate_policy.Evaluation('correctness-failed', ('coverage',), {})
        self.assertTrue(gate_policy.may_complete_with_advisory_timing([yes, timing]))
        for values in ([], [yes, bad], [timing, bad], [gate_policy.Evaluation('unknown', (), {})]):
            self.assertFalse(gate_policy.may_complete_with_advisory_timing(values))

    def test_modes_and_reference_request_cannot_disguise_calibration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = [sys.executable, str(TOOLS / 'run_gate.py')]
            for option in ('repo', 'dart', 'native-library', 'sqlite-library', 'output'):
                base.extend(['--' + option, str(root / option)])
            for flags in (['--hosted-advisory', '--measure-only'],
                          ['--hosted-advisory', '--diagnose-costs'],
                          ['--hosted-advisory', '--reference-request', str(root / 'request')],
                          ['--measure-only', '--reference-request', str(root / 'request')]):
                result = subprocess.run(base + flags, capture_output=True, text=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('runner requires Linux', result.stderr)
                self.assertFalse((root / 'output').exists())

    def test_non_linux_runner_still_refuses_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            command = ['run_gate.py']
            for option in ('repo', 'dart', 'native-library', 'sqlite-library', 'output'):
                command.extend(['--' + option, str(root / option)])
            with patch.object(sys, 'argv', command), patch.object(sys, 'platform', 'win32'), \
                    contextlib.redirect_stderr(io.StringIO()) as errors:
                with self.assertRaises(SystemExit) as raised:
                    run_gate.main()
            self.assertEqual(raised.exception.code, 2)
            self.assertIn('runner requires Linux', errors.getvalue())
            self.assertFalse((root / 'output').exists())


class ReferenceReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.tools = self.repo / 'tool/performance'
        self.tools.mkdir(parents=True)
        (self.repo / 'lib').mkdir()
        (self.repo / 'lib/a.dart').write_text('const a = 1;\n')
        (self.tools / 'benchmark.dart').write_text("import 'package:tandemlog/a.dart';\n")
        (self.repo / 'pubspec.yaml').write_text('name: tandemlog\n')
        (self.repo / 'pubspec.lock').write_text('synthetic locked test dependencies\n')
        self.limits = json.loads((TOOLS / 'limits-v1.json').read_text())
        write(self.tools / 'limits-v1.json', self.limits)
        write(self.tools / 'coverage-v1.json', json.loads((TOOLS / 'coverage-v1.json').read_text()))
        self.tool_hashes = {name: hashlib.sha256(name.encode()).hexdigest() for name in
                            ('/bin/dart', '/bin/utils/gen_snapshot', '/libtandemlog_text.so', '/libsqlite3.so')}
        self.tool_hashes['/tool/performance/limits-v1.json'] = receipt.digest(self.tools / 'limits-v1.json')
        self.bounds = {'memory.max': str(6 * 1024**3), 'memory.swap.max': '0',
                       'cpu.max': '200000 100000', 'pids.max': '128'}
        environment = {'architecture': 'x86_64', 'kernel': 'test-kernel', 'python': 'test-python',
                       'logicalCPUs': 16, 'cpuModel': 'test CPU', 'filesystemType': 'ext4'}
        self.controller = self.repo / 'evidence/synthetic-controller.py'
        self.controller.parent.mkdir()
        self.controller.write_text('# synthetic controller marker;never executed\n')
        self.host = {'schemaVersion': 1, 'status': 'registered', 'hostId': 'farnsworth',
                     'hardwareMultiplier': 1, 'environment': environment, 'controllerSHA256': receipt.digest(self.controller),
                     'resourceBounds': self.bounds, 'limitsSHA256': self.tool_hashes['/tool/performance/limits-v1.json'],
                     'pubspecLockSHA256': receipt.digest(self.repo / 'pubspec.lock'), 'toolHashes': self.tool_hashes,
                     'packageContractSHA256': hashlib.sha256(b'package-contract').hexdigest(), 'packageNames': ['tandemlog']}
        compiled = {'/repo/.dart_tool/package_config.json': 'original-config',
                    '/stage/.dart_tool/package_config.json': 'staged-config',
                    '/sdk/bin/cache/dart-sdk/bin/utils/gen_snapshot': self.tool_hashes['/bin/utils/gen_snapshot'],
                    '/cache/hosted/pub.dev/test-1.0/lib/test.dart': 'dependency'}
        toolpins = {'/sdk/bin/cache/dart-sdk/bin/dart': self.tool_hashes['/bin/dart'],
                    '/stage/.dart_tool/package_config.json': 'staged-config',
                    '/native/libtandemlog_text.so': self.tool_hashes['/libtandemlog_text.so'],
                    '/sqlite/libsqlite3.so': self.tool_hashes['/libsqlite3.so'],
                    '/repo/tool/performance/limits-v1.json': self.tool_hashes['/tool/performance/limits-v1.json']}
        # One marker binds the root used by source_pins/compiled inventory.
        (self.tools / 'run_gate.py').write_text('# synthetic marker, never executed\n')
        marker = {'/repo/tool/performance/run_gate.py': receipt.digest(self.tools / 'run_gate.py')}
        self.host['compiledDependencies'] = receipt.compiled_inventory(
            {'toolPins': toolpins, 'sourcePins': marker, 'compiledSourceAndDependencyPins': compiled})[1]
        write(self.repo / receipt.PROFILE, self.host)
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'config', 'user.name', 'Receipt Test'], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'config', 'user.email', 'receipt@example.invalid'], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'config', 'core.autocrlf', 'false'], check=True)
        self.commit()
        self.identity = receipt.source_identity(self.repo)
        self.request = {'schemaVersion': 1, 'purpose': 'controlled-reference-performance-v1', 'requestId': '1' * 32,
                        'issuedAtUTC': '2026-10-25T00:00:00Z', 'sourceRevision': self.head(),
                        'relevantSource': self.identity, 'hostProfileSHA256': receipt.digest(self.repo / receipt.PROFILE),
                        'controllerSHA256': self.host['controllerSHA256'], 'controllerPath': str(self.controller)}
        # Reports originate on Linux even when the receipt validator runs on Windows.
        pins = {'/repo/' + Path(p).relative_to(self.repo).as_posix(): value
                for p, value in run_gate.source_pins(self.repo, self.tools).items()}
        originals = {p.relative_to(self.repo).as_posix(): receipt.digest(p) for p in (self.repo / 'lib').rglob('*') if p.is_file()}
        originals.update({p: receipt.digest(self.repo / p) for p in ('pubspec.yaml', 'pubspec.lock')})
        compiled.update({'/stage/' + name: value for name, value in originals.items()})
        self.bundle = self.repo / receipt.QUALIFICATION
        self.bundle.mkdir(parents=True)
        self.log = b'synthetic regression log, not an execution\n'
        self.log_sha = hashlib.sha256(self.log).hexdigest()
        execution = {'exitCode': 0, 'childAbsent': True, 'logSHA256': self.log_sha, 'noise': {}}
        fixtures = copy.deepcopy(json.loads((TOOLS.parents[1] / 'evidence/rc4-cloud-attribution-20261024/reference-034a57d-pins.json').read_text())['fixtures'])
        fixture_items = {}
        for size, contract in fixtures.items():
            contract['workspace'] = '/synthetic/' + size
            path = self.bundle / ('fixture-' + size) / 'fixture.json'
            write(path, contract)
            fixture_items[size] = {'contract': contract, 'manifestSHA256': receipt.digest(path), 'generation': execution.copy()}
            (self.bundle / (size + '-generate.log')).write_bytes(self.log)
        binding = {'source': hashlib.sha256(json.dumps(pins, sort_keys=True).encode()).hexdigest(),
                   'binary': 'b' * 64, 'limits': self.host['limitsSHA256'],
                   'fixtures': {s: v['manifestSHA256'] for s, v in fixture_items.items()}}
        self.report = {'correctnessAccepted': True, 'measurementCompleted': True, 'allPinsMatch': True,
                       'releaseGateAccepted': True, 'timingLimitsPassed': True, 'timingRole': 'enforcing',
                       'measureOnly': False, 'costDiagnosticsEnabled': False, 'resourceBounds': self.bounds,
                       'startedAtUTC': '2026-10-25T00:00:01Z', 'finishedAtUTC': '2026-10-25T00:00:02Z',
                       'referenceBinding': {'requestId': self.request['requestId'],
                           'requestSHA256': receipt.canonical_digest(self.request),
                           'relevantSourceSHA256': self.identity['sha256'],
                           'hostProfileSHA256': self.request['hostProfileSHA256'],
                           'environment': environment, 'controllerSHA256': self.host['controllerSHA256']},
                       'sourceRewrites': [], 'shimAllowlist': [], 'sourcePins': pins, 'toolPins': toolpins,
                       'compiledSourceAndDependencyPins': compiled,
                       'compiledFileSeals': {n: {'originalSHA256': v, 'compiledSHA256': v, 'change': 'none'}
                                             for n, v in originals.items()},
                       'projectImportClosure': ['/repo/tool/performance/benchmark.dart', '/stage/lib/a.dart'],
                       'packageContractSHA256': self.host['packageContractSHA256'], 'rerunsUsed': 0,
                       'compile': execution.copy(), 'binaryMode': '0o700', 'binarySHA256': binding['binary'],
                       'fixtures': fixture_items, 'attempts': [], 'pairedScalingAttempts': []}
        effective = {**self.limits, 'sha256': self.host['limitsSHA256']}
        summaries = {}
        for size in fixtures:
            rows = [{'action': a, 'index': i, 'warmup': i < 2, 'microseconds': 1000}
                    for a in self.limits['actionsBySize'][size] for i in range(7)]
            result = {'size': size, 'correctnessPassed': True, 'limitsSHA256': effective['sha256'], 'observations': rows}
            decision = gate_policy.evaluate(result, effective)
            summaries[size] = decision.summaries
            self.report['attempts'].append({'size': size, 'attempt': 0, 'execution': execution.copy(), 'binding': binding,
                                           'result': result, 'status': decision.status,
                                           'failures': list(decision.failures), 'summaries': decision.summaries})
            (self.bundle / (size + '-attempt-0.log')).write_bytes(self.log)
        for name, spec in run_gate.scaling_specs(self.limits).items():
            decision = gate_policy.evaluate_scaling(summaries, spec, fixtures)
            self.assertEqual(decision.status, 'passed')
            self.report['pairedScalingAttempts'].append({'attempt': 0, 'comparison': name,
                'smallSize': spec['smallSize'], 'largeSize': spec['largeSize'], 'status': decision.status,
                'failures': list(decision.failures), 'comparisons': decision.summaries})
        self.cleanup = {'requestId': self.request['requestId'], 'controllerSHA256': self.host['controllerSHA256'],
                        'ownedUnitsInactive': True, 'ownedProcessesAbsent': True, 'inputPinsUnchanged': True,
                        'withinDeadline': True, 'activeProcesses': 0, 'workloadSwapBytes': 0, 'oomKills': 0,
                        'completedAtUTC': '2026-10-25T00:00:03Z', 'deadlineUTC': '2026-10-25T00:25:00Z', 'errors': []}
        (self.bundle / 'compile.log').write_bytes(self.log)
        self.refresh()

    def commit(self):
        subprocess.run(['git', '-C', str(self.repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'commit', '-qm', 'synthetic receipt test'], check=True)

    def head(self):
        return subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()

    def refresh(self):
        write(self.bundle / 'request.json', self.request)
        write(self.bundle / 'gate-result.json', self.report)
        write(self.bundle / 'cleanup.json', self.cleanup)
        files = {p.relative_to(self.bundle).as_posix(): receipt.digest(p)
                 for p in self.bundle.rglob('*') if p.is_file() and p.name != 'qualification.json'}
        write(self.bundle / 'qualification.json', {'schemaVersion': 1, 'requestId': self.request['requestId'],
              'files': files, 'binarySHA256VerifiedAtExport': self.report['binarySHA256'],
              'fixtureBytesVerifiedAtExport': True})

    def verify(self):
        return receipt.verify_bundle(self.repo, self.bundle)

    def test_fresh_complete_source_bound_receipt_passes(self):
        self.assertTrue(self.verify()['referencePerformanceQualified'])
        self.assertFalse(self.verify()['releaseOrNativeUIAccepted'])

    def test_documentation_successor_is_allowed_but_code_change_is_stale(self):
        (self.repo / 'README.md').write_text('documentation only\n')
        self.commit()
        self.verify()
        (self.repo / 'lib/a.dart').write_text('const a = 2;\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'stale/mismatched'):
            self.verify()

    def test_missing_bundle_and_missing_manifest_fail_closed(self):
        with self.assertRaises(ValueError):
            receipt.verify_bundle(self.repo, self.repo / 'missing')
        (self.bundle / 'qualification.json').unlink()
        with self.assertRaises(ValueError):
            self.verify()

    def test_measure_only_advisory_incomplete_or_historical_never_qualify(self):
        original = copy.deepcopy(self.report)
        for key, value in [('measureOnly', True), ('timingRole', 'hosted-advisory'),
                           ('measurementCompleted', False), ('correctnessAccepted', False),
                           ('costDiagnosticsEnabled', True), ('referenceBinding', {})]:
            self.report = copy.deepcopy(original); self.report[key] = value; self.refresh()
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()

    def test_tampered_log_does_not_pass_a_report_hash(self):
        (self.bundle / 'compile.log').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'member changed'):
            self.verify()
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'execution log'):
            self.verify()

    def test_tool_or_dependency_byte_change_is_mandatory_failure(self):
        original = copy.deepcopy(self.report)
        for key, path in [('toolPins', '/native/libtandemlog_text.so'),
                          ('compiledSourceAndDependencyPins', '/cache/hosted/pub.dev/test-1.0/lib/test.dart')]:
            self.report = copy.deepcopy(original); self.report[key][path] = 'changed'; self.refresh()
            with self.assertRaises(ValueError):
                receipt.check_reference_toolchain(self.report, self.host)
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()

    def test_resource_environment_request_and_time_mismatches_fail(self):
        original = copy.deepcopy(self.report)
        for change in [lambda r: r['resourceBounds'].update({'memory.swap.max': '1'}),
                       lambda r: r['referenceBinding']['environment'].update({'kernel': 'other'}),
                       lambda r: r['referenceBinding'].update({'requestId': '2' * 32}),
                       lambda r: r.update(startedAtUTC='2026-10-24T23:59:59Z')]:
            self.report = copy.deepcopy(original); change(self.report); self.refresh()
            with self.assertRaises(ValueError):
                self.verify()

    def test_missing_sample_generation_or_growth_pair_fails(self):
        original = copy.deepcopy(self.report)
        for change in [lambda r: r['attempts'][0]['result']['observations'].pop(),
                       lambda r: r['fixtures']['dense-1']['generation'].update({'exitCode': 1}),
                       lambda r: r['pairedScalingAttempts'].pop(),
                       lambda r: r['pairedScalingAttempts'][0].update({'attempt': 99}),
                       lambda r: r['attempts'][0]['binding']['fixtures'].update({'dense-1': 'changed'})]:
            self.report = copy.deepcopy(original); change(self.report); self.refresh()
            with self.assertRaises(ValueError):
                self.verify()

    def test_bad_absolute_or_growth_result_cannot_be_relabelled_passed(self):
        self.report['attempts'][0]['result']['observations'][-1]['microseconds'] = 10000000
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'Absolute'):
            self.verify()

    def test_retry_without_external_noise_is_rejected(self):
        self.report['rerunsUsed'] = 1
        for key in ('attempts', 'pairedScalingAttempts'):
            second = copy.deepcopy(self.report[key])
            for item in second:
                item['attempt'] = 1
            self.report[key].extend(second)
        self.refresh()
        with self.assertRaisesRegex(ValueError, 'retry lacks'):
            self.verify()

    def test_cleanup_is_required_and_false_or_boolean_counters_fail(self):
        original = copy.deepcopy(self.cleanup)
        for key, value in [('ownedUnitsInactive', False), ('activeProcesses', 1),
                           ('workloadSwapBytes', False), ('oomKills', 1),
                           ('errors', ['unverified']), ('completedAtUTC', '2026-10-25T00:30:00Z')]:
            self.cleanup = copy.deepcopy(original); self.cleanup[key] = value; self.refresh()
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()

    def test_dirty_or_untracked_source_cannot_reuse_receipt(self):
        (self.repo / 'lib/untracked.dart').write_text('untracked\n')
        with self.assertRaisesRegex(ValueError, 'dirty or untracked'):
            self.verify()

    def test_request_preflight_checks_actual_host_and_caps(self):
        with patch.object(receipt, 'fingerprint', return_value=self.host['environment']):
            value = receipt.request_context(self.repo, self.bundle / 'request.json', self.repo, self.bounds)
            self.assertEqual(value['requestSHA256'], receipt.canonical_digest(self.request))
            with self.assertRaisesRegex(ValueError, 'resource bounds'):
                receipt.request_context(self.repo, self.bundle / 'request.json', self.repo, {})
        with patch.object(receipt, 'fingerprint', return_value={**self.host['environment'], 'kernel': 'other'}):
            with self.assertRaisesRegex(ValueError, 'environment differs'):
                receipt.request_context(self.repo, self.bundle / 'request.json', self.repo, self.bounds)

    def test_request_controller_cannot_change_after_review(self):
        self.controller.write_text('changed controller\n')
        with patch.object(receipt, 'fingerprint', return_value=self.host['environment']):
            with self.assertRaisesRegex(ValueError, 'controller bytes changed'):
                receipt.request_context(self.repo, self.bundle / 'request.json', self.repo, self.bounds)

    def test_pending_host_and_claimed_binary_export_are_not_acceptance(self):
        host = {**self.host, 'status': 'pending'}
        write(self.repo / receipt.PROFILE, host)
        with self.assertRaisesRegex(ValueError, 'not registered'):
            self.verify()
        write(self.repo / receipt.PROFILE, self.host)
        manifest = receipt.read(self.bundle / 'qualification.json')
        manifest['binarySHA256VerifiedAtExport'] = 'different'
        write(self.bundle / 'qualification.json', manifest)
        with self.assertRaisesRegex(ValueError, 'binary/fixture'):
            self.verify()

    def test_unknown_request_role_or_malformed_nonce_fails(self):
        original = copy.deepcopy(self.request)
        for key, value in [('purpose', 'historical-comparison'), ('requestId', 'old')]:
            self.request = {**original, key: value}
            self.report['referenceBinding']['requestId'] = self.request['requestId']
            self.report['referenceBinding']['requestSHA256'] = receipt.canonical_digest(self.request)
            self.refresh()
            with self.assertRaises(ValueError):
                self.verify()

    def test_export_roundtrip_checks_owned_binary_and_fixture_bytes(self):
        run = self.repo / 'evidence/synthetic-owned-run'
        run.mkdir()
        binary = run / 'benchmark'
        binary.write_bytes(b'synthetic executable marker, never executed')
        binary.chmod(0o700)
        self.report['binarySHA256'] = receipt.digest(binary)
        for size, item in self.report['fixtures'].items():
            folder = run / ('fixture-' + size)
            workspace = folder / 'workspace'; workspace.mkdir(parents=True)
            (workspace / 'synthetic.applog').write_bytes(b'synthetic fixture marker')
            item['contract']['workspace'] = str(workspace)
            item['contract']['files'] = {'synthetic.applog': receipt.digest(workspace / 'synthetic.applog')}
            write(folder / 'fixture.json', item['contract'])
            item['manifestSHA256'] = receipt.digest(folder / 'fixture.json')
        for attempt in self.report['attempts']:
            attempt['binding']['binary'] = self.report['binarySHA256']
            attempt['binding']['fixtures'] = {s: v['manifestSHA256'] for s, v in self.report['fixtures'].items()}
        for path in self.bundle.glob('*.log'):
            (run / path.name).write_bytes(path.read_bytes())
        write(run / 'gate-result.json', self.report)
        output = self.repo / 'evidence/synthetic-export'
        command = ['reference_receipt.py', 'seal', '--repo', str(self.repo),
                   '--request', str(self.bundle / 'request.json'), '--cleanup', str(self.bundle / 'cleanup.json'),
                   '--run', str(run), '--output', str(output)]
        with patch.object(sys, 'argv', command), contextlib.redirect_stdout(io.StringIO()):
            receipt.main()
        self.assertTrue(receipt.verify_bundle(self.repo, output)['referencePerformanceQualified'])
        self.assertFalse((output / 'benchmark').exists())


class ReferenceReceiptAliasTests(unittest.TestCase):
    def test_fixture_canonicalizes_aliased_temporary_root(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        (root / 'alias-step').mkdir()
        alias = str(root / 'alias-step' / '..')
        fixture = ReferenceReceiptTests(methodName='test_fresh_complete_source_bound_receipt_passes')
        self.addCleanup(fixture.doCleanups)
        # Reproduce resolved source pins against a lexically different temp
        # root without requiring Windows 8.3 aliases or symlink privileges.
        with patch.object(temporary, 'name', alias), \
                patch.object(tempfile, 'TemporaryDirectory', return_value=temporary):
            fixture.setUp()
        self.assertEqual(fixture.repo, root)
        self.assertTrue(fixture.verify()['referencePerformanceQualified'])


@unittest.skipUnless(sys.platform.startswith('linux'), 'Synthetic orchestration exercises the Linux-only AOT runner')
class HostedRunnerTests(unittest.TestCase):
    def run_synthetic_runner(self, failure):
        fixture = ReferenceReceiptTests(methodName='test_fresh_complete_source_bound_receipt_passes')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        repo, tools = fixture.repo, fixture.tools
        config = {'configVersion': 2, 'packages': [{'name': 'tandemlog', 'rootUri': repo.as_uri() + '/',
                                                   'packageUri': 'lib/', 'languageVersion': '3.13'}]}
        write(repo / '.dart_tool/package_config.json', config)
        sdk = repo / 'sdk/bin/cache/dart-sdk'
        for name in ('bin/dart', 'bin/utils/gen_snapshot', 'lib/_internal/vm_platform_strong.dill'):
            path = sdk / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(b'synthetic tool input')
        for name in ('native.so', 'sqlite.so'):
            (repo / name).write_bytes(b'synthetic library input')
        output = repo / 'hosted-output'
        command = ['run_gate.py', '--repo', str(repo), '--dart', str(sdk / 'bin/dart'),
                   '--native-library', str(repo / 'native.so'), '--sqlite-library', str(repo / 'sqlite.so'),
                   '--output', str(output), '--expected-limits-sha256', receipt.digest(tools / 'limits-v1.json'),
                   '--hosted-advisory']
        measured = {a['size']: copy.deepcopy(a['result']['observations']) for a in fixture.report['attempts']}
        if failure == 'absolute timing':
            for rows in measured.values():
                for row in rows:
                    row['microseconds'] = 10000000
        if failure == 'paired timing':
            for row in measured['dense-2']:
                if row['action'] == 'task.title.save':
                    row['microseconds'] = 20000
        def child(args, log, env, timeout):
            log.write_bytes(b'synthetic runner control-flow test, never an executed benchmark\n')
            bad = False
            if args[1] == 'compile':
                (output / 'benchmark').write_bytes(b'synthetic executable marker')
            elif args[1] == 'generate':
                folder = Path(args[2]); size = folder.name.removeprefix('fixture-')
                contract = copy.deepcopy(fixture.report['fixtures'][size]['contract'])
                workspace = folder / 'workspace'; workspace.mkdir(parents=True)
                (workspace / 'test.applog').write_bytes(b'synthetic fixture marker')
                contract.update(workspace=str(workspace), files={'test.applog': receipt.digest(workspace / 'test.applog')})
                if failure == 'fixture contract' and size == 'dense-2':
                    contract['currentStateSHA256'] = 'different'
                write(folder / 'fixture.json', contract)
                bad = failure == 'generation exit'
            else:
                bad = failure == 'benchmark exit'
            return {'exitCode': 1 if bad else 0, 'childAbsent': True, 'logSHA256': receipt.digest(log), 'noise': {}}
        def observations(log):
            size = log.name.split('-attempt-')[0]
            return measured[size], failure != 'missing completion'
        real_pins = run_gate.source_pins
        count = 0
        def pins(*args):
            nonlocal count
            count += 1
            value = real_pins(*args)
            return {**value, 'unexpected': 'changed'} if failure == 'source binding' and count > 1 else value
        with patch.object(sys, 'argv', command), patch.object(run_gate, '__file__', str(tools / 'run_gate.py')), \
                patch.object(run_gate, 'run_child', side_effect=child), \
                patch.object(run_gate, 'measurements', side_effect=observations), \
                patch.object(run_gate, 'source_pins', side_effect=pins), \
                patch.object(run_gate, 'actual_resource_bounds', return_value=fixture.bounds):
            status = run_gate.main()
        return status, json.loads((output / 'gate-result.json').read_text())

    def test_hosted_absolute_and_paired_timing_failures_are_retained_advisory(self):
        for kind in ('absolute timing', 'paired timing'):
            with self.subTest(kind=kind):
                status, report = self.run_synthetic_runner(kind)
                self.assertEqual(status, 0, report.get('error'))
                self.assertTrue(report['correctnessAccepted'])
                self.assertTrue(report['allPinsMatch'])
                self.assertTrue(report['measurementCompleted'])
                self.assertFalse(report['timingLimitsPassed'])
                self.assertFalse(report['releaseGateAccepted'])
                self.assertEqual(report['timingRole'], 'hosted-advisory')
                self.assertEqual(report['rerunsUsed'], 0)
                self.assertTrue(any(a['failures'] for a in report['attempts']) or
                                any(p['failures'] for p in report['pairedScalingAttempts']))

    def test_hosted_structural_correctness_and_binding_failures_stay_fatal(self):
        for kind in ('benchmark exit', 'missing completion', 'source binding', 'fixture contract', 'generation exit'):
            with self.subTest(kind=kind):
                status, report = self.run_synthetic_runner(kind)
                self.assertEqual(status, 1)
                self.assertFalse(report['correctnessAccepted'])
                self.assertFalse(report['releaseGateAccepted'])
                self.assertIn('error', report)


if __name__ == '__main__':
    unittest.main()
