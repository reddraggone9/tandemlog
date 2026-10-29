"""Source-bound one-shot reference qualification. No runner, access or launch API."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import subprocess
import sys

from gate_policy import (evaluate, evaluate_scaling, validate_registered_coverage,
                         diagnostic_did_not_reproduce, OFFICIAL_RERUN_LIMIT)
import disk_stall

PROFILE = 'tool/performance/reference-host-v1.json'
QUALIFICATION = 'evidence/reference-performance/current'
# Release-owner acceptance of a retained failure for one exact release; see owner_override.py.
OWNER_OVERRIDE = 'evidence/reference-performance/owner-override-stable101'
OWNER_OVERRIDES = (OWNER_OVERRIDE, 'evidence/reference-performance/owner-override-food-rc1')
# A verified borderline failure of the qualified identity, with its queued follow-up; see borderline.py.
BORDERLINE = 'evidence/reference-performance/borderline'
EXCLUDED = ('evidence/', 'design/')
PRIOR_RESULT = 'prior-gate-result.json'
AUTHORIZATION = 'official-rerun.json'
AUTHORIZATION_SUFFIX = '.official-rerun.json'
TIMING_FAILURE = 'Absolute or paired timing limit exceeded; no eligible further rerun'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read(path):
    path = Path(path)
    need(path.is_file() and not path.is_symlink() and path.stat().st_size <= 16 * 1024**2,
         'Missing, linked or oversized receipt input: ' + str(path))
    return json.loads(path.read_text())


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def instant(value):
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    need(parsed.tzinfo is not None and parsed.utcoffset() == dt.timedelta(0), 'UTC timestamp required')
    return parsed


def relevant(path):
    return not path.startswith(EXCLUDED) and path not in ('README.md', 'AGENTS.md')


# v1 identities carry no scheme field and pin every relevant file's literal bytes; receipts recorded
# under v1 keep exactly that meaning. v2 additionally ignores the release version: only pubspec.yaml's
# top-level `version:` line and a plain Flatpak release list, which must follow that version.
IDENTITY_V1 = 'relevant-source-v1'
IDENTITY_V2 = 'relevant-source-v2'
IDENTITY_SCHEME = IDENTITY_V2
METAINFO = 'packaging/linux/com.reddraggone9.tandemlog.metainfo.xml'
VERSION_LINE = re.compile(rb'^version:[ \t]*[0-9A-Za-z.+~-]+[ \t]*(\r?\n|$)', re.M)
RELEASE_LIST = re.compile(rb'<releases>(?:\s*<release version="[0-9A-Za-z.+~-]+" date="[0-9]{4}-[0-9]{2}-[0-9]{2}"'
                          rb' type="(?:stable|development)"/>)*\s*</releases>')


def identity_scheme(identity):
    need(isinstance(identity, dict), 'Relevant-source identity required')
    if 'scheme' not in identity:
        return IDENTITY_V1
    need(identity['scheme'] == IDENTITY_V2, 'Unknown relevant-source identity scheme')
    return IDENTITY_V2


def release_normalized(name, content):
    """Version-free bytes for v2, or None when the file must be pinned literally."""
    if name == 'pubspec.yaml':
        if len(re.findall(rb'^version:', content, re.M)) == 1 and len(VERSION_LINE.findall(content)) == 1:
            return 'pubspec-version-v1', VERSION_LINE.sub(lambda m: b'version: *' + m.group(1), content)
    elif name == METAINFO:
        if content.count(b'<releases') == 1 and len(RELEASE_LIST.findall(content)) == 1:
            return 'appstream-release-list-v1', RELEASE_LIST.sub(b'<releases/>', content)
    return None


def pin(name, content, mode, scheme):
    normalized = release_normalized(name, content) if scheme == IDENTITY_V2 else None
    if normalized is None:
        return {'sha256': hashlib.sha256(content).hexdigest(), 'mode': mode}
    return {'sha256': hashlib.sha256(normalized[1]).hexdigest(), 'mode': mode, 'normalized': normalized[0]}


def identity(pins, scheme):
    if scheme == IDENTITY_V1:
        return {'sha256': canonical_digest(pins), 'files': pins}
    return {'scheme': scheme, 'sha256': canonical_digest({'scheme': scheme, 'files': pins}), 'files': pins}


def git_blobs(repo, objects):
    """Read unique literal blobs in one Git process; validate every byte of its protocol."""
    # Multiple inventory paths may legitimately name the same object. Only request it once,
    # so a duplicate response can never be confused with legitimate duplicate content.
    objects = list(dict.fromkeys(objects))
    need(all(re.fullmatch('[0-9a-f]{40}', obj) is not None for obj in objects),
         'Invalid Git blob object ID')
    if not objects:
        return {}
    output = subprocess.check_output(['git', '-C', str(repo), 'cat-file', '--batch'],
                                     input=('\n'.join(objects) + '\n').encode('ascii'))
    blobs = {}
    offset = 0
    for expected in objects:
        end = output.find(b'\n', offset)
        need(end != -1, 'Missing/truncated Git blob batch header')
        header = output[offset:end]
        match = re.fullmatch(rb'([0-9a-f]{40}) blob (0|[1-9][0-9]*)', header)
        need(match is not None, 'Malformed/missing or non-blob Git batch response')
        obj = match[1].decode('ascii')
        need(obj not in blobs, 'Duplicate Git blob batch response')
        need(obj == expected, 'Unexpected Git blob batch object ID')
        size = int(match[2])
        start = end + 1
        end = start + size
        need(end < len(output), 'Truncated Git blob batch content')
        need(output[end:end + 1] == b'\n', 'Invalid Git blob batch content terminator')
        content = output[start:end]
        need(hashlib.sha1(b'blob ' + str(size).encode('ascii') + b'\0' + content).hexdigest() == obj,
             'Git blob batch content/object ID differs')
        blobs[obj] = content
        offset = end + 1
    need(offset == len(output), 'Trailing/duplicate Git blob batch output')
    return blobs


def source_identity(repo, scheme=IDENTITY_SCHEME):
    """All tracked non-documentation inputs, including tests, workflows and native source."""
    identity_scheme({'scheme': scheme} if scheme != IDENTITY_V1 else {})
    repo = Path(repo).resolve()
    changed = subprocess.check_output(['git', '-C', str(repo), 'diff', 'HEAD', '--name-only', '-z']).decode().split('\0')
    untracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '--others', '--exclude-standard', '-z']).decode().split('\0')
    need(not any(p and relevant(p) for p in changed + untracked), 'Relevant source is dirty or untracked')
    pins = {}
    inventory = []
    names = set()
    for row in subprocess.check_output(['git', '-C', str(repo), 'ls-files', '--stage', '-z']).decode().split('\0'):
        if not row:
            continue
        info, name = row.split('\t', 1)
        need(name not in names, 'Duplicate Git source inventory path')
        names.add(name)
        if not relevant(name):
            continue
        mode, blob, stage = info.split()
        need(stage == '0' and mode in ('100644', '100755'), 'Unmerged or linked relevant source')
        inventory.append((name, mode, blob))
    blobs = git_blobs(repo, (blob for _, _, blob in inventory))
    for name, mode, blob in inventory:
        path = repo / name
        need(path.is_file() and not path.is_symlink(), 'Relevant source missing or linked')
        original = blobs[blob]
        value = digest(path)
        need(hashlib.sha256(original).hexdigest() == value, 'Reference/hosted Linux source differs from literal Git bytes: ' + name)
        pins[name] = pin(name, original, mode, scheme)
    need(bool(pins), 'Empty relevant source inventory')
    return identity(pins, scheme)


def committed_identity(repo, revision, scheme=IDENTITY_SCHEME):
    identity_scheme({'scheme': scheme} if scheme != IDENTITY_V1 else {})
    need(re.fullmatch('[0-9a-f]{40}', revision) is not None, 'Exact source commit required')
    pins = {}
    inventory = []
    names = set()
    for row in subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', '-z', revision]).decode().split('\0'):
        if not row:
            continue
        info, name = row.split('\t', 1)
        need(name not in names, 'Duplicate Git source inventory path')
        names.add(name)
        if not relevant(name):
            continue
        mode, kind, blob = info.split()
        need(kind == 'blob' and mode in ('100644', '100755'), 'Linked/unexpected committed source')
        inventory.append((name, mode, blob))
    blobs = git_blobs(repo, (blob for _, _, blob in inventory))
    for name, mode, blob in inventory:
        content = blobs[blob]
        pins[name] = pin(name, content, mode, scheme)
    return identity(pins, scheme)


def recorded_identity(repo, recorded, revision=None):
    """(current, committed-at-revision) identities under the scheme the request recorded.

    An old receipt is never reinterpreted under a newer scheme.
    """
    scheme = identity_scheme(recorded)
    need(recorded == identity(recorded.get('files'), scheme), 'Relevant-source identity scheme/digest differs')
    return (source_identity(repo, scheme),
            None if revision is None else committed_identity(repo, revision, scheme))


def requested_bytes_sha256(repo, request, name):
    """Literal bytes the request's own revision supplied; v2 may differ from HEAD only by version."""
    return hashlib.sha256(subprocess.check_output(
        ['git', '-C', str(repo), 'show', request['sourceRevision'] + ':' + name])).hexdigest()


