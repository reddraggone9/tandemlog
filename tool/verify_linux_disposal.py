#!/usr/bin/env python3
"""Observe GTK/Flutter disposal after normal synthetic app exit; no timing gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

from measure_startup import (inspect_stopped_witness, launch, seed_fixture,
                             verify_loaded)

PREFIX = 'TANDEMLOG_LIFECYCLE_PROBE '
OBJECTS = {'window', 'view', 'engine'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_trace(text, pid):
    """Require real finalization on the GTK owning thread before loop return."""
    seen = {name: [] for name in OBJECTS}
    returns = set()
    detached = False
    for line in text.splitlines():
        if not line.startswith(PREFIX):
            continue
        fields = dict(word.split('=', 1) for word in line[len(PREFIX):].split())
        event, name = fields.get('event'), fields.get('object')
        if name not in OBJECTS or fields.get('thread') != str(pid):
            raise RuntimeError('Disposal observation object/thread mismatch')
        if event != 'run-return' and returns:
            raise RuntimeError('Disposal completed after application loop returned')
        history = seen[name]
        if event == 'watch':
            if history:
                raise RuntimeError('Duplicate lifecycle observer')
        elif event == 'detach':
            if name != 'window' or detached or history != ['watch']:
                raise RuntimeError('Invalid window detach order')
            detached = True
        elif event == 'destroyed':
            if name == 'engine' or not detached or 'watch' not in history or 'destroyed' in history or 'finalized' in history:
                raise RuntimeError('Invalid widget destruction order')
        elif event == 'finalized':
            if 'watch' not in history or 'finalized' in history or (name != 'engine' and 'destroyed' not in history):
                raise RuntimeError('Invalid finalization order')
        elif event == 'run-return':
            if name in returns or 'finalized' not in history or fields.get('watched') != '1' or fields.get('finalized') != '1' or fields.get('destroyed') != ('0' if name == 'engine' else '1'):
                raise RuntimeError('Object remains live at application loop return')
            returns.add(name)
        else:
            raise RuntimeError('Unknown disposal observation')
        history.append(event)
    if not detached or returns != OBJECTS:
        raise RuntimeError('Incomplete disposal observation')
    return {'objectsFinalizedBeforeLoopReturn': sorted(returns),
            'sameOwningThread': True, 'events': seen}


def bundle_pins(bundle):
    return {str(p.relative_to(bundle)): digest(p) for p in sorted(bundle.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, default=Path('build/linux/x64/release/bundle/tandemlog'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != 'linux':
        parser.error('This native GTK ownership check requires Linux')
    binary = args.binary.resolve()
    root = args.output.resolve()
    root.mkdir(mode=0o700, exist_ok=False)
    report = {'diagnosticOnly': True, 'performanceAcceptance': False,
              'passed': False, 'applicationReruns': 0, 'results': []}
    status = 1
    try:
        if os.environ.get('LD_PRELOAD'):
            raise RuntimeError('Unexpected existing LD_PRELOAD; no combined observer allowed')
        pins = bundle_pins(binary.parent)
        report['bundlePins'] = pins
        probe_source = Path(__file__).with_name('linux_lifecycle_probe.c').resolve()
        report['sourcePins'] = {p.name: digest(p) for p in (
            Path(__file__).resolve(), probe_source,
            Path(__file__).with_name('measure_startup.py'),
            Path(__file__).with_name('synthetic_text_fixture.py'))}
        probe = root/'lifecycle_probe.so'
        flags = shlex.split(subprocess.check_output(
            ['pkg-config', '--cflags', '--libs', 'gtk+-3.0'], text=True, timeout=10))
        command = [shutil.which('clang') or 'clang', '-std=c11', '-Wall', '-Wextra',
                   '-Werror', '-shared', '-fPIC', str(probe_source), *flags,
                   '-ldl', '-o', str(probe)]
        with (root/'compile.log').open('wb') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                           timeout=30, check=True)
        report['probeSHA256'] = digest(probe)
        library = binary.parent/'lib/libtandemlog_text.so'
        folder, profile, fixture = seed_fixture(root/'fixture', 10, str(library))
        report['fixture'] = fixture
        previous = None
        for number in (1, 2):
            before = inspect_stopped_witness(profile, folder)
            os.environ['LD_PRELOAD'] = str(probe)
            try:
                result = launch(str(binary), profile, root, number,
                                close_mode='normal', xdotool=shutil.which('xdotool') or 'xdotool')
            finally:
                os.environ.pop('LD_PRELOAD', None)
            result['witnessBeforeLaunch'] = before
            result['previousNormalExitVerified'] = bool(previous)
            verify_loaded(profile, folder, 10, result, number > 1)
            result['disposal'] = validate_trace(
                (root/f'run-{number}.stdout-stderr.log').read_text(),
                result['shutdown']['pid'])
            report['results'].append(result)
            previous = result
        if bundle_pins(binary.parent) != pins:
            raise RuntimeError('Measured bundle bytes changed')
        report.update(passed=True, bundleBytesUnchanged=True)
        status = 0
    except Exception as error:
        report['error'] = f'{type(error).__name__}: {error}'
    finally:
        for name in ('text-seed.stdout.log', 'text-seed.stderr.log'):
            source = root/'fixture'/name
            if source.exists():
                shutil.copyfile(source, root/name)
        (root/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    return status


if __name__ == '__main__':
    raise SystemExit(main())
