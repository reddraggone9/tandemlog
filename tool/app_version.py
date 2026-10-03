"""Approved CalVer plus explicit historical prerelease build-number parsing."""
from pathlib import Path
import re
import sys


def release_components(name):
    match = re.fullmatch(r'([1-9][0-9]{3})\.([1-9]|1[0-2])\.(0|[1-9][0-9]*)(?:-rc\.([1-9][0-9]*))?', name)
    if not match:
        raise ValueError('Expected year.month.patch or year.month.patch-rc.N (unpadded month)')
    year, month, patch, rc = match.groups()
    return int(year), int(month), int(patch), int(rc) if rc else None


def version(text):
    matches = re.findall(r'^version: ([^\s+]+)\+([1-9][0-9]*)$', text, re.M)
    if len(matches) != 1:
        raise ValueError('Expected one explicit CalVer version and positive integer build number')
    name, build = matches[0]
    year, month, patch, _ = release_components(name)
    code = int(build)
    # Runner.rc uses all four components; fail before resource compilation.
    if any(component > 65535 for component in (year, month, patch, code)):
        raise ValueError('Windows version resource components must fit unsigned 16-bit integers')
    return name, code


def historical_version(text):
    try:
        return version(text)
    except ValueError:
        # Retain the build floor of the actual disposable pre-CalVer releases.
        # This does not admit those names as a new candidate format.
        match = re.search(r'^version: (0\.1\.0-rc\.[1-9][0-9]*)\+([1-9][0-9]*)$', text, re.M)
        if not match:
            raise ValueError('Unsupported historical release version')
        return match[1], int(match[2])


def verify_release_kind(name, kind, lee_accepted=False):
    rc = release_components(name)[3]
    if kind == 'prerelease' and rc is not None:
        return
    if kind == 'stable' and rc is None and lee_accepted:
        return
    raise ValueError('Release channel/version mismatch or missing explicit Lee stable acceptance')


if __name__ == '__main__':
    name, build = version(Path('pubspec.yaml').read_text())
    if sys.argv[1:] == ['--windows-resource']:
        year, month, patch, _ = release_components(name)
        print(f'{year}.{month}.{patch}.{build}')
    elif sys.argv[1:]:
        raise ValueError('Unsupported version command')
    else:
        print(f'Validated CalVer {name}, build {build}, and Windows resource bounds.')