def fingerprint(output):
    result = {'architecture': platform.machine(), 'kernel': platform.release(),
              'python': platform.python_version(), 'logicalCPUs': os.cpu_count()}
    result['cpuModel'] = next(line.split(':', 1)[1].strip()
                              for line in Path('/proc/cpuinfo').read_text().splitlines()
                              if line.startswith('model name') and ':' in line)
    result['filesystemType'] = subprocess.check_output(
        ['findmnt', '-n', '-o', 'FSTYPE', '-T', str(Path(output).resolve())], text=True).strip()
    return result


def profile(repo):
    value = read(Path(repo) / PROFILE)
    need(value.get('schemaVersion') == 1 and value.get('status') == 'registered',
         'Controlled reference host is not registered')
    need(value.get('hostId') == 'farnsworth' and type(value.get('hardwareMultiplier')) is int and value['hardwareMultiplier'] == 1,
         'Only the approved unscaled reference host is allowed')
    expected = value.get('environment', {})
    need(set(expected) == {'architecture', 'kernel', 'python', 'logicalCPUs', 'cpuModel', 'filesystemType'}
         and all(v is not None and v != '' for v in expected.values()), 'Incomplete reference environment registration')
    need(re.fullmatch('[0-9a-f]{64}', value.get('controllerSHA256', '')) is not None,
         'Reviewed external controller hash required')
    expected_bounds = {'memory.max': str(6 * 1024**3), 'memory.swap.max': '0',
                       'cpu.max': '200000 100000', 'pids.max': '128'}
    need(value.get('resourceBounds') == expected_bounds, 'Registered reference caps must remain unchanged')
    suffixes = {'/bin/dart', '/bin/utils/gen_snapshot', '/libtandemlog_text.so',
                '/libsqlite3.so', '/tool/performance/limits-v1.json'}
    hashes = value.get('toolHashes', {})
    need(set(hashes) == suffixes and all(isinstance(v, str) and re.fullmatch('[0-9a-f]{64}', v)
                                        for v in hashes.values()), 'Complete reviewed tool/library pins required')
    need(hashes['/tool/performance/limits-v1.json'] == value['limitsSHA256'], 'Tool/limit registration differs')
    dependencies = value.get('compiledDependencies', {})
    need(type(dependencies.get('count')) is int and dependencies['count'] > 0 and
         isinstance(dependencies.get('sha256'), str) and re.fullmatch('[0-9a-f]{64}', dependencies['sha256']),
         'Complete compiled dependency inventory required')
    names = value.get('packageNames', [])
    need(isinstance(names, list) and all(isinstance(n, str) for n in names) and names == sorted(set(names))
         and 'tandemlog' in names and re.fullmatch('[0-9a-f]{64}', value.get('packageContractSHA256', '')),
         'Complete reviewed package contract required')
    need(digest(Path(repo) / 'pubspec.lock') == value['pubspecLockSHA256'], 'Reviewed dependency lock differs')
    need(digest(Path(repo) / 'tool/performance/limits-v1.json') == value['limitsSHA256'], 'Reference limits differ')
    return value


