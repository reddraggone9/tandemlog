#!/bin/bash
base=/home/nibbler/tandemlog-stalls-lab
out=$base/runs/control; mkdir -p $out/runtime; chmod 700 $out/runtime
export XDG_RUNTIME_DIR=$out/runtime GTK_USE_PORTAL=0 NO_AT_BRIDGE=1
if [ "${PRIVATE_BUS:-0}" != 1 ]; then exec dbus-run-session -- env PRIVATE_BUS=1 bash "$0" "$@"; fi
: > $out/display
Xvfb -displayfd 3 -screen 0 1600x1000x24 -nolisten tcp 3>$out/display >/dev/null 2>&1 & xpid=$!
for i in {1..50}; do test -s $out/display && break; sleep .1; done
export DISPLAY=:$(cat $out/display)
openbox >/dev/null 2>&1 & wpid=$!
sleep 1
for i in 1 2 3 4 5 6 7 8; do for w in 0 1; do
  echo -n "warmup=$w "; PROBE_WARMUP=$w timeout 20 $base/control/build/linux/x64/release/bundle/floorprobe 2>/dev/null | grep PROBE_FIRST_LIST | sed "s/.*ms=/ms=/"
  sleep 0.5
done; done
kill $wpid $xpid
