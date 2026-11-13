#!/bin/bash
# One qualification with vex-adb left running. Never stops, restarts or uses adb.
set -euo pipefail
cd /
source "$SCRIPTS/arguments.sh"
SAMPLER=
exec > "$REF/service-coordination.log" 2>&1
date -u +%FT%TZ
adb_sample() {
  pid=$(systemctl --user show vex-adb.service -p MainPID --value)
  python3 - "$pid" "$1" <<'PY' >> "$REF/adb-run-telemetry.jsonl"
import json,os,sys,time
pid,phase=int(sys.argv[1]),sys.argv[2]
f=open(f'/proc/{pid}/stat').read().rsplit(')',1)[1].split() if pid else None
print(json.dumps({'phase':phase,'pid':pid,'monotonic':time.monotonic(),'ticks':int(f[11])+int(f[12]) if f else None,'start':f[19] if f else None,'clk':os.sysconf('SC_CLK_TCK')}))
PY
}
cleanup() { rc=$?; test -n "$SAMPLER" && kill "$SAMPLER" 2>/dev/null; adb_sample after || true; systemctl --user show vex-adb.service -p ActiveState -p MainPID; printf 'coordinatorExit=%s\n' "$rc"; exit "$rc"; }
trap cleanup EXIT
systemctl --user show vex-adb.service -p ActiveState -p MainPID -p ActiveEnterTimestamp
python3 -I -B "$SCRIPTS/quiet_admission.py" "$REF/quiet-before-plan.json" > "$REF/quiet-before-plan.log" 2>&1
date -u +%FT%TZ
ps -e -o uid=,pid=,comm= > "$REF/processes-at-plan.txt"
sudo -n /usr/bin/env -i HOME=/root PATH=/usr/bin:/bin LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -I -B "$LAUNCHER" plan "${ARGS[@]}" > "$REF/plan-preflight-admitted.json" 2> "$REF/plan-preflight-admitted.stderr"
python3 - "$REF/plan-preflight-admitted.json" "$R8_SHA" "$LAUNCHER_SHA" <<'CHECK'
import json,sys
from pathlib import Path
expected=json.loads((Path(sys.argv[1]).parent/"fresh-request-bindings.json").read_text())
p=json.load(open(sys.argv[1]))
assert p['requestId']==expected['requestId']
assert p['sourceRevision']==expected['sourceRevision']
assert p['requestSHA256']==expected['requestSHA256']
assert p['controllerSHA256']==sys.argv[2]
assert p['pressureSHA256']=='f67076216c21ae898dd0728132bbbfe388af307b8734c056f0ab5d05b7797e10'
assert p['launcherSHA256']==sys.argv[3]
assert p['executionSeconds']==1500 and p['sharedCleanupSeconds']==20
assert p['noExternalRetry'] and not p['sealsAutomatically']
assert expected['requestId'] in p['managerUnit'] and expected['requestId'] in p['workloadUnit']
assert p['output']==str(Path(__import__('os').environ['Q'])/'invocation')
print(json.dumps({k:v for k,v in p.items() if k not in ('context','initialUnits','managerCommand','finalizeCommand')},indent=2))
CHECK
# Device work during the run would compete with the workload unseen by the
# controller's preflight-only check; the seal refuses if the server averaged
# more than the controller's idle threshold.
adb_sample before
"$SCRIPTS/host-sampler.sh" > "$REF/host-samples.log" 2>&1 &
SAMPLER=$!
bash "$SCRIPTS/launch.sh"
