import datetime, hashlib, json, subprocess, sys, urllib.request, zipfile
from pathlib import Path

repo = Path('/tmp/tandemlog-food-date-readability')
out = Path('/tmp/food-rc64-publication/root-public-verification')
out.mkdir(exist_ok=True)
dispatch, run = sys.argv[1:]
name = 'reddraggone9/tandemlog'
tag = 'v2026.10.4-rc.2'
source = '71045e5021f9dee821bc24ea1c118158f029fd83'
notes_sha = '8608fcdba20b61f67ae9f9cd33b3c4da00c65c47af5fb34a7ae2011b6830fea8'
expected = {
    'tandemlog-2026.10.4-rc.2-android.apk': (67000993, 'c5e6aff8cb25c0b6a67a8fce79aaabd000be352d891fc11025d7b20efcca117f'),
    'tandemlog-2026.10.4-rc.2-windows-x64-setup.exe': (12376785, '76727c860e176b166f31c615f6ef9210fce97ab77d6a6b43ac5de5954d822c09'),
    'tandemlog-2026.10.4-rc.2-linux-x64.flatpak': (9225872, 'd3ee6b7b971d742514075075336ace5246f7693f57170ea4db849c8af10527e3'),
}
def digest(b):
    return hashlib.sha256(b).hexdigest()
def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{name}/{path}']))
def save(file, x):
    (out / file).write_text(json.dumps(x, indent=2) + '\n')
release = api(f'releases/tags/{tag}')
assert release['tag_name'] == tag and release['prerelease'] and not release['draft']
assert {a['name'] for a in release['assets']} == set(expected) and len(release['assets']) == 3
notes = release['body'].encode()
assert digest(notes) == notes_sha
assert notes == subprocess.check_output(['git', '-C', str(repo), 'show', f'{dispatch}:design/prerelease-notes.md'])
save('release-api.json', release)
(out/'published-notes.md').write_bytes(notes)
actual = []
for a in release['assets']:
    size, sha = expected[a['name']]
    assert a['size'] == size and a['digest'] == 'sha256:' + sha and a['state'] == 'uploaded'
    request = urllib.request.Request(a['browser_download_url'], headers={'User-Agent': 'Tandemlog-public-acceptance'})
    assert not request.has_header('Authorization')
    p = out / a['name']
    with urllib.request.urlopen(request, timeout=60) as response, p.open('wb') as f:
        while b := response.read(1048576):
            f.write(b)
    assert p.stat().st_size == size and digest(p.read_bytes()) == sha
    actual.append({'name': a['name'], 'asset_id': a['id'], 'bytes': size, 'sha256': sha,
                   'anonymous_actual_download': 'PASS', 'browser_download_url': a['browser_download_url']})
    print('Actual anonymous installer PASS:', a['name'], flush=True)
refs = api('git/matching-refs/tags/')
old_refs = json.loads(Path('/tmp/food-rc64-publication/tags-before.json').read_text())
before_refs = {x['ref']: x for x in old_refs}
after_refs = {x['ref']: x for x in refs}
assert set(after_refs) == set(before_refs) | {'refs/tags/' + tag}
assert all(after_refs[k] == v for k, v in before_refs.items())
obj = after_refs['refs/tags/' + tag]['object']
if obj['type'] == 'tag':
    obj = api('git/tags/' + obj['sha'])['object']
assert obj == {'type': 'commit', 'sha': source, 'url': f'https://api.github.com/repos/{name}/git/commits/{source}'}
latest = api('releases/latest')
old_latest = json.loads(Path('/tmp/food-rc64-publication/latest-before.json').read_text())
assert latest['id'] == old_latest['id'] == 408448633 and latest['tag_name'] == 'v2026.10.3'
releases = api('releases?per_page=100')
before = json.loads(Path('/tmp/food-rc64-publication/releases-before.json').read_text())
assert len(before) == 23
after = {x['id']: x for x in releases}
assert set(after) == {x['id'] for x in before} | {release['id']}
rk = ['id','tag_name','target_commitish','name','draft','immutable','prerelease','created_at','updated_at','published_at','body']
ak = ['id','node_id','name','label','state','content_type','size','digest','browser_download_url','created_at','updated_at']
def normalized(x):
    return ({k:x.get(k) for k in rk}, sorted([{k:a.get(k) for k in ak} for a in x['assets']], key=lambda a:a['id']))
assert all(normalized(after[x['id']]) == normalized(x) for x in before)
promotion = api('actions/runs/' + run)
assert promotion['head_sha'] == dispatch and promotion['status'] == 'completed' and promotion['conclusion'] == 'success'
jobs = api('actions/runs/' + run + '/jobs')
assert len(jobs['jobs']) == 2 and all(j['conclusion'] == 'success' for j in jobs['jobs'])
apk = out/'tandemlog-2026.10.4-rc.2-android.apk'
sdk = Path('/workspace/toolchains/android-sdk/build-tools/36.0.0')
signature = subprocess.check_output([str(sdk/'apksigner'), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
badging = subprocess.check_output([str(sdk/'aapt'), 'dump', 'badging', str(apk)], text=True)
sys.path.insert(0, str(repo/'tool'))
import android_release
android_release.verify_apk(signature, badging, '0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d', ('2026.10.4-rc.2', 64))
with zipfile.ZipFile(apk) as z:
    assert z.testzip() is None
    count = len(z.infolist())
(out/'public-apksigner.txt').write_text(signature)
(out/'public-badging.txt').write_text(badging)
for file, x in [('latest-api.json', latest), ('tag-refs-api.json', refs), ('all-releases-api.json', releases), ('promotion-run-api.json', promotion), ('promotion-jobs-api.json', jobs)]:
    save(file, x)
receipt = {'verdict': 'PASS_ACTUAL_PUBLIC_BYTES_SOURCE_NOTES_SIGNATURE_AND_PRESERVATION',
           'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'release_url': release['html_url'], 'release_id': release['id'], 'tag': tag,
           'candidate_source': source, 'candidate_run': 38133887765, 'promotion_run': int(run),
           'dispatch_sha': dispatch, 'notes_sha256': notes_sha, 'installers': actual,
           'public_APK_signature_package_version_nondebuggable_ABIs': 'PASS Android SDK36 verifier',
           'APK_zip_crc_members': count, 'prerelease_notLatest': True,
           'latest_preserved': 'v2026.10.3', 'prior_public_releases_preserved': len(before),
           'prior_tag_refs_preserved': len(before_refs),
           'preservation_scope': 'Original release metadata/body/timestamps/asset identities/digests/sizes and every prior tag ref/object; mutable download counts excluded.',
           'rebuild': False, 'qualification': 'Public bytes and original accepted artifacts verified; no new runtime test or general16KB compliance claim. Native64 and broad62 attribution remain in separate receipts.'}
save('root-public-verification.json', receipt)
print(json.dumps(receipt, indent=2))
