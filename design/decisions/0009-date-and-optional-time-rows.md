# 0009 — Separate Start/Due date and time controls

Status: approved presentation revision for the next preview, 2026-10-04.
Native visual/release acceptance are separate gates. Published build43 keeps its
original Add time behavior; build44 supersedes that presentation.

Lee requested Start and Due rows with a wider date and smaller independent time.
After reviewing build43, he approved an always-visible blank input labeled
**Time**, replacing Add time. The existing X clears a set time and retains the
date; the blank input remains available. No optional suffix is needed: most
editor fields are optional, and clearing makes the interaction discoverable.
This avoids an extra activation click and keeps the controls stable.

Date/time retain separate controllers, contextual Start/Due accessibility labels,
keyboard editing and the existing date picker. Rows stack when available width
or enlarged text cannot comfortably fit both. Bulk mixed values retain their
independent apply controls. Focusing a blank time does not change date-only
precision; explicit midnight stays different from no time.

Tags and Assignee follow all scheduling content immediately before actions,
in single and bulk editors. Lee edits title/notes/dates more frequently. Reading
and keyboard order follow the visual order: Start, Due, Repeat, Timezone, sort
bounds, then tags/assignee, with existing conditional occurrence controls in
context. These moves preserve field keys/controllers, drafts and semantics.

This changes presentation only. Validation, recurrence/occurrence overrides,
precision, zones, canonical logs and draft guards follow
[product behavior](../product-behavior.md). No protocol or durable-data change.

Rejected alternatives: combined timestamp obscures precision; four full-width
controls consume unnecessary space; Add time reduces emptiness but adds an
unwanted click; a new time-picker workflow exceeds this bounded revision.

Revisit after native use if time entry/clearing, touch targets or enlarged text
make separate controls awkward. Tests cover blank focus/clean Cancel, explicit
midnight, zone retention, clear without losing date, row proportions, 390px fit,
320px/200% stacking and single/bulk field order. Every UI revision still needs
actual native desktop inspection and exact Android affected-workflow acceptance.

An [isolated follow-up investigation](../date-time-layout-investigation.md)
measures populated fields before tightening enlarged-text stacking. It remains
a separately reviewed presentation candidate; its native evidence does not
promote Android or release acceptance.
