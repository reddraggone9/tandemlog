"""Resolve an already-validated candidate, without accepting arbitrary artifact runs."""
import json
import os
from pathlib import Path
import re
import subprocess


def validate_run(run, repository):
    if (run['event'] != 'workflow_dispatch' or run['head_branch'] != 'main'
            or run['path'] != '.github/workflows/android-candidate.yml'
            or run['status'] != 'completed' or run['conclusion'] != 'success'
            or run['repository']['full_name'] != repository
            or run['head_repository']['full_name'] != repository
            or not re.fullmatch(r'[0-9a-f]{40}', run['head_sha'])):
        raise ValueError('Expected successful main-branch signed candidate from this repository')
    return run['head_sha']


if __name__ == '__main__':
    run_id = os.environ['CANDIDATE_RUN_ID']
    if not re.fullmatch(r'[0-9]+', run_id):
        raise ValueError('Invalid candidate run ID')
    repo = os.environ['GITHUB_REPOSITORY']
    run = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/actions/runs/{run_id}']))
    sha = validate_run(run, repo)
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write(f'sha={sha}\n')