REQUEST_FIELDS = {'schemaVersion', 'purpose', 'requestId', 'issuedAtUTC', 'sourceRevision',
                  'relevantSource', 'hostProfileSHA256', 'controllerSHA256', 'controllerPath'}


def request_shape(value):
    # The registered external controller accepts exactly these fields; extensions live beside the request.
    need(set(value) == REQUEST_FIELDS, 'Request fields differ from the registered controller contract')
    need(value.get('schemaVersion') == 1 and value.get('purpose') == 'controlled-reference-performance-v1',
         'Not a reference qualification request')
    need(re.fullmatch('[0-9a-f]{32}', value.get('requestId', '')) is not None, 'Fresh request nonce required')
    instant(value['issuedAtUTC'])

def failed_qualification_failures(prior_request, report):
    """Failing labels of an enforcing, complete, timing-only reference failure; else refuse."""
    request_shape(prior_request)
    binding = report.get('referenceBinding', {})
    need(binding.get('requestId') == prior_request['requestId'] and
         binding.get('requestSHA256') == canonical_digest(prior_request) and
         binding.get('relevantSourceSHA256') == prior_request['relevantSource']['sha256'],
         'Prior result is not bound to the prior qualification request')
    need(report.get('timingRole') == 'enforcing' and report.get('measureOnly') is False and
         report.get('costDiagnosticsEnabled') is False and report.get('releaseGateAccepted') is not True and
         report.get('timingLimitsPassed') is not True and report.get('error') == TIMING_FAILURE,
         'Only an enforcing timing-limit failure can be officially rerun')
    attempts, pairs = report.get('attempts', []), report.get('pairedScalingAttempts', [])
    need(bool(attempts) and all(a['status'] in ('passed', 'timing-failed') and a['execution']['exitCode'] == 0 and
                                a['execution']['childAbsent'] is True for a in attempts) and
         all(p['status'] in ('passed', 'timing-failed') for p in pairs),
         'Correctness, coverage or execution failures are terminal and cannot be rerun')
    last = max(a['attempt'] for a in attempts)
    resampled = [r for r in report.get('diskStallResamples', []) if r['attempt'] == last]
    if resampled:
        # A resampled label that missed again is an ordinary failure; its effective labels are the failures.
        need(len(resampled) == 1, 'Repeated disk-stall resample record')
        failures = sorted({size + ':' + f for size, value in resampled[0]['absolute'].items() for f in value['failures']} |
                          {name + ':' + f for name, value in resampled[0]['paired'].items() for f in value['failures']})
    else:
        failures = sorted({a['size'] + ':' + f for a in attempts if a['attempt'] == last for f in a['failures']} |
                          {p['comparison'] + ':' + f for p in pairs if p['attempt'] == last for f in p['failures']})
    need(bool(failures), 'Prior result has no timing failure to rerun')
    instant(report['finishedAtUTC'])
    return failures


def check_authorization_shape(value, request):
    """Request-bound authorization for the single official rerun; the request itself stays standard."""
    need(isinstance(value, dict) and value.get('schemaVersion') == 1 and
         value.get('kind') == 'official-rerun-authorization-v1' and
         value.get('ordinal') == 1 + OFFICIAL_RERUN_LIMIT and
         value.get('requestId') == request['requestId'] and
         value.get('requestSHA256') == canonical_digest(request) and isinstance(value.get('priorRequest'), dict),
         'Official rerun limit exceeded or authorization not bound to this request')
    prior = value['priorRequest']
    request_shape(prior)
    need(prior['requestId'] != request['requestId'] and
         prior['relevantSource']['sha256'] == request['relevantSource']['sha256'],
         'Official rerun must repeat the failed request\'s unchanged relevant source')
    diagnostic = value.get('diagnostic', {})
    need(diagnostic_did_not_reproduce(diagnostic, prior['requestId'], prior['relevantSource']['sha256'],
                                      value.get('priorFailures', [])),
         'Official rerun lacks a recorded diagnostic that failed to reproduce every prior failure')
    need(instant(diagnostic['recordedAtUTC']) <= instant(request['issuedAtUTC']) and
         all(instant(value['priorFinishedAtUTC']) <= instant(r['startedAtUTC']) <= instant(r['finishedAtUTC'])
             <= instant(diagnostic['recordedAtUTC']) for r in diagnostic['runs']),
         'Diagnostic must follow the failed qualification and precede the rerun request')


