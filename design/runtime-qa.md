# Runtime and visual QA — updated 2026-10-01

## Actual environment and target matrix

| Target | Verified evidence | Remaining limit |
| --- | --- | --- |
| Linux native | Flutter GTK app built in debug/release, launched under Xvfb/Openbox; actual folder picker, capture/edit/completion shown; native integration flow passed restart, undo and unsupported-record recovery | Linux is the accepted primary desktop visual QA target, not proof of Windows-specific behavior. Software display/container performance does not predict phones. |
| Android build | RC4 code 22 universal owner-signed, nondebuggable APK independently verified; hosted target/build/signing gates passed | Compilation and signing do not establish revised native UI or SAF acceptance. |
| Android runtime | RC3 code 17 passed exact native API 30 workflow/SAF/idle/drag/search acceptance on accelerated Farnsworth; see evidence below | Exact RC4 code 22 acceptance pending. Broader real-phone/API 36/provider and permission-revocation evidence remain separate. Cloud software emulation is unusable. |
| Windows | RC4 code 22 hosted native build/tests plus per-user install, visible launch, replacement, uninstall/data preservation and reinstall passed | Full manual UI/folder-dialog/scaling and prerequisite-missing clean-machine acceptance remain unperformed. Linux is the routine desktop visual QA target. |
| Web | Not used for app acceptance | A browser preview would not validate Android or Windows. |

