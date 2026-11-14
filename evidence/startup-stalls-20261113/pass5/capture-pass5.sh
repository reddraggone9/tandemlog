#!/bin/bash
# stallrun.sh <bundle-dir> <name> [warm]: private bus + Xvfb + openbox, then stallrun.py.
set -uo pipefail
base=/home/nibbler/tandemlog-stalls-lab
name=$2; out=$base/runs/$name
if [ "${PRIVATE_BUS:-0}" != 1 ]; then
 mkdir -p "$out/runtime"; chmod 700 "$out/runtime"
 export XDG_RUNTIME_DIR=$out/runtime GTK_USE_PORTAL=0
 exec dbus-run-session -- env PRIVATE_BUS=1 bash "$0" "$@" 2>"$out/dbus.log"
fi
source $base/env.sh
export NO_AT_BRIDGE=1
: > "$out/display"
Xvfb -displayfd 3 -screen 0 1600x1000x24 -nolisten tcp 3>"$out/display" > "$out/xvfb.log" 2>&1 & xpid=$!
trap 'kill "${wpid:-}" "$xpid" 2>/dev/null; for p in $(pgrep -u nibbler -f "xdg-|at-spi"); do grep -qz "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" /proc/$p/environ 2>/dev/null && kill $p; done; wait 2>/dev/null' EXIT
for i in {1..50}; do test -s "$out/display" && break; sleep .1; done
export DISPLAY=:$(cat "$out/display")
for i in {1..50}; do xdpyinfo >/dev/null 2>&1 && break; sleep .1; done
openbox > "$out/openbox.log" 2>&1 & wpid=$!
mkdir -p $base/ws
python3 $base/capture-pass5.py $base/repo "$1" $base/ws/$name "${3:-5}" 2>"$out/stderr.log" >"$out/stdout.log"; rc=$?; grep -E "^(strict|warm|  zz) " "$out/stdout.log" | tee "$out/result.txt"; echo "exit $rc"; exit 0
# | tee "$out/result.txt"
echo "exit ${PIPESTATUS[0]}"