def official_rerun(repo, request, prior_request, prior_report, prior_report_sha256, diagnostic):
    """The single approved rerun of unchanged source; budgets and limits are untouched."""
    request_shape(request)
    need(prior_request['relevantSource'] == request['relevantSource'] ==
         recorded_identity(repo, request['relevantSource'])[0],
         'Changed source needs a fresh request, not a rerun')
    value = {'schemaVersion': 1, 'kind': 'official-rerun-authorization-v1', 'ordinal': 1 + OFFICIAL_RERUN_LIMIT,
             'requestId': request['requestId'], 'requestSHA256': canonical_digest(request),
             'priorRequest': prior_request, 'priorResultSHA256': prior_report_sha256,
             'priorFinishedAtUTC': prior_report['finishedAtUTC'],
             'priorFailures': failed_qualification_failures(prior_request, prior_report),
             'diagnostic': diagnostic}
    check_authorization_shape(value, request)
    return value


def check_official_rerun(repo, request, authorization, prior_report_path):
    check_authorization_shape(authorization, request)
    need(prior_report_path.is_file() and digest(prior_report_path) == authorization.get('priorResultSHA256'),
         'Official rerun prior failed result is missing or changed')
    expected = official_rerun(repo, request, authorization.get('priorRequest', {}), read(prior_report_path),
                              authorization['priorResultSHA256'], authorization.get('diagnostic', {}))
    need(expected == authorization, 'Official rerun authorization differs from the prior failed result')



def request_context(repo, request_path, output, bounds):
    value = read(request_path)
    request_shape(value)
    host = profile(repo)
    identity, committed = recorded_identity(repo, value['relevantSource'], value['sourceRevision'])
    need(value['relevantSource'] == identity == committed, 'Stale/mismatched relevant source request')
    need(value['hostProfileSHA256'] == digest(Path(repo) / PROFILE), 'Host registration/request differs')
    need(value['controllerSHA256'] == host['controllerSHA256'], 'External controller request differs')
    controller = Path(value['controllerPath'])
    need(controller.is_absolute() and controller.is_file() and not controller.is_symlink() and
         digest(controller) == host['controllerSHA256'], 'Actual external controller bytes changed')
    need(fingerprint(output) == host['environment'], 'Actual reference environment differs')
    need(bounds == host['resourceBounds'], 'Actual reference resource bounds differ')
    return {'requestId': value['requestId'], 'requestSHA256': canonical_digest(value),
            'issuedAtUTC': value['issuedAtUTC'], 'relevantSourceSHA256': identity['sha256'],
            'hostProfileSHA256': value['hostProfileSHA256'], 'environment': host['environment'],
            'controllerSHA256': host['controllerSHA256']}


def package_contract(config):
    """Root paths may differ; package identity/language/library contracts may not."""
    need(config.get('configVersion') == 2, 'Package configuration version differs')
    names = [p['name'] for p in config['packages']]
    need(len(names) == len(set(names)), 'Duplicate package identity')
    return canonical_digest(sorted((p['name'], p.get('languageVersion'), p.get('packageUri', ''))
                                   for p in config['packages']))


def compiled_inventory(report):
    tools = report['toolPins']
    def one(values):
        values = list(values)
        need(len(values) == 1, 'Ambiguous compiled root binding')
        return values[0]
    original = one(p[:-len('tool/performance/run_gate.py')] for p in report['sourcePins']
                   if p.endswith('/tool/performance/run_gate.py'))
    staged = one(p[:-len('.dart_tool/package_config.json')] for p in tools
                 if p.endswith('/.dart_tool/package_config.json'))
    flutter = one(p[:-len('bin/cache/dart-sdk/bin/dart')] for p in tools
                  if p.endswith('/bin/cache/dart-sdk/bin/dart'))
    def rename(path):
        for prefix, label in ((staged, 'staged/'), (original, 'project/'), (flutter, 'flutter/')):
            if path.startswith(prefix):
                return label + path[len(prefix):]
        if path.count('/hosted/pub.dev/') == 1:
            return 'pub/' + path.split('/hosted/pub.dev/')[1]
        raise ValueError('Unrecognized compiled dependency root')
    normalized = {}
    for name, value in report['compiledSourceAndDependencyPins'].items():
        key = rename(name)
        need(key not in normalized, 'Compiled inventory path collision')
        normalized[key] = value
    need({'project/.dart_tool/package_config.json', 'staged/.dart_tool/package_config.json'} <= set(normalized),
         'Missing original/staged package configuration pins')
    dependencies = {k: v for k, v in normalized.items() if not k.startswith(('project/', 'staged/'))}
    return normalized, {'count': len(dependencies), 'sha256': canonical_digest(dependencies)}, rename


