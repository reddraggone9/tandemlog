# UX improvements — 2026-10-26

Status: local development implementation, not released or native-accepted.

## Accepted scope

Lee requested six concrete refinements: next-24-hour timed tasks in Today;
completed chronology/date display; carried Search/Add text; Food long-press
selection; deleted Food editing without restoration; month/year calendar jumps.
The improvements note's unspecified Food logging, games and tentative menu
redesign are not implemented. Agent read/write access remains a separate proposed
architecture, not a product endpoint.

Current behavior is specified in [product behavior](product-behavior.md).
ADR0016's former explicit-clearing choice is replaced by Lee's newer request.

## Implementation boundaries

- Today is derived grouping only. Tomorrow's untimed tasks stay tomorrow;
  timed effective dates enter Today at their real instant minus24hours. Resolve
  original zone-aware date/time before comparing, preserving DST folds. If a
  sorting bound changed the day, use that effective viewer-local wall time.
  Distant tasks schedule their own future grouping boundary; no unrelated activity
  is required. Date/manual ordering buckets do not change. Tomorrow rows inside
  Today retain their actual Due/occurrence date, avoiding an apparent today deadline.
- Completed displays its recorded civil date, not the scheduled due date. Reverse
  date order uses the selected surviving completion's canonical clock/writer/
  sequence for same-date ties, without pretending that clock is actual completion
  wall time. Reopen/Undo selects surviving effects. Chronological rows do not drag.
- `completionOrder` is additive disposable projection metadata, not a canonical
  record field. Task cache witness generation4 and projection digest domainv3
  invalidate pre-metadata clean-cache reuse; canonical logs/schema are unchanged.
  An old disposable cache rebuilds through existing admission, without history
  mutation or local-profile schema reset.
- Search queries are explicitly inactive in Add. The outgoing TextEditingValue
  replaces the destination only after existing dirty-editor/pending-save guards.
  Native desktop focus does not select all over the carried selection; both
  inputs retain the outgoing selection when focused after a toggle. A toggle
  neither submits nor writes a task.
- Food selection starts with exact observed physical IDs and existing group/
  workspace guard. Deleted editing uses ordinary details actions, retaining exact
  observed deletion references in the editor freshness guard. Restore stays separate.
- Shared date entry composes public Material CalendarDatePicker, YearPicker and
  InputDatePickerFormField. DatePickerDialog does not expose its pending date;
  keeping it would reset a user's newly selected day on month jump. The app-owned
  dialog preserves that tentative date and manual-input validation, without an SDK
  fork. A month jump clamps the current day, and only OK changes the caller's draft.
  The supported range includes all of1900–9999, not just January1 of9999.
  Existing measured day-cell geometry remains readable at320dp/enlarged text.
  At narrow widths and enlarged text, the editable date format hint may wrap
  over two lines instead of hiding its final day digits behind an ellipsis. The
  calendar target, editable value and controller/focus ownership stay unchanged.
  Native GTK exposed the clipping; the real-font regression fails before this fix.
  Compact English month labels match the current English app; full localized
  month/year labels are supplied to semantics. No new package or SDK fork.

## Development evidence

All fixtures are synthetic. No household workspace, migration or release was used.
Pinned Flutter3.47.5/Dart3.13.4 and the package cache were recovered from the
previous worker's task-local reflink copies; no shared source SDK was modified. Existing native text library from reference034a57d
has SHA256 `d33124d01cbcc7be76e6bbf421362c44d3d2b8e7f5ce1a1fc5b9ddcd9dd1ad83`.
The `native/text_engine` source diff from034a57d to096f79b is empty. This library
was used for real native-text-backed synthetic host/cache/Undo tests, not a claim
of exact candidate native UI/performance acceptance.

Focused coverage includes:

- `task_chronology_view_test`: rolling horizon, untimed tomorrow, completed search/
  filter ordering, surviving completion metadata after selective Undo, distant
  clock boundaries, sorting bounds, viewer zones and DST folds.
