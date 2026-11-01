"""Prepare stable channel metadata from verified GitHub Latest receipts.

This tool does not publish, install, operate hosts, create a signing key or
fetch an unverified URL. The release owner supplies anonymous release/Latest
receipts after normal publication verification. Prereleases never advance feeds.
"""
import argparse
import json
import re
from pathlib import Path

from app_version import release_components

REPO = 'reddraggone9/tandemlog'
FLATPAK_URL = 'https://reddraggone9.github.io/tandemlog/flatpak'


def stable_asset(release, latest, suffix):
    if (release.get('id') != latest.get('id') or not release.get('id')
            or release.get('tag_name') != latest.get('tag_name')
            or release.get('draft') is not False
            or release.get('prerelease') is not False
            or latest.get('draft') is not False
            or latest.get('prerelease') is not False):
        raise ValueError('Only the verified current stable Latest advances channels')
    tag = release['tag_name']
    if not isinstance(tag, str) or not tag.startswith('v'):
        raise ValueError('Invalid stable tag')
    version = tag[1:]
    release_components(version)
    if '-rc.' in version:
        raise ValueError('Prerelease never advances stable channels')
    name = f'tandemlog-{version}-{suffix}'
    matches = [a for a in release.get('assets', []) if a.get('name') == name]
    if len(matches) != 1:
        raise ValueError('Exactly one accepted asset is required')
    asset = matches[0]
    expected_url = f'https://github.com/{REPO}/releases/download/{tag}/{name}'
    digest = asset.get('digest', '')
    if asset.get('browser_download_url') != expected_url or not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Asset URL or SHA256 differs from accepted release')
    return version, expected_url, digest[7:]


def scoop_manifest(release, latest):
    version, url, digest = stable_asset(release, latest, 'windows-x64-portable.zip')
    # Ordinary Windows application support path is shared with Inno. Never
    # persist a package-relative profile or set TANDEMLOG_PROFILE here: doing so
    # creates a second GUI installation identity. Agent profiles stay separate.
    return {
        'version': version,
        'description': 'Shared household tasks and food inventory',
        'homepage': f'https://github.com/{REPO}',
        'license': 'CC0-1.0',
        'architecture': {'64bit': {'url': url, 'hash': digest}},
        'shortcuts': [['tandemlog.exe', 'Tandemlog']],
        'bin': [['cli/bin/tandemlog-cli.exe', 'tandemlog-cli']],
        'notes': 'Requires the Microsoft Visual C++ x64 runtime. Keeps your existing Windows profile. Close Tandemlog before updating. Do not run Inno and Scoop updaters for the same app concurrently.',
        'checkver': {'github': f'https://github.com/{REPO}'},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=Path, required=True)
    parser.add_argument('--latest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = scoop_manifest(json.loads(args.release.read_text()), json.loads(args.latest.read_text()))
    # Fresh output; never silently replace an accepted public channel snapshot.
    args.output.mkdir()
    (args.output / 'bucket').mkdir()
    (args.output / 'bucket/tandemlog.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
