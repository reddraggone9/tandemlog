import hashlib, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

from release_context import context, configure, asset_inventory
parser = context('Stage or finalize accepted candidate bytes as an RC prerelease or a stable; never builds or dispatches.')
parser.add_argument('--lee-accepted', action='store_true', help='Required for a stable tag; unused for an RC')
parser.add_argument('--policy-revision', default='origin/main')
sub = parser.add_subparsers(dest='command', required=True)
d = sub.add_parser('draft')
d.add_argument('--dist', type=Path, required=True)
d.add_argument('--run-id', required=True)
d.add_argument('--android-sha256', required=True)
sub.add_parser('publish')
args = configure(parser.parse_args())
root, repo_dir, repo, tag = args.output, args.repo_dir, args.repository, args.tag
rc = args.prerelease
if not rc and not args.lee_accepted:
    parser.error('--lee-accepted is required for a stable tag')
# Same channel inputs as prerelease.yml and the former stable.yml.
kind_env = {'RELEASE_KIND': 'prerelease'} if rc else {'RELEASE_KIND': 'stable', 'LEE_ACCEPTED_STABLE': 'true'}
title = f'{tag} — experimental' if rc else tag
env = dict(os.environ)
env['GITHUB_REPOSITORY'] = repo
state_file = root / 'draft-release.json'


def run(*a, cwd=None, extra=None):
    return subprocess.check_output([str(x) for x in a], cwd=cwd, env={**env, **(extra or {})}, text=True)


def api(path, *a):
    return json.loads(run('gh', 'api', path, *a))


def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def all_releases():
    return [r for page in json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
            for r in page]


def ident(r):
    return (r['id'], r['tag_name'], r['prerelease'], r['draft'], r['body'], r['target_commitish'],
            tuple(sorted((a['id'], a['name'], a['size'], a.get('digest')) for a in r['assets'])))


def draft(dist, run_id, android_sha):
    assert not state_file.exists(), 'Draft already created; recover it, never create another'
    main = run('git', '-C', repo_dir, 'rev-parse', args.policy_revision).strip()
    # Policy, notes and media come from the live main, as in a workflow dispatch; a stale local ref refuses.
    assert run('git', '-C', repo_dir, 'ls-remote', 'origin', 'refs/heads/main').split()[:1] == [main], \
        'Policy revision is not the current remote main'
    work = Path(tempfile.mkdtemp(prefix='release-draft-', dir=root))
    out = work / 'github_output'; out.touch()
    # candidate job: trusted dispatch revision (main) policy resolves the candidate run.
    wt_main = work / 'main'
    run('git', '-C', repo_dir, 'worktree', 'add', '--detach', wt_main, main)
    try:
        run('python3', 'tool/candidate_source.py', cwd=wt_main,
            extra={'CANDIDATE_RUN_ID': run_id, 'CANDIDATE': tag, **kind_env, 'GITHUB_OUTPUT': str(out)})
        sha = out.read_text().strip().removeprefix('sha=')
        assert len(sha) == 40, sha
        # publish job: checkout candidate sha, policy from dispatch revision.
        wt = work / 'candidate'
        run('git', '-C', repo_dir, 'worktree', 'add', '--detach', wt, sha)
        shutil.copytree(dist, wt / 'dist')
        (wt / '.release-policy').mkdir()
        for policy in ('app_version.py', 'android_release.py', 'publish_gate.py', 'release_assets.py'):
            (wt / '.release-policy' / policy).write_text(run('git', '-C', repo_dir, 'show', f'{main}:tool/{policy}'))
        gate_env = {'CANDIDATE': tag, 'CANDIDATE_SHA': sha, 'ANDROID_VERIFIED_SHA256': android_sha, **kind_env}
        print(run('python3', '.release-policy/publish_gate.py', cwd=wt, extra=gate_env).strip())
        for sums in ('linux', 'windows', 'android'):
            run('sha256sum', '--check', f'{sums}-SHA256SUMS.txt', cwd=wt / 'dist')
        notes = run('git', '-C', repo_dir, 'show', f'{main}:design/{"prerelease" if rc else "stable"}-notes.md')
        # Pin relative media links to the commit the notes come from, not a moving branch.
        notes = notes.replace('(media/', f'(https://raw.githubusercontent.com/{repo}/{main}/design/media/')
        for path in re.findall(rf'/{main}/(design/media/[^)]+)\)', notes):
            run('git', '-C', repo_dir, 'cat-file', '-e', f'{main}:{path}')
        (work / 'release-notes.md').write_text(notes)
        (root / 'release-notes-published.md').write_text(notes)
        print(run('python3', '.release-policy/release_assets.py', cwd=wt, extra=gate_env).strip())
        assets = wt / 'public-assets'
        expected = {p.name: {'sha256': sha256(p), 'size': p.stat().st_size} for p in assets.iterdir()}
        assert len(expected) == 4, expected
        before = all_releases()
        assert not any(r['tag_name'] == tag for r in before), 'Release/draft for tag already exists'
        (root / 'releases-before-publish.json').write_text(json.dumps(before, indent=2) + '\n')
        state = {'phase': 'creating', 'tag': tag, 'prerelease': rc, 'source': sha, 'dispatchRevision': main, 'candidateRun': run_id,
                 'androidVerifiedSHA256': android_sha, 'notesSHA256': hashlib.sha256(notes.encode()).hexdigest(),
                 'assets': expected}
        state_file.write_text(json.dumps(state, indent=2) + '\n')
        url = run('gh', 'release', 'create', tag, *sorted(assets.iterdir()), '--repo', repo, '--draft',
                  *(['--prerelease'] if rc else []),
                  '--target', sha, '--title', title, '--notes-file', work / 'release-notes.md').strip()
        rel = [r for r in all_releases() if r['tag_name'] == tag]
        assert len(rel) == 1 and rel[0]['draft'] is True, rel
        rel = rel[0]
        assert rel['target_commitish'] == sha and rel['body'].strip() == notes.strip() and rel['name'] == title
        assert rel['prerelease'] is rc
        got = asset_inventory(rel)
        assert got == expected, (got, expected)
        state.update(phase='draft-verified', releaseId=rel['id'], draftUrl=url)
        state_file.write_text(json.dumps(state, indent=2) + '\n')
        print(json.dumps(state, indent=2))
    finally:
        for w in work.glob('*'):
            if (w / '.git').exists():
                subprocess.run(['git', '-C', str(repo_dir), 'worktree', 'remove', '--force', str(w)], check=False)


