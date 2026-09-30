# Current status — 2026-09-30

## Implemented locally

Flutter/Dart task slice: dedicated folder selection, user creation/selection, Inbox capture, title/notes editing, completion/targeted undo, periodic/resume ingestion, visible errors. Canonical JSONL logs plus private SQLite cache; desktop path adapter and Android SAF bridge. Public experimental prerelease preparation is authorized; stable release remains deferred.

Persistence tests cover restart/cache rebuild, shuffled delivery, conflicting fields, concurrent completions, interrupted append, malformed/unknown input, replaced/missing streams, missing dependencies and manifest identity. Independent review found and prompted fixes for concurrent commands, preappend validation, closing during I/O, deferred undo references, folder-bound undo and capture retry identity. See [runtime evidence](runtime-qa.md) for actual results; implementation does not imply target acceptance.

## Remaining acceptance gates

1. Native Android live SAF folder grants, restart, atomic replacement, permission revocation, and app workflow; then video. Real BasicSync/provider and phone-to-phone offline transport still require intended devices even if emulator succeeds.
2. Windows native build/run, folder/text/keyboard behavior and video on a Windows runner.
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
- Android SAF durability and grant/provider replacement behavior are unverified until live tests. Exit: runtime matrix below plus real-device provider test. No broad-storage permission workaround.
- No recurrence, dates, deletion, private spaces, games, food or LLM ingestion implemented. Their contracts stay separate from v1 tasks.

Latest checks: 23 domain/storage tests passed after three independent review rounds; static analysis clean; native Linux debug integration and release build passed. [Startup measurements](runtime-qa.md#recorded-release-measurements) now include a controlled minimal-app comparison and a verified D-Bus session fix: 2,000-task loaded-frame startup is 908–1,091 ms with emulator paused. Target-device performance is still pending. Final native Linux demo is recorded/reviewed. Video and emulator ANR evidence were delivered through Library; private artifact identifiers are excluded from the public repository.

Android universal debug APK build passed in 26.0 seconds (first complete build: 262.0 seconds) after adding the matching workspace JDK and resolving repositories. No native Android app/SAF run is claimed until emulator/device acceptance succeeds.

Concrete performance cleanup: capture retry existence checks now query the indexed entity ID instead of decoding all cached rows for every line. Startup profiling found no warm-start N+1 query. Full rebuild projects each touched entity; the measured 2,000-task import is 212 ms with a correct desktop session, so larger restructuring remains evidence-driven.

A final targeted review also fixed reopen behavior when all canonical files disappeared: a known cached workspace now fails before any new manifest is created. Regression covers no mutation plus identity/projection recovery after restoring originals.

API 30 completed boot but System UI repeatedly stopped responding before Tandemlog installation; package installation failed with a broken pipe. API 36 never completed usable boot. Both software emulators were stopped after bounded diagnosis. Native Android/SAF verification requires a usable accelerated emulator or device. See [release procedure](releases.md).
