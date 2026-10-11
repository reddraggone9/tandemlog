import argparse,datetime,hashlib,json,os,re,subprocess,sys,time,urllib.request,zipfile,zlib
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--promotion-run',required=True,type=int);parser.add_argument('--dispatch-sha',required=True);parser.add_argument('--notes-sha256',required=True);args=parser.parse_args()
r=Path('/tmp/food-rc64-publication/independent-public-verification');r.mkdir(mode=0o700,exist_ok=True);repo=Path('/tmp/tandemlog-food-date-readability');name='reddraggone9/tandemlog';tag='v2026.10.4-rc.2';source='71045e5021f9dee821bc24ea1c118158f029fd83'
def digest(data):return hashlib.sha256(data).hexdigest()
def public_json(path):
 request=urllib.request.Request('https://api.github.com/'+path,headers={'Accept':'application/vnd.github+json','User-Agent':'Tandemlog-independent-public-verification'})
 with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
def authenticated_json(path):return json.loads(subprocess.check_output(['gh','api',path]))
release=public_json(f'repos/{name}/releases/tags/{tag}');(r/'anonymous-release-api.json').write_text(json.dumps(release,indent=2)+'\n')
assert release['tag_name']==tag and release['draft'] is False and release['prerelease'] is True
latest=public_json(f'repos/{name}/releases/latest');before_latest=json.loads(Path('/tmp/food-rc64-latest-before-20261011.json').read_text());assert latest['id']==before_latest['id'] and latest['tag_name']=='v2026.10.3'
notes=(release['body'] or '').encode('utf-8');assert digest(notes)==args.notes_sha256
assert notes==subprocess.check_output(['git','-C',str(repo),'show',args.dispatch_sha+':design/prerelease-notes.md'])
(r/'published-release-notes.md').write_bytes(notes)
manifest=json.loads(Path('/tmp/food-rc64-calendar-artifact-independent-review/build64-independent-original-artifact-manifest.json').read_text())
expected={'tandemlog-2026.10.4-rc.2-android.apk':manifest['members']['android-release/tandemlog-android.apk'],'tandemlog-2026.10.4-rc.2-windows-x64-setup.exe':manifest['members']['windows/tandemlog-windows-x64-unsigned-setup.exe'],'tandemlog-2026.10.4-rc.2-linux-x64.flatpak':manifest['members']['linux/tandemlog-linux-x64.flatpak']}
assert len(release['assets'])==3 and {a['name'] for a in release['assets']}==set(expected)
assets=[]
for asset in release['assets']:
 e=expected[asset['name']];assert asset['size']==e['bytes'] and asset['digest']=='sha256:'+e['sha256'] and asset['state']=='uploaded'
 p=r/asset['name'];request=urllib.request.Request(asset['browser_download_url'],headers={'User-Agent':'Tandemlog-independent-public-verification','Accept':'application/octet-stream'})
 assert not request.has_header('Authorization')
 with urllib.request.urlopen(request,timeout=60) as response,p.open('wb') as stream:
  while data:=response.read(1048576):stream.write(data)
 actual=p.read_bytes();assert len(actual)==e['bytes'] and digest(actual)==e['sha256'];crc32=f'{zlib.crc32(actual):08x}';assert crc32==e['crc32']
 assets.append({'asset_id':asset['id'],'name':asset['name'],'bytes':len(actual),'sha256':digest(actual),'crc32':crc32,'original_archive_member_crc32':'PASS','GitHub_API_digest_size':'PASS','anonymous_public_download':'PASS no Authorization header; exact returned public browser_download_url','url':asset['browser_download_url']})
refs=authenticated_json(f'repos/{name}/git/matching-refs/tags/');before_refs=json.loads(Path('/tmp/food-rc64-publication/independent-prior-tag-refs-before.json').read_text());prior={x['ref']:x for x in before_refs};after={x['ref']:x for x in refs};assert set(after)==set(prior)|{'refs/tags/'+tag}
assert all(after[k]==v for k,v in prior.items());target=after['refs/tags/'+tag]['object']
if target['type']=='tag':target=authenticated_json(f"repos/{name}/git/tags/{target['sha']}")['object']
assert target['type']=='commit' and target['sha']==source
all_releases=[]
for page in range(1,10):
 chunk=public_json(f'repos/{name}/releases?per_page=100&page={page}');all_releases+=chunk
 if len(chunk)<100:break
