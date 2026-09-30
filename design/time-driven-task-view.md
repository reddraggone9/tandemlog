# Time-driven task views — implementation plan

Status: release blocker identified by owner feedback; renderer audit pending. Build 9 is diagnostic only and must not be published as workflow parity. The prior private rehearsal proved parsed-field reconstruction and recurrence behavior, not the complete adjacent Markdown renderer's semantics. Tags such as `#due-min` and `#due-max` carry behavior beyond opaque tag membership. Preserve them unchanged until their actual meaning is audited; do not invent a bound schema.

## Current gap

`TasksPage` currently filters by completion and assignee, using stored manual order. It displays schedule metadata but does not implement start-based availability or effective-due sorting. `didChangeAppLifecycleState` requests folder ingestion on resume; unchanged logs do not cause a view rebuild. Therefore neither foreground folder polling nor an unrelated edit is a valid time-refresh mechanism.

## Proposed boundary

Keep persisted task facts and event clocks separate from derived view time. A pure task-view calculation receives projected tasks, one current instant, current local-zone context, and the renderer-backed view policy. It returns visible ordered rows/counts and the earliest future instant at which that result can change. Effective due bounds belong in functional domain fields once their meaning is established; do not persist a constantly moving derived date or emit events when time passes. Retain manual order as a deterministic tie-break or explicit ordering mode only as supported by the audited workflow.

A small foreground controller owns one cancellable timer for the earliest boundary. Recompute from the actual clock when it fires, not by adding a fixed duration to a cached time. Reschedule after data/user/filter/workspace changes. Pause timers while suspended; immediately recompute and rearm on resume/focus. Dispose old timers and ignore stale callbacks after workspace replacement. View refresh must preserve capture text, editor controllers, focus and selection and must not write logs or reread SQLite merely because time elapsed.

System clock and zone changes also invalidate the derived view immediately through platform signals where available. Verify native notification delivery on each target; Flutter lifecycle callbacks alone do not promise such delivery while the window remains open. A bounded foreground watchdog can detect missed wall-clock/offset changes using wall time versus monotonic elapsed time, but is a fallback with a documented maximum delay, not a claim of immediate delivery. Use a single low-frequency wake-up (proposed ceiling: once per minute) combined with exact boundary timers; no background service or frequent full-data polling. The final adapter design must cover the explicit immediate-change requirement, including a local-zone identity change that currently shares the same UTC offset.

Compute midnight using the relevant civil calendar/zone, never by assuming every day lasts 24 hours. Reuse the established pinned-zone gap/fold policy. Floating schedules follow the current local zone; pinned schedules retain their own zone. Event ordering clocks remain the approved wall-clock causal scalar and are unaffected by view invalidation.

## Required tests before readiness

- Fake clock/scheduler: immediately before, exactly at and after a start instant; date-only midnight; delayed timer firing and several boundaries crossed during suspension.
- Pure view: effective-due bound transitions and sorting/count changes based on the audited renderer; stable ties; no persisted mutation. Do not write speculative expected bound results before the audit.
- Backward/forward wall-clock jumps, local-zone changes including equal-current-offset zones, pinned-zone independence, DST gap/fold and 23/25-hour days.
- Lifecycle: resume recomputes before any import finishes; data/folder changes cancel obsolete timers; dispose cannot update state; no overlapping work or zero-delay loops.
- Widget: leave the app open across a boundary without edits/imports and observe visibility/order/count update; preserve a partially typed capture and an open editor. Completed history behavior follows the agreed view policy.
- Native desktop and Android: actual boundary, background/resume and platform time/zone notification behavior, then refreshed feature demos. A fake-clock unit test is not evidence of native notification delivery.

No final import or source edits are authorized by this plan. Markdown remains authoritative, and the private serializer must be revalidated for newly discovered functional fields after the renderer audit.
