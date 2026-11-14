#!/bin/bash
set -euo pipefail
export TANDEMLOG_SYNTHETIC_TEMPLATE=/home/nibbler/tandemlog-stalls-lab/ws/baseline
base=/home/nibbler/tandemlog-stalls-lab
for i in 1 2 3 4 5 6; do
 for side in before after; do
  bundle=$base/bundle-base
  [ "$side" = after ] && bundle=$base/bundle-pass3b
  uptime >> "$base/load-pass7.txt"
  bash "$base/stallrun.sh" "$bundle" "p7-$side-$i" 1
 done
done
