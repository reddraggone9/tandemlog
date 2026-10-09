"""Package the existing migration child as isolated native Windows QA tooling."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--app-bundle', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--run', required=True)
    args = parser.parse_args()
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != args.source:
        raise ValueError('Harness source must be the checked-out candidate')
    files = sorted(path for path in args.bundle.rglob('*') if path.is_file())
    executable = args.bundle / 'bin/local_profile_migration_child.exe'
    libraries = [path for path in files if path.suffix.lower() == '.dll' and 'sqlite3' in path.name.lower()]
    if not executable.is_file() or len(libraries) != 1:
        raise ValueError('Expected compiled migration child and one SQLite DLL')
    sqlite_hash = sha(libraries[0])
    matches = [path for path in args.app_bundle.rglob('*')
               if path.is_file() and path.suffix.lower() == '.dll' and sha(path) == sqlite_hash]
    if len(matches) != 1:
        raise ValueError('Harness SQLite DLL must match the actual Release app payload')
    hashes = {path.relative_to(args.bundle).as_posix(): sha(path) for path in files}
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / 'tandemlog-TEST-ONLY-windows-storage-harness.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
        for path in files:
            zipped.write(path, path.relative_to(args.bundle).as_posix())
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() or set(zipped.namelist()) != set(hashes):
            raise ValueError('Incomplete harness archive')
        for name, expected in hashes.items():
            if hashlib.sha256(zipped.read(name)).hexdigest() != expected:
                raise ValueError('Harness archive member changed')
    root = Path(__file__).resolve().parents[1]
    target = root / 'test/support/local_profile_migration_child.dart'
    receipt = {'source': args.source, 'run': args.run, 'test_only': True,
               'target': str(target.relative_to(root)), 'target_sha256': sha(target),
               'pubspec_lock_sha256': sha(root / 'pubspec.lock'),
               'dart_version': subprocess.check_output(['dart', '--version'], text=True).strip(),
               'archive': archive.name, 'archive_sha256': sha(archive),
               'payload_sha256': hashes, 'sqlite_sha256': sqlite_hash,
               'matching_release_sqlite': matches[0].relative_to(args.app_bundle).as_posix(),
               'scope': 'Existing frozen migration child compiled for synthetic native QA; not installed-application evidence'}
    (args.output / 'windows-storage-harness-provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
