# Bounded actual Linux GTK idle observation

The valid run is **run-04**, 2026-10-08 13:41:55–13:44:51 UTC. It did not
reproduce a stale visible task list. This is an instrumented Linux GTK debug
observation, not Windows reproduction or release acceptance.

| Condition | External write observation | Result |
|---|---|---|
| Focused, no input for 25 seconds | Verified new scalar v3 record, watcher → refresh → rows/view publication → build → actual title-render paint | New entity painted 368.050 ms after verified arrival; screenshot shows 2 tasks before input |
| Visible but another window focused, no input for 70 seconds | WM Normal, Flutter inactive, frames enabled; 5 existing fallback ticks during interval | New entity painted 348.941 ms after arrival; screenshot shows 3 tasks before input |
| Minimized for 35 seconds after arrival | WM Iconic/HIDDEN; Flutter hidden, frames disabled; importer stopped | Verified canonical record remained available; zero import/build/paint events before restore |
| Normal window restore, no mouseover | Existing lifecycle restart imports pending record | New entity painted 166.146 ms after restore action; screenshot shows 4 tasks |

The pointer stayed at screen coordinate 1390,890, outside the 1100×740 app
window at 20,20. The virtual display was 1400×900, theme dark. A separate
`xmessage` window held focus for the unfocused and minimized intervals. Window
activation/minimization/restoration are explicitly timestamped setup/lifecycle
actions; there were no task/editor inputs during the observation intervals.

[Structured result](result.json) binds exact entity IDs to paint markers and
records each stage's UTC timestamp. Raw [app trace](run-04/app-trace.jsonl),
[external writer/window trace](run-04/orchestrator.jsonl),
[process stdout](run-04/app-stdout.txt) and screenshots are retained. The actual
pixels of screenshots 01, 02, 04, 06 and 07 were viewed. Screenshot
[04](run-04/04-visible-unfocused-arrived-before-input.png) shows the unfocused
arrival; [07](run-04/07-restored-arrival-before-mouseover.png) shows the restored
arrival. PNG digests and pointer/window observations are in the raw trace and
result inventory. The synthetic canonical stream is retained under run-04/shared.

## Source and observation boundaries

The built source was main `0a16a88355823d74c98246ed55f1ce85e45428ab` plus the
[temporary observation patch](instrumentation.patch). The
[manifest](instrumentation-manifest.json) records patch/source SHA256, pinned
Flutter revision, exact built bundle file hashes and the executed runner digest.
Production files have been restored exactly to that base. The extra Dart probe
is preserved in instrumentation/idle_probe.dart, not enabled production source.
No production fix, dependency change or constant redraw/poll was added.

The probe records watcher hints, existing fallback/request/reconcile calls,
refresh start/end/changed, row IDs, lifecycle/frame availability, view revisions,
builds, one-shot post-frame callbacks and natural `RenderProxyBox.paint` calls.
Post-frame callbacks do not request a frame. The paint observer does not call
`markNeedsPaint`. Logging requires an explicit synthetic-only environment token
and a matching synthetic profile/trace directory inside this evidence root.
Only synthetic fixture data was used. Synchronous metadata I/O and render
observers affect timing; these numbers are diagnostic, not benchmark claims.

The normal compiled application ran as its own process. No WidgetsTester,
`tester.pump`, timer-generated input, forced frame, synthetic refresh request or
repeated mouse movement was used. The Python peer appended and fsynced real
canonical bytes, then verified their readable bytes/hash before observation.
Screenshots came from the actual X11 root via ImageMagick `import`.

## Replay and excluded setups

The exact run-04 script is preserved as run-04/executed-runner.py. The current
[runner](run_probe.py) performs the same phases with a fresh timestamped run
directory and refuses to reuse it. Apply instrumentation.patch to this exact
base in an isolated checkout, source /workspace/toolchains/env.sh, build Linux
debug, and launch the runner under `dbus-run-session`. Choose a free X display
(the recorded script uses :194). Do not reuse a profile/canonical stream from a
prior run. The [summary tool](summarize_probe.py) reads run-04 without app input.

Initial setup attempts are retained but excluded: run-01 contains the first
failed WM setup and an interrupted DBus retry with reused fixture roots;
run-03 hit a display-shutdown race. Their mixed/incomplete records cannot support
acceptance. The successful run uses a fresh profile, peer writer and X display.

This finite virtual-display debug probe does not establish all-night idleness,
physical display sleep/wake, a Windows GUI/backend, a signed release artifact,
real folder-provider delivery, or the cause of Lee's reported Windows behavior.
Direct Windows capture/diagnostics remain necessary before claiming a fix.
