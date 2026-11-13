"""Anonymous, fail-closed verification of the finalized stable release and prior releases.
Input draft-release.json: source, releaseId, assets {name:{sha256,size}}.
Input release-notes-published.md: exact independently reviewed dispatched notes.
"""
import hashlib,json,re,urllib.request,os,subprocess,sys
from pathlib import Path
from release_context import context, configure, asset_inventory
parser = context('Anonymously verify stable assets and frozen prior state.')
parser.add_argument('--build-tools', type=Path, required=True)
args = configure(parser.parse_args())
ROOT, TAG = args.output, args.tag
API = f'https://api.github.com/repos/{args.repository}'
# Deliberately no Authorization header, credential access or inherited egress proxy.
http=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def get(url):
    request=urllib.request.Request(url,headers={'User-Agent':'tandemlog-public-verify','Accept':'application/vnd.github+json'})
    with http.open(request,timeout=180) as response:return response.read()
def j(url):return json.loads(get(url))
def ident(r):
    return (r['id'],r['tag_name'],r['prerelease'],r['draft'],r['body'],r['target_commitish'],r.get('immutable'),
            tuple(sorted((a['id'],a['name'],a['size'],a.get('digest')) for a in r['assets'])))
state=json.loads((ROOT/'draft-release.json').read_text())
release=j(API+'/releases/tags/'+TAG)
assert release['id']==state['releaseId']
assert not release['prerelease'] and not release['draft'] and release.get('immutable'),release
latest=j(API+'/releases/latest')
prior_latest=json.loads((ROOT/'prior-latest.json').read_text())
assert latest['id']==release['id'] and latest['tag_name']==TAG
assert state['tag']==TAG
assert asset_inventory(release)==state['assets']
ref=j(API+'/git/ref/tags/'+TAG)['object']
sha=ref['sha'] if ref['type']=='commit' else j(ref['url'])['object']['sha']
assert sha==state['source'],sha
notes=(ROOT/'release-notes-published.md').read_text()
assert release['body'].strip()==notes.strip()
assert len(release['assets'])==len(state['assets']) and {a['name'] for a in release['assets']}==set(state['assets'])
folder=ROOT/'public-download';folder.mkdir(exist_ok=True)
verified={}
for asset in release['assets']:
    name=asset['name'];assert '/' not in name and '\\' not in name
    data=get(asset['browser_download_url'])
    actual={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data)}
    assert actual==state['assets'][name],(name,actual)
    if asset.get('digest'):assert asset['digest']=='sha256:'+actual['sha256']
    (folder/name).write_bytes(data);verified[name]=actual
sys.path.insert(0, str(args.repo_dir / 'tool'))
from android_release import fingerprint, verify_apk, version
source_file = lambda path: subprocess.check_output(['git', '-C', str(args.repo_dir), 'show', state['source'] + ':' + path], text=True)
pin = fingerprint(source_file('android/signing-certificate.sha256'))
expected = version(source_file('pubspec.yaml'))
assert TAG == 'v' + expected[0]
apk = folder / f'tandemlog-{expected[0]}-android.apk'
certs = subprocess.check_output([args.build_tools / 'apksigner', 'verify', '--print-certs', '--verbose', apk], text=True)
badging = subprocess.check_output([args.build_tools / 'aapt', 'dump', 'badging', apk], text=True)
verify_apk(certs, badging, pin, expected)
images=re.findall(r'\((https://raw\.githubusercontent\.com/[^)]+\.png)\)',notes)

for url in images:
    prefix = f'https://raw.githubusercontent.com/{args.repository}/'
    assert url.startswith(prefix), 'Note image must be in this repository'
    revision, path = url[len(prefix):].split('/', 1)
    assert re.fullmatch('[0-9a-f]{40}', revision) and path.startswith('design/media/'), 'Note image must be commit-pinned'
    data=get(url)
    expected_image = subprocess.check_output(['git', '-C', str(args.repo_dir), 'show', revision + ':' + path])
    assert data == expected_image, url
prior={r['id']:r for r in json.loads((ROOT/'prior-releases.json').read_text())}
now=[];page=1
while True:
    batch=j(API+f'/releases?per_page=100&page={page}')
    if not batch:break
    now.extend(batch);page+=1
remaining={r['id']:r for r in now if r['tag_name']!=TAG}
assert set(remaining)==set(prior)
assert all(ident(remaining[i])==ident(prior[i]) for i in prior)
prior_tags={r['ref']:r['object'] for r in json.loads((ROOT/'prior-tags.json').read_text())}
now_tags={r['ref']:r['object'] for r in j(API+'/git/matching-refs/tags/')}
assert set(now_tags)==set(prior_tags)|{'refs/tags/'+TAG}
assert all(now_tags[k]==v for k,v in prior_tags.items())
result={'result':'PASS','release':release['html_url'],'releaseId':release['id'],'source':sha,'prerelease':False,'latest':True,
        'immutable':release['immutable'],'stableLatest':latest['tag_name'],'publishedAt':release['published_at'],'notesMatchReviewedBytes':True,
        'apkSignerVersionVerified':True,'noteImagesVerified':len(images),'assets':verified,'priorReleasesUnchanged':len(prior),'priorTagsUnchanged':len(prior_tags)}
(ROOT/'public-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
