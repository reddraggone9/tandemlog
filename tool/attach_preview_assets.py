"""Attach exact gated artifacts to an owner-authorized private preview draft.

Actions cannot create releases at workflow-different historical commits. The
workflow token only uploads; the existing authorized connection finalizes after
verification. No permission changes, new credentials, rebuilding or clobbering.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def validate_draft(meta, release_id, tag, sha):
    if (meta.get('id') != release_id or meta.get('tag_name') != tag
            or meta.get('target_commitish') != sha or meta.get('draft') is not True
            or meta.get('prerelease') is not True):
        raise ValueError('Expected exact owner-authorized private experimental draft')


def missing_assets(assets, expected):
    seen=set()
    for asset in assets:
        name=asset.get('name')
        if (name not in expected or name in seen or asset.get('state') != 'uploaded'
                or any(asset.get(k) != v for k,v in expected[name].items())):
            raise ValueError('Unexpected, duplicate or nonmatching draft asset; never clobber')
        seen.add(name)
    return sorted(set(expected)-seen)


if __name__ == '__main__':
    text=os.environ['DRAFT_RELEASE_ID']
    if not re.fullmatch(r'[0-9]+',text):raise ValueError('Invalid release ID')
    release_id=int(text);repo=os.environ['GITHUB_REPOSITORY']
    endpoint=f'repos/{repo}/releases/{release_id}'
    meta=json.loads(subprocess.check_output(['gh','api',endpoint]))
    validate_draft(meta,release_id,os.environ['CANDIDATE'],os.environ['CANDIDATE_SHA'])
    root=Path('public-assets')
    expected={p.name:{'size':p.stat().st_size,'digest':'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()} for p in root.iterdir()}
    if len(expected)!=3:raise ValueError('Expected three already-gated installers')
    missing=missing_assets(meta.get('assets',[]),expected)
    if missing:
        subprocess.run(['gh','release','upload',os.environ['CANDIDATE'],*[str(root/name) for name in missing],'--repo',repo],check=True)
    meta=json.loads(subprocess.check_output(['gh','api',endpoint]))
    validate_draft(meta,release_id,os.environ['CANDIDATE'],os.environ['CANDIDATE_SHA'])
    if missing_assets(meta.get('assets',[]),expected):raise ValueError('Draft uploads incomplete')
    print('Three exact installer digests verified; release remains private draft for authorized finalization.')
