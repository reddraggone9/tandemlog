#!/usr/bin/env bash
source /workspace/toolchains/env.sh
export TANDEMLOG_TEXT_LIBRARY=/workspace/toolchains/tandemlog-rust-bootstrap/target/x86_64-unknown-linux-gnu/release/libtandemlog_text.so
export FONTCONFIG_FILE=/tmp/food-ux-review/native-regressions/ci-fontconfig.conf
export TANDEMLOG_NATIVE_QA_SCREENSHOTS="/tmp/food-ux-review/native-regressions/$1"
mkdir -p "$TANDEMLOG_NATIVE_QA_SCREENSHOTS"
sha256sum lib/main.dart lib/storage/local_profile_database.dart "$2" > "$TANDEMLOG_NATIVE_QA_SCREENSHOTS/source-before.sha256"
test_options=()
if [ -n "${3:-}" ]; then test_options=(--name "$3"); fi
dbus-run-session -- xvfb-run -a -s '-screen 0 1600x1100x24' flutter test "$2" -d linux --no-pub --reporter expanded "${test_options[@]}" > "$TANDEMLOG_NATIVE_QA_SCREENSHOTS/native.log" 2>&1
task_run_status=$?
printf '%s\n' "$task_run_status" > "$TANDEMLOG_NATIVE_QA_SCREENSHOTS/process-exit.txt"
sha256sum lib/main.dart lib/storage/local_profile_database.dart "$2" > "$TANDEMLOG_NATIVE_QA_SCREENSHOTS/source-after.sha256"
exit "$task_run_status"