The [Android emulator acceleration guide](https://developer.android.com/studio/run/emulator-acceleration) describes KVM requirements. Here `emulator -accel-check` reports KVM requires vmx/svm; `/dev/kvm` is absent. Software emulation was actually attempted, not dismissed from this probe alone.

## Historical first-slice Linux workflow evidence

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

## rc2 local release validation

Implementation commit `45d0b1c8f4616a7a0460a3ba61038a689c5a1a9a`: clean analyzer, 28 unit/integrity tests and five native Linux integration workflows passed. The native suite includes 390-pixel width and 200% text scaling for the list and settings. Manual release inspection covered actual desktop Enter/Shift+Enter/keypad Enter, inline setup, light/dark and narrow layout. See the [task-based UX audit](ux-audit-rc2.md).

Two fresh Linux release processes with 2,000 tasks measured **979 ms cache rebuild / 740 ms warm cache** to the loaded-frame marker; first-frame markers were 589/496 ms externally. Warm cache read zero canonical log files. `evidence/startup-rc2.json` contains raw phases. OS page cache was not flushed; no emulator/build was active, but an idle native demo window was open. Methodology/limits above still apply.

The rc2 native Linux walkthrough is time-compressed (23 seconds), shows five captures, inline setup, theme change, completion and settings, and overlays the measured pointer location because the reconnected display did not support normal shared-memory recording. It is not timing evidence. Open data folder was separately confirmed to launch Thunar at the actual canonical location.

The final responsive correction at `106f90aaf3671cee798d5e055ff98bfe7ebfca10` rebuilt successfully for Linux release and Android x86_64 debug. The native suite passed again; the revised narrow Settings layout was visually inspected. Screenshots are `evidence/linux-rc2-*`. The initial hosted failure exposed real large-text overflow; it was fixed rather than relaxing the assertion.

[Corrected rc2 full CI](https://github.com/reddraggone9/tandemlog/actions/runs/36746991732) passed Linux native integration/release startup, Windows native build/tests, and Android build/signature verification for implementation `106f90a`. This resolves the large-text failure in the preceding run. Device-worker acceptance of this corrected APK is still tracked separately.

## rc2 build 3

Implementation `0d66917402c2647c3badab9a50b75161b3e8716a`, version `0.1.0-rc.2+3`: 31 unit/integrity tests and five native workflows pass, including persistent Completed browsing/unchecking and 48×48 hit targets. Independent persistence review requested two additional reopen boundary tests (arrival between snapshot and refresh; partial durable undo then retry); both pass. Linux release and Android x86_64 debug builds succeeded. The APK was signature/version-verified and handed off separately for device regression.

Native release visual inspection confirms compact rows, full long-title wrapping, dark snackbar contrast and checked Completed rows. The [UX audit](ux-audit-rc2.md#measured-native-linux-comparison) records measured density and exact limits. Android build 3 regression and its phone/video evidence remain pending: the accelerated worker dispatch hit approval-service timeouts before task admission. This is not an application failure or a new user-approval requirement.

Final build-3 implementation `20e4f3e5bb9032aed628ffee698fcc96c20bddca` clears the stale Undo snackbar after reopening. The native regression and release walkthrough verify that change. [Final full CI](https://github.com/reddraggone9/tandemlog/actions/runs/36752532225) passed on Linux, Windows and Android. The final independent UX review found no concrete regression in the native Linux screenshots/walkthrough; Android-specific runtime evidence remains pending as stated above.


### Final build-3 startup sample

Frozen app source `20e4f3e` was measured in five fresh native Linux release processes, with 2,000 synthetic tasks, explicit session bus, Xvfb/software graphics and no emulator/build or demo app running. Launch to loaded-frame marker: **1,880 ms cache rebuild; 978 / 844 / 801 / 860 ms warm cache**. External first-frame times were **1,328 / 757 / 683 / 589 / 629 ms**. The rebuild reached Dart main at 987 ms, then reported 246 ms ingestion and 8 ms total query/decode/sort; warm runs read zero canonical log contents. The complete cached task count was asserted on every run. Raw data: `evidence/startup-rc2-build3.json`.

A subsequent three-process minimal Flutter release comparison in the same display/session measured **474 / 428 / 379 ms** to its first frame, with Dart main at **365 / 319 / 291 ms** (`evidence/startup-minimal-rc2-build3.json`). Retain the slower rebuild sample rather than replacing it with earlier favorable timings. Its longer pre-Dart interval does not establish an application regression or prove an environmental cause. These are sequential samples, not controlled target-device acceptance.

The benchmark resets only its isolated local cache before run 1; OS page caches are not flushed. The loaded post-frame marker approximates task-ready startup, not physical presentation or a measured first successful input. Internal phase timers exclude engine startup; first frame can precede task readiness. Windows and Android startup acceptance remain separate.

The final Android build-3 worker was subsequently admitted successfully; its current regression result is pending. Publication is held for that result, with no speculative app changes during the freeze.


### Build 4 validation delta

`434771783eeba45499c30179b46794931bd3f342` passes analyzer, 31 tests and five native workflows locally. Linux release and Android x86_64 debug builds passed; Android versionName `0.1.0-rc.2`, code 4, APK SHA-256 `1223efd0091faf41ad15c5bf0d7592673971f1fb46e1b1033abab777152519a0`. The APK uses the existing cloud debug certificate, matching local build 3 but differing from public rc1. No new signing identity was generated. The [UX audit](ux-audit-rc2.md#build-4-settings-and-notes-preview) distinguishes native release screenshots from the temporary 200% text harness. Android settings/notes recheck is pending; do not carry forward build-3 UI evidence as if it covered this delta.


### External Android build-4 result

The parent reports native accelerated Android QA passed for source `434771783eeba45499c30179b46794931bd3f342`, debug version `0.1.0-rc.2+4`: final settings/radio choice, full multiline editor notes versus one-line preview, 130% font scaling, capture/completion/Undo/checked-row reopening, persisted SAF grants and external updates. Public rc1 was preserved; the local build 3→4 upgrade succeeded because those cloud APKs share a certificate, distinct from public rc1. Touch-video verification was still finishing when this result was recorded. This is worker-supplied evidence, not a cloud emulator run. The code-5 owner-signed release APK needs a separate installed smoke test because build mode and signer differ; domain/UI source is unchanged from tested build 4.


### Owner-signed build-5 artifact verification

Candidate run `36762053783` at source `d89a7d99fabecd27993e81707e98e7f0a3a8227c` passed the full platform matrix and owner-signing gate. Independent downloaded-archive CRC, APK checksum, apksigner, aapt package/version/non-debuggable/ABI and source-metadata checks passed. APK SHA-256 is `cd392117b91c8db8193fa164a45600032d6f6de055066f757aeb8cb8777be046`, certificate SHA-256 is `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`. This confirms build/signing integrity; native install/launch smoke of this exact release APK remains pending the device worker. Earlier build-4 debug QA is separate evidence.


### Signed native acceptance and public release

The device worker reports PASS for the exact owner-signed APK SHA-256 `cd392117b91c8db8193fa164a45600032d6f6de055066f757aeb8cb8777be046` on KVM Android 11/API 30: launch, SAF access to copied canonical history, retained users/tasks/notes, capture/completion/checked-row reopening and process restart; fourteen unique events and four UI states checked. No OOM; services were stopped and rc1/debug AVDs preserved. This acceptance preceded publication and was supplied by the parent; evidence ZIP was delivered through Library.

Published rc2 preserves that exact APK, and public-download checks additionally passed for its signature/version/checksum, all asset SHA-256 values, Windows archive CRC and native Linux release startup. See [final publication status](status.md#verified-rc2-publication). Real phones/API 36/provider matrix and interactive Windows acceptance remain broader gates; no stable release was published.

## Local next-candidate onboarding spacing (2026-09-30)

Unreleased local correction after rc2: wrapping primary/secondary actions with 12-pixel horizontal/vertical gaps, standard label typography, 48-pixel minimum targets and scrollable welcome content. Actual native Linux debug inspection covered 1000×760 at normal text, 320×820 at normal text and 390×820 at 200% text. Screenshots were visually inspected: desktop actions share a row, narrow/enlarged actions stack, labels remain readable and no overflow exception occurred. The first native assertion exposed desktop visual density shrinking a requested 48-pixel minimum to 40; explicit standard density corrected it. The rerun verified both target heights, spacing and no canonical `data/` folder before Start. Temporary visual harness/screenshots are local toolchain artifacts, not shipped app code.

This is Linux evidence, not Android or Windows runtime acceptance. Android verification and refreshed platform demos remain part of the next coherent candidate, not a separate release for this adjustment.

### Local capture caret regression

Reproduced the reported Shift+Enter bug in the native Linux app before fixing it: with four existing lines, the caret bottom reached 120 pixels in a 96-pixel editable viewport and remained clipped after layout settled. The fix calls `EditableTextState.userUpdateTextEditingValue` with the keyboard cause and explicit collapsed selection, preserving Flutter's post-layout reveal behavior. A first attempted generic replacement action preserved a selected range; the final method preserves the original shortcut's collapsed-caret behavior instead.

The permanent regression in `integration_test/task_flow_test.dart` checks visibility before any further input after three successive Shift+Enter presses, multiline clipboard paste, middle selected-text replacement and active composition preservation, at normal and 200% text. Native screenshots at both scales were inspected and show the caret on the final blank line inside the field. No general controller listener or refresh-driven scroll was introduced. These are local Linux debug results, not a new published candidate or Android validation.

Validation for these local corrections: `flutter analyze` passed; 31 unit/storage tests passed; the final native `task_flow_test.dart` run passed all six scenarios (53 seconds), including the added caret regression. `git diff --check` passed. Temporary screenshot capture code was removed before the final integration run.

### Local stable header regression

The next-candidate header uses a viewport/text-scale breakpoint and reserves both actual count-label layouts, preventing Open/Completed text changes from moving the controls. Native Linux inspection uses a sanitized long username, 1,000 open tasks versus one completed task, widths 1000/390/320 at normal text and 390 at 200% text (820-pixel height). The check compares exact user-selector, Everyone-filter and tab-bar rectangles across both tabs. Screenshots are inspected separately: equal rectangles alone would not catch clipped names. Inspection exposed Chip's inherited one-line text restriction and its avatar growing with multiline label height; the label now wraps and the icon keeps an explicit 18-pixel box. Android runtime validation remains pending with the next candidate.

### Local settings paragraph/action inspection

Actual native Linux debug screenshots at 1000×820, 390×820 and 390×820 with 200% text were inspected. The single paragraph is readable, desktop actions share a row with a gap, narrow actions wrap with a gap, and the enlarged dialog scrolls to both actions without overflow. The native visual harness passed action-spacing and single-paragraph assertions; temporary screenshot code remains outside the repository.

Final local batch validation after the header/settings corrections: static analysis passed and all seven native Linux integration scenarios passed in 102 seconds, including the 1,001-task header fixture. The permanent header regression uses Flutter test view sizing; separate native window resizing/screenshots supplied the visual evidence above. `git diff --check` passed. No candidate was published and no Android runtime claim is made for this batch.

## rc3 integrated local validation

Final local static analysis passed; all 83 unit/domain/storage/migration tests and six release-gate Python tests passed. The complete native Linux integration file passed nine scenarios in 116 seconds, including precise start/scheduled/due times, zone selection, invalid-date draft preservation, tags, manual movement, successor placement after a move, history reopening and nonblocking future-clock capture. The 185 pinned upstream recurrence comparisons are part of the schedule tests, not 185 separately reported test functions.

Native visual inspection covered 1000×820 and 390×820, light/dark, 100%/200% text (56 frames across eight combinations), plus the future-clock warning at desktop/narrow/enlarged sizes. Six captures with the warning visible persisted through reopen. The demo caught a genuine successor-ordering defect; chronological order projection and late-arrival/cache-rebuild regressions fixed it before the final native run. See [task-based UX findings](ux-audit-rc3.md).

The compiled external migration CLI passed byte-exact synthetic reconstruction. A separate bundled oracle from official Obsidian Tasks 7.20.0 matched 99 synthetic recurring rows covering 37 forms at three completion dates, including DST/leap-day dates. These are not claims about the private source. Private-source rehearsal and exact signed Android candidate acceptance remain pending; source text is never a public fixture or release asset.

Release-mode startup measurements and hosted candidate results will be recorded separately. No native Windows or Android rc3 result is inferred from Linux or compilation.

### Completion metadata and standalone production-store audit

Actual private rehearsal exposed a missing completion-action parser case; no source or live destination was changed. The corrected adapter preserves source flags, deliberately retains all app history, and reports any authorized Markdown export normalization separately from byte equality. The fresh source inventory is checked privately, never hardcoded from an earlier snapshot.

The integrated local suite passes 89 tests and clean analysis. Five audit tests cover read-only canonical access, output containment and failure integrity. A relocated Linux bundle containing only its executable and bundled SQLite library ran with an empty environment: production TaskStore loaded canonical events, reopened identical cached rows with zero log reads, and verified unchanged canonical hashes. This is actual storage evidence, not Android/UI acceptance. Independent read-only review confirmed the completion adapter and audit guard fixes without finding further defects.

### Rc3 native release startup samples

After the completion-metadata/storage-audit changes (storage source `794ad22`) and the first header checkmark correction, native Linux release process launch to loaded-frame measured **996 ms** for a 2,000-task cache rebuild and **706 / 622 / 729 / 1,448 ms** for warm cache. External first-frame times were **548 / 508 / 473 / 564 / 1,049 ms**. A subsequent ten-task set measured **1,198 ms** rebuild and **1,402 / 1,239 / 759 / 1,156 ms** warm; first frames **1,033 / 1,120 / 1,066 / 607 / 973 ms**. All warm runs read zero log contents, and every projected task count was asserted. Raw samples: `evidence/startup-rc3-2000.json` and `evidence/startup-rc3-10.json`.

Method: five fresh processes per workload, native release, Xvfb/software graphics and explicit session D-Bus; no local emulator, recording or native build/test running. Only the isolated first-run SQLite cache was removed; OS page caches were not flushed. These are loaded post-frame markers, not physical presentation or measured first successful input. Small-workload timings are not consistently faster, so these variable sequential VM samples cannot isolate workload cost or establish target-device performance. The subsequent narrow large-text tab orientation change is outside this measured binary; hosted final-source startup remains a candidate check.

### Build 7 final local native regression

Source `46bcb5a981cd7c8d751a187dd463b898c316835f` passed all nine native Linux scenarios in 111 seconds, including the final measured-width filter layout, all optional times, manual order, recurrence/history and nonblocking future-clock warning. The six-width/text-scale filter test checks both toggle directions and verifies each label remains a single rendered line. Actual native screenshots at 350px/200% and 390px/250% confirm the vertical fallback; ordinary widths remain horizontal. Analyzer, formatting, 89 Dart tests and six Python tests pass. Hosted platform and exact signed Android results remain separate gates.

### Independent private-source rehearsal acceptance

The local worker, reported through the parent, passed the corrected tooling at source `794ad226337a39d8852f79a47a6c793b473b19c0`: 217 tasks (210 open, seven completed) matched independently for order, titles/opaque links, tags, completion, schedules, precision and floating times. All 95 recurrence rows across 37 forms matched pinned upstream Obsidian Tasks at 2026-09-30, 2027-03-14 and 2028-02-29, including relative offsets and configured scheduled-date removal.

Production TaskStore/SQLite import and unchanged cache reopen passed with zero reopen log reads and unchanged canonical hashes. Canonical-only export reconstructed byte-identical Markdown with the source unavailable; provenance is in import.document events, with no external sidecar. Same-timestamp fresh-staging retries were identical, and existing-staging overwrite was refused without changes. All 95 source delete flags remain Markdown provenance while app behavior keeps history; zero export normalization was needed. Both original source copies remained unchanged. Private source text, hashes and detailed reports are not published here.

This verifies unchanged-import fidelity, not edited-task Markdown export. Build-7 source has identical domain/storage/schema code to the audited tool revision; only UI, QA tooling and documentation differ. Matching Android UI acceptance and explicit live-destination approval remain separate.

### Data-only replacement after owner review

The owner rejected canonical formatting provenance after build 7. Its publication is canceled; prior source-map rehearsal results remain historical only. The replacement removes import-only records/references, uses shared actual projection/order for canonical Markdown, and fails explicitly on values the source syntax cannot represent. Cache format 6 prevents older cached provenance or invalid UUID namespaces bypassing wire validation.

The data-only storage change passed all nine local native workflows (115 seconds). Focused tests cover valid deterministic UUIDv5 import identities, strict reference completeness, unsafe output containment, edited-state export and projected completion dates. A compiled importer created a fresh synthetic recurring task, then the standalone production-store audit completed that imported task in a separate copied workspace: one successor, correct dates/order, identical cache reopen with zero log reads, and unchanged original canonical hashes. This exercises actual UUID-based successor generation rather than recurrence-date prediction alone. The new private source formatting diff and semantic acceptance remain pending.

## Renderer semantics correction — release still blocked

The initial field/recurrence rehearsal did not cover the adjacent renderer’s functional due-bound tags, visibility and ordering. It is superseded as evidence of full workflow parity. The new standalone private oracle adapter uses the application’s shared task timing evaluator, checks a copied source hash and transient line mapping, and separates date/order/visibility from intentional group-label presentation differences. No source mapping is persisted in app events.

Native Linux idle-boundary regression passed: future-start tasks appeared without an edit/import, capture focus/selection/draft and an open notes editor survived, and canonical JSONL remained byte-identical. Invalid bounds produced no write; valid typed bounds preserved the stored deadline. Eight viewport/theme/text-scale visual configurations passed; screenshots remain outside the repository. Linux’s foreground timerfd count decreased by one on disposal, confirming observer cleanup; this is not a test that changes the host clock. Actual Android/Windows system-change delivery remains pending.

A separate Dart JIT microbenchmark with 2,000 synthetic timed/bounded tasks measured pure projection at 225 ms on the first invocation (including initialization) and 39–42 ms on three subsequent invocations. This is not an AOT startup or end-to-end UI latency measurement. Final candidate startup/device checks remain required after behavior and private renderer acceptance.

### Build 10 renderer acceptance checkpoint

The independent private actual-renderer comparison passed all 7,812 task/instant evaluations. Someday representation (null versus legacy sentinel) and group-label wording/countdown were normalized as intentional differences; availability, effective dates, bounds and ordering had zero unexpected differences. This applies to the audited snapshot, not future edits automatically.

[Candidate run 36790803679](https://github.com/reddraggone9/tandemlog/actions/runs/36790803679), source `09bb3cf1cd7d9804a2fc7199b2349d80e29bae62`, passed Linux native workflows/release startup, Windows tests/native compilation, Android compilation and owner signing. The readiness marker now waits for successful time projection and the loaded task frame; a delayed-zone native regression prevents early readiness claims. Build 10 is available for exact Android testing but predates the final drag/warning changes. Compilation does not establish native Windows or Android runtime acceptance.

### Build 10 native Android timing evidence

The authorized local worker reported successful build-10 native Android tests for idle start-time appearance with capture draft preservation; intraday ordering of precise and bounded times; midnight bound advancement retaining task time/draft; floating visibility after Los Angeles/Chicago zone changes and resume; and multiline keyboard behavior. Canonical hashes were unchanged for view-only clock/zone operations. These are build-10 results, before drag/Show upcoming and the cache recovery fix.

A retained build-7 fixture exposed a cache-version-4 versus current-version-7 opening failure. Both the fixture and cache were preserved for exact code-11 upgrade testing. Build 10 had a tag editor but no tag-filter UI; its native evidence does not establish filter behavior.

### Code 11 final local acceptance

Formatting and analysis pass, with 102 generic app tests and six release-gate tests. All 12 native Linux workflows pass in 154 seconds on the final production source. The drag scenario covers hidden global order, rejected different-time destinations, stale view cancellation, and a wall-clock advance without a timer callback; the guarded append rejects the expired bucket. Show upcoming preserves capture text, permits editing a future task and resets off after restart. Nonrecurring scheduled values warn and save without loss.

Known obsolete cache regressions preserve writer identity, a readable old SQLite snapshot, workspace binding and committed-stream checks through failed replay/retry. Unknown future cache versions and incompatible canonical records remain explicit failures. Exact Android retained-cache upgrade remains a separate gate.

### Code 11 native release startup samples

Source `4d255e2b06187d6d6ad383d9142bfb2b3454c6b4`, locally compiled native Linux release, measured external process-launch to loaded-frame at **1,570 ms** for a fresh 2,000-task cache rebuild and **819 / 983 / 853 / 954 ms** warm. Corresponding first-frame times were **980 / 620 / 773 / 634 / 714 ms**. Ten tasks measured **860 ms** rebuild and **818 / 771 / 884 / 840 ms** warm, with first frames **686 / 658 / 613 / 654 / 665 ms**. Every warm run read zero log contents and asserted the complete workload in SQLite. Raw samples: `evidence/startup-rc3-code11-2000.json` and `evidence/startup-rc3-code11-10.json`.

Method: five sequential fresh processes per workload, prepared selected-folder profile, isolated fresh cache on the first run, native AOT release under Xvfb/software graphics with an explicit D-Bus session. No emulator, recording or build/test ran concurrently; OS page caches were not flushed. The loaded-frame marker follows successful time projection and post-frame rendering, not a physical presentation or first successful input measurement. Cache-hit correctness is demonstrated separately by zero content reads; these VM samples do not establish target-phone performance or a cold OS launch.

The refreshed 90-second native Linux demonstration shows accepted and rejected drag targets, timed groups/bounds, Show upcoming, recurrence/history and both themes, with visible pointer. It uses sanitized fixtures and an explicitly controlled advancing UTC view clock in an instrumented debug build; actual native Android clock/lifecycle results remain separately scoped.

### Code 11 hosted candidate and artifact handoff

[Signed candidate 36793617099](https://github.com/reddraggone9/tandemlog/actions/runs/36793617099) passed all platform gates for source `4d255e2b06187d6d6ad383d9142bfb2b3454c6b4`. Android version `0.1.0-rc.3`, code 11, is nondebuggable and includes arm64-v8a, armeabi-v7a and x86_64. Its owner certificate matches the pinned fingerprint. Exact APK SHA256: `957bcb065c7d7dbfcf2351fd691994fcc23045c73c58b9c50abfddbe7bbfc74c`. Retained-cache upgrade and the final drag/upcoming/lifecycle checks are handed to the native Android worker; no release is published from compilation alone.

The Windows unsigned x64 ZIP hash is `ffbecd2a2a91f3af17fcc1e2637e3121636785f0f94dffb823681b3ceecd3ed9`; Linux x64 tar.gz is `241755e0899b49f8b45ebb6dff9c1a64680059ed497d3cab5b924fd063c5c2b7`. Hosted Linux startup smoke measured 427 ms rebuild and 322 ms warm for its ten-task workload, with zero warm log reads. These hosted values are separate samples from the local software-graphics VM measurements above. Subsequent documentation-only commits do not change the accepted production/artifact source.

### Code 12 tag and long-list drag acceptance

Formatting and analysis are clean. All 103 generic app tests, six release-gate tests and 13 native Linux workflows pass (176 seconds). The new flow combines exact-tag filtering with user/Everyone, Open/Completed and Show upcoming, preserves capture drafts, clears the tag explicitly and resets on restart. A stationary edge drag reaches an initially unmounted peer and preserves the relative global ranks of hidden tagged tasks and completed history. Canceling over a valid target writes no move. Existing cross-bucket/time/concurrent-change guards still pass.

Native screenshots at 1000px/100% and 390px/200%, Light/Dark, show a bounded tag label and reachable clear action. The reviewed 90-second Linux demo shows tag selection/reset and earlier task/drag/theme flows; its recording ends before the long-list edge segment, which has separate native regression evidence. The demo uses sanitized fixtures and an explicitly controlled advancing UTC clock in a native debug build. Exact code-12 Android affected regression remains required; these Linux results do not establish touch behavior.

### Code 11 native Android core acceptance

The local worker reported exact signed-APK/certificate verification and successful retained schema-4 to schema-7 cache recovery: the archived cache was retained and canonical bytes plus writer identity were unchanged. Valid handle dragging, rejected cross-date drops without an event, absent handles across different times, hidden manual ranks, upcoming edit/default/reset, scheduled warnings, intraday ordering and cold persistence passed. The reviewed touch-visible demo accompanies this evidence. Picker-reopen automation remained blocked; retained-grant testing used an already-authorized profile. This is code-11 API-30 evidence, before code-12 tag filtering and edge scrolling.

### Code 12 hosted candidate handoff

[Candidate 36796794061](https://github.com/reddraggone9/tandemlog/actions/runs/36796794061) and push CI 36796787111 passed for source `bd02aa6fc58b6f82488cc0a005c989effa6d8c0c`. All target checks/builds and owner signing are green. Android is nondebuggable, version `0.1.0-rc.3`, code 12, package `com.reddraggone9.tandemlog`, with ARM and x86_64 support. The pinned owner certificate is verified; APK SHA256 is `3c4be43dfd40aada0f18b77521bec7c24ae0b67f106074ded11ff3d50f490d9b`. Its exact signed package is handed to local Android affected regression; no public release is authorized by compilation alone.

Linux x64 tar.gz SHA256: `9824da968773e83b4fe4b0c988c4ddfca53297f879326d83e74b6773a8b633a8`. Windows unsigned ZIP SHA256: `22764af605ac9c66b6cf37950e2e53b67129f13edd87faf4678e4d40a7b3ce32`. Hosted Linux ten-task release startup measured 471 ms rebuild and 438 ms warm, zero warm log contents; OS page caches were retained. The earlier methodology and limitations still apply. Documentation-only follow-ups do not change the accepted production/artifact source.

### Code 13 consolidated header acceptance

Formatting and analysis pass, with 103 generic app tests, six release-gate tests and all 14 native Linux workflows passing (209 seconds). The new flow verifies filter composition, reopen/reset, real Tab/arrow navigation and Escape, retained capture text/selection, active-identity separation and Settings access. Existing six-size header geometry, stationary edge-scroll, stale/cross-bucket/time guards, lifecycle and domain workflows still pass.

Final desktop/narrow screenshots cover both themes and 100%/200% text; the task-based audit records same-fixture density measurements. The reviewed 90-second native Linux debug demo shows the new menu/reset, identity/Settings, both themes and stationary edge movement within the recording. Sanitized fixtures and a controlled advancing UTC view clock are explicit; this is not Android or physical-device performance evidence. Code 12 remains an intermediate candidate. Final code-13 platform/signing and exact Android menu/header acceptance remain required before publication.

### Code 13 signed candidate handoff

[Candidate 36799901390](https://github.com/reddraggone9/tandemlog/actions/runs/36799901390) and push CI 36799892529 passed for production source `f5f3d025841ae64da13af3ba3f615309e00221df`. All platform gates and owner signing are green. The exact nondebuggable APK is version `0.1.0-rc.3`, code 13, with the pinned owner certificate and phone ARM/emulator x86_64 support. SHA256: `edf56111b8d66343f939571bc41f9e8e4fb6e42395800a1a9541b6abf18bcfcf`. It is handed to native Android menu/header regression; publication remains held for that result.

Linux tar.gz SHA256: `1215813eb879abaaf376d3beb3827c21285e1b904b21f3d37d8a46e19deb9c1c`. Windows unsigned ZIP SHA256: `2fd33dc7cd359bc5b4aaf86ae2bedf2ac73792c1506ac45854cdafccff522969`. Hosted ten-task Linux startup measured 469 ms rebuild and 367 ms warm, with zero warm log contents and retained OS page caches. These samples follow the documented loaded-frame methodology; they do not establish target-phone or physical-presentation latency. Subsequent documentation-only commits do not change artifact source.

### Code 13 Android affected acceptance

The local worker verified the exact signed APK/certificate and passed combined filters, reset/indicator, dismiss/reopen, identity versus assignee, Settings and narrow 150% text scaling. Stationary edge-scroll automation held the handle tooltip instead of initiating a drag; that result is inconclusive, not a verified application defect. Code 14 removes the handle's touch-long-press tooltip recognizer while retaining mouse-hover help and its accessibility label. A native Linux touch regression holds 700 ms before moving and then verifies stationary edge scrolling, cancellation and preserved hidden ranks. Exact Android touch regression remains required on the replacement candidate.

### Code 14 native review and aggregate checks

Formatting and analysis are clean; all 103 generic app tests, six release-gate tests and 15 native Linux workflows pass (227 seconds). The added workflow covers a 100-tag inventory, bounded lazy results, case-insensitive search with exact-case selection, empty results, selected-tag clear/reopen/reset, adjacent wide metadata and narrow 100%/200% layouts. Existing composition, keyboard, drag/hidden-rank/concurrency guards, cache recovery, time transitions and draft-preservation tests remain green.

Forty-two sanitized native screenshots cover Light/Dark at 1000px and 390px, including 200% text, full pinned deadlines, long tags, bare tasks and one-line description previews. The reviewed focused 30.5-second native Linux debug demo shows picker search/clear/reset and wide metadata with a visible pointer. Early screenshots and the demo were delivered before the full platform build, allowing user feedback in parallel with validation. Exact signed Android replacement checks remain pending; no new runtime or performance claims follow from these Linux visuals.

### Code 15 group-date presenter

All 108 app tests and six release-gate tests pass, including five presenter cases for same/different/bounded dates, exact times, pinned zones, Someday and empty separators. The final affected native Linux metadata/picker workflow passes (9 seconds), explicitly covering a differing bounded start date. The retained-view timezone-reload regression also passed during this refinement; the final presenter has no live timezone reads or timezone-resolution machinery.

Light/dark 1000px/390px and 200% screenshots were inspected. Lee's final rule is times/roles/zones only in day-group rows, with all full dates in the editor; the earlier differing-date exception was superseded before publication. Early reviewed screenshots were delivered before rebuilding. Source/task facts and storage formats are unchanged. Final candidate CI runs the full platform matrix and native Linux suite; exact revised Android acceptance remains required.

### Code 16 localized list times

Formatting/analysis are clean, all 111 app tests and six release-gate tests pass. Eight presenter regressions verify pinned-to-local midnight rollover, zone changes, DST gaps/folds shared with production projection, bound consistency, unchanged source maps, floating times and date-only precision. Two affected native Linux workflows pass (10 seconds), including retained rendering during a timezone reload. Both-theme wide/narrow and 200% screenshots were inspected; a reviewed 12-second native debug clip with visible cursor was delivered before the final build. Original editor dates/zones and canonical data are unchanged. Full final hosted gates and exact Android affected acceptance remain required.

The first code-16 candidate passed Windows/Android but correctly blocked signing when one native Linux test still expected the removed `09:30 UTC` list suffix. The assertion now requires `Start 09:30` and no suffix, while the existing canonical-zone/time assertions remain. The complete affected native dates/recurrence/history flow passes (17 seconds). Application behavior was unchanged by this test correction; the full candidate gates rerun on the corrected source.

### Code 17 workspace search — checks in progress

All 113 app tests and six release-gate tests pass, with clean formatting and analysis. The pure view search checks trim/case-insensitive title and description matching, retained future availability, assignee/tag bypass and empty-query restoration. The focused native Linux search workflow passed in 11 seconds: hidden/title/description matches, restored filters, drafts, incoming updates on resume, same-key drag, cross-completion rejection and checked-history reopening. Wide/narrow 200% screenshots were inspected. The changed occurrence/date/zone/tags/recurring-history scenario also passed (16 seconds). Code 16's final hosted matrix/signing passed at run 36807290597; it is superseded, not published. No build-17 Android runtime acceptance is claimed yet.

### Published RC3 exact-artifact acceptance — 2026-10-01

Source `8ca015fa10cdfc17a1a84e55685c1fb00d2f5c3e`; candidate [36809817199](https://github.com/reddraggone9/tandemlog/actions/runs/36809817199) and push CI 36809817060 passed all targets. The exact owner-signed nondebuggable Android APK, code 17, passed native Android 11/API 30 acceptance: title/description search across hidden categories and filter restoration/live updates; bounded tag picker; responsive layouts; occurrence label; natural time transitions/draft preservation; restart; hidden-rank constrained dragging; actual stationary edge scrolling; rejected drops with no events. Active touches were verified in demo Library `libfile_96544bdb91248191981a26be26194d2c`. Local services stopped and guest state restored; real source/data untouched. This does not establish real-phone/API 36/provider-specific coverage.

APK SHA256 `fa3f5758c3b54567587f788827d5a694952b23c0721fa5de28c905ed0577315f`; public certificate SHA256 `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`. Windows unsigned bundle SHA256 `9f8ec5a062b935b9097bfefe0440703551f9a8739d3fd66ce46cf4c451f57a1b`; Linux bundle SHA256 `c6e187da756e4bfe497bb2b391714021a66d11cac1e89519f1444eb04e83a7a1`. Windows hosted builds/tests and archive checks passed, not full manual Windows UI acceptance.

Publication [36812834339](https://github.com/reddraggone9/tandemlog/actions/runs/36812834339) reused those artifacts without rebuilding, creating [v0.1.0-rc.3](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.3) with prerelease=true and latest=false. Public unauthenticated downloads of all nine assets matched GitHub digests and accompanying checksums. The downloaded APK signature/package/version/nondebuggable flags, Windows ZIP and Linux tar integrity passed. Tag points to the tested source; Latest endpoint returned404 (no stable release). Release notes disclose identifier/protocol break, canonical backups/reselection, and runtime limits. No migration tooling or private source content is bundled.

Native release Linux/Xvfb startup, 10 tasks, OS page cache not flushed: external loaded-task marker439ms with rebuilt cache and396ms warm; external first-frame264/265ms; app loaded markers263/221ms; warm read zero log contents. These process-launch observations are not physical-display or OS cold-boot timing. Method and complete measurements accompany `linux-startup.json`. Reviewed native Linux debug search demo is Library `libfile_ed918c8cdf5c81918f597466be0e92ab`, version10; synthetic fixtures, visible pointer. Stable0.1.0 and coordinated live migration remain unapproved.

### RC4 build 22 exact candidate handoff

Source `a742f3325dce0b8d2340ba893ab4ea58e3cef0b6`, version `0.1.0-rc.4+22`. [Full CI 36885633090](https://github.com/reddraggone9/tandemlog/actions/runs/36885633090) and [signed candidate 36885656212](https://github.com/reddraggone9/tandemlog/actions/runs/36885656212) passed all target gates. Formatting/analysis, all 141 application tests, 12 packaging/release tests and the complete native Linux workflow suite are green. Six focused local native flows include selected-block edge scrolling/cancellation, mixed search-section range selection, dirty Save/Discard/Cancel, checkbox keyboard isolation and dropdown repositioning after metrics change. The final native visual flow passed in 77 seconds with 24 sanitized Light/Dark/desktop/narrow/200% screenshots. Lee accepted the reviewed 22.5-second pointer-visible native Linux debug preview. Simulated keyboard insets are Linux geometry coverage, not Android keyboard evidence.

Downloaded candidate ZIP CRC/digests, every bundle checksum and Android signer/metadata passed independent verification. APK SHA256: `349b817861246a878f2154ec23b58dd0b721daebf55b3447bda9ebdc4d764313`; pinned owner certificate `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`; package `com.reddraggone9.tandemlog`, nondebuggable code 22, ARMv7/arm64/x86_64. Native Android acceptance subsequently failed the keyboard-open tag-picker flow; this candidate is superseded and must not publish. RC3 evidence is not claimed for these changed flows.

Linux Flatpak SHA256: `f353f3cd5e56b3208c343df1f160732bd99a956e2e52ea14b4bb9008136e845d`. All installed lifecycle phases passed with verified exact-instance cleanup. Replacement uses a private metadata-only baseline with identical payload/permissions and a distinct OSTree commit, then restores the untouched candidate; it proves package replacement, not previous-version application compatibility. Windows unsigned installer SHA256: `099c5cfa1843f93b27f2c370f262f2636be63d4db4919874d8340aa91802b680`. Its four hosted native lifecycle phases passed with payload/shortcut, visible-window/projection and preserved-profile/canonical checks. Manual Windows UX, missing-runtime clean-machine behavior and cloud Flatpak runtime remain explicitly unverified.

Hosted native Linux **release**, ten synthetic tasks, two fresh processes: external launch→loaded-task frame **571 ms cache rebuild / 417 ms warm**; external first framework frame **348 / 296 ms**; launch→Dart main **259 / 200 ms**; internal loaded markers **308 / 213 ms**. Warm log-content reads were zero (rebuild one). OS page caches were not flushed. These markers distinguish complete model/cache behavior from engine initialization; they do not measure physical presentation, first accepted input, cold OS/device boot or phone performance. The original `linux-startup.json` asset contains a D-Bus log preamble before the intact JSON; independent parsing preserved the original artifact. Strict report-output cleanup is bounded CI debt in [status](status.md#architecture-review-and-bounded-debt), not an application failure or a reason to rebuild the native-acceptance candidate.

### RC4 build 23 picker regression

The device worker verified build-22 signing/upgrade and retained synthetic data, then reproduced no reachable tag suggestion with the keyboard open on Android 11/API 30, 540×960 pixels at density 240. Remaining selection/bulk/tablet checks and the final Android demo were not completed; the emulator was stopped. That failed acceptance overrides green hosted gates and Lee's desktop-preview acceptance.

An added native Linux regression exposed a control-tap race: the query's outside-tap handling dismissed the dropdown before the same tap activated its collapse/expand control. The entire picker now belongs to the text field tap region. Regression requires successful collapse/reopen, retained query focus, actual hit-testable matching/no-match output, popup height at least 48 logical pixels, keyboard-safe bounds, stable dialog rectangles and successful tag selection at 360×640/1.5 density with a 280-logical-pixel simulated IME inset. Three affected native workflows passed in 60 seconds, covering compound filters/selection/bulk/drafts and the earlier bounded picker/200% scenario. All 141 generic app tests, 12 Python gates, formatting and analysis pass. Ten both-theme native Linux screenshots were inspected; these use overridden phone metrics and simulated insets under Xvfb, not a real Android keyboard. No storage/protocol/cache meaning changes. New full hosted build/signing gates and exact build-23 native Android acceptance remain required.

The new [signed candidate 36897516356](https://github.com/reddraggone9/tandemlog/actions/runs/36897516356) and [push CI 36897514952](https://github.com/reddraggone9/tandemlog/actions/runs/36897514952) passed all platform gates at source `b9e445da917e58fef18f4e8fe45607eda4eab090`. Exact owner-signed APK `1c1eefd969e73a95a2266821320bc788474e0bdf36455ed3d48f6cf1f92ede32`, code 23, independently verified and handed off; native Android tag acceptance passed but the editor keyboard gate failed, so this candidate is superseded. Linux Flatpak `7f1bbd369993b023021e0751b74d5e4accef902352e5900a75aefc65458757cd` and unsigned Windows setup `ecebf2c3c9aa1955afbf78ba115e03cff9fa4d427436f1c8ae8fd030e9958dfe` passed archive/checksum and all four installed lifecycle checks. [Derived verification evidence](../evidence/rc4-build23-candidate-verification.json) preserves the original startup-report hash and declares its D-Bus preamble extraction; candidate assets are unchanged.

Hosted ten-task native Linux release startup: **432 ms rebuild / 367 ms warm** external launch→loaded-frame marker; first frame **284 / 238 ms**, Dart main **213 / 167 ms**, internal ready **215 / 197 ms**. Warm log reads zero; two fresh processes, OS page caches retained. Physical presentation, first input, cold OS boot and phone latency remain unmeasured. The refreshed 11.5-second native Linux debug clip has visible pointer input and simulated IME insets; the broader previously accepted desktop design preview remains historical evidence, not Android acceptance.

### RC4 build 24 editor correction — acceptance pending

Native API 30 build 23 passed tag keyboard/results, selection, Save/Discard/Cancel and bulk clearing tests, then failed both editor form visibility with the keyboard open at 540×960/density 240. No publication of that candidate is authorized. An actual-app Linux debug regression with the matching phone metrics, status/navigation padding and simulated 280px logical keyboard reproduced the 8px scroll viewport. The correction prevents double IME subtraction and scrolls the modal heading with the form; wide panel scrolling remains separate. Tests require a usable scroll viewport, focused caret inside it/above the IME through repeated open/close, both single/bulk at 100/130/200% text, and unchanged canonical files after focus-only cancellation. Linux simulated metrics remain geometry evidence, not native Android acceptance.

Local build-24 results: focused actual-app geometry/caret/canonical-invariance regression **39 seconds, pass**; both-theme visual flow **96 seconds, pass**, 24 inspected synthetic screenshots. Normal, 130% and 200% text use the same 540×960 physical/1.5 density, 24px logical status/navigation padding and 280px logical IME. Modal title/form share the scroll region, so heading may scroll out while an offscreen field is focused; actions remain available. All **142** application unit tests, **18** editor cases and **12** Python packaging/release cases pass, analysis/format clean. Hosted full suite and exact new Android runtime acceptance remain pending.

Exact build-24 [candidate 36906871648](https://github.com/reddraggone9/tandemlog/actions/runs/36906871648) and [CI 36906794308](https://github.com/reddraggone9/tandemlog/actions/runs/36906794308) passed all targets at `ded2eebc10eb1670658995cbc0c06b4676a5c583`. Signed APK SHA256 `eaf16ed555acc6bef637542133d907a7ee349434657cf6c7f64a7e5cdff57bda`, code 24, approved owner signer/nondebuggable/three ABIs; exact native Android acceptance remains pending. Linux Flatpak `f9c4f883b596498a650d35be892e14e29a97038d19622b6d37ff856dae487ec9` and unsigned Windows setup `b7fab39b4eb98565f31d42f13706c6c2b1eb9ddd3687f9bbe9dd19122f37f875` passed independent downloaded digest/CRC/checksum and all four installed lifecycle phases. [Evidence](../evidence/rc4-build24-candidate-verification.json).

Hosted ten-task native Linux release, two fresh processes: external launch→loaded-frame marker **507 ms rebuild / 391 ms warm**; first framework frame **307 / 258 ms**; launch→Dart main **217 / 168 ms**; internal ready **287 / 220 ms**. Warm log-content reads zero; OS page caches retained. Physical presentation, first accepted input, cold OS boot and phone latency are unmeasured. Original startup asset retains its known daemon/portal/PipeWire preamble; derived strict JSON extraction matches the reviewed prior preamble aside from numeric process/timing values, and preserves the original hash. No candidate assets were modified.

The reviewed 28.23-second native Linux debug regression clip has visible pointer input and a permanent explicit simulated-phone/IME caption. It shows single/bulk field focus and scrolling, not Android runtime behavior or startup timing. Temporary capture harness is outside tracked source. Exact Android build-24 test and updated device demo remain required before publication.
