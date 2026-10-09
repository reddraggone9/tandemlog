"""Require actual visible-window proof for the existing exact build56 installer."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

SOURCE = '76c5dd5cb7eedb09d2d4b62f737d429e1abab7d9'
RUN = 37995721678
ARTIFACT = 11646614634
ZIP_SHA = '7721d5edf66b19a5ee344a7a1bc7cb777aae623d688208d2783ccb5315846a4c'
INSTALLER_SHA = 'd391a50969de880b3a87b7b9d35ccfa35a2ecacca7950bbda6e4a32ef23bfb23'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if os.name != 'nt':
        raise RuntimeError('Actual Windows required')
    root = Path(os.environ['RUNNER_TEMP']) / 'exact-visible-build56'
    root.mkdir(exist_ok=False)
    output = Path('visible-proof-dist')
    output.mkdir(exist_ok=False)
    row = json.loads(subprocess.check_output(['gh', 'api',
        f'repos/reddraggone9/tandemlog/actions/artifacts/{ARTIFACT}'], text=True))
    if (row['name'] != 'windows' or row['expired'] or
            row['digest'] != 'sha256:' + ZIP_SHA or
            row['workflow_run']['id'] != RUN or row['workflow_run']['head_sha'] != SOURCE):
        raise ValueError('Exact candidate artifact identity differs')
    archive_path = root / 'candidate-windows.zip'
    with archive_path.open('wb') as handle:
        result = subprocess.run(['gh', 'api',
            f'repos/reddraggone9/tandemlog/actions/artifacts/{ARTIFACT}/zip'],
            stdout=handle, stderr=subprocess.PIPE)
    if result.returncode or sha(archive_path) != ZIP_SHA:
        raise ValueError('Exact candidate artifact download/hash failed')
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or archive.testzip():
            raise ValueError('Corrupt or duplicate artifact members')
        for item in archive.infolist():
            if ('\\' in item.filename or ':' in item.filename or item.filename.startswith('/')
                    or any(part in ('', '.', '..') for part in item.filename.rstrip('/').split('/'))
                    or (item.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError('Unsafe artifact member')
        archive.extractall(root / 'artifact')
    installer = root / 'artifact/tandemlog-windows-x64-unsigned-setup.exe'
    if sha(installer) != INSTALLER_SHA:
        raise ValueError('Exact installer SHA differs')
    for name in ('windows-install-smoke.json', 'windows-portable-provenance.json'):
        data = (root / 'artifact' / name).read_bytes()
        (output / ('candidate-original-' + name)).write_bytes(data)
        print(name + '=' + data.decode(), flush=True)
    provenance = json.loads((root / 'artifact/windows-portable-provenance.json').read_text())
    if provenance['source_revision'] != SOURCE or str(provenance['github_run_id']) != str(RUN):
        raise ValueError('Portable candidate provenance differs')
    original = subprocess.check_output(['git', 'show', SOURCE + ':packaging/smoke.py'])
    text = original.decode()
    needle = "if 'TANDEMLOG_READY_MS=' in line:"
    markers = "if x.startswith('TANDEMLOG_')"
    visible = '                    if found:\n'
    if text.count(needle) != 1 or text.count(markers) != 1 or text.count(visible) != 1:
        raise ValueError('Frozen smoke adapter no longer matches')
    # This private QA copy strengthens only Windows readiness and records route.
    text = text.replace(needle, "if os.name != 'nt' and 'TANDEMLOG_READY_MS=' in line:")
    text = text.replace(markers, "if x.startswith(('TANDEMLOG_', 'WINDOWS_VISIBLE_'))")
    text = text.replace(visible, '                    if not found:\n                        visible_since = None\n' + visible)
    adapted = root / 'require-visible-smoke.py'
    adapted.write_text(text)
    install = subprocess.run([str(installer), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'])
    if install.returncode:
        raise RuntimeError('Exact installer failed')
    executable = Path(os.environ['LOCALAPPDATA']) / 'Programs/Tandemlog/tandemlog.exe'
    if sha(executable) != provenance['payload_sha256']['tandemlog.exe']:
        raise ValueError('Installed exact executable differs')
    # Verify every installed Release payload against the original candidate.
    for name, expected in provenance['payload_sha256'].items():
        if sha(executable.parent / name) != expected:
            raise ValueError('Installed candidate payload differs: ' + name)
    report = output / 'exact-visible-window-smoke.json'
    subprocess.run([sys.executable, str(adapted), '--workspace', str(root / 'synthetic'),
                    '--report', str(report.resolve()), '--phase', 'exact-build56-visible',
                    '--seed', '--', str(executable)], check=True)
    phase = json.loads(report.read_text())['phases']
    marker = 'WINDOWS_VISIBLE_NATIVE_WINDOW_MODEL_VERIFIED_AFTER_STOP'
    if len(phase) != 1 or not phase[0]['passed'] or not phase[0]['loaded_projection'] or marker not in phase[0]['markers']:
        raise ValueError('Actual exact installed visible-window/model proof missing')
    receipt = {'source': SOURCE, 'candidateRun': RUN, 'candidateArtifact': ARTIFACT,
               'candidateZipSha256': ZIP_SHA, 'installerSha256': INSTALLER_SHA,
               'executableSha256': sha(executable),
               'originalSmokeSha256': hashlib.sha256(original).hexdigest(),
               'adaptedSmokeSha256': sha(adapted), 'proof': phase[0],
               'scope': 'Exact installed own-PID OS IsWindowVisible flag continuously sampled for three seconds plus post-stop rebuilt synthetic model/settings/canonical proof; no pixels/occlusion/manual UX claim or rebuild'}
    (output / 'exact-visible-window-provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('EXACT_VISIBLE_BUILD56=' + json.dumps(receipt), flush=True)


if __name__ == '__main__':
    main()
