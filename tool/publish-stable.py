import hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

from release_context import context, configure, asset_inventory
parser = context('Stage or finalize accepted stable bytes; never builds or dispatches.')
parser.add_argument('--lee-accepted', action='store_true', required=True)
parser.add_argument('--notes', type=Path)
parser.add_argument('--policy-revision', default='origin/main')
sub = parser.add_subparsers(dest='command', required=True)
d = sub.add_parser('draft')
d.add_argument('--dist', type=Path, required=True)
d.add_argument('--run-id', required=True)
d.add_argument('--android-sha256', required=True)
sub.add_parser('publish')
args = configure(parser.parse_args())
root, repo_dir, repo, tag = args.output, args.repo_dir, args.repository, args.tag
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
    work = Path(tempfile.mkdtemp(prefix='release-draft-', dir=root))
    out = work / 'github_output'; out.touch()
    # candidate job: trusted dispatch revision (main) policy resolves the candidate run.
    wt_main = work / 'main'
    run('git', '-C', repo_dir, 'worktree', 'add', '--detach', wt_main, main)
    try:
        run('python3', 'tool/candidate_source.py', cwd=wt_main,
            extra={'CANDIDATE_RUN_ID': run_id, 'CANDIDATE': tag, 'RELEASE_KIND': 'stable',
                   'LEE_ACCEPTED_STABLE': 'true', 'GITHUB_OUTPUT': str(out)})
        sha = out.read_text().strip().removeprefix('sha=')
        assert len(sha) == 40, sha
        # publish job: checkout candidate sha, policy from dispatch revision.
        wt = work / 'candidate'
        run('git', '-C', repo_dir, 'worktree', 'add', '--detach', wt, sha)
        shutil.copytree(dist, wt / 'dist')
        (wt / '.release-policy').mkdir()
        for policy in ('app_version.py', 'android_release.py', 'publish_gate.py', 'release_assets.py'):
            (wt / '.release-policy' / policy).write_text(run('git', '-C', repo_dir, 'show', f'{main}:tool/{policy}'))
        gate_env = {'CANDIDATE': tag, 'CANDIDATE_SHA': sha, 'ANDROID_VERIFIED_SHA256': android_sha,
                    'RELEASE_KIND': 'stable', 'LEE_ACCEPTED_STABLE': 'true'}
        print(run('python3', '.release-policy/publish_gate.py', cwd=wt, extra=gate_env).strip())
        for sums in ('linux', 'windows', 'android'):
            run('sha256sum', '--check', f'{sums}-SHA256SUMS.txt', cwd=wt / 'dist')
        assert args.notes is not None, '--notes is required for draft'
        notes = args.notes.read_text()
        # Pin relative media links to the candidate source, not a moving branch.
        notes = notes.replace('(media/', f'(https://raw.githubusercontent.com/{repo}/{sha}/design/media/')
        (work / 'release-notes.md').write_text(notes)
        (root / 'release-notes-published.md').write_text(notes)
        print(run('python3', '.release-policy/release_assets.py', cwd=wt, extra=gate_env).strip())
        assets = wt / 'public-assets'
        expected = {p.name: {'sha256': sha256(p), 'size': p.stat().st_size} for p in assets.iterdir()}
        assert len(expected) == 4, expected
        before = all_releases()
        assert not any(r['tag_name'] == tag for r in before), 'Release/draft for tag already exists'
        (root / 'releases-before-publish.json').write_text(json.dumps(before, indent=2) + '\n')
        state = {'phase': 'creating', 'tag': tag, 'source': sha, 'dispatchRevision': main, 'candidateRun': run_id,
                 'androidVerifiedSHA256': android_sha, 'notesSHA256': hashlib.sha256(notes.encode()).hexdigest(),
                 'assets': expected}
        state_file.write_text(json.dumps(state, indent=2) + '\n')
        url = run('gh', 'release', 'create', tag, *sorted(assets.iterdir()), '--repo', repo, '--draft',
                  '--target', sha, '--title', tag, '--notes-file', work / 'release-notes.md').strip()
        rel = [r for r in all_releases() if r['tag_name'] == tag]
        assert len(rel) == 1 and rel[0]['draft'] is True, rel
        rel = rel[0]
        assert rel['target_commitish'] == sha and rel['body'].strip() == notes.strip() and rel['name'] == tag
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
    assert not rel['prerelease'] and rel['name'] == tag
    assert state['tag'] == tag
    assert rel['draft'] is True and rel['tag_name'] == tag and rel['target_commitish'] == state['source']
    assert hashlib.sha256(rel['body'].encode()).hexdigest() == state['notesSHA256']
    got = asset_inventory(rel)
    assert got == state['assets'], got
    main = run('git', '-C', repo_dir, 'rev-parse', args.policy_revision).strip()
    before = {r['id']: r for r in json.loads((root / 'releases-before-publish.json').read_text())}
    now = {r['id']: r for r in all_releases() if r['tag_name'] != tag}
    assert set(now) == set(before) and all(ident(before[i]) == ident(now[i]) for i in before), 'Prior releases changed'
    state.update(phase='publishing', mainAtPublish=main)
    state_file.write_text(json.dumps(state, indent=2) + '\n')
    final = api(f'repos/{repo}/releases/{state["releaseId"]}', '-X', 'PATCH', '-F', 'draft=false',
                '-f', 'make_latest=true', '-f', f'tag_name={tag}', '-f', f'target_commitish={state["source"]}')
    assert final['draft'] is False and final['prerelease'] is False, final
    state.update(phase='published', publishedAt=final['published_at'], url=final['html_url'])
    state_file.write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps(state, indent=2))


if __name__ == '__main__':
    if args.command == 'draft':
        draft(args.dist.resolve(), args.run_id, args.android_sha256)
    else:
        publish()