before=json.loads(Path('/tmp/food-rc64-releases-before-20261011.json').read_text());current={x['id']:x for x in all_releases};assert set(current)=={x['id'] for x in before}|{release['id']}
release_keys=['id','tag_name','target_commitish','name','draft','immutable','prerelease','created_at','updated_at','published_at','body'];asset_keys=['id','node_id','name','label','state','content_type','size','digest','browser_download_url','created_at','updated_at']
def normalized(x):return {'release':{k:x.get(k) for k in release_keys},'assets':sorted([{k:a.get(k) for k in asset_keys} for a in x['assets']],key=lambda x:x['id'])}
assert all(normalized(current[x['id']])==normalized(x) for x in before)
apk=r/'tandemlog-2026.10.4-rc.2-android.apk'
with zipfile.ZipFile(apk) as z:assert z.testzip() is None;crc_count=len(z.infolist())
sys.path.insert(0,str(repo/'tool'));import android_release
sdk=Path('/workspace/toolchains/android-sdk/build-tools/36.0.0');signature=subprocess.check_output([str(sdk/'apksigner'),'verify','--verbose','--print-certs',str(apk)],text=True);badging=subprocess.check_output([str(sdk/'aapt'),'dump','badging',str(apk)],text=True);pin='0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d';android_release.verify_apk(signature,badging,pin,('2026.10.4-rc.2',64));(r/'public-apk-signature.txt').write_text(signature);(r/'public-apk-badging.txt').write_text(badging)
promotion=authenticated_json(f'repos/{name}/actions/runs/{args.promotion_run}');assert promotion['head_sha']==args.dispatch_sha and promotion['status']=='completed' and promotion['conclusion']=='success';jobs=authenticated_json(f'repos/{name}/actions/runs/{args.promotion_run}/jobs');assert len(jobs['jobs'])==2 and all(j['conclusion']=='success' for j in jobs['jobs'])
for file,data in [('latest-after-api.json',latest),('all-releases-after-api.json',all_releases),('tag-refs-after-api.json',refs),('promotion-run-api.json',promotion),('promotion-jobs-api.json',jobs)]: (r/file).write_text(json.dumps(data,indent=2)+'\n')
result={'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'verdict':'ACCEPT_INDEPENDENT_ANONYMOUS_PUBLIC_BYTES_AND_RELEASE_PRESERVATION','release_id':release['id'],'tag':tag,'source':source,'version':'2026.10.4-rc.2+64','candidate_run':38133887765,'promotion_run':args.promotion_run,'dispatch_sha':args.dispatch_sha,'notes_sha256':digest(notes),'assets':assets,'public_APK_signature_package_version_nondebuggable_threeABIs':'PASS ownSDK36','APK_zip_crc_members':crc_count,'tag_source':'PASS exact accepted candidate source','prerelease_notLatest':True,'stableLatest_unchanged':'v2026.10.3','prior_releases_unchanged':len(before),'prior_tag_refs_unchanged':len(prior),'prior_comparison_scope':'Release identities/notes/source targets/flags/timestamps and asset identities/names/digests/sizes/timestamps; download_count intentionally excluded as mutable traffic statistics. All prior tag ref/object metadata exact.','qualification':'Verified actual anonymous public installer bytes and source-bound promotion; no rebuild or runtime execution. Native64 acceptance consumed in separate readiness receipt. Existing inherited RELRO qualification retained; no fullAPK16K runtime/compliance claim.'}
p=r/'independent-public-verification.json';p.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'receipt':str(p),'sha256':digest(p.read_bytes()),'verdict':result['verdict'],'assets':assets},indent=2))
