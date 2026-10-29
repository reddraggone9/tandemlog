"""Borderline timing on identical, already qualified relevant source. Never a waiver.

Lee approved on 2026-10-27, extended to absolute misses on 2026-10-28: when the same
relevant-source identity already holds a verified passing reference qualification, a later
enforcing failure whose only misses are absolute or history-growth bounds exceeded by at most
the declared run-to-run variation band is a borderline limit, not a regression. It does not
block the release and queues a follow-up on the limit or the scaling
behind it. Budgets are unchanged. Missing/stale prior pass, other identity, correctness,
coverage, replay/integrity, execution or any miss beyond the band fails closed.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from gate_policy import evaluate, evaluate_scaling, classify_borderline, BORDERLINE_VARIATION_BAND, BORDERLINE_ACCEPTED
from reference_receipt import (need, digest, canonical_digest, read, instant, request_shape, profile, recorded_identity,
                               verify_bundle, check_official_rerun, QUALIFICATION, AUTHORIZATION, PRIOR_RESULT, PROFILE,
                               resampled_decisions, check_resample_logs, resample_log_names)
from owner_override import validate_failed_report, validate_failed_cleanup

DIRECTORY = 'evidence/reference-performance/borderline'
RECORD = 'borderline.json'
KIND = 'reference-performance-borderline-v1'
STATE = 'QUALIFIED_WITH_BORDERLINE_FOLLOW_UP_QUEUED'
FOLLOW_UP = 'Review the timing limit or the scaling behind it; budgets stay unchanged unless Lee approves'
RECORD_FIELDS = {'schemaVersion', 'kind', 'verdict', 'relevantSourceSHA256', 'requestId', 'requestSHA256',
                 'resultSHA256', 'qualificationRequestId', 'qualificationResultSHA256', 'limitsSHA256',
                 'budgetsChanged', 'variationBand', 'borderlineMetrics', 'followUp', 'files'}


def classify_failed_run(repo, root, qualification):
    """Recompute everything from retained bytes; return (classification, record fields)."""
    repo = Path(repo).resolve()
    prior = verify_bundle(repo, qualification)
    prior_request = read(Path(qualification) / 'request.json')
    prior_report_path = Path(qualification) / 'gate-result.json'
    host = profile(repo)
    request = read(root / 'request.json')
    request_shape(request)
    need(request['requestId'] != prior_request['requestId'], 'Borderline result must come from a separate request')
    need(request['relevantSource'] == prior_request['relevantSource'] and
         request['relevantSource']['sha256'] == prior['relevantSourceSHA256'],
         'Borderline result is for a different relevant-source identity than the passing qualification')
    current, committed = recorded_identity(repo, request['relevantSource'], request['sourceRevision'])
    need(request['relevantSource'] == current == committed, 'Missing/stale/mismatched borderline source')
    need(subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', request['sourceRevision'], 'HEAD'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
         'Borderline request source is not in current history')
    need(request['hostProfileSHA256'] == digest(repo / PROFILE) == prior_request['hostProfileSHA256'],
         'Stale host profile request')
    need(instant(read(prior_report_path)['finishedAtUTC']) <= instant(request['issuedAtUTC']),
         'Borderline rule needs an earlier passing qualification of this identity')
    report = read(root / 'gate-result.json')
    validate_failed_report(repo, report, request, host, committed)
    for label, item in [('compile', report['compile']),
                        *[(size + '-generate', value['generation']) for size, value in report['fixtures'].items()],
                        *[(a['size'] + '-attempt-' + str(a['attempt']), a['execution']) for a in report['attempts']]]:
        need(digest(root / (label + '.log')) == item['logSHA256'], 'Missing/changed execution log')
    check_resample_logs(root, report)
    for size, item in report['fixtures'].items():
        file = root / ('fixture-' + size) / 'fixture.json'
        need(digest(file) == item['manifestSHA256'] and read(file) == item['contract'], 'Fixture receipt changed')
    validate_failed_cleanup(read(root / 'cleanup.json'), report, request, host)
    if (root / AUTHORIZATION).exists():
        check_official_rerun(repo, request, read(root / AUTHORIZATION), root / PRIOR_RESULT)
    else:
        need(not (root / PRIOR_RESULT).exists(), 'Unexpected prior result without an official rerun')
    limits = read(repo / 'tool/performance/limits-v1.json')
    limits['sha256'] = digest(repo / 'tool/performance/limits-v1.json')
    from run_gate import scaling_specs
    absolute = {a['size']: evaluate(a['result'], limits) for a in report['attempts']}
    contracts = {size: item['contract'] for size, item in report['fixtures'].items()}
    summaries = {size: decision.summaries for size, decision in absolute.items()}
    paired = {name: evaluate_scaling(summaries, spec, contracts) for name, spec in scaling_specs(limits).items()}
    # A disk-stall resample replaces its label's samples: classify what the gate actually decided.
    resampled = resampled_decisions(report, 0, {a['size']: a['result'] for a in report['attempts']},
                                    limits, scaling_specs(limits), contracts, [])
    if resampled is not None:
        absolute, paired = resampled
    result = classify_borderline(prior['relevantSourceSHA256'], request['relevantSource']['sha256'],
                                 absolute, paired, limits=limits)
    need(result['verdict'] == BORDERLINE_ACCEPTED, 'Not borderline; ordinary failure: ' + result['reason'])
    labels = sorted({m['label'] for m in result['borderlineMetrics']})
    fields = {'schemaVersion': 1, 'kind': KIND, 'verdict': BORDERLINE_ACCEPTED,
              'relevantSourceSHA256': request['relevantSource']['sha256'], 'requestId': request['requestId'],
              'requestSHA256': canonical_digest(request), 'resultSHA256': digest(root / 'gate-result.json'),
              'qualificationRequestId': prior_request['requestId'],
              'qualificationResultSHA256': digest(prior_report_path), 'limitsSHA256': limits['sha256'],
              'budgetsChanged': False, 'variationBand': BORDERLINE_VARIATION_BAND,
              'borderlineMetrics': result['borderlineMetrics'],
              'followUp': {'status': 'queued', 'action': FOLLOW_UP, 'metrics': labels}}
    return prior, fields


def verify_borderline(repo, directory, qualification=None):
    repo = Path(repo).resolve()
    root = Path(directory).absolute()
    need(root.is_dir() and not any(p.is_symlink() for p in (root, *root.parents)) and
         not any(p.is_symlink() for p in root.rglob('*')), 'Borderline evidence is missing or linked')
    record = read(root / RECORD)
    need(set(record) == RECORD_FIELDS, 'Borderline record fields differ')
    members = record['files']
    actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
    need(actual == set(members) | {RECORD}, 'Borderline file inventory differs')
    for name, value in members.items():
        path = Path(name)
        need(not path.is_absolute() and '..' not in path.parts and '\\' not in name and digest(root / path) == value,
             'Borderline member changed')
    prior, fields = classify_failed_run(repo, root, qualification or repo / QUALIFICATION)
    need({k: v for k, v in record.items() if k != 'files'} == fields,
         'Borderline record differs from the recomputed classification')
    return {'state': STATE, 'referencePerformanceQualified': True,
            'relevantSourceSHA256': prior['relevantSourceSHA256'], 'qualificationRequestId': prior['requestId'],
            'borderlineRequestId': fields['requestId'], 'borderlineMetrics': fields['borderlineMetrics'],
            'followUp': fields['followUp'], 'budgetsChanged': False, 'releaseOrNativeUIAccepted': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('seal', 'verify'))
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, help='Borderline bundle (default ' + DIRECTORY + ' for verify)')
    parser.add_argument('--request', type=Path)
    parser.add_argument('--run', type=Path, help='Original failed run directory')
    parser.add_argument('--cleanup', type=Path)
    parser.add_argument('--prior-result', type=Path, help='Official rerun only: its prior failed gate-result.json')
    parser.add_argument('--rerun-authorization', type=Path, help='Official rerun only: REQUEST.official-rerun.json')
    args = parser.parse_args()
    if args.mode == 'verify':
        print(json.dumps(verify_borderline(args.repo, args.output or args.repo / DIRECTORY), indent=2))
        return
    need(all(v is not None for v in (args.output, args.request, args.run, args.cleanup)),
         'Seal requires request/run/cleanup/output')
    need(not args.output.exists(), 'Fresh borderline bundle required')
    need((args.rerun_authorization is None) == (args.prior_result is None),
         'An official rerun needs both its authorization and its prior failed result')
    report = read(args.run / 'gate-result.json')
    args.output.mkdir(parents=True)
    try:
        shutil.copyfile(args.request, args.output / 'request.json')
        shutil.copyfile(args.cleanup, args.output / 'cleanup.json')
        if args.prior_result is not None:
            shutil.copyfile(args.prior_result, args.output / PRIOR_RESULT)
            shutil.copyfile(args.rerun_authorization, args.output / AUTHORIZATION)
        for name in ['gate-result.json', 'compile.log',
                     *[size + '-generate.log' for size in report['fixtures']],
                     *[a['size'] + '-attempt-' + str(a['attempt']) + '.log' for a in report['attempts']],
                     *resample_log_names(report),
                     *['fixture-' + size + '/fixture.json' for size in report['fixtures']]]:
            target = args.output / name
            target.parent.mkdir(exist_ok=True)
            shutil.copyfile(args.run / name, target)
        _, fields = classify_failed_run(args.repo, args.output, args.repo / QUALIFICATION)
    except Exception:
        shutil.rmtree(args.output)
        raise
    fields['files'] = {p.relative_to(args.output).as_posix(): digest(p) for p in args.output.rglob('*') if p.is_file()}
    (args.output / RECORD).write_text(json.dumps(fields, indent=2) + '\n')
    print(json.dumps(verify_borderline(args.repo, args.output), indent=2))


if __name__ == '__main__':
    main()
