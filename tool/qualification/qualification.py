"""Reusable q16 preparation/admission/launch/seal, with explicit private paths.

No action runs by default. The controller remains the reviewed, host-provisioned
controller pinned by the source profile, not a copied or relaxed implementation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['prepare', 'run', 'seal'])
    for name in ('repo', 'output', 'lab', 'controller', 'dart', 'native-library',
                 'sqlite-library', 'package-config'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--admission-seconds', type=int, default=3600)
    a = p.parse_args()
    if not 120 <= a.admission_seconds <= 86400:
        p.error('admission-seconds must be between 120 and 86400')
    profile = json.loads((a.repo / 'tool/performance/reference-host-v1.json').read_text())
    controller_hash = hashlib.sha256(a.controller.read_bytes()).hexdigest()
    if controller_hash != profile['controllerSHA256']:
        raise ValueError('Controller differs from source profile')
    scripts = Path(__file__).resolve().parent
    launcher = scripts / 'launch_reference.py'
    a.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PRODUCT=str(a.repo.resolve()), REF=str(a.output.resolve()),
               Q=str(a.lab.resolve()), CTRL=str(a.controller.resolve()),
               R8_SHA=controller_hash, LAUNCHER=str(launcher),
               LAUNCHER_SHA=hashlib.sha256(launcher.read_bytes()).hexdigest(),
               DART=str(a.dart.resolve()), NATIVE=str(a.native_library.resolve()),
               SQLITE=str(a.sqlite_library.resolve()), PACKAGE_CONFIG=str(a.package_config.resolve()),
               SCRIPTS=str(scripts), ADMISSION_SECONDS=str(a.admission_seconds))
    script = {'prepare': 'prepare.sh', 'run': 'coordinate.sh', 'seal': 'verify-seal.sh'}[a.action]
    subprocess.run(['bash', str(scripts / script)], env=env, check=True)


if __name__ == '__main__':
    main()
