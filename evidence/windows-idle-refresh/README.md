# Windows idle update investigation

Status: bounded Linux GTK observation complete, 2026-10-08; Windows cause is
not established. Lee observed stale content two or three times first thing in
the morning after overnight idle, clearing on mouseover. Normal time-based
updates occur while he uses the computer without interacting with Tandemlog.
Remote changes may be irrelevant; a start-time crossing is a hypothesis, and
sleep or display-off has not been confirmed. The separately reviewed
[actual GTK probe](native/README.md) used synthetic data and temporary metadata
observers in a normal compiled process, then restored all production source.
No production fix, live data access, dependency upgrade or new polling was added.

## Source bindings and observations

The isolated branch is `investigate/windows-idle-refresh`. Compared source:

| Source | Exact commit |
| --- | --- |
| Stable `v2026.10.1` (peeled) | `da4859ea82f8b066ed701740c57cb9bcff1083ff` |
| Main at investigation start | `0a16a88355823d74c98246ed55f1ce85e45428ab` |
| Frozen queued application | `a960c882c06c018a1e721e7459f08dbe4d17bed3` |

[source-bindings.json](source-bindings.json) records Git blob identities. The
foreground importer, local folder adapter, view clock, time source and three
Windows runner files are byte-identical across all three sources. The setup
Flutter action is also identical: Flutter 3.47.5, framework source
`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`. These source bindings do not identify
the binary installed on Lee's Windows machine; that remains to be recorded.

The relevant `lib/main.dart` paths are unchanged between stable and main (their
only main.dart difference is the Settings version tile). Queued source adds
native receipt/capture reconciliation, but retains the watcher, lifecycle and
refresh scheduling discussed here.

- `lib/platform/foreground_importer.dart:8-79` uses filesystem notifications with
  a 250 ms debounce and a 15 second foreground reconciliation fallback. It
  retries failed watchers and coalesces requests while reconciliation is running.
  The fallback reconciles metadata; it does not unconditionally redraw the UI.
- `lib/main.dart:889-912` attaches `Directory(folder.location).watch()` for local
  Windows folders. The directory is not watched recursively; canonical logs are
  direct children. Provider transport runs outside this application.
- `lib/main.dart:915-960` skips reconciliation while unmounted, hidden, without
  a store, busy, or already syncing. An admitted change publishes `origin.rows`
  inside `setState`, then invalidates the timed projection. Exceptions publish a
  read error. The periodic fallback and action completion requests normally
  recover skipped requests; actual stuck busy/syncing state is not demonstrated.
- `lib/main.dart:963-977` treats both `resumed` and `inactive` as foreground.
  Hidden/minimized states stop imports and time observations. Returning to a
  visible state restarts the importer with an immediate request; `resumed` also
  explicitly requests reconciliation. Simply losing input focus while remaining
  visible does not stop this app's importer.
- `lib/storage/log_folder.dart:54-73` lists current local file size and timestamp
  observations. Store ingestion validates canonical records and projects new
  events. Equal-size/unchanged observations and incomplete suffixes require
  separate diagnosis from file transport arrival; a complete appended remote
  completion normally changes length. Metadata alone is not proof of content.
- `lib/presentation/view_clock.dart:57-107` projects on invalidation, upcoming
  schedule boundaries or detected time/zone jumps. Its one-minute watchdog does
  not project on every ordinary wake. `ViewTimeSource` has a separate one-minute
  zone fallback and Windows native time-change notifications. Neither is the
  remote log transport.
- `lib/main.dart:700-702` reacts to Flutter focus changes with `setState`, without
  directly reading logs. The main task `MouseRegion` has a cursor but no explicit
  hover/import callback. `windows/runner/flutter_window.cpp:88` forwards Windows
  messages to Flutter; its `ForceRedraw` is startup-only. Pointer-triggered
  repaint is plausible, but is not evidence that import already completed.

Existing `test/foreground_importer_test.dart` verifies debounce, fallback,
stop/dispose, watcher recovery and overlapping work using fake time. Those tests
were inspected, not rerun here. They cannot establish native Windows idle
event-loop, display presentation or provider delivery behavior. A widget test or
GTK flow that pumps frames cannot settle the reported symptom either.

## Official Flutter evidence and limits

Flutter documents visible desktop windows without input focus as `inactive`,
and minimized or nonvisible desktop windows as `hidden`.
[AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html).
The scheduler enables frames for resumed/inactive and disables them for
hidden/paused/detached, matching the installed pinned framework source inspected
at `packages/flutter/lib/src/scheduler/binding.dart:414-427`.
[Lifecycle scheduler implementation](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/handleAppLifecycleStateChanged.html).

