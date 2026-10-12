#!/usr/bin/env python3
"""Install/verify the reviewed Gradle repository policy in an isolated CI home."""
import argparse
import hashlib
import os
from pathlib import Path


def policy_paths():
    source = Path(__file__).with_name('gradle-repositories.init.gradle')
    configured_home = os.environ.get('GRADLE_USER_HOME')
    if not configured_home:
        raise SystemExit('Set an explicit isolated GRADLE_USER_HOME before installing or verifying the policy')
    for name in ['GRADLE_OPTS', 'JAVA_OPTS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS']:
        value = os.environ.get(name, '')
        if 'gradle.user.home' in value or '--gradle-user-home' in value:
            raise SystemExit('Gradle home overrides in ' + name + ' are forbidden for protected builds')
    home = Path(configured_home)
    return source, home / 'init.d' / 'tandemlog-repositories.gradle'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'verify'])
    args = parser.parse_args()
    source, target = policy_paths()
    expected = source.read_bytes()
    if args.action == 'install':
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            raise SystemExit('Refusing a symlink at the Gradle policy destination')
        if target.exists() and target.read_bytes() != expected:
            raise SystemExit('Refusing to replace a different Gradle repository policy')
        if not target.exists():
            with target.open('xb') as stream:
                stream.write(expected)
            target.chmod(0o600)
    if not target.is_file() or target.is_symlink() or target.read_bytes() != expected:
        raise SystemExit('Reviewed Gradle repository policy is missing or differs; signing is blocked')
    print('Gradle repository policy verified: sha256=' + hashlib.sha256(expected).hexdigest())


if __name__ == '__main__':
    main()
