"""Source-bound hosted Windows application tests; receipts only, no profiles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SCOPES = (
    ('tag_input_workflow_test.dart', 3, ()),
    ('historical_checklist_recompletion_test.dart', 1, ()),
)
CAPTURE_VARIABLES = (
    'TANDEMLOG_NATIVE_QA_SCREENSHOTS', 'TANDEMLOG_BULK_QA_VIDEO',
    'TANDEMLOG_TEXT_QA_SCREENSHOTS', 'DATE_LAYOUT_EVIDENCE', 'DATE_LAYOUT_RECORD',
)


def configure_console():
    """Set this receipt runner's console encoding before printing tool output."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, 'reconfigure', None)
        if reconfigure is not None:
            reconfigure(encoding='utf-8', errors='backslashreplace')


def result(text, expected, exit_code):
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text)
    counts = re.findall(r'\+(\d+)(?:\s+~(\d+))?(?:\s+-(\d+))?:', text)
    passed, skipped, failed = (map(lambda value: int(value or 0), counts[-1])
                               if counts else (0, 0, 0))
    first_frames = [int(value) for value in re.findall(
        r'\bTANDEMLOG_FIRST_FRAME_MS=(\d+)(?=\s|$)', text)]
    readiness = [dict(marker=marker, elapsed_ms=int(value)) for marker, value in re.findall(
        r'\bTANDEMLOG_(READY|ONBOARDING_READY)_MS=(\d+)(?=\s|$)', text)]
    return dict(completed=passed, skipped=skipped, failed=failed,
                first_frame_ms=first_frames, readiness_markers=readiness,
                passed=(exit_code == 0 and passed == expected and skipped == failed == 0
                        and bool(first_frames) and bool(readiness)
                        and 'All tests passed!' in text))


def hashes(bundle):
    for name in ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                 'data/icudtl.dat', 'data/flutter_assets/kernel_blob.bin'):
        if not (bundle / name).is_file():
            raise ValueError('Missing debug payload: ' + name)
        if (bundle / name).stat().st_size == 0:
            raise ValueError('Empty debug payload: ' + name)
    return {path.relative_to(bundle).as_posix():
            dict(bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            for path in sorted(bundle.rglob('*')) if path.is_file()}


def library_environment(env):
    value = env.get('TANDEMLOG_TEXT_LIBRARY')
    entry = dict(value=value, used_by_app_entrypoints=False)
    if value:
        try:
            path = Path(value)
            entry.update(bytes=path.stat().st_size,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        except OSError as error:
            entry['read_error'] = str(error)
    return entry


def command(args, output, env, timeout=300):
    started = time.monotonic()
    with output.open('wb') as log:
        process = subprocess.Popen(args, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Stop only this fresh test command and its descendants; no GUI inputs.
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                           stdout=log, stderr=subprocess.STDOUT, check=False)
            process.wait(timeout=30)
            code = 124
            log.write(f'\nScoped command exceeded its {timeout} second limit.\n'.encode())
    print(output.read_text(encoding='utf-8', errors='replace'), flush=True)
    return code, round(time.monotonic() - started, 3)


def main():
    configure_console()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    output = parser.parse_args().output
    output.mkdir(parents=True, exist_ok=False)
    report = dict(platform=platform.platform(), machine=platform.machine(),
                  python=sys.version, expected_flows=4, scopes=[], diagnostics=[],
                  run_id=os.environ.get('GITHUB_RUN_ID'),
                  run_attempt=os.environ.get('GITHUB_RUN_ATTEMPT'),
                  image_version=os.environ.get('ImageVersion'), passed=False)
    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    save()
    try:
        if sys.platform != 'win32':
            raise ValueError('This application runner requires actual Windows.')
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        report['source_sha'] = source
        if os.environ.get('GITHUB_SHA') != source:
            raise ValueError('Checkout HEAD does not match the dispatched source.')
        env = os.environ.copy()
        report['native_library_environment'] = library_environment(env)
        report['native_build_target_directory'] = env.get('TANDEMLOG_TEXT_TARGET_DIR')
        report['native_loader_policy'] = dict(
            selection='NativeTextEngine() default; adjacent debug-bundle DLL',
            windows_path='File(Platform.resolvedExecutable).parent/tandemlog_text.dll',
            environment_override_applies=False,
            evidence='Source-declared loader; runtime loaded-module enumeration is not performed',
            source_sha256=hashlib.sha256((ROOT / 'lib/text/native_text_engine.dart').read_bytes()).hexdigest(),
        )
        for key in CAPTURE_VARIABLES:
            env.pop(key, None)
        report['unset_capture_variables'] = list(CAPTURE_VARIABLES)
        flutter = shutil.which('flutter')
        if not flutter:
            raise ValueError('Pinned Flutter is unavailable on PATH.')
        for index, args in enumerate((
            [flutter, '--version'], [flutter, 'doctor', '-v'], [flutter, 'devices'],
            ['rustc', '+1.99.0', '--version', '--verbose'],
            ['cargo', '+1.99.0', '--version'],
        )):
            log = output / f'diagnostic-{index + 1}.txt'
            code, duration = command(args, log, env, timeout=60)
            report['diagnostics'].append(dict(command=args, exit_code=code,
                                             elapsed_seconds=duration, log=log.name))
            save()
        for index, (entrypoint, expected, extra) in enumerate(SCOPES):
            args = [flutter, 'test', 'integration_test/' + entrypoint, '-d', 'windows',
                    '--reporter', 'expanded', '--no-pub', *extra]
            log = output / f'{index + 1}-{entrypoint}.txt'
            scope = dict(command=args, entrypoint=entrypoint, expected=expected, status='running', log=log.name)
            report['scopes'].append(scope)
            save()
            try:
                code, duration = command(args, log, env)
                scope.update(exit_code=code, elapsed_seconds=duration, status='completed',
                             **result(log.read_text(encoding='utf-8', errors='replace'), expected, code))
                scope['log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
                try:
                    scope['debug_payload_hashes'] = hashes(ROOT / 'build/windows/x64/runner/Debug')
                except ValueError as error:
                    scope.update(passed=False, payload_error=str(error))
            except Exception as error:
                scope.update(status='runner-error', passed=False, error=str(error))
            save()
        report['passed'] = all(scope.get('passed') for scope in report['scopes'])
    except Exception as error:
        report['error'] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        save()
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
