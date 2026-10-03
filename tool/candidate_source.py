"""Resolve an already-validated candidate, without accepting arbitrary artifact runs."""
import json
import os
from pathlib import Path
import re
import subprocess
from app_version import verify_release_kind, version


def validate_run(run, repository):
    if (run['event'] != 'workflow_dispatch' or run['head_branch'] != 'main'
            or run['path'] != '.github/workflows/android-candidate.yml'
            or run['status'] != 'completed' or run['conclusion'] != 'success'
            or run['repository']['full_name'] != repository
            or run['head_repository']['full_name'] != repository
            or not re.fullmatch(r'[0-9a-f]{40}', run['head_sha'])):
        raise ValueError('Expected successful main-branch signed candidate from this repository')
    return run['head_sha']


def validate_candidate_version(spec, tag, kind, lee_accepted=False):
    expected = version(spec)
    verify_release_kind(expected[0], kind, lee_accepted)
    if tag != 'v' + expected[0]:
        raise ValueError('Tag must match the selected candidate display version')
    return expected


if __name__ == '__main__':
    run_id = os.environ['CANDIDATE_RUN_ID']
    if not re.fullmatch(r'[0-9]+', run_id):
        raise ValueError('Invalid candidate run ID')
    repo = os.environ['GITHUB_REPOSITORY']
    run = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/actions/runs/{run_id}']))
    sha = validate_run(run, repo)
    # This is the trusted dispatch revision's policy, not executable code from
    # an older selected candidate that may predate channel/version checks.
    spec = subprocess.check_output(['git', 'show', f'{sha}:pubspec.yaml'], text=True)
    validate_candidate_version(spec, os.environ['CANDIDATE'], os.environ['RELEASE_KIND'],
                               os.environ.get('LEE_ACCEPTED_STABLE') == 'true')
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write(f'sha={sha}\n')
