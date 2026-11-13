# Task editor at large text

## UX brief (2026-11-13)
The editor answers: what is this task, and should I save my edits? Keep the existing field order and controls; add no explanations or new actions. Title wraps visually (stored title stays a single line) and grows up to six visual lines, then scrolls inside the field. Reuse the existing outline padding. At narrow effective widths, put Delete and Cancel in an intentional secondary row, followed by full-width Save changes. When all actions fit, retain Delete left and Cancel/Save right. This also applies to the narrow pane in a wide window. Next action is Save, Cancel, or Delete without ambiguous stacking.

UX principles: 11 consistent gaps, 14 size to content, 16 unchanged single-line date/time fields (Title already wraps), 21 width-based layout, 23 direct actions. No domain/storage changes. Native evidence and independent review recorded below.

## Native review

Final source e456dfe: Linux GTK widget-driven captures, 390px dark/light
200%, 1000px dark/light 200%, and 390px dark 100%. The title now shows the
whole three-line fixture. Actions use deliberate Delete/Cancel then full-width
Save at 200%, including the side pane; 100% retains the original single row.
Scrolled-bottom captures confirm Assignee and all actions remain reachable.
Builder visually inspected top/actions dark 390 and 1000 at 200%, light 390
and 1000 at 200%, and normal-text 390. Independent screenshot-only final
review found both target defects fixed and no regressions. Native capture
suite: five variants passed. No storage/domain behavior or new action path.

Evidence: Vex vault `artifacts/tandemlog-startup-20261113/{before,after}/`,
plus `before-after-title.png` and `before-after-actions.png` (Before left,
After right, Linux GTK 390px dark 200%).

Unchanged, pre-existing observations (outside this bounded fix): Time inset
is tighter than date inset at 200%; Material's dialog padding shrinks at large
text; fields are clipped at the scroll viewport edge above the pinned footer;
filled-button labels have tight vertical padding at 200% (the existing
app-wide large-text sizing follow-up). Not release acceptance on Android or
Windows. Keyboard/persistence semantics retain existing unit-suite coverage;
the capture workflow itself opens, scrolls and cancels a synthetic draft.
