"""Freeze the public release/tag/Latest state anonymously before publishing.

Usage: python3 -I freeze-prior.py   (writes prior-releases.json, prior-tags.json, prior-latest.json here)
"""
import json, os, urllib.request
from pathlib import Path

from release_context import context, configure
args = configure(context('Freeze public state before creating a draft.').parse_args())
ROOT, TAG = args.output, args.tag
API = f'https://api.github.com/repos/{args.repository}'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def get(url):
    req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'vex-freeze'})
    with opener.open(req, timeout=30) as r:
        return json.loads(r.read())


def pages(path):
    out, page = [], 1
    while True:
        batch = get(f'{API}/{path}{"&" if "?" in path else "?"}per_page=100&page={page}')
        out += batch
        if len(batch) < 100:
            return out
        page += 1


assert all(not (ROOT / n).exists() for n in ('prior-releases.json', 'prior-tags.json', 'prior-latest.json')), 'Frozen state already exists'
releases = pages('releases')
tags = pages('git/refs/tags')
latest = get(f'{API}/releases/latest')
assert not any(r['tag_name'] == TAG for r in releases), 'Target tag already released'
assert not any(t['ref'] == 'refs/tags/'+TAG for t in tags), 'Target tag already exists'

for name, value in (('prior-releases.json', releases), ('prior-tags.json', tags), ('prior-latest.json', latest)):
    with (ROOT / name).open('x') as f:
        f.write(json.dumps(value, indent=2) + '\n')
print(json.dumps({'releases': len(releases), 'tags': len(tags), 'latest': latest['tag_name']}))
