#!/bin/bash
set -euo pipefail
cd /
source "$SCRIPTS/arguments.sh"
QUAL_REV=$(git -C "$PRODUCT" rev-parse HEAD)
test -z "$(git -C "$PRODUCT" status --porcelain)"
python3 - "$PRODUCT" <<'PY'
import hashlib,json,pathlib,sys
r=pathlib.Path(sys.argv[1]); p=json.loads((r/'tool/performance/reference-host-v1.json').read_text())
h=p['limitsSHA256']
assert hashlib.sha256((r/'tool/performance/limits-v1.json').read_bytes()).hexdigest()==h
assert p['limitsSHA256']==p['toolHashes']['/tool/performance/limits-v1.json']==h
assert p['controllerSHA256']==__import__('os').environ['R8_SHA']
assert hashlib.sha256((r/'pubspec.lock').read_bytes()).hexdigest()==p['pubspecLockSHA256']
PY
test ! -e "$REF/activity-source.bundle"
git -C "$PRODUCT" bundle create "$REF/activity-source.bundle" HEAD
sudo -n -u nibbler mkdir "$Q"
sudo -n install -o nibbler -g nibbler -m 0644 "$REF/activity-source.bundle" "$Q/source.bundle"
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin \
  /usr/bin/git clone --no-checkout "$Q/source.bundle" "$Q/source"
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin \
  /usr/bin/git -C "$Q/source" checkout --detach "$QUAL_REV"
sudo -n -u nibbler /usr/bin/python3 -I -B - "$Q/source" <<'PY'
import hashlib,json,pathlib,sys,urllib.parse
repo=pathlib.Path(sys.argv[1])
old=pathlib.Path(__import__('os').environ['PACKAGE_CONFIG'])
config=json.loads(old.read_text())
for package in config['packages']:
    package['rootUri']=(repo.as_uri()+'/' if package['name']=='tandemlog'
                        else urllib.parse.urljoin(old.as_uri(),package['rootUri']))
profile=json.loads((repo/'tool/performance/reference-host-v1.json').read_text())
assert sorted(p['name'] for p in config['packages'])==profile['packageNames']
assert hashlib.sha256((repo/'pubspec.lock').read_bytes()).hexdigest()==profile['pubspecLockSHA256']
sys.path.insert(0,str(repo/'tool/performance'))
from reference_receipt import package_contract
assert package_contract(config)==profile['packageContractSHA256']
(repo/'.dart_tool').mkdir()
with (repo/'.dart_tool/package_config.json').open('x') as f:
    json.dump(config,f,indent=2); f.write('\n')
PY
sudo -n -u nibbler chmod -R a-w "$Q/source"
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin GIT_OPTIONAL_LOCKS=0 \
  /usr/bin/git -C "$Q/source" status --porcelain
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin \
  /usr/bin/git -C "$Q/source" rev-parse HEAD
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -B "$Q/source/tool/performance/reference_receipt.py" fingerprint \
  --repo "$Q/source" --output "$Q" > "$REF/fingerprint.json"
python3 - "$REF/fingerprint.json" "$PRODUCT/tool/performance/reference-host-v1.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))==json.load(open(sys.argv[2]))['environment']
PY
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -B "$Q/source/tool/performance/reference_receipt.py" request \
  --repo "$Q/source" --controller "$CTRL" --output "$Q/request.json"
# Launcher plan runs in coordinate-q16.sh with vex-adb up (controller r8 admits it idle).
sudo -n /usr/bin/python3 -I -B - "$Q/request.json" "$QUAL_REV" > "$REF/fresh-request-bindings.json" <<'PY'
import hashlib,json,sys
raw=open(sys.argv[1],'rb').read(); r=json.loads(raw)
assert r['sourceRevision']==sys.argv[2]
print(json.dumps({'requestId':r['requestId'],'requestSHA256':hashlib.sha256(raw).hexdigest(),'sourceRevision':r['sourceRevision']},indent=2))
PY
