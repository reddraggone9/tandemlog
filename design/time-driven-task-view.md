# Time-driven task views — implementation plan

Status: renderer implementation and private actual-renderer comparison pass; exact final native Android acceptance remains required. Build 9 is diagnostic only and must not be published as workflow parity. The prior private rehearsal proved parsed-field reconstruction and recurrence behavior, not the complete adjacent Markdown renderer's semantics. Tags such as `#due-min` and `#due-max` carry behavior beyond opaque tag membership. They now map to typed sorting bounds under the audited rules in product behavior; prior opaque-tag rehearsals are superseded.

## Original gap (corrected)

The pre-correction `TasksPage` filtered by completion and assignee, using stored manual order. It displays schedule metadata but does not implement start-based availability or effective-due sorting. `didChangeAppLifecycleState` requests folder ingestion on resume; unchanged logs do not cause a view rebuild. Therefore neither foreground folder polling nor an unrelated edit is a valid time-refresh mechanism.

## Implemented boundary

Keep persisted task facts and event clocks separate from derived view time. A pure task-view calculation receives projected tasks, one current instant, current local-zone context, and the renderer-backed view policy. It returns visible ordered rows/counts and the earliest future instant at which that result can change. Effective due bounds belong in functional domain fields; do not persist a constantly moving derived date or emit events when time passes. Retain manual order as a deterministic tie-break or explicit ordering mode only as supported by the audited workflow.

A small foreground controller owns one cancellable timer for the earliest boundary. Recompute from the actual clock when it fires, not by adding a fixed duration to a cached time. Reschedule after data/user/filter/workspace changes. Pause timers while suspended; immediately recompute and rearm on resume/focus. Dispose old timers and ignore stale callbacks after workspace replacement. View refresh must preserve capture text, editor controllers, focus and selection and must not write logs or reread SQLite merely because time elapsed.

System clock and zone changes also invalidate the derived view immediately through platform signals where available. Verify native notification delivery on each target; Flutter lifecycle callbacks alone do not promise such delivery while the window remains open. A bounded foreground watchdog can detect missed wall-clock/offset changes using wall time versus monotonic elapsed time, but is a fallback with a documented maximum delay, not a claim of immediate delivery. Use a single low-frequency wake-up (proposed ceiling: once per minute) combined with exact boundary timers; no background service or frequent full-data polling. The final adapter design must cover the explicit immediate-change requirement, including a local-zone identity change that currently shares the same UTC offset.

Compute midnight using the relevant civil calendar/zone, never by assuming every day lasts 24 hours. Reuse the established pinned-zone gap/fold policy. Floating schedules follow the current local zone; pinned schedules retain their own zone. Event ordering clocks remain the approved wall-clock causal scalar and are unaffected by view invalidation.

## Required tests before readiness

- Fake clock/scheduler: immediately before, exactly at and after a start instant; date-only midnight; delayed timer firing and several boundaries crossed during suspension.
- Pure view: effective-due bound transitions and sorting/count changes based on the audited renderer; stable ties; no persisted mutation. Use the audited scheduled-first/min/max/Someday examples and independent private renderer comparison.
- Backward/forward wall-clock jumps, local-zone changes including equal-current-offset zones, pinned-zone independence, DST gap/fold and 23/25-hour days.
- Lifecycle: resume recomputes before any import finishes; data/folder changes cancel obsolete timers; dispose cannot update state; no overlapping work or zero-delay loops.
- Widget: leave the app open across a boundary without edits/imports and observe visibility/order/count update; preserve a partially typed capture and an open editor. Completed history behavior follows the agreed view policy.
- Native desktop and Android: actual boundary, background/resume and platform time/zone notification behavior, then refreshed feature demos. A fake-clock unit test is not evidence of native notification delivery.

No final import or source edits are authorized by this plan. Markdown remains authoritative, and the private serializer must be revalidated for newly discovered functional fields after the renderer audit.

## Implemented infrastructure checkpoint

`domain/timed_view.dart` defines the pure projection contract: one instant and explicit local-zone identity/offset in, view value and optional strictly-future boundary out. `presentation/view_clock.dart` implements a single cancellable foreground timer, exact boundary wakes, immediate explicit invalidation/start, monotonic-versus-wall-clock jump detection, and a one-minute watchdog. Ordinary watchdog wakes do not rerun projection. Generation checks ignore cancelled callbacks; callback-triggered disposal cannot rearm the timer. The controller has no database, event writer, widget, or editor dependency.

Eight injected-clock tests cover exact boundaries, idle watchdogs, suspension/resume, forward/backward clock changes, same-offset zone identity changes, delayed callbacks, input changes, teardown, invalid boundaries, and 23/25-hour calendar days. These are infrastructure tests, not proof of task policy, actual draft preservation in widgets, or native platform notification delivery. The subsequent task-view integration implements the audited policy. Native Linux idle-boundary tests also preserve active drafts and leave canonical logs unchanged; actual OS notification delivery remains separately scoped.

## Native adapter implementation and remaining evidence

Android observes foreground protected time/timezone broadcasts without a new service or permission. Linux watches the parent of the local-zone files (including atomic replacement) and uses `CLOCK_REALTIME` timerfd cancellation for discontinuous clock changes. Windows observes top-level time/settings messages and maps its zone identity through the system ICU library. Adapters compare current native offset with the selected IANA rules; unsupported mapping/configuration fails explicitly. Unchanged fallback checks do not rebuild the task view, and stale asynchronous observations cannot replace newer zone information.

These implementations follow [Android time broadcasts](https://developer.android.com/reference/android/content/Intent#ACTION_TIME_CHANGED), [Linux timerfd cancellation](https://man7.org/linux/man-pages/man2/timerfd_create.2.html), [Windows time messages](https://learn.microsoft.com/en-us/windows/win32/sysinfo/wm-timechange), and [Windows ICU support](https://learn.microsoft.com/en-us/windows/win32/intl/international-components-for-unicode--icu-). A bounded watchdog covers missed signals; small continuous clock slews are not described as native cancellation events.

Injected adapter tests and Linux compilation are narrower evidence than actual system time/zone changes. Native target validation must distinguish real idle boundaries, lifecycle events, synthetic notification injection, and changing OS settings. Do not mutate a shared host clock merely to manufacture test coverage. Windows native runtime and Android device/emulator delivery remain pending.
