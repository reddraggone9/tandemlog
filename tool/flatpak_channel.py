"""Prepare the Flatpak update channel from one accepted candidate's own repository.

Off until a signing identity is approved. Never creates a key, rebuilds, commits
or publishes: `pack` records what a candidate built, `site` lays out static files
for the separately dispatched Pages workflow, and only for the current stable
Latest whose bundle bytes match. Prereleases never advance the channel.
"""
import argparse
import base64
import hashlib
import json
import re
import subprocess
import tarfile
from pathlib import Path

from update_channels import FLATPAK_URL, stable_asset

APP = 'com.reddraggone9.tandemlog'
REF = f'app/{APP}/x86_64/master'
ARCHIVE = 'flatpak-repo.tar'
PROVENANCE = 'flatpak-repo-provenance.json'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def commit_of(repo):
    result = subprocess.run(['ostree', f'--repo={repo}', 'rev-parse', REF],
                            check=True, capture_output=True, text=True)
    commit = result.stdout.strip()
    if not re.fullmatch(r'[0-9a-f]{64}', commit):
        raise ValueError('Repository has no exact channel commit')
    return commit


def pack(repo, bundle, source_revision, output):
    if not re.fullmatch(r'[0-9a-f]{40}', source_revision):
        raise ValueError('Exact source revision required')
    output.mkdir()  # Fresh: a stale repository must never pass as this candidate.
    commit = commit_of(repo)
    archive = output / ARCHIVE
    with tarfile.open(archive, 'w') as tar:
        tar.add(repo, arcname='repo')
    (output / PROVENANCE).write_text(json.dumps({
        'source': source_revision,
        'ref': REF,
        'commit': commit,
        'bundleSha256': sha256(bundle),
        'archiveSha256': sha256(archive),
    }, indent=2) + '\n')


def extract(archive, destination):
    with tarfile.open(archive) as tar:
        tar.extractall(destination, filter='data')  # Refuses links out and absolute paths.


def signature_fingerprints(repo, commit):
    result = subprocess.run(['ostree', 'show', f'--repo={repo}', commit],
                            check=True, capture_output=True, text=True)
    return set(re.findall(r'(?:Primary key ID|Using RSA key ID|key ID)\s+([0-9A-Fa-f]{16,40})', result.stdout))


def flatpakrepo(public_key):
    return '\n'.join([
        '[Flatpak Repo]',
        'Title=Tandemlog',
        f'Url={FLATPAK_URL}/repo/',
        'Homepage=https://github.com/reddraggone9/tandemlog',
        'Comment=Shared household tasks and food inventory',
        'DefaultBranch=master',
        f'GPGKey={base64.b64encode(public_key).decode()}',
        '',
    ])


def site(archive, provenance, release, latest, public_key, fingerprint, output):
    version, _, bundle_digest = stable_asset(release, latest, 'linux-x64.flatpak')
    record = json.loads(provenance.read_text())
    if (record.get('ref') != REF or sha256(archive) != record.get('archiveSha256')
            or record.get('bundleSha256') != bundle_digest):
        raise ValueError('Repository is not the exact accepted Latest candidate')
    if not re.fullmatch(r'[0-9A-F]{40}', fingerprint) or not public_key.read_bytes():
        raise ValueError('Reviewed signing fingerprint and public key required')
    output.mkdir()
    root = output / 'flatpak'
    root.mkdir()
    extract(archive, root)
    repo = root / 'repo'
    if commit_of(repo) != record['commit']:
        raise ValueError('Repository ref differs from candidate provenance')
    if not (repo / 'summary.sig').is_file():
        raise ValueError('Unsigned repository summary never becomes a channel')
    found = signature_fingerprints(repo, record['commit'])
    if not any(fingerprint.endswith(value.upper()) for value in found):
        raise ValueError('Commit is not signed by the reviewed identity')
    (root / 'tandemlog.flatpakrepo').write_text(flatpakrepo(public_key.read_bytes()))
    (output / '.nojekyll').write_text('')
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    p = commands.add_parser('pack')
    p.add_argument('--repo', type=Path, required=True)
    p.add_argument('--bundle', type=Path, required=True)
    p.add_argument('--source-revision', required=True)
    p.add_argument('--output', type=Path, required=True)
    s = commands.add_parser('site')
    s.add_argument('--archive', type=Path, required=True)
    s.add_argument('--provenance', type=Path, required=True)
    s.add_argument('--release', type=Path, required=True)
    s.add_argument('--latest', type=Path, required=True)
    s.add_argument('--public-key', type=Path, required=True)
    s.add_argument('--fingerprint', required=True)
    s.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'pack':
        pack(args.repo, args.bundle, args.source_revision, args.output)
    else:
        print(site(args.archive, args.provenance, json.loads(args.release.read_text()),
                   json.loads(args.latest.read_text()), args.public_key, args.fingerprint,
                   args.output))


if __name__ == '__main__':
    main()
