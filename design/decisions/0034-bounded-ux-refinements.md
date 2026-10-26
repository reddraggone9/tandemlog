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
  YearPicker and InputDatePickerFormField. DatePickerDialog's pending selection is
  private, so an outer month jump cannot reliably preserve the selected day.
  Reject SDK forks, private-state traversal, shadow selection and dependencies.
- Display recorded civil completion dates and reverse surviving completion order.
  Do not fabricate precise completion timestamps from causal clocks. Invalidate
  disposable projection witnesses for additive completion-order metadata; canonical
  bytes and protocol meaning stay unchanged.
- Today changes derived grouping only. Preserve original pinned instants through
  DST folds; if a sort bound changed the day, resolve that effective local value.
  Schedule future grouping boundaries without relying on another task or input.

## Consequences and validation

The shared picker benefits Task and Food inputs while leaving draft-owner lifetime,
manual entry, cancellation and confirmation intact. Compact month labels follow
the current English app; full localized month/year semantics remain available.
Existing day-cell measurements, both themes and enlarged text remain covered.
The dialog adds app-owned layout, not a duplicate calendar/date-validation engine.

[Implementation evidence](../ux-improvements-20261026.md) records independent
review corrections, replay/cache/Undo checks, visual observations and platform
gaps. Existing performance budgets and candidate/native gates are not waived.
No agent endpoint, menu redesign, schema migration or broad Food/game module is
introduced. Exact actual completion-time capture would need separate semantics.

## Revisit trigger

Owner: Tandemlog maintainers. Revisit the small calendar layout at the next native
candidate acceptance or when app localization expands; resolve any demonstrated
accessibility/input/paint defect without weakening geometry or latency checks.
Actual completion timestamps remain a separate future decision if requested.
