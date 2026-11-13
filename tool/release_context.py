"""Shared CLI context for recoverable private-draft releases."""
import argparse
import json
import os
from pathlib import Path

def context(description):
    p = argparse.ArgumentParser(description=description)
    p.add_argument('--repo-dir', type=Path, required=True)
    p.add_argument('--repository', default='reddraggone9/tandemlog')
    p.add_argument('--tag', required=True)
    p.add_argument('--output', type=Path, required=True)
    return p

def configure(a):
    if not a.tag.startswith('v') or '/' in a.tag or '..' in a.tag:
        raise ValueError('Expected a version tag')
    a.repo_dir = a.repo_dir.resolve()
    a.output = a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=True)
    return a

def asset_inventory(release):
    result = {}
    for a in release['assets']:
        name = a['name']
        if not name or '/' in name or '\\' in name or name in ('.', '..') or name in result:
            raise ValueError('Unsafe or duplicate asset name')
        digest = a.get('digest') or ''
        if not digest.startswith('sha256:') or len(digest) != 71:
            raise ValueError('Missing SHA-256 asset digest')
        result[name] = {'sha256': digest[7:], 'size': a['size']}
    return result
