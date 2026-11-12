# Runtime and visual QA

How native QA is done and what counts as evidence. The per-build log of every
earlier run is in [archive/runtime-qa-history.md](archive/runtime-qa-history.md);
each release's actual results are in its `evidence/` receipt. The rules on when
to run QA (UX pass, review captures) are in [AGENTS.md](../AGENTS.md).

## What counts as native evidence

- The actual app on the actual platform. A browser at phone width is not
  Android, Linux desktop is not Windows, and a Linux build, cross-compile or Wine
  run is not Windows verification.
- Widget/component captures are labelled as widget captures, not platform evidence.
- Candidate acceptance uses the exact signed candidate artifacts, not a rebuild;
  upgrades are tested from the previous release on retained synthetic labs.
- Synthetic data in isolated profiles and workspaces only; never the live
  household workspace. Detailed media stays private; commit sanitized receipts
  under `evidence/`.
- Unrun or failed checks stay listed as pending or failed; a pass on one source
  or build is not claimed for another.

## Environments

- **Linux (primary desktop visual target):** native GTK app under Xvfb with
  `xvfb-run -a dbus-run-session`, private runtime/profile dirs; release
  acceptance uses the installed Flatpak bundle in an isolated lab.
- **Android:** hardware-accelerated API 30 x86_64 emulator on the engineering host for
  candidate acceptance and retained upgrade labs. Cloud software emulation is
  unusable. RC owner testing uses the side-by-side install on Lee's phone or Leela
  described in [releases.md](releases.md#6-hand-the-rc-to-lee);
  it does not replace exact-artifact lab acceptance.
- **Windows:** hosted CI builds and unit tests, installer lifecycle (install,
  launch, replace, uninstall with data kept, reinstall) and payload inventory.
  No routine manual GUI session.
- **Web:** not used for app acceptance.

Coverage not yet done: real-phone/API 36/provider sync, permission revocation,
Android hardware Ctrl/Shift, Windows manual folder dialog/scaling and a
prerequisite-missing clean machine.

## Capture

- Review screenshots use the production theme from
  `lib/presentation/tandemlog_theme.dart` (`tandemlogTheme(Brightness)`).
  Component-only capture harnesses must use it too; a bare `ThemeData` uses
  Flutter's default purple palette, not Tandemlog. `captureUx` checks theme parity
  even when PNG output is disabled.
- UX review set (see AGENTS.md): dark and light, wide and 390 px, 200% text.
- Videos show inputs (desktop pointer; Android Show taps) and label the
  actual OS/device and build; verify the inputs appear in the recording.

## Desktop verification split

Linux is the primary desktop visual QA target and ships an x64 bundle. Routine shared UI changes require native Linux visual inspection. Windows retains hosted native builds and targeted packaging, Unicode/path, folder-dialog and startup smoke checks; a full emulated Windows session is not required for every shared UI change. Android still needs independent native visual, lifecycle and SAF tests.

## Windows verification path

On Windows with official Flutter and Visual Studio's Desktop development with C++ workload: `flutter doctor -v`, `flutter pub get`, `flutter analyze`, `flutter test`, `flutter test integration_test/task_flow_test.dart -d windows`, `flutter build windows --release`. Run the generated executable; test native folder picker, keyboard/focus, scaling, Unicode paths, restart, read-only/missing folder and two local profiles exchanging logs. Record an actual Windows video. Do not label a Linux build, cross-compilation, or Wine run as native Windows verification.

## Android SAF acceptance script

1. Install native APK; choose a dedicated tree using Android DocumentsUI; create user/task.
2. Force-stop/relaunch and reboot; verify retained URI permission, task and write ability.
3. Replace a remote writer file atomically through the actual sync provider, then refresh/resume; verify enumeration reopens the new document and imports once.
4. Revoke the grant/remove the folder; verify visible failure, no false save acknowledgment and no history overwrite; regrant/recover.
5. Two intended phones: initialize one space, transport manifest, join second; edit offline, exchange logs with BasicSync and another compatible provider where available; check convergence and no-internet hotspot behavior.
6. Record Android API/device/provider versions and actual demo. Emulator directory grants alone cannot establish BasicSync/phone provider behavior.

Android uses [SAF tree/document URIs and persisted grants](https://developer.android.com/training/data-storage/shared/documents-files), not ordinary filesystem paths. SQLite remains private.

## Harness notes

- On a desktop host that someone is logged in to, give the native Linux session
  its own runtime directory: export a private `XDG_RUNTIME_DIR` **before**
  `dbus-run-session` and set `GTK_USE_PORTAL=0`. Otherwise the private bus
  activates a document portal on the real session's runtime directory, and
  teardown unmounts it and kills that user's portal (seen 2026-10-26).

- Linux integration tests and the Linux release build must run one after the
  other in a checkout: they share `linux/flutter/ephemeral`.
- Unit and native workflow tests need `TANDEMLOG_TEXT_LIBRARY` pointing at a
  library built by `tool/build_text_engine.py` (commands in [status.md](status.md#commands)).
- `tool/measure_startup.py` launches separate native Linux **release** processes
  against synthetic tasks (default 2,000 tasks, 5 runs). Run 1 rebuilds the
  SQLite cache; later runs reuse it; OS page caches are not flushed. Its markers
  end at a post-frame callback, not physical presentation or input-ready time.
- Native cold start to the first usable list is gated by
  `tool/performance/native_cold_start.py` (1,000 ms median, mixed Task and Food
  histories); boundaries in [performance-gate.md](performance-gate.md).
- Normal-close disposal on Linux is checked by `tool/verify_linux_disposal.py`:
  renderers must never finalize before their engine, and a normal close exits 0.
