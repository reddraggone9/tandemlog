#!/bin/bash
set -euo pipefail
export TANDEMLOG_SYNTHETIC_TEMPLATE=/home/nibbler/tandemlog-stalls-lab/ws/baseline
base=/home/nibbler/tandemlog-stalls-lab
for i in 1 2 3 4 5; do
 for side in before after; do
  bundle=$base/bundle-pass3b
  [ "$side" = after ] && bundle=/home/nibbler/tandemlog-stalls-20261113/build/linux/x64/release/bundle
  uptime >> "$base/load-pass5.txt"
  bash "$base/stallrun.sh" "$bundle" "p5-$side-$i" 1
 done
done
