"""Verify exact downloaded candidate artifacts with the repository's own gate functions.

Usage: python3 -I verify-candidate.py <merged-dist-dir> <source-sha>
Writes candidate-verification.json next to this script. Never modifies artifacts.
"""
import hashlib, json, os, subprocess, sys
from pathlib import Path

from release_context import context, configure
parser = context('Verify exact downloaded candidate with source gates.')
parser.add_argument('--dist', type=Path, required=True)
parser.add_argument('--source', required=True)
parser.add_argument('--build-tools', type=Path, required=True)
args = configure(parser.parse_args())
repo = args.repo_dir
sys.path.insert(0, str(repo / 'tool'))
os.chdir(repo)  # check_version reads the exact stable source pubspec.yaml
from android_release import fingerprint, verify_apk, check_version  # noqa: E402
from publish_gate import verify_candidate_inventory, verify_install_smoke, verify_metadata  # noqa: E402

dist, sha = args.dist.resolve(), args.source
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == sha
bt = args.build_tools.resolve()
expected = check_version()
assert args.tag == 'v' + expected[0], expected
pin = fingerprint((repo / 'android/signing-certificate.sha256').read_text())
verify_candidate_inventory(dist, sha)
for platform in ('linux', 'windows'):
    verify_install_smoke(json.loads((dist / f'{platform}-install-smoke.json').read_text()),
                         require_changed_commit=platform == 'linux')
sums = {}
for f in ('linux-SHA256SUMS.txt', 'windows-SHA256SUMS.txt', 'android-SHA256SUMS.txt', 'windows-portable-SHA256SUMS.txt'):
    for line in (dist / f).read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = name.lstrip('*')
        actual = hashlib.sha256((dist / name).read_bytes()).hexdigest()
        assert actual == digest, (f, name)
        sums[name] = digest
apk = dist / 'tandemlog-android.apk'
actual = hashlib.sha256(apk.read_bytes()).hexdigest()
certs = subprocess.check_output([bt / 'apksigner', 'verify', '--print-certs', '--verbose', apk], text=True)
badging = subprocess.check_output([bt / 'aapt', 'dump', 'badging', apk], text=True)
verify_apk(certs, badging, pin, expected)
verify_metadata(json.loads((dist / 'android-release-metadata.json').read_text()), sha, actual, actual, expected, pin)
out = {'source': sha, 'version': expected, 'pin': pin, 'apk_sha256': actual, 'checksums': sums,
       'apksigner_schemes': [l for l in certs.splitlines() if l.startswith('Verified using')],
       'sdk_line': [l for l in badging.splitlines() if 'sdkVersion' in l],
       'native_code': [l for l in badging.splitlines() if l.startswith('native-code')],
       'debuggable': 'application-debuggable' in badging, 'result': 'PASS'}
(args.output / 'candidate-verification.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps(out, indent=2))
