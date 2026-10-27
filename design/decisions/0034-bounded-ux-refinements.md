# ADR0034 — bounded input, calendar and history refinements

Status: Lee-requested scope accepted2026-10-26; implemented locally, not released
or native/performance accepted. Supersedes ADR0016's outgoing-text clearing rule.

## Context and decision

[Product behavior](../product-behavior.md) owns the accepted behavior. This batch
addresses typed text lost by Search/Add, Food selection discovery, reusable deleted
Food templates, distant calendar navigation and misleading completed chronology.
The confirmed next24h Today rule includes timed tomorrow values, not untimed ones.

- Carry the actual TextEditingValue only after existing navigation/readiness
  guards. Pause Search in Add. Successful capture still clears the active value.
  Separate retained mode drafts would resurrect stale text and miss the goal.
- Reuse physical Food IDs, details field masks, receipts and selective Undo.
  Long-press is selection-only; deleted editing never emits Restore/Delete.
  A Restore arriving while a draft is open invalidates its observed deletion context.
- Use a small app-owned dialog composing public Material CalendarDatePicker,
  InputDatePickerFormField and a small app-owned year grid. Native200% review found the SDK YearPicker initial offset assumed three columns while rendering two, opening decades before the selected year; owned public GridView/ScrollController geometry fixes that without private SDK traversal. DatePickerDialog's pending selection is
  private, so an outer month jump cannot reliably preserve the selected day.
  Reject SDK forks, private-state traversal, shadow selection and dependencies.
- Completion-date presentation was the initial bounded implementation. Lee's
  subsequent exact-instant/viewer-local decision is implemented in [ADR0035](0035-exact-completion-instants.md).
- Today changes derived grouping only. Preserve original pinned instants through
  DST folds; if a sort bound changed the day, resolve that effective local value.
  Schedule future grouping boundaries without relying on another task or input.

## Consequences and validation

The shared picker benefits Task and Food inputs while leaving draft-owner lifetime,
manual entry, cancellation and confirmation intact. Compact month labels follow
the current English app; full localized month/year semantics remain available.
Existing day-cell measurements, both themes and enlarged text remain covered.
The dialog swaps its calendar body for the month/year grid in place; it never stacks a second dialog. Back or Escape returns to the day calendar before closing. The dialog adds app-owned layout, not a duplicate calendar/date-validation engine.

[Implementation evidence](../ux-improvements-20261026.md) records independent
review corrections, replay/cache/Undo checks, visual observations and platform
gaps. Existing performance budgets and candidate/native gates are not waived.
No agent endpoint, menu redesign, schema migration or broad Food/game module is
introduced. Exact completion-time capture follows ADR0035.

## Revisit trigger

Owner: Tandemlog maintainers. Revisit the small calendar layout at the next native
candidate acceptance or when app localization expands; resolve any demonstrated
accessibility/input/paint defect without weakening geometry or latency checks.
Completion timestamp semantics now follow ADR0035.
