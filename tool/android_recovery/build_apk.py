"""Build a DEBUG, separately identified test APK from an exact committed source.

Run after sourcing /workspace/toolchains/env.sh. Never changes repository build
configuration, lib/main.dart, production identity, or signing credentials.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'com.reddraggone9.tandemlog.recoverytest'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--snapshot-root', type=Path, default=Path(tempfile.gettempdir()))
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', args.revision + '^{commit}'], cwd=ROOT, text=True).strip()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    snapshot = Path(tempfile.mkdtemp(prefix='tandemlog-recovery-source-', dir=args.snapshot_root))
    archive = destination / 'committed-source.tar'
    with archive.open('wb') as handle:
        subprocess.run(['git', 'archive', revision], cwd=ROOT, stdout=handle, check=True)
    with tarfile.open(archive) as handle:
        handle.extractall(snapshot, filter='data')
    archive.unlink()
    overlay = snapshot / 'tool/android_recovery'
    overlay.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name in ('harness.dart', 'main.dart'):
        data = (Path(__file__).parent / name).read_bytes()
        (overlay / name).write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    gradle = snapshot / 'android/app/build.gradle.kts'
    original = gradle.read_text()
    needle = 'applicationId = "com.reddraggone9.tandemlog"'
    if original.count(needle) != 1:
        raise RuntimeError('Unexpected application identity configuration')
    gradle.write_text(original.replace(needle, f'applicationId = "{PACKAGE}"'))
    manifest = snapshot / 'android/app/src/main/AndroidManifest.xml'
    content = manifest.read_text()
    content = content.replace('android:label="Tandemlog"', 'android:label="TEST ONLY Tandemlog Recovery"').replace('android:name=".MainActivity"', 'android:name="com.reddraggone9.tandemlog.MainActivity"')
    manifest.write_text(content)
    subprocess.run(['flutter', 'pub', 'get', '--offline'], cwd=snapshot, check=True)
    subprocess.run(['flutter', 'analyze', 'tool/android_recovery'], cwd=snapshot, check=True)
    subprocess.run(['flutter', 'build', 'apk', '--debug', '--target', 'tool/android_recovery/main.dart', '--dart-define=RECOVERY_SOURCE_REVISION=' + revision], cwd=snapshot, check=True)
    apk = destination / 'tandemlog-TEST-ONLY-recovery-debug.apk'
    apk.write_bytes((snapshot / 'build/app/outputs/flutter-apk/app-debug.apk').read_bytes())
    with zipfile.ZipFile(apk) as payload:
        native_hashes = {name: hashlib.sha256(payload.read(name)).hexdigest() for name in payload.namelist() if name.startswith('lib/') and name.endswith('.so')}
    provenance = {'pubspecLockSha256': hashlib.sha256((snapshot / 'pubspec.lock').read_bytes()).hexdigest(), 'packagedNativeSha256': native_hashes, 'sourceRevision': revision, 'snapshot': str(snapshot), 'package': PACKAGE, 'target': 'tool/android_recovery/main.dart', 'testOnly': True, 'debugSigned': True, 'overlaySha256': hashes, 'snapshotOnlyChanges': ['applicationId', 'application label', 'fully qualified existing MainActivity', 'harness overlay'], 'apk': str(apk), 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
    (destination / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(json.dumps(provenance, indent=2))


if __name__ == '__main__':
    main()
