#!/bin/bash
# Read-only evidence for "was the host quiet during the run": one sample a minute. Not part of the gate.
while :; do
  printf '%s load=%s cpu=%s io=%s\n' "$(date -u +%FT%TZ)" "$(cut -d' ' -f1-3 /proc/loadavg)" "$(head -1 /proc/pressure/cpu)" "$(head -1 /proc/pressure/io)"
  cat /sys/fs/cgroup/user.slice/cpu.stat /sys/fs/cgroup/system.slice/cpu.stat
  ps -eo user=,pid=,stat=,time=,comm= | awk '$3 ~ /^R/' | head -12
  sleep 60
done
