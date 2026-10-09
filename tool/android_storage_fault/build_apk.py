"""Compile isolated debug QA overlay of immutable accepted production source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'com.reddraggone9.tandemlog.storagefaulttest'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tracked_hashes(snapshot, paths):
    return {str(path.relative_to(snapshot)): sha(path)
            for name in paths for path in sorted((snapshot / name).rglob('*'))
            if path.is_file()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', args.revision + '^{commit}'], cwd=ROOT, text=True).strip()
    overlay_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    snapshot = Path(tempfile.mkdtemp(prefix='tandemlog-storage-fault-source-'))
    source_archive = output / 'production-source.tar'
    with source_archive.open('wb') as handle:
        subprocess.run(['git', 'archive', revision], cwd=ROOT, stdout=handle, check=True)
    with tarfile.open(source_archive) as archive:
        archive.extractall(snapshot, filter='data')
    before = tracked_hashes(snapshot, ['lib', 'native'])
    lock_hash = sha(snapshot / 'pubspec.lock')
    overlay = snapshot / 'tool/android_storage_fault'
    overlay.mkdir(parents=True, exist_ok=True)
    overlay_hashes = {}
    for name in ('harness.dart', 'main.dart'):
        data = (Path(__file__).parent / name).read_bytes()
        (overlay / name).write_bytes(data)
        overlay_hashes[name] = sha(overlay / name)
    gradle = snapshot / 'android/app/build.gradle.kts'
    text = gradle.read_text()
    needle = 'applicationId = "com.reddraggone9.tandemlog"'
    if text.count(needle) != 1:
        raise ValueError('Unexpected application ID')
    gradle.write_text(text.replace(needle, f'applicationId = "{PACKAGE}"'))
    manifest = snapshot / 'android/app/src/main/AndroidManifest.xml'
    text = manifest.read_text()
    for needle in ('android:label="Tandemlog"', 'android:name=".MainActivity"'):
        if text.count(needle) != 1:
            raise ValueError('Unexpected manifest identity')
    manifest.write_text(text.replace('android:label="Tandemlog"',
                                    'android:label="TEST ONLY Storage Faults"')
                       .replace('android:name=".MainActivity"',
                                'android:name="com.reddraggone9.tandemlog.MainActivity"'))
    tracked_names = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', revision],
                                            cwd=ROOT, text=True).splitlines()
    patched_inputs = {name: sha(snapshot / name) for name in tracked_names}
    subprocess.run(['flutter', 'pub', 'get', '--offline', '--enforce-lockfile'], cwd=snapshot, check=True)
    subprocess.run(['flutter', 'analyze', '--no-pub', 'tool/android_storage_fault'], cwd=snapshot, check=True)
    subprocess.run(['flutter', 'build', 'apk', '--debug', '--no-pub', '--target',
                    'tool/android_storage_fault/main.dart',
                    '--dart-define=STORAGE_FAULT_SOURCE=' + revision], cwd=snapshot, check=True)
    if tracked_hashes(snapshot, ['lib', 'native']) != before or sha(snapshot / 'pubspec.lock') != lock_hash:
        raise ValueError('Production libraries/native/lockfile changed')
    if {name: sha(snapshot / name) for name in tracked_names} != patched_inputs:
        raise ValueError('Build modified an archived tracked input beyond the allowed identity patches')
    if {name: sha(overlay / name) for name in overlay_hashes} != overlay_hashes:
        raise ValueError('Build modified the QA target overlay')
    apk = output / 'tandemlog-TEST-ONLY-storage-fault-debug.apk'
    apk.write_bytes((snapshot / 'build/app/outputs/flutter-apk/app-debug.apk').read_bytes())
    subprocess.run(['python', str(snapshot / 'tool/native_build_gates.py'), 'verify_payload',
                    '--platform', 'android', '--payload', str(apk)], cwd=snapshot, check=True)
    build_tools = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
    with (output / 'signature.txt').open('w') as handle:
        subprocess.run([str(build_tools / 'apksigner'), 'verify', '--print-certs', str(apk)], stdout=handle, check=True)
    with (output / 'badging.txt').open('w') as handle:
        subprocess.run([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], stdout=handle, check=True)
    if f"name='{PACKAGE}'" not in (output / 'badging.txt').read_text().splitlines()[0]:
        raise ValueError('Packaged QA identity differs')
    with zipfile.ZipFile(apk) as archive:
        native = {name: hashlib.sha256(archive.read(name)).hexdigest()
                  for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
    receipt = {
        'sourceRevision': revision, 'overlayRevision': overlay_revision,
        'productionLibraryNativeSha256': before, 'pubspecLockSha256': lock_hash,
        'productionSourceArchiveSha256': sha(source_archive),
        'patchedTrackedInputSha256': patched_inputs,
        'package': PACKAGE, 'target': 'tool/android_storage_fault/main.dart',
        'testOnly': True, 'debugSigned': True, 'overlaySha256': overlay_hashes,
        'buildScriptSha256': sha(Path(__file__)), 'packagedNativeSha256': native,
        'apk': apk.name, 'apkSha256': sha(apk),
        'snapshotOnlyChanges': ['separate applicationId', 'test label',
                                'fully qualified existing MainActivity', 'two-file QA target'],
        'limits': 'Not owner-signed production app, SAF, physical power failure or directory-barrier proof.',
    }
    tooling = output / 'qa-source'
    tooling.mkdir()
    for name in ('harness.dart', 'main.dart', 'build_apk.py', 'run_on_device.py', 'README.md'):
        (tooling / name).write_bytes((Path(__file__).parent / name).read_bytes())
    receipt['qaToolingSha256'] = {path.name: sha(path) for path in sorted(tooling.iterdir())}
    (output / 'provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    (output / 'SHA256SUMS.txt').write_text(f'{sha(apk)}  {apk.name}\n')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
