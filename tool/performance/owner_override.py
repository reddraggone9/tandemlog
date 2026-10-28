"""Release-owner acceptance of one failed reference qualification. Never a qualification.

The owner may accept a specific, independently recomputed timing-only failure for exactly one
release and source identity. Correctness, coverage, fixture, binding, toolchain and cleanup
checks are re-evaluated here and stay fatal; budgets and limits are untouched. Any other version,
product byte, tool byte, mode, failure set or measurement refuses.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

from gate_policy import evaluate, evaluate_scaling, validate_registered_coverage
from reference_receipt import (need, digest, canonical_digest, read, instant, request_shape, profile,
                               source_identity, committed_identity, check_reference_toolchain,
                               failed_qualification_failures, check_authorization_shape, PROFILE,
                               TIMING_FAILURE, AUTHORIZATION, PRIOR_RESULT, IDENTITY_V1, IDENTITY_V2)

RECORD = 'override.json'
STATE = 'OWNER_OVERRIDE_ACCEPTED_NOT_QUALIFIED'
# Exactly what the failed workload's cleanup reports when run_gate exits 1; nothing else is waived.
FAILED_WORKLOAD_CLEANUP_ERRORS = [
    'RuntimeError: Workload failed; original terminal status and raw result retained',
    'COUNTERS RuntimeError: Original terminal workload not successful']
# Lee accepted dfb2260 at 2026-10-27 14:56 CDT for stable 2026.10.7+101 only.
POLICY = {
    'release': '2026.10.7+101',
    'sourceRevision': 'dfb2260c83c443e867dd1e809c947c1617a30515',
    'relevantSourceSHA256': '4608c4f657317f4960645a77e699f82b972ec4ae4cf779a99b1882339adf3da2',
    'requestId': '6662eaf60ee673b27feb93d624a26f94',
    'priorRequestId': '5b95fb32ceac4a20f43414a27b2c3524',
    'limitsSHA256': '50a606cb302eb6a769c760188901132fb8b35b153ecc41dde11a17c95b39742e',
    'acceptedFailures': ['task-own-history:scaling:sync.peerTask.whileFood.storageAdmission'],
    'allowedDelta': ['tool/performance/owner_override.py', 'tool/performance/reference_receipt.py',
                     'tool/test_owner_override.py'],
}
# Lee accepted 634cd9c at 2026-10-28 16:14 CDT for prerelease 2026.10.9-rc.1+104 only. The q5 official
# rerun of q4 failed one food-own-history growth maximum; profiling attributed it to host NVMe flush stalls.
FOOD_RC1_POLICY = {
    'release': '2026.10.9-rc.1+104',
    'sourceRevision': '634cd9c2d9409e96d31094052d7e3115e4d8a7d2',
    'relevantSourceSHA256': 'eebbe7e10373c1f1c30e9db592ce0d898c75547eb42918ee431fdff66a8f3fcc',
    'requestId': '1f0dd03d23e5cca41d04d732d5d3e463',
    'priorRequestId': 'ed8ff0a62c67b6b5259ba725082f9cfb',
    'limitsSHA256': '894f3af11a2cf642fe8a18aaceeb1cd05077346ac2b3a384b558109676f98409',
    'acceptedFailures': ['food-own-history:scaling:food.details.1'],
    # .gitattributes only keeps a frozen test fixture literal in Windows checkouts; no benchmark input.
    'allowedDelta': ['.gitattributes', 'tool/performance/owner_override.py', 'tool/performance/reference_receipt.py',
                     'tool/test_owner_override.py'],
    'identity': IDENTITY_V2,
}
# Evidence directory -> policy attribute name; each routes only while pubspec is exactly its release.
OVERRIDES = {'evidence/reference-performance/owner-override-stable101': 'POLICY',
             'evidence/reference-performance/owner-override-food-rc1': 'FOOD_RC1_POLICY'}
RECORD_FIELDS = {'schemaVersion', 'kind', 'state', 'referencePerformanceQualified', 'release', 'sourceRevision',
                 'relevantSourceSHA256', 'requestId', 'requestSHA256', 'resultSHA256', 'priorRequestId',
                 'priorResultSHA256', 'limitsSHA256', 'budgetsChanged', 'acceptedFailures', 'acceptedMeasurements',
                 'owner', 'scope', 'permittedDelta', 'files'}


def release_version(repo):
    found = re.findall(r'(?m)^version:\s*(\S+)\s*$', (Path(repo) / 'pubspec.yaml').read_text())
    need(len(found) == 1, 'Exactly one pubspec version required')
    return found[0]


def permitted_delta(repo, base, allowed, scheme=IDENTITY_V1):
    """Current relevant source must equal the accepted source plus only the reviewed policy files."""
    current = source_identity(repo, scheme)
    need(set(base['files']) <= set(current['files']), 'Accepted relevant source file removed')
    delta = {p: v for p, v in current['files'].items() if base['files'].get(p) != v}
    need(set(delta) <= set(allowed), 'Relevant source differs outside the reviewed override policy files: ' +
         ', '.join(sorted(set(delta) - set(allowed))))
    return current, delta


def failing_labels(report):
    last = report['rerunsUsed']
    return sorted({a['size'] + ':' + f for a in report['attempts'] if a['attempt'] == last for f in a['failures']} |
                  {p['comparison'] + ':' + f for p in report['pairedScalingAttempts']
                   if p['attempt'] == last for f in p['failures']})


def validate_failed_report(repo, report, request, host, base):
    """Recompute every absolute/growth/fixture contract of the retained failed report.

    Source pins come from the literal bytes of the request's revision, not the current
    tree, because the permitted delta lives in tool/performance; `base` is that request's
    recorded identity. The failure state itself must be exact: no success flag may be
    present or set. Also used for borderline results (borderline.py).
    """
    from run_gate import scaling_specs, validate_project_imports, may_rerun_all
    repo = Path(repo).resolve()
    request_shape(request)
    need(report.get('correctnessAccepted') is False and report.get('releaseGateAccepted') is False and
         not {'timingLimitsPassed', 'measurementCompleted', 'allPinsMatch'} & set(report) and
         report.get('error') == TIMING_FAILURE,
         'Override requires the original unmodified timing-limit failure state')
    need(report.get('timingRole') == 'enforcing' and report.get('measureOnly') is False and
         report.get('costDiagnosticsEnabled') is False,
         'Advisory/calibration/instrumented result cannot be accepted')
    binding = report.get('referenceBinding', {})
    need(binding.get('requestId') == request['requestId'] and binding.get('requestSHA256') == canonical_digest(request),
         'Reference request binding differs')
    need(binding.get('relevantSourceSHA256') == base['sha256'] == request['relevantSource']['sha256'],
         'Failed result is not bound to the accepted source')
    need(binding.get('hostProfileSHA256') == digest(repo / PROFILE) == request['hostProfileSHA256'] and
         binding.get('environment') == host['environment'], 'Reference environment/profile differs')
    need(binding.get('controllerSHA256') == host['controllerSHA256'] == request['controllerSHA256'],
         'Reference controller differs')
    need(instant(request['issuedAtUTC']) <= instant(report['startedAtUTC']) <= instant(report['finishedAtUTC']),
         'Result predates request or has invalid timestamps')
    need(report['resourceBounds'] == host['resourceBounds'], 'Reference resource bounds differ')
    need(report.get('sourceRewrites') == [] and report.get('shimAllowlist') == [], 'Source rewrite/shim refused')
    files = committed_identity(repo, request['sourceRevision'], IDENTITY_V1)['files']
    expected = {p: v['sha256'] for p, v in files.items()
                if p.startswith(('lib/', 'tool/performance/')) or p in ('pubspec.yaml', 'pubspec.lock')}
    normalized, rename = check_reference_toolchain(report, host)
    actual = {rename(p).removeprefix('project/'): v for p, v in report['sourcePins'].items()}
    need(actual == expected, 'Reference source pin inventory differs from the accepted source')
    originals = {p: v['sha256'] for p, v in files.items() if p.startswith('lib/') or p in ('pubspec.yaml', 'pubspec.lock')}
    seals = report['compiledFileSeals']
    need(set(seals) == set(originals) and all(
        seals[n] == {'originalSHA256': h, 'compiledSHA256': h, 'change': 'none'} for n, h in originals.items()),
        'Compiled project bytes differ')
    need({k.removeprefix('staged/'): v for k, v in normalized.items()
          if k.startswith('staged/') and k != 'staged/.dart_tool/package_config.json'} == originals,
         'Compiled project pin inventory/bytes differ')
    need({k for k in normalized if k.startswith('project/')} == {'project/.dart_tool/package_config.json'},
         'Unexpected original project compilation input')
    imports = validate_project_imports(repo / 'tool/performance/benchmark.dart', repo, host['packageNames'])
    need(all(rename(p).startswith(('staged/', 'project/')) for p in report['projectImportClosure']), 'Import escaped project')
    need(sorted(rename(p).split('/', 1)[1] for p in report['projectImportClosure']) ==
         sorted(Path(p).relative_to(repo).as_posix() for p in imports), 'Compiled project import closure differs')
    limits = read(repo / 'tool/performance/limits-v1.json')
    limits['sha256'] = digest(repo / 'tool/performance/limits-v1.json')
    need(limits['sha256'] == host['limitsSHA256'] == files['tool/performance/limits-v1.json']['sha256'],
         'Limits differ from the accepted source')
    specs = scaling_specs(limits)
    validate_registered_coverage(read(repo / 'tool/performance/coverage-v1.json'), limits, specs)
    attempts, pairs = report['attempts'], report['pairedScalingAttempts']
    need(report['rerunsUsed'] == 0 and type(report['rerunsUsed']) is int and len(attempts) == 3 and
         len(pairs) == len(specs) and all(type(x['attempt']) is int and x['attempt'] == 0 for x in attempts + pairs),
         'Missing/extra/repeated reference attempt')
    need(type(report['compile']['exitCode']) is int and report['compile']['exitCode'] == 0 and
         report['compile']['childAbsent'] is True and report['compile'].get('childGroupAbsent') is True and
         report.get('binaryMode') == '0o700', 'Incomplete compile')
    contracts = {size: item['contract'] for size, item in report['fixtures'].items()}
    need(set(contracts) == set(limits['historySizes']), 'Fixture inventory differs')
    need(all(type(v['generation']['exitCode']) is int and v['generation']['exitCode'] == 0 and
             v['generation']['childAbsent'] is True and v['generation'].get('childGroupAbsent') is True
             for v in report['fixtures'].values()), 'Incomplete fixture generation')
    need(all(c.get('syntheticOnly') is True for c in contracts.values()), 'Fixture is not public synthetic data')
    need({a['size'] for a in attempts} == set(contracts), 'Missing reference size')
    summaries, decisions, executions = {}, {}, {}
    for item in attempts:
        execution = item['execution']
        need(type(execution['exitCode']) is int and execution['exitCode'] == 0 and execution['childAbsent'] is True and
             execution.get('childGroupAbsent') is True, 'Incomplete action execution')
        need(item['result'].get('size') == item['size'], 'Attempt size label differs')
        decision = evaluate(item['result'], limits)
        need(decision.status in ('passed', 'timing-failed') and decision.status == item['status'] and
             list(decision.failures) == item['failures'] and decision.summaries == item['summaries'],
             'Absolute correctness/coverage/summary differs')
        summaries[item['size']], decisions[item['size']], executions[item['size']] = decision.summaries, decision, execution
    need({p['comparison'] for p in pairs} == set(specs), 'Missing/extra growth pair')
    paired = []
    measured = {size + ':' + f: summaries[size][f] for size, d in decisions.items() for f in d.failures}
    for item in pairs:
        rule = specs[item['comparison']]
        need(item['smallSize'] == rule['smallSize'] and item['largeSize'] == rule['largeSize'], 'Growth size labels differ')
        decision = evaluate_scaling(summaries, rule, contracts)
        need(decision.status in ('passed', 'timing-failed') and decision.status == item['status'] and
             list(decision.failures) == item['failures'] and decision.summaries == item['comparisons'],
             'Growth correctness/rules/summary differs')
        paired.append((rule, decision))
        measured.update({item['comparison'] + ':' + f: decision.summaries[f.removeprefix('scaling:')]
                         for f in decision.failures})
    bindings = [a['binding'] for a in attempts]
    need(all(b == bindings[0] for b in bindings) and bindings[0]['binary'] == report['binarySHA256'] and
         bindings[0]['limits'] == limits['sha256'] and
         bindings[0]['fixtures'] == {size: v['manifestSHA256'] for size, v in report['fixtures'].items()} and
         bindings[0]['source'] == hashlib.sha256(json.dumps(report['sourcePins'], sort_keys=True).encode()).hexdigest(),
         'Binary/source/fixture/limits binding changed')
    need(not may_rerun_all(decisions, paired, 0, executions, bindings[0], bindings[0]),
         'Failure was eligible for the in-invocation retry; result is not the final refusal')
    labels = failing_labels(report)
    need(labels and labels == failed_qualification_failures(request, report), 'Failure labels differ')
    return labels, measured


def validate_failed_cleanup(cleanup, report, request, host):
    need(cleanup.get('requestId') == request['requestId'] and cleanup.get('controllerSHA256') == host['controllerSHA256'],
         'Cleanup/request/controller binding differs')
    for key in ('ownedUnitsInactive', 'ownedProcessesAbsent', 'inputPinsUnchanged', 'withinDeadline'):
        need(cleanup.get(key) is True, 'Missing/failed cleanup proof: ' + key)
    need(all(type(cleanup.get(k)) is int and cleanup[k] == 0 for k in ('activeProcesses', 'workloadSwapBytes', 'oomKills')),
         'Incomplete reference cleanup/pressure proof')
    # A failed workload cannot reach the success capture; only its exact consequences are tolerated.
    need(cleanup.get('resourceCaptureBoundary') == 'work-complete/pre-exit' and
         cleanup.get('verifiedCompletionCapture') is False and
         cleanup.get('errors') == FAILED_WORKLOAD_CLEANUP_ERRORS and
         isinstance(cleanup.get('completionCaptureSHA256'), str) and
         re.fullmatch('[0-9a-f]{64}', cleanup['completionCaptureSHA256']) is not None,
         'Cleanup errors differ from the original failed-workload refusal')
    need(instant(report['finishedAtUTC']) <= instant(cleanup['completedAtUTC']) <= instant(cleanup['deadlineUTC']),
         'Cleanup missing,late or predates measurement')


def check_prior(request, base, authorization, prior_report, prior_sha256, policy):
    """The failed run was the single official rerun; recompute its authorization from retained bytes."""
    check_authorization_shape(authorization, request)
    prior_request = authorization['priorRequest']
    need(prior_request['requestId'] == policy['priorRequestId'] and prior_request['relevantSource'] == base,
         'Official rerun prior request differs')
    expected = {'schemaVersion': 1, 'kind': 'official-rerun-authorization-v1', 'ordinal': authorization['ordinal'],
                'requestId': request['requestId'], 'requestSHA256': canonical_digest(request),
                'priorRequest': prior_request, 'priorResultSHA256': prior_sha256,
                'priorFinishedAtUTC': prior_report['finishedAtUTC'],
                'priorFailures': failed_qualification_failures(prior_request, prior_report),
                'diagnostic': authorization.get('diagnostic', {})}
    need(expected == authorization, 'Official rerun authorization differs from the prior failed result')


def verify_override(repo, directory, policy=None):
    policy = policy or POLICY
    repo = Path(repo).resolve()
    root = Path(directory).absolute()
    need(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)) and
         not any(p.is_symlink() for p in root.rglob('*')), 'Owner override evidence is missing or linked')
    record = read(root / RECORD)
    need(set(record) == RECORD_FIELDS and record['schemaVersion'] == 1 and
         record['kind'] == 'reference-performance-owner-override-v1' and record['state'] == STATE and
         record['referencePerformanceQualified'] is False and record['budgetsChanged'] is False,
         'Not an owner override that preserves the failed qualification')
    for key in ('release', 'sourceRevision', 'relevantSourceSHA256', 'requestId', 'priorRequestId',
                'limitsSHA256', 'acceptedFailures'):
        need(record[key] == policy[key], 'Owner override is not for this exact release policy: ' + key)
    need(release_version(repo) == policy['release'], 'Owner override applies only to ' + policy['release'])
    members = record['files']
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    need(actual == set(members) | {RECORD}, 'Owner override file inventory differs')
    for name, value in members.items():
        path = Path(name)
        need(not path.is_absolute() and '..' not in path.parts and '\\' not in name and digest(root / path) == value,
             'Owner override member changed')
    host = profile(repo)
    need(host['limitsSHA256'] == policy['limitsSHA256'], 'Budgets/limits changed')
    request = read(root / 'request.json')
    request_shape(request)
    need(request['requestId'] == policy['requestId'] and request['sourceRevision'] == policy['sourceRevision'] and
         record['requestSHA256'] == canonical_digest(request), 'Override request differs')
    need(subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', policy['sourceRevision'], 'HEAD'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
         'Accepted source is not in current history')
    # The q11 request predates identity v2; its recorded v1 meaning is kept. Later policies name theirs.
    scheme = policy.get('identity', IDENTITY_V1)
    base = committed_identity(repo, policy['sourceRevision'], scheme)
    need(base == request['relevantSource'] and base['sha256'] == policy['relevantSourceSHA256'],
         'Accepted source identity differs from the failed request')
    need(request['hostProfileSHA256'] == digest(repo / PROFILE), 'Stale host profile request')
    current, delta = permitted_delta(repo, base, policy['allowedDelta'], scheme)
    need(record['permittedDelta'] == delta, 'Reviewed policy-file bytes/modes differ from the owner override')
    need(record['resultSHA256'] == digest(root / 'gate-result.json'), 'Failed result differs')
    report = read(root / 'gate-result.json')
    labels, measured = validate_failed_report(repo, report, request, host, base)
    need(labels == policy['acceptedFailures'] == record['acceptedFailures'],
         'Failure set differs from the owner-accepted failures')
    need(record['acceptedMeasurements'] == {k: measured[k] for k in labels}, 'Accepted measurement differs')
    for label, item in [('compile', report['compile']),
                        *[(size + '-generate', value['generation']) for size, value in report['fixtures'].items()],
                        *[(a['size'] + '-attempt-' + str(a['attempt']), a['execution']) for a in report['attempts']]]:
        need(digest(root / (label + '.log')) == item['logSHA256'], 'Missing/changed execution log')
    for size, item in report['fixtures'].items():
        file = root / ('fixture-' + size) / 'fixture.json'
        need(digest(file) == item['manifestSHA256'] and read(file) == item['contract'], 'Fixture receipt changed')
    cleanup = read(root / 'cleanup.json')
    validate_failed_cleanup(cleanup, report, request, host)
    if policy['priorRequestId'] is None:
        need(AUTHORIZATION not in members and PRIOR_RESULT not in members, 'Unexpected prior result')
    else:
        need(record['priorResultSHA256'] == digest(root / PRIOR_RESULT), 'Prior failed result differs')
        check_prior(request, base, read(root / AUTHORIZATION), read(root / PRIOR_RESULT),
                    record['priorResultSHA256'], policy)
    owner = record['owner']
    need(isinstance(owner, dict) and owner.get('name') == 'Lee' and owner.get('role') == 'release owner' and
         instant(cleanup['completedAtUTC']) <= instant(owner.get('acceptedAtUTC', '')),
         'Owner acceptance must follow the retained failure')
    return {'state': STATE, 'referencePerformanceQualified': False, 'qualificationFailed': True,
            'release': policy['release'], 'sourceRevision': policy['sourceRevision'],
            'acceptedRelevantSourceSHA256': base['sha256'], 'currentRelevantSourceSHA256': current['sha256'],
            'permittedDeltaPaths': sorted(delta), 'ownerAcceptedFailures': labels, 'requestId': request['requestId'],
            'releaseOrNativeUIAccepted': False}