def check_reference_toolchain(report, host):
    """Used before compiler/native execution as well as by the receipt verifier."""
    normalized, deps, rename = compiled_inventory(report)
    need(deps == host['compiledDependencies'], 'Compiled dependency/SDK inventory differs')
    need(report.get('packageContractSHA256') == host['packageContractSHA256'], 'Package identity/language contract differs')
    for suffix, expected_hash in host['toolHashes'].items():
        values = [v for p, v in {**report['toolPins'], **report['compiledSourceAndDependencyPins']}.items()
                  if p.endswith(suffix)]
        need(values == [expected_hash], 'Tool/library pin differs: ' + suffix)
    return normalized, rename


def validate_report(repo, report, request, host):
    from run_gate import source_pins, scaling_specs, validate_project_imports
    repo = Path(repo).resolve()
    request_shape(request)
    for key in ('correctnessAccepted', 'measurementCompleted', 'allPinsMatch', 'releaseGateAccepted', 'timingLimitsPassed'):

        need(report.get(key) is True, 'Incomplete/incorrect reference result: ' + key)
    need(report.get('timingRole') == 'enforcing' and report.get('measureOnly') is False
         and report.get('costDiagnosticsEnabled') is False and not report.get('error'),
         'Advisory/calibration/instrumented/historical result cannot qualify')
    binding = report.get('referenceBinding', {})
    need(binding.get('requestId') == request['requestId'] and
         binding.get('requestSHA256') == canonical_digest(request), 'Reference request binding differs')
    need(binding.get('relevantSourceSHA256') == recorded_identity(repo, request['relevantSource'])[0]['sha256'] ==
         request['relevantSource']['sha256'], 'Stale reference source')
    need(binding.get('hostProfileSHA256') == digest(repo / PROFILE) == request['hostProfileSHA256'] and
         binding.get('environment') == host['environment'], 'Reference environment/profile differs')
    need(binding.get('controllerSHA256') == host['controllerSHA256'], 'Reference controller differs')
    need(instant(request['issuedAtUTC']) <= instant(report['startedAtUTC']) <= instant(report['finishedAtUTC']),
         'Qualification predates request or has invalid timestamps')
    need(report['resourceBounds'] == host['resourceBounds'], 'Reference resource bounds differ')
    need(report.get('sourceRewrites') == [] and report.get('shimAllowlist') == [], 'Source rewrite/shim refused')
    pins = source_pins(repo, repo / 'tool/performance')
    expected = {Path(p).relative_to(repo).as_posix(): v for p, v in pins.items()}
    # Identity equality leaves only pubspec.yaml's version line able to differ from what ran.
    requested_pubspec = requested_bytes_sha256(repo, request, 'pubspec.yaml')
    expected['pubspec.yaml'] = requested_pubspec
    normalized, rename = check_reference_toolchain(report, host)
    actual = {rename(p).removeprefix('project/'): v for p, v in report['sourcePins'].items()}
    need(actual == expected, 'Reference source pin inventory differs')
    seals = report['compiledFileSeals']
    originals = {p.relative_to(repo).as_posix(): digest(p) for p in (repo / 'lib').rglob('*') if p.is_file()}
    originals.update({'pubspec.yaml': requested_pubspec, 'pubspec.lock': digest(repo / 'pubspec.lock')})
    need(set(seals) == set(originals), 'Compiled project file inventory differs')
    for name, value in seals.items():
        need(value == {'originalSHA256': originals[name], 'compiledSHA256': originals[name], 'change': 'none'},
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
    validate_registered_coverage(read(repo / 'tool/performance/coverage-v1.json'), limits, scaling_specs(limits))
    attempts = report['attempts']
    retries = report['rerunsUsed']
    need(type(retries) is int and retries in (0, 1) and len(attempts) == 3 * (retries + 1),
         'Missing/extra/repeated reference attempt')
    need(type(report['compile']['exitCode']) is int and report['compile']['exitCode'] == 0 and
         report['compile']['childAbsent'] is True and report['compile'].get('childGroupAbsent') is True and report.get('binaryMode') == '0o700', 'Incomplete compile')
    contracts = {size: item['contract'] for size, item in report['fixtures'].items()}
    need(set(contracts) == set(limits['historySizes']), 'Fixture inventory differs')
    need(all(type(v['generation']['exitCode']) is int and v['generation']['exitCode'] == 0 and
             v['generation']['childAbsent'] is True and v['generation'].get('childGroupAbsent') is True for v in report['fixtures'].values()), 'Incomplete fixture generation')
    need(all(type(a['attempt']) is int and 0 <= a['attempt'] <= retries for a in attempts), 'Invalid attempt ordinal')
    need(len(report['pairedScalingAttempts']) == (retries + 1) * len(scaling_specs(limits)) and
         all(type(p['attempt']) is int and 0 <= p['attempt'] <= retries for p in report['pairedScalingAttempts']),
         'Missing/extra growth attempt')
    decisions, effective_paired, used = {}, {}, []
    records = report.get('diskStallResamples', [])
    need(isinstance(records, list) and all(type(r.get('attempt')) is int and 0 <= r['attempt'] <= retries for r in records) and
         len({r['attempt'] for r in records}) == len(records), 'Missing/extra disk-stall resample record')
    for number in range(retries + 1):
        batch = [a for a in attempts if a['attempt'] == number]
        need(len(batch) == 3 and {a['size'] for a in batch} == set(contracts), 'Missing reference size')
        summaries = {}
        for item in batch:
            execution = item['execution']
            need(type(execution['exitCode']) is int and execution['exitCode'] == 0 and execution['childAbsent'] is True and execution.get('childGroupAbsent') is True,
                 'Incomplete action execution')
            decision = evaluate(item['result'], limits)
            need(decision.status != 'correctness-failed' and decision.status == item['status'] and
                 list(decision.failures) == item['failures'] and decision.summaries == item['summaries'],
                 'Absolute correctness/coverage/summary differs')
            summaries[item['size']] = decision.summaries
            decisions[number, item['size']] = decision
        pairs = [p for p in report['pairedScalingAttempts'] if p['attempt'] == number]
        specs = scaling_specs(limits)
        need(len(pairs) == len(specs) and {p['comparison'] for p in pairs} == set(specs), 'Missing/extra growth pair')
        for item in pairs:
            rule = specs[item['comparison']]
            need(item['smallSize'] == rule['smallSize'] and item['largeSize'] == rule['largeSize'], 'Growth size labels differ')
            decision = evaluate_scaling(summaries, specs[item['comparison']], contracts)
            need(decision.status != 'correctness-failed' and decision.status == item['status'] and
                 list(decision.failures) == item['failures'] and decision.summaries == item['comparisons'],
                 'Growth correctness/rules/summary differs')
            effective_paired[number, item['comparison']] = decision
        record = next((r for r in records if r['attempt'] == number), None)
        if record is not None:
            # Lee's disk-stall rule: recompute attribution from the original samples and recorded
            # append/CPU numbers (bound to the attempt log by verify_bundle), then the label's resample.
            originals = {item['size']: item['result'] for item in batch}
            planned, unattributed = disk_stall.plan(originals, disk_stall.recorded_diagnostics(record['resamples']),
                                                    limits, specs, contracts, used)
            need(record.get('policy') == disk_stall.POLICY and planned and not unattributed and
                 planned == record['resamples'], 'Disk-stall resample is not attributed under the rule')
            need(len(record['executions']) == len(planned) and
                 all(type(e['exitCode']) is int and e['exitCode'] == 0 and e['childAbsent'] is True and
                     e.get('childGroupAbsent') is True for e in record['executions']), 'Incomplete disk-stall resample')
            used += [[item['size'], item['action']] for item in planned]
            effective = disk_stall.apply(originals, planned, record['replacements'], limits)
            absolute, pairs = disk_stall.evaluate_all(effective, limits, specs, contracts)
            need(all(d.status != 'correctness-failed' for d in [*absolute.values(), *pairs.values()]) and
                 record['absolute'] == {s: {'status': d.status, 'failures': list(d.failures), 'summaries': d.summaries}
                                        for s, d in absolute.items()} and
                 record['paired'] == {n: {'status': d.status, 'failures': list(d.failures), 'comparisons': d.summaries}
                                      for n, d in pairs.items()}, 'Disk-stall resample decision differs')
            decisions.update({(number, size): d for size, d in absolute.items()})
            effective_paired.update({(number, name): d for name, d in pairs.items()})
        if number == retries:
            need(all(effective_paired[number, name].status == 'passed' for name in specs), 'Reference history-growth limit failed')
            need(all(decisions[number, size].status == 'passed' for size in contracts), 'Reference absolute limit failed')
    if retries:
        from run_gate import may_rerun_all
        first = {a['size']: a for a in attempts if a['attempt'] == 0}
        paired = [(scaling_specs(limits)[name], effective_paired[0, name]) for name in scaling_specs(limits)]
        need(may_rerun_all({s: decisions[0, s] for s in first}, paired, 0,
                          {s: first[s]['execution'] for s in first},
                          first[next(iter(first))]['binding'], first[next(iter(first))]['binding']),
             'Reference retry lacks existing external-noise eligibility')
    bindings = [a['binding'] for a in attempts]
    need(all(b == bindings[0] for b in bindings) and bindings[0]['binary'] == report['binarySHA256'] and
         bindings[0]['limits'] == limits['sha256'] and
         bindings[0]['fixtures'] == {size: v['manifestSHA256'] for size, v in report['fixtures'].items()} and
         bindings[0]['source'] == hashlib.sha256(json.dumps(report['sourcePins'], sort_keys=True).encode()).hexdigest(),
         'Binary/source/fixture/limits binding changed')
    return {'referencePerformanceQualified': True, 'absoluteAndBothGrowthBudgetsPassed': True,
            'relevantSourceSHA256': request['relevantSource']['sha256'], 'requestId': request['requestId'],
            'releaseOrNativeUIAccepted': False}


def verify_bundle(repo, directory):
    root = Path(directory).absolute()
    need(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)),
         'Reference qualification receipt is missing or linked')
    need(not any(p.is_symlink() for p in root.rglob('*')), 'Linked qualification input refused')
    request = read(root / 'request.json')
    request_shape(request)
    host = profile(repo)
    need(request['hostProfileSHA256'] == digest(Path(repo) / PROFILE), 'Stale host profile request')
    current, committed = recorded_identity(repo, request['relevantSource'], request['sourceRevision'])
    need(request['relevantSource'] == current == committed, 'Missing/stale/mismatched reference source')
    need(subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', request['sourceRevision'], 'HEAD'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
         'Reference request source is not in current history')
    manifest = read(root / 'qualification.json')
    need(manifest.get('schemaVersion') == 1 and manifest.get('requestId') == request['requestId'], 'Qualification request differs')
    members = manifest['files']
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    need(actual == set(members) | {'qualification.json'}, 'Qualification file inventory differs')
    for name, value in members.items():
        path = Path(name)
        need(not path.is_absolute() and '..' not in path.parts and '\\' not in name and digest(root / path) == value,
             'Qualification member changed')
    if AUTHORIZATION in members:
        check_official_rerun(repo, request, read(root / AUTHORIZATION), root / PRIOR_RESULT)
    else:
        need(PRIOR_RESULT not in members, 'Unexpected prior result in a first qualification')
    report = read(root / 'gate-result.json')
    result = validate_report(repo, report, request, host)
    from run_gate import measurements
    for label, item in [('compile', report['compile']),
                        *[(size + '-generate', value['generation']) for size, value in report['fixtures'].items()],
                        *[(a['size'] + '-attempt-' + str(a['attempt']), a['execution']) for a in report['attempts']]]:
        need(digest(root / (label + '.log')) == item['logSHA256'], 'Missing/changed execution log')
    for record in report.get('diskStallResamples', []):
        for ordinal, (item, execution) in enumerate(zip(record['resamples'], record['executions'])):
            label = 'disk-stall-resample-' + str(record['attempt']) + '-' + str(ordinal)
            need(digest(root / (label + '.log')) == execution['logSHA256'], 'Missing/changed disk-stall resample log')
            logged = disk_stall.action_diagnostics(root / (item['size'] + '-attempt-' + str(record['attempt']) + '.log'))
            need(all(logged.get((item['action'], s['index'])) ==
                     disk_stall.recorded_diagnostics([item])[item['size']][item['action'], s['index']]
                     for s in item['samples']), 'Disk-stall attribution differs from the attempt log')
            rows, complete = measurements(root / (label + '.log'))
            need(complete and record['replacements'][ordinal] == [r for r in rows if r['action'] == item['action']] and
                 {v['family'] for (a, _), v in disk_stall.action_diagnostics(root / (label + '.log')).items()} ==
                 {item['family']}, 'Disk-stall resample differs from its log')
    for size, item in report['fixtures'].items():
        file = root / ('fixture-' + size) / 'fixture.json'
        need(digest(file) == item['manifestSHA256'] and read(file) == item['contract'], 'Fixture receipt changed')
    cleanup = read(root / 'cleanup.json')
    need(cleanup.get('requestId') == request['requestId'] and cleanup.get('controllerSHA256') == host['controllerSHA256'],
         'Cleanup/request/controller binding differs')
    for key in ('ownedUnitsInactive', 'ownedProcessesAbsent', 'inputPinsUnchanged', 'withinDeadline'):
        need(cleanup.get(key) is True, 'Missing/failed cleanup proof: ' + key)
    need(all(type(cleanup.get(k)) is int and cleanup[k] == 0
             for k in ('activeProcesses', 'workloadSwapBytes', 'oomKills')) and not cleanup.get('errors'),
         'Incomplete reference cleanup/pressure proof')
    need(cleanup.get('resourceCaptureBoundary') == 'work-complete/pre-exit' and
         cleanup.get('verifiedCompletionCapture') is True and
         isinstance(cleanup.get('completionCaptureSHA256'), str) and
         re.fullmatch('[0-9a-f]{64}', cleanup['completionCaptureSHA256']) is not None,
         'Missing/invalid live completion-counter capture attestation')
    need(instant(report['finishedAtUTC']) <= instant(cleanup['completedAtUTC']) <= instant(cleanup['deadlineUTC']),
         'Cleanup missing,late or predates measurement')
    need(manifest.get('binarySHA256VerifiedAtExport') == report['binarySHA256'] and
         manifest.get('fixtureBytesVerifiedAtExport') is True,
         'Missing final binary/fixture verification')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('fingerprint', 'request', 'authorize-rerun', 'seal', 'verify'))
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--request', type=Path)
    parser.add_argument('--run', type=Path)
    parser.add_argument('--cleanup', type=Path)
    parser.add_argument('--controller', type=Path)
    parser.add_argument('--rerun-of-request', type=Path, help='Failed qualification request (official rerun only)')
    parser.add_argument('--rerun-of-result', type=Path, help='Its original failed gate-result.json')
    parser.add_argument('--diagnostic', type=Path, help='Recorded non-reproducing diagnostic (official rerun only)')
    parser.add_argument('--prior-result', type=Path, help='Seal: the official rerun\'s prior failed gate-result.json')
    parser.add_argument('--rerun-authorization', type=Path, help='Seal: REQUEST.official-rerun.json')
    args = parser.parse_args()
    rerun_inputs = (args.rerun_of_request, args.rerun_of_result, args.diagnostic)
    need(args.mode == 'authorize-rerun' or rerun_inputs == (None, None, None), 'Rerun inputs only apply to authorize-rerun')
    need(args.mode == 'seal' or (args.prior_result, args.rerun_authorization) == (None, None),
         'Prior result/authorization only apply to seal')
    if args.mode == 'fingerprint':
        need(args.output is not None, 'Existing output-parent path required')
        print(json.dumps(fingerprint(args.output), indent=2))
    elif args.mode == 'request':
        need(args.output is not None and not args.output.exists(), 'Fresh request output required')
        host = profile(args.repo)
        need(args.controller is not None and digest(args.controller) == host['controllerSHA256'], 'Reviewed controller differs')
        value = {'schemaVersion': 1, 'purpose': 'controlled-reference-performance-v1',
                 'requestId': secrets.token_hex(16), 'issuedAtUTC': utc(),
                 'sourceRevision': subprocess.check_output(['git', '-C', str(args.repo), 'rev-parse', 'HEAD'], text=True).strip(),
                 'relevantSource': source_identity(args.repo), 'hostProfileSHA256': digest(args.repo / PROFILE),
                 'controllerSHA256': host['controllerSHA256'], 'controllerPath': str(args.controller.resolve())}
        with args.output.open('x') as stream:
            json.dump(value, stream, indent=2); stream.write('\n')
    elif args.mode == 'authorize-rerun':
        need(args.request is not None and all(v is not None for v in rerun_inputs),
             'Official rerun needs the fresh request, prior request, prior result and diagnostic')
        output = Path(str(args.request) + AUTHORIZATION_SUFFIX)
        need(args.output in (None, output), 'Authorization must sit beside its request')
        need(not Path(str(args.rerun_of_request) + AUTHORIZATION_SUFFIX).exists(),
             'Official rerun limit exceeded: the failed run was itself an official rerun')
        value = official_rerun(args.repo, read(args.request), read(args.rerun_of_request), read(args.rerun_of_result),
                               digest(args.rerun_of_result), read(args.diagnostic))
        with output.open('x') as stream:
            json.dump(value, stream, indent=2); stream.write('\n')
    elif args.mode == 'verify':
        if args.output is None and any((args.repo / p).exists() for p in OWNER_OVERRIDES):
            import owner_override
            for path in OWNER_OVERRIDES:
                policy = getattr(owner_override, owner_override.OVERRIDES[path])
                # Each override is scoped to one release; at any other version it is retained history only.
                if (args.repo / path).exists() and owner_override.release_version(args.repo) == policy['release']:
                    # Not a qualification: the failure stays retained and the result says so.
                    result = owner_override.verify_override(args.repo, args.repo / path, policy)
                    print('::warning title=Reference performance NOT qualified::' + result['state'] + ' for ' +
                          result['release'] + '; owner accepted ' + ', '.join(result['ownerAcceptedFailures']),
                          file=sys.stderr)
                    print(json.dumps(result, indent=2))
                    return
        if args.output is None and (args.repo / BORDERLINE).exists():
            # Requires the passing qualification too; a rejected borderline bundle fails the check.
            from borderline import verify_borderline
            result = verify_borderline(args.repo, args.repo / BORDERLINE)
            print('::warning title=Reference performance borderline, follow-up queued::' +
                  ', '.join(m['label'] + ' ' + m['statistic'] + ' ' + format(m['ratioOfBound'], '.2%') + ' of bound'
                            for m in result['borderlineMetrics']), file=sys.stderr)
            print(json.dumps(result, indent=2))
            return
        print(json.dumps(verify_bundle(args.repo, args.output or args.repo / QUALIFICATION), indent=2))
    else:
        need(all(v is not None for v in (args.output, args.request, args.run, args.cleanup)), 'Seal requires request/run/cleanup/output')
        need(not args.output.exists(), 'Fresh qualification bundle required')
        from run_gate import fixture_binding
        report = read(args.run / 'gate-result.json')
        request = read(args.request)
        validate_report(args.repo, report, request, profile(args.repo))
        need((args.rerun_authorization is None) == (args.prior_result is None),
             'An official rerun bundle needs both its authorization and its prior failed result')
        if args.prior_result is not None:
            check_official_rerun(args.repo, request, read(args.rerun_authorization), args.prior_result)
        need(digest(args.run / 'benchmark') == report['binarySHA256'] and os.access(args.run / 'benchmark', os.X_OK),
             'Compiled binary changed or is not executable before export')
        for size, value in report['fixtures'].items():
            need(Path(value['contract']['workspace']).resolve() == (args.run / ('fixture-' + size) / 'workspace').resolve(),
                 'Synthetic fixture workspace escaped the owned run')
        fixture_binding({size: {'manifest': args.run / ('fixture-' + size) / 'fixture.json', 'receipt': value['contract']}
                         for size, value in report['fixtures'].items()})
        args.output.mkdir()
        shutil.copyfile(args.request, args.output / 'request.json')
        shutil.copyfile(args.cleanup, args.output / 'cleanup.json')
        if args.prior_result is not None:
            shutil.copyfile(args.prior_result, args.output / PRIOR_RESULT)
            shutil.copyfile(args.rerun_authorization, args.output / AUTHORIZATION)
        for name in ['gate-result.json', 'compile.log',
                     *[size + '-generate.log' for size in report['fixtures']],
                     *[a['size'] + '-attempt-' + str(a['attempt']) + '.log' for a in report['attempts']],
                     *['disk-stall-resample-' + str(r['attempt']) + '-' + str(i) + '.log'
                       for r in report.get('diskStallResamples', []) for i in range(len(r['executions']))],
                     *['fixture-' + size + '/fixture.json' for size in report['fixtures']]]:
            target = args.output / name
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(args.run / name, target)
        manifest = {'schemaVersion': 1, 'requestId': request['requestId'],
                    'binarySHA256VerifiedAtExport': report['binarySHA256'], 'fixtureBytesVerifiedAtExport': True,
                    'files': {p.relative_to(args.output).as_posix(): digest(p) for p in args.output.rglob('*') if p.is_file()}}
        (args.output / 'qualification.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print(json.dumps(verify_bundle(args.repo, args.output), indent=2))


if __name__ == '__main__':
    main()
