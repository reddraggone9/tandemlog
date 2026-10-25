#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" != 0 ]]; then
  echo "Usage: run_io_diagnostic.sh" >&2
  exit 2
fi
repo=$(pwd -P)
output="$RUNNER_TEMP/io-diagnostic-results"
unit="tandemlog-io-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
runner_uid=$(id -u)
runner_gid=$(id -g)
dart="$(dirname "$(command -v flutter)")/cache/dart-sdk/bin/dart"
cleanup() {
  original_status=$?
  status=$original_status
  trap - EXIT
  if ! stop_message=$(sudo -n systemctl stop "$unit.service" 2>&1); then
    echo "I/O diagnostic stop diagnostic: $stop_message" >&2
  fi
  load_state=""
  state=""
  main_pid=""
  if observed=$(sudo -n systemctl show "$unit.service" \
      --property=LoadState --property=ActiveState --property=MainPID); then
    while IFS='=' read -r key value; do
      case "$key" in
        LoadState) load_state="$value" ;;
        ActiveState) state="$value" ;;
        MainPID) main_pid="$value" ;;
        *) status=1 ;;
      esac
    done <<< "$observed"
    if [[ "$main_pid" != 0 ]] ||
       ! { [[ "$load_state" == not-found && "$state" == inactive ]] ||
           [[ "$load_state" == loaded && ( "$state" == inactive || "$state" == failed ) ]]; }; then
      echo "I/O diagnostic cleanup postcondition failed: $observed" >&2
      status=1
    fi
  else
    echo "I/O diagnostic cleanup manager query failed; absence is unverified" >&2
    status=1
  fi
  if [[ "$original_status" != 0 ]]; then status=$original_status; fi
  echo "I/O diagnostic cleanup: unit=$unit.service load=$load_state state=$state pid=$main_pid"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
test -f "$TANDEMLOG_TEXT_LIBRARY"
test -f "$repo/.dart_tool/lib/libsqlite3.so"
timeout --signal=TERM --kill-after=20s 1290s \
  sudo -n systemd-run --unit="$unit" --uid="$runner_uid" --gid="$runner_gid" \
    --wait --pipe --collect --service-type=exec \
    --property=WorkingDirectory="$repo" \
    --property=MemoryMax=6G --property=MemorySwapMax=0 \
    --property=CPUQuota=200% --property=TasksMax=128 \
    --property=RuntimeMaxSec=1260 --property=TimeoutStopSec=20 \
    --property=KillMode=control-group --property=OOMPolicy=kill \
    /usr/bin/env -i HOME="$HOME" PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}" \
      PATH="$PATH" LANG=C.UTF-8 \
      /usr/bin/python3 "$repo/tool/diagnose_performance_io.py" \
      --repo "$repo" --dart "$dart" \
      --native-library "$TANDEMLOG_TEXT_LIBRARY" \
      --sqlite-library "$repo/.dart_tool/lib/libsqlite3.so" \
      --output "$output"
