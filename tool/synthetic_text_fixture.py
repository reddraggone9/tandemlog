"""QA-only baseline construction for newly generated disposable scalar logs.

Uses production native seed digests/frontiers through the established historical
fixture API. Its cache is separate from the app profile being measured.
"""
import json
from pathlib import Path
import shutil
import subprocess


def resolve_dart():
    # Same SDK resolution as package_storage_harness.py: Windows subprocesses
    # must execute the actual pinned SDK binary, not the Flutter batch wrapper.
    dart = shutil.which('dart')
    if dart is None:
        raise RuntimeError('Pinned Dart executable is unavailable')
    dart = Path(dart)
    if dart.suffix.lower() == '.bat':
        dart = dart.parent/'cache/dart-sdk/bin/dart.exe'
    if not dart.is_file():
        raise RuntimeError('Pinned SDK Dart executable is unavailable')
    return dart.resolve()


def initialize_fixture(folder, workspace, native_library):
    workspace = Path(workspace)
    private = workspace / 'text-seed-private'
    if private.exists():
        raise RuntimeError('Synthetic seed cache must be fresh; existing state retained')
    library = Path(native_library).resolve()
    if not library.is_file():
        raise RuntimeError('Pinned synthetic fixture native library is missing')
    repo = Path(__file__).resolve().parents[1]
    try:
        result = subprocess.run(
            [str(resolve_dart()), 'run', str(repo / 'tool/initialize_synthetic_text_fixture.dart'),
             str(Path(folder).resolve()), str(private.resolve()), str(library)],
            cwd=repo, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired as error:
        for name, content in (('stdout', error.stdout), ('stderr', error.stderr)):
            data = content or b''
            if isinstance(data, str):
                data = data.encode('utf-8')
            (workspace/f'text-seed.{name}.log').write_bytes(data)
        raise RuntimeError('Synthetic text initialization timed out; diagnostics retained') from error
    (workspace / 'text-seed.stdout.log').write_text(result.stdout, encoding='utf-8')
    (workspace / 'text-seed.stderr.log').write_text(result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError('Synthetic text initialization failed: '+result.stdout+result.stderr)
    receipt = json.loads(result.stdout)
    if receipt.get('synthetic') is not True or receipt.get('initialized') is not True:
        raise RuntimeError('Synthetic initializer did not confirm admission')
    (workspace / 'synthetic-text-fixture.json').write_text(
        json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    return receipt
