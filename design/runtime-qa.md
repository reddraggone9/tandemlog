# Runtime and visual QA — 2026-09-30

## Actual environment and target matrix

| Target | Verified evidence | Remaining limit |
| --- | --- | --- |
| Linux native | Flutter GTK app built in debug/release, launched under Xvfb/Openbox; actual folder picker, capture/edit/completion shown; native integration flow passed restart, undo and unsupported-record recovery | Linux is the accepted primary desktop visual QA target, not proof of Windows-specific behavior. Software display/container performance does not predict phones. |
| Android build | `flutter build apk --debug` passed (262.0 s); APK at `build/app/outputs/flutter-apk/app-debug.apk`, 153 MiB universal debug | Kotlin bridge compiles; this does not verify SAF or native UI. |
| Android runtime | rc1 passed eight native API 30 workflow/SAF assertions on accelerated Farnsworth; see evidence below | Revised rc2 UI, real phones, API 36 and actual BasicSync remain pending. Cloud software emulation is unusable. |
| Windows | Hosted Windows native release build and domain/storage tests passed | Native launch and targeted packaging/path/dialog/startup checks remain pending. Linux is the routine desktop visual QA target. |
| Web | Not used for app acceptance | A browser preview would not validate Android or Windows. |

The [Android emulator acceleration guide](https://developer.android.com/studio/run/emulator-acceleration) describes KVM requirements. Here `emulator -accel-check` reports KVM requires vmx/svm; `/dev/kvm` is absent. Software emulation was actually attempted, not dismissed from this probe alone.

## Linux workflow evidence

`flutter test integration_test/task_flow_test.dart -d linux` exercises real native Flutter: create/select user, capture, edit title/notes, complete, immediate undo, retain a typed draft through periodic refresh, recreate the app with the same profile, encounter a complete unknown-version record, remove the bad test fixture and recover. The folder chooser was separately operated in the native GTK UI; integration preselects a test folder. App recreation verifies persisted state; process restart is also exercised by release measurement/manual workflow.

Visual inspection: cream background, green primary action, bounded white task cards, explicit Inbox labels and notes. The empty state directs capture. The edit dialog shows title/notes and character limits. Initial periodic refresh disabled capture and could interrupt typing; changed to quiet serialized refresh and added a draft-retention check. Actual errors retain known task content with a visible banner. Evidence is under `evidence/`; final selected video/screenshots are delivered through Library when upload succeeds.

## Startup measurement

`tool/measure_startup.py` launches five separate native Linux **release** processes against 2,000 synthetic tasks plus one user. It resets only its isolated benchmark store directory (SQLite cache and local writer identity) before run 1, preserving the synthetic canonical history; runs 2–5 reuse cache. OS page caches are **not** flushed. The external timer begins immediately before process creation and ends when stdout reports a post-frame callback after loading state. The Dart stopwatch begins at TasksPage state construction, excluding engine/process initialization. Neither marker proves physical display presentation or input-ready latency; the external marker is a useful end-to-end approximation, not a device cold-boot claim.

`FILES_READ=0` on warm runs means canonical log contents were not read/replayed. Manifest and directory metadata still receive validation. Cache-hit correctness and total user-perceived startup are separate questions. Raw numbers and concurrency conditions belong with the final JSON results; do not use the internal stopwatch as full cold-start time.

## Android SAF acceptance script

1. Install native APK; choose a dedicated tree using Android DocumentsUI; create user/task.
2. Force-stop/relaunch and reboot; verify retained URI permission, task and write ability.
3. Replace a remote writer file atomically through the actual sync provider, then refresh/resume; verify enumeration reopens the new document and imports once.
4. Revoke the grant/remove the folder; verify visible failure, no false save acknowledgment and no history overwrite; regrant/recover.
5. Two intended phones: initialize one space, transport manifest, join second; edit offline, exchange logs with BasicSync and another compatible provider where available; check convergence and no-internet hotspot behavior.
6. Record Android API/device/provider versions and actual demo. Emulator directory grants alone cannot establish BasicSync/phone provider behavior.

Android uses [SAF tree/document URIs and persisted grants](https://developer.android.com/training/data-storage/shared/documents-files), not ordinary filesystem paths. SQLite remains private. Syncthing Android's [official retirement](https://forum.syncthing.net/t/discontinuing-syncthing-android/23002) and [closed replacement/grant report #10887](https://github.com/syncthing/syncthing/issues/10887) motivate provider testing; the report is not universal proof of failure or an assertion that the upstream issue remains open.

## Desktop verification split

Linux is the primary desktop visual QA target and ships an x64 bundle. Routine shared UI changes require native Linux visual inspection. Windows retains hosted native builds and targeted packaging, Unicode/path, folder-dialog and startup smoke checks; a full emulated Windows session is not required for every shared UI change. Android still needs independent native visual, lifecycle and SAF tests.

## Windows verification path

On Windows with official Flutter and Visual Studio's Desktop development with C++ workload: `flutter doctor -v`, `flutter pub get`, `flutter analyze`, `flutter test`, `flutter test integration_test/task_flow_test.dart -d windows`, `flutter build windows --release`. Run the generated executable; test native folder picker, keyboard/focus, scaling, Unicode paths, restart, read-only/missing folder and two local profiles exchanging logs. Record an actual Windows video. Do not label a Linux build, cross-compilation, or Wine run as native Windows verification.

Every subsequent UI change requires rerunning the affected workflow, visually inspecting it, recording observations and correcting issues. Accessibility/touch checks, error/repeated/interrupted flows and device transport tests remain explicit acceptance work.

### Recorded release measurements

Historical pre-fix measurement batch (native Linux release, Xvfb/Openbox, software emulator paused; no Gradle build active at batch start):

| Run | SQLite | External launch → loaded-frame marker | Dart state → marker | Log files read |
| --- | --- | ---: | ---: | ---: |
| 1 | Rebuild | 7,955 ms | 963 ms | 1 |
| 2 | Warm | 7,038 ms | 657 ms | 0 |
| 3 | Warm | 7,304 ms | 837 ms | 0 |
| 4 | Warm | 9,234 ms | 1,927 ms | 0 |
| 5 | Warm | 7,535 ms | 1,056 ms | 0 |

Historical pre-fix [JSON](../evidence/linux-release-startup.json); superseded by the controlled diagnosis below. All are fresh processes; “warm” refers to the SQLite cache, not an already-running app. These times are not satisfactory startup performance. The difference before Dart state construction needs profiling of engine/platform initialization on actual intended targets; do not blame SQLite or claim a device-speed prediction without that evidence. Subsequent SDK extraction/download overlapped the measurement batch, so this is not a controlled idle-machine benchmark.

### Deliverables and delivery limitation

`evidence/tandemlog-linux-release-demo.mp4`: 25.001 seconds, native Linux release at 1000×740 content size; actual capture/edit/complete/undo and process restart. Restart pause is shortened and explicitly labeled. Raw recording retained as `tandemlog-linux-demo.mp4`. Key frames and the contact sheet were visually inspected. Final screenshots: `linux-edit-final.png`, `linux-complete-final.png`, `linux-tasks-final.png`, `linux-restart-final.png`.

The reviewed native Linux video and Android emulator ANR screenshot were delivered through Library. Private artifact identity metadata is not committed.


## Controlled startup diagnosis and correction

A separate `flutter create --empty --platforms=linux` project, with **no task code or plugins**, uses `tool/minimal_startup.dart` as its entrypoint. Tests use the same release toolchain, Xvfb display and host. New instrumentation records external launch→Dart `main`, first framework frame, loaded-task frame, identity/lock, SQLite open/schema, manifest, ingestion, query, model decoding and sorting. The first frame may show loading; it is not task-ready. The loaded-frame callback follows `busy=false` and loaded rows, but does not measure physical display presentation or OS input latency.

With emulator paused and builds finished, before correcting the desktop session:

| Workload | Launch→loaded marker, three fresh processes | Launch→Dart main |
| --- | --- | --- |
| Minimal Flutter | 6,867 / 6,454 / 6,476 ms | 6,761 / 6,366 / 6,398 ms |
| 10 tasks | 6,991 / 6,956 / 7,479 ms | 6,466 / 6,297 / 6,343 ms |
| 2,000 tasks | 7,357 / 7,160 / 6,889 ms | 6,394 / 6,539 / 6,353 ms |

`strace -f -tt -T` exposed repeated `dbus-launch --autolaunch` subprocesses sleeping three seconds. `DBUS_SESSION_BUS_ADDRESS` was unset in the headless session. Starting a session bus and explicitly exporting its address removed these waits **without changing the application or Flutter renderer**. This is a verified environment cause, not a general Flutter startup diagnosis or assumed graphics cost.

After correction, emulator paused:

| Workload | Launch→loaded marker | Launch→Dart main | Launch→first frame |
| --- | --- | --- | --- |
| Minimal Flutter | 356 / 445 / 455 ms | 274 / 349 / 373 ms | Same loaded-frame marker |
| 10 tasks | 941 / 878 / 863 ms | 377 / 364 / 263 ms | 656 / 651 / 593 ms |
| 2,000 tasks | 1,091 / 1,001 / 908 ms | 281 / 428 / 308 ms | 603 / 732 / 594 ms |

For task rows, run 1 rebuilds cache, runs 2–3 reuse it; every run starts a fresh process and OS caches are not flushed. Minimal Flutter does not use SQLite. In the 2,000-task corrected run, rebuild ingestion costs 212 ms, warm ingestion 11/21 ms; query 0/5/5 ms, JSON decoding 5/10/5 ms, sorting 1/1/0 ms. Warm reads remain zero log contents. No warm-start N+1 database query was found: one `views` query supplies UI rows. Rebuild does query/project each touched entity, but measured rebuild work is bounded at this dataset and is not the six-second cause. Retain larger-history streaming/projection debt; do not refactor SQL speculatively from the old timings.

Raw controlled results: `evidence/startup-{minimal,small,large}-paused.json` and `evidence/startup-{minimal,small,large}-dbus-paused.json`. Traces are under `/workspace/toolchains/minimal-{startup,process}.strace`. The corrected result is substantially better, but target Windows/phone measurements and input-ready timing remain acceptance work.

For reproducible headless commands, run under an explicit session bus, for example `dbus-run-session -- env DISPLAY=:99 NO_AT_BRIDGE=1 python3 tool/measure_startup.py --tasks 2000 --runs 3`. The current saved environment uses `unix:path=/tmp/tandemlog-session-bus`; recreate it after environment restart. Do not alter users' normal desktop session settings in the shipped app.

With the corrected session and emulator running, minimal release launch→frame is **408 / 460 / 384 ms** (Dart main **303 / 363 / 301 ms**); 2,000 tasks are **1,231 / 1,032 / 951 ms** (Dart main **384 / 373 / 457 ms**, first frame **675 / 645 / 687 ms**). Cache rebuild with fresh benchmark writer identity is the first task run; the next two read zero log contents. Raw files: `startup-minimal-dbus-running.json`, `startup-large-dbus-running.json`. The modest variation does not explain the original pre-Dart delay. All measurements are software-display Linux development evidence, not native target acceptance.

The deliverable video was recorded before the session-bus correction; its edited restart pause is not a startup benchmark. The UI remains the same. Current performance results come from the separate instrumented release runs above.

## Android build and boot attempts

Official build tools and a matching Debian OpenJDK 21 JDK live under `/workspace/toolchains`. Maven Central HTTP 429 was handled with a workspace-only Gradle initialization file using Google's Maven Central mirror; Java proxy settings are also workspace-only. The repository does not force this workaround on other developers. The final debug APK rebuild passed in **26.0 seconds**; the first successful complete build took **262.0 seconds**. Static analysis and all 23 domain/storage tests pass; the final native Linux integration rerun passed after the indexed capture existence-check change.

API 36 software emulation was tried at the original device dimensions, then 480×800 with 3 GiB RAM, two virtual cores, SwiftShader, Vulkan disabled and fresh userdata. It reaches ADB and system_server/package service, but installation returned `Error: device is still booting.` Screen capture has timed out. No native Android app run, tree-grant restart, atomic-replacement test, or Android demo is yet verified. An official API 30 AOSP x86_64 fallback was also tried; its default 12 GiB userdata request exceeded available disk, so the test AVD was configured with a smaller userdata partition. Its final failure is recorded below.

Raw logs: `/workspace/toolchains/android-build-final.log`, `android-install-retry.log`, `emulator-small.log`, `emulator-api30.log`. This is a practical unaccelerated-runtime limitation established in this environment, not a claim that Android emulation is universally impossible. No native Windows environment is exposed.

Final fallback result: API 30 reached `sys.boot_completed=1`, but the package service failed (`Broken pipe (32)`) after a complete x86_64 APK transfer. Host emulator-console screenshots repeatedly showed **System UI isn’t responding**, before Tandemlog installation. Guest input and screenshot requests also timed out. Both software emulators were stopped. This establishes an unusable runtime in this environment, not an application failure. Evidence: `evidence/android-emulator-system-ui-anr.png`. A usable accelerated emulator/device is required for the remaining Android checks.

Hosted target build/test evidence is linked in [current status](status.md#hosted-validation-and-publication). Distribution follows Flutter’s official [Linux bundle guidance](https://docs.flutter.dev/platform-integration/linux/building) and [Windows ZIP guidance](https://docs.flutter.dev/platform-integration/windows/building). Keep all bundle files together; system runtime dependencies are documented in the candidate notes.

Published v0.1.0-rc.1 was downloaded, checksum-verified and run as a native Linux binary. Visual checks showed ten loaded tasks, completion reducing the count to nine, and Undo restoring ten. Captured at 1280×900 under Xvfb/Openbox; screenshots are `linux-published-release.png`, `linux-published-complete.png`, and `linux-published-undo.png`. The public Windows ZIP passed CRC/checksum validation; the public Android APK passed signature/checksum/version/ABI inspection, without implying native execution. See current status for exact release/commit and startup metrics.

## Android rc1 device-worker evidence

The parent supplied successful native **rc1** evidence from an accelerated local Linux/KVM host: Android API 30, 720p, SwiftShader with Vulkan disabled, a 4 GiB/two-CPU container cap and 2 GiB guest RAM. Eight assertions covered capture/edit/complete/undo, SAF force-stop/reopen, external atomic-replacement ingestion and subsequent local writes; eleven unique canonical events were preserved. The emulator was stopped afterward and its video delivered through Library. These are rc1 observations, not coverage of the changed onboarding/theme/keyboard UI in the next candidate. Real phones, API 36 and the actual BasicSync provider remain unverified.

Future Android demo recordings should enable Show taps and visibly verify the touch indicators in the video. Desktop recordings should retain the pointer. Keep exact candidate/version, native platform, fixture, restart/provider actions and remaining gaps with each recording.

## User-reported rc1 cross-device observation

Lee reports users and tasks syncing between their devices and the UI updating promptly. An already-open user menu does not show a newly arrived user until reopened; retain selection stability and treat this as low-priority polish. This is user-reported real setup evidence, not an independently observed device/provider matrix or exhaustive BasicSync validation.