def publish():
    state = json.loads(state_file.read_text())
    assert state['phase'] == 'draft-verified', state['phase']
    rel = api(f'repos/{repo}/releases/{state["releaseId"]}')
    assert rel['prerelease'] is rc and rel['name'] == title
    assert state['tag'] == tag
    assert rel['draft'] is True and rel['tag_name'] == tag and rel['target_commitish'] == state['source']
    assert hashlib.sha256(rel['body'].encode()).hexdigest() == state['notesSHA256']
    got = asset_inventory(rel)
    assert got == state['assets'], got
    main = run('git', '-C', repo_dir, 'rev-parse', args.policy_revision).strip()
    before = {r['id']: r for r in json.loads((root / 'releases-before-publish.json').read_text())}
    now = {r['id']: r for r in all_releases() if r['tag_name'] != tag}
    assert set(now) == set(before) and all(ident(before[i]) == ident(now[i]) for i in before), 'Prior releases changed'
    # An RC stays a prerelease and never moves Latest; a stable becomes Latest.
    channel = ['-F', 'prerelease=true', '-f', 'make_latest=false'] if rc else ['-f', 'make_latest=true']
    latest = api(f'repos/{repo}/releases/latest')['id'] if rc else None
    state.update(phase='publishing', mainAtPublish=main)
    state_file.write_text(json.dumps(state, indent=2) + '\n')
    final = api(f'repos/{repo}/releases/{state["releaseId"]}', '-X', 'PATCH', '-F', 'draft=false',
                *channel, '-f', f'tag_name={tag}', '-f', f'target_commitish={state["source"]}')
    assert final['draft'] is False and final['prerelease'] is rc, final
    assert not rc or api(f'repos/{repo}/releases/latest')['id'] == latest, 'Prerelease moved Latest'
    state.update(phase='published', publishedAt=final['published_at'], url=final['html_url'])
    state_file.write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps(state, indent=2))


if __name__ == '__main__':
    if args.command == 'draft':
        draft(args.dist.resolve(), args.run_id, args.android_sha256)
    else:
        publish()
