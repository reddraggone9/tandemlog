#!/bin/bash
set -euo pipefail
cd /
source "$SCRIPTS/arguments.sh"
python3 -I -B "$SCRIPTS/quiet_admission.py" "$REF/quiet-admission.json" > "$REF/quiet.log" 2>&1
sudo -n /usr/bin/env -i HOME=/root PATH=/usr/bin:/bin LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -I -B "$LAUNCHER" plan "${ARGS[@]}" \
  > "$REF/plan.json" 2> "$REF/plan.stderr"
cmp "$REF/plan-preflight-admitted.json" "$REF/plan.json"
for p in "$Q/request.json.claimed.json" "$Q/request.json.executor-claimed.json" "$Q/invocation" "$Q/invocation.executor"; do
  sudo -n test ! -e "$p"
done
set +e
sudo -n /usr/bin/env -i HOME=/root PATH=/usr/bin:/bin LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 -I -B "$LAUNCHER" launch "${ARGS[@]}" \
  > "$REF/launch.log" 2>&1
launch_rc=$?
set -e
printf '%s\n' "$launch_rc" > "$REF/launcher-exit.txt"
test "$launch_rc" -eq 0
