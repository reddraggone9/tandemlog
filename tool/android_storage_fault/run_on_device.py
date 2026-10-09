"""Run isolated QA APK on a selected actual Android device; preserve all evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid
import zipfile

PACKAGE = 'com.reddraggone9.tandemlog.storagefaulttest'
ACTIVITY = PACKAGE + '/com.reddraggone9.tandemlog.MainActivity'
CUTS = ['import.started', 'files.imported', 'caches.imported', 'cleanup.planned',
        'sources.verified', 'activation.before', 'activation.committed',
        'cleanup.marked', 'cleanup.deleted', 'cleanup.committed', 'cleanup.finished']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifact-directory', required=True, type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cut', choices=CUTS, action='append')
    args = parser.parse_args()
    provenance = json.loads((args.artifact_directory / 'provenance.json').read_text())
    tooling_names = {'harness.dart', 'main.dart', 'build_apk.py', 'run_on_device.py', 'README.md'}
    if set(provenance['qaToolingSha256']) != tooling_names:
        raise ValueError('Unexpected delivered QA tooling inventory')
    for name, expected in provenance['qaToolingSha256'].items():
        if hashlib.sha256((args.artifact_directory / 'qa-source' / name).read_bytes()).hexdigest() != expected:
            raise ValueError('Delivered QA tooling changed: ' + name)
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != provenance['qaToolingSha256']['run_on_device.py']:
        raise ValueError('Execute the exact delivered QA runner')
    apk = args.artifact_directory / 'tandemlog-TEST-ONLY-storage-fault-debug.apk'
    if (provenance['sourceRevision'] != args.source or provenance['package'] != PACKAGE
            or not provenance['testOnly'] or not provenance['debugSigned']
            or hashlib.sha256(apk.read_bytes()).hexdigest() != provenance['apkSha256']):
        raise ValueError('Exact source-bound isolated APK verification failed')
    with zipfile.ZipFile(apk) as zipped:
        native = {name: hashlib.sha256(zipped.read(name)).hexdigest()
                  for name in zipped.namelist() if name.startswith('lib/') and name.endswith('.so')}
    if native != provenance['packagedNativeSha256']:
        raise ValueError('Native payload binding failed')
    args.output.mkdir(parents=True, exist_ok=False)
    adb = ['adb', '-s', args.serial]
    qa_pids = set()

    def command(*words, check=True, input_bytes=None):
        return subprocess.run(adb + list(words), input=input_bytes, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, check=check)

    def shell(*words, check=True):
        return command('shell', *words, check=check).stdout.decode('utf-8').strip()

    def stop():
        old_pid = shell('pidof', PACKAGE, check=False)
        if old_pid.isdigit():
            qa_pids.add(old_pid)
        shell('am', 'force-stop', PACKAGE)
        deadline = time.monotonic() + 15
        while shell('pidof', PACKAGE, check=False):
            if time.monotonic() >= deadline:
                raise RuntimeError('QA package survived force-stop')
            time.sleep(.2)
        return old_pid

    def control(case, mode, cut=None):
        stop()
        value = {'case': case, 'mode': mode}
        if cut:
            value['cut'] = cut
        # Fixed own-package path; no root from user or device can alter it.
        command('shell', f"run-as {PACKAGE} sh -c 'cat > app_flutter/storage-fault-control.json'",
                input_bytes=json.dumps(value).encode())
        shell('am', 'start', '-n', ACTIVITY)

    def await_json(case, filename, predicate):
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            result = command('exec-out', 'run-as', PACKAGE, 'cat',
                             f'app_flutter/storage-fault-cases/{case}/{filename}', check=False)
            if result.returncode == 0:
                try:
                    value = json.loads(result.stdout)
                    if predicate(value):
                        return value
                except (ValueError, KeyError, TypeError):
                    pass
            time.sleep(.3)
        raise RuntimeError(f'No matching {filename} for retained case {case}')

    runtime = {'serial': args.serial, 'api': shell('getprop', 'ro.build.version.sdk'),
               'abi': shell('getprop', 'ro.product.cpu.abi'),
               'fingerprint': shell('getprop', 'ro.build.fingerprint')}
    log_start = shell("date '+%m-%d %H:%M:%S.000'")
    if not any(name.startswith('lib/' + runtime['abi'] + '/') for name in native):
        raise ValueError('Device ABI absent from bound APK')
    command('install', '-r', str(apk))
    stop()
    # Retained control must not replay an earlier case during a subsequent run.
    if command('exec-out', 'run-as', PACKAGE, 'test', '-d', 'app_flutter', check=False).returncode:
        shell('am', 'start', '-n', ACTIVITY)
    deadline = time.monotonic() + 45
    while command('exec-out', 'run-as', PACKAGE, 'test', '-d', 'app_flutter', check=False).returncode:
        if time.monotonic() >= deadline:
            raise RuntimeError('QA app documents unavailable')
        time.sleep(.2)
    records = []
    try:
        for index, cut in enumerate(args.cut or CUTS):
            case = f'qa-{uuid.uuid4().hex[:12]}-{index}'
            control(case, 'seed-held')
            legacy = await_json(case, 'ready.json', lambda row:
                                row['source'] == args.source and row['boundary'] == 'legacy-wal'
                                and str(row['pid']) == shell('pidof', PACKAGE, check=False))
            if not legacy['walExists']:
                raise RuntimeError('Legacy seed did not retain committed WAL')
            killed_legacy = stop()
            if killed_legacy != str(legacy['pid']):
                raise RuntimeError('Legacy held PID changed before force-stop')
            control(case, 'cut', cut)
            marker = await_json(case, 'ready.json', lambda row:
                                row['source'] == args.source and row['boundary'] == cut
                                and str(row['pid']) == shell('pidof', PACKAGE, check=False))
            killed = stop()
            if killed != str(marker['pid']):
                raise RuntimeError('Migration held PID changed before force-stop')
            control(case, 'resume')
            report = await_json(case, 'report.json', lambda row:
                                row['source'] == args.source and row['mode'] == 'resume'
                                and row['passed'] and row['profileClosed']
                                and str(row['pid']) == shell('pidof', PACKAGE, check=False))
            if (report['root'] != marker['root'] or report['cutMarker'] != marker
                    or not all(report[key] for key in ['pendingExact', 'guardExact', 'writerExact',
                               'trustedObservationsAndAcceptedEventsExact'])):
                raise RuntimeError('Same-root migration recovery assertions failed')
            record = {'case': case, 'cut': cut, 'legacy': legacy, 'legacyKilledPid': killed_legacy,
                      'marker': marker, 'killedPid': killed, 'exitConfirmed': True, 'report': report}
            if index == 0:
                control(case, 'sql-full')
                record['sqlFull'] = await_json(case, 'report.json', lambda row:
                    row['source'] == args.source and row['mode'] == 'sql-full'
                    and row['passed'] and row['profileClosed'] and row['injectedSqlResultCode'] == 13
                    and str(row['pid']) == shell('pidof', PACKAGE, check=False))
            records.append(record)
            (args.output / f'{case}.json').write_text(json.dumps(record, indent=2) + '\n')
            print(f'PASS {cut} actual PID {killed} force-stopped; same-root recovery verified', flush=True)
    finally:
        stop()
        for qa_pid in sorted(qa_pids):
            (args.output / f'logcat-qa-pid-{qa_pid}.txt').write_bytes(
                command('logcat', '-d', '--pid', qa_pid, '-T', log_start,
                        '-s', 'flutter:I', check=False).stdout)
        receipt = {'passed': len(records) == len(args.cut or CUTS), 'runtime': runtime,
                   'source': args.source, 'apkSha256': provenance['apkSha256'],
                   'package': PACKAGE, 'cases': records, 'provenance': provenance,
                   'qaPids': sorted(qa_pids), 'logStartDeviceTime': log_start,
                   'limits': 'QA migration and injected SQL capacity only; no production APK/SAF/power-loss guarantee.'}
        (args.output / 'android-storage-fault-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
