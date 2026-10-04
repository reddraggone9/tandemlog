# 0009 — Start and Due with separate optional time

Status: layout approved by Lee for the next preview, 2026-10-04. Implemented
locally; native visual inspection and release acceptance remain separate gates.

The editor previously gave Start date, Start time, Due date and Due time four
full-width fields even when times were absent. Lee requested one Start row and
one Due row, with a wider date control and smaller independent optional time.

Empty time uses a compact **Add time** button. It opens and focuses the existing
time text input without inventing a value. A set time has a clear control that
returns to Add time while retaining the date. Date and time retain separate
controllers and keyboard editing; the existing calendar picker stays attached
to the date. Rows stack when available width or enlarged text cannot comfortably
fit both controls. Bulk mixed values retain their independent apply controls.

This changes presentation only. Date precision, explicit midnight, time zone,
coupled validation, recurrence and occurrence overrides follow
[product behavior](../product-behavior.md); canonical logs and draft guards are
unchanged. Activating Add time alone does not dirty the stored schedule.

Rejected alternatives: a combined timestamp control would obscure date-only
precision; four persistent full-width inputs would retain the unnecessary empty
time space; a new time-picker workflow exceeds this bounded layout change.

Revisit after native desktop and Android use if time entry, clearing, touch
targets or enlarged text make the separate controls awkward. Widget tests cover
row proportions, 390px fit, narrow/200% stacking, focus on Add time, midnight
entry and clearing without losing the date. The reference Library image could
not be downloaded, so implementation follows Lee's explicit layout description.