- `task_chronology_host_test`: actual app renders Today and completion date in
  search rather than2099 Due; synthetic native-text-backed host.
- `task_input_carry_host_test`: actual Search/Add toggle preserves current text,
  disables hidden filtering, preserves multiline selection, handles same-mode
  Ctrl+F/clear, and does not resurrect submitted capture text. Toggling itself
  leaves canonical bytes unchanged.
- `food_selection_deleted_edit_test`: grouped/one-row long-press, busy/pending and
  pointer-down/recognition races, deleted Save and incoming-Restore refusal.
- `food_store_undo_test`: deleted details Save/Undo/reopen retains exact tombstones.
- `fast_month_picker_test`: month/year jump, pending-day preservation, manual input,
  upper range, leap-day clamp and cancel at320dp1x/2x in dark/light.
- Existing Task view, Food bulk/search/context, Task cache, recurrence Undo,
  projection atomicity and calendar geometry tests.

Faithful action coverage and the unchanged below100ms ordinary-action objective
are recorded in `tool/performance/coverage-v1.json`. No reference benchmark or
budget change was made for this batch.

Widget raster captures cover dark320dp calendar/month grid at1x/2x, Food
selection/deleted editor and synthetic app Today/completed-search views. These
are widget-test evidence, not native desktop/Android demos. Exact-source OS
runtime checks, touch/IME/keyboard acceptance, native desktop/Android videos and
candidate performance qualification remain pending; no platform claim is inferred
from widget width. Private capture/log locations are in the Vex implementation
checkpoint rather than copied into public app artifacts.

## Review and acceptance boundaries

A separate read-only review identified distant-clock refresh, clamped-time,
pending-day and upper-range defects. All four have focused regressions and fixes.
Cache witness probes and their real native-exit/reopen test now follow generation4;
a previous-generation synthetic cache rebuilds without canonical mutation.

The final widget captures were visually inspected at320×640,1x/2x,dark/light.
Day numbers and month targets fit, actions remain reachable, and the revised picker
keeps one compact Month/year control. Material's month-navigation title ellipsizes
at2x while its full date semantics and the explicit jump remain available; this is
an observed display limit, not a claim of native acceptance. Wide800×600 synthetic
Food and Tasks captures show unchanged row density, selection, deleted editor,
Today and completed-date metadata. See ADR0034 for the bounded design rationale.

Native Linux build was attempted but this execution host lacks CMake/Ninja/Xvfb.
Android artifact acquisition failed TLS certificate validation before a native
build could run; no exact-source Android runtime/demo was produced. Desktop and
Android demonstrations remain blocked here. The
pinned Rust1.99.0 gate cannot execute because rustup is absent (system Cargo1.99.1
is not a substitute). These checks remain blocked, with retained attempt logs.
Full unit/host, format, analyzer, Python tooling/native contracts are recorded in
the private implementation report. Exact-source controlled performance qualification
and native UI input-to-paint timings remain pending with existing budgets intact.
No push, release, live profile or household history was used.

## Final development checks —2026-10-26

- Full Flutter unit/host suite:1556passed,0failed.
- Final independent-review regression subset:97passed,0failed.
- Final Food gesture/shared-picker subset:15passed,0failed.
- Python repository tooling:207total,205passed,0failed,2skipped.
- Python native admission/worker contracts:107passed,0failed,using the verified
  unchanged-source production library described above.
- Whole-tree Dart formatting:406files,0changes;Flutter analyzer:0issues;
  Git whitespace check passed. Production native ABI verification passed.
- Initial full-suite attempt retained1543passes/4failures:two subprocess PATH
  setup failures and two stale exact range/witness expectations. These were fixed,
  not skipped; the final full rerun above passes all cases.

These are development checks, not native OS/input/IME demonstrations or fresh
controlled performance qualification. No acceptance limit, canonical fixture or
release gate was changed. Exact commands and private log paths are in Vex's dated
implementation report, outside the public product source.
