"""Run the exact reviewed Ubuntu AppStream tools without changing host packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'evidence/flatpak-2026.10.4-rc.2/tool-audit-manifest.json'
PACKAGES = {
    'appstream_1.0.2-1build6_amd64.deb': 'main/a/appstream',
    'appstream-compose_1.0.2-1build6_amd64.deb': 'universe/a/appstream',
    'libappstream5_1.0.2-1build6_amd64.deb': 'main/a/appstream',
    'libappstream-compose0_1.0.2-1build6_amd64.deb': 'main/a/appstream',
    'libxmlb2_0.3.18-1_amd64.deb': 'main/libx/libxmlb',
    'libstemmer0d_2.2.0-4build1_amd64.deb': 'main/s/snowball',
}


def load_packages(manifest=MANIFEST):
    entries = json.loads(Path(manifest).read_text())
    packages = [entry for entry in entries if entry['file'].endswith('.deb')]
    if len(packages) != len(PACKAGES) or {p['file'] for p in packages} != set(PACKAGES):
        raise ValueError('Expected exactly the six previously audited amd64 packages')
    for package in packages:
        filename = package['file']
        expected_url = f'https://archive.ubuntu.com/ubuntu/pool/{PACKAGES[filename]}/{filename}'
        if package['url'] != expected_url:
            raise ValueError('Package URL differs from the audited Ubuntu archive URL')
        if not re.fullmatch(r'[0-9a-f]{64}', package.get('sha256', '')):
            raise ValueError('Package lacks a SHA256 verification obligation')
        size = package.get('size')
        if not isinstance(size, int) or isinstance(size, bool) or not 0 < size <= 2_000_000:
            raise ValueError('Package lacks a bounded exact size')
    return packages


def download_packages(directory, packages, opener=urllib.request.urlopen):
    directory = Path(directory)
    directory.mkdir(parents=True)
    verified = []
    for package in packages:
        with opener(package['url'], timeout=30) as response:
            if response.geturl() != package['url']:
                raise ValueError('Unexpected redirect away from the audited package URL')
            data = response.read(package['size'] + 1)
        if len(data) != package['size'] or hashlib.sha256(data).hexdigest() != package['sha256']:
            raise ValueError(f"Audited package size/SHA256 mismatch: {package['file']}")
        path = directory / package['file']
        path.write_bytes(data)
        verified.append((package, path))
    return verified


def extract_packages(directory, verified):
    directory = Path(directory)
    directory.mkdir(parents=True)
    for package, path in verified:
        name, version, arch = package['file'].removesuffix('.deb').rsplit('_', 2)
        result = subprocess.run(['dpkg-deb', '--field', str(path), 'Package', 'Version', 'Architecture'],
                                check=True, text=True, capture_output=True)
        fields = dict(line.split(': ', 1) for line in result.stdout.strip().splitlines())
        if fields != {'Package': name, 'Version': version, 'Architecture': arch}:
            raise ValueError('Downloaded package identity does not match audited filename')
        # --extract only unpacks data.tar; no postinst, triggers or system install.
        subprocess.run(['dpkg-deb', '--extract', str(path), str(directory)], check=True)


def write_wrapper(directory, extracted):
    directory, extracted = Path(directory), Path(extracted).resolve()
    directory.mkdir(parents=True)
    wrapper = directory / 'appstreamcli'
    wrapper.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import sys

root = Path(ROOT_LITERAL)
args = sys.argv[1:]
if args and args[0] == 'compose':
    target = root / 'usr/libexec/appstreamcli-compose'
    args = args[1:]
else:
    target = root / 'usr/bin/appstreamcli'
env = dict(os.environ, LD_LIBRARY_PATH=str(root / 'usr/lib/x86_64-linux-gnu'))
os.execve(str(target), [str(target), *args], env)
'''.replace('ROOT_LITERAL', repr(str(extracted))))
    wrapper.chmod(0o755)
    return wrapper


def prepare_tools(destination, packages, opener=urllib.request.urlopen):
    destination = Path(destination).resolve()
    destination.mkdir(parents=True)
    # Verify the entire closure before any package extraction or executable read.
    verified = download_packages(destination / 'packages', packages, opener)
    extracted = destination / 'extracted'
    extract_packages(extracted, verified)
    wrapper = write_wrapper(destination / 'bin', extracted)
    return wrapper


def verify_runtime(wrapper):
    root = wrapper.parent.parent / 'extracted'
    env = dict(os.environ, LD_LIBRARY_PATH=str(root / 'usr/lib/x86_64-linux-gnu'))
    dependencies = {}
    for relative in ['usr/bin/appstreamcli', 'usr/libexec/appstreamcli-compose']:
        result = subprocess.run(['ldd', str(root / relative)], env=env,
                                check=True, text=True, capture_output=True)
        if 'not found' in result.stdout:
            raise ValueError('The audited AppStream runtime closure has missing libraries')
        sonames = ['libappstream.so.5', 'libxmlb.so.2', 'libstemmer.so.0d']
        if relative.endswith('appstreamcli-compose'):
            sonames.append('libappstream-compose.so.0')
        for soname in sonames:
            library = root / 'usr/lib/x86_64-linux-gnu' / soname
            expected = f'{soname} => {library} '
            if expected not in result.stdout:
                raise ValueError('Audited tool must load its extracted library closure')
        dependencies[relative] = result.stdout
    version = subprocess.run([str(wrapper), '--version'], check=True, text=True,
                             capture_output=True).stdout.strip()
    if version != 'AppStream version: 1.0.2':
        raise ValueError('Runtime AppStream version differs from audited source')
    return version, dependencies


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--destination', required=True)
    parser.add_argument('--github-path')
    args = parser.parse_args()
    packages = load_packages()
    wrapper = prepare_tools(args.destination, packages)
    version, dependencies = verify_runtime(wrapper)
    receipt = {'method': 'SHA256-verified data-only extraction; no package installation or hooks',
               'packages': packages, 'runtime_version': version, 'elf_dependencies': dependencies,
               'wrapper': str(wrapper), 'library_environment': 'exact tool child only',
               'host_packages_modified': False}
    (wrapper.parent.parent / 'tool-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    if args.github_path:
        with Path(args.github_path).open('a') as output:
            output.write(str(wrapper.parent) + '\n')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
