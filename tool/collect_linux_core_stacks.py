"""Postmortem stacks only; never launch or retry the application.

Raw cores may contain ambient CI credentials and are deliberately not uploaded.
Frame arguments/locals are omitted. The original unchanged startup harness runs
first without a debugger, so capture cannot alter pre-fault execution timing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def owned_cores(root, allowed_pids):
    entries = list(root.iterdir())
    if len(entries) > 2:
        raise RuntimeError('At most two original startup processes expected')
    for path in entries:
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r'core\.[1-9][0-9]*', path.name):
            raise RuntimeError('Unexpected diagnostic core entry')
        if int(path.name.split('.')[1]) not in allowed_pids:
            raise RuntimeError('Core PID is not certified by the original owned-window harness')
    return sorted(entries)


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(256*1024), b''):
            result.update(data)
    return result.hexdigest()


def stack_metadata(text):
    signal = re.search(r'Program terminated with signal (SIG[A-Z0-9]+)', text)
    return {'nativeSignal': signal.group(1) if signal else None,
            'stackCaptured': bool(signal and re.search(r'^#0\s', text, re.MULTILINE))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cores', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if not sys.platform.startswith('linux'):
        parser.error('Linux postmortem diagnosis only')
    repo = args.source.resolve(strict=True)
    binary = repo/'build/linux/x64/release/bundle/tandemlog'
    args.output.mkdir(exist_ok=False)
    report = {'diagnosticOnly': True, 'acceptance': False,
              'applicationRerunByCollector': False, 'rawCoresUploaded': False,
              'collectorSHA256': sha(Path(__file__)),
              'sourceRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
              'binarySHA256': sha(binary), 'cores': []}
    try:
        certified = set()
        for receipt in args.output.parent.glob('run-*.json'):
            if receipt.is_symlink() or receipt.stat().st_size > 256*1024:
                raise RuntimeError('Unexpected original-process receipt')
            pid = json.loads(receipt.read_text()).get('shutdown', {}).get('pid')
            if isinstance(pid, int) and pid > 1:
                certified.add(pid)
        report['certifiedApplicationPIDs'] = sorted(certified)
        for core in owned_cores(args.cores, certified):
            if core.stat().st_size > 512*1024*1024:
                raise RuntimeError('Core exceeds the explicit 512MiB bound')
            log = args.output/(core.name+'.stack.txt')
            command = ['gdb', '--nx', '--batch', '-iex', 'set auto-load safe-path /nonexistent',
                       '-iex', 'set debuginfod enabled off', '-iex', 'set pagination off',
                       '-iex', 'set print frame-arguments none', '-ex', 'info program',
                       '-ex', 'thread apply all bt 32', '-ex', 'info sharedlibrary',
                       '--se='+str(binary), '--core='+str(core)]
            result = {'name': core.name, 'bytes': core.stat().st_size,
                      'sha256': sha(core), 'stackFile': log.name}
            with log.open('w') as output:
                try:
                    process = subprocess.run(command, cwd=repo, stdin=subprocess.DEVNULL,
                                             stdout=output, stderr=subprocess.STDOUT, timeout=60)
                    result['gdbExit'] = process.returncode
                except subprocess.TimeoutExpired:
                    result['error'] = 'Bounded postmortem debugger timeout'
            result.update(stack_metadata(log.read_text(errors='replace')))
            report['cores'].append(result)
        report['coreCount'] = len(report['cores'])
    except Exception as error:
        report['error'] = repr(error)
    finally:
        (args.output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    return 1 if report.get('error') or any(c.get('gdbExit') != 0 or not c['stackCaptured'] for c in report['cores']) else 0


if __name__ == '__main__':
    sys.exit(main())
