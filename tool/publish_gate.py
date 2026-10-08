"""Only publish the exact signed APK whose native QA was explicitly accepted."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import zipfile
from android_release import check_candidate_history, check_version, fingerprint
from app_version import verify_release_kind


def verify_metadata(metadata, sha, accepted, actual, expected_version, pin):
    if not re.fullmatch(r'[0-9a-fA-F]{64}', accepted):
        raise ValueError('Supply the exact SHA-256 after native APK installation/QA')
    if (metadata['source_commit'] != sha or metadata['apk_sha256'] != actual
            or accepted.lower() != actual or metadata['certificate_sha256'] != pin
            or (metadata['version'], metadata['version_code']) != expected_version):
        raise ValueError('Accepted APK identity does not match candidate artifacts/source')


def verify_candidate_inventory(dist, source_sha):
    expected_files = {'tandemlog-linux-x64.flatpak', 'linux-SHA256SUMS.txt', 'linux-startup.json', 'linux-install-smoke.json',
                      'tandemlog-windows-x64-unsigned-setup.exe', 'windows-SHA256SUMS.txt', 'windows-install-smoke.json',
                      'tandemlog-android.apk', 'android-SHA256SUMS.txt',
                      'android-signature.txt', 'android-release-metadata.json'}
    portable_files = {'tandemlog-windows-x64-unsigned-portable.zip',
                      'windows-portable-SHA256SUMS.txt', 'windows-portable-provenance.json'}
    files = list(dist.iterdir())
    names = {p.name for p in files}
    if (names not in (expected_files, expected_files | portable_files)
            or any(p.is_symlink() or not p.is_file() or p.stat().st_size >= 2*1024**3
                   for p in files)):
        raise ValueError('Missing/unexpected candidate assets or oversized asset')
    if names == expected_files:
        return  # Previously accepted candidates did not contain portable QA.
    verify_portable_evidence(dist, source_sha)


def stream_sha256(stream):
    digest = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        digest.update(chunk)
    return digest.hexdigest()


def verify_portable_evidence(dist, source_sha):
    archive = dist / 'tandemlog-windows-x64-unsigned-portable.zip'
    with archive.open('rb') as stream:
        digest = stream_sha256(stream)
    metadata = json.loads((dist / 'windows-portable-provenance.json').read_text())
    if (not isinstance(metadata, dict) or not re.fullmatch(r'[0-9a-f]{40}', source_sha)
            or metadata.get('source_revision') != source_sha
            or not re.fullmatch(r'[0-9]+', str(metadata.get('github_run_id', '')))
            or metadata.get('artifact') != archive.name
            or metadata.get('artifact_sha256') != digest
            or (dist / 'windows-portable-SHA256SUMS.txt').read_text()
            != f'{digest}  {archive.name}\n'):
        raise ValueError('Portable QA archive identity does not match candidate')
    hashes = metadata.get('payload_sha256')
    required = {'tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                'data/flutter_assets/AssetManifest.bin'}
    if (not isinstance(hashes, dict) or not required <= hashes.keys()
            or any(not isinstance(value, str) or not re.fullmatch(r'[0-9a-f]{64}', value)
                   for value in hashes.values())):
        raise ValueError('Portable QA payload inventory is incomplete or invalid')
    with zipfile.ZipFile(archive) as zipped:
        members = zipped.infolist()
        names = [member.filename for member in members]
        if (set(names) != hashes.keys() or len(set(name.casefold() for name in names)) != len(names)
                or sum(member.file_size for member in members) >= 2*1024**3):
            raise ValueError('Portable QA member inventory does not match provenance')
        for member in members:
            path = PurePosixPath(member.filename)
            file_kind = (member.external_attr >> 16) & 0o170000
            if (path.is_absolute() or '..' in path.parts or '\\' in member.filename
                    or ':' in member.filename or path.as_posix() != member.filename
                    or member.is_dir() or member.flag_bits & 1
                    or file_kind not in (0, 0o100000)):
                raise ValueError('Unsafe portable QA member')
            with zipped.open(member) as stream:
                if stream_sha256(stream) != hashes[member.filename]:
                    raise ValueError('Portable QA member differs from provenance')


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
    verify_release_kind(expected[0], os.environ['RELEASE_KIND'],
                        os.environ.get('LEE_ACCEPTED_STABLE') == 'true')
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
    check_candidate_history(expected, sha)
    dist = Path('dist')
    verify_candidate_inventory(dist, sha)
    for platform in ('linux', 'windows'):
        verify_install_smoke(json.loads((dist / f'{platform}-install-smoke.json').read_text()),
                             require_changed_commit=platform == 'linux')
    apk = dist / 'tandemlog-android.apk'
    verify_metadata(json.loads((dist / 'android-release-metadata.json').read_text()), sha,
                    os.environ['ANDROID_VERIFIED_SHA256'], hashlib.sha256(apk.read_bytes()).hexdigest(),
                    expected, fingerprint(Path('android/signing-certificate.sha256').read_text()))
    print('Exact tested APK, signer, source, version, installed desktop QA and asset set verified.')
