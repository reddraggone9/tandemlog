# TEST ONLY Android recovery harness

This target is outside `lib/` and is never imported by the production entrypoint.
It runs six synthetic cases through the actual `TaskStore`, native text engine,
SQLite and native file transport. The existing Android SAF adapter can be selected
with its existing platform folder picker. There is no new dependency or plugin.

The two Save cases inject an unknown outcome before/after canonical append,
then retry the frozen draft with deliberately different metadata. They require
identical receipt bytes/ID, exactly one canonical occurrence, native draft rollback
until acknowledgement, original schedule/tags, and successful selective Undo.
The four restart cases cross before/after append with retained/deleted SQLite.
They require preserved writer UUID, exact private receipt/retry, canonical dedup,
metadata preservation, and acknowledged intent cleanup. Each case has its own
private profile. The SAF run shares a newly selected, strictly empty canonical
folder across these synthetic writers and leaves its evidence intact.

Build from reviewed committed source, excluding all dirty production prototypes:

```bash
source /workspace/toolchains/env.sh
export RUSTUP_HOME=/tmp/tandemlog-rustup-android
export CARGO_HOME=/workspace/toolchains/cargo
export PATH="$CARGO_HOME/bin:$PATH"
python3 tool/android_recovery/build_apk.py \
  --revision 926f28dd617527d168ce94236bb9f4a99d1f9708 \
  --output /workspace/android-recovery-artifact
```

The build script exports an isolated committed tree under `/tmp`, overlays only
the two harness Dart files, and patches only that snapshot's application ID,
label and activity qualification. The APK has the separate identity
`com.reddraggone9.tandemlog.recoverytest`, label `TEST ONLY Tandemlog Recovery`,
and SDK debug signing. No publication, release signing, production profile,
production Gradle edit or production `lib/main.dart` edit occurs. Exact source,
overlay hashes and APK SHA-256 are recorded in `provenance.json`.

Install/run on the local Android worker:

```bash
adb install -r /workspace/android-recovery-artifact/tandemlog-TEST-ONLY-recovery-debug.apk
adb shell am start -n com.reddraggone9.tandemlog.recoverytest/com.reddraggone9.tandemlog.MainActivity
```

Tap **Run private folder** or **Choose empty SAF folder**. Each tap runs exactly
six cases; there is no timer or background retry. For SAF, create a fresh empty
folder in the system picker. A populated folder is rejected before any store
opens. Capture `TANDEMLOG_RECOVERY` / `TANDEMLOG_RECOVERY_RESULT` through logcat.
The screen reports the exact app-private `report.json` path. Export it using its
path shown on screen or enumerate the app's own synthetic reports:

```bash
adb shell run-as com.reddraggone9.tandemlog.recoverytest find app_flutter -name report.json
adb exec-out run-as com.reddraggone9.tandemlog.recoverytest cat app_flutter/recovery-REPLACE/report.json > android-recovery-report.json
adb logcat -d -s flutter:I > android-recovery-logcat.txt
```

Inspect `passed: true`, six passed case records and each
`canonicalOccurrences: 1`. Retain the native Android report, transport, device/API,
APK hash and logs together. The runner retains synthetic profiles/logs for review;
a subsequent run gets a fresh profile root, and SAF needs a fresh empty folder.

Focused host verification:

```bash
TANDEMLOG_TEXT_LIBRARY=/tmp/tandemlog-yrs-adoption/linux/libtandemlog_text.so \
  flutter test test/android_recovery_harness_test.dart
flutter analyze tool/android_recovery test/android_recovery_harness_test.dart
```

Limits: orderly store close/reopen exercises SQLite recovery, not Android process
kill or power failure. Synthetic failure surrounds the real append call; it does
not reproduce a provider's own partial write/failure. This target does not cover
editor UI, incoming remote sync or notifications. Linux test results are host
evidence only; Android/SAF execution remains pending until the exact APK runs on
the local worker. No cloud KVM Android run is claimed.

On `experiment/text-activation-policy` only, the existing Android CI job also
builds this separate target from the immutable reviewed base above. Its APK and
provenance are under `android-recovery/` in that run's Android artifact. The main
application target and other branches never package the recovery entrypoint.
