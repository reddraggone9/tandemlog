"""Archive the verified Windows build unchanged for isolated native acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    output = args.output.resolve()
    for name in ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                 'data/flutter_assets/AssetManifest.bin'):
        if not (bundle / name).is_file():
            raise SystemExit(f'Missing verified bundle payload: {name}')
    files = sorted(path for path in bundle.rglob('*') if path.is_file())
    hashes = {path.relative_to(bundle).as_posix(): sha256(path.read_bytes())
              for path in files}
    output.mkdir(parents=True, exist_ok=True)
    archive = output / 'tandemlog-windows-x64-unsigned-portable.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as zipped:
        for path in files:
            zipped.write(path, path.relative_to(bundle).as_posix())
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None or set(zipped.namelist()) != set(hashes):
            raise SystemExit('Portable archive is incomplete or corrupt')
        for name, expected in hashes.items():
            if sha256(zipped.read(name)) != expected:
                raise SystemExit(f'Portable archive differs from build: {name}')
    archive_hash = sha256(archive.read_bytes())
    (output / 'windows-portable-SHA256SUMS.txt').write_text(
        f'{archive_hash}  {archive.name}\n', encoding='ascii')
    (output / 'windows-portable-provenance.json').write_text(json.dumps({
        'source_revision': args.source_revision,
        'github_run_id': args.run_id,
        'artifact': archive.name,
        'artifact_sha256': archive_hash,
        'payload_sha256': hashes,
        'scope': 'Exact unsigned Release bundle; isolated synthetic QA only',
    }, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'source_revision': args.source_revision,
        'github_run_id': args.run_id,
        'portable_archive': archive.name,
        'portable_sha256': archive_hash,
        'executable_sha256': hashes['tandemlog.exe'],
        'native_library_sha256': hashes['tandemlog_text.dll'],
    }, sort_keys=True))


if __name__ == '__main__':
    main()
