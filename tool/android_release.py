"""Non-secret release verification. Never reads or prints private signing inputs."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from app_version import historical_version, version


def fingerprint(text):
    value = ''.join(line.split('#', 1)[0].strip() for line in text.splitlines())
    if not re.fullmatch(r'[0-9a-fA-F]{64}', value):
        raise ValueError('Owner public certificate SHA-256 pin is missing or invalid')
    return value.lower()


def verify_apk(cert_output, badging, pin, expected_version):
    certs = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$', cert_output, re.M)
    if len(certs) != 1 or certs[0].lower() != pin:
        raise ValueError('APK signer does not match the pinned owner certificate')
    name, code = expected_version
    package = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != ('com.reddraggone9.tandemlog', str(code), name):
        raise ValueError('APK package/version does not match source')
    if 'application-debuggable' in badging:
        raise ValueError('Distributable APK must not be debuggable')
    abi = re.search(r'^native-code: (.+)$', badging, re.M)
    if not abi or set(re.findall(r"'([^']+)'", abi[1])) != {'armeabi-v7a', 'arm64-v8a', 'x86_64'}:
        raise ValueError('Expected phone and emulator ABIs in the universal APK')


def check_version():
    current = version(Path('pubspec.yaml').read_text())
    # Builds 1–4 were already handed to testers, including unpublished APKs.
    floor = 4
    for tag in subprocess.check_output(['git', 'tag', '--list', 'v*'], text=True).splitlines():
        text = subprocess.check_output(['git', 'show', f'{tag}:pubspec.yaml'], text=True)
        floor = max(floor, historical_version(text)[1])
    if current[1] <= floor:
        raise ValueError('Android build number must exceed the test-build floor and published tags')
    return current


def check_candidate_codes(current_code, previous_codes):
    if any(current_code <= code for code in previous_codes):
        raise ValueError('Increase Android build number beyond previous signed candidates')


def check_candidate_history(current=None, source_sha=None):
    current = current or check_version()
    repo = os.environ['GITHUB_REPOSITORY']
    sha = source_sha or os.environ['GITHUB_SHA']
    previous = subprocess.check_output([
        'gh', 'api', '--paginate',
        f'repos/{repo}/actions/workflows/android-candidate.yml/runs?event=workflow_dispatch&per_page=100',
        '--jq', '.workflow_runs[] | select(.conclusion == "success" and .head_branch == "main") | .head_sha',
    ], text=True).splitlines()
    codes = []
    for old_sha in set(previous) - {sha}:
        if not re.fullmatch(r'[0-9a-f]{40}', old_sha):
            raise ValueError('Invalid candidate source SHA')
        old = subprocess.check_output(['git', 'show', f'{old_sha}:pubspec.yaml'], text=True)
        codes.append(historical_version(old)[1])
    check_candidate_codes(current[1], codes)


def main():
    if sys.argv[1] == 'candidate-history':
        check_candidate_history()
        return
    if sys.argv[1] == 'preflight':
        check_version()
        fingerprint(Path('android/signing-certificate.sha256').read_text())
        return
    apk = Path(sys.argv[1])
    build_tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
    certs = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    pin = fingerprint(Path('android/signing-certificate.sha256').read_text())
    expected = check_version()
    verify_apk(certs, badging, pin, expected)
    metadata = {'source_commit': os.environ['GITHUB_SHA'], 'version': expected[0], 'version_code': expected[1],
                'certificate_sha256': pin, 'apk_sha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
    (apk.parent / 'android-release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    (apk.parent / 'android-signature.txt').write_text(certs)
    print('Verified release certificate, package, version, non-debuggable flag and universal ABIs.')


if __name__ == '__main__':
    main()
