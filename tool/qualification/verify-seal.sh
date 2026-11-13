#!/bin/bash
set -euo pipefail
source "$SCRIPTS/arguments.sh"
python3 - "$REF/adb-run-telemetry.jsonl" <<'PY'
import json,sys
rows={r['phase']:r for r in map(json.loads,open(sys.argv[1]))}
a,b=rows['before'],rows['after']
assert a['pid']==b['pid'] and a['start']==b['start'], 'vex-adb server restarted during the run'
rate=(b['ticks']-a['ticks'])/a['clk']/(b['monotonic']-a['monotonic'])
assert rate<=0.05, f'vex-adb server averaged {rate:.3f} CPU during the run; not idle'
print(f'vex-adb idle during the run: {rate:.4f} CPU average, same server')
PY
sudo -n /usr/bin/python3 -I -B - "$Q" <<'PY'
import json,pathlib,sys
q=pathlib.Path(sys.argv[1]); inv=q/'invocation'; e=q/'invocation.executor'
read=lambda p:json.loads(p.read_text())
result=read(e/'executor-result.json'); final=read(e/'independent-final.json'); clean=read(inv/'cleanup.json')
assert result['errors']==[] and result['originalClientExit']==result['finalizeExit']==0
assert result['readyForParentEvidenceReviewOnly'] is True
assert final['checksPassed'] is True and final['remainingExactProcesses']==[]
assert all(v['MainPID']=='0' and v['ActiveState'] in ('inactive','failed') for v in final['units'].values())
assert all(not v['members'] for v in final['groups'].values())
assert clean['errors']==[] and clean['activeProcesses']==clean['workloadSwapBytes']==clean['oomKills']==0
assert all(clean[k] is True for k in ('ownedUnitsInactive','ownedProcessesAbsent','inputPinsUnchanged','withinDeadline','verifiedCompletionCapture'))
assert clean['resourceCaptureBoundary']=='work-complete/pre-exit'
gate=read(inv/'run/gate-result.json')
assert all(gate[k] is True for k in ('correctnessAccepted','measurementCompleted','allPinsMatch','releaseGateAccepted','timingLimitsPassed'))
assert not gate.get('error') and gate['timingRole']=='enforcing' and gate['measureOnly'] is False
print('Original executor, final readbacks, cleanup and enforcing result consistent; parent review still required')
PY
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -B "$Q/source/tool/performance/reference_receipt.py" seal \
  --repo "$Q/source" --request "$Q/request.json" --run "$Q/invocation/run" \
  --cleanup "$Q/invocation/cleanup.json" --output "$Q/bundle"
sudo -n -u nibbler /usr/bin/env -i HOME=/home/nibbler PATH=/usr/bin:/bin PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -B "$Q/source/tool/performance/reference_receipt.py" verify \
  --repo "$Q/source" --output "$Q/bundle" > "$REF/verify-lab.json"
sudo -n test ! -e "$REF/current-source-bundle"
sudo -n cp -a "$Q/bundle" "$REF/current-source-bundle"
sudo -n chown -R "$(id -u):$(id -g)" "$REF/current-source-bundle"
python3 -B "$PRODUCT/tool/performance/reference_receipt.py" verify \
  --repo "$PRODUCT" --output "$REF/current-source-bundle" > "$REF/verify-current-source.json"