`setState` schedules a build; normal `scheduleFrame` waits for the engine/OS
frame opportunity, which can be delayed while the display is off. It also
coalesces an already scheduled frame and respects `framesEnabled`.
[setState](https://api.flutter.dev/flutter/widgets/State/setState.html),
[scheduleFrame](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/scheduleFrame.html).
These contracts support recording import completion and frame completion
separately. They do not justify a perpetual redraw loop or forcing hidden frames.

Official Flutter issue [175135](https://github.com/flutter/flutter/issues/175135)
reported mouse-sensitive Windows animation frame rates on Flutter 3.35 and is
marked fixed. Issue [178916](https://github.com/flutter/flutter/issues/178916)
describes a later Windows frame-rate regression and a thread-policy workaround.
Neither report establishes hours-stale task state on Tandemlog's pinned Flutter
3.47.5. No engine attribution, thread-policy change, toolkit upgrade or
workaround is recommended from these symptom similarities.

## Narrow native reproduction plan

Use a disposable synthetic space and private preferences/cache roots, with the
exact Windows executable/archive hash and framework/engine source recorded.
Never test against a live synced folder. First use a second synthetic writer to
produce a valid completion locally, avoiding the provider. Then repeat with the
actual provider connected only to a synthetic test folder if separately allowed.

1. Establish a normal visible, focused, stationary-pointer control. Append the
   complete valid peer record after the initial loaded frame and wait at least
   two existing fallback periods without input. Record the change before moving
   the pointer. Do not call test `pump`, force a frame, animate a heartbeat or
   inject mouse input during the observation interval.
2. Repeat visible but unfocused; minimized then restored; display off then on;
   and lock/unlock or sleep/resume as distinct cases. A long stationary visible
   idle interval approximates the reported hours-long case. Record Windows
   build, power mode, screen state, GPU/driver, monitor refresh configuration and
   remote-session use rather than assuming they are interchangeable.
3. In a separately reviewed diagnostic build, add bounded event-triggered
   receipts only: monotonic and wall timestamps for local file arrival/watcher
   hints, existing fallback wake, lifecycle state, import request/skip reason,
   refresh start/end and changed/event-count outcome, row/view revision, frame
   scheduled status and completed frame timing. Record anonymous synthetic
   operation IDs or counters, not task contents. A one-shot post-frame receipt
   observes the next natural frame; it must not itself schedule one. Do not
   replace Flutter's engine callbacks or resolve the symptom with diagnostic
   timers before measuring it. Temporary Linux instrumentation is preserved in
   [the probe patch](native/instrumentation.patch); Windows capture is pending.
4. Capture the actual desktop pixels before any pointer movement, then move the
   pointer once and capture again. Treat screenshots/presentation and Dart
   build/frame receipts as separate evidence: a completed framework frame alone
   does not prove that Windows presented the updated pixels. Record whether the
   first input caused file arrival, lifecycle transition, reconciliation, build,
   rasterization or only presentation.

Interpretation determines the smallest fix:

| Last stage completed before first input | Next investigation |
| --- | --- |
| Peer wrote, but complete bytes absent locally | Folder provider arrival, placeholders and conflict copies; no repaint fix |
| Bytes present, no watcher/fallback execution | Lifecycle, watcher attachment or event-loop wake; no faster polling by default |
| Request runs but refresh skipped/stalled/errors | Busy/sync state, store admission and error recovery |
| Refresh and row/view revision advance, no natural frame | Framework/engine frame scheduling with exact state and source |
| Frame completes but desktop pixels remain stale | Windows presentation/GPU/display recovery |

An event-driven fix can be selected only after locating the failing boundary.
Candidates include recovering an actually missed visibility/watcher event or
making one bounded invalidation after a proven reconciliation/resume edge. An
extra frame request already coalesces with a pending request and may not repair
an engine presentation failure. Preserve current low-compute behavior, canonical
admission and foreground policy; do not add aggressive polling, hidden-state
imports, forced-frame loops or generic idle animations.

## Remaining blockers

The [distinct clock-boundary GTK probe](native/clock-README.md) also completed
without reproducing staleness. It used preloaded synthetic tasks and unchanged
canonical data. A scheduled task painted while visible and unfocused, and a
second painted after explicit restoration. These finite virtual-display cases
do not exercise an overnight Windows session or physical monitor transitions.

This Linux executor has no native Windows session. Hosted Windows compilation,
startup/installer checks and tests that explicitly pump frames do not reproduce
the hours-idle workflow. Lee's installed build/provider/power/visibility details
and an input-free native receipt are not yet available. Cause and any production
fix remain pending; the queued candidate and shared tag feature are unchanged.
