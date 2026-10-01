# Current status — 2026-09-30

Current published preview: [v0.1.0-rc.2](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.2), Android build 5, source `d89a7d99fabecd27993e81707e98e7f0a3a8227c`. Public experimental prerelease, not Latest; stable remains deferred. Signed Android API 30 native smoke passed before publication. Historical development checkpoints below retain their original scope; final release verification is at the end.

## Active work — final tag filtering and long-list drag

**Publication remains gated:** owner feedback exposed functional due-bound tags and missing clock-driven visibility/sorting. Those behaviors are implemented, and the private actual-renderer comparison passed all 7,812 task/instant evaluations after normalizing Someday representation and intentional group-label presentation differences. See [time-driven view plan](time-driven-task-view.md). Earlier parsed-field rehearsals alone did not establish renderer parity.

Signed build 10, source `09bb3cf1cd7d9804a2fc7199b2349d80e29bae62`, passed [all hosted gates](https://github.com/reddraggone9/tandemlog/actions/runs/36790803679): Linux native workflows and release startup, Windows tests/native build, Android build and owner signing. Exact Android runtime acceptance is pending. This build predates the final constrained drag and permissive nonrecurring-scheduled warning; it is available for parallel timing/renderer QA, not publication.

Lee confirmed civil-day clamping that retains precise task times and constrained dragging within equal effective date/time, without a pure manual-sort view. Native Linux idle-boundary checks preserve drafts/editor and leave logs unchanged. Constrained drag, the advisory scheduled-date warning and session-only Show upcoming are integrated. Known obsolete caches now retain a private backup and rebuild from validated logs, preserving writer/space/stream guards; unknown future caches remain explicit errors. Final local formatting, analysis, 102 app tests and six release-gate tests pass. All 12 native Linux workflows pass (154 seconds), including the final drag/time/upcoming flow. The refreshed 90-second native Linux demo is reviewed. [Code-11 candidate gates](https://github.com/reddraggone9/tandemlog/actions/runs/36793617099) all pass for production source `4d255e2b06187d6d6ad383d9142bfb2b3454c6b4`; code-11 Android retained-cache upgrade and core interaction QA passed; picker-reopen automation remains separately limited. Code 12 closes the omitted ordinary-tag filter and adds drag edge auto-scroll. All 103 app tests, six release-gate tests and 13 native Linux workflows pass; both themes and enlarged-text layouts were inspected. [Code-12 candidate 36796794061](https://github.com/reddraggone9/tandemlog/actions/runs/36796794061) passed all platform/signing gates for source `bd02aa6fc58b6f82488cc0a005c989effa6d8c0c`; the exact signed code-12 APK is handed off. Lee subsequently requested a consolidated filter menu and top-bar identity; code 12 is intermediate. Code 13 consolidates filters and identity/settings; all 103 app tests, six gate tests and 14 native Linux workflows pass, with both-theme/narrow visual inspection and a reviewed focused demo. [Final code-13 candidate 36799901390](https://github.com/reddraggone9/tandemlog/actions/runs/36799901390) passed all platform/signing gates for source `f5f3d025841ae64da13af3ba3f615309e00221df`; its exact APK is handed off. Final affected Android regression remains required before publication.

Feature implementation is authorized and underway: dates/times, tags, manual order, observed recurrence and external dry-run migration. Includes the accepted local UI corrections and new application identifier. Protocol v2 deliberately requires a new workspace; Markdown remains authoritative throughout prereleases; all app tests use disposable copies, with final fresh migration coordinated before stable 0.1.0. No live migration or deletion has been authorized. See [ADR 0003](decisions/0003-task-parity-and-prerelease-boundary.md). The published rc.2 remains unchanged while candidate gates run.

Build 7 is superseded because it retained rejected source-format provenance; build 8 removed that provenance but still bundled one-off tools. Build 9 removes those tools and dedicated tests from the application repository and release assets. The private data-only rehearsal passed independently; Android build-7 synthetic UI evidence remains scoped to that build, and final exact-APK acceptance is still required.

## Current parity checkpoint

- Independently implemented recurrence matches 185 cases evaluated against pinned Obsidian Tasks 7.20.0 source, including all 37 observed forms. Schedule/zone/clock-helper tests pass.
- Native Linux parity scenario passed: invalid schedule preserves draft, corrected UTC schedule/tags save, manual move, recurring completion and history reopen preserve one successor. This is not Android coverage.
- The private data-only rehearsal passed independent semantic comparison for 217 tasks, production-store cache reopen, events-only export and canonical reimport. All 95 recurring tasks across 37 forms matched the pinned upstream oracle at three dates; completion retained history and created exactly one correctly ordered successor. Only 19 cosmetic lines differed, and private formatting guidance was delivered to Lee. This evidence applies to the tested snapshot, not the actively edited source indefinitely. Source and live destination remained untouched.
- Event-ordering correction is implemented: the original wall-clock/causal scalar replaces the inappropriate pure Lamport counter, with exact string serialization, explicit protocol separation and a nonblocking skew warning. Hosted integrated checks pass; exact-APK runtime acceptance remains pending.

The superseded build-8 candidate 36785084105 passed all hosted Linux, Windows, Android and owner-signing gates. After the tool-boundary cleanup, local analysis/formatting, all 71 generic app tests and six Python release-gate tests pass. The external private project retains 21 one-off tests and its actual-app source pin verifies. Independent boundary review found no remaining migration-only runtime/schema/CI coupling. The refreshed 65-second native Linux feature demo passed and was visually inspected; final build-9 platform gates remain pending. Generic app regressions remain in app CI; one-off migration tests are retained in the external private project. Native desktop and Android feature demos follow the delivered formatting guidance. No test-folder replacement or live cutover is authorized.

The first hosted candidate passed Android compilation but found two failures: a Windows test launched the Unix Dart wrapper, and enlarged-font Linux filter selection changed tab height. The launcher now uses the SDK executable; selection no longer adds a width-changing checkmark. Both fixes retain their regression checks. Signing/publication remain gated by a fresh successful matrix.

## Historical implementation checkpoints

The sections below record earlier slices and their original limitations. Current scope is governed by ADR 0003 and the active candidate gates above.

## Implemented

Flutter/Dart task slice: dedicated folder selection, user creation/selection, Inbox capture, title/notes editing, completion/targeted undo, periodic/resume ingestion, visible errors. Canonical JSONL logs plus private SQLite cache; desktop path adapter and Android SAF bridge. Public experimental prerelease preparation is authorized; stable release remains deferred.

Persistence tests cover restart/cache rebuild, shuffled delivery, conflicting fields, concurrent completions, interrupted append, malformed/unknown input, replaced/missing streams, missing dependencies and manifest identity. Independent review found and prompted fixes for concurrent commands, preappend validation, closing during I/O, deferred undo references, folder-bound undo and capture retry identity. See [runtime evidence](runtime-qa.md) for actual results; implementation does not imply target acceptance.

## Remaining acceptance gates

1. Broader Android real-phone/API 36/provider, permission-revocation and target startup acceptance. Native API 30 workflow, retained SAF/restart and replacement evidence now exists; real setup sync was also user-reported. Keep those specific results separate from exhaustive provider coverage.
2. Windows native launch and targeted packaging/path/dialog/startup checks; hosted native builds and domain/storage tests have passed. Linux is the primary routine desktop visual QA target.
3. Broader interrupted/error interaction and accessibility review before daily use. Persisted drafts and explicit recovery UI are not implemented.

## Commands in this environment

Toolchains and caches are isolated under `/workspace/toolchains`; source `/workspace/toolchains/env.sh`. Flutter 3.47.5 stable, Dart 3.13.4. Linux GTK/build dependencies are rootless Debian packages. Native display is Xvfb `:99` with Openbox.

```sh
flutter analyze
flutter test
DISPLAY=:99 flutter test integration_test/task_flow_test.dart -d linux
flutter build linux --release
DISPLAY=:99 NO_AT_BRIDGE=1 python3 tool/measure_startup.py
flutter build apk --debug
adb devices
adb shell getprop sys.boot_completed
```

Android SDK License Agreement accepted with Lee's explicit approval; no unrelated component terms accepted. Installed platforms 35/36, build-tools 36, CMake 3.22.1, NDK 28.2.13676358, emulator 37.1.11 and AOSP API 36 x86_64 image. Installation evidence is `/workspace/toolchains/sdk-acceptance.txt`.

Java requires proxy configuration here. Maven Central returns HTTP 429; workspace-only Gradle initialization tries Google's public Maven Central mirror, Google Maven and the official Gradle plugin portal. These environment accommodations are not repository-wide dependency changes.

## Architecture review and bounded debt

Owner: next implementation session, reviewed with Lee at M1 acceptance. Keep domain projection pure and adapters separate. Current compact store combines command orchestration and SQLite projection; extract a use-case layer only when a second domain or recovery workflow creates concrete pressure. No generalized event framework.

- Entire changed stream is read and prefix hashed; record sizes are validated after reading, but stream allocation is not bounded. Exit: add bounded/streaming reads and benchmark larger realistic histories before large-history mobile use. Android currently revalidates every poll because metadata reliability is unproven.
- All undo references are revalidated on ingestion. Exit: measure real histories, then index/restrict to newly resolved references without weakening correctness.
- Failed appends can be uncertain. In-session task capture retries retain identity, but drafts are not durable across termination. Exit: explicit recovery/draft UX before claiming interruption-safe drafts.
- rc1 SAF restart and atomic-replacement behavior passed on an accelerated API 30 emulator. Actual phone/BasicSync behavior and revised rc2 UI still need live checks. Exit: runtime matrix plus real-device provider test. No broad-storage permission workaround.
- No recurrence, dates, deletion, private spaces, games, food or LLM ingestion implemented. Their contracts stay separate from v1 tasks.

Latest checks: 23 domain/storage tests passed after three independent review rounds; static analysis clean; native Linux debug integration and release build passed. [Startup measurements](runtime-qa.md#recorded-release-measurements) now include a controlled minimal-app comparison and a verified D-Bus session fix: 2,000-task loaded-frame startup is 908–1,091 ms with emulator paused. Target-device performance is still pending. Final native Linux demo is recorded/reviewed. Video and emulator ANR evidence were delivered through Library; private artifact identifiers are excluded from the public repository.

Android universal debug APK build passed in 26.0 seconds (first complete build: 262.0 seconds) after adding the matching workspace JDK and resolving repositories. No native Android app/SAF run is claimed until emulator/device acceptance succeeds.

Concrete performance cleanup: capture retry existence checks now query the indexed entity ID instead of decoding all cached rows for every line. Startup profiling found no warm-start N+1 query. Full rebuild projects each touched entity; the measured 2,000-task import is 212 ms with a correct desktop session, so larger restructuring remains evidence-driven.

A final targeted review also fixed reopen behavior when all canonical files disappeared: a known cached workspace now fails before any new manifest is created. Regression covers no mutation plus identity/projection recovery after restoring originals.

API 30 completed boot but System UI repeatedly stopped responding before Tandemlog installation; package installation failed with a broken pipe. API 36 never completed usable boot. Both software emulators were stopped after bounded diagnosis. Native Android/SAF verification requires a usable accelerated emulator or device. See [release procedure](releases.md).

## Hosted validation and publication

[Full push CI](https://github.com/reddraggone9/tandemlog/actions/runs/36731215334) passed on all three targets: Linux format/analyze/integrity tests/native integration/release startup, Windows integrity tests/native release build, Android test APK build/signature verification. Final startup-gate strengthening separately requires a successful model-load marker, complete cached task projection and warm zero-log-read behavior. This gate is not visual QA.

[Candidate workflow](https://github.com/reddraggone9/tandemlog/actions/runs/36732068434) passed every gate and published [v0.1.0-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.1) from source `adacd395a19b94dbf4a2f00788e0ffd00a1497f0`. The tag resolves to that exact commit; GitHub confirms `prerelease=true`, `draft=false`, and the Latest endpoint returns 404 (no stable release). Normal main pushes and public experimental prereleases are approved; stable publication remains deferred.

Windows and Android CI artifacts uploaded successfully. This executor's direct download of temporary Actions artifact blobs returned HTTP 403; do not claim local inspection of those downloaded bundles. Release jobs perform their own checksum verification. Native Android/SAF and Windows interaction limits above remain in effect.

All three **public release** bundles were downloaded successfully and their SHA-256 checksums verified. Windows ZIP CRC integrity passed. Android APK signature verifies as Android Debug; version is `0.1.0-rc.1`, build 1, API 24 minimum/API 36 target, with `arm64-v8a`, `armeabi-v7a` and `x86_64`. Its SHA-256 is `c0aecfb70f54dadf36439e0168a83f64e87ccde8ee4ca888d61104750eec2ee7`. This does not establish Android runtime acceptance.

The downloaded Linux release ran locally under Xvfb, loaded all ten synthetic tasks and passed completion/undo visual inspection. Fresh/warm cache startup measured 781/705 ms locally and 371/314 ms on the hosted Linux runner; OS page caches were not flushed. Raw metrics and screenshots are in `evidence/startup-published-release-*` and `evidence/linux-published-*`. Earlier 2,000-task controlled measurements remain the larger workload evidence.

## rc2 revision in validation

Desktop explicit Start/default workspace, secondary chooser, inline first-user creation, locally persisted System/Light/Dark themes, compact task header, settings-only folder management and automatic foreground import are implemented. Desktop Enter/keypad Enter submits; Shift+Enter adds a task line. Android retains its SAF chooser and regular Enter newline. These are new rc2 behaviors, not claims about rc1. See [decision rationale](decisions/0002-onboarding-and-everyday-interface.md).

Static analysis and all 28 unit/integrity tests pass. All five native workflow tests pass, including 390-pixel/200% text-scale coverage. Native release visual and keyboard checks pass; the updated demo and Android candidate are in external QA. Independent review found and fixed uncertain-capture identity reuse, first-user retry selection, and keypad Enter handling; final read-only review found no remaining concrete data-loss/duplication issue. No canonical schema migration is required; legacy local settings default to System.

rc1 now has successful external native Android evidence; [runtime QA](runtime-qa.md#android-rc1-device-worker-evidence) distinguishes it from the earlier cloud emulator limitation and from untested rc2 UI.

## CI efficiency

Documentation/evidence-only main pushes skip platform builds; executable/tooling/workflow changes, all PRs/manual runs and every release candidate retain full checks. See [release policy](releases.md#documentation-only-pushes). The earlier doc-only run 36733292643 completed successfully after slow runner setup; no application change was needed.

## rc2 build 3 follow-up

Lee approved Open/Completed views with ordinary checked task rows; unchecking reopens. This is now implemented within the still-unpublished rc2, along with dark snackbar styling and removal of repeated Inbox badges. Build number advances from 2 to 3 to distinguish corrected APKs. The canonical event schema is unchanged. New targeted tests cover observed multiple completions, unseen concurrent completion, retry idempotence, restart and convergence. All 31 unit/integrity tests and five native workflows pass, including reopening and explicit 48×48 checkbox target assertions. Static analysis is clean. Final native release visual QA and all three hosted target gates passed for `20e4f3e5bb9032aed628ffee698fcc96c20bddca` ([CI](https://github.com/reddraggone9/tandemlog/actions/runs/36752532225)). The final Android build-3 APK has now been admitted to the accelerated device worker after earlier dispatch timeouts. Application source is frozen at `20e4f3e`; publication is on hold until that regression result arrives. The prematurely started candidate run 36753099020 was canceled before publication; the separate full CI above remains green. Stable remains deferred.

Future Inbox grouping/detail-based departure remains deferred; current stored state is retained and hidden. See [product behavior](product-behavior.md#completed-tasks-and-capture-grouping).


## rc2 build 4 — settings correction

Application source `434771783eeba45499c30179b46794931bd3f342`, version `0.1.0-rc.2+4`, replaces the awkward segmented appearance control with a Theme/current-value row and standard radio choices. Description previews are one ellipsized line with whitespace normalized for display; titles and stored notes remain complete. No persistence/schema change.

Analyzer, all 31 unit/integrity tests and five native workflows pass locally. Linux release and x86_64 Android debug builds passed. The corrected APK and a 20-second native Linux settings/notes demo were delivered through Library. [Hosted build-4 validation](https://github.com/reddraggone9/tandemlog/actions/runs/36755315998) completed successfully on Linux, Windows and Android. Android build-3 validation is separate; build 4 needs the focused settings/notes recheck. Publication remains held pending that result and the signing decision in [release guidance](releases.md#android-signing-continuity-and-owner-handoff).


## Owner-signed candidate setup

Lee authorized key generation/storage on Farnsworth with owner-only GitHub secret provisioning. Cloud changes prepare build 5 (UI unchanged from build 4), a fail-closed Gradle release-signing configuration, public signer pin and a staged candidate/publication workflow. The exact signed APK must be installed/tested before its hash is accepted for publication; no rebuild after acceptance. Debug QA stays independent. See [owner handoff and gates](releases.md#android-signing-continuity-and-owner-handoff). No private key/password is generated or transmitted by this cloud worker.

Validation of signing preparation: six release-gate tests and actionlint pass; an actual local `flutter build apk --release` fails with the explicit missing-signing error, while the subsequent x86_64 debug build succeeds without secrets. Independent review found no remaining blocking defect. Successful owner-signed build/certificate verification and native install/upgrade remain pending owner provisioning; these checks are not claimed from negative-path tests.


Owner key generation is confirmed on Farnsworth (RSA 3072, PKCS12, alias `tandemlog-release`); only its public certificate SHA-256 is pinned here: `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`. Secret provisioning remains owner-pending. Android worker reports build-4 debug QA passed for settings/radio themes, one-line multiline-note previews, 130% text, capture/completion/Undo/reopen, persisted SAF access and external updates. Local debug build 3→4 upgraded successfully with the same cloud certificate; this does not establish public rc1 compatibility. Final owner-signed build-5 installation/launch smoke remains required.

[Signing-preparation CI](https://github.com/reddraggone9/tandemlog/actions/runs/36759005277) passed all Linux, Windows and Android jobs at `aa323d068c80085cc2c902680bd89be2f9c66c3a`, including six release-gate tests, domain/integrity tests and native Linux workflows. Android here is the secret-free debug validation build; this does not claim the pending owner-signed APK has been built or installed.


## Owner-signed candidate ready for native smoke

[Signed candidate run 36762053783](https://github.com/reddraggone9/tandemlog/actions/runs/36762053783) completed successfully from source `d89a7d99fabecd27993e81707e98e7f0a3a8227c`. All platform gates and the owner-signing job passed. The integration cannot list repository secret metadata (HTTP 403); the required-input checks and successful signing establish that all four owner inputs were supplied and usable, without the cloud agent reading their values.

The `android-release` artifact (ID `11118684574`) was downloaded through the supported GitHub connector, ZIP-CRC checked, and independently verified locally. APK SHA-256: `cd392117b91c8db8193fa164a45600032d6f6de055066f757aeb8cb8777be046`; owner certificate matches the pinned fingerprint, package `dev.tandemlog.tandemlog`, version `0.1.0-rc.2`, code 5, non-debuggable, API 24 minimum/API 36 target, ARMv7/arm64/x86_64. The exact artifact ZIP was delivered through Library for native installation/launch smoke. No public rc2 release has been created.

After successful native acceptance, publish from this candidate run using the exact APK SHA above. Do not rebuild or substitute another artifact. Preserve the external canonical folder across the required debug-to-owner-signature reinstall transition.


## Verified rc2 publication

[Publication run 36764934306](https://github.com/reddraggone9/tandemlog/actions/runs/36764934306) passed and published [v0.1.0-rc.2](https://github.com/reddraggone9/tandemlog/releases/tag/v0.1.0-rc.2) from candidate `36762053783` without rebuilding. Tag resolves to `d89a7d99fabecd27993e81707e98e7f0a3a8227c`; release is public, `prerelease=true`, and not Latest (Latest API returns 404; no stable release). rc1 is preserved.

All nine public assets were downloaded and compared with GitHub's SHA-256 digests; all three bundle checksum files match. Public Android APK is byte-identical to the native-accepted candidate and passes signer/version/non-debuggable/ABI checks. Windows ZIP CRC passed; no interactive Windows runtime claim is made. Downloaded Linux native release startup passed with ten synthetic tasks: 959 ms cache rebuild / 678 ms warm to loaded-frame marker, with complete cached rows and zero warm log reads. OS page caches were not flushed; this is a release-download smoke, not target cold-boot/input-latency acceptance. Evidence: `evidence/rc2-public-download-verification.json`, `evidence/startup-published-rc2.json`.

## Rc3 build-7 candidate handoff

[Candidate 36781661950](https://github.com/reddraggone9/tandemlog/actions/runs/36781661950) passed Linux, Windows, Android and owner-signing gates at source `46bcb5a981cd7c8d751a187dd463b898c316835f`. Downloaded archives/checksums passed; the exact hosted Linux bundle launched locally and its compiled migration tool passed byte-exact synthetic smoke. Signed APK SHA-256: `199da11842204cd0dcc9f4bb3abe006c64f03a3e40ec60dcad21961bccc6c340`, version 0.1.0-rc.3/code 7, package com.reddraggone9.tandemlog, non-debuggable and matching the pinned owner certificate. It was handed to the device worker through Library; no rc3 publication or live migration has occurred.
