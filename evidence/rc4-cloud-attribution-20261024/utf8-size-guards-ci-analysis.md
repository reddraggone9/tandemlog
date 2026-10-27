# UTF-8 repair exact-source CI and next review point

Snapshot: 2026-10-25 05:27 UTC. Product source
`6e400f7a69e3b4f48ec0c87266c30d3c4a5068e6` is pushed; later commits change
handoff/evidence and the literal-byte attribute for the archived stack only.
Cloud remains sole product writer. No ownership transfer or release.

[CI 40164354926](https://github.com/reddraggone9/tandemlog/actions/runs/40164354926)
is terminal, overall failure, updated 05:24:31 UTC. Exactly one dispatch, with
`calibrate_performance=false`, after the previous same-branch run was terminal.
The initial list lagged accepted dispatch; it was checked without redispatch.

| Job | Result | Qualification |
| --- | --- | --- |
| Windows | PASS | Full workflow, including unit/build/native payload and installer lifecycle. No Leela foreground or hardware timing acceptance. |
| Android | PASS | Exact-source build/payload gate. Archive digest/APK checksum independently checked; cloud performs no installation. |
| Linux | FAIL | All 1,515 units, format/analysis/tooling/build/payload checks pass; normal close SIGSEGV blocks warm startup and downstream native workflows. |
| Performance | FAIL | Strict existing limits/resources; all three shapes/232 correctness metrics pass, timings fail, zero retries. |

## Performance failure retained

[Full enforcing summaries, samples, misses, pins and artifact receipt](utf8-size-guards-enforcing-performance.json):
179 absolute metric failures (13 exceed a median bound; all 179 exceed a maximum
bound). There are 105 paired failures: 12 exceed median-growth bounds and 103
exceed maximum-growth bounds, with overlap. These are counts across shapes/pairs,
not unique action IDs. Base/Task-growth/Food-growth absolute counts are 54/61/64;
paired Task/Food counts are 57/48. All correctness/coverage checks pass.

The gate records no eligible further retry. Its final `allPinsMatch` and
`measurementCompleted` flags are unset because timing failure exits before those
assignments. Independently inspected direct source hashes all match the 118
committed/current source files; do not replace the unset flags with invented
success flags. Native/SQLite/SDK hashes and the unchanged limits digest are
retained. Resource bounds are 6 GiB, no swap, two CPU and 128 tasks. The local
measure-only run used different caps and native-library bytes.

This runner reports EPYC 9V74, versus the prior enforcing e23 EPYC 7763. Base
Title Save/Undo/completion medians are 25.107/22.763/13.519 ms, but maximum Title
Save is 94.231 ms; Task-growth Title Save maximum is 230.358 ms. These are not a
controlled before/after comparison and establish neither a whole-action speedup
nor regression caused by the helper.

Unmodified selected raw samples illustrate the remaining attribution gap:

- Base Title Save: 94.231 ms wall, append interval 76.901 ms, bracketed cgroup CPU
  17.757 ms, zero reported quota throttling.
- Task-growth Title Save: 230.358 ms wall, append interval 0.328 ms, bracketed
  cgroup CPU 29.055 ms, zero reported quota throttling.

Counters bracket rather than partition action time; do not subtract them as
exclusive causes. The samples show that slow tails are not uniformly inside the
append interval. They do not isolate filesystem service, scheduler delay, GC or
another cause. No further performance rerun, threshold adjustment or gate-policy
change is requested or performed. The prior e23 hosted failures and supplied
Farnsworth 0/0, 0/1, 0/0 series remain separately attributed and retained.

## Actual Linux fault captured

The [failure receipt](utf8-size-guards-linux-close.json) and
[original sanitized stack](utf8-size-guards-linux-close-stack.txt) come from the
failing full CI execution, after normal owned-window WM_DELETE. The first fresh
launch reached readiness at 1,732 ms and then exited -11 after a 2,781.761 ms
normal-close interval. Warm startup and subsequent native Linux cases were not
executed. A successful unit/build stage does not replace those gates.

The corrected postmortem collector ran only after the fault. It captured a
SIGSEGV stack; no app relaunch, debugger before fault or raw-core upload. The
sparse core's logical size was 803,553,280 bytes and allocated data 232,001,536
bytes, inside the unchanged 512 MiB allocation bound. Only a labelled 64 KiB
prefix was hashed; it is not a full-core digest. Cloud received sanitized stack
text and the test-only bundle, not the raw core.

Faulting thread: LLVM EVT/SelectionDAG/MCJIT code generation, called through
Gallium 25.2.8 and Flutter. Main process thread: code in LLVM within process exit
handlers. This is concrete evidence that graphics compilation is still active
during process exit. It locates the failure; it does not prove which component
owns the root cause or clear the application lifecycle.

## Separate lifecycle review before further edits

The pinned official Flutter source at
`6a19cca56475dbfba1478ee68d7bd0c2ef891da1` was inspected locally; no SDK change:

- [FlView delete event](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/shell/platform/linux/fl_view.cc#L95)
  requests app exit and consumes the native delete event.
- [Platform quit](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/shell/platform/linux/fl_platform_handler.cc#L94)
  detaches windows from GtkApplication and calls `g_application_quit`.
- [View disposal](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/shell/platform/linux/fl_view.cc#L506)
  releases the engine; [engine disposal](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/shell/platform/linux/fl_engine.cc#L590)
  calls embedder Shutdown.

The current runner's shutdown callback does not explicitly destroy its view or
window. Hypothesis: the detached window/view remains alive, allowing renderer
work to overlap process-exit LLVM teardown. Actual object-disposal order has not
been instrumented, so this remains a hypothesis despite the concurrent stacks.

A separate next scoped proof would observe window/view/engine disposal before
main returns under the original immediate-normal-close harness. If confirmed,
a minimal runner repair could keep a weak reference to its own window and
destroy it during GApplication shutdown, after Dart has accepted exit and drained
private queues/native owners. It must not destroy the window during a canceled
exit or bypass rejected Save, continued typing, dirty-editor decisions, peer/tail
or durability guarantees. Verify actual engine disposal and bounded normal exit,
not just a clean sample; retain all crash evidence and cancellations.

**No lifecycle patch or new diagnostic run has been made.** This changes a
native lifecycle beyond the latest UTF8-only equivalence scope, so it is held at
the requested review point. No force exit, sleep, graphics-backend substitution,
dependency upgrade, SDK fork or security setting change is proposed as a silent
workaround. No release, live data change or performance-budget loosening follows.
