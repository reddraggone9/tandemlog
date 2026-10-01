"""Only publish the exact signed APK whose native QA was explicitly accepted."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from android_release import check_version, fingerprint


def verify_metadata(metadata, sha, accepted, actual, expected_version, pin):
    if not re.fullmatch(r'[0-9a-fA-F]{64}', accepted):
        raise ValueError('Supply the exact SHA-256 after native APK installation/QA')
    if (metadata['source_commit'] != sha or metadata['apk_sha256'] != actual
            or accepted.lower() != actual or metadata['certificate_sha256'] != pin
            or (metadata['version'], metadata['version_code']) != expected_version):
        raise ValueError('Accepted APK identity does not match candidate artifacts/source')


def verify_install_smoke(report, require_changed_commit=False):
    phases = report.get('phases', [])
    required = ['after-install', 'after-upgrade', 'after-uninstall', 'after-reinstall']
    if [phase.get('phase') for phase in phases] != required:
        raise ValueError('Missing installed desktop lifecycle QA phases')
    for phase in phases:
        expected_launch = phase['phase'] != 'after-uninstall'
        if phase.get('passed') is not True or phase.get('loaded_projection') is not expected_launch:
            raise ValueError('Installed desktop launch/data preservation QA did not pass')

    if require_changed_commit:
        if any(phase.get('sandbox_stopped') is not True for phase in phases
               if phase['phase'] != 'after-uninstall'):
            raise ValueError('Synthetic Flatpak instance cleanup was not verified')
        upgrade = report.get('upgrade', {})
        commits = [upgrade.get(key, '') for key in ('candidate_commit', 'baseline_commit')]
        if (not all(re.fullmatch(r'[0-9a-f]{64}', commit) for commit in commits)
                or commits[0] == commits[1]
                or any(upgrade.get(key) is not True for key in
                       ('baseline_payload_equal', 'baseline_permissions_equal', 'final_candidate_restored'))):
            raise ValueError('Flatpak real commit replacement with unchanged payload was not verified')


if __name__ == '__main__':
    expected = check_version()
    tag = os.environ['CANDIDATE']
    if tag != 'v' + expected[0]:
        raise ValueError('Tag must match candidate source version')
    tags = subprocess.check_output(['git', 'tag', '--list'], text=True).splitlines()
    if tag in tags:
        raise ValueError('Never overwrite an existing candidate tag')
    remote = subprocess.run(['git', 'ls-remote', '--exit-code', '--tags', 'origin', f'refs/tags/{tag}'], capture_output=True)
    if remote.returncode != 2:
        raise ValueError('Tag exists remotely or remote absence could not be verified')
    sha = os.environ['CANDIDATE_SHA']
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != sha:
        raise ValueError('Checkout is not the validated source')
    dist = Path('dist')
    expected_files = {'tandemlog-linux-x64.flatpak', 'linux-SHA256SUMS.txt', 'linux-startup.json', 'linux-install-smoke.json',
                      'tandemlog-windows-x64-unsigned-setup.exe', 'windows-SHA256SUMS.txt', 'windows-install-smoke.json',
                      'tandemlog-android.apk', 'android-SHA256SUMS.txt',
                      'android-signature.txt', 'android-release-metadata.json'}
    if {p.name for p in dist.iterdir()} != expected_files or any(p.stat().st_size >= 2*1024**3 for p in dist.iterdir()):
        raise ValueError('Missing/unexpected candidate assets or oversized asset')
    for platform in ('linux', 'windows'):
        verify_install_smoke(json.loads((dist / f'{platform}-install-smoke.json').read_text()),
                             require_changed_commit=platform == 'linux')
    apk = dist / 'tandemlog-android.apk'
    verify_metadata(json.loads((dist / 'android-release-metadata.json').read_text()), sha,
                    os.environ['ANDROID_VERIFIED_SHA256'], hashlib.sha256(apk.read_bytes()).hexdigest(),
                    expected, fingerprint(Path('android/signing-certificate.sha256').read_text()))
    print('Exact tested APK, signer, source, version, installed desktop QA and asset set verified.')
